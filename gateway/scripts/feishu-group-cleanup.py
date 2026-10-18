#!/usr/bin/env python3
"""飞书同名群去重：解散除保留目标以外的同名群。

用法：
  python3 scripts/feishu-group-cleanup.py                # 干跑：列出所有群与候选
  python3 scripts/feishu-group-cleanup.py --apply        # 真正解散
  python3 scripts/feishu-group-cleanup.py --name "Hermes AI 助手群" --apply
  python3 scripts/feishu-group-cleanup.py --keep oc_xxx --apply   # 显式指定保留哪个

保留规则（按优先级）：--keep > FEISHU_PUSH_CHAT_ID > 名单里第一个
安全约束：**只删同名群**；每个群都会打印 user_count，**若待删群有真人成员则默认跳过**（用 --force 才删）。
权限要求：应用需 im:chat（或 im:chat:delete）；缺失时脚本会打印开通链接。
"""
import argparse, json, os, pathlib, re, sys, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
API = 'https://open.feishu.cn/open-apis'


def env() -> dict:
    e = dict(os.environ)
    for f in [ROOT/'config/.env', ROOT/'data/hermes/.env', ROOT/'.env']:
        if not f.exists():
            continue
        for line in f.read_text(encoding='utf-8', errors='ignore').split('\n'):
            m = re.match(r'^\s*([A-Z][A-Z0-9_]+)\s*=\s*(.*?)\s*$', line.replace('\r', ''))
            if m and m.group(1) not in e:
                e[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return e


def call(url: str, token: str, method='GET', payload=None) -> dict:
    data = json.dumps(payload).encode() if payload else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={'Authorization': f'Bearer {token}',
                                          'Content-Type': 'application/json; charset=utf-8'})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as ex:
        return json.loads(ex.read().decode())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--name', default='Hermes AI 助手群')
    ap.add_argument('--keep')
    ap.add_argument('--force', action='store_true', help='即使群里有真人成员也删')
    a = ap.parse_args()

    e = env()
    for k in ('FEISHU_APP_ID', 'FEISHU_APP_SECRET'):
        if not e.get(k):
            print(f'缺少 {k}', file=sys.stderr); return 1
    tok = call(f'{API}/auth/v3/tenant_access_token/internal', '', 'POST',
               {'app_id': e['FEISHU_APP_ID'], 'app_secret': e['FEISHU_APP_SECRET']})
    if tok.get('code') != 0:
        print('取 token 失败:', tok.get('msg'), file=sys.stderr); return 1
    tok = tok['tenant_access_token']

    lst = call(f'{API}/im/v1/chats?page_size=100', tok)
    if lst.get('code') != 0:
        print('列群失败:', lst.get('code'), lst.get('msg'), file=sys.stderr); return 1
    chats = (lst.get('data') or {}).get('items') or []
    print(f'机器人所在群共 {len(chats)} 个：')
    for c in chats:
        d = call(f"{API}/im/v1/chats/{c['chat_id']}", tok).get('data') or {}
        c['user_count'] = int(d.get('user_count') or 0); c['bot_count'] = int(d.get('bot_count') or 0)
        print(f"  {c['chat_id']}  「{c.get('name')}」  真人={c['user_count']} 机器人={c['bot_count']}")

    same = [c for c in chats if (c.get('name') or '') == a.name]
    if len(same) <= 1:
        print(f'\n同名「{a.name}」只有 {len(same)} 个，无需去重。'); return 0
    keep = a.keep or e.get('FEISHU_PUSH_CHAT_ID') or same[0]['chat_id']
    print(f'\n同名群 {len(same)} 个；保留 = {keep}')
    rc = 0
    for c in same:
        cid = c['chat_id']
        if cid == keep:
            print(f'  跳过（保留）：{cid}'); continue
        if int(c.get('user_count') or 0) > 0 and not a.force:
            print(f"  跳过（有 {c.get('user_count')} 个真人成员，需 --force）：{cid}"); continue
        if not a.apply:
            print(f'  [干跑] 将解散：{cid} 「{c.get("name")}」'); continue
        r = call(f"{API}/im/v1/chats/{cid}", tok, 'DELETE')
        if r.get('code') == 0:
            print(f'  ✓ 已解散：{cid}')
        else:
            print(f'  ✗ 解散失败：{cid} → code={r.get("code")} {str(r.get("msg"))[:120]}')
            if r.get('code') in (99991672, 99991679):
                print('     → 应用缺权限，去开 im:chat / im:chat:delete 后发布版本：'
                      f"https://open.feishu.cn/app/{e['FEISHU_APP_ID']}/auth?q=im:chat,im:chat:delete")
            rc = 2
    return rc


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""飞书消息推送 —— 把内容/热点/日报推送到飞书群或用户。

用法：
  # 纯文本
  python3 scripts/feishu-push.py --text "构建完成：3 个服务已重启"

  # 结构化卡片（标题 + Markdown 正文 + 可选跳转按钮）
  python3 scripts/feishu-push.py --title "今日知识库" --text "**入库** 12 篇\n**新增** 3 页" --link "https://example.com|查看"

  # 从 Markdown 文件推（首个 # 标题作为卡片标题）
  python3 scripts/feishu-push.py --file /workspace/digest.md

  # 指定目标（默认取 env FEISHU_PUSH_CHAT_ID）；oc_ 开头＝群，ou_ 开头＝用户
  python3 scripts/feishu-push.py --to oc_xxxx --file digest.md

  # 只打印将要发送的 JSON，不真发
  python3 scripts/feishu-push.py --title T --text B --dry-run

凭据来源（按序）：环境变量 → config/.env → data/hermes/.env
  必填 FEISHU_APP_ID / FEISHU_APP_SECRET；目标 FEISHU_PUSH_CHAT_ID（可被 --to 覆盖）
退出码：0 成功；1 参数/凭据错误；2 飞书接口报错。
"""
import argparse, json, os, pathlib, re, sys, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENV_FILES = [ROOT / 'config/.env', ROOT / 'data/hermes/.env', ROOT / '.env']
API = 'https://open.feishu.cn/open-apis'


def load_env() -> dict:
    """环境变量优先；缺失的键从 .env 补（去掉行内注释与引号）。"""
    env = dict(os.environ)
    for f in ENV_FILES:
        if not f.exists():
            continue
        for line in f.read_text(encoding='utf-8', errors='ignore').split('\n'):
            m = re.match(r'^\s*([A-Z][A-Z0-9_]+)\s*=\s*(.*?)\s*$', line.replace('\r', ''))
            if m and m.group(1) not in env:
                env[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return env


def post(url: str, payload: dict, token: str | None = None) -> dict:
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), method='POST',
                                 headers={'Content-Type': 'application/json; charset=utf-8'})
    if token:
        req.add_header('Authorization', f'Bearer {token}')
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())


def tenant_token(env: dict) -> str:
    d = post(f'{API}/auth/v3/tenant_access_token/internal',
             {'app_id': env['FEISHU_APP_ID'], 'app_secret': env['FEISHU_APP_SECRET']})
    if d.get('code') != 0:
        sys.exit(f'[feishu] 取 tenant_access_token 失败：code={d.get("code")} msg={d.get("msg")}')
    return d['tenant_access_token']


def build_card(title: str, body: str, link: str | None) -> dict:
    els = [{'tag': 'div', 'text': {'tag': 'lark_md', 'content': body}}]
    if link:
        url, _, label = link.partition('|')
        els += [{'tag': 'hr'},
                {'tag': 'action', 'actions': [{'tag': 'button', 'text': {'tag': 'plain_text', 'content': label or '查看原文'},
                                               'url': url, 'type': 'primary'}]}]
    return {'config': {'wide_screen_mode': True},
            'header': {'title': {'tag': 'plain_text', 'content': title}, 'template': 'blue'},
            'elements': els}


def main() -> int:
    ap = argparse.ArgumentParser(description='推送消息到飞书')
    ap.add_argument('--text', help='正文（Markdown/lark_md 语法；也可与 --file 二选一）')
    ap.add_argument('--file', help='从文件读正文（首个 # 一级标题作卡片标题）')
    ap.add_argument('--title', default='', help='卡片标题（不填则用文件名或首行）')
    ap.add_argument('--link', help='按钮："URL|文案" 或仅 URL')
    ap.add_argument('--to', help='目标 oc_…(群) / ou_…(用户)；默认 env FEISHU_PUSH_CHAT_ID')
    ap.add_argument('--raw-text', action='store_true', help='发纯文本而非卡片')
    ap.add_argument('--dry-run', action='store_true', help='只打印 payload')
    a = ap.parse_args()

    env = load_env()
    for k in ('FEISHU_APP_ID', 'FEISHU_APP_SECRET'):
        if not env.get(k):
            print(f'[feishu] 缺少 {k}（查 config/.env / data/hermes/.env）', file=sys.stderr)
            return 1

    body = a.text or ''
    title = a.title
    if a.file:
        p = pathlib.Path(a.file)
        if not p.exists():
            print(f'[feishu] 文件不存在：{p}', file=sys.stderr); return 1
        raw = p.read_text(encoding='utf-8', errors='ignore')
        m = re.search(r'^#\s+(.+)$', raw, re.M)
        if m and not title:
            title = m.group(1).strip()
            raw = raw.replace(m.group(0), '', 1)
        body = (body + '\n' + raw).strip()
        title = title or p.stem
    if not body and not a.file:
        print('[feishu] 需要 --text 或 --file', file=sys.stderr); return 1
    title = title or body.split('\n', 1)[0][:60]

    target = a.to or env.get('FEISHU_PUSH_CHAT_ID') or ''
    if not target:
        print('[feishu] 未指定目标：用 --to 或设置 FEISHU_PUSH_CHAT_ID', file=sys.stderr); return 1
    kind = 'chat_id' if target.startswith('oc_') else ('user_id(open_id)' if target.startswith('ou_') else 'open_id?')

    payload = {'receive_id': target,
               'msg_type': 'text' if a.raw_text else 'interactive',
               'content': json.dumps({'text': body} if a.raw_text else build_card(title, body, a.link),
                                     ensure_ascii=False)}
    if a.dry_run:
        print(json.dumps({'target': target, 'kind': kind, 'payload': json.loads(payload['content'] if a.raw_text else json.dumps(build_card(title, body, a.link), ensure_ascii=False))},
                         ensure_ascii=False, indent=1))
        return 0

    tok = tenant_token(env)
    d = post(f'{API}/im/v1/messages?receive_id_type={"chat_id" if target.startswith("oc_") else "open_id"}',
             payload, tok)
    if d.get('code') != 0:
        print(f'[feishu] 发送失败：code={d.get("code")} msg={d.get("msg")}', file=sys.stderr)
        if d.get('code') in (99991672, 99991679):
            print('  → 多为应用缺权限：去 https://open.feishu.cn/app 开通 im:message（发送）后发布版本', file=sys.stderr)
        return 2
    print(f"[feishu] 已发送 → {kind}={target} | message_id={d['data']['message_id']} | 标题=「{title}」")
    return 0


if __name__ == '__main__':
    sys.exit(main())

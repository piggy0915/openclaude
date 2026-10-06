#!/usr/bin/env bash
# 飞书通道自检：token / 机器人身份 / 所在群 / 发送权限
set -uo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp); chmod 600 "$TMP"; trap 'rm -f "$TMP"' EXIT
python3 - "$TMP" <<'PY'
import re, sys, pathlib
out=[]
for f in ['config/.env','data/hermes/.env','.env']:
    p=pathlib.Path(f)
    if not p.exists(): continue
    for l in p.read_text(encoding='utf-8',errors='ignore').split('\n'):
        m=re.match(r'^\s*(FEISHU_[A-Z_]+)\s*=\s*(.*?)\s*$', l.replace('\r',''))
        if m and m.group(1) not in [o.split('=')[0] for o in out]:
            out.append(f'{m.group(1)}={m.group(2).strip().strip(chr(34)).strip(chr(39))}')
pathlib.Path(sys.argv[1]).write_text('\n'.join(out)+'\n',encoding='utf-8')
PY
set -a; . "$TMP"; set +a

echo "[1/4] 凭据"
echo "  FEISHU_APP_ID        = ${FEISHU_APP_ID:0:8}…（长度 ${#FEISHU_APP_ID}）"
echo "  CONNECTION_MODE      = ${FEISHU_CONNECTION_MODE:-（未设）}"
echo "  ALLOWED_USERS 条目数 = $(echo "${FEISHU_ALLOWED_USERS:-}" | tr ',' '\n' | grep -c . )"
echo "  PUSH_CHAT_ID         = ${FEISHU_PUSH_CHAT_ID:-（未设）}"

TOK=$(curl -s -m 20 -X POST 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d "{\"app_id\":\"$FEISHU_APP_ID\",\"app_secret\":\"$FEISHU_APP_SECRET\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('tenant_access_token',''))")
echo "[2/4] tenant_access_token: $([ -n "$TOK" ] && echo "OK（${#TOK} 字符）" || echo "失败")"
[ -z "$TOK" ] && exit 1

echo "[3/4] 机器人身份"
curl -s -m 20 "https://open.feishu.cn/open-apis/bot/v3/info" -H "Authorization: Bearer $TOK" \
 | python3 -c "
import sys,json;d=json.load(sys.stdin);b=d.get('bot') or {}
print('  code=',d.get('code'),'机器人=',b.get('app_name'),'激活状态=',b.get('activate_status'))"

echo "[4/4] 所在群"
curl -s -m 25 "https://open.feishu.cn/open-apis/im/v1/chats?page_size=20" -H "Authorization: Bearer $TOK" \
 | python3 -c "
import sys,json;d=json.load(sys.stdin);items=(d.get('data') or {}).get('items') or []
print('  code=',d.get('code'),'群数=',len(items))
for c in items: print('   ',c.get('chat_id'),'|',(c.get('name') or '')[:30])"

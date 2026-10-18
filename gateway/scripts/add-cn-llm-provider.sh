#!/usr/bin/env bash
# 接入国内 LLM 提供方到 freellmapi（魔搭 ModelScope / 硅基流动 SiliconFlow）
#
# 用法：
#   bash add-cn-llm-provider.sh modelscope   <MODELSCOPE_TOKEN>  [模型id...]
#   bash add-cn-llm-provider.sh siliconflow  <SILICONFLOW_KEY>   [模型id...]
#   bash add-cn-llm-provider.sh verify       [模型id...]      # 只验证，不改配置
#
# 拿 key：
#   魔搭   https://modelscope.cn/  -> 个人中心 -> 访问令牌
#          !!! 必须先「绑定阿里云中国站账号 + 中国实名认证」，否则调用报
#              401 please bind your alibaba cloud account before use
#          !!! 目录里 modelscope 的 11 个模型 supportsTools 全为 false -> 只能纯对话
#   硅基流动 https://cloud.siliconflow.cn/account/ak
#          !!! 需实名；新用户送约 2000 万 token（~14 元）；9B 以下模型永久免费
#
# 为什么必须重启：key 由应用加密存储（encrypted_key/iv/auth_tag），只能由应用自己在
# 启动时从声明式配置写入 —— applyDeclarativeConfigFromEnv() 仅启动时执行一次。
# 这是单容器重启（freellmapi），不涉及 hermes / hermes-webui 成对启停。
set -euo pipefail

ROOT="${ROOT:-/home/user/gateway}"
CFG="$ROOT/data/freellmapi/freellmapi.config.json"
SILICONFLOW_BASE='https://api.siliconflow.cn/v1'

die() { echo "x $*" >&2; exit 1; }
ok()  { echo "v $*"; }

verify() {
  local key rc model
  key=$(grep -m1 '^FREELLMAPI_KEY=' "$ROOT/data/hermes/.env" | cut -d= -f2) || die "读不到 FREELLMAPI_KEY"
  echo "-- 验证 auto 链（应首次即中，无国外超时）--"
  for i in 1 2 3; do
    printf "  auto #%d " "$i"
    curl -s --max-time 60 -X POST http://127.0.0.1:3030/v1/chat/completions \
      -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
      -d '{"model":"auto","messages":[{"role":"user","content":"OK"}],"max_tokens":8}' \
      -D /tmp/.ffv.h -w '[%{http_code} %{time_total}s]' -o /dev/null 2>/dev/null
    grep -i 'x-routed-via' /tmp/.ffv.h | tr -d '\r' | paste -sd' ' | sed 's/^/ /'
    echo
  done
  if [ "$#" -gt 0 ]; then
    echo "-- 逐个模型 --"
    for model in "$@"; do
      printf "  %-42s " "$model"
      rc=$(curl -s --max-time 40 -X POST http://127.0.0.1:3030/v1/chat/completions \
        -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
        -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"说OK\"}],\"max_tokens\":12}" \
        -w '%{http_code}' -o /tmp/.ffv.json 2>/dev/null)
      RC="$rc" python3 - <<'PY'
import json, os
rc = os.environ['RC']
try:
    d = json.load(open('/tmp/.ffv.json'))
    if 'error' in d: print(rc, 'x', str(d['error'].get('message', ''))[:70])
    else:
        v = d.get('_routed_via', {})
        print(rc, 'v 路由=' + str(v.get('platform', '?')) + '/' + str(v.get('model', '?')))
except Exception: print(rc, '?')
PY
    done
  fi
}

PROVIDER="${1:-}"; shift || true
case "$PROVIDER" in
  verify) verify "$@"; exit 0 ;;
  modelscope|siliconflow) ;;
  *) die "用法: $0 {modelscope|siliconflow|verify} <KEY> [模型id...]" ;;
esac

KEY="${1:-}"; shift || true
[ -n "$KEY" ] || die "$PROVIDER 的 key 不能为空"
[ -f "$CFG" ] || die "配置文件不存在: $CFG"

DEFAULT_MODELSCOPE=("ZhipuAI/GLM-4.7-Flash" "deepseek-ai/DeepSeek-V4-Pro" "Qwen/Qwen3.5-397B-A17B")
DEFAULT_SILICONFLOW=("Qwen/Qwen2.5-7B-Instruct" "THUDM/glm-4-9b-chat")
if [ "$#" -gt 0 ]; then MODELS=("$@")
elif [ "$PROVIDER" = modelscope ]; then MODELS=("${DEFAULT_MODELSCOPE[@]}")
else MODELS=("${DEFAULT_SILICONFLOW[@]}"); fi

cp "$CFG" "$CFG.bak-$(date +%Y%m%d-%H%M%S)"
ok "已备份 $CFG"

CFG="$CFG" PROVIDER="$PROVIDER" KEY="$KEY" SBASE="$SILICONFLOW_BASE" \
MODELS="$(printf '%s\n' "${MODELS[@]}")" python3 - <<'PY'
import json, os
cfg, provider, key = os.environ['CFG'], os.environ['PROVIDER'], os.environ['KEY']
sbase = os.environ['SBASE']
models = [m for m in os.environ['MODELS'].splitlines() if m.strip()]
d = json.load(open(cfg, encoding='utf-8'))
before_keys = json.loads(json.dumps(d.get('keys', [])))
is_custom = provider == 'siliconflow'

if is_custom:
    # 目录未收录 -> 声明 customProvider。注意 models 项字段名是 'model'（modelEntrySchema）
    cps = d.setdefault('customProviders', [])
    entry = {'baseUrl': sbase, 'apiKey': key, 'label': provider,
             'models': [{'model': m,
                         'displayName': m.split('/')[-1] + ' (硅基流动)',
                         'supportsTools': True, 'fallbackEnabled': True} for m in models]}
    cps[:] = [c for c in cps if c.get('label') != provider] + [entry]
else:
    # 目录已收录 -> 只需 key
    ks = d.setdefault('keys', [])
    ks[:] = [k for k in ks if not (k.get('platform') == provider and k.get('label') == provider + '1')]
    ks.append({'platform': provider, 'key': key, 'label': provider + '1'})

fb = d.setdefault('fallback', [])
maxp = max([e.get('priority', 0) for e in fb] or [0])
for m in models:
    maxp += 1
    if is_custom:
        # custom 平台下的模型靠 endpoint(baseUrl) 定位
        fb.append({'platform': 'custom', 'modelId': m, 'endpoint': sbase, 'priority': maxp})
    else:
        fb.append({'platform': provider, 'modelId': m, 'priority': maxp})

with open(cfg, 'w', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, indent=2); f.write('\n')

after = json.load(open(cfg, encoding='utf-8'))
expect = len(before_keys) + (0 if is_custom else 1)
assert len(after.get('keys', [])) == expect, '原有 keys 被破坏！'
print('  顶层键:', list(after.keys()))
print('  fallback 条数:', len(after['fallback']), '(新增 %d)' % len(models))
PY
ok "配置已写入（原有 keys 未破坏）"
echo
echo "-- 下一步：重启 freellmapi 容器让配置生效 --"
echo "   cd $ROOT && docker compose up -d freellmapi"
echo "   然后： bash $0 verify ${MODELS[*]}"

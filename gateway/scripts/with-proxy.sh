#!/bin/bash
# with-proxy.sh —— 策略 A：代理**不常驻**，按需给单条命令套上 v2ray 代理
#
# 为什么需要它：
#   ① 容器/宿主默认不带代理，需要时手写 -x / -e 容易记错端点；
#   ② 若盲目填 HTTP_PROXY 而 v2ray 没开，请求会**丢包慢超时（10s+）**，且会把
#      「本来能通的」也一起弄坏（含 qdrant 记忆检索，因为 qdrant 不在 NO_PROXY）。
#      所以本脚本**先探测端点**，不通就直接报错并提醒开 v2ray，绝不让你等超时。
#
# 用法：
#   with-proxy.sh --check                              # 只探测代理是否可用
#   with-proxy.sh curl -sS https://github.com          # 套代理跑任意命令
#   with-proxy.sh git clone https://github.com/O/R /tmp/x
#   with-proxy.sh -p socks5h://192.168.137.1:10810 curl …   # 换端点（默认走 HTTP :10811）
#   docker exec hermes /home/agent/scripts/with-proxy.sh curl -sS https://github.com
#
# 端点可用环境变量覆盖：PROXY_HOST / PROXY_HTTP_PORT / PROXY_SOCKS_PORT
set -uo pipefail

HOST=${PROXY_HOST:-192.168.137.1}
HTTP_PORT=${PROXY_HTTP_PORT:-10811}
SOCKS_PORT=${PROXY_SOCKS_PORT:-10810}
PREFIX="http://$HOST:$HTTP_PORT"

# NO_PROXY 里必须保留容器内部服务名，否则设了代理后内部调用会绕到代理上超时
NO_PROXY_KEEP="${NO_PROXY_KEEP:-localhost,127.0.0.1,chromadb,embedding-llama,reranker-llama,qdrant,dify-limiter,searxng,redis,postgres,minio,host.docker.internal,172.18.0.1,172.17.0.1}"

probe() { timeout "${PROBE_TIMEOUT:-3}" bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

if [ "${1:-}" = "--check" ]; then
  if probe "$HOST" "$HTTP_PORT"; then
    echo "✅ 代理可用：$PREFIX（SOCKS5 备用：socks5h://$HOST:$SOCKS_PORT）"
    exit 0
  fi
  echo "❌ 代理不可用（$PREFIX）"
  echo "   → 请在 Windows 上启动 v2rayN，并勾选「允许来自局域网的连接」"
  echo "   → 参考技能 devops/outbound-access-and-v2ray-proxy"
  exit 3
fi

if [ "${1:-}" = "-p" ]; then PREFIX="${2:?用法: -p <代理URL>}"; shift 2; fi
if [ $# -eq 0 ]; then sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1; fi

# 探测目标端点（从 URL 里取端口）
PP=${PREFIX#*://}; PH=${PP%%:*}
case "$PP" in *:*) PPORT=${PP##*:};; *) PPORT=1080;; esac
if ! probe "$PH" "$PPORT"; then
  echo "❌ 代理端点不可用：$PREFIX" >&2
  echo "   → 大概率是 v2ray 没开，或 v2rayN 未勾选「允许来自局域网的连接」" >&2
  echo "   → 已实测可用的端点：$HOST:$HTTP_PORT (HTTP)、$HOST:$SOCKS_PORT (SOCKS5)" >&2
  echo "   → 先用 $(basename "$0") --check 复核" >&2
  exit 3
fi

export HTTP_PROXY="$PREFIX"  HTTPS_PROXY="$PREFIX"
export http_proxy="$PREFIX"  https_proxy="$PREFIX"
export NO_PROXY="$NO_PROXY_KEEP" no_proxy="$NO_PROXY_KEEP"
exec "$@"

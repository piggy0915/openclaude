#!/usr/bin/env bash
# 监视 webui 侧顶层配置，一旦有变化立即调用单向同步（轮询，默认 3 秒；无额外依赖）
set -u
SRC=/home/user/gateway/data/.hermes-rt
SYNC=/home/user/gateway/scripts/sync-webui-to-brain.sh
INTERVAL=${SYNC_WATCH_INTERVAL:-3}
FILES=(config.yaml .env auth.json SOUL.md)

snapshot() { ( cd "$SRC" && sha256sum "${FILES[@]}" 2>/dev/null ) | sha256sum | cut -c1-16; }

# 启动先对一次：补上服务停机期间遗漏的变化
"$SYNC" --quiet
last=$(snapshot)

while true; do
  sleep "$INTERVAL"
  cur=$(snapshot)
  [ "$cur" = "$last" ] && continue
  last=$cur
  "$SYNC" --quiet
done

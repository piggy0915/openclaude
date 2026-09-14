#!/usr/bin/env bash
# normalize-shared-ownership.sh
# 目的：消除「共享树属主漂移」——两个容器都以 root 运行，它们写的文件是 root:root 0600；
#       一旦有任何以 uid 10000(hermes) 运行的进程（docker exec -u 10000、将来改成 user: "10000:10000"），
#       这些文件会 Permission denied。本脚本把共享树里 root 属主项统一归一到 10000:10000（幂等）。
# 用法：bash normalize-shared-ownership.sh [--quiet]
# 由 /etc/cron.d/hermes-ownership-normalize 每 15 分钟调用。
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

BASE=/home/user/gateway
TARGETS=(
  "$BASE/data/hermes/skills"
  "$BASE/data/hermes/memories"
  "$BASE/data/hermes/plugins"
  "$BASE/data/hermes/hooks"
  "$BASE/data/hermes/mcp"
  "$BASE/data/hermes/bin"
  "$BASE/data/hermes/cron"
  "$BASE/data/hermes/shared"
  "$BASE/data/hermes/wisdom"
  "$BASE/data/hermes/workspace"
  "$BASE/data/.hermes-rt"
  "$BASE/data/hermes-web-ui"
)

total=0
for d in "${TARGETS[@]}"; do
  [ -d "$d" ] || continue
  n=$(find "$d" -xdev -user root 2>/dev/null | wc -l)
  if [ "$n" -gt 0 ]; then
    find "$d" -xdev -user root -print0 2>/dev/null | xargs -0 -r chown -h 10000:10000 --
    total=$((total + n))
  fi
done

if [ "$QUIET" -eq 0 ]; then
  echo "$(date '+%F %T') 归一化完成：root->10000 共 $total 项"
elif [ "$total" -gt 0 ]; then
  echo "$(date '+%F %T') 归一化完成：root->10000 共 $total 项"
fi
exit 0

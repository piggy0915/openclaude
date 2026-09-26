#!/bin/bash
# 快照 Hermes 关键配置（config.yaml / .env）+ 卷内工具链文件
# 由 cron 每 10 分钟调用；内容未变化则不落新快照
# 快照目录含明文密钥 → 权限 700/600，且绝不可进任何 git 仓库
set -u

HERMES_DIR=/home/user/gateway/data/hermes
# B″″(2026-09-14)：webui 有了自己独立的 config.yaml/.env/auth.json（宿主 data/.hermes-rt），
# 同样会踩 save_config 丢段 bug，所以纳入同一套快照（前缀 rt- 区分）。
RT_DIR=/home/user/gateway/data/.hermes-rt
SNAP_DIR="$HERMES_DIR/config-snapshots"
LOG="$SNAP_DIR/snapshots.log"
KEEP=30
# "目录|文件名|快照前缀[|安装权限]" 四元组（权限缺省 600；可执行脚本写 755）
# 2026-09-19 纳入卷内工具链文件（Reasonix / OpenCodeReview 的引导脚本与配置）：
# 这些文件可以在卷里热改（改引导逻辑不必重建镜像），所以同样值得有版本可回滚。
ENTRIES="
$HERMES_DIR|config.yaml|
$HERMES_DIR|.env|
$RT_DIR|config.yaml|rt-
$RT_DIR|.env|rt-
$RT_DIR|auth.json|rt-
/opt/data/coding-agents|bootstrap.sh|ca-|755
/opt/data/coding-agents|run-bootstrap.sh|ca-|755
/opt/data/reasonix|config.toml|rk-|600
# Reasonix 的密钥文件（与 config.yaml/.env 同级待遇；快照目录 700/600，永不进 git）
/opt/data/reasonix|.env|rk-|600
/opt/data/opencodereview|config.json|ocr-|600
/opt/data/ghidra-mcp|env|gm-|600
"

mkdir -p "$SNAP_DIR"
chmod 700 "$SNAP_DIR"

newest_hash() {   # $1=文件名 -> 最近一份快照的 hash 前缀（无则空）
  local f
  f=$(ls -1t "$SNAP_DIR/$1-"* 2>/dev/null | head -1)
  [ -n "$f" ] || { printf ''; return; }
  basename "$f" | sed -E 's/.*-([0-9a-f]{8})$/\1/'
}

echo "$ENTRIES" | while IFS='|' read -r dir f prefix mode; do
  [ -n "${dir:-}" ] || continue
  src="$dir/$f"
  [ -f "$src" ] || continue
  key="${prefix}${f}"
  h=$(sha256sum "$src" | cut -c1-8)
  cur=$(newest_hash "$key")
  [ "$h" = "$cur" ] && continue
  ts=$(date +%Y%m%d-%H%M%S)
  dst="$SNAP_DIR/${key}-${ts}-${h}"
  install -m "${mode:-600}" -o root -g root "$src" "$dst" || continue
  printf '%s  %-16s %8s字节  %s  %s\n' \
    "$(date '+%F %T')" "$key" "$(stat -c %s "$src")" "$h" "$(basename "$dst")" >> "$LOG"
  # 只保留最近 KEEP 份
  ls -1t "$SNAP_DIR/$key-"* 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do rm -f "$old"; done
done

# 日志自截断
if [ -f "$LOG" ]; then tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; fi

# 心跳：每次执行都刷新（与「变化才落快照」互补，用于确认 cron 是否在跑）
{
  printf 'last_run : %s\n' "$(date '+%F %T')"
  printf 'snapshots（受管文件）: %s 份\n' "$(ls -1 "$SNAP_DIR" 2>/dev/null | grep -cE '^(config\.yaml|\.env|rt-|ca-|rk-|ocr-)')"
} > "$SNAP_DIR/.last-run" 2>/dev/null
chmod 600 "$SNAP_DIR/.last-run" 2>/dev/null

exit 0

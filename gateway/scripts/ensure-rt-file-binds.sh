#!/bin/bash
# ensure-rt-file-binds.sh —— B′「文件级共享」启动前自愈守卫（必须在 docker start 之前跑）
#
# 坑的机制（2026-09-13 实测定论）：
#   B′ 把 6 个「内容类」文件逐个 bind 到 webui 的运行时家，例如
#     ${PWD}/data/hermes/auth.lock  →  /home/agent/.hermes-rt/auth.lock
#   Docker 首次启动时会在这两个位置各建一个**空的占位文件**。
#   但 auth.lock 是**临时锁文件**（Hermes 加锁后常会 unlink）→ 下次启动时源文件可能不存在，
#   于是 Docker 把**源侧建成了目录** → 再往卷内那个「文件」上挂 → 容器创建直接失败：
#     "... auth.lock ... not a directory: Are you trying to mount a directory onto a file?"
#
# 本脚本把源/目标两侧都规整成普通文件。规则：
#   临时文件（auth.lock）缺失 → 直接补空文件（安全）
#   内容文件（auth.json / config.yaml / .env / SOUL.md / install_id）缺失 → **只告警不补**
#     （补成空文件会让 Hermes 拿到空配置，比启动失败更糟）
#
set -uo pipefail

HERMES_DIR=${HERMES_DIR:-/home/user/gateway/data/hermes}
RT_DIR=${RT_DIR:-/home/user/gateway/data/hermes-runtime}
TRANSIENT="auth.lock"                                  # 可安全补空
CONTENT="auth.json config.yaml .env SOUL.md install_id" # 缺失必须告警

say(){ printf '  %s\n' "$*"; }
ok(){ printf '✅ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
FIXED=0; BAD=0

echo "===== 源侧（$HERMES_DIR）====="
for f in $TRANSIENT $CONTENT; do
  p="$HERMES_DIR/$f"
  if [ -d "$p" ]; then
    if [ -z "$(ls -A "$p" 2>/dev/null)" ]; then
      rmdir "$p" && { say "删除被误建为目录的源: $f"; FIXED=1; }
    else
      warn "$f 源是**非空目录**（内容可能已丢）→ 需人工处理，跳过"; BAD=$((BAD+1)); continue
    fi
  fi
  if [ ! -e "$p" ]; then
    case " $TRANSIENT " in *" $f "*)
      : > "$p" && { say "补建临时源文件: $f"; FIXED=1; } ;;
    *)
      warn "内容文件缺失: $f → 不自动补空（请从备份恢复，如 config-snapshots / *.bak-*）"; BAD=$((BAD+1)); continue ;;
    esac
  fi
  case "$f" in config.yaml|.env|SOUL.md|install_id) chown 10000:10000 "$p" 2>/dev/null || true ;; esac
done

echo "===== 目标侧（$RT_DIR 卷内占位）====="
mkdir -p "$RT_DIR"
for f in $TRANSIENT $CONTENT; do
  p="$RT_DIR/$f"
  if [ -d "$p" ]; then
    rmdir "$p" 2>/dev/null && { say "删除被误建为目录的目标占位: $f"; FIXED=1; } || { warn "$f 目标是非空目录，跳过"; BAD=$((BAD+1)); continue; }
  fi
  if [ ! -e "$p" ]; then
    : > "$p" && chmod 600 "$p" && { say "补建目标占位: $f"; FIXED=1; }
  fi
done

echo
if [ "$BAD" -gt 0 ]; then
  warn "有 $BAD 项需要人工处理 —— 修好后再启动容器"
  exit 2
fi
[ "$FIXED" -eq 0 ] && ok "6 个源/目标均为普通文件，可以安全启动" || ok "已自愈 $FIXED 处，可以安全启动"
exit 0

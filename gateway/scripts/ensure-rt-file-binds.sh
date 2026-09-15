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
# 又一变体（2026-09-14 实测）：把**宿主源由目录改成真文件**后，容器**快照层**里还残留着
#   当时被建成的同名**目录**（挂载目标），此时 docker start 同样直接失败：
#     error mounting "...": not a directory: Are you trying to mount a directory onto a file
#   → 见下方「③ 快照层陈旧目录清理」。
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

echo "===== ③ 容器快照层里的陈旧挂载目标目录 ====="
# 场景：bind 源曾经是目录 → 容器快照 fs 里把挂载目标建成了目录；源改成文件后 start 直接失败。
# 安全前提：只在容器**已停止**时动快照；rmdir 只删空目录，非空会失败因而不会误删。
SNAPROOT=${SNAPROOT:-/srv/docker/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots}
FILE_BINDS=(
  "root/.openclaude.json|/home/user/gateway/config/openclaude/.openclaude.json"
  "root/.openclaude/settings.json|/home/user/gateway/config/openclaude/settings.json"
)
if [ -d "$SNAPROOT" ]; then
  RUNNING=$(docker inspect -f '{{.State.Running}}' hermes 2>/dev/null || echo false)
  if [ "$RUNNING" = "true" ]; then
    warn "hermes 仍在运行 → 跳过快照清理（本守卫须在 docker stop 之后、docker start 之前运行）"
  else
    for ent in "${FILE_BINDS[@]}"; do
      dst=${ent%%|*}; src=${ent##*|}
      [ -f "$src" ] || continue          # 源还不是真文件 → 现在不需要清
      for fsdir in "$SNAPROOT"/*/fs; do
        t="$fsdir/$dst"
        [ -d "$t" ] || continue
        snap=$(basename "$(dirname "$fsdir")")
        if rmdir "$t" 2>/dev/null; then
          say "删除快照 $snap 内的陈旧目录: $dst"; FIXED=1
        else
          warn "快照 $snap 内 $dst 是**非空目录** → 需人工处理"; BAD=$((BAD+1))
        fi
      done
    done
    [ "$RUNNING" != "true" ] && ok "快照层已检查（无需清理即为正常）"
  fi
else
  say "未发现 containerd 快照目录 $SNAPROOT（可能是别的存储驱动）→ 跳过"
fi

echo
if [ "$BAD" -gt 0 ]; then
  warn "有 $BAD 项需要人工处理 —— 修好后再启动容器"
  exit 2
fi
[ "$FIXED" -eq 0 ] && ok "源/目标均为普通文件、快照层无陈旧目录，可以安全启动" || ok "已自愈 $FIXED 处，可以安全启动"
exit 0

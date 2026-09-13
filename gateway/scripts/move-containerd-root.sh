#!/bin/bash
# move-containerd-root.sh —— 把 containerd 的 root 迁到新盘（Docker 数据搬迁的"缺失那一半"）
#
#   scripts/move-containerd-root.sh --check     只检查前置条件并打印计划（不改动任何东西）
#   scripts/move-containerd-root.sh             执行迁移（会停 docker/containerd，全套容器短暂中断）
#   scripts/move-containerd-root.sh --rollback  回滚：还原 containerd 配置并重启（数据未删，秒回）
#
#   背景：Docker 用了 containerd snapshotter（driver-type: io.containerd.snapshotter.v1），
#         镜像层/容器可写层归 **系统 containerd** 管，其 root 默认 /var/lib/containerd，
#         与 docker 的 data-root 无关 → 只改 data-root 搬不走真正的大头。
set -uo pipefail

SRC=/var/lib/containerd
TARGET=/srv/docker/containerd
CONF=/etc/containerd/config.toml
TS=$(date +%Y%m%d-%H%M%S)

MODE=execute
case "${1:-}" in
  ""|--apply)  MODE=execute ;;
  --check|-c|--dry-run) MODE=check ;;
  --rollback)  MODE=rollback ;;
  *) echo "用法: $0 [--check | --rollback]" >&2; exit 2 ;;
esac

say(){ printf '  %s\n' "$*"; }
ok(){ printf '✅ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
die(){ printf '❌ %s\n' "$*" >&2; exit 1; }
step(){ printf '\n===== %s =====\n' "$*"; }

# ─────────────── 回滚 ───────────────
if [ "$MODE" = rollback ]; then
  step "回滚 containerd root 到 $SRC"
  [ -f "$CONF.bak-$TS" ] || ls -1t "$CONF".bak-* >/dev/null 2>&1 || die "找不到配置备份（$CONF.bak-*）"
  BAK=$(ls -1t "$CONF".bak-* 2>/dev/null | head -1)
  say "使用备份: $BAK"
  systemctl stop docker docker.socket 2>/dev/null || true
  systemctl stop containerd 2>/dev/null || true
  cp -p "$BAK" "$CONF" && ok "配置已还原（root 不再指向 $TARGET）"
  systemctl start containerd && systemctl start docker
  sleep 5
  say "containerd: $(systemctl is-active containerd)  docker: $(systemctl is-active docker)"
  say "$(docker ps -q 2>/dev/null | wc -l) 个容器在跑"
  ok "回滚完成。原数据一直在 $SRC，未受影响。"
  exit 0
fi

step "0. 前置检查"
[ "$(id -u)" -eq 0 ] || die "需要 root"
[ -d "$SRC" ] || die "找不到 $SRC"
[ -d /srv/docker ] || die "/srv/docker 不存在（新盘未挂载？）"
mountpoint -q /srv/docker || die "/srv/docker 不是挂载点 —— 新盘没挂上，中止"
SRC_SIZE=$(du -sx --block-size=1 "$SRC" | cut -f1)
SRC_G=$(awk -v b="$SRC_SIZE" 'BEGIN{printf "%.1f", b/1024/1024/1024}')
TGT_FREE=$(df -B1 --output=avail /srv/docker | tail -1)
TGT_FREE_G=$(awk -v b="$TGT_FREE" 'BEGIN{printf "%.1f", b/1024/1024/1024}')
say "源 $SRC            : ${SRC_G} GiB"
say "目标 $TARGET 可用  : ${TGT_FREE_G} GiB"
[ "$TGT_FREE" -gt $((SRC_SIZE * 11 / 10)) ] || die "目标可用空间不足（需 ≥ 源 ×1.1）"
ok "空间充足"

CUR_ROOT=$(grep -E '^\s*root\s*=' "$CONF" 2>/dev/null | tail -1 | sed 's/.*=\s*//;s/"//g')
say "当前 containerd root : ${CUR_ROOT:-（未显式配置 → 默认 /var/lib/containerd）}"
[ "$CUR_ROOT" = "$TARGET" ] && { warn "containerd 已指向 $TARGET —— 无需再迁移"; [ "$MODE" = check ] && exit 0; }

IMG_BEFORE=$(docker images -q 2>/dev/null | wc -l)
CON_BEFORE=$(docker ps -a -q 2>/dev/null | wc -l)
SNAP_BEFORE=$(ls -1 "$SRC/io.containerd.snapshotter.v1.overlayfs/snapshots/" 2>/dev/null | wc -l)
say "迁移前基线: 镜像 $IMG_BEFORE 个 / 容器 $CON_BEFORE 个 / 快照 $SNAP_BEFORE 个"

if [ "$MODE" = check ]; then
  step "将要执行的动作（预览，未改动）"
  say "1) systemctl stop docker docker.socket containerd"
  say "2) 备份 $CONF → $CONF.bak-$TS，写入 root = \"$TARGET\""
  say "3) rsync -aHAX --numeric-ids $SRC/ $TARGET/"
  say "4) 校验（大小与快照数一致）"
  say "5) systemctl start containerd && systemctl start docker"
  say "6) 复核容器/镜像数 + overlay lowerdir 是否已指向 $TARGET"
  warn "此操作会短暂中断所有容器（含 hermes-webui，即当前对话界面）"
  exit 0
fi

step "1. 停止 docker + containerd"
systemctl stop docker docker.socket containerd
sleep 3
say "containerd: $(systemctl is-active containerd)  docker: $(systemctl is-active docker)"
[ "$(systemctl is-active containerd)" = "inactive" ] || die "containerd 未停止，中止（未做任何修改）"
ok "已停止"

step "2. 备份配置并写入新 root"
cp -p "$CONF" "$CONF.bak-$TS" 2>/dev/null || : > "$CONF.bak-$TS"
if grep -qE '^\s*root\s*=' "$CONF" 2>/dev/null; then
  sed -i -E "s|^\s*root\s*=.*|root = \"$TARGET\"|" "$CONF"
else
  printf 'root = "%s"\n' "$TARGET" >> "$CONF"
fi
say "配置备份: $CONF.bak-$TS"
sed -n '1,6p' "$CONF" | sed 's/^/    /'

step "3. 迁移数据（rsync，源保留不动）"
mkdir -p "$TARGET"
rsync -aHAX --numeric-ids --info=stats2 "$SRC/" "$TARGET/" | tail -5 | sed 's/^/  /'

step "4. 校验数据完整性"
TGT_SIZE=$(du -sx --block-size=1 "$TARGET" | cut -f1)
SNAP_AFTER=$(ls -1 "$TARGET/io.containerd.snapshotter.v1.overlayfs/snapshots/" 2>/dev/null | wc -l)
say "源 ${SRC_G} GiB → 目标 $(awk -v b="$TGT_SIZE" 'BEGIN{printf "%.1f", b/1024/1024/1024}') GiB"
say "快照数 $SNAP_BEFORE → $SNAP_AFTER"
if [ "${SNAP_AFTER:-0}" -lt "${SNAP_BEFORE:-0}" ]; then
  warn "快照数不一致，自动回滚"
  cp -p "$CONF.bak-$TS" "$CONF"
  systemctl start containerd && systemctl start docker
  die "数据校验失败，已回滚（配置还原，源数据完好）"
fi
ok "数据校验通过"

step "5. 启动 containerd + docker"
systemctl start containerd && sleep 2 && systemctl start docker
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
say "containerd: $(systemctl is-active containerd)  docker: $(systemctl is-active docker)"

step "6. 结果复核"
IMG_AFTER=$(docker images -q 2>/dev/null | wc -l)
CON_AFTER=$(docker ps -a -q 2>/dev/null | wc -l)
RUN_AFTER=$(docker ps -q 2>/dev/null | wc -l)
say "镜像 $IMG_BEFORE → $IMG_AFTER ；容器 $CON_BEFORE → $CON_AFTER （运行中 $RUN_AFTER）"
LOWER_SRV=$(mount | grep -c "lowerdir=$TARGET")
LOWER_VAR=$(mount | grep -c "lowerdir=$SRC")
say "overlay lowerdir 指向新盘: $LOWER_SRV 个 ；仍指向旧盘: $LOWER_VAR 个"
echo
df -hT /var /srv/docker | sed 's/^/  /'

if [ "$IMG_AFTER" -lt "$IMG_BEFORE" ] || [ "$CON_AFTER" -lt "$CON_BEFORE" ]; then
  warn "镜像/容器数减少 —— 建议回滚：$0 --rollback"
  exit 4
fi
ok "迁移完成。"
echo
warn "旧数据仍保留在 $SRC（未删除）—— 观察 2~3 天、确认容器与镜像一切正常后再清理："
say "  rm -rf $SRC && df -h /var"
say "如需立即回滚： $0 --rollback"

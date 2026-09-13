#!/bin/bash
# migrate-docker-to-disk.sh —— 把 Docker 数据目录整体迁到新磁盘（设计二）
#   Docker Root Dir: /var/lib/docker  →  /srv/docker（新盘，独立文件系统）
#   好处：/var 占用从 53G 降到约 9G；系统盘与 /var 不受新盘影响；出问题可改回配置回滚
#
#   scripts/migrate-docker-to-disk.sh --check        预览（不改动任何东西）
#   scripts/migrate-docker-to-disk.sh [设备]         执行（默认自动挑第一块干净的未用盘，如 /dev/sdb）
#   scripts/migrate-docker-to-disk.sh --status       看当前状态与回滚点
#   scripts/migrate-docker-to-disk.sh --rollback     改回 /var/lib/docker（需停 Docker）
#
#   ⚠ 本脚本会停掉**所有容器**（含 hermes-webui）。因此：
#      · 请在**宿主 shell** 里跑，不要在容器内跑；
#      · 建议脱离会话运行，避免 Shell 断开导致迁移中断：
#        nohup bash scripts/migrate-docker-to-disk.sh --yes >/var/log/docker-migrate.log 2>&1 &
#        tail -f /var/log/docker-migrate.log
#
set -uo pipefail

SRC=/var/lib/docker
DST=/srv/docker
FSLABEL=docker
DAEMON_JSON=/etc/docker/daemon.json
STAMP=$(date +%Y%m%d-%H%M%S)

say(){ printf '  %s\n' "$*"; }
ok(){ printf '✅ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
die(){ printf '❌ %s\n' "$*" >&2; exit 1; }

MODE=apply; DEV=""; ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check|-c) MODE=check ;;
    --status)   MODE=status ;;
    --rollback) MODE=rollback ;;
    --yes|-y)   ASSUME_YES=1 ;;
    /dev/*)     DEV="$1" ;;
    *) die "未知参数：$1" ;;
  esac; shift
done
[ "$(id -u)" -eq 0 ] || die "需要 root"

cur_root(){ docker info 2>/dev/null | awk -F': ' '/Docker Root Dir/{print $2}'; }
json_get(){ python3 -c "import json,sys;print(json.load(open('$DAEMON_JSON')).get('$1',''))" 2>/dev/null; }

# ---------------- --status ----------------
if [ "$MODE" = status ]; then
  echo "===== 当前状态 ====="
  say "Docker Root Dir : $(cur_root)"
  say "daemon.json     : data-root=$(json_get data-root || echo '(未设置)')  live-restore=$(json_get live-restore)"
  say "容器/镜像       : $(docker ps -q 2>/dev/null | wc -l) 个运行 / $(docker images -q 2>/dev/null | wc -l) 个镜像"
  say "旧目录 $SRC : $([ -d $SRC ] && echo "存在（$(du -sh $SRC 2>/dev/null | cut -f1)）← 回滚点" || echo 不存在)"
  say "新目录 $DST : $([ -d $DST ] && echo "存在（$(du -sh $DST 2>/dev/null | cut -f1)）" || echo 不存在)"
  say "mount /srv/docker : $(findmnt -no SOURCE,OPTIONS $DST 2>/dev/null || echo '未挂载')"
  say "fstab 条目      : $(grep -c "$FSLABEL $DST" /etc/fstab 2>/dev/null || true) 条"
  df -h /var /srv/docker 2>/dev/null | sed 's/^/  /'
  exit 0
fi

# ---------------- --rollback ----------------
if [ "$MODE" = rollback ]; then
  echo "===== 回滚到 $SRC ====="
  [ -d "$SRC" ] || die "$SRC 不存在，无法回滚"
  BAK=$(ls -1t ${DAEMON_JSON}.bak-migrate-* 2>/dev/null | head -1)
  [ -n "$BAK" ] || die "找不到 daemon.json 备份（${DAEMON_JSON}.bak-migrate-*）"
  say "将 daemon.json 还原为 $BAK（含 data-root=$(python3 -c "import json;print(json.load(open('$BAK')).get('data-root','(无)'))" 2>/dev/null)）"
  [ "$ASSUME_YES" = 1 ] || { read -rp "  确认回滚？(yes) " a; [ "$a" = yes ] || die "已取消"; }
  docker stop $(docker ps -q) 2>/dev/null
  systemctl stop docker docker.socket containerd 2>/dev/null
  cp -p "$DAEMON_JSON" "${DAEMON_JSON}.bak-rollback-$STAMP"
  cp -p "$BAK" "$DAEMON_JSON"
  systemctl start docker
  sleep 5
  ok "已回滚。Docker Root Dir = $(cur_root)"
  exit 0
fi

# ---------------- 前置检查（check 与 apply 共用）----------------
echo "===== 0. 前置检查 ====="
command -v rsync >/dev/null || die "缺少 rsync：apt-get install -y rsync"
[ -f "$DAEMON_JSON" ] || die "$DAEMON_JSON 不存在"
python3 -c "import json;json.load(open('$DAEMON_JSON'))" || die "$DAEMON_JSON 不是合法 JSON"
say "当前 Docker Root Dir: $(cur_root)"
[ "$(cur_root)" = "$SRC" ] || warn "当前 root 不是 $SRC —— 迁移将实际从 $(cur_root) 拷贝；本脚本按 $SRC 处理，请确认"

if [ -z "$DEV" ]; then
  for d in /sys/block/sd*; do
    n=$(basename "$d"); [ "$n" = sda ] && continue
    [ -b "/dev/$n" ] && DEV="/dev/$n" && break
  done
fi
[ -n "$DEV" ] && [ -b "$DEV" ] || die "找不到可用的新磁盘（请确认 VHDX 已挂到虚拟机：lsblk 应看到 sdb）"
say "目标设备: $DEV  ($(lsblk -no SIZE "$DEV" | head -1))"

case "$(basename "$DEV")" in sda|sda[0-9]*) die "$DEV 是系统盘，拒绝操作";; esac
if lsblk -no NAME "$DEV" | tail -n +2 | grep -q .; then
  lsblk -no NAME "$DEV" | tail -n +2 | sed 's/^/    已有分区: /'
  die "$DEV 上已有分区 —— 若确为该盘请先清理（wipefs -a $DEV）"
fi
if pvs "$DEV" >/dev/null 2>&1; then die "$DEV 已是 LVM PV，拒绝覆盖"; fi

EXIST_FS=$(blkid -s TYPE -o value "$DEV" 2>/dev/null || true)
EXIST_LABEL=$(blkid -s LABEL -o value "$DEV" 2>/dev/null || true)
if [ -n "$EXIST_FS" ]; then
  if [ "$EXIST_FS" = ext4 ] && [ "$EXIST_LABEL" = "$FSLABEL" ]; then
    say "检测到已有 ext4 文件系统（LABEL=$FSLABEL）→ 复用，不格式化"
    DO_MKFS=0
  else
    die "$DEV 上已有文件系统 ($EXIST_FS, LABEL=${EXIST_LABEL:-无)}) —— 拒绝覆盖，防止误删数据"
  fi
else
  say "设备干净（无文件系统/分区表）→ 将创建 ext4 (LABEL=$FSLABEL)"
  DO_MKFS=1
fi

SRC_SIZE_MB=$(du -sm "$SRC" 2>/dev/null | cut -f1)
[ -n "$SRC_SIZE_MB" ] && [ "$SRC_SIZE_MB" -gt 0 ] || die "无法测量 $SRC 体积"
DEV_SIZE_MB=$(( $(cat /sys/class/block/$(basename "$DEV")/size) / 2048 ))
say "待迁数据: ${SRC_SIZE_MB} MiB    目标盘: ${DEV_SIZE_MB} MiB"
[ "$DEV_SIZE_MB" -ge $(( SRC_SIZE_MB * 12 / 10 )) ] \
  || warn "目标盘容量 < 数据量 ×1.2，可能不够（建议至少 $(( SRC_SIZE_MB * 12 / 10 / 1024 )) GiB）"

BEFORE_CTN=$(docker ps -q 2>/dev/null | wc -l)
BEFORE_IMG=$(docker images -q 2>/dev/null | wc -l)
say "迁移前: ${BEFORE_CTN} 个运行容器 / ${BEFORE_IMG} 个镜像"

if [ "$MODE" = check ]; then
  echo
  echo "===== 预览：将要执行的动作 ====="
  say "1) $([ "$DO_MKFS" = 1 ] && echo "mkfs.ext4 -L $FSLABEL $DEV" || echo "（复用已有文件系统）")"
  say "2) mkdir -p $DST；写入 fstab（LABEL=$FSLABEL $DST ext4 defaults 0 2）；mount $DST"
  say "3) 在线预拷（不停机）：rsync -aHAX --delete $SRC/ $DST/"
  say "4) 停容器：docker stop \$(docker ps -q)   ← 含 hermes-webui"
  say "5) 停守护进程：systemctl stop docker docker.socket containerd"
  say "6) 增量补拷：rsync -aHAX --delete $SRC/ $DST/"
  say "7) 备份并改写 $DAEMON_JSON，加 \"data-root\": \"$DST\""
  say "8) systemctl start docker，校验 root/容器数/镜像数；失败自动回滚"
  say "9) 保留 $SRC 作为回滚点（不删）"
  echo
  warn "以上为预览，未做任何改动。（执行请去掉 --check）"
  exit 0
fi

# ---------------- 执行 ----------------
[ "$ASSUME_YES" = 1 ] || {
  echo
  warn "接下来会停掉全部 ${BEFORE_CTN} 个容器（含 hermes-webui / 可能正在对话的网页会话），并迁移 ${SRC_SIZE_MB} MiB 数据。"
  read -rp "  输入 yes 继续: " ans; [ "$ans" = yes ] || die "已取消"
}

echo
echo "===== 1. 准备文件系统 ====="
if [ "$DO_MKFS" = 1 ]; then
  mkfs.ext4 -q -L "$FSLABEL" "$DEV" || die "mkfs 失败"
  ok "已创建 ext4 (LABEL=$FSLABEL) on $DEV"
else
  ok "复用已有文件系统"
fi

echo
echo "===== 2. 挂载 $DST ====="
mkdir -p "$DST"
if ! grep -q "LABEL=$FSLABEL $DST" /etc/fstab; then
  cp -p /etc/fstab /etc/fstab.bak-migrate-$STAMP
  printf 'LABEL=%s %s ext4 defaults 0 2\n' "$FSLABEL" "$DST" >> /etc/fstab
  ok "已写入 fstab（备份 /etc/fstab.bak-migrate-$STAMP）"
fi
mountpoint -q "$DST" || mount "$DST" || die "挂载失败"
df -hT "$DST" | sed 's/^/  /'

echo
echo "===== 3. 在线预拷（不停机，可随时中断重跑）====="
rsync -aHAX --delete --info=progress2 "$SRC"/ "$DST"/ || die "预拷失败（磁盘空间不足？）"
ok "预拷完成"

echo
echo "===== 4. 停止容器（live-restore=true 下必须显式停）====="
if [ "$(docker ps -q | wc -l)" -gt 0 ]; then
  docker stop $(docker ps -q) 2>/dev/null | tail -3
fi
say "剩余运行容器: $(docker ps -q | wc -l)"

echo
echo "===== 5. 停止 Docker 守护进程 ====="
systemctl stop docker docker.socket containerd 2>/dev/null
sleep 3
pgrep -x dockerd >/dev/null && { systemctl stop docker; sleep 2; }
pgrep -x dockerd >/dev/null && die "dockerd 仍在运行，已中止（未改动 daemon.json）"
ok "dockerd 已停"

echo
echo "===== 6. 增量补拷 ====="
rsync -aHAX --delete "$SRC"/ "$DST"/ || { systemctl start docker; die "补拷失败，已恢复启动 Docker（daemon.json 未改）"; }
ok "补拷完成  ($(du -sh "$DST" 2>/dev/null | cut -f1))"

echo
echo "===== 7. 改写 daemon.json ====="
cp -p "$DAEMON_JSON" "${DAEMON_JSON}.bak-migrate-$STAMP"
python3 - "$DAEMON_JSON" "$DST" <<'PY'
import json, sys
p, dst = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d['data-root'] = dst
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
print('  data-root =', d['data-root'], '| live-restore =', d.get('live-restore'))
PY

echo
echo "===== 8. 启动并校验 ====="
systemctl start docker
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 2; done
NEWROOT=$(cur_root)
AFTER_CTN=$(docker ps -q 2>/dev/null | wc -l)
AFTER_IMG=$(docker images -q 2>/dev/null | wc -l)
say "Docker Root Dir : $NEWROOT"
say "容器/镜像       : ${AFTER_CTN} 个运行 / ${AFTER_IMG} 个镜像（迁移前 ${BEFORE_CTN}/${BEFORE_IMG}）"

FAIL=0
[ "$NEWROOT" = "$DST" ] || { warn "Docker Root Dir 不是 $DST"; FAIL=1; }
[ "$AFTER_IMG" -ge "$BEFORE_IMG" ] || { warn "镜像数减少（$BEFORE_IMG → $AFTER_IMG）"; FAIL=1; }

if [ "$FAIL" = 1 ]; then
  echo
  warn "校验未通过 → 自动回滚"
  docker stop $(docker ps -q) 2>/dev/null
  systemctl stop docker docker.socket containerd 2>/dev/null
  cp -p "${DAEMON_JSON}.bak-migrate-$STAMP" "$DAEMON_JSON"
  systemctl start docker
  sleep 5
  warn "已回滚，Docker Root Dir = $(cur_root)。旧目录 $SRC 完好，未丢数据。"
  exit 1
fi

ok "迁移完成"
echo
echo "===== 9. 收尾 ====="
df -hT /var "$DST" | sed 's/^/  /'
docker system df | sed 's/^/  /'
echo
warn "回滚点：$SRC 仍然完整保留（当前仍占 $(du -sh $SRC 2>/dev/null | cut -f1)）"
say "· 稳定运行 2–4 周后再删：rm -rf $SRC     ← 这一步才真正释放 /var 空间"
say "· 期间如需回滚：$0 --rollback --yes"
say "· 查看状态：$0 --status"
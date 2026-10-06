#!/bin/bash
# grow-sdb.sh —— 在线扩容 Docker data-root（/srv/docker）所在磁盘，零停机
#
#   scripts/grow-sdb.sh --check     只看现状与将要执行的动作（不改动任何东西）
#   scripts/grow-sdb.sh             执行：重扫磁盘 → 扩分区（如有）→ 在线扩 ext4 → 健康检查
#
# 前提：宿主侧（Hyper-V）已把该 VHDX 扩到目标大小（见 docs/docker-disk-grow-2026-10-02.md）
# 说明：
#   ① 本机 /srv/docker 的 ext4 **直接建在整盘上**（无分区表）→ 不需要 growpart；
#   ② 扩 ext4 是纯元数据操作，**不需要重启 Docker、不用停容器**（在线 resize）；
#   ③ 盘符会漂移（插新盘后 sda/sdb 可能互换）→ 设备一律从 /srv/docker 动态推导，不硬编码。
set -uo pipefail
MNT=/srv/docker
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

say(){ printf '  %s\n' "$*"; }
ok(){ printf '✅ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
die(){ printf '❌ %s\n' "$*" >&2; exit 1; }
run(){ if [ "$CHECK" = 1 ]; then printf '  [预览] %s\n' "$*"; else eval "$@"; fi; }

echo "===== 0. 设备推导与前置检查 ====="
[ "$(id -u)" -eq 0 ] || die "需要 root 执行"
SRC=$(findmnt -no SOURCE "$MNT") || die "$MNT 未挂载"
FSTYPE=$(findmnt -no FSTYPE "$MNT")
OPT=$(findmnt -no OPTIONS "$MNT")
DISKNAME=$(lsblk -no PKNAME "$SRC" 2>/dev/null | head -1)
if [ -n "$DISKNAME" ]; then
  DISK="/dev/$DISKNAME"; PARTNUM=$(basename "$SRC" | sed "s/^${DISKNAME}//")
else
  DISKNAME=$(basename "$SRC"); DISK="$SRC"; PARTNUM=""
fi
say "$MNT → $SRC（$FSTYPE, $OPT）→ 整盘 $DISK（分区号 ${PARTNUM:-无}）"
case "$FSTYPE" in ext4|ext3) ;; *) die "只支持 ext4/ext3 在线扩容（当前 $FSTYPE）" ;; esac
case "$OPT" in *ro*|ro,*) die "$MNT 当前是只读挂载，先处理只读问题" ;; esac
ROOTDISK=$(basename "$(findmnt -no SOURCE / | sed 's#^/dev/##')" | sed 's/[0-9]*$//')
[ "$DISKNAME" = "$ROOTDISK" ] && die "$MNT 与 / 同盘（$DISK），请人工确认后再继续"
command -v resize2fs >/dev/null || die "缺少 resize2fs（e2fsprogs）"

echo
echo "===== 1. 重新扫描磁盘 + 计算可扩增量 ====="
run "echo 1 > /sys/class/block/$DISKNAME/device/rescan 2>/dev/null || true"
[ "$CHECK" = 0 ] && sleep 2
DEV_BYTES=$(( $(cat /sys/block/$DISKNAME/size) * 512 ))
BLK=$(dumpe2fs -h "$DISK" 2>/dev/null | awk -F: '/^Block count/{print $2}' | tr -d ' ')
BSZ=$(dumpe2fs -h "$DISK" 2>/dev/null | awk -F: '/^Block size/{print $2}' | tr -d ' ')
FS_BYTES=$(( ${BLK:-0} * ${BSZ:-0} ))
say "设备 $DISK : $((DEV_BYTES/1024/1024/1024)) GiB    文件系统: $((FS_BYTES/1024/1024/1024)) GiB"
# 判据：设备比文件系统大才有活干（不看 before/after —— 内核可能早已识别新容量）
if [ "$DEV_BYTES" -le "$FS_BYTES" ]; then
  warn "设备容量未超出文件系统（宿主侧未扩 / 已扩满 / 内核未识别），未做任何改动。请确认："
  say "① Hyper-V 里这块 VHDX 是否已扩到目标大小（当前盘：$DISK，内核看到 $((DEV_BYTES/1024/1024/1024)) GiB）"
  say "② 该 VM 是否有检查点/快照挡住扩容（有则先合并/删除）"
  say "③ 手动重扫：echo 1 > /sys/class/block/$DISKNAME/device/rescan"
  say "④ 仍不变 → 需要重启本机（关机期间不会动 Docker 数据）"
  exit 3
fi
ok "可扩增量：$(( (DEV_BYTES-FS_BYTES)/1024/1024/1024 )) GiB"

if [ -n "$PARTNUM" ]; then
  echo
  echo "===== 2. 扩展分区 ====="
  run "growpart $DISK $PARTNUM; partx -u $DISK 2>/dev/null || true"
else
  echo
  echo "===== 2. 无分区表（fs 直接建在整盘）→ 跳过分区扩展 ====="
fi

echo
echo "===== 3. 在线扩展文件系统（Docker 无需停机）====="
DOCKER_BEFORE=$(docker ps -q 2>/dev/null | wc -l)
DF_BEFORE=$(df -h "$MNT" | awk 'NR==2{print $2"  →  可用 "$4}')
say "扩容前: $DF_BEFORE（运行中容器 $DOCKER_BEFORE 个）"
run "resize2fs $DISK 2>&1 | sed 's/^/  /'"
DF_AFTER=$(df -h "$MNT" | awk 'NR==2{print $2"  →  可用 "$4}')
say "扩容后: $DF_AFTER"

echo
echo "===== 4. 健康检查（Docker 未受影响）====="
DOCKER_AFTER=$(docker ps -q 2>/dev/null | wc -l)
if [ "$DOCKER_BEFORE" = "$DOCKER_AFTER" ]; then ok "容器数未变：$DOCKER_AFTER 个"; else warn "容器数变化：$DOCKER_BEFORE → $DOCKER_AFTER，请检查"; fi
if [ "$CHECK" = 0 ]; then
  docker info 2>/dev/null | grep -E 'Storage Driver|Docker Root Dir' | sed 's/^/  /'
  TESTF="$MNT/.space-test.bin"
  if fallocate -l 5G "$TESTF" 2>/dev/null; then rm -f "$TESTF"; ok "写入测试通过（分配 5G 后已删除）"; else warn "写入测试失败（可能真的没空间了）"; fi
fi
echo
[ "$CHECK" = 1 ] && warn "以上为预览，未做任何改动" || ok "完成：$MNT 已在线扩容，Docker 全程未重启"

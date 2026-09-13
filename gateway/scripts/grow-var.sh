#!/bin/bash
# grow-var.sh —— 在线扩容 /var（自动识别 /var 背后的物理盘与分区，不依赖盘符）
#
#   scripts/grow-var.sh --check     只看现状与将要执行的动作（不改动任何东西）
#   scripts/grow-var.sh             把新增空间**全部**给 /var（默认）
#   scripts/grow-var.sh 100G        只给 /var 加 100G，其余留在卷组备用
#
#   ⚠ 2026-09-13 重写：原版硬编码 /dev/sda3；新增数据盘后系统盘变成 /dev/sdb，
#     盘符不可信 → 现改为从「/var 所在 LV → PV → 所在整盘」动态推导。
set -uo pipefail

VG=zgjy-debian-vg
LV=var
MNT=/var

CHECK=0
ADD_PCT="+100%FREE"
ADD_ABS=""
case "${1:-}" in
  ""|--apply) ;;
  --check|-c) CHECK=1 ;;
  +[0-9]*[GMTgmt]) ADD_ABS="+${1#+}" ;;
  [0-9]*[GMTgmt])  ADD_ABS="+${1}" ;;
  *) echo "用法: $0 [--check | <容量，如 100G>]" >&2; exit 2 ;;
esac

say(){ printf '  %s\n' "$*"; }
ok(){ printf '✅ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
die(){ printf '❌ %s\n' "$*" >&2; exit 1; }
run(){ if [ "$CHECK" = 1 ]; then printf '  [预览] %s\n' "$*"; else eval "$@"; fi; }

echo "===== 0. 前置检查与设备推导 ====="
[ "$(id -u)" -eq 0 ] || die "需要 root 执行"
command -v growpart >/dev/null || die "缺少 growpart → apt-get install -y cloud-guest-utils"
vgs "$VG" >/dev/null 2>&1 || die "找不到卷组 $VG"
SRC=$(findmnt -no SOURCE "$MNT"); ESC=$(printf '%s' "$VG" | sed 's/-/--/g')
case "$SRC" in /dev/mapper/${ESC}-*) : ;; *) die "$MNT 不在 $VG 上（当前 $SRC）" ;; esac
say "$MNT → $SRC（ext4 $(findmnt -no FSTYPE $MNT)）"

LVDEV=$(findmnt -no SOURCE "$MNT")
PV=$(pvs --noheadings -o pv_name --select "vg_name=$VG" 2>/dev/null | awk '{print $1}' | head -1)
[ -n "$PV" ] || die "推导不出 $VG 的 PV"
[ -b "$PV" ] || die "PV $PV 不是块设备"
DISKNAME=$(lsblk -no PKNAME "$PV" 2>/dev/null | head -1)
if [ -n "$DISKNAME" ]; then
  PARTNUM=$(basename "$PV" | sed "s/^${DISKNAME}//")
  DISK="/dev/$DISKNAME"
  say "PV=$PV → 整盘 /dev/$DISKNAME（分区号 ${PARTNUM:-无}）"
else
  DISKNAME=$(basename "$PV"); DISK="$PV"; PARTNUM=""
  say "PV=$PV → 整盘（无分区表，PV 直接建在整盘上）"
fi
[ "$DISKNAME" = "$(basename "$(findmnt -no SOURCE /)")" ] && warn "注意：$MNT 的 PV 竟然与 / 同盘，请人工确认后再继续"

echo
echo "===== 1. 重新扫描磁盘（让内核识别宿主侧扩容）====="
BEFORE=$(cat /sys/block/$DISKNAME/size)
run "echo 1 > /sys/class/block/$DISKNAME/device/rescan 2>/dev/null || true"
[ "$CHECK" = 0 ] && sleep 2
AFTER=$(cat /sys/block/$DISKNAME/size)
say "/dev/$DISKNAME 内核容量: $((BEFORE/2/1024/1024)) GiB → $((AFTER/2/1024/1024)) GiB"
if [ "$AFTER" -eq "$BEFORE" ]; then
  warn "内核识别的磁盘大小没变，无法继续。请依次确认："
  say "① 宿主 Hyper-V 是否真的扩了这块盘（当前是 /dev/$DISKNAME）"
  say "② 是否有检查点（快照）挡住扩容"
  say "③ 手动重扫：echo 1 > /sys/class/block/$DISKNAME/device/rescan"
  say "④ 仍不变则需重启本机"
  exit 3
fi

echo
echo "===== 2. 备份分区表（改动前必留）====="
DUMP="/root/${DISKNAME}-partition-table-$(date +%Y%m%d-%H%M%S).dump"
run "sfdisk -d $DISK > $DUMP"
say "备份文件: $DUMP"

echo
echo "===== 3. 扩展分区 ====="
if [ -z "$PARTNUM" ]; then
  say "PV 直接建在整盘上，跳过分区扩展"
else
  if [ "$CHECK" = 1 ]; then
    printf '  [预览] growpart %s %s\n' "$DISK" "$PARTNUM"
  else
    OUT=$(growpart "$DISK" "$PARTNUM" 2>&1); RC=$?
    echo "$OUT" | sed 's/^/  /'
    case "$RC" in
      0) ok "分区已扩展" ;;
      1) say "无需变更（分区已到磁盘末尾）" ;;
      *) die "growpart 失败(exit=$RC)；分区表未改动，可用备份还原：sfdisk $DISK < $DUMP" ;;
    esac
    partx -u "$DISK" 2>/dev/null || true
  fi
  say "$PV 现在: $(( $(cat /sys/block/$DISKNAME/$(basename $PV)/size 2>/dev/null || echo 0) /2/1024/1024 )) GiB"
fi

echo
echo "===== 4. 扩展物理卷 PV ====="
run "pvresize $PV"
[ "$CHECK" = 0 ] && vgs -o vg_name,pv_count,vg_size,vg_free "$VG" | sed 's/^/  /'

echo
echo "===== 5. 扩展逻辑卷 + 在线扩文件系统 ====="
VFREE_MB=$(vgs --noheadings -o vg_free --units m "$VG" | tr -dc '0-9')
if [ "$CHECK" = 0 ] && [ "${VFREE_MB:-0}" -lt 1024 ]; then die "卷组可用不足 1 GiB（${VFREE_MB}M），未改动 $MNT"; fi
if [ -n "$ADD_ABS" ]; then
  run "lvextend -r -L $ADD_ABS $LVDEV"
else
  run "lvextend -r -l +100%FREE $LVDEV"
fi

echo
echo "===== 6. 结果 ====="
df -hT "$MNT" | sed 's/^/  /'
vgs --noheadings -o vg_name,vg_free "$VG" | sed 's/^/  卷组剩余: /'
[ "$CHECK" = 1 ] && warn "以上为预览，未做任何改动" || ok "完成：$MNT 已在线扩容（零停机）"

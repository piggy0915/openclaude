#!/bin/bash
# add-disk-to-vg.sh —— 把新加的虚拟磁盘（VHDX）并入现有 LVM 卷组，在线扩容 /var
#
#   scripts/add-disk-to-vg.sh --check /dev/sdc   只检查，不改动
#   scripts/add-disk-to-vg.sh /dev/sdc           把该盘做成 PV → 加入卷组 → 扩容 /var
#   scripts/add-disk-to-vg.sh --check /dev/sdc 100G   只给 /var 加 100G（其余留在卷组）
#
#   ⚠ 2026-09-13 修正：盘符会随新盘插入而漂移（本机系统盘已从 sda 变成 sdb）→
#     保护名单不再硬编码，改为运行时推导：承载 /、/boot 以及卷组现有 PV 的整盘。
#
#   ⚠ 只会操作你显式指定的设备；对已有分区表/文件系统/PV 签名的盘一律拒绝。
set -uo pipefail

VG=zgjy-debian-vg
LV=var
MNT=/var
# 保护名单在运行时动态推导（见下）

say(){ printf '  %s\n' "$*"; }
ok(){ printf '✅ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
die(){ printf '❌ %s\n' "$*" >&2; exit 1; }
run(){ if [ "$CHECK" = 1 ]; then printf '  [预览] %s\n' "$*"; else eval "$@"; fi; }

CHECK=0
DEV=""
ADD_PCT="+100%FREE"
ADD_ABS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check|-c) CHECK=1 ;;
    /dev/*)     DEV="$1" ;;
    +[0-9]*[GMTgmt]|[0-9]*[GMTgmt]) ADD_ABS="+${1#+}" ;;
    *) die "无法识别的参数：$1" ;;
  esac
  shift
done
[ -n "$DEV" ] || { sed -n '2,8p' "$0" | sed 's/^# \?//'; exit 2; }

echo "===== 0. 前置检查 ====="
[ "$(id -u)" -eq 0 ] || die "需要 root 执行"
command -v pvcreate >/dev/null || die "缺少 pvcreate（lvm2）"
vgs "$VG" >/dev/null 2>&1 || die "找不到卷组 $VG"
SRC=$(findmnt -no SOURCE "$MNT"); ESC=$(printf '%s' "$VG" | sed 's/-/--/g')
case "$SRC" in /dev/mapper/${ESC}-*) : ;; *) die "$MNT 不在 $VG 上（当前 $SRC）" ;; esac

echo
echo "===== 1. 校验目标设备 ====="
[ -b "$DEV" ] || die "$DEV 不是块设备（不存在？新盘需要先让内核发现：for h in /sys/class/scsi_host/host*/scan; do echo \"- - -\" > \$h; done）"
# 动态推导受保护整盘：承载 / 、/boot 的盘 + 卷组现有 PV 所在盘
PROTECTED_DISKS=$( { findmnt -no SOURCE / ; findmnt -no SOURCE /boot 2>/dev/null; \
                     pvs --noheadings -o pv_name --select "vg_name=$VG" 2>/dev/null; } \
  | while read -r src; do
      [ -n "$src" ] || continue
      case "$src" in /dev/*) ;; *) continue ;; esac
      pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
      if [ -n "$pk" ]; then echo "$pk"; else
        b=$(basename "$src")
        case "$b" in sd[a-z]*|vd[a-z]*|nvme[0-9]*n[0-9]*) echo "$b" ;; esac   # 只接受整盘名，避免混入 LV
      fi
    done | sort -u )
say "受保护整盘（系统盘 / 卷组现用盘）：$(echo $PROTECTED_DISKS | tr '\n' ' ')"

DEV_DISK=$(lsblk -no PKNAME "$DEV" 2>/dev/null | head -1)
[ -n "$DEV_DISK" ] || DEV_DISK=$(basename "$DEV")
for p in $PROTECTED_DISKS; do
  [ "$DEV_DISK" = "$p" ] && die "$DEV 属于受保护整盘 /dev/$p（承载 / 或 /boot 或卷组数据）——拒绝操作"
done
[ "$(lsblk -no TYPE "$DEV" | head -1)" = "disk" ] || warn "$DEV 不是整盘（可能是分区，继续前请确认）"

if lsblk -no NAME "$DEV" | tail -n +2 | grep -q .; then
  die "$DEV 上已有分区：$(lsblk -no NAME "$DEV" | tail -n +2 | tr '\n' ' ')
     若该盘本应干净，可能是内核仍保留旧分区视图 → 先执行：partx -d "$DEV" 或重扫控制器
     确认盘上确实无数据后再重跑本脚本"
fi
if blkid "$DEV" >/dev/null 2>&1; then
  die "$DEV 已有文件系统/分区表签名：$(blkid "$DEV") —— 为防误删数据，拒绝继续"
fi
if pvs "$DEV" >/dev/null 2>&1; then
  say "该盘已是 PV，跳过 pvcreate"
else
  say "该盘干净（无分区表/文件系统/PV 签名）→ 可安全做成 PV"
fi
say "设备大小: $(lsblk -no SIZE "$DEV")"

echo
echo "===== 2. 创建 PV 并加入卷组 ====="
run "pvcreate -f -y '$DEV'"
run "vgextend '$VG' '$DEV'"
[ "$CHECK" = 0 ] && vgs -o vg_name,pv_count,vg_size,vg_free "$VG" | sed 's/^/  /'

echo
echo "===== 3. 扩容 /var ====="
VFREE_MB=$(vgs --noheadings -o vg_free --units m "$VG" | tr -dc '0-9')
if [ "$CHECK" = 0 ] && [ "${VFREE_MB:-0}" -lt 1024 ]; then die "卷组可用不足 1 GiB，未改动 /var"; fi
if [ -n "$ADD_ABS" ]; then
  run "lvextend -r -L $ADD_ABS /dev/$VG/$LV"
else
  run "lvextend -r -l +100%FREE /dev/$VG/$LV"
fi

echo
echo "===== 4. 结果 ====="
df -hT "$MNT" | sed 's/^/  /'
vgs -o vg_name,pv_count,vg_free "$VG" | sed 's/^/  /'
[ "$CHECK" = 1 ] && warn "以上为预览，未做任何改动" || ok "完成：$MNT 已在线扩容（零停机）"
if [ "$CHECK" = 0 ]; then
  echo
  warn "重要：卷组现在跨 $(pvs --noheadings -o pv_name --select "vg_name=$VG" 2>/dev/null | wc -l) 块物理盘 —— 新加入的 $DEV **不可单独拔除/删除**，否则 /var 会残缺。"
fi

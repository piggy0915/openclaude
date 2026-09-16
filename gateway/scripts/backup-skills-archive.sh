#!/bin/bash
# backup-skills-archive.sh —— 技能归档区跨盘快照（内容变化才写，保留最近 N 份）
#
# 为什么：data/hermes/skills-archive（132 技能/40M）此前**没有任何备份**；
#   本脚本把它快照到**另一块物理盘**（/srv/docker 所在的 sda），防误删/误操作。
#   （注：/home 与 /opt/data 同在一块盘 sdb3 的 LVM 上，放那里不防盘损）
#
# 用法：
#   backup-skills-archive.sh --check     # 只看指纹/份数，不写
#   backup-skills-archive.sh             # 有变化才写快照并校验
# 环境变量可覆盖：SRC / CAT / DST / KEEP / LOG
set -uo pipefail
SRC=${SRC:-/home/user/gateway/data/hermes/skills-archive}
CAT=${CAT:-/home/user/gateway/data/workspace/skills-catalog.md}
DST=${DST:-/srv/docker/backups/skills-archive}
KEEP=${KEEP:-5}
LOG=${LOG:-/var/log/skills-archive-backup.log}
ts(){ date '+%F %T'; }

[ -d "$SRC" ] || { echo "❌ 源目录不存在: $SRC"; exit 2; }
mkdir -p "$DST"
COUNT=$(find "$SRC" -name SKILL.md | wc -l)
FP=$( (cd "$SRC" && find . -name SKILL.md -printf '%P\n' -exec md5sum {} \; 2>/dev/null) | md5sum | cut -c1-16)
FPL="$DST/.fingerprint"; PREV=$(cat "$FPL" 2>/dev/null || echo "")

if [ "${1:-}" = "--check" ]; then
  echo "  源      : $SRC（$COUNT 个 SKILL.md）"
  echo "  目标    : $DST（保留最近 $KEEP 份）"
  echo "  当前指纹: $FP  |  上次: ${PREV:-无}"
  echo "  已有快照: $(ls -1 "$DST"/skills-archive-*.tgz 2>/dev/null | wc -l) 份，共 $(du -sh "$DST" 2>/dev/null | cut -f1)"
  exit 0
fi

if [ "$FP" = "$PREV" ]; then echo "$(ts) 无变化，跳过（指纹 $FP）" >> "$LOG"; echo "  无变化，跳过"; exit 0; fi
OUT="$DST/skills-archive-$(date +%Y%m%d-%H%M%S).tgz"
tar czf "$OUT" -C "$(dirname "$SRC")" "$(basename "$SRC")"
SZ=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
N=$(tar tzf "$OUT" 2>/dev/null | grep -c 'SKILL.md$')
if [ "$N" != "$COUNT" ] || [ "$SZ" -lt 1000000 ]; then
  echo "$(ts) ❌ 校验失败：tar 内 $N vs 源 $COUNT，$((SZ/1024))KB → 删除 $OUT" >> "$LOG"
  rm -f "$OUT"; echo "  ❌ 校验失败（见 $LOG）"; exit 1
fi
echo "$FP" > "$FPL"
[ -f "$CAT" ] && cp -f "$CAT" "$DST/skills-catalog-latest.md"
ls -1t "$DST"/skills-archive-*.tgz 2>/dev/null | tail -n +$((KEEP+1)) | while read -r f; do
  rm -f "$f"; echo "$(ts) 清理旧快照 $(basename "$f")" >> "$LOG"
done
echo "$(ts) ✅ $(basename "$OUT")（$((SZ/1024/1024))MB，$N 个 SKILL.md），保留最近 $KEEP 份" >> "$LOG"
echo "  ✅ 已写 $(basename "$OUT")（$((SZ/1024/1024))MB / $N 个 SKILL.md）"

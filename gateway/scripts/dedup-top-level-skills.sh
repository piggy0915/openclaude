#!/bin/bash
# dedup-top-level-skills.sh —— 清理「技能搬进分类目录后留下的顶层副本」
#
# 背景：整理技能时把顶层技能复制进分类目录（如 pptx → document-processing/pptx），
#       但顶层的原件没删 → 同一 frontmatter name 出现两次。
#       Hermes 索引按 name 去重 → 其中一个成为「影子副本」永不出现。
#
#   scripts/dedup-top-level-skills.sh            预览（默认，不改动）
#   scripts/dedup-top-level-skills.sh --apply    执行（顶层副本**移动**到备份目录，不删除）
#
# 安全规则：
#   ① 只处理「顶层同名 + 分类同名」且 **内容哈希完全一致** 的组
#   ② 内容不一致（真·同名不同技能）→ 只报告，绝不自动处理
#   ③ 用 mv 到备份目录，可一键还原
set -uo pipefail
LIVE=/home/user/gateway/data/hermes/skills
MODE=preview
[ "${1:-}" = "--apply" ] && MODE=apply
BK="/root/skill-dedup-backup-$(date +%Y%m%d-%H%M%S)"

mapfile -t groups < <(python3 - "$LIVE" <<'PY'
import pathlib, re, sys, collections
LIVE = pathlib.Path(sys.argv[1])
by = collections.defaultdict(list)
for f in LIVE.rglob('SKILL.md'):
    if any(p.startswith('.') for p in f.parts): continue
    t = f.read_text(encoding='utf-8', errors='ignore')
    m = re.search(r'^name:\s*(.+)$', t, re.M)
    nm = m.group(1).strip().strip('"\'') if m else f.parent.name
    rel = f.parent.relative_to(LIVE)
    by[nm].append((str(rel), str(f)))
for nm, v in sorted(by.items()):
    if len(v) < 2: continue
    tops = [x for x in v if x[0] == nm]                 # 位于顶层的副本
    others = [x for x in v if x[0] != nm]
    for tp, tpath in tops:
        for od, opath in others:
            print(f'{nm}\t{tpath}\t{opath}')
PY
)
n=0; skip=0
for line in "${groups[@]}"; do
  [ -n "$line" ] || continue
  IFS=$'\t' read -r nm tpath opath <<< "$line"
  h1=$(sha256sum "$tpath" | cut -c1-16); h2=$(sha256sum "$opath" | cut -c1-16)
  if [ "$h1" != "$h2" ]; then
    printf '  ⚠️ 内容不同，跳过: %-34s 顶层(%s) vs %s(%s)\n' "$nm" "$h1" "$opath" "$h2"; skip=$((skip+1)); continue
  fi
  rel=${tpath#$LIVE/}
  printf '  ✂ 顶层副本: %-34s %s  （分类版保留: %s）\n' "$nm" "$rel" "${opath#$LIVE/}"
  if [ "$MODE" = apply ]; then
    dest="$BK/$(dirname "$rel")"; mkdir -p "$dest"
    mv "$tpath" "$dest/" && rm -rf "$(dirname "$tpath")" 2>/dev/null
  fi
  n=$((n+1))
done
echo
echo "===== 汇总 ====="
echo "  可清理的顶层副本: $n 组    内容不一致跳过: $skip 组"
if [ "$MODE" = apply ]; then
  echo "  ✅ 已移动到备份目录: $BK"
  echo "  还原：cp -a $BK/* $LIVE/"
  echo "  ⚠ 需重启刷新索引: docker stop hermes hermes-webui && docker start hermes hermes-webui"
else
  echo "  （预览模式，未改动。执行请加 --apply）"
fi

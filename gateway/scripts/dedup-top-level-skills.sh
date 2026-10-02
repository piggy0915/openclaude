#!/bin/bash
# dedup-top-level-skills.sh —— 清理「技能搬进分类目录后留下的顶层副本」
#
# 背景：整理技能时把顶层技能复制进分类目录（如 pptx → document-processing/pptx），
#       但顶层的原件没删 → 同一 frontmatter name 出现两次。
#
#   scripts/dedup-top-level-skills.sh            预览（默认，不改动）
#   scripts/dedup-top-level-skills.sh --apply    执行（副本**移动**到备份目录，不删除）
#
# 安全规则：
#   ① 只处理「顶层副本 + 分类副本」且 SKILL.md **内容哈希完全一致** 的组
#   ② 内容不一致（分类版是超集/更新等）→ 只报告，需人工判断后单独处理
#   ③ mv 到备份目录，可一键还原
#   ④ 例外：Studio(webui) 注入的顶层技能（见 .webui-managed-skills.json）删了会被重新注入
#        → 这类反向处理：保留顶层、丢弃分类副本
#   ⑤ 类目容器目录（自身之外还含嵌套 SKILL.md，如 document-processing/、mcp/）**绝不整体删除**
#      —— 2026-10-02 曾因把 document-processing/、mcp/ 误当“顶层副本”而整目录删除（已用快照回滚）
set -uo pipefail
LIVE=/home/user/gateway/data/hermes/skills
ARCH=/home/user/gateway/data/skill-archive
MODE=preview
[ "${1:-}" = "--apply" ] && MODE=apply
BK="$ARCH/dedup-$(date +%Y%m%d-%H%M%S)"
MANAGED="$LIVE/.webui-managed-skills.json"

mapfile -t groups < <(python3 - "$LIVE" <<'PY'
import pathlib, re, sys, collections
LIVE = pathlib.Path(sys.argv[1])

def is_container(d: pathlib.Path) -> bool:
    """类目/容器目录：自身之外还含嵌套 SKILL.md → 绝不整体删除。"""
    try:
        return any(p.parent != d for p in d.rglob('SKILL.md'))
    except OSError:
        return True   # 读不了就按容器处理（宁可不处理）

by = collections.defaultdict(list)
for f in LIVE.rglob('SKILL.md'):
    if any(p.startswith('.') for p in f.parts): continue
    t = f.read_text(encoding='utf-8', errors='ignore')
    m = re.search(r'^name:\s*(.+)$', t, re.M)
    nm = m.group(1).strip().strip('"\'') if m else f.parent.name
    by[nm].append((str(f.parent.relative_to(LIVE)), str(f)))

for nm, v in sorted(by.items()):
    if len(v) < 2: continue
    v = [x for x in v if not is_container(LIVE / x[0])]   # 容器目录直接出列
    tops   = [x for x in v if '/' not in x[0]]            # 顶层副本（按路径深度判定，兼容目录名≠frontmatter name）
    others = [x for x in v if '/' in x[0]]
    for tp, tpath in tops:
        for od, opath in others:
            print(f'{nm}\t{tpath}\t{opath}')
PY
)
n=0; skip=0; skipc=0
for line in "${groups[@]}"; do
  [ -n "$line" ] || continue
  IFS=$'\t' read -r nm tpath opath <<< "$line"
  [ -e "$tpath" ] && [ -e "$opath" ] || continue        # 前一对可能已把它们移走
  h1=$(sha256sum "$tpath" | cut -c1-16); h2=$(sha256sum "$opath" | cut -c1-16)
  if [ "$h1" != "$h2" ]; then
    printf '  ⚠️ 内容不同，跳过: %-30s 顶层(%s) vs %s(%s)\n' "$nm" "$h1" "$opath" "$h2"; skip=$((skip+1)); continue
  fi
  # 方向判定：Studio 托管 → 丢弃分类副本、保留顶层；否则丢弃顶层、保留分类副本
  if python3 -c "import json,sys;sys.exit(0 if '$nm' in json.load(open('$MANAGED')) else 1)" 2>/dev/null; then
    drop="$opath"; keep="$tpath"; kind="分类副本"
  else
    drop="$tpath"; keep="$opath"; kind="顶层副本"
  fi
  # 安全闸：待丢弃目录内含子技能 = 类目容器 → 只报告，不删
  if [ -n "$(find "$(dirname "$drop")" -mindepth 2 -name SKILL.md -print -quit 2>/dev/null)" ]; then
    printf '  ⏭ 类目容器，跳过: %-30s %s\n' "$nm" "$(dirname "$drop")"; skipc=$((skipc+1)); continue
  fi
  printf '  ✂ %-30s 丢弃 %-8s %-42s 保留 %s\n' "$nm" "$kind" "${drop#$LIVE/}" "${keep#$LIVE/}"
  if [ "$MODE" = apply ]; then
    dest="$BK/$(dirname "$drop")"; mkdir -p "$dest"
    mv "$drop" "$dest/" && rm -rf "$(dirname "$drop")" 2>/dev/null
  fi
  n=$((n+1))
done
echo
echo "===== 汇总 ====="
echo "  可清理副本: $n 组    内容不一致跳过: $skip 组    类目容器跳过: $skipc 组"
if [ "$MODE" = apply ]; then
  echo "  ✅ 已移动到备份目录: $BK"
  echo "  还原：cp -a $BK/* $LIVE/"
  echo "  ⚠ 需重启刷新索引: docker stop hermes hermes-webui && docker start hermes hermes-webui"
else
  echo "  （预览模式，未改动。执行请加 --apply）"
fi

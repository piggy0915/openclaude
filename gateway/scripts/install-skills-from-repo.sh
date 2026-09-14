#!/bin/bash
# install-skills-from-repo.sh —— 从 Gitee 技能仓库安装技能到 live 目录
#
#   仓库自带 sync-new-skills.py 只做 live→repo（备份方向），没有反向安装 → 本脚本补上。
#
#   scripts/install-skills-from-repo.sh --list                列出尚未安装的仓库技能（按分类）
#   scripts/install-skills-from-repo.sh --tier 1              预览：Tier1 推荐清单（不改动）
#   scripts/install-skills-from-repo.sh --tier 1 --apply      安装 Tier1
#   scripts/install-skills-from-repo.sh --tier 2 --apply      安装 Tier2
#   scripts/install-skills-from-repo.sh --only a b c --apply  只装指定技能
#   scripts/install-skills-from-repo.sh --file names.txt --apply   按文件里的名单装（每行一个）
#
#   安全规则：目标已存在 → 跳过（绝不覆盖）；源不存在 → 报错；全程只写 live 目录。
set -uo pipefail

REPO=/opt/data/hermes-skills
LIVE=/home/user/gateway/data/hermes/skills
CONTAINER_SKILLS=/home/agent/.hermes/skills

# ── Tier 1：与 Hermes 自托管 / 多智能体 / 文档 / 质量安全合规 / 产品项目 直接对口 ──
TIER1="
engineering-devops-automator
engineering-sre
engineering-incident-response-commander
engineering-code-reviewer
engineering-software-architect
engineering-minimal-change-engineer
engineering-database-optimizer
engineering-security-engineer
engineering-threat-detection-engineer
engineering-technical-writer
engineering-git-workflow-master
engineering-multi-agent-systems-architect
engineering-prompt-engineer
engineering-backend-architect
engineering-data-engineer
engineering-codebase-onboarding-engineer
agents-orchestrator
specialized-mcp-builder
specialized-document-generator
specialized-workflow-architect
automation-governance-architect
data-consolidation-agent
report-distribution-agent
operations-manager
specialized-model-qa
lsp-index-engineer
specialized-strategy-duel-agent
security-compliance-auditor
security-architect
security-cloud-security-architect
security-appsec-engineer
security-incident-responder
testing-evidence-collector
testing-reality-checker
testing-tool-evaluator
testing-test-results-analyzer
testing-workflow-optimizer
testing-api-tester
project-management-meeting-notes-specialist
project-management-project-shepherd
project-management-experiment-tracker
product-manager
product-feedback-synthesizer
product-sprint-prioritizer
product-trend-researcher
design-ux-architect
design-ui-designer
design-image-prompt-engineer
support-executive-summary-generator
support-infrastructure-maintainer
support-analytics-reporter
chief-of-staff
chief-financial-officer
finance-financial-analyst
finance-fpa-analyst
"

# ── Tier 2：中文平台营销 / 咨询与治理 / 开发补充 / 学习类 ──
TIER2="
marketing-zhihu-strategist
marketing-xiaohongshu-specialist
marketing-wechat-official-account
marketing-multi-platform-publisher
marketing-content-creator
marketing-carousel-growth-engine
marketing-seo-specialist
marketing-ai-citation-strategist
marketing-aeo-foundations
marketing-video-optimization-specialist
marketing-book-co-author
marketing-pr-communications-manager
marketing-growth-hacker
business-strategist
change-management-consultant
customer-success-manager
organizational-psychologist
data-privacy-officer
specialized-pricing-analyst
personal-growth-mentor
engineering-ai-engineer
engineering-rapid-prototyper
engineering-senior-developer
engineering-frontend-developer
engineering-it-service-manager
engineering-embedded-firmware-engineer
engineering-voice-ai-integration-engineer
engineering-email-intelligence-engineer
testing-accessibility-auditor
testing-performance-benchmarker
sales-proposal-strategist
sales-deal-strategist
sales-account-strategist
sales-pipeline-analyst
academic-anthropologist
academic-historian
academic-psychologist
academic-geographer
academic-narratologist
"

say(){ printf '  %s\n' "$*"; }
ok(){ printf '✅ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
die(){ printf '❌ %s\n' "$*" >&2; exit 1; }

MODE=preview; TIER=""; FILE=""; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)  MODE=apply ;;
    --list)   MODE=list ;;
    --tier)   TIER="${2:-}"; shift ;;
    --file)   FILE="${2:-}"; shift ;;
    --only)   ONLY="1" ;;
    --help|-h) sed -n '2,14p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) if [ -n "$ONLY" ]; then ONLY="$ONLY $1"; else die "未知参数: $1"; fi ;;
  esac
  shift
done

[ -d "$REPO" ] || die "仓库不存在: $REPO"
[ -d "$LIVE" ] || die "live 技能目录不存在: $LIVE"

# 技能名 -> 仓库源路径（优先 agency-agents-zh/<cat>/<name>，其次顶层 <name>）
src_of(){
  local n="$1" p
  p=$(find "$REPO/agency-agents-zh" -maxdepth 2 -type d -name "$n" 2>/dev/null | head -1)
  [ -n "$p" ] && { echo "$p"; return; }
  p=$(find "$REPO" -maxdepth 1 -type d -name "$n" 2>/dev/null | head -1)
  [ -n "$p" ] && { echo "$p"; return; }
  echo ""
}
# 目标分类：仓库在 agency-agents-zh/<cat>/ 下 → 用 <cat>；否则顶层
target_of(){
  local src="$1" n="$2"
  case "$src" in
    "$REPO"/agency-agents-zh/*/*) echo "$LIVE/$(basename "$(dirname "$src")")/$n" ;;
    *) echo "$LIVE/$n" ;;
  esac
}

list_missing(){
  python3 - "$REPO" "$LIVE" <<'PY'
import pathlib, sys, collections
repo, live = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
def names(root): return {f.parent.name for f in root.rglob('SKILL.md') if not any(p.startswith('.') for p in f.parts)}
r, l = names(repo), names(live)
miss = sorted(r - l)
by = collections.Counter()
for f in repo.rglob('SKILL.md'):
    if any(p.startswith('.') for p in f.parts): continue
    if f.parent.name in miss:
        rel = f.parent.relative_to(repo)
        by[str(rel.parent) if str(rel.parent) != '.' else '(顶层)'] += 1
print(f'  未安装: {len(miss)} 个（仓库 {len(r)} / live {len(l)}）')
for c, n in sorted(by.items(), key=lambda x: -x[1]):
    print(f'    {n:4d}  {c}')
PY
}

case "$MODE" in
  list) echo "=== 尚未安装的仓库技能 ==="; list_missing; exit 0 ;;
esac

# 组装名单
if [ -n "$ONLY" ]; then
  NAMES=$(echo "$ONLY" | tr ' ' '\n' | grep -v '^1$' | grep -v '^$')
elif [ -n "$FILE" ]; then
  [ -f "$FILE" ] || die "名单文件不存在: $FILE"
  NAMES=$(grep -vE '^\s*#|^\s*$' "$FILE")
elif [ "$TIER" = 1 ]; then NAMES=$(echo "$TIER1" | grep -v '^$')
elif [ "$TIER" = 2 ]; then NAMES=$(echo "$TIER2" | grep -v '^$')
elif [ "$TIER" = 3 ]; then NAMES=$(cat <<'EOF'
EOF
)
else die "需指定 --list / --tier N / --only ... / --file ..."; fi

TOTAL=0; NEW=0; SKIP=0; ERR=0
echo "===== 模式: $([ "$MODE" = apply ] && echo 安装 || echo 预览) ====="
while read -r n; do
  [ -n "$n" ] || continue
  TOTAL=$((TOTAL+1))
  src=$(src_of "$n")
  if [ -z "$src" ]; then printf '  ❌ 仓库里找不到: %s\n' "$n"; ERR=$((ERR+1)); continue; fi
  dst=$(target_of "$src" "$n")
  if [ -e "$dst" ]; then printf '  ⏭  已存在，跳过: %s\n' "$n"; SKIP=$((SKIP+1)); continue; fi
  printf '  ➕ %-52s → %s\n' "$n" "${dst#$LIVE/}"
  if [ "$MODE" = apply ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst" || { printf '     ❌ 复制失败\n'; ERR=$((ERR+1)); continue; }
  fi
  NEW=$((NEW+1))
done <<< "$NAMES"

echo
echo "===== 汇总 ====="
say "名单总数: $TOTAL   新装: $NEW   已存在跳过: $SKIP   错误: $ERR"
if [ "$MODE" = apply ] && [ "$NEW" -gt 0 ]; then
  ok "已写入 live: $LIVE（容器内可见: $CONTAINER_SKILLS）"
  warn "技能索引在启动时构建 → 需成对重启才生效："
  say "  docker stop hermes hermes-webui && docker start hermes hermes-webui"
  say "验证：docker exec hermes-webui bash -c 'find $CONTAINER_SKILLS -name SKILL.md | wc -l'"
else
  warn "以上为预览，未改动任何文件（加 --apply 才执行）"
fi

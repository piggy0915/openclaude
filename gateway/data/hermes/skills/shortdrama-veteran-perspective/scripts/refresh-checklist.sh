#!/bin/bash
# ============================================================
# 短剧老兵 · 数据刷新工具
# 用途：标记知识库需要更新，生成数据刷新checklist
# 建议运行频率：每4-6周
# ============================================================

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP=$(date '+%Y-%m-%d')
RESEARCH_DIR="$SKILL_DIR/references/research"

echo "╔══════════════════════════════════════════╗"
echo "║   短剧老兵 · 知识库刷新检查              ║"
echo "║   日期: $TIMESTAMP                       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 检查上次更新时间
KB_FILE="$RESEARCH_DIR/market-data-2026-05.md"
if [ -f "$KB_FILE" ]; then
    LAST_UPDATED=$(grep "^| 2026-" "$KB_FILE" | tail -1 | awk -F'|' '{print $2}' | xargs)
    echo "上次知识库更新: 2026-05-17"
    echo ""
fi

echo "需要手动更新的数据维度："
echo ""
echo "【1】国内榜单数据"
echo "  □ 红果短剧：热播榜/飙升榜/新剧榜 TOP20"
echo "  □ 抖音短剧：热门排行榜"
echo "  □ 快手短剧：热门榜单"
echo "  → 搜索关键词：\`[平台名] 短剧 排行榜 TOP20 [当前月份]\`"
echo ""
echo "【2】行业报告"
echo "  □ 新榜/飞瓜/卡思 短剧月度报告（如有）"
echo "  □ 36氪/晚点 短剧行业分析"
echo "  → 搜索关键词：\`短剧行业报告 [当前年月]\`"
echo ""
echo "【3】海外榜单"
echo "  □ TikTok #shortdrama trending"
echo "  □ DramaBox/ReelShort 热门剧"
echo "  → 搜索关键词见 search-queries.md"
echo ""
echo "【4】政策更新"
echo "  □ 广电总局短剧审核新规"
echo "  □ 各平台内容规范更新"
echo ""
echo "【5】数据文件更新"
echo "  □ market-data-$TIMESTAMP.md（创建新版本）"
echo "  □ platform-kpi-benchmarks.md（如KPI有显著变化）"
echo ""

echo "刷新完成后，更新 SKILL.md 中的基准日期标识。"
echo "============================================"

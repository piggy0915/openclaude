#!/bin/bash
# openclaude-ds.sh —— 用 DeepSeek 驱动 openclaude（OpenAI 兼容路由，实测可用）
#
# 关键（2026-09-14 实测定位，血泪版）：
#   ① 必须用 CLAUDE_CODE_USE_OPENAI=1 激活「Custom (OpenAI-compatible)」路由。
#      只给 --provider openai 会走**默认 OpenAI 路由**（硬编码 https://api.openai.com），
#      本机不可达 → 连接超时 → **自动重试 11 次**（看起来像"卡死"，实测每次约 21s）。
#   ② 本端点真实模型名是 deepseek-flash / deepseek-v4-pro（不是 deepseek-chat）。
#   ③ 提示词从 stdin 传入最稳：printf '任务' | openclaude-ds.sh -p
#   ④ root 身份禁止 --dangerously-skip-permissions/--yolo（CLI 主动拒绝）。
#
# 用法：
#   printf '写一个快速排序' | openclaude-ds.sh -p
#   openclaude-ds.sh -p "写一个快速排序"        # 位置参数亦可
#   docker exec -i hermes /home/agent/scripts/openclaude-ds.sh -p < task.txt
set -euo pipefail
: "${DEEPSEEK_API_KEY:?容器内未设置 DEEPSEEK_API_KEY —— 检查 config/.env}"
# ⑤ HOME 必须干净：容器里 /root/.openclaude.json 与 /root/.openclaude/settings.json
#    都被 Docker 误建成了**目录**（bind 源缺失时的老坑），openclaude 写配置会 EISDIR 且静默无输出。
#    这里给 openclaude 一个专用 HOME，绕开坏路径（不动那两个挂载，零风险）。
# ⑥ 容器内 HOME 现已是干净状态（/root/.openclaude.json 与 /root/.openclaude/settings.json
#    已由目录改回真文件 + 快照层清理，见 scripts/ensure-rt-file-binds.sh ③）。
#    正常无需覆盖 HOME；如再遇 EISDIR，可设 OPENCLAUDE_HOME 指到别处兜底。
[ -n "${OPENCLAUDE_HOME:-}" ] && { export HOME="$OPENCLAUDE_HOME"; mkdir -p "$HOME"; }
export CLAUDE_CODE_USE_OPENAI=1
export OPENAI_API_KEY="${OPENAI_API_KEY:-$DEEPSEEK_API_KEY}"
export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.deepseek.com/v1}"
export OPENAI_MODEL="${OPENAI_MODEL:-deepseek-flash}"
exec openclaude --output-format text "$@"

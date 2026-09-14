#!/bin/bash
# check-kb-stack.sh —— KB-FIRST 栈自检（重建/重启后跑一次）
# 校验：SOUL.md 常驻指令 · kb-first-lookup 技能 · kb-lookup.sh · qdrant 插件两处补丁
#       · .env 行尾 · provider 激活 · 三层可用性（Qdrant / Obsidian / Dify）
set -uo pipefail
H=/home/user/gateway/data/hermes
S=/home/user/gateway/scripts
FAIL=0
ok(){ printf '  ✅ %-30s %s\n' "$1" "$2"; }
bad(){ printf '  ❌ %-30s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
info(){ printf '  ⏭  %-30s %s\n' "$1" "$2"; }

echo "===== 1. 常驻指令与技能 ====="
if grep -q "KB-FIRST" "$H/SOUL.md" 2>/dev/null; then ok "SOUL.md KB-FIRST 段" "$(stat -c %s $H/SOUL.md)B"
else bad "SOUL.md KB-FIRST 段" "缺失（从 $H/SOUL.md.bak-* 恢复）"; fi
sk=$(find "$H/skills" -path "*kb-first-lookup*" -name SKILL.md 2>/dev/null | head -1)
if [ -n "$sk" ]; then ok "技能 kb-first-lookup" "${sk#$H/skills/}"; else bad "技能 kb-first-lookup" "缺失"; fi
if [ -x "$S/kb-lookup.sh" ]; then ok "scripts/kb-lookup.sh" "可执行"; else bad "scripts/kb-lookup.sh" "缺失/不可执行"; fi
if grep -q "docker exec -i" "$S/kb-lookup.sh" 2>/dev/null; then ok "kb-lookup.sh 带 -i" "heredoc 可用"
else bad "kb-lookup.sh 缺 -i" "会静默无输出"; fi

echo "===== 2. qdrant 插件四处补丁（卷内，重建保留；被覆盖 provider 又会坏）====="
P="$H/plugins/qdrant/__init__.py"
if [ -f "$P" ]; then
  if grep -q "https=False" "$P"; then ok "补丁① https=False" "$(grep -c 'https=False' $P) 处"
  else bad "补丁① https=False" "缺失 → SSL WRONG_VERSION_NUMBER"; fi
  if grep -q "_EMBED_MAX_CHARS" "$P"; then ok "补丁② embedding 分块" "$(grep -c '_EMBED_MAX_CHARS' $P) 处"
  else bad "补丁② embedding 分块" "缺失 → 长文本 exceed_context_size_error"; fi
  if grep -q "query_points(" "$P"; then ok "补丁③ query_points" "$(grep -c 'query_points(' $P) 处"
  else bad "补丁③ query_points" "缺失 → qdrant-client≥1.12 无 search()，自动检索静默失效"; fi
  if [ "$(grep -c '_extra_collections' "$P" 2>/dev/null || echo 0)" -ge 2 ]; then ok "补丁④ 多集合检索" "$(grep -c '_extra_collections' $P) 处"
  else bad "补丁④ 多集合检索" "缺失 → 知识库 hermes_knowledge 不参与自动检索"; fi
else bad "qdrant 插件存在" "找不到 $P"; fi
cr=$(grep -c $'\r' "$H/.env" 2>/dev/null | head -1); cr=${cr:-0}
if [ "$cr" = "0" ]; then ok ".env 行尾" "无 CR"; else bad ".env 行尾" "$cr 行带 CR"; fi

echo "===== 3. provider 与四层可用性 ====="
last_act=$(docker exec hermes sh -c "grep \"Memory provider 'qdrant' activated\" /home/agent/.hermes/logs/agent.log 2>/dev/null | tail -1 | cut -c1-19")
last_fail=$(docker exec hermes sh -c "grep 'initialize failed' /home/agent/.hermes/logs/errors.log 2>/dev/null | tail -1 | cut -c1-19")
if [ -n "$last_act" ] && { [ -z "$last_fail" ] || [[ "$last_act" > "$last_fail" ]]; }; then
  ok "memory provider" "activated 于 $last_act（最后一次失败 $last_fail）"
elif [ -n "$last_act" ]; then
  bad "memory provider" "最后失败($last_fail) 晚于最后激活($last_act)"
else
  bad "memory provider" "从未见 activated（查 errors.log 的 initialize failed）"
fi

q=$(docker exec hermes python3 /home/agent/scripts/qdrant-probe.py 2>/dev/null | tail -1)
case "$q" in
  ERR*) bad "Qdrant 可达" "$q" ;;
  "")   bad "Qdrant 可达" "无输出（查 embedding-llama / qdrant 容器）" ;;
  *)    ok "Qdrant 可达" "集合 $(echo $q|cut -d' ' -f1) 个 / hermes_memory $(echo $q|cut -d' ' -f2) 点" ;;
esac
n=$(find /home/user/gateway/data/obsidian/knowledge -name "*.md" 2>/dev/null | wc -l)
if [ "$n" -gt 0 ]; then ok "Obsidian 库" "$n 篇 md"; else bad "Obsidian 库" "0 篇"; fi
if grep -qE "^DIFY_DATASET_KEY=..*" "$H/.env" 2>/dev/null; then ok "Dify 凭据" "已配置"
else info "Dify 凭据" "未配置（/v1/datasets 401）→ 见技能 kb-first-lookup"; fi

echo
if [ "$FAIL" -gt 0 ]; then echo "❌ KB 栈有 $FAIL 项异常：KB-FIRST 无法完整生效"; exit 1; fi
echo "✅ KB 栈全部就绪：先 superpowers → 自动检索(记忆+知识) + 显式四层 → 回答带来源"

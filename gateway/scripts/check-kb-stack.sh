#!/bin/bash
# check-kb-stack.sh —— KB-FIRST 栈自检（重建/重启后跑一次）
# 校验：SOUL.md 常驻指令 · kb-first-lookup 技能 · kb-lookup.sh · qdrant 插件两处补丁
#       · .env 行尾 · provider 激活 · 三层可用性（Qdrant / Obsidian / Dify）
set -uo pipefail
# 路径自适应：既能在宿主跑，也能在容器内直接跑（两处内容等价）
if [ -f /home/user/gateway/data/hermes/config.yaml ]; then
  H=/home/user/gateway/data/hermes; S=/home/user/gateway/scripts
  ENVF=$H/.env;                    OBS=/home/user/gateway/data/obsidian/knowledge; LOC=host
else
  H=/home/agent/.hermes;           S=/home/agent/scripts
  ENVF=$H/.env;                    OBS=/knowledge_base/obsidian;                  LOC=container
fi
# DC：在「脑侧」执行一段命令 —— 宿主上跑就走 docker exec，容器内跑就直接本地执行
DC(){ if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx hermes; then docker exec hermes sh -c "$1"; else sh -c "$1"; fi; }
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
cr=$(grep -c $'\r' "$ENVF" 2>/dev/null | head -1); cr=${cr:-0}
if [ "$cr" = "0" ]; then ok ".env 行尾" "无 CR"; else bad ".env 行尾" "$cr 行带 CR"; fi

echo "===== 3. provider 与四层可用性 ====="
# 注意：agent.log 会轮转，激活行常已滚到 agent.log.1，必须搜 agent.log*（此前的误报根因）
last_act=$(DC "grep -h \"Memory provider 'qdrant' activated\" /home/agent/.hermes/logs/agent.log* 2>/dev/null | cut -c1-19 | sort | tail -1")
last_fail=$(DC "grep -h 'initialize failed' /home/agent/.hermes/logs/errors.log* 2>/dev/null | cut -c1-19 | sort | tail -1")
cfg_prov=$(grep -E '^\s*provider:\s*qdrant' "$H/config.yaml" 2>/dev/null | head -1)
if [ -n "$last_act" ] && { [ -z "$last_fail" ] || [[ "$last_act" > "$last_fail" ]]; }; then
  ok "memory provider" "activated 于 $last_act（最后一次失败 ${last_fail:-无}）"
elif [ -n "$last_act" ]; then
  bad "memory provider" "最后失败($last_fail) 晚于最后激活($last_act)"
elif [ -n "$cfg_prov" ]; then
  info "memory provider" "日志已轮转、无激活行；config 已配 qdrant 且无新失败记录（以真机实测为准）"
else
  bad "memory provider" "config.yaml 未配置 qdrant provider，且日志无激活记录"
fi

q=$(DC "python3 /home/agent/scripts/qdrant-probe.py" 2>/dev/null | tail -1)
case "$q" in
  ERR*) bad "Qdrant 可达" "$q" ;;
  "")   bad "Qdrant 可达" "无输出（查 embedding-llama / qdrant 容器）" ;;
  *)    ok "Qdrant 可达" "集合 $(echo $q|cut -d' ' -f1) 个 / hermes_memory $(echo $q|cut -d' ' -f2) 点" ;;
esac
n=$(find "$OBS" -name "*.md" 2>/dev/null | wc -l)
if [ "$n" -gt 0 ]; then ok "Obsidian 库" "$n 篇 md"; else bad "Obsidian 库" "0 篇"; fi
if grep -qE "^DIFY_DATASET_KEY=..*" "$ENVF" 2>/dev/null; then ok "Dify 凭据" "已配置"
else info "Dify 凭据" "未配置（/v1/datasets 401）→ 见技能 kb-first-lookup"; fi
# 功能性验证：凭据存在 ≠ 这层能用（2026-09-15 踩过：脚本打 127.0.0.1 静默失效，凭据检查照样绿）
dfy=$(DC "python3 /home/agent/scripts/dify-probe.py" 2>/dev/null | tail -1)
case "$dfy" in
  ERR*) bad "Dify 检索可用" "$dfy" ;;
  "")   bad "Dify 检索可用" "无输出（缺 /home/agent/scripts/dify-probe.py？）" ;;
  *)    set -- $dfy
        if [ "${2:-0}" -gt 0 ] && [ -z "${3:-}" ]; then ok "Dify 检索可用" "数据集 $1 个 / 探测命中 $2 条"
        elif [ "${2:-0}" -gt 0 ]; then ok "Dify 检索可用" "数据集 $1 个 / 命中 $2 条（$3：rerank 未生效已回退，见 §1.8 故障表）"
        else info "Dify 检索可用" "数据集 $1 个 / 探测 0 命中（层通但该查询无内容）"; fi ;;
esac

echo "===== 4. 记忆点 id 自检（防重启涨点）====="
# 判定基准=上次容器启动时刻：插件补丁写进文件后，运行中的进程要重启才生效，
# 否则会把「旧代码写的点」误报成异常（实测 2026-09-14 19:41~21:09 有 3 个 sync_turn 点属此类）。
SINCE=""
if command -v docker >/dev/null 2>&1; then
  SINCE=$(date -d "$(docker inspect -f '{{.State.StartedAt}}' hermes 2>/dev/null)" +%s 2>/dev/null || true)
fi
idv=$(DC "HERMES_RESTART_TS=${SINCE:-0} python3 /home/agent/scripts/qdrant-check-ids.py" 2>/dev/null | grep -E '判定：' | tail -1)
case "$idv" in
  *"✅"*) ok "记忆点 id 确定性" "$(echo "$idv" | sed 's/判定：//')" ;;
  "")     bad "记忆点 id 确定性" "无输出（缺 qdrant-check-ids.py？）" ;;
  *)      bad "记忆点 id 确定性" "$(echo "$idv" | sed 's/判定：//')" ;;
esac

echo "===== 5. 技能索引覆盖磁盘（用户指定：索引里没有要回磁盘找）====="
idx=$(python3 - <<'PYEOF_IDX' 2>/dev/null
import json, pathlib, re
S = pathlib.Path('/home/user/gateway/data/hermes/skills')
snap = pathlib.Path('/home/user/gateway/data/hermes/.skills_prompt_snapshot.json')
disk = set()
for f in S.rglob('SKILL.md'):
    head = f.read_text(encoding='utf-8', errors='replace')[:2000]
    m = re.search(r'^name:\s*(.+)$', head, re.M)
    disk.add(f.parent.name); disk.add(m.group(1).strip().strip('"').strip("'") if m else f.parent.name)
if snap.exists():
    d = json.loads(snap.read_text()); sk = d.get('skills') or []
    ns = {x.get('skill_name') for x in sk} | {x.get('frontmatter_name') for x in sk}
    # 磁盘有而索引无（只统计分类目录内的，顶层扁平多为回填副本）
    miss = []
    for f in S.rglob('SKILL.md'):
        if f.parent.name in ns: continue
        head = f.read_text(encoding='utf-8', errors='replace')[:2000]
        m = re.search(r'^name:\s*(.+)$', head, re.M)
        if (m.group(1).strip().strip('"').strip("'") if m else f.parent.name) in ns: continue
        miss.append(str(f.relative_to(S)))
    print("%d|%d|%s" % (len(list(S.rglob("SKILL.md"))), len(sk), ",".join(miss[:6])))
PYEOF_IDX
)
IFS='|' read -r dcount icount misses <<< "$idx"
if [ -z "${dcount:-}" ]; then info "技能索引覆盖" "无法统计（缺快照或 skills 目录）"
elif [ "${misses:-}" = "" ]; then ok "技能索引覆盖" "磁盘 ${dcount} 个技能全部在索引内（索引 ${icount} 条）"
else info "技能索引覆盖" "磁盘 ${dcount} 个 / 索引 ${icount} 条；未进索引：${misses}…（新技能需**起新会话**才进索引，可回磁盘直接读）"
fi

echo "===== 6. 插件改动是否已在运行进程生效 ====="
# 插件位于共享卷（不在镜像里）→ 「打包镜像」不会带上插件改动，只有容器启动时才重新加载。
# 因此会出现「文件已新版、进程仍旧版」的哑区（2026-09-15 补丁⑥ 就晚于容器启动 11 分钟）。
PLUG="$H/plugins/qdrant/__init__.py"
if command -v docker >/dev/null 2>&1 && [ -f "$PLUG" ]; then
  S_START=$(date -d "$(docker inspect -f '{{.State.StartedAt}}' hermes 2>/dev/null)" +%s 2>/dev/null || echo 0)
  S_MTIME=$(stat -c %Y "$PLUG" 2>/dev/null || echo 0)
  if [ "${S_MTIME:-0}" -gt "${S_START:-0}" ]; then
    bad "插件改动已生效" "插件文件比容器启动晚 $(( (S_MTIME - S_START)/60 )) 分钟 → 进程仍是旧模块，需成对重启"
  else
    ok "插件改动已生效" "插件文件早于容器启动（当前进程已加载）"
  fi
else
  info "插件改动已生效" "容器内跑时跳过（该项需宿主侧 docker inspect）"
fi

echo
if [ "$FAIL" -gt 0 ]; then echo "❌ KB 栈有 $FAIL 项异常：KB-FIRST 无法完整生效"; exit 1; fi
echo "✅ KB 栈全部就绪：先 superpowers → 自动检索(记忆+知识) + 显式四层 → 回答带来源"

#!/bin/bash
# check-wal-health.sh —— WAL 换代保护 与 数据完整性 体检（含退役归档评估）
#
# 背景：Hermes 在 halt/close 时会"换代"（把旧 WAL 退役归档到 state.db.retired-wal-<UTC时间戳>-<pid>/）。
#       若换代时**另一个活进程仍握着已删除的 WAL inode** → 触发 FATAL 保护（拒绝开写，防止铸出第二本 WAL）。
#       该事件会自愈（新世代被铸出），但要判断：① 事件是"启动前"还是"启动后"仍在发生；② 归档副本是否比活库新（决定要不要恢复）。
#
# 用法：scripts/check-wal-health.sh        （退出码非 0 = 需要人工介入）
set -uo pipefail
cd /home/user/gateway || exit 2
FAILC=0
ok(){ printf '  ✅ %-30s %s\n' "$1" "$2"; }
bad(){ printf '  ❌ %-30s %s\n' "$1" "$2"; FAILC=$((FAILC+1)); }
info(){ printf '  ⏳ %-30s %s\n' "$1" "$2"; }

# 容器内检查脚本（宿主 sqlite 缺 cjk_unicode61 分词器，必须在容器内跑）
PROBE=/opt/data/.wal-probe.py
cat > "$PROBE" <<'PY'
import sqlite3, sys
try:
    c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    q = c.execute("pragma quick_check").fetchone()[0]
    j = c.execute("pragma journal_mode").fetchone()[0]
    n = c.execute("select count(*) from messages").fetchone()[0]
    print(f"{q}|{j}|{n}")
except Exception as e:
    print(f"ERR|{e}|-1")
PY

for pair in "hermes:/home/agent/.hermes" "hermes-webui:/home/agent/.hermes-rt"; do
  CTR="${pair%%:*}"; HOME_IN="${pair##*:}"
  HOST_DIR=$([ "$CTR" = hermes ] && echo data/hermes || echo data/hermes-runtime)
  echo "===== $CTR ($HOME_IN) ====="
  START=$(docker inspect "$CTR" --format '{{.State.StartedAt}}' | tr -d 'Z' | tr 'T' ' ')
  echo "  容器启动(UTC): $START"

  # ① 已删除 inode 是否仍被持有（应为 0）
  HOLD=$(docker exec "$CTR" bash -c 'for p in /proc/[0-9]*; do ls -l "$p/fd" 2>/dev/null | grep -q "state.db.*(deleted)" && echo x; done | wc -l' 2>/dev/null)
  [ "${HOLD:-0}" = "0" ] && ok "已删除 inode 持有" "0" || bad "已删除 inode 持有" "$HOLD 个进程仍握着"

  # ② 正常持有者（应恰好 1 个 = gateway/bridge）
  N=$(docker exec "$CTR" bash -c 'for p in /proc/[0-9]*; do ls -l "$p/fd" 2>/dev/null | grep -q "state.db-wal" && echo x; done | wc -l' 2>/dev/null)
  [ "${N:-0}" -le 1 ] && ok "state.db 写者数" "$N" || info "state.db 写者数" "$N（桥+子进程并存属正常，注意换代时是否有子进程存活）"

  # ③ FATAL 是否在容器启动之后仍出现
  LAST=$(grep -h "Refusing to open or write" "$HOST_DIR/logs/errors.log" 2>/dev/null | tail -1 | grep -oE "^[0-9-]+ [0-9:]+")
  CNT=$(grep -hc "Refusing to open or write" "$HOST_DIR/logs/errors.log" 2>/dev/null)
  if [ -z "$LAST" ]; then
    ok "WAL 保护告警" "从未触发"
  elif [ "$LAST" \> "$START" ]; then
    bad "WAL 保护告警" "最近一次 $LAST **晚于**容器启动 $START（仍在发生）"
  else
    ok "WAL 保护告警" "累计 $CNT 次，最近 $LAST（早于容器启动 → 已自愈）"
  fi

  # ④ 退役归档 vs 活库：谁更新
  ARCH=$(ls -1dt "$HOST_DIR"/state.db.retired-wal-* 2>/dev/null | head -1)
  LIVE=$(docker exec "$CTR" /opt/hermes/.venv/bin/python /opt/data/.wal-probe.py "$HOME_IN/state.db" 2>/dev/null)
  if [ -n "$ARCH" ]; then
    A=$(docker exec "$CTR" /opt/hermes/.venv/bin/python /opt/data/.wal-probe.py "$HOME_IN/${ARCH#$HOST_DIR/}/state.db" 2>/dev/null)
    LN=$(echo "$LIVE" | cut -d'|' -f3); AN=$(echo "$A" | cut -d'|' -f3)
    if [ "${AN:-0}" -le "${LN:-0}" ]; then
      ok "最新归档 vs 活库" "归档 ${AN} 条 ≤ 活库 ${LN} 条 → 归档是旧世代，无需恢复"
    else
      bad "最新归档 vs 活库" "归档 ${AN} 条 > 活库 ${LN} 条 → 可能丢数据，用 hermes sessions recover --inspect-only 评估"
    fi
  else
    info "退役归档" "无"
  fi
  echo "    活库: quick_check|journal|messages = $LIVE"
done
rm -f "$PROBE"
echo
[ "$FAILC" -gt 0 ] && { echo "❌ 有 $FAILC 项需要介入"; exit 1; } || { echo "✅ WAL/完整性体检通过"; exit 0; }

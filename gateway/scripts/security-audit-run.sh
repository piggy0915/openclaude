#!/bin/bash
# ============================================================================
# 安全审计定期运行器（内置 + 全局盲区补充）—— 2026-09-20 落地
# ----------------------------------------------------------------------------
# 覆盖三层：
#   ① 内置   `hermes security audit --json`（venv / 插件依赖 / config.yaml 里 pin 的 npx·uvx）
#   ② 盲区补 全局 npm 包（/usr/local + /opt/data/npm-global）与 pip 工具 → OSV.dev 批量查询
#   ③ 深扫    pip-audit（venv site-packages）+ Bandit（本栈自有脚本与插件）
# 产物：/opt/data/security-audit/<日期>/（= 宿主 data/opt-data/security-audit/<日期>/）
#   容器与宿主同路径可见，无需 docker cp。
# 退出码恒 0（cron 友好）；失败写审计日志。
# ============================================================================
set -u

BASE=/home/user/gateway
CTR=hermes
OUT_ROOT=/opt/data/security-audit                 # 卷内路径（容器/宿主同路径）
DAY=$(date +%F)
TS=$(date +%Y%m%d-%H%M%S)
OUT="$OUT_ROOT/$DAY"
LOG="$OUT_ROOT/audit.log"
JQ=/opt/data/bin/jq
OSV_HELPER=/opt/data/scripts/security-audit-osv.py
# venv site-packages 路径随 Python 版本变化（3.13→3.14 时曾硬编码失效）→ 动态取
VENV_SITE=$(docker exec "$CTR" sh -c 'ls -d /opt/hermes/.venv/lib/python3.*/site-packages 2>/dev/null | head -1')
[ -n "$VENV_SITE" ] || VENV_SITE=/opt/hermes/.venv/lib/python3.14/site-packages

mkdir -p "$OUT"; chmod 700 "$OUT_ROOT" 2>/dev/null

note() { printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }
[ -f "$LOG" ] && { tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }

note "── 开始审计（$TS）"

# ---------------------------------------------------------------- ① 内置
docker exec "$CTR" sh -c '/opt/hermes/.venv/bin/hermes security audit --json' \
      > "$OUT/hermes-security-audit.json" 2>"$OUT/hermes-security-audit.err"
RC=$?
BUILTIN=$($JQ -r 'if type=="object" then ((.findings//.results//[])|length) else 0 end' \
          "$OUT/hermes-security-audit.json" 2>/dev/null || echo "?")
if [ -s "$OUT/hermes-security-audit.json" ] && [ "$BUILTIN" != "?" ]; then
    # 实测：CLI 只要**有发现**就返回 1 —— exit=1 属正常，不是失败
    note "① 内置审计 完成（exit=$RC；有发现即返回 1，findings=$BUILTIN）"
else
    note "① 内置审计 失败（exit=$RC，JSON 空或不可解析，见 hermes-security-audit.err）"
fi

# ------------------------------------------------- ② 全局依赖 → OSV（盲区）
docker exec "$CTR" sh -c '/opt/hermes/.venv/bin/python -m pip list --format=json' \
      > "$OUT/pip-list.json" 2>/dev/null || true
if docker exec "$CTR" sh -c "python3 $OSV_HELPER \
        --npm-root /opt/data/npm-global/lib/node_modules \
        --npm-root /usr/local/lib/node_modules \
        --pip-json $OUT/pip-list.json \
        --pip-site /usr/local/lib/python3.13/dist-packages \
        --pip-site /usr/lib/python3/dist-packages \
        --pip-site /opt/data/uv-tools \
        --out-json $OUT/global-deps-osv.json" >> "$LOG" 2>&1; then
    note "② 全局依赖 OSV 查询 完成"
else
    note "② 全局依赖 OSV 查询 失败（见 audit.log 上一行）"
fi
GC=$($JQ -r '.by_severity.CRITICAL // 0' "$OUT/global-deps-osv.json" 2>/dev/null || echo 0)
GH=$($JQ -r '.by_severity.HIGH // 0'     "$OUT/global-deps-osv.json" 2>/dev/null || echo 0)
GP=$($JQ -r '.vulnerable_packages // 0'  "$OUT/global-deps-osv.json" 2>/dev/null || echo 0)
GN=$($JQ -r '.scanned_packages // 0'     "$OUT/global-deps-osv.json" 2>/dev/null || echo 0)

# ---------------------------------------------------------------- ③ pip-audit
docker exec "$CTR" sh -c "if [ -d $VENV_SITE ]; then pip-audit --path $VENV_SITE -f json -o $OUT/pip-audit.json 2>$OUT/pip-audit.err && echo ok; else echo 'no site-packages'; fi" \
    > "$OUT/pip-audit.status" 2>&1 || true
# pip-audit -f json 实测输出 `{dependencies:[{name,version,vulns:[]}], fixes:[]}`（不是数组）
PA=$($JQ -r 'if type=="array" then ([.[]|(.vulns//[])|length]|add // 0)
             elif (.dependencies?|type)=="array" then ([.dependencies[]|(.vulns//[])|length]|add // 0)
             else ((.vulnerabilities//[])|length) end' "$OUT/pip-audit.json" 2>/dev/null || echo "?")
PV=$($JQ -r '[.dependencies[]?|select((.vulns//[])|length>0)]|length' "$OUT/pip-audit.json" 2>/dev/null || echo "?")
note "③ pip-audit 完成（漏洞 $PA 条 / $PV 个包）"

# ------------------------------------------------------------------ ④ Bandit
if [ -x /opt/data/bin/bandit ]; then
    # 注意：宿主的 tool venv 解释器是 /usr/bin/python3；容器内调用工具时要清 PYTHONPATH
    #（否则 Hermes venv 的 site-packages 会泄漏进工具进程，semgrep 会 import 到不兼容的 mcp 包）
    PYTHONPATH= /opt/data/bin/bandit -q -r "$BASE/scripts" "$BASE/data/hermes/plugins" \
        -f json -o "$OUT/bandit.json" > "$OUT/bandit.out" 2>&1 || true
    BA=$($JQ -r '(.results|length) // 0' "$OUT/bandit.json" 2>/dev/null || echo "?")
    note "④ Bandit 完成（findings=$BA）"
else
    BA="n/a"; note "④ Bandit 不可用（/opt/data/bin/bandit 缺失）"
fi

# ------------------------------------------------------------------ ⑤ 汇总
{
    echo "# 安全审计摘要 $DAY $TS"
    echo
    echo "| 层 | 结果 |"
    echo "|---|---|"
    echo "| ① 内置（venv/插件/MCP pin） | findings = $BUILTIN |"
    echo "| ② 全局依赖（OSV 直查） | 扫描 $GN 个包；$GP 个包命中；CRITICAL $GC / HIGH $GH |"
    echo "| ③ pip-audit（venv site-packages，PyPI 公告库） | 漏洞 $PA 条 / $PV 个包 |"
    echo "| ④ Bandit（本栈脚本/插件） | findings = $BA |"
    echo
    echo "产物：$(ls -1 "$OUT" | tr '\n' ' ')"
    echo
    if [ "$GP" != "0" ] && [ -f "$OUT/global-deps-osv.json" ]; then
        echo "## ② 全局依赖命中（按严重度）"
        $JQ -r '.results[] | "  - [\(.severity)] \(.name)@\(.version)  \(.id)  \(.summary[0:100])"' \
            "$OUT/global-deps-osv.json" 2>/dev/null | head -40
    fi
} > "$OUT/SUMMARY.md" 2>/dev/null

printf '%s  内置=%s  全局包=%s(命中%s/C%s/H%s)  pip-audit=%s  bandit=%s\n' \
    "$(date '+%F %T')" "$BUILTIN" "$GN" "$GP" "$GC" "$GH" "$PA($PV包)" "$BA" >> "$OUT_ROOT/trend.log"
{
    printf 'last_run : %s\n' "$(date '+%F %T')"
    printf 'dir      : %s\n' "$OUT"
} > "$OUT_ROOT/.last-run"
chmod 600 "$OUT_ROOT/.last-run" "$OUT_ROOT/trend.log" 2>/dev/null

note "── 结束审计（结果：内置=$BUILTIN 全局命中=$GP pip-audit=$PA bandit=$BA）"
echo "审计完成：$OUT/SUMMARY.md"
exit 0

#!/bin/bash
# ============================================================================
# 重建后核验（一条命令跑完）—— 2026-09-20
# 覆盖：镜像钉版是否生效 / 引导链路 / 浏览器两条链 / 安全工具 / MCP / 回归项
# 用法： bash scripts/post-rebuild-verify.sh
# ============================================================================
set -u
CTR=hermes
WUI=hermes-webui
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31m✗\033[0m %s\n' "$1"; }
info(){ printf '    %s\n' "$1"; }

echo "=== 0) 镜像与容器 ==="
docker images --format '  {{.Repository}}:{{.Tag}}  {{.ID}}  {{.CreatedSince}}' | grep -E 'hermes-base|hermes-agent|hermes-web-ui'
docker ps --format '  {{.Names}}  {{.Status}}' | grep hermes

echo
echo "=== 1) 镜像钉版（本轮应有：ocr 1.12.9 / crawl4ai≥0.9.3 / anyio≥4.14.2 / pip≥26.2.0 / dev-browser 0.2.9）==="
docker exec $CTR sh -c '
  printf "  ocr        : "; ocr --version 2>/dev/null | head -1
  /opt/hermes/.venv/bin/python - <<PY
import importlib.metadata as m
for p,minv in (("crawl4ai",(0,9,3)),("anyio",(4,14,2)),("pip",(26,2,0))):
    try:
        v=m.version(p)
    except Exception:
        print(f"  {p:<11}: 未安装"); continue
    t=tuple(int(x) for x in v.split(".")[:3])
    ok = "达标" if t>=minv else "低于 " + ".".join(str(x) for x in minv)
    print(f"  {p:<11}: {v}  {ok}")
PY
  printf "  dev-browser: "; command -v dev-browser || echo "未找到"
  printf "  dev-browser 版本: "
  /opt/hermes/.venv/bin/python - <<PY
import json
print(json.load(open("/usr/local/lib/node_modules/dev-browser/package.json"))["version"])
PY
  printf "  状态目录(镜像内): "; ls -d $HOME/.dev-browser >/dev/null 2>&1 && du -sh $HOME/.dev-browser | cut -f1 || echo "缺失"
'

echo
echo "=== 2) 引导日志（dev-browser 那行应消失）==="
docker logs $CTR 2>&1 | grep '\[coding-agents\]' | tail -6 | sed 's/^/  hermes: /'
docker logs $WUI 2>&1 | grep '\[coding-agents\]' | tail -6 | sed 's/^/  webui : /'

echo
echo "=== 3) 浏览器两条链 ==="
docker exec $CTR sh -c 'curl -s -m 5 http://127.0.0.1:9222/json/version | head -c 60; echo' | sed 's/^/  CDP Chrome: /'
docker exec $CTR sh -c 'export PATH=/opt/data/npm-global/bin:$PATH; printf "%s\n" "const p = await browser.getPage(\"m\");" "await p.goto(\"about:blank\");" "console.log(\"dev-browser OK\", await p.title());" > /tmp/v.js; timeout 120 dev-browser --headless run /tmp/v.js 2>&1 | tail -1' | sed 's/^/  /'
systemctl is-active bsk-daemon 2>/dev/null | sed 's/^/  bsk-daemon: /'
BSK_HOME=/opt/data/bsk-home BSK_AUTO_START=0 bsk browsers --json 2>/dev/null | grep -E 'browser_name|instance_id' | sed 's/^/  bsk: /'

echo
echo "=== 4) 安全工具四件套（容器内清 PYTHONPATH）==="
  docker exec $CTR sh -c 'for b in pip-audit bandit semgrep jq; do printf "  %-10s " $b; env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy PYTHONPATH= $b --version 2>/dev/null | head -1; done'

echo
echo "=== 5) 回归项 ==="
docker exec $CTR sh -c '
  printf "  codegraph : "; CODEGRAPH_NO_DOWNLOAD=1 codegraph --version 2>&1 | head -1
  printf "  node      : "; node -v
  printf "  playwright: "; npx --no-install playwright --version 2>&1 | head -1
  printf "  yt-dlp    : "; /opt/hermes/.venv/bin/yt-dlp --version 2>/dev/null | head -1
  printf "  whisper   : "; du -sh /opt/hermes/.whisper 2>/dev/null | cut -f1
  printf "  MCP       : "; grep -hoE "MCP: registered [0-9]+ tool\(s\) from [0-9]+ server\(s\)" $(ls -t /home/agent/.hermes/logs/*.log | head -2) 2>/dev/null | tail -1
'
echo
echo
echo "=== 6) GhidraMCP 栈（agent 无头逆向）==="
systemctl is-active ghidra-mcp 2>/dev/null | sed 's/^/  ghidra-mcp       : /'
systemctl is-active ghidra-mcp-bridge 2>/dev/null | sed 's/^/  ghidra-mcp-bridge: /'
printf "  服务端探活       : "; curl -s -m 5 http://127.0.0.1:8089/check_connection | head -c 60; echo
printf "  配置条目         : "; grep -c 'ghidra-mcp:' data/hermes/config.yaml 2>/dev/null || grep -c 'ghidra-mcp:' /home/user/gateway/data/hermes/config.yaml
docker exec $CTR python3 /opt/data/ghidra-mcp/probe-http.py 2>&1 | sed 's/^/  容器侧: /'
echo "（审计趋势可看： tail -3 /opt/data/security-audit/trend.log）"
exit 0

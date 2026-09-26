#!/usr/bin/env bash
# GhidraMCP headless server（VM 侧）—— 参照官方 docker/entrypoint.sh
set -euo pipefail
GHIDRA_HOME="${GHIDRA_HOME:-/opt/data/ghidra/ghidra_12.1.3_PUBLIC}"
JAVA_HOME="${JAVA_HOME:-/opt/data/jdk/jdk-25.0.4.1+1}"
export JAVA_HOME
PORT="${GHIDRA_MCP_PORT:-8089}"
BIND="${GHIDRA_MCP_BIND_ADDRESS:-0.0.0.0}"
JAVA_OPTS="${JAVA_OPTS:--Xmx4g -XX:+UseG1GC}"

JAR="$GHIDRA_HOME/Ghidra/Extensions/GhidraMCP/lib/GhidraMCP-6.0.0.jar"
[ -f "$JAR" ] || { echo "找不到扩展 jar: $JAR"; exit 1; }

CP="$JAR"
for d in "$GHIDRA_HOME"/Ghidra/Framework/*/lib "$GHIDRA_HOME"/Ghidra/Features/*/lib "$GHIDRA_HOME"/Ghidra/Processors/*/lib; do
  for j in "$d"/*.jar; do [ -f "$j" ] && CP="$CP:$j"; done
done

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/opt/data/ghidra-config}"
mkdir -p /opt/data/ghidra-mcp/projects

exec "$JAVA_HOME/bin/java" $JAVA_OPTS -Dghidra.home="$GHIDRA_HOME" -Dapplication.name=GhidraMCP \
  -classpath "$CP" com.xebyte.headless.GhidraMCPHeadlessServer --port "$PORT" --bind "$BIND" "$@"

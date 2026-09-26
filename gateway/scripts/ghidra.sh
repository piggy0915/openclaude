#!/bin/bash
# ============================================================================
# Ghidra 无头封装（本栈自包含：/opt/data/jdk（JDK 25）+ /opt/data/ghidra（12.1.3））
# 放在共享卷上 → 宿主与两个容器都能用，镜像重建不丢。
# 用法：
#   ghidra.sh info                             显示 JDK/Ghidra 路径与版本
#   ghidra.sh decompile <binary> [regex] [max] 快速反编译（默认匹配 main，最多 5 个函数）
#   ghidra.sh analyze <PROJ_DIR> <NAME> …      透传 analyzeHeadless（完整参数）
# 说明：Ghidra 12.1.3 需要 **JDK 25**（官方 README 要求；Win11 现有的 JDK 21 不够）。
# ============================================================================
set -u

GH_ROOT=${GH_ROOT:-/opt/data/ghidra}
JDK_ROOT=${JDK_ROOT:-/opt/data/jdk}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

JDK="$(ls -d "$JDK_ROOT"/jdk-* 2>/dev/null | sort -V | tail -1)"
GH="$(ls -d "$GH_ROOT"/ghidra_*_PUBLIC 2>/dev/null | sort -V | tail -1)"

if [ -n "${JDK:-}" ]; then export JAVA_HOME="$JDK"; export PATH="$JDK/bin:$PATH"; fi
# Ghidra 的用户设置/扩展目录跟 XDG_CONFIG_HOME 走（实测有效）→ 指到共享卷，重建不丢扩展
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/opt/data/ghidra-config}"
mkdir -p "$XDG_CONFIG_HOME" 2>/dev/null || true
HS="${GH:-}/support/analyzeHeadless"

usage() {
cat <<EOF
用法:
  $(basename "$0") info                          显示 JDK/Ghidra 版本与路径
  $(basename "$0") decompile <binary> [regex]    快速反编译（默认 main，最多 5 个函数）
  $(basename "$0") analyze <PROJ_DIR> <NAME> …   透传 analyzeHeadless 全部参数
示例:
  $(basename "$0") decompile /bin/ls 'main|check'
  $(basename "$0") analyze /tmp/p proj1 -import /bin/ls -postScript DecompileSelected.java main -scriptPath $SCRIPT_DIR -deleteProject
EOF
}

case "${1:-}" in
  info)
    echo "JAVA_HOME=${JAVA_HOME:-未找到}"
    java -version 2>&1 | head -2 | sed 's/^/  /'
    echo "GHIDRA=${GH:-未找到}"
    [ -n "${GH:-}" ] && ls "$GH" | head -6 | sed 's/^/  /'
    ;;
  analyze)
    shift
    [ -x "$HS" ] || { echo "✗ analyzeHeadless 未找到（$HS）"; exit 2; }
    exec "$HS" "$@"
    ;;
  decompile)
    BIN="${2:-}"; RX="${3:-main}"; MAX="${4:-5}"
    [ -n "$BIN" ] && [ -f "$BIN" ] || { echo "✗ 用法: $0 decompile <binary> [regex] [max]"; exit 2; }
    [ -x "$HS" ] || { echo "✗ analyzeHeadless 未找到（$HS）"; exit 2; }
    PROJ="$(mktemp -d /tmp/ghidra-proj.XXXXXX)"
    echo "  项目目录: $PROJ   目标: $BIN   匹配: $RX"
    # Ghidra 自身日志分流到文件，stdout 留给 post-script 的输出（更干净）
    "$HS" "$PROJ" hermesproj -import "$BIN" \
        -postScript DecompileSelected.java "$RX" "$MAX" \
        -scriptPath "$SCRIPT_DIR" -log "$PROJ/ghidra.log" -deleteProject
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "  ✗ analyzeHeadless 退出码 $rc，日志尾部："
        tail -15 "$PROJ/ghidra.log" 2>/dev/null | sed 's/^/     /'
    fi
    rm -rf "$PROJ"
    exit $rc
    ;;
  *) usage ;;
esac

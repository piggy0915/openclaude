#!/bin/bash
# 插件安装辅助脚本
# 位置：./data/hermes/scripts/install-plugin.sh

PLUGIN_NAME=$1
PLUGIN_SOURCE=$2

if [ -z "$PLUGIN_NAME" ]; then
    echo "Usage: ./install-plugin.sh <plugin-name> [plugin-source]"
    echo ""
    echo "Examples:"
    echo "  ./install-plugin.sh superpower"
    echo "  ./install-plugin.sh superpower /opt/plugins/local-plugin"
    echo "  ./install-plugin.sh superpower git+https://github.com/user/superpower.git"
    echo ""
    echo "Note: Plugin source can be:"
    echo "  - PyPI package name"
    echo "  - Local directory path (will be copied to ./data/hermes/plugins/)"
    echo "  - Git repository URL"
    exit 1
fi

# 如果是本地目录，先复制到持久化目录
if [ -n "$PLUGIN_SOURCE" ] && [ -d "$PLUGIN_SOURCE" ]; then
    echo "📁 Copying plugin from $PLUGIN_SOURCE to ./data/hermes/plugins/$PLUGIN_NAME"
    cp -r "$PLUGIN_SOURCE" "./data/hermes/plugins/$PLUGIN_NAME"
    PLUGIN_SOURCE="/opt/plugins/$PLUGIN_NAME"
fi

echo "🔧 Installing plugin: $PLUGIN_NAME"

if [ -n "$PLUGIN_SOURCE" ]; then
    # 从指定源安装
    docker exec -it hermes bash -c "
        source /opt/hermes/.venv/bin/activate 2>/dev/null || true &&
        pip install $PLUGIN_SOURCE
    "
else
    # 尝试从 PyPI 安装
    docker exec -it hermes bash -c "
        source /opt/hermes/.venv/bin/activate 2>/dev/null || true &&
        pip install $PLUGIN_NAME
    "
fi

if [ $? -eq 0 ]; then
    echo "✅ Plugin $PLUGIN_NAME installed successfully!"
    echo "🔄 Restart hermes container to apply: docker-compose restart hermes"
else
    echo "❌ Failed to install plugin $PLUGIN_NAME"
    exit 1
fi
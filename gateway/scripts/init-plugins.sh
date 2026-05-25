#!/bin/bash
# Hermes 插件初始化脚本
# 位置：./data/hermes/scripts/init-plugins.sh

set -e

echo "========================================="
echo "Initializing Hermes Plugins..."
echo "========================================="

# 激活虚拟环境
if [ -f "/opt/hermes/.venv/bin/activate" ]; then
    source /opt/hermes/.venv/bin/activate
else
    echo "⚠️  Virtual environment not found, creating..."
    python3 -m venv /opt/hermes/.venv
    source /opt/hermes/.venv/bin/activate
fi

# 创建必要的目录
mkdir -p /root/.claude/plugins
mkdir -p /opt/plugins

# 升级 pip
pip install --upgrade pip

# ===========================================
# 插件安装区域
# ===========================================

# 方式1：如果有 Python 包，直接 pip 安装
# pip install claude-superpower

# 方式2：从本地目录安装（插件放在 ./data/hermes/plugins/ 中）
if [ -d "/opt/plugins/superpower" ] && [ -f "/opt/plugins/superpower/setup.py" ]; then
    echo "📦 Installing superpower from local directory..."
    cd /opt/plugins/superpower
    pip install -e .
    echo "✓ superpower installed from local source"
fi

# 方式3：从 wheel 文件安装
if ls /opt/plugins/*.whl 1> /dev/null 2>&1; then
    echo "📦 Installing plugins from wheel files..."
    pip install /opt/plugins/*.whl
fi

# 方式4：复制预构建的插件到 Claude 目录
if [ -d "/opt/plugins/superpower-dist" ]; then
    echo "📁 Copying superpower distribution to Claude plugins directory..."
    cp -r /opt/plugins/superpower-dist/* /root/.claude/plugins/ 2>/dev/null || true
    echo "✓ superpower distribution copied"
fi

# ===========================================
# 验证插件安装
# ===========================================
echo ""
echo "📋 Installed Python packages:"
pip list | grep -E "(superpower|claude|hermes)" || echo "  No plugin-related packages found"

echo ""
echo "📁 Plugin directory contents:"
ls -la /root/.claude/plugins/ 2>/dev/null || echo "  No plugins in Claude directory"

echo ""
echo "========================================="
echo "✓ Plugin initialization complete!"
echo "========================================="
#!/bin/bash
set -e

echo "=== Running custom entrypoint script ==="

# 确保全局包的命令可用
if [ -f /usr/local/lib/node_modules/@gitlawb/openclaude/bin/openclaude ]; then
    echo "Creating symlink for openclaude..."
    ln -sf /usr/local/lib/node_modules/@gitlawb/openclaude/bin/openclaude /usr/local/bin/openclaude
fi

# 创建 reasonix 符号链接（正确路径）
if [ -f /usr/local/lib/node_modules/reasonix/dist/cli/index.js ]; then
    echo "Creating symlink for reasonix..."
    ln -sf /usr/local/lib/node_modules/reasonix/dist/cli/index.js /usr/local/bin/reasonix
    chmod +x /usr/local/bin/reasonix
    echo "✓ reasonix symlink created from dist/cli/index.js"
else
    echo "⚠ reasonix not found at expected path"
fi

# 显示 PATH 中的命令
echo "Available commands:"
ls -la /usr/local/bin/ | grep -E "openclaude|reasonix" || echo "  (none found)"

echo "=== Entrypoint script completed ==="

# 执行传入的命令（重要！）
exec "$@"
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

# 2. 关键：把 SSH 私钥从 root 目录复制到 hermes 用户可访问的位置
#    因为 docker-compose 把密钥挂载到了 /root/.ssh/，但 Gateway 以 UID 10000 运行
if [ -f /root/.ssh/id_rsa_hermes ]; then
    echo "Setting up SSH key for hermes user..."
    mkdir -p /home/agent/.ssh
    cp /root/.ssh/id_rsa_hermes /home/agent/.ssh/
    # 归属改为 hermes (10000)，权限设为 600
    chown -R 10000:10000 /home/agent/.ssh
    chmod 700 /home/agent/.ssh
    chmod 600 /home/agent/.ssh/id_rsa_hermes
    echo "✓ SSH key ready at /home/agent/.ssh/id_rsa_hermes"
else
    echo "⚠ SSH key not found at /root/.ssh/id_rsa_hermes"
fi

echo "=== Entrypoint script completed ==="

# 执行传入的命令（重要！）
exec "$@"
#!/bin/bash
set -e

echo "=== Running custom entrypoint script ==="
echo "=== Running as user: $(whoami) (UID: $(id -u)) ==="

# 如果以 root 运行，修复权限
if [ "$(id -u)" = "0" ]; then
    echo "=== Fixing permissions (running as root) ==="
    
    # 修复 /home/agent 目录权限
    if [ -d "/home/agent" ]; then
        # 修复所有权
        chown -R 10000:10000 /home/agent 2>/dev/null || true
        
        # 设置目录权限
        chmod -R 775 /home/agent 2>/dev/null || true
        chmod -R 775 /home/agent/.hermes 2>/dev/null || true
        
        # 日志和会话目录需要写权限
        find /home/agent -type d \( -name "logs" -o -name "sessions" \) -exec chmod 775 {} \; 2>/dev/null || true
        find /home/agent -path "*/.hermes/logs" -type d -exec chmod 775 {} \; 2>/dev/null || true

        # 清理锁文件
        find /home/agent -name "*.lock" -type f -delete 2>/dev/null || true
        find /home/agent -name "*.db-wal" -type f -delete 2>/dev/null || true
        
        # SSH 密钥特殊权限
        if [ -f /home/agent/.ssh/id_rsa_hermes ]; then
            chmod 600 /home/agent/.ssh/id_rsa_hermes
        fi

        echo "✓ Permissions fixed"
    fi
fi

# SSH 密钥配置（如果从 root 复制）
if [ -f /root/.ssh/id_rsa_hermes ] && [ ! -f /home/agent/.ssh/id_rsa_hermes ]; then
    echo "Setting up SSH key for hermes user..."
    mkdir -p /home/agent/.ssh
    cp /root/.ssh/id_rsa_hermes* /home/agent/.ssh/ 2>/dev/null
    cp /root/.ssh/known_hosts /home/agent/.ssh/ 2>/dev/null
    chown -R 10000:10000 /home/agent/.ssh 2>/dev/null
    chmod 700 /home/agent/.ssh
    chmod 600 /home/agent/.ssh/id_rsa_hermes 2>/dev/null
    echo "✓ SSH key configured"
fi

# 确保全局包的命令可用
if [ -f /usr/lib/node_modules/@gitlawb/openclaude/bin/openclaude ]; then
    echo "Creating symlink for openclaude..."
    ln -sf /usr/lib/node_modules/@gitlawb/openclaude/bin/openclaude /usr/bin/openclaude
else
    echo "⚠ openclaude not found at expected path"
fi

# 创建 reasonix 符号链接（正确路径）
if [ -f /usr/lib/node_modules/reasonix/dist/cli/index.js ]; then
    echo "Creating symlink for reasonix..."
    ln -sf /usr/lib/node_modules/reasonix/dist/cli/index.js /usr/bin/reasonix
    chmod +x /usr/bin/reasonix
    echo "✓ reasonix symlink created from dist/cli/index.js"
else
    echo "⚠ reasonix not found at expected path"
fi

echo "=== Starting Hermes Gateway ==="
exec hermes gateway run

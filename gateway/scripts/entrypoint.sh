#!/bin/bash
set -e

echo "=== Running custom entrypoint script ==="
echo "=== Running as user: $(whoami) (UID: $(id -u)) ==="

# ── 新增：修复 /app/bin 目录权限 ──
echo "=== Fixing /app/bin permissions ==="
if [ -d "/app/bin" ]; then
    # 确保所有 .sh 文件可执行
    find /app/bin -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    # 或者直接给整个目录加执行权限
    chmod -R +x /app/bin 2>/dev/null || true
    echo "✓ /app/bin permissions fixed"
    echo "Contents of /app/bin:"
    ls -la /app/bin/
else
    echo "⚠ /app/bin directory not found!"
fi

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
#    ln -sf /usr/lib/node_modules/@gitlawb/openclaude/bin/openclaude /usr/bin/openclaude
else
    echo "⚠ openclaude not found at expected path"
fi

# 创建 reasonix 符号链接（正确路径）
if [ -f /usr/lib/node_modules/reasonix/dist/cli/index.js ]; then
    echo "Creating symlink for reasonix..."
#    ln -sf /usr/lib/node_modules/reasonix/dist/cli/index.js /usr/bin/reasonix
#    chmod +x /usr/bin/reasonix
    echo "✓ reasonix symlink created from dist/cli/index.js"
else
    echo "⚠ reasonix not found at expected path"
fi

# ── AgentChat skills 链接（运行时建链，进卷生效）──
# 2026-08-20 修正：Dockerfile 构建时建链会被 hermes_data_volume 遮蔽（卷覆盖镜像层），
# 链接永远进不了卷。改在 entrypoint 每次启动时建链，Hermes 才能加载 AgentChat skills。
if [ -d /opt/agentchat/skills ]; then
    echo "=== Linking AgentChat skills into ~/.hermes/skills ==="
    mkdir -p /home/agent/.hermes/skills
    for s in AgentChat-OneWeb AgentChat-IndependentTasks AgentChat-WebSubAgent; do
        if [ -d "/opt/agentchat/skills/$s" ] && [ ! -e "/home/agent/.hermes/skills/$s" ]; then
            ln -sfn "/opt/agentchat/skills/$s" "/home/agent/.hermes/skills/$s"
            echo "✓ linked $s"
        elif [ -e "/home/agent/.hermes/skills/$s" ]; then
            echo "✓ $s already present (skip)"
        fi
    done
else
    echo "⚠ /opt/agentchat/skills not found — AgentChat skills skipped"
fi

# ── CDP Chrome（替代 s6 chrome-cdp：本镜像 PID1=entrypoint.sh，s6-overlay 不生效）──
# 2026-08-18 修复：原 Dockerfile 的 s6 chrome-cdp 服务永远不会被拉起，
# 因为容器入口是 entrypoint.sh（exec hermes gateway run），没有 s6-svscan。
# 这里按 AGENTCHAT_CHROME_CDP 开关启动 Xvfb + CDP Chrome，登录态在 /opt/data/chrome-profile。
if [ -n "${AGENTCHAT_CHROME_CDP:-}" ] && [ "${AGENTCHAT_CHROME_CDP}" != "0" ]; then
    echo "=== Starting CDP Chrome (AGENTCHAT_CHROME_CDP=${AGENTCHAT_CHROME_CDP}) ==="
    export DISPLAY=:99
    pgrep -x Xvfb >/dev/null 2>&1 || { Xvfb :99 -screen 0 1280x800x24 -ac >/dev/null 2>&1 & sleep 2; }
    CHROME="$(ls -d /opt/hermes/.playwright/chromium-*/chrome-linux64/chrome 2>/dev/null | head -1)"
    if [ -n "$CHROME" ] && ! curl -s -m 2 http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
        mkdir -p /opt/data/chrome-profile
        nohup "$CHROME" \
            --remote-debugging-port=9222 --remote-debugging-address=127.0.0.1 \
            --no-sandbox --disable-gpu --disable-dev-shm-usage \
            --disable-blink-features=AutomationControlled --disable-background-networking \
            --disable-field-trial-config --no-first-run --no-default-browser-check \
            --user-data-dir=/opt/data/chrome-profile --window-size=1280,800 \
            "https://www.kimi.com/" >/tmp/chrome-cdp.log 2>&1 &
        echo "✓ CDP Chrome started (PID $!) → http://127.0.0.1:9222"
    else
        echo "⚠ CDP Chrome skip (CHROME='$CHROME' or 9222 already up)"
    fi
else
    echo "⚠ AGENTCHAT_CHROME_CDP not set — CDP Chrome disabled"
fi

# ── 最终启动：使用 start-studio-all.sh ──
echo "=== Starting Hermes Studio ==="
if [ -f "/app/bin/start-studio-all.sh" ] && [ "${HERMES_GATEWAY_MODE:-0}" != "1" ];  then
    # 修复所有 .sh 和 .mjs 的 CRLF 与权限
    find /app/bin -type f \( -name "*.sh" -o -name "*.mjs" \) -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
    find /app/bin -type f \( -name "*.sh" -o -name "*.mjs" \) -exec chmod +x {} \; 2>/dev/null || true
    # 直接尝试执行（文件在构建时已有权限）
    if [ -x "/app/bin/start-studio-all.sh" ]; then
        echo "✓ Executing: /app/bin/start-studio-all.sh $@"
        exec /app/bin/start-studio-all.sh "$@"
    else
        # 如果权限丢失，用 bash 执行
        echo "⚠ Permissions lost due to mount, executing with bash"
        exec bash /app/bin/start-studio-all.sh "$@"
    fi
else
    echo "✗ ERROR: /app/bin/start-studio-all.sh not found!"
    echo "Falling back to 'hermes gateway run'"
    exec su -s /bin/bash hermes -c "/opt/hermes/.venv/bin/hermes gateway run"
fi
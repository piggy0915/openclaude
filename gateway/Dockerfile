# Dockerfile
FROM nousresearch/hermes-agent:main

# 环境变量
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV NODE_VERSION=24
ENV NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
USER root

# AgentChat: Chromium 存持久卷
ENV PLAYWRIGHT_BROWSERS_PATH=/home/agent/.hermes/playwright-data
ENV CRAWL4AI_PLAYWRIGHT_BROWSERS_PATH=/home/agent/.hermes/playwright-data

# ============================================
# 步骤 1: 配置国内镜像源
# ============================================
RUN if [ -f /etc/apt/sources.list ]; then \
        sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list && \
        sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list; \
    elif [ -f /etc/apt/sources.list.d/debian.sources ]; then \
        sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources && \
        sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources; \
    else \
        echo "⚠️ No sources.list found, skipping mirror configuration"; \
    fi

# ============================================
# 步骤 2: 复制 AgentChat 框架
# ============================================
COPY agentchat-framework/ /opt/agentchat/
COPY chrome-cdp/ /etc/s6-overlay/s6-rc.d/chrome-cdp/

# ============================================
# 步骤 3: 配置 s6 服务和符号链接
# ============================================
RUN echo "chrome-cdp" >> /etc/s6-overlay/s6-rc.d/user/contents.d/chrome-cdp && \
    ln -sf /opt/agentchat/scripts/start-chrome-debug.sh /usr/local/bin/agentchat-start && \
    ln -sf /opt/agentchat/scripts/connect-gemini.sh /usr/local/bin/agentchat-connect && \
    ln -sf /opt/agentchat/skills/AgentChat-OneWeb/index.js /usr/local/bin/agentchat-oneweb

# ============================================
# 步骤 4: 清理旧 Node.js 并安装系统依赖
# ============================================
RUN rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack && \
    rm -rf /usr/local/lib/node_modules && \
    apt-get remove -y nodejs npm || true && \
    apt-get autoremove -y || true

RUN apt-get update && \
    apt-get install -y \
        build-essential \
        curl \
        wget \
        libnss3 \
        libatk-bridge2.0-0 \
        libdrm2 \
        libxkbcommon0 \
        libgbm1 \
        libasound2

# ============================================
# 步骤 5: 安装 Node.js 24
# ============================================
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs python3-pip && \
    npm config set registry ${NPM_CONFIG_REGISTRY}

# ============================================
# 步骤 6: 创建 Python 虚拟环境
# ============================================
RUN python3 -m venv /opt/hermes/.venv

# ============================================
# 步骤 7: 安装 Python 包（分组安装，便于定位）
# ============================================
RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    -e /opt/hermes \
    'qdrant-client>=1.18.0' \
    'firecrawl-py>=4.28.2' \
    'lark-oapi==1.6.8' \
    'qrcode==7.4.2' \
    'dingtalk-stream==0.24.3' \
    'alibabacloud-dingtalk==2.2.49' \
    'playwright>=1.61.0' \
    'websocket-client>=1.8.0'

RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.org/simple \
    --extra-index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    'crawl4ai'

# 使用 pip 安装 firecrawl-anydoc（Rust 原生包，pip 处理更好）
RUN /opt/hermes/.venv/bin/pip install firecrawl-anydoc --index-url https://pypi.org/simple

# ============================================
# 步骤 8: 安装并升级 npm
# ============================================
RUN npm --version || apt-get install -y npm && \
    npm config set prefix /usr && \
    npm install -g npm@latest && \
    npm --version

# ============================================
# 步骤 9: 安装全局 npm 工具
# ============================================
RUN npm install -g @gitlawb/openclaude@latest reasonix@latest @firecrawl/anydoc && \
    openclaude --version && \
    reasonix --version

# ============================================
# 步骤 10: 清理 npm 缓存并创建符号链接
# ============================================
RUN npm cache clean --force && \
    node --version && \
    ln -sf /usr/bin/node /usr/local/bin/node && \
    ln -sf /usr/bin/npm /usr/local/bin/npm && \
    ln -sf /usr/bin/npx /usr/local/bin/npx && \
    ln -sf /usr/lib/node_modules/.bin/openclaude /usr/local/bin/openclaude && \
    ln -sf /usr/lib/node_modules/.bin/reasonix /usr/local/bin/reasonix

# ============================================
# 步骤 11: 安装 Playwright Chromium（备用镜像）
# ============================================
RUN mkdir -p /home/agent/.hermes/playwright-data && \
    echo "=== Installing Chromium with Playwright ===" && \
    PLAYWRIGHT_BROWSERS_PATH=/home/agent/.hermes/playwright-data \
    PLAYWRIGHT_DOWNLOAD_HOST=https://cdn.npmmirror.com/binaries/playwright \
    /opt/hermes/.venv/bin/python3 -m playwright install chromium || \
    PLAYWRIGHT_BROWSERS_PATH=/home/agent/.hermes/playwright-data \
    PLAYWRIGHT_DOWNLOAD_HOST=https://registry.npmmirror.com/-/binary/playwright \
    /opt/hermes/.venv/bin/python3 -m playwright install chromium || \
    PLAYWRIGHT_BROWSERS_PATH=/home/agent/.hermes/playwright-data \
    /opt/hermes/.venv/bin/python3 -m playwright install chromium

# ============================================
# 步骤 12: 验证 Chromium 安装
# ============================================
RUN echo "=== Verifying Chromium ===" && \
    CHROME_PATH=$(find /home/agent/.hermes/playwright-data -name chrome -type f 2>/dev/null | head -1) && \
    if [ -n "$CHROME_PATH" ]; then \
        echo "✅ Chromium found at: $CHROME_PATH"; \
        $CHROME_PATH --version 2>/dev/null || echo "⚠️ Version check failed"; \
    else \
        echo "❌ Chromium not found!"; \
        echo "Directory contents:"; \
        ls -la /home/agent/.hermes/playwright-data/ 2>/dev/null || echo "Directory empty"; \
        exit 1; \
    fi

# ============================================
# 步骤 13: 清理 apt 缓存
# ============================================
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================
# 步骤 14: AgentChat npm 依赖
# ============================================
RUN cd /opt/agentchat && \
    npm install --no-audit --no-fund && \
    (cd skills/AgentChat-OneWeb && npm install --no-audit --no-fund) && \
    test -d /opt/agentchat/node_modules && \
    test -d /opt/agentchat/skills/AgentChat-OneWeb/node_modules || \
    { echo "FAIL: agentchat npm deps"; exit 1; }

# ============================================
# 步骤 15: 创建 skills 符号链接
# ============================================
RUN mkdir -p /home/agent/.hermes/skills /home/agent/.claude && \
    for s in AgentChat-OneWeb AgentChat-IndependentTasks AgentChat-WebSubAgent; do \
        ln -sfn /opt/agentchat/skills/$s /home/agent/.hermes/skills/$s; \
    done && \
    ln -sfn /home/agent/.hermes/skills /home/agent/.claude/skills

# ============================================
# 步骤 16: 安装 Serena
# ============================================
RUN python3 -m venv /opt/serena-venv && \
    /opt/serena-venv/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple \
        'serena-agent==1.6.1' && \
    HOME=/home/agent /opt/serena-venv/bin/serena init

# ============================================
# 步骤 17: 安装 MCP 客户端依赖
# ============================================
RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    mcp

# ============================================
# 步骤 18: 安装 CodeGraph
# ============================================
RUN npm i -g @colbymchenry/codegraph && \
    ln -sf "$(npm root -g)/@colbymchenry/codegraph/npm-shim.js" /usr/local/bin/codegraph && \
    codegraph --version && \
    test -x /usr/local/bin/codegraph || { echo "FAIL: CodeGraph"; exit 1; }

# ============================================
# 步骤 19: 安装其他 MCP 包
# ============================================
RUN npm install -g ppt-mcp@2.0.0 @upstash/context7-mcp@4.0.2 @drawio/mcp@1.6.0 && \
    test -f /usr/lib/node_modules/ppt-mcp/build/index.js && \
    test -f /usr/lib/node_modules/@upstash/context7-mcp/dist/index.js && \
    test -f /usr/lib/node_modules/@drawio/mcp/src/index.js && \
    echo "OK: MCP packages installed" || { echo "FAIL: MCP packages"; exit 1; }

# ============================================
# 步骤 20: 编译 SQLite（如果失败，使用备用方案）
# ============================================
COPY sqlite-autoconf-3510300.tar.gz /tmp/
RUN set -eu; \
    echo "📦 Starting SQLite compilation..."; \
    if [ ! -f /tmp/sqlite-autoconf-3510300.tar.gz ]; then \
        echo "❌ SQLite tarball not found!"; \
        echo "⚠️ Installing SQLite from apt as fallback..."; \
        apt-get update && apt-get install -y sqlite3 libsqlite3-dev && \
        sqlite3 --version && \
        exit 0; \
    fi; \
    tar xzf /tmp/sqlite-autoconf-3510300.tar.gz -C /tmp; \
    cd /tmp/sqlite-autoconf-3510300; \
    ./configure --prefix=/usr/local --all; \
    make -j$(nproc) && make install; \
    ldconfig; \
    sqlite3 --version; \
    /opt/hermes/.venv/bin/python3 -c \
        "import sqlite3; v=sqlite3.sqlite_version; print(f'✅ SQLite upgraded: {v}'); assert v>='3.51.3'"; \
    rm -rf /tmp/sqlite-autoconf-*

# ============================================
# 步骤 21: 编译 CJK 分词扩展
# ============================================
RUN mkdir -p /home/agent/.hermes/lib && \
    cd /opt/hermes/native/fts5_cjk && \
    gcc -shared -fPIC -O2 -Wall -I/usr/local/include fts5_cjk.c -o libfts5_cjk.so && \
    install -m 0644 libfts5_cjk.so /home/agent/.hermes/lib/libfts5_cjk.so

# ============================================
# 启动命令
# ============================================
CMD ["gateway", "run"]
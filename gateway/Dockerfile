# Dockerfile
FROM nousresearch/hermes-agent:main

# 环境变量
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV NODE_VERSION=24
# Increase Node.js memory limit to prevent OOM during build
ENV NODE_OPTIONS=--max-old-space-size=4096

# 设置环境变量让node-gyp和npm使用国内镜像（所有配置通过环境变量）
ENV NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
ENV NODEJS_ORG_MIRROR=https://registry.npmmirror.com/-/binary/node
ENV ELECTRON_MIRROR=https://registry.npmmirror.com/-/binary/electron/
ENV PYTHON_MIRROR=https://registry.npmmirror.com/-/binary/python/
USER root

# AgentChat: Chromium 存镜像内路径（/opt/hermes 无卷挂载，避免被 hermes_data_volume 遮蔽）
# ⚠️ 2026-08-20 修正：原 playwright-data 在 /home/agent/.hermes 下会被卷遮蔽，
#    构建装的浏览器运行时找不到。与 compose 642 行 PLAYWRIGHT_BROWSERS_PATH 统一为镜像内路径。
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV CRAWL4AI_PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

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
    apt-get install -y --no-install-recommends \
        ca-certificates \
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
RUN /opt/hermes/.venv/bin/pip install \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    --extra-index-url https://pypi.org/simple \
    --no-cache-dir \
    -e /opt/hermes \
    'firecrawl-py>=4.37.0'

RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    -e /opt/hermes \
    'qdrant-client>=1.18.0' \
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
RUN mkdir -p /opt/hermes/.playwright && \
    echo "=== Installing Chromium with Playwright ===" && \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    PLAYWRIGHT_DOWNLOAD_HOST=https://cdn.npmmirror.com/binaries/playwright \
    /opt/hermes/.venv/bin/python3 -m playwright install chromium || \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    PLAYWRIGHT_DOWNLOAD_HOST=https://registry.npmmirror.com/-/binary/playwright \
    /opt/hermes/.venv/bin/python3 -m playwright install chromium || \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    /opt/hermes/.venv/bin/python3 -m playwright install chromium

# ============================================
# 步骤 12: 验证 Chromium 安装
# ============================================
RUN echo "=== Verifying Chromium ===" && \
    CHROME_PATH=$(find /opt/hermes/.playwright -name chrome -type f 2>/dev/null | head -1) && \
    if [ -n "$CHROME_PATH" ]; then \
        echo "✅ Chromium found at: $CHROME_PATH"; \
        $CHROME_PATH --version 2>/dev/null || echo "⚠️ Version check failed"; \
    else \
        echo "❌ Chromium not found!"; \
        echo "Directory contents:"; \
        ls -la /opt/hermes/.playwright/ 2>/dev/null || echo "Directory empty"; \
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
RUN npm install -g ppt-mcp@2.0.0 @upstash/context7-mcp@4.0.2 @drawio/mcp@1.3.2 && \
    test -f /usr/lib/node_modules/ppt-mcp/build/index.js && \
    test -f /usr/lib/node_modules/@upstash/context7-mcp/dist/index.js && \
    test -f /usr/lib/node_modules/@drawio/mcp/src/index.js && \
    echo "OK: MCP packages installed" || { echo "FAIL: MCP packages"; exit 1; }

# ============================================
# 步骤 20: 验证 SQLite（基础镜像 v2026.8.18 已自带 3.53.4，无需编译）
# ⚠️ 2026-08-20 修正：原步骤编译 3.53.4 反而降级，已删除（含 COPY tarball）
# ============================================
COPY sqlite-autoconf-3530400.tar.gz /tmp/
RUN set -eu; \
    echo "📦 Starting SQLite compilation..."; \
    if [ ! -f /tmp/sqlite-autoconf-3530400.tar.gz ]; then \
        echo "❌ SQLite tarball not found!"; \
        echo "⚠️ Installing SQLite from apt as fallback..."; \
        apt-get update && apt-get install -y sqlite3 libsqlite3-dev && \
        sqlite3 --version && \
        exit 0; \
    fi; \
    tar xzf /tmp/sqlite-autoconf-3530400.tar.gz -C /tmp; \
    cd /tmp/sqlite-autoconf-3530400; \
    ./configure --prefix=/usr/local --all; \
    make -j$(nproc) && make install; \
    ldconfig; \
    sqlite3 --version; \
    /opt/hermes/.venv/bin/python3 -c \
        "import sqlite3; v=sqlite3.sqlite_version; print(f'✅ SQLite upgraded: {v}'); assert v>='3.51.3'"; \
    rm -rf /tmp/sqlite-autoconf-*

# ============================================
# 步骤 21: 编译 CJK 分词扩展（装到镜像内 /usr/local/lib，避开 .hermes 卷遮蔽）
# ⚠️ 2026-08-20 修正：原装到 /home/agent/.hermes/lib 会被 hermes_data_volume 遮蔽，
#    每次重建镜像后运行时仍加载卷里旧版。改为镜像内路径 + compose 设置
#    HERMES_FTS5_CJK_SO=/usr/local/lib/libfts5_cjk.so（源码原生支持，见 hermes_state.py），
#    保证每次重建镜像后自动生效，无需 docker cp / 删卷。
# ============================================
RUN cd /opt/hermes/native/fts5_cjk && \
    gcc -shared -fPIC -O2 -Wall -I/usr/local/include fts5_cjk.c -o libfts5_cjk.so && \
    install -m 0644 libfts5_cjk.so /usr/local/lib/libfts5_cjk.so

# ============================================
# 启动命令（2026-08-20 修正：容器实际入口是挂载的 /home/agent/scripts/entrypoint.sh，
# 其末尾 exec hermes gateway run，镜像 CMD 被遮蔽，故删除以免误导）
# ============================================
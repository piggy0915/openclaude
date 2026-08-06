# Dockerfile
FROM nousresearch/hermes-agent:v2026.8.3
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV NODE_VERSION=24
ENV NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
USER root

# AgentChat: Chromium 存持久卷
ENV PLAYWRIGHT_BROWSERS_PATH=/home/agent/.hermes/playwright-data

# 使用国内镜像源（如果在国内）
# 使用国内镜像源（如果在国内）- 修复：先检查文件是否存在
RUN if [ -f /etc/apt/sources.list ]; then \
        sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list && \
        sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list; \
    elif [ -f /etc/apt/sources.list.d/debian.sources ]; then \
        sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources && \
        sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources; \
    else \
        echo "⚠️ No sources.list found, skipping mirror configuration"; \
    fi

COPY agentchat-framework/ /opt/agentchat/
# AgentChat: s6 chrome-cdp 服务
#COPY chrome-cdp/ /opt/hermes/docker/s6-rc.d/chrome-cdp/
COPY chrome-cdp/ /etc/s6-overlay/s6-rc.d/chrome-cdp/
RUN echo "chrome-cdp" >> /etc/s6-overlay/s6-rc.d/user/contents.d/chrome-cdp && \
    ln -sf /opt/agentchat/scripts/start-chrome-debug.sh /usr/local/bin/agentchat-start && \
    ln -sf /opt/agentchat/scripts/connect-gemini.sh /usr/local/bin/agentchat-connect && \
    ln -sf /opt/agentchat/skills/AgentChat-OneWeb/index.js /usr/local/bin/agentchat-oneweb

#RUN echo "chrome-cdp" >> /opt/hermes/docker/s6-rc.d/user/contents.d/chrome-cdp && \
#    ln -s /opt/agentchat/start-chrome.sh /usr/local/bin/agentchat-start && \
#    ln -s /opt/agentchat/scripts/connect-gemini.sh /usr/local/bin/agentchat-connect

# 彻底移除旧 Node.js（包括 /usr/local/bin/ 下的多阶段构建产物）
RUN rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack && \
    rm -rf /usr/local/lib/node_modules && \
    apt-get remove -y nodejs npm || true && \
    apt-get autoremove -y || true && \
    apt-get update && \
    # 安装 SQLite 编译依赖和其他必要工具
    apt-get install -y \
        build-essential \
        curl \
        wget \
        && \
    # 使用 NodeSource 安装 Node.js 24(不要再用 curl 下载二进制)
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs python3-pip && \
    # 配置npm镜像源
    npm config set registry ${NPM_CONFIG_REGISTRY} && \
    python3 -m venv /opt/hermes/.venv && \
    # ← 修复：加 PyPI 镜像（国内网络）
    uv pip install --python /opt/hermes/.venv/bin/python3 \
        --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
        -e /opt/hermes \
        'qdrant-client>=1.18.0' \
        'firecrawl-py>=4.28.2' \
        'lark-oapi==1.6.8' \
        'qrcode==7.4.2' \
        'dingtalk-stream==0.24.3' \
        'alibabacloud-dingtalk==2.2.49' \
        'playwright>=1.61.0' \
        && \
    # 升级npm到最新版本
    npm install -g npm@latest && \
    npm install -g @gitlawb/openclaude@latest reasonix@latest && \
    npm cache clean --force && \
    # 恢复默认 prefix
    npm config delete prefix && \
    node --version && \
    ln -sf /usr/bin/node /usr/local/bin/node && \
    ln -sf /usr/bin/npm /usr/local/bin/npm && \
    ln -sf /usr/bin/npx /usr/local/bin/npx && \
    ln -sf /usr/lib/node_modules/.bin/openclaude /usr/local/bin/openclaude && \
    ln -sf /usr/lib/node_modules/.bin/reasonix /usr/local/bin/reasonix && \
    # 下载完整版 Chromium 到持久卷（支持 CDP）- npmmirror 加速 + 显式路径 + 构建期验证
    mkdir -p /home/agent/.hermes/playwright-data && \
    PLAYWRIGHT_BROWSERS_PATH=/home/agent/.hermes/playwright-data \
    PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright \
    /opt/hermes/.venv/bin/python3 -m playwright install chromium && \
    ls -d /home/agent/.hermes/playwright-data/chromium-*/chrome-linux64/chrome >/dev/null || { echo "FAIL: Chromium missing in persistent volume"; exit 1; } && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# AgentChat (Node.js v2) - npm 依赖 + Hermes skill 挂载
RUN cd /opt/agentchat && \
    npm install --no-audit --no-fund && \
    (cd skills/AgentChat-OneWeb && npm install --no-audit --no-fund) && \
    mkdir -p /home/agent/.hermes/skills /home/agent/.claude && \
    for s in AgentChat-OneWeb AgentChat-IndependentTasks AgentChat-WebSubAgent; do \
        ln -sfn /opt/agentchat/skills/$s /home/agent/.hermes/skills/$s; \
    done && \
    ln -sfn /home/agent/.hermes/skills /home/agent/.claude/skills

# SQLite 升级 - 增加错误处理和详细日志
COPY sqlite-autoconf-3510300.tar.gz /tmp/
RUN set -eu; \
    echo "📦 Starting SQLite compilation..."; \
    # 验证文件存在
    if [ ! -f /tmp/sqlite-autoconf-3510300.tar.gz ]; then \
        echo "❌ SQLite tarball not found!"; \
        exit 1; \
    fi; \
    tar xzf /tmp/sqlite-autoconf-3510300.tar.gz -C /tmp; \
    cd /tmp/sqlite-autoconf-3510300; \
    echo "📋 Running configure..."; \
    ./configure --prefix=/usr/local --all; \
    echo "🔨 Compiling SQLite (this may take a few minutes)..."; \
    # 先尝试单线程编译（更稳定）
    make -j$(nproc); \
    echo "📦 Installing SQLite..."; \
    make install; \
    ldconfig; \
    echo "✅ SQLite installed, verifying..."; \
    # 验证系统级 SQLite
    sqlite3 --version; \
    # 验证 Python 中的 SQLite 版本
    /opt/hermes/.venv/bin/python3 -c \
        "import sqlite3; v=sqlite3.sqlite_version; print(f'✅ SQLite upgraded: {v}'); assert v>='3.51.3'"; \
    echo "🧹 Cleaning up..."; \
    rm -rf /tmp/sqlite-autoconf-*
# CJK 分词扩展（必须在 SQLite 升级之后，用新 headers 编译）
RUN mkdir -p /home/agent/.hermes/lib && \
    cd /opt/hermes/native/fts5_cjk && \
    gcc -shared -fPIC -O2 -Wall -I/usr/local/include fts5_cjk.c -o libfts5_cjk.so && \
    install -m 0644 libfts5_cjk.so /home/agent/.hermes/lib/libfts5_cjk.so

# 可选：如果上述方法仍然失败，使用这个备用方案
# RUN apt-get update && apt-get install -y sqlite3 libsqlite3-dev && \
#     sqlite3 --version

#ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]
CMD ["gateway", "run"]
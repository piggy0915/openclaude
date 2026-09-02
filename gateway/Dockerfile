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
# 步骤 3: 配置国内镜像源
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
# 步骤 4: 复制 AgentChat 框架
# ============================================
COPY agentchat-framework/ /opt/agentchat/
COPY chrome-cdp/ /etc/s6-overlay/s6-rc.d/chrome-cdp/

# ============================================
# 步骤 5: 配置 s6 服务和符号链接
# ============================================
RUN echo "chrome-cdp" >> /etc/s6-overlay/s6-rc.d/user/contents.d/chrome-cdp && \
    ln -sf /opt/agentchat/scripts/start-chrome-debug.sh /usr/local/bin/agentchat-start && \
    ln -sf /opt/agentchat/scripts/connect-gemini.sh /usr/local/bin/agentchat-connect && \
    ln -sf /opt/agentchat/skills/AgentChat-OneWeb/index.js /usr/local/bin/agentchat-oneweb

# ============================================
# 步骤 6: 清理旧 Node.js 并安装系统依赖
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
        libasound2 \
        ffmpeg

# ============================================
# 步骤 8: 安装 Node.js 24
# ============================================
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs python3-pip && \
    npm config set registry ${NPM_CONFIG_REGISTRY}

# ============================================
# 步骤 9: 创建 Python 虚拟环境
# ============================================
RUN python3 -m venv /opt/hermes/.venv

# ============================================
# 步骤 10: 安装 Python 包（分组安装，便于定位）
# ============================================
RUN /opt/hermes/.venv/bin/pip install \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    --extra-index-url https://pypi.org/simple \
    --no-cache-dir \
    -e /opt/hermes \
    'firecrawl-py>=4.37.0'
# lazy_deps edge-tts pin 固化：镜像层直接 7.2.8，消除启动 lazy-refresh 竞态（2026-09-01）
RUN sed -i 's/edge-tts==7\.2\.7/edge-tts==7.2.8/g' /opt/hermes/tools/lazy_deps.py && grep -q 'edge-tts==7.2.8' /opt/hermes/tools/lazy_deps.py && echo "lazy_deps pin 固化 7.2.8"

RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    -e /opt/hermes \
    'qdrant-client>=1.18.0' \
    'psycopg[binary]>=3.2.0' \
    'lark-oapi>=1.6.8' \
    'qrcode>=7.4.2' \
    'dingtalk-stream>=0.24.3' \
    'alibabacloud-dingtalk>=2.2.49' \
    'playwright>=1.61.0' \
    'websocket-client>=1.8.0'

RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.org/simple \
    --extra-index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    'crawl4ai'

# 使用 pip 安装 firecrawl-anydoc（Rust 原生包，pip 处理更好）
RUN /opt/hermes/.venv/bin/pip install firecrawl-anydoc --index-url https://pypi.org/simple

# ============================================
# 步骤 14: 文档处理依赖（openpyxl/docx/pptx 等，2026-08-21 固化）
# 注意：原临时安装写在容器可写层，容器重建即丢失（venv 在镜像内非持久卷）。
# 统一在此固化，构建后无需再手动 uv pip install。
# ============================================
RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    'openpyxl>=3.1.5' \
    'python-docx>=1.1.0' \
    'python-pptx>=1.0.2' \
    'defusedxml>=0.7.1' \
    'pymupdf>=1.24.0' \
    'Pillow>=10.0.0' \
    'lxml>=5.0.0' \
    'pandas>=2.0.0' \
    'xlsxwriter>=3.1.0' \
    'edge-tts>=7.2.8'
RUN python3 - <<'PY'
p = "/opt/hermes/tools/tts_tool.py"
s = open(p, encoding="utf-8").read()
old = '''def _import_edge_tts():
    """Lazy import edge_tts. Returns the module or raises ImportError."""
    try:
        from tools.lazy_deps import ensure as _lazy_ensure
        _lazy_ensure("tts.edge", prompt=False)
    except ImportError:
        pass
    except Exception:
        pass
    import edge_tts
    return edge_tts'''
new = '''def _import_edge_tts():
    """Lazy import edge_tts. Returns the module or raises ImportError."""
    import edge_tts
    return edge_tts'''
assert old in s, "tts_tool.py 结构不符，请检查"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
print("✓ tts_tool._import_edge_tts 已移除 lazy_ensure")
PY

# ============================================
# 步骤 15: 安装并升级 npm
# ============================================
RUN npm --version || apt-get install -y npm && \
    npm config set prefix /usr && \
    npm install -g npm@latest && \
    npm --version

# ============================================
# 步骤 16: 安装全局 npm 工具
# ============================================
RUN npm install -g @gitlawb/openclaude@latest reasonix@latest @firecrawl/anydoc @marp-team/marp-cli && \
    openclaude --version && \
    reasonix --version

# ============================================
# 步骤 17: 清理 npm 缓存并创建符号链接
# ============================================
RUN npm cache clean --force && \
    node --version && \
    ln -sf /usr/bin/node /usr/local/bin/node && \
    ln -sf /usr/bin/npm /usr/local/bin/npm && \
    ln -sf /usr/bin/npx /usr/local/bin/npx && \
    ln -sf /usr/lib/node_modules/.bin/openclaude /usr/local/bin/openclaude && \
    ln -sf /usr/lib/node_modules/.bin/reasonix /usr/local/bin/reasonix

# ============================================
# 步骤 18: 安装 Playwright Chromium（备用镜像）
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
# 步骤 19: 验证 Chromium 安装
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
# 步骤 20: 清理 apt 缓存
# ============================================
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# ============================================
# 步骤 21: AgentChat npm 依赖
# ============================================
RUN cd /opt/agentchat && \
    npm install --no-audit --no-fund && \
    (cd skills/AgentChat-OneWeb && npm install --no-audit --no-fund) && \
    test -d /opt/agentchat/node_modules && \
    test -d /opt/agentchat/skills/AgentChat-OneWeb/node_modules || \
    { echo "FAIL: agentchat npm deps"; exit 1; }

# ============================================
# 步骤 22: 创建 skills 符号链接
# ============================================
RUN mkdir -p /home/agent/.hermes/skills /home/agent/.claude && \
    for s in AgentChat-OneWeb AgentChat-IndependentTasks AgentChat-WebSubAgent; do \
        ln -sfn /opt/agentchat/skills/$s /home/agent/.hermes/skills/$s; \
    done && \
    ln -sfn /home/agent/.hermes/skills /home/agent/.claude/skills

# ============================================
# 步骤 23: 安装 Serena
# ============================================
RUN python3 -m venv /opt/serena-venv && \
    /opt/serena-venv/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple \
        'serena-agent==1.6.1' && \
    HOME=/home/agent /opt/serena-venv/bin/serena init

# ============================================
# 步骤 24: 安装 MCP 客户端依赖
# ============================================
RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    mcp

# ============================================
# 步骤 25: 安装 CodeGraph
# ============================================
RUN npm i -g @colbymchenry/codegraph && \
    ln -sf "$(npm root -g)/@colbymchenry/codegraph/npm-shim.js" /usr/local/bin/codegraph && \
    codegraph --version && \
    test -x /usr/local/bin/codegraph || { echo "FAIL: CodeGraph"; exit 1; }

# ============================================
# 步骤 26: 安装其他 MCP 包
# ============================================


# ============================================
# 步骤 27: huashu-design 导出工具链（node 全局）
# 供 huashu-design skill 的 scripts/ 调用：
#   render-video.js / html2pptx.js → playwright + sharp
#   export_deck_pptx.mjs          → pptxgenjs
#   export_deck_pdf.mjs           → pdf-lib
# scripts/ 以 `require('playwright')` 方式加载，故必须装到全局 node_modules
# 并用 NODE_PATH 指向全局，否则 skill 运行时 require 找不到。
# ============================================
ENV NODE_PATH=/usr/lib/node_modules
RUN npm install -g playwright pptxgenjs sharp pdf-lib && \
    echo "=== Installing Chromium for node playwright ===" && \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    PLAYWRIGHT_DOWNLOAD_HOST=https://cdn.npmmirror.com/binaries/playwright \
    npx playwright install chromium || \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    PLAYWRIGHT_DOWNLOAD_HOST=https://registry.npmmirror.com/-/binary/playwright \
    npx playwright install chromium || \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright \
    npx playwright install chromium

# ============================================
# 步骤 28: 验证 SQLite（基础镜像 v2026.8.18 已自带 3.53.4，无需编译）
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
# 步骤 30: 修复 Hermes Provider 刷新问题
# ============================================

# 2. 创建 ~/.local/bin 软链接，解决 hermes 命令找不到的问题
RUN mkdir -p /home/agent/.local/bin && \
    ln -sf /opt/hermes/.venv/bin/hermes /home/agent/.local/bin/hermes && \
    # 确保 PATH 包含该目录
    echo 'export PATH=/home/agent/.local/bin:$PATH' >> /home/agent/.bashrc

# 3. 清理并重建 state.db（解决 disk I/O error）
RUN cd /home/agent/.hermes && \
    # 备份旧的（如果有）
    (mv state.db state.db.bak.$(date +%Y%m%d) 2>/dev/null || true) && \
    # 删除所有相关文件
    rm -f state.db state.db-shm state.db-wal && \
    # 用 hermes 重新初始化数据库（必须在 venv 激活状态下）
    /opt/hermes/.venv/bin/python3 -c "from hermes.db import init_db; init_db()" 2>/dev/null || \
    # 如果上面不行，用 hermes 命令
    /home/agent/.local/bin/hermes db init 2>/dev/null || \
    echo "⚠️ DB init skipped (will be done at runtime)"

# 4. 升级配置版本（v38 → v39）
RUN /home/agent/.local/bin/hermes config upgrade 2>/dev/null || true

# 5. 环境变量：修复 Python 和 Playwright 路径（防止在容器内找不到）
ENV PATH="/home/agent/.local/bin:${PATH}"
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# 删除 ENV PYTHONPATH 那行，改用 RUN 在 shell 中设置
RUN echo 'export PYTHONPATH="/opt/hermes${PYTHONPATH:+:${PYTHONPATH}}"' >> /etc/profile.d/hermes.sh && \
    echo 'export PYTHONPATH="/opt/hermes${PYTHONPATH:+:${PYTHONPATH}}"' >> /home/agent/.bashrc

# 6. 创建启动脚本，每次容器启动时自动修复
RUN echo '#!/bin/bash\n\
# === Hermes Provider 修复脚本 ===\n\
\n\
# 修复 DNS（容器每次启动可能被重置）\n\
echo "nameserver 223.5.5.5" > /etc/resolv.conf\n\
echo "nameserver 8.8.8.8" >> /etc/resolv.conf\n\
\n\
# 确保软链接存在\n\
mkdir -p /home/agent/.local/bin\n\
ln -sf /opt/hermes/.venv/bin/hermes /home/agent/.local/bin/hermes\n\
\n\
# 修复 state.db（如果有锁或损坏）\n\
cd /home/agent/.hermes\n\
if [ -f state.db ]; then\n\
    # 检查 DB 是否正常\n\
    if ! /opt/hermes/.venv/bin/python3 -c "import sqlite3; sqlite3.connect(\"state.db\").cursor().execute(\"SELECT 1\")" 2>/dev/null; then\n\
        echo "⚠️ state.db corrupted, rebuilding..."\n\
        rm -f state.db state.db-shm state.db-wal\n\
        /home/agent/.local/bin/hermes db init 2>/dev/null || true\n\
    fi\n\
else\n\
    /home/agent/.local/bin/hermes db init 2>/dev/null || true\n\
fi\n\
\n\
# 升级配置（如果还没升级）\n\
/home/agent/.local/bin/hermes config upgrade 2>/dev/null || true\n\
\n\
# 执行原始命令\n\
exec "$@"\n\
' > /usr/local/bin/hermes-fix.sh && chmod +x /usr/local/bin/hermes-fix.sh

# 7. 设置 entrypoint 为修复脚本（保留原 CMD）
ENTRYPOINT ["/usr/local/bin/hermes-fix.sh"]
# 注意：原 Dockerfile 底部有注释说明 CMD 被遮蔽，这里保留原 CMD 不变
# 如果原镜像有 CMD，会被 ENTRYPOINT 透传执行


# ============================================
# 步骤 35: 编译 CJK 分词扩展（装到镜像内 /usr/local/lib，避开 .hermes 卷遮蔽）
# ⚠️ 2026-08-20 修正：原装到 /home/agent/.hermes/lib 会被 hermes_data_volume 遮蔽，
#    每次重建镜像后运行时仍加载卷里旧版。改为镜像内路径 + compose 设置
#    HERMES_FTS5_CJK_SO=/usr/local/lib/libfts5_cjk.so（源码原生支持，见 hermes_state.py），
#    保证每次重建镜像后自动生效，无需 docker cp / 删卷。
# ============================================
RUN cd /opt/hermes/native/fts5_cjk && \
    gcc -shared -fPIC -O2 -Wall -I/usr/local/include fts5_cjk.c -o libfts5_cjk.so && \
    install -m 0644 libfts5_cjk.so /usr/local/lib/libfts5_cjk.so

# ============================================
# 步骤 36: book-to-skill（2026-08-28 固化；未上 PyPI，源码 COPY 安装）
# 纯本地规则提取引擎（无 LLM/网络调用），依赖走清华 PyPI 源
# ============================================
COPY book-to-skill/ /opt/book-to-skill/
RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    '/opt/book-to-skill[pdf,epub,docx,html,rtf]'

# ============================================
# 步骤 38: archify（2026-08-28 固化；Node CLI 零依赖，JSON-IR → 自包含 HTML）
# 装镜像内 /opt/archify（/home/agent/.hermes 被卷遮蔽，SKILL.md 走 Gitee skills 同步）
# ============================================
COPY archify-src/archify/ /opt/archify/
RUN ln -sf /opt/archify/bin/archify.mjs /usr/local/bin/archify && \
    chmod +x /opt/archify/bin/archify.mjs

# ============================================
# 步骤 40: AI-Video-Transcriber（MCP 工具）
# ⚠️ 2026-08-28 修正：hf-mirror 对 faster-whisper-base 报 401（xethub CAS 存储不兼容），
#    改为构建时 COPY 已下载的模型进镜像（零网络依赖），运行时 HF_HOME 直接命中缓存。
# ============================================
COPY ai-video-transcriber/ /opt/ai-video-transcriber/
COPY whisper-model/ /opt/hermes/.whisper/

RUN uv pip install --python /opt/hermes/.venv/bin/python3 \
    --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
    'yt-dlp>=2024.12.13' \
    'faster-whisper>=1.1.0'

ENV HF_HOME=/opt/hermes/.whisper

# ============================================
# 启动命令（2026-08-20 修正：容器实际入口是挂载的 /home/agent/scripts/entrypoint.sh，
# 其末尾 exec hermes gateway run，镜像 CMD 被遮蔽，故删除以免误导）
# ============================================
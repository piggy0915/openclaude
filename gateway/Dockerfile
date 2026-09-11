# syntax=docker/dockerfile:1
# ============================================================
# hermes-agent:main —— 大脑容器镜像
#   gateway / 消息渠道 / cron / API server(8642) / MCP
# 公共工具链（Node、Python 依赖、agent-browser、Chromium、技能链）全部来自
# hermes-base:main —— 本文件只保留 hermes 专属内容。
# ============================================================
FROM hermes-base:main

USER root

# ============================================
# AgentChat CDP Chrome（s6 服务）
# 2026-08-20 修正：本容器 PID1 是挂载的 scripts/entrypoint.sh，
# s6 服务仅注册；实际 CDP 由 entrypoint.sh 内联启动，见该脚本。
# ============================================
COPY chrome-cdp/ /etc/s6-overlay/s6-rc.d/chrome-cdp/
RUN echo "chrome-cdp" >> /etc/s6-overlay/s6-rc.d/user/contents.d/chrome-cdp && \
    ln -sf /opt/agentchat/scripts/start-chrome-debug.sh /usr/local/bin/agentchat-start && \
    ln -sf /opt/agentchat/scripts/connect-gemini.sh /usr/local/bin/agentchat-connect && \
    ln -sf /opt/agentchat/skills/AgentChat-OneWeb/index.js /usr/local/bin/agentchat-oneweb

# ============================================
# 已从本文件移除（原因）：
#   * 构建期初始化 state.db / config upgrade —— /home/agent/.hermes 是卷，
#     构建期写入会被卷遮蔽，完全无效；运行时由 scripts/entrypoint.sh 负责。
#   * AgentChat skills 软链 —— 同上，改在 entrypoint 每次启动时建链。
#   * 编译 SQLite —— 基础镜像已自带新版，编译反而降级。
#   * 重复的 apt 包 / NODE_PATH / Chromium 安装 —— 已统一到 hermes-base。
# ============================================

# 与 compose 的 entrypoint 保持一致；单独 docker run 时也能起
ENTRYPOINT ["/home/agent/scripts/entrypoint.sh"]

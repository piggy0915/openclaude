# Dockerfile
FROM nousresearch/hermes-agent:v2026.6.19
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ENV NODE_VERSION=24
ENV NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
USER root

# 彻底移除旧 Node.js（包括 /usr/local/bin/ 下的多阶段构建产物）
RUN rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack && \
    rm -rf /usr/local/lib/node_modules && \
    apt-get remove -y nodejs npm || true && \
    apt-get autoremove -y || true && \
    apt-get update && \
    # 使用 NodeSource 安装 Node.js 24(不要再用 curl 下载二进制)
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs python3-pip && \
    # 配置npm镜像源
    npm config set registry ${NPM_CONFIG_REGISTRY} && \
    # 安装Python包
    pip3 install 'qdrant-client>=1.12.0' && \
    # 升级npm到最新版本
    npm install -g npm@latest && \
    npm cache clean --force && \
    # 恢复默认 prefix
    npm config delete prefix && \
    node --version && \
    ln -sf /usr/bin/node /usr/local/bin/node && \
    ln -sf /usr/bin/npm /usr/local/bin/npm && \
    ln -sf /usr/bin/npx /usr/local/bin/npx && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]
CMD ["gateway", "run"]
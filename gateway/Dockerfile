# Dockerfile
FROM nousresearch/hermes-agent:v2026.5.29.2
ENV PIP_BREAK_SYSTEM_PACKAGES=1
USER root

# 彻底移除旧 Node.js（包括 /usr/local/bin/ 下的多阶段构建产物）
RUN rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack && \
    rm -rf /usr/local/lib/node_modules && \
    apt-get remove -y nodejs npm || true && \
    apt-get autoremove -y || true

# 安装新 Node.js 24.x
#RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
#    apt-get install -y nodejs python3-pip && \
#    npm install -g npm@latest && \
#    npm config set prefix /usr -g && \
#    pip3 install 'qdrant-client>=1.12.0' && \
#    npm cache clean --force && \
#    apt-get clean && \
#    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs python3-pip && \
    # 直接使用默认位置，但通过环境变量临时改变 prefix
    export npm_config_prefix=/usr/local && \
    npm config set registry https://registry.npmmirror.com && \
    pip3 install 'qdrant-client>=1.12.0' && \
    npm install -g npm@latest && \
    npm cache clean --force && \
    # 恢复默认 prefix
    npm config delete prefix && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]
CMD ["gateway", "run"]
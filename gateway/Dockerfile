# Dockerfile
FROM nousresearch/hermes-agent:v2026.5.16

USER root

# 方法1：完全移除旧版本 Node.js 和 npm
RUN apt-get remove -y nodejs npm || true && \
    apt-get autoremove -y || true

# 使用 NodeSource 官方脚本安装 Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs python3-pip && \
    pip3 install 'qdrant-client>=1.12.0' && \
    # 清理 npm 缓存
    npm cache clean --force || true


ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]
CMD ["gateway", "run"]
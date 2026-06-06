#!/bin/bash
# 一次性修复 Hermes 宿主机权限（适配容器内 hermes 用户 UID 10000）

set -e

HERMES_DIR="./data/hermes"
WEBUI_DIR="./data/hermes-web-ui"
NODE_MODULES_DIR="./data/node_modules"
APP_DIR="./data/app"
WORKSPACE_DIR="./data/workspace"
CONTAINER_NAME="hermes"

echo "=== 1. 停止容器 ==="
docker compose down 2>/dev/null || docker stop $CONTAINER_NAME 2>/dev/null || true

echo "=== 2. 清理残留锁文件和 WAL ==="
rm -f $HERMES_DIR/gateway.lock \
       $HERMES_DIR/gateway.pid \
       $HERMES_DIR/state.db-wal \
       $HERMES_DIR/state.db-shm \
       $WEBUI_DIR/*.db-wal \
       $WEBUI_DIR/*.db-shm 2>/dev/null || true

echo "=== 3. 修复目录归属（使用容器内 hermes 用户 UID 10000）==="
# 修改为 10000:10000 以匹配容器内的 hermes 用户
sudo chown -R 10000:10000 $HERMES_DIR
sudo chmod -R 755 $HERMES_DIR
sudo chown -R 10000:10000 $WEBUI_DIR
sudo chmod -R 755 $WEBUI_DIR
sudo chown -R 10000:10000 $NODE_MODULES_DIR
sudo chmod -R 755 $NODE_MODULES_DIR
sudo chown -R 10000:10000 $APP_DIR
sudo chmod -R 755 $APP_DIR
sudo chown -R 10000:10000 $WORKSPACE_DIR
sudo chmod -R 755 $WORKSPACE_DIR

# 特别确保日志目录存在且可写
mkdir -p $HERMES_DIR/logs
mkdir -p $HERMES_DIR/.hermes/logs
mkdir -p $HERMES_DIR/sessions
mkdir -p $HERMES_DIR/cache
mkdir -p $HERMES_DIR/credentials
mkdir -p $HERMES_DIR/skills


echo "=== 4. 确保关键子目录可写 ==="
find "$HERMES_DIR" -type d -print0 | while IFS= read -r -d '' dir; do
    # 跳过根目录本身
    if [ "$dir" = "$HERMES_DIR" ]; then
        continue
    fi

    echo "处理: $dir"
    sudo chown -R 10000:10000 "$dir"

    # 根据目录名设置不同权限
    if [[ "$dir" == *"/logs"* ]] || [[ "$dir" == *"/.hermes/logs"* ]]; then
        sudo chmod 775 "$dir"
    else
        sudo chmod 755 "$dir"
    fi
done

sudo chown -R 10000:10000 $HERMES_DIR/logs $HERMES_DIR/.hermes/logs
sudo chmod -R 775 $HERMES_DIR/logs
sudo chmod -R 775 $HERMES_DIR/.hermes/logs
sudo chmod -R 775 $HERMES_DIR/sessions
sudo chmod -R 775 $HERMES_DIR/cache
sudo chmod -R 775 $HERMES_DIR/credentials

echo "=== 5. 检查 bind mount 的配置文件是否可读 ==="
for f in "$HERMES_DIR/.env" "$HERMES_DIR/config.yaml"; do
    if [ -f "$f" ]; then
        sudo chown 10000:10000 "$f"
        sudo chmod 644 "$f"
        echo "  ✓ $f"
    fi
done

echo "=== 6. 修复工作目录和配置目录 ==="
# 修复 workspace 目录
if [ -d WORKSPACE_DIR ]; then
    sudo chown -R 10000:10000 WORKSPACE_DIR
    sudo chmod -R 755 WORKSPACE_DIR
    echo "  ✓ ./data/workspace"
fi

# 修复 config 目录
if [ -d "./config" ]; then
    sudo chown -R 10000:10000 ./config
    sudo chmod -R 755 ./config
    echo "  ✓ ./config"
fi

# 修复 app 目录
if [ -d APP_DIR ]; then
    sudo chown -R 10000:10000 APP_DIR
    sudo chmod -R 755 APP_DIR
    echo "  ✓ ./data/app"
fi

# 修复 scripts 目录（确保 entrypoint.sh 可执行）
if [ -d "./scripts" ]; then
    sudo chown -R 10000:10000 ./scripts
    sudo chmod -R 755 ./scripts
    sudo chmod +x ./scripts/entrypoint.sh
    sudo chmod +x ./scripts/chpermission.sh
    echo "  ✓ ./scripts"
fi

echo "=== 7. 设置 SSH 密钥（供 hermes 用户使用）==="
# 创建 .ssh 目录并复制 SSH 密钥
mkdir -p $HERMES_DIR/.ssh

if [ -f ~/.ssh/id_rsa_hermes ]; then
    echo "Copying SSH key from host to $HERMES_DIR/.ssh/"
    cp ~/.ssh/id_rsa_hermes $HERMES_DIR/.ssh/
    cp ~/.ssh/id_rsa_hermes.pub $HERMES_DIR/.ssh/ 2>/dev/null
    cp ~/.ssh/known_hosts $HERMES_DIR/.ssh/ 2>/dev/null

    sudo chown -R 10000:10000 $HERMES_DIR/.ssh
    sudo chmod 700 $HERMES_DIR/.ssh
    sudo chmod 600 $HERMES_DIR/.ssh/id_rsa_hermes
    sudo chmod 644 $HERMES_DIR/.ssh/id_rsa_hermes.pub 2>/dev/null
    sudo chmod 644 $HERMES_DIR/.ssh/known_hosts 2>/dev/null
    echo "✓ SSH key configured for hermes user (UID 10000)"
else
    echo "⚠ SSH key not found at ~/.ssh/id_rsa_hermes"
    echo "  Generate with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_hermes -N \"\""
    echo "  Then add to authorized_keys: cat ~/.ssh/id_rsa_hermes.pub >> ~/.ssh/authorized_keys"
fi

echo "=== 8. 修复 Obsidian SSL 证书权限 ==="
if [ -f "./data/obsidian/nginx/ssl/obsidian.crt" ]; then
    sudo chmod 644 ./data/obsidian/nginx/ssl/obsidian.crt
    sudo chown root:root ./data/obsidian/nginx/ssl/obsidian.crt
    echo "  ✓ obsidian.crt"
fi

if [ -f "./data/obsidian/nginx/ssl/obsidian.key" ]; then
    sudo chmod 600 ./data/obsidian/nginx/ssl/obsidian.key
    sudo chown root:root ./data/obsidian/nginx/ssl/obsidian.key
    echo "  ✓ obsidian.key"
fi

echo "=== 9. 修复 Qdrant 数据目录权限 ==="
if [ -d "./data/qdrant" ]; then
    # Qdrant 容器通常使用 UID 1000，保持原样
    echo "  ✓ ./data/qdrant (preserve existing permissions)"
fi

echo "=== 10. 验证关键目录权限 ==="
echo "--- $HERMES_DIR ---"
ls -la $HERMES_DIR | head -10

echo ""
echo "--- $HERMES_DIR/.hermes/logs ---"
ls -la $HERMES_DIR/.hermes/logs 2>/dev/null || echo "  (directory may not exist yet)"

echo ""
echo "--- $HERMES_DIR/.ssh ---"
ls -la $HERMES_DIR/.ssh 2>/dev/null || echo "  (directory may not exist yet)"

echo ""
echo "=== 11. 验证 UID 匹配 ==="
echo "Expected UID in container: 10000 (hermes)"
echo "Current ownership on host:"
stat -c "  %n: UID=%u GID=%g" $HERMES_DIR 2>/dev/null

echo ""
echo "=== 完成！现在可以启动容器 ==="
echo "Run: docker compose up -d"
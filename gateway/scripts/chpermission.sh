#!/bin/bash
# 一次性修复 Hermes 宿主机权限（直接粘贴执行）

set -e

HERMES_DIR="../data/hermes"
CONTAINER_NAME="hermes"

echo "=== 1. 停止容器 ==="
#docker compose down 2>/dev/null || docker stop $CONTAINER_NAME 2>/dev/null || true

echo "=== 2. 清理残留锁文件和 WAL ==="
rm -f $HERMES_DIR/gateway.lock \
           $HERMES_DIR/gateway.pid \
           $HERMES_DIR/state.db-wal \
           $HERMES_DIR/state.db-shm \
           $HERMES_DIR/hermes-web-ui/*.db-wal \
           $HERMES_DIR/hermes-web-ui/*.db-shm 2>/dev/null || true

echo "=== 3. 修复目录归属（对齐容器内 hermes 用户 UID 10000）==="
chown -R 10000:10000 $HERMES_DIR
chmod -R u+rwx $HERMES_DIR

echo "=== 4. 确保关键子目录可写 ==="
for subdir in hermes-web-ui .hermes .claude plugins skills logs sessions; do
    if [ -d "$HERMES_DIR/$subdir" ]; then
        chown -R 10000:10000 "$HERMES_DIR/$subdir"
        chmod -R u+rwx "$HERMES_DIR/$subdir"
    fi
done

echo "=== 5. 检查 bind mount 的配置文件是否可读 ==="
for f in "$HERMES_DIR/.env" "$HERMES_DIR/config.yaml"; do
    if [ -f "$f" ]; then
        chmod 644 "$f"
        echo "  ✓ $f"
    fi
done

echo "=== 6. 验证 ==="
ls -la $HERMES_DIR | head -20

echo "=== 完成，现在可以 docker compose up -d ==="
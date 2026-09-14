#!/usr/bin/env bash
# 单向同步：webui 侧设置 -> 脑侧（合并语义见同目录 sync-webui-to-brain.py 头部）
exec python3 /home/user/gateway/scripts/sync-webui-to-brain.py "$@"

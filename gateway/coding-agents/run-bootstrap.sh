#!/usr/bin/env sh
# ---------------------------------------------------------------------------
# 编码工具链引导 —— 薄壳入口（两个容器统一调这个）
#   优先执行持久卷内那份（可热更新，改完下次启动即生效，不必重建镜像）；
#   卷内缺失时回退到镜像内那份（新卷首次启动、裸跑镜像的场景）。
#   本文件同时存在于：/opt/data/coding-agents/（卷，优先）
#                     /opt/hermes/coding-agents/（镜像，兜底）
# ---------------------------------------------------------------------------
VOL=/opt/data/coding-agents/bootstrap.sh
IMG=/opt/hermes/coding-agents/bootstrap.sh

if [ -x "$VOL" ]; then exec "$VOL" "$@"; fi
if [ -x "$IMG" ]; then exec "$IMG" "$@"; fi
echo "[coding-agents] 引导脚本缺失（卷与镜像都没有），跳过"
exit 0

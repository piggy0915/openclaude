#!/bin/bash
# after-rebuild-cleanup.sh —— 重建镜像后的固定收尾（防构建缓存无限膨胀）
#
#   scripts/after-rebuild-cleanup.sh              常规：清理无引用的构建缓存 + 悬空镜像
#   scripts/after-rebuild-cleanup.sh --aggressive 激进：连"在用"的构建缓存一起清（下次重建会全量重跑）
#   scripts/after-rebuild-cleanup.sh --check      只看现状与可回收量，不清理
#
#   背景：每次 `docker compose build` 都会往构建缓存塞新层（实测峰值 20.34GB）。
#   注意：Docker 根目录 2026-09-13 起已迁到 /srv/docker（新盘），不再看 /var。
set -uo pipefail

say(){ printf '  %s\n' "$*"; }
ok(){ printf '✅ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
die(){ printf '❌ %s\n' "$*" >&2; exit 1; }

MODE=normal
case "${1:-}" in
  ""|--apply)     ;;
  --check|-c)     MODE=check ;;
  --aggressive|-a) MODE=aggressive ;;
  *) echo "用法: $0 [--check | --aggressive]" >&2; exit 2 ;;
esac

echo "===== 0. 前置 ====="
docker info >/dev/null 2>&1 || die "Docker 未运行"
ROOT=$(docker info 2>/dev/null | awk -F': ' '/Docker Root Dir/{print $2}')
say "Docker 根目录: $ROOT"
printf "  运行中容器: %s（本脚本不会重启/停止任何容器）\n" "$(docker ps -q | wc -l)"

echo
echo "===== 1. 清理前 ====="
docker system df | sed 's/^/  /'
df -h "$ROOT" | tail -1 | sed 's/^/  /'

if [ "$MODE" = check ]; then
  echo
  warn "--check：未执行任何清理"
  exit 0
fi

echo
echo "===== 2. 清理构建缓存 ====="
if [ "$MODE" = aggressive ]; then
  warn "--aggressive：将清空全部构建缓存（下次重建 base 需全量重跑，约 1h+）"
  docker builder prune -af | tail -2
else
  docker builder prune -f | tail -2
fi

echo
echo "===== 3. 清理悬空镜像 ====="
docker image prune -f | tail -2

echo
echo "===== 4. 清理后 ====="
docker system df | sed 's/^/  /'
USE=$(df --output=pcent "$ROOT" 2>/dev/null | tail -1 | tr -dc '0-9')
df -h "$ROOT" | tail -1 | sed 's/^/  /'

echo
if [ "${USE:-0}" -ge 70 ]; then
  warn "$ROOT 使用率 ${USE}%（≥70%）→ 建议执行：$0 --aggressive"
  exit 1
else
  ok "$ROOT 使用率 ${USE}%，余量充足"
fi

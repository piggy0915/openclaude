#!/usr/bin/env bash
# ============================================================
# 统一构建：hermes-base → hermes-agent → hermes-web-ui
# 用法： ./build.sh [base|hermes|webui|laya|all|desktop]   默认 all
#   base         公共基座(slim)     hermes-base:main           ← 官方 :v0.21.6-amd64
#   hermes       大脑镜像(slim)     hermes-agent:main          ← hermes-base:main
#   webui        WebUI 镜像         hermes-web-ui:0.7.31       ← hermes-base:main
#   all（默认）  两条链一起出：
#                  hermes-base:main         ← 官方 :v0.21.6-amd64           （webui 用）
#                  hermes-base:main-desktop ← 官方 :v0.21.6-amd64-desktop （大脑用）
#                  hermes-agent:main        ← hermes-base:main
#                  hermes-agent:main-desktop← hermes-base:main-desktop
#                  webui（见下）
#   desktop      只出桌面链（desktop 基座 + desktop 大脑），用于快速重建
#   laya         自托管判断引擎     laya:main                  ← ./laya（Jev 平替）
#                = `docker compose build laya`（服务定义在 docker-compose.yml）
#
# 口径：镜像名跟着来源走 —— 基于官方 v0.21.6-amd64 生成 = hermes-agent:main；
#       基于官方 v0.21.6-amd64-desktop 生成 = hermes-agent:main-desktop。
# 容器对应：hermes 容器用 hermes-agent:main-desktop，
#           webui 容器用 hermes-web-ui:0.7.31（源自 slim 基座）—— 见 docker-compose.yml。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# 2026-10-08 升到 v0.21.6（官方 v0.21.6 起启用平台化 tag：slim=:v0.21.6-amd64 / desktop=:v0.21.6-amd64-desktop）
# 回退到浮动 tag：UPSTREAM=nousresearch/hermes-agent:main ./build.sh
UPSTREAM=${UPSTREAM:-nousresearch/hermes-agent:rc.5-v0.21.7}
UPSTREAM_LATEST=${UPSTREAM_DESKTOP:-nousresearch/hermes-agent:latest}
UPSTREAM_STABLE=${UPSTREAM_DESKTOP:-nousresearch/hermes-agent:stable}
UPSTREAM_DESKTOP=${UPSTREAM_DESKTOP:-nousresearch/hermes-agent:v0.21.6-desktop}
UPSTREAM_MAIN=${UPSTREAM_DESKTOP:-nousresearch/hermes-agent:main}
TAG_BASE=${TAG_BASE:-hermes-base:main}
TAG_BASE_DESKTOP=${TAG_BASE_DESKTOP:-hermes-base:main-desktop}
TAG_HERMES=${TAG_HERMES:-hermes-agent:main}
TAG_HERMES_DESKTOP=${TAG_HERMES_DESKTOP:-hermes-agent:main-desktop}
TAG_WEBUI=${WEBUI_IMAGE:-hermes-web-ui:0.7.32}
TARGET=${1:-all}

build_base() {
  echo "==> [1/4] 公共基座(slim)     $TAG_BASE            ← $UPSTREAM"
  docker build -f Dockerfile.base --build-arg BASE_IMAGE="$UPSTREAM" -t "$TAG_BASE" .
}
build_latest() {
  echo "==> [1/4] 公共基座(slim)     $TAG_BASE            ← $UPSTREAM_LATEST"
  docker build -f Dockerfile.base --build-arg BASE_IMAGE="$UPSTREAM_LATEST" -t "$TAG_BASE" .
}
build_stable() {
  echo "==> [1/4] 公共基座(slim)     $TAG_BASE            ← $UPSTREAM_STABLE"
  docker build -f Dockerfile.base --build-arg BASE_IMAGE="$UPSTREAM_STABLE" -t "$TAG_BASE" .
}
build_base_desktop() {
  echo "==> [2/4] 公共基座(desktop)  $TAG_BASE_DESKTOP   ← $UPSTREAM_DESKTOP"
#  docker build -f Dockerfile.base --build-arg BASE_IMAGE="$UPSTREAM_DESKTOP" -t "$TAG_BASE_DESKTOP" .
}
build_hermes() {
  echo "==> [3/4] 大脑镜像(slim)     $TAG_HERMES           ← $TAG_BASE"
  docker build -f Dockerfile --build-arg BASE_IMAGE="$TAG_BASE" -t "$TAG_HERMES" .
}
build_hermes_desktop() {
  echo "==> [4/4] 大脑镜像(desktop)  $TAG_HERMES_DESKTOP  ← $TAG_BASE_DESKTOP"
#  docker build -f Dockerfile --build-arg BASE_IMAGE="$TAG_BASE_DESKTOP" -t "$TAG_HERMES_DESKTOP" .
}
build_webui() {
  echo "==> WebUI 镜像           $TAG_WEBUI            ← $TAG_BASE（webui 始终走 slim 基座）"
  echo "    提示：webui 构建当前是注释状态；需要重建时执行："
  echo "      docker build -f app/Dockerfile --build-arg BASE_IMAGE=$TAG_BASE -t $TAG_WEBUI app"
#  docker compose -f app/docker-compose.yml build
#  docker build -f app/Dockerfile --build-arg BASE_IMAGE="$TAG_BASE" -t "$TAG_WEBUI" app
}

build_laya() {
  echo "==> Laya 判断引擎镜像   laya:main             ← ./laya（权重烘入，见 docker-compose.yml 的 laya 服务）"
  docker compose build laya
}

case "$TARGET" in
  base)    build_base ;;
  latest)  build_latest ;;
  stable)  build_stable ;;
  hermes)  build_hermes ;;
  webui)   build_webui ;;
  laya)    build_laya ;;
  desktop) build_base_desktop; build_hermes_desktop ;;
  all)     build_base; build_base_desktop; build_hermes; build_hermes_desktop; build_webui ;;
  *) echo "用法: $0 [base|hermes|webui|laya|all|desktop]"; exit 2 ;;
esac
echo "==> 完成"

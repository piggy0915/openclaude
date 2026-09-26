#!/usr/bin/env bash
# ============================================================
# 统一构建：hermes-base → hermes-agent → hermes-web-ui
# 用法： ./build.sh [base|hermes|webui|all|desktop]   默认 all
#   base         公共基座(slim)     hermes-base:main           ← 官方 :main
#   hermes       大脑镜像(slim)     hermes-agent:main          ← hermes-base:main
#   webui        WebUI 镜像         hermes-web-ui:0.7.24       ← hermes-base:main
#   all（默认）  两条链一起出：
#                  hermes-base:main         ← 官方 :main          （webui 用）
#                  hermes-base:main-desktop ← 官方 :main-desktop  （大脑用）
#                  hermes-agent:main        ← hermes-base:main
#                  hermes-agent:main-desktop← hermes-base:main-desktop
#                  webui（见下）
#   desktop      只出桌面链（desktop 基座 + desktop 大脑），用于快速重建
#
# 口径：镜像名跟着来源走 —— 基于官方 main 生成 = hermes-agent:main；
#       基于官方 main-desktop 生成 = hermes-agent:main-desktop。
# 容器对应：hermes 容器用 hermes-agent:main-desktop，
#           webui 容器用 hermes-web-ui:0.7.24（源自 slim 基座）—— 见 docker-compose.yml。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

UPSTREAM=${UPSTREAM:-nousresearch/hermes-agent:main}
UPSTREAM_DESKTOP=${UPSTREAM_DESKTOP:-nousresearch/hermes-agent:main-desktop}
TAG_BASE=${TAG_BASE:-hermes-base:main}
TAG_BASE_DESKTOP=${TAG_BASE_DESKTOP:-hermes-base:main-desktop}
TAG_HERMES=${TAG_HERMES:-hermes-agent:main}
TAG_HERMES_DESKTOP=${TAG_HERMES_DESKTOP:-hermes-agent:main-desktop}
TAG_WEBUI=${WEBUI_IMAGE:-hermes-web-ui:0.7.24}
TARGET=${1:-all}

build_base() {
  echo "==> [1/4] 公共基座(slim)     $TAG_BASE            ← $UPSTREAM"
  docker build -f Dockerfile.base --build-arg BASE_IMAGE="$UPSTREAM" -t "$TAG_BASE" .
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

case "$TARGET" in
  base)    build_base ;;
  hermes)  build_hermes ;;
  webui)   build_webui ;;
  desktop) build_base_desktop; build_hermes_desktop ;;
  all)     build_base; build_base_desktop; build_hermes; build_hermes_desktop; build_webui ;;
  *) echo "用法: $0 [base|hermes|webui|all|desktop]"; exit 2 ;;
esac
echo "==> 完成"

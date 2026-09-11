#!/usr/bin/env bash
# ============================================================
# 统一构建：hermes-base → hermes-agent → hermes-web-ui
# 用法： ./build.sh [base|hermes|webui|all]   默认 all
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

TAG_BASE=${TAG_BASE:-hermes-base:main}
TAG_HERMES=${TAG_HERMES:-hermes-agent:main}
TAG_WEBUI=${WEBUI_IMAGE:-hermes-web-ui:0.7.19}
TARGET=${1:-all}

build_base() {
  echo "==> [1/3] 公共基座  $TAG_BASE"
  docker build -f Dockerfile.base -t "$TAG_BASE" .
}
build_hermes() {
  echo "==> [2/3] 大脑镜像  $TAG_HERMES"
  docker build -f Dockerfile -t "$TAG_HERMES" .
}
build_webui() {
  echo "==> [3/3] WebUI 镜像 $TAG_WEBUI"
  docker build -f app/Dockerfile --build-arg BASE_IMAGE="$TAG_BASE" -t "$TAG_WEBUI" app
}

case "$TARGET" in
  base)   build_base ;;
  hermes) build_hermes ;;
  webui)  build_webui ;;
  all)    build_base; build_hermes; build_webui ;;
  *) echo "用法: $0 [base|hermes|webui|all]"; exit 2 ;;
esac
echo "==> 完成"

#!/usr/bin/env bash
# ============================================================================
# 重建后核验：编码工具链固化（Reasonix + OpenCodeReview / ocr）
# 用途：用户重建 hermes-base / hermes-agent / hermes-web-ui 并重启容器后，
#       一条命令确认「镜像自带能力 + 启动引导」都到位。只读，不改任何配置。
# 用法：bash /home/user/gateway/scripts/verify-coding-agents.sh
# ============================================================================
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
chk()  { if [ "$2" = "1" ]; then ok "$1"; else bad "$1"; fi; }

echo "== 1) 镜像内二进制与运行环境（hermes 容器）=="
docker exec hermes bash -lc 'ocr --version 2>/dev/null | head -1' | grep -q 'open-code-review' && ok "ocr 二进制在镜像内" || bad "ocr 缺失（Dockerfile.base 步骤 5.2 未生效？）"
docker exec hermes bash -lc 'echo $REASONIX_HOME' | grep -q '/opt/data/reasonix' && ok "REASONIX_HOME=/opt/data/reasonix" || bad "REASONIX_HOME 未设置"
docker exec hermes bash -lc 'echo $PATH' | grep -q '/opt/data/npm-global/bin' && ok "PATH 含 /opt/data/npm-global/bin" || bad "PATH 未含 npm-global/bin"
docker exec hermes bash -lc 'test -L /root/.reasonix && test -L /root/.opencodereview' && ok "两个家目录符号链接存在" || bad "符号链接缺失"

echo "== 2) 配置实体（持久卷）与密钥是否到位 =="
docker exec hermes bash -lc 'test -s /opt/data/reasonix/config.toml' && ok "reasonix config.toml 在卷内" || bad "reasonix config.toml 缺失"
docker exec hermes bash -lc 'test -s /opt/data/reasonix/.env' && ok "reasonix .env（密钥）在卷内" || bad "reasonix .env 缺失"
docker exec hermes bash -lc 'test -s /opt/data/opencodereview/config.json' && ok "ocr config.json 在卷内" || bad "ocr config.json 缺失"

echo "== 3) 启动引导是否被调用过（entrypoint / HERMES_PATCH_SCRIPT）=="
if docker logs hermes 2>&1 | grep -q 'coding-agents'; then
    docker logs hermes 2>&1 | grep 'coding-agents' | tail -3 | sed 's/^/      /'
    ok "hermes 容器启动时跑过引导脚本"
else
    bad "hermes 日志里无 coding-agents 行（entrypoint 钩子未生效？）"
fi
if docker logs hermes-webui 2>&1 | grep -q 'optional Hermes patch not found'; then
    bad "webui 的 HERMES_PATCH_SCRIPT 指向的脚本不存在（webui 镜像未重建？）"
elif docker logs hermes-webui 2>&1 | grep -q '\[studio\] optional Hermes patch failed'; then
    bad "webui 引导脚本执行失败（看日志）"
else
    ok "webui 侧钩子无报错"
fi

echo "== 4) 引导脚本幂等性（重跑应零写入）=="
before=$(docker exec hermes bash -lc 'sha256sum /opt/data/reasonix/config.toml /opt/data/reasonix/.env /opt/data/opencodereview/config.json 2>/dev/null' | sha256sum | cut -c1-16)
docker exec hermes bash -lc '/opt/hermes/coding-agents/bootstrap.sh' >/dev/null 2>&1
after=$(docker exec hermes bash -lc 'sha256sum /opt/data/reasonix/config.toml /opt/data/reasonix/.env /opt/data/opencodereview/config.json 2>/dev/null' | sha256sum | cut -c1-16)
[ "$before" = "$after" ] && ok "幂等：三个配置文件哈希未变 ($before)" || bad "重跑改动了配置 ($before -> $after)"

echo "== 5) 连通性（真实调用 LLM）=="
docker exec hermes bash -lc 'timeout 90 ocr llm test 2>&1 | tail -2' | grep -q 'Connection test successful' && ok "ocr llm test 通过" || bad "ocr llm test 未通过"
k=$(docker exec hermes bash -lc 'reasonix doctor 2>&1 | grep -c "key:present"' 2>/dev/null | tr -d '\r')
[ "${k:-0}" -ge 1 ] && ok "reasonix key:present=$k" || bad "reasonix 未识别密钥"

echo
echo "== 汇总：通过 $PASS 项，失败 $FAIL 项 =="
[ "$FAIL" -eq 0 ] && echo "全部通过 —— 镜像固化生效。" || echo "有失败项，见上。"
echo
echo "（附：仅当需要跑真实审查时）cd /workspace/projects/zgjy-cloud && ocr review --from HEAD~5 --to HEAD --format json --output /tmp/ocr-review.json"
exit 0

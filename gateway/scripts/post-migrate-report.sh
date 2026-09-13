#!/bin/bash
# 迁移后自动体检：输出到日志，供恢复会话后直接读取
echo
echo "======== POST-MIGRATION REPORT  $(date '+%F %T')  ========"
echo
echo "--- 1. Docker 根目录 ---"
docker info 2>/dev/null | grep -E "Docker Root Dir|Storage Driver" || echo "  (docker info 失败)"

echo
echo "--- 2. 容器/镜像计数 ---"
printf "  运行中: %s   总容器: %s   镜像: %s\n" \
  "$(docker ps -q 2>/dev/null | wc -l)" "$(docker ps -aq 2>/dev/null | wc -l)" "$(docker images -q 2>/dev/null | wc -l)"

echo
echo "--- 3. 未运行的容器（无 restart 策略的不会自动回来）---"
docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep -viE "up " | sed 's/^/  /' || echo "  （全部运行中）"

echo
echo "--- 4. hermes 两个容器 ---"
docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep -i hermes | sed 's/^/  /'

echo
echo "--- 5. 磁盘 ---"
df -hT /var /srv/docker 2>/dev/null | sed 's/^/  /'
echo "  旧目录: $(du -sh /var/lib/docker 2>/dev/null | cut -f1)   新目录: $(du -sh /srv/docker 2>/dev/null | cut -f1)"

echo
echo "--- 6. hermes 关键不变量 ---"
printf "  gateway uid(应0): %s\n" "$(docker exec hermes ps -o uid= -p 1 2>/dev/null | tr -d ' ')"
printf "  WAL 保护计数(应4): %s\n" "$(docker exec hermes grep -c 'Refusing to open or write' /home/agent/.hermes/logs/errors.log 2>/dev/null)"
printf "  socat 6060: %s\n" "$(docker exec hermes curl -s -o /dev/null -w 'http=%{http_code}' -m 6 http://127.0.0.1:6060/ 2>/dev/null)"
printf "  配置快照心跳: %s\n" "$(tail -1 /home/user/gateway/data/hermes/config-snapshots/.last-run 2>/dev/null)"

echo
echo "--- 7. 迁移脚本退出码 ---"
echo "  ${1:-未传入}（0=成功；1=校验失败已自动回滚）"
echo
echo "======== REPORT END ========"

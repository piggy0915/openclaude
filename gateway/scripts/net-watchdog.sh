#!/usr/bin/env bash
# net-watchdog.sh — 宿主休眠/断网后自动恢复容器 DNS 与网络（Hermes 栈）
# 2026-09-18 创建；v2 加「不打扰」护栏；v3 唤醒路径加 NTP 校时（宿主休眠会冻结 VM 时钟）
#
# 用法：
#   net-watchdog.sh --check            仅检查；健康 exit 0
#   net-watchdog.sh --cycle            看门狗一轮（timer 用）：连续失败达阈值才动作
#   net-watchdog.sh --fix-wake         宿主唤醒钩子用：等就绪 → 校时 → 按需修复
#   net-watchdog.sh --status           状态、计数、最近日志
#   net-watchdog.sh --guards           只打印护栏状态（排查用）
#   net-watchdog.sh --pause [30m|2h|秒] 维护暂停（重建镜像/停机前先跑）
#   net-watchdog.sh --resume           取消暂停
#   DRY_RUN=1 net-watchdog.sh --cycle  只记录将要执行的动作，不真执行
set -uo pipefail

# ---------------- 可调参数 ----------------
FAIL_THRESHOLD="${FAIL_THRESHOLD:-3}"            # 连续失败达此值才动手
WAKE_WAIT_MAX="${WAKE_WAIT_MAX:-180}"            # --fix-wake 等待就绪上限（秒）
WAIT_STEP="${WAIT_STEP:-5}"
COOLDOWN="${COOLDOWN:-900}"                      # 两次修复阶梯最小间隔（秒）
MAX_LADDER_PER_HOUR="${MAX_LADDER_PER_HOUR:-3}"
THROTTLE_WINDOW="${THROTTLE_WINDOW:-600}"        # 同一句「跳过」日志最小间隔（秒）
DOCKER_UPTIME_GUARD="${DOCKER_UPTIME_GUARD:-90}" # dockerd 启动后多久内不动手
TIME_MAX_OFFSET="${TIME_MAX_OFFSET:-30}"         # 校时阈值：NTP 偏差超过多少秒才强制校时
IDE_TUNNEL_UNIT="${IDE_TUNNEL_UNIT:-hermes-ide-mcp-tunnel}"  # Win11 IDEA MCP 的 SSH 隧道 systemd 单元
IDE_TUNNEL_HOST="${IDE_TUNNEL_HOST:-172.17.0.1}"
IDE_TUNNEL_PORT="${IDE_TUNNEL_PORT:-16434}"
IDE_TUNNEL_HOSTHDR="${IDE_TUNNEL_HOSTHDR:-127.0.0.1:64342}"  # 经隧道探活时用的 Host 头（IDE 校验）
TUNNEL_COOLDOWN="${TUNNEL_COOLDOWN:-600}"        # 隧道重建冷却（秒），防热循环
STATE_DIR="/run/hermes-net-watchdog"
LOG="/var/log/hermes-net-watchdog.log"
PAUSE_FILE="${PAUSE_FILE:-/home/user/gateway/.net-watchdog-pause}"
PROBE_HOST="${PROBE_HOST:-api.deepseek.com}"
PROBE_PORT="${PROBE_PORT:-443}"
IFACE="${IFACE:-eth0}"
APP_CONTAINER="${APP_CONTAINER:-hermes}"
PEER_CONTAINER="${PEER_CONTAINER:-hermes-webui}"
DRY_RUN="${DRY_RUN:-0}"
# -----------------------------------------

mkdir -p "$STATE_DIR"
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; trim_log; }
trim_log(){ local s; s=$(stat -c%s "$LOG" 2>/dev/null || echo 0); if [ "$s" -gt 5242880 ]; then tail -c 2621440 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; fi; }
log_throttled(){ local f="$STATE_DIR/last_skip" now last; now=$(date +%s); last=$(cat "$f" 2>/dev/null || echo 0)
  if [ $(( now - last )) -ge "$THROTTLE_WINDOW" ]; then log "$*"; echo "$now" > "$f"; fi; }
act(){ if [ "$DRY_RUN" = "1" ]; then log "[dry-run] 将要执行: $*"; else "$@"; fi; }
nap(){ if [ "$DRY_RUN" != "1" ]; then sleep "$1"; fi; }

# ---------------- 连通性检查 ----------------
chk_route(){ ip route get 8.8.8.8 >/dev/null 2>&1; }
chk_dns_host(){ getent hosts "$PROBE_HOST" >/dev/null 2>&1; }
chk_app(){ docker exec -e H="$PROBE_HOST" -e P="$PROBE_PORT" "$APP_CONTAINER" \
    python3 -c 'import os,socket;s=socket.create_connection((os.environ["H"],int(os.environ["P"])),5);s.close()' >/dev/null 2>&1; }
ok_now(){ chk_route && chk_app; }

# ---------------- 校时（只用 NTP 中位数）----------------
# 宿主休眠期间 VM 时钟冻结，唤醒后可能滞后数十分钟（会把 cron 定时任务带偏）。
# 实测 CDN 的 HTTP Date 不可信（同一时刻淘宝 +13.2s、Apple +24.7s），拿它 date -s 只会引入误差；
# 测不到 NTP 就不动时钟：宁可不修，不可修错。
ntp_offset(){
  python3 -c "
import socket, struct, time
def sntp(host, timeout=4):
    p = b'\x1b' + 47 * b'\x00'
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(timeout)
    try:
        t0 = time.time(); s.sendto(p, (host, 123)); d, _ = s.recvfrom(48); t3 = time.time()
        u = struct.unpack('!12I', d[:48]); t = u[10] + float(u[11]) / 2**32 - 2208988800
        return t - (t0 + t3) / 2
    except Exception:
        return None
    finally:
        s.close()
offs = [o for o in (sntp(h) for h in ('ntp.aliyun.com','time.windows.com','pool.ntp.org','cn.pool.ntp.org')) if o is not None]
if len(offs) >= 2:
    offs.sort(); print(int(round(offs[len(offs)//2])))
" 2>/dev/null
}
fix_clock(){
  local off off2
  off=$(ntp_offset)
  [ -n "$off" ] || { log_throttled "校时：取不到 NTP 时间，跳过"; return 1; }
  if [ "${off#-}" -le "$TIME_MAX_OFFSET" ]; then return 0; fi
  log "校时：NTP 偏移 ${off}s > ${TIME_MAX_OFFSET}s，强制 NTP 步进"
  timedatectl set-ntp false >/dev/null 2>&1
  systemctl restart systemd-timesyncd >/dev/null 2>&1
  timedatectl set-ntp true >/dev/null 2>&1
  sleep 5
  off2=$(ntp_offset)
  if [ -n "$off2" ] && [ "${off2#-}" -gt "$TIME_MAX_OFFSET" ]; then
    log "校时：NTP 步进未生效（仍偏 ${off2}s），按 NTP 中位数直接 set"
    date -s "$(date -d "@$(( $(date +%s) - off2 ))" '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1
    hwclock --systohc >/dev/null 2>&1
  fi
  log "校时完成（现偏移 $(ntp_offset)s）"
}

# ---------------- IDE 隧道健康（Hermes → Win11 IDEA MCP）----------------
# 隧道断了不影响模型连通性，但会让 IDEA 的 56 个工具失效；这里独立于修复阶梯，带冷却重建。
# 注意：本地端口在听 ≠ 远端可用（IDEA 关掉时 ssh 的 -L 监听仍在）→ 因此分两级判定：
#   · 本地无监听            → 重启 unit
#   · 本地在听但远端无响应   → 只提示（多半 IDEA 未运行/MCP 未启用），不重启，避免无意义循环
ide_tunnel_local(){ timeout 3 bash -c "cat </dev/null >/dev/tcp/${IDE_TUNNEL_HOST}/${IDE_TUNNEL_PORT}" >/dev/null 2>&1; }
ide_tunnel_probe(){
  python3 -c "
import socket
try:
    s = socket.create_connection(('$IDE_TUNNEL_HOST', $IDE_TUNNEL_PORT), 5)
    s.sendall(b'POST /stream HTTP/1.1\r\nHost: $IDE_TUNNEL_HOSTHDR\r\nAccept: application/json, text/event-stream\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}')
    s.settimeout(5)
    print('alive' if s.recv(32) else 'no-response')
    s.close()
except Exception:
    print('unreachable')
" 2>/dev/null
}
ide_tunnel_check(){
  [ -f "/etc/systemd/system/${IDE_TUNNEL_UNIT}.service" ] || return 0
  local force="${1:-}" now last f="$STATE_DIR/last_tunnel_restart"
  if ! ide_tunnel_local; then
    now=$(date +%s); last=$(cat "$f" 2>/dev/null || echo 0)
    if [ "$force" != "force" ] && [ $(( now - last )) -lt "$TUNNEL_COOLDOWN" ]; then return 0; fi
    echo "$now" > "$f"
    log "IDE 隧道本地端口 ${IDE_TUNNEL_HOST}:${IDE_TUNNEL_PORT} 无监听 → 重启 ${IDE_TUNNEL_UNIT}"
    act systemctl restart "$IDE_TUNNEL_UNIT" >/dev/null 2>&1
    nap 3
    if ide_tunnel_local; then log "IDE 隧道已重建（本地监听恢复）"; else log "IDE 隧道重建失败，需人工介入"; fi
    return 0
  fi
  case "$(ide_tunnel_probe)" in
    alive) : ;;
    *) log_throttled "IDE 隧道本地在听但远端无响应 → 多半是 Win11 上 IDEA 未运行或 MCP Server 未勾选（隧道不重启；IDEA 一开即自动恢复）" ;;
  esac
}

# ---------------- 护栏（不打扰）----------------
paused(){ # 0 = 暂停中
  [ -f "$PAUSE_FILE" ] || return 1
  local until; until=$(tr -dc '0-9' < "$PAUSE_FILE" 2>/dev/null)
  [ -z "$until" ] && return 0
  [ "$(date +%s)" -lt "$until" ] && return 0
  rm -f "$PAUSE_FILE"; return 1
}
maint_in_progress(){ # 构建 / compose 操作 / 容器化 builder 运行中 → 绝不重启 dockerd
  local hit
  hit=$(ps -eo comm=,args= 2>/dev/null | awk '
    { n=split($0,t," ")
      c0=t[1]; m0=split(c0,q,"/"); c0=q[m0]
      fam = (c0 ~ /^docker(-[a-z0-9]+)?$/ || c0=="buildx" || c0=="buildctl" || c0=="podman")
      di=0
      for(i=1;i<=n;i++){ b=t[i]; m=split(b,c,"/"); b=c[m]
        if(b ~ /^(docker|docker-[a-z]+|buildx|buildctl|podman)$/){ di=i; break } }
      okpre=0
      if(di>0){ okpre=1
        for(j=1;j<di;j++){ p=t[j]; m=split(p,q,"/"); p=q[m]
          if(p ~ /^[0-9]+$/||p=="sudo"||p=="doas"||p=="nice"||p=="ionice"||p=="timeout"||p=="systemd-run"||p=="env"||p=="command"||p=="nohup"||p=="-n"||p=="-u") continue
          okpre=0 } }
      if(fam||okpre){
        for(k=(di>0?di:1)+1;k<=n;k++){ b=t[k]; m=split(b,c,"/"); b=c[m]
          if(b=="build"||b=="up"||b=="down"||b=="stop"||b=="start"||b=="restart"||b=="pull"||b=="bake"||b=="push") found=1 } }
    }
    END{ print (found?"yes":"no") }')
  [ "$hit" = "yes" ] && return 0
  docker ps --format '{{.Image}}' 2>/dev/null | grep -qi 'buildkit' && return 0
  return 1
}
app_running(){ [ "$(docker inspect -f '{{.State.Running}}' "$APP_CONTAINER" 2>/dev/null)" = "true" ]; }
docker_fresh(){ local st t; st=$(systemctl show -p ActiveEnterTimestamp --value docker 2>/dev/null); [ -z "$st" ] && return 1
  t=$(date -d "$st" +%s 2>/dev/null || echo 0); [ $(( $(date +%s) - t )) -lt "$DOCKER_UPTIME_GUARD" ]; }
guards_block(){ # 输出阻止原因；无输出=可以动作
  if paused; then echo "维护暂停中（$PAUSE_FILE）"; return 0; fi
  if ! app_running; then echo "应用容器 $APP_CONTAINER 未运行（已 down 或正在重建）"; return 0; fi
  if maint_in_progress; then echo "docker 构建/compose 操作进行中"; return 0; fi
  if docker_fresh; then echo "dockerd 启动不足 ${DOCKER_UPTIME_GUARD}s"; return 0; fi
  return 1
}

# ---------------- 状态计数 ----------------
failcount(){ cat "$STATE_DIR/fails" 2>/dev/null || echo 0; }
set_failcount(){ echo "$1" > "$STATE_DIR/fails"; }
reset_failcount(){ set_failcount 0; }
ladder_history(){ cat "$STATE_DIR/ladder_ts" 2>/dev/null || true; }
record_ladder(){ echo "$(date +%s)" >> "$STATE_DIR/ladder_ts"; tail -n "$MAX_LADDER_PER_HOUR" "$STATE_DIR/ladder_ts" > "$STATE_DIR/ladder_ts.tmp" && mv "$STATE_DIR/ladder_ts.tmp" "$STATE_DIR/ladder_ts"; }
ladder_allowed(){
  local last now cnt
  last=$(tail -n1 "$STATE_DIR/ladder_ts" 2>/dev/null || echo 0); now=$(date +%s)
  if [ $(( now - last )) -lt "$COOLDOWN" ]; then log "冷却中（距上次阶梯 $(( now - last ))s < ${COOLDOWN}s），跳过"; return 1; fi
  cnt=$(ladder_history | awk -v now="$now" '$1 > now-3600' | wc -l)
  if [ "$cnt" -ge "$MAX_LADDER_PER_HOUR" ]; then log "已达每小时上限 ${MAX_LADDER_PER_HOUR} 次，跳过"; return 1; fi
  return 0
}

# ---------------- 修复阶梯 ----------------
ladder(){
  local why; why=$(guards_block || true)
  if [ -n "$why" ]; then log "放弃自动修复：$why"; return 1; fi
  record_ladder
  log "修复阶梯开始（route=$(chk_route && echo ok || echo bad) dns=$(chk_dns_host && echo ok || echo bad) app=$(chk_app && echo ok || echo bad) dry_run=$DRY_RUN）"
  act dhcpcd -n "$IFACE" >/dev/null 2>&1 || true
  nap 15
  if ok_now; then log "阶梯① dhcpcd -n $IFACE 后已恢复"; return 0; fi
  why=$(guards_block || true); if [ -n "$why" ]; then log "放弃阶梯②/③：$why"; return 1; fi
  act systemctl restart docker >/dev/null 2>&1
  nap 20
  if ok_now; then log "阶梯② 重启 dockerd 后已恢复"; return 0; fi
  why=$(guards_block || true); if [ -n "$why" ]; then log "放弃阶梯③：$why"; return 1; fi
  for c in "$APP_CONTAINER" "$PEER_CONTAINER"; do act docker restart "$c" >/dev/null 2>&1 || true; done
  nap 25
  if ok_now; then log "阶梯③ 重启应用容器后已恢复"; return 0; fi
  log "阶梯①②③ 均无效：仍需人工介入（请检查宿主 Wi-Fi / 虚拟交换机）"
  return 1
}

# ---------------- 入口 ----------------
do_check(){
  local r d a; r=$(chk_route && echo ok || echo FAIL); d=$(chk_dns_host && echo ok || echo FAIL); a=$(chk_app && echo ok || echo FAIL)
  printf 'route=%s dns(host)=%s app(container)=%s fails=%s\n' "$r" "$d" "$a" "$(failcount)"
  ok_now
}
do_cycle(){
  docker info >/dev/null 2>&1 || { log_throttled "docker 未运行，跳过本轮"; return 0; }
  ide_tunnel_check
  local why; why=$(guards_block || true)
  if [ -n "$why" ]; then log_throttled "跳过本轮：$why（不计失败）"; return 0; fi
  if ok_now; then
    if [ "$(failcount)" != "0" ]; then log "已恢复正常（此前连续失败 $(failcount) 次）"; fi
    reset_failcount; return 0
  fi
  local n; n=$(( $(failcount) + 1 )); set_failcount "$n"
  log "连续失败第 $n 次（route=$(chk_route && echo ok || echo bad) dns=$(chk_dns_host && echo ok || echo bad) app=$(chk_app && echo ok || echo bad)）"
  [ "$n" -ge "$FAIL_THRESHOLD" ] || return 0
  ladder_allowed || return 0
  if ladder; then reset_failcount; else set_failcount 0; fi
}
do_fix_wake(){
  log "唤醒钩子触发：等待网络就绪（最多 ${WAKE_WAIT_MAX}s）"
  local waited=0 why
  while [ "$waited" -lt "$WAKE_WAIT_MAX" ]; do
    if ok_now; then ide_tunnel_check force; fix_clock; log "唤醒后 ${waited}s 内自愈，无需网络动作"; reset_failcount; return 0; fi
    why=$(guards_block || true)
    if [ -n "$why" ]; then log "唤醒钩子按护栏退出：$why"; fix_clock; return 0; fi
    sleep "$WAIT_STEP"; waited=$(( waited + WAIT_STEP ))
  done
  why=$(guards_block || true)
  if [ -n "$why" ]; then log "放弃自动修复：$why"; fix_clock; reset_failcount; return 0; fi
  if ladder_allowed; then if ladder; then reset_failcount; fi; else reset_failcount; fi
  fix_clock
}
do_guards(){
  printf 'paused=%s\napp_running=%s\nmaint_in_progress=%s\ndockerd_fresh=%s\n' \
    "$(paused && echo yes || echo no)" "$(app_running && echo yes || echo no)" \
    "$(maint_in_progress && echo yes || echo no)" "$(docker_fresh && echo yes || echo no)"
  printf 'PAUSE_FILE=%s PROBE=%s:%s APP=%s DRY_RUN=%s\n' "$PAUSE_FILE" "$PROBE_HOST" "$PROBE_PORT" "$APP_CONTAINER" "$DRY_RUN"
}
do_pause(){ local arg="${1:-}"; if [ -z "$arg" ]; then echo "(无限期)" > "$PAUSE_FILE"; log "维护暂停：无限期"; else
    local secs; case "$arg" in *h) secs=$(( ${arg%h} * 3600 ));; *m) secs=$(( ${arg%m} * 60 ));; *) secs="$arg";; esac
    echo "$(( $(date +%s) + secs ))" > "$PAUSE_FILE"; log "维护暂停 ${arg}（到 $(date -d "@$(( $(date +%s) + secs ))" '+%F %T')）"; fi
  echo "已暂停：$(cat "$PAUSE_FILE")"; }
do_resume(){ rm -f "$PAUSE_FILE"; log "维护暂停已解除"; echo "已解除暂停"; }
do_status(){
  echo "PROBE=${PROBE_HOST}:${PROBE_PORT} IFACE=${IFACE} THRESHOLD=${FAIL_THRESHOLD} COOLDOWN=${COOLDOWN}s TIME_MAX_OFFSET=${TIME_MAX_OFFSET}s DRY_RUN=${DRY_RUN}"
  do_guards
  do_check
  echo "NTP 偏移=$(ntp_offset)s"
  echo "IDE 隧道: local=$(ide_tunnel_local && echo up || echo DOWN) remote=$(ide_tunnel_local && ide_tunnel_probe || echo n/a)（单元 active=$(systemctl is-active ${IDE_TUNNEL_UNIT} 2>/dev/null)）"
  echo "ladder_history=$(ladder_history | tr '\n' ',')"
  echo "--- 最近日志 ---"; tail -n 10 "$LOG" 2>/dev/null || echo "(无)"
}

case "${1:---cycle}" in
  --check) do_check ;;
  --cycle) do_cycle ;;
  --fix-wake) do_fix_wake ;;
  --guards) do_guards ;;
  --pause) do_pause "${2:-}" ;;
  --resume) do_resume ;;
  --status) do_status ;;
  *) echo "用法: $0 {--check|--cycle|--fix-wake|--guards|--pause [30m|2h|秒]|--resume|--status}"; exit 2 ;;
esac

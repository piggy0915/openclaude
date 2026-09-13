#!/bin/bash
# Hermes 配置快照：查看 / 对比 / 恢复
#
#   restore-config.sh --list [config.yaml|.env]   列出快照（时间/大小/段数）
#   restore-config.sh --diff <快照名或路径>        与 live 逐段对比
#   restore-config.sh --apply <快照名或路径>       备份 live 后恢复该快照
#   restore-config.sh --status                    当前 live 与最近快照的差异摘要
#
set -u

HERMES_DIR=/home/user/gateway/data/hermes
SNAP_DIR="$HERMES_DIR/config-snapshots"
CTR=hermes
CHOME=/home/agent/.hermes

usage() { sed -n '2,9p' "$0" | sed 's/^# \?//'; exit 1; }
keys_of() { grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*:' "$1" 2>/dev/null | tr -d ':' | sort -u; }
to_abs()  { [ -f "$1" ] && readlink -f "$1" || readlink -f "$SNAP_DIR/$1" 2>/dev/null; }
base_of() {
  local b; b=$(basename "$1")
  case "$b" in
    config.yaml*) echo config.yaml ;;
    .env*)        echo .env ;;
    *)            echo "$b" ;;
  esac
}

# YAML 校验：优先宿主 pyyaml；否则回落到容器（把路径换算成容器可见路径）
validate_yaml() {
  local f="$1"
  if python3 -c 'import yaml' 2>/dev/null; then
    python3 -c 'import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));print("  YAML 合法，顶层键",len(d or {}))' "$f"
    return $?
  fi
  local cpath tmp=""
  case "$f" in
    "$HERMES_DIR"/*) cpath="$CHOME/${f#$HERMES_DIR/}" ;;
    *) tmp="$SNAP_DIR/.validate-tmp.yaml"; cp -f "$f" "$tmp"; cpath="$CHOME/config-snapshots/.validate-tmp.yaml" ;;
  esac
  docker exec "$CTR" /opt/hermes/.venv/bin/python -c \
    'import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));print("  YAML 合法，顶层键",len(d or {}))' "$cpath"
  local rc=$?
  [ -n "$tmp" ] && rm -f "$tmp"
  return $rc
}

case "${1:-}" in
  --list)
    pat="${2:-}"
    echo "快照目录：$SNAP_DIR"
    ls -1At "$SNAP_DIR" 2>/dev/null | while read -r b; do
      f="$SNAP_DIR/$b"
      [ -f "$f" ] || continue
      [ "$b" = "snapshots.log" ] && continue   # 点开头文件（.env 快照 / .last-run）用 -A 才能列出
      [ "$b" = ".last-run" ] && continue
      if [ -n "$pat" ]; then case "$b" in *"$pat"*) ;; *) continue ;; esac; fi
      printf '  %-46s %8s字节  段数:%-4s  %s\n' "$b" "$(stat -c %s "$f")" "$(keys_of "$f" | wc -l)" "$(date -r "$f" '+%F %T')"
    done
    ;;

  --diff|--apply)
    snap=$(to_abs "${2:-}")
    [ -n "$snap" ] && [ -f "$snap" ] || { echo "找不到快照：${2:-}"; exit 2; }
    base=$(base_of "$snap")
    live="$HERMES_DIR/$base"
    [ -f "$live" ] || { echo "live 文件不存在：$live"; exit 2; }

    if [ "$1" = "--diff" ]; then
      echo "快照 : $snap  ($(stat -c %s "$snap") 字节)"
      echo "live : $live  ($(stat -c %s "$live") 字节)"
      echo
      echo "=== 仅 live 有（快照里缺的段）==="; comm -23 <(keys_of "$live") <(keys_of "$snap") | sed 's/^/  + /'
      echo "=== 仅快照有（apply 后会补回的段）==="; comm -13 <(keys_of "$live") <(keys_of "$snap") | sed 's/^/  - /'
      echo "=== 两边都有（快照内容更长的段）==="
      comm -12 <(keys_of "$live") <(keys_of "$snap") | while read -r k; do
        a=$(awk -v k="$k" '$0 ~ "^"k":" {p=1;next} /^[a-zA-Z_]/ {p=0} p' "$snap" | wc -l)
        b=$(awk -v k="$k" '$0 ~ "^"k":" {p=1;next} /^[a-zA-Z_]/ {p=0} p' "$live"  | wc -l)
        [ "$a" -gt "$b" ] && printf '  %-28s 快照 %s 行 / live %s 行\n' "$k" "$a" "$b"
      done
      exit 0
    fi

    echo "== 校验（$base）=="
    if [ "$base" = ".env" ]; then echo "  (.env 跳过 YAML 校验)"; else
      validate_yaml "$snap" || { echo "  ❌ 校验失败，未恢复"; exit 3; }
    fi
    ts=$(date +%Y%m%d-%H%M%S)
    cp -p "$live" "$live.pre-restore-$ts" || exit 4
    install -m 664 -o 10000 -g 10000 "$snap" "$live" || exit 5
    echo "✅ 已恢复：$live"
    echo "   恢复前副本：$(basename "$live").pre-restore-$ts"
    echo "   段数：$(keys_of "$live" | wc -l)（快照 $(keys_of "$snap" | wc -l)）"
    echo "   生效：容器启动时读取 → docker stop hermes hermes-webui && docker start hermes hermes-webui"
    ;;

  --status)
    for base in config.yaml .env; do
      live="$HERMES_DIR/$base"
      [ -f "$live" ] || continue
      snap=$(ls -1t "$SNAP_DIR/$base-"* 2>/dev/null | head -1)
      lh=$(sha256sum "$live" | cut -c1-8)
      sh=$(basename "${snap:-x}" | sed -E 's/.*-([0-9a-f]{8})$/\1/')
      if [ "$lh" = "$sh" ]; then
        printf '  %-12s ✅ 与最近快照一致 (%s，段数 %s)\n' "$base" "$lh" "$(keys_of "$live" | wc -l)"
      else
        printf '  %-12s ⚠️ 已变化：live=%s 最近快照=%s\n' "$base" "$lh" "$sh"
        if [ "$base" = config.yaml ] && [ -n "$snap" ]; then
          echo "     live 独有段："; comm -23 <(keys_of "$live") <(keys_of "$snap") | sed 's/^/       + /'
          echo "     快照独有段（已被丢掉）："; comm -13 <(keys_of "$live") <(keys_of "$snap") | sed 's/^/       - /'
        fi
      fi
    done
    ;;

  *) usage ;;
esac

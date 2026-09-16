#!/bin/bash
# github-read.sh —— 受限网络下的 GitHub 只读访问（API 优先）
#
# 本机实测（2026-09-15）：
#   ✅ api.github.com          → 200（读文件/树/issue/PR/搜索；匿名 60 次/时，带 token 5000 次/时）
#   ✅ codeload.github.com     → 301（整仓 tar 包下载，等效 clone 读码）
#   ❌ github.com              → 000 不通
#   ❌ raw.githubusercontent.com → 000 不通（所以别用 download_url，要用 contents API）
#   ❌ git clone https://github.com/... → 挂住超时
#
# 令牌：优先 $GITHUB_TOKEN，否则读 $GITHUB_TOKEN_FILE（默认 /opt/data/.github-token，0600）。
#       无令牌时匿名可用（仅公开仓库、60 次/时）。
#
# 用法：
#   github-read.sh quota                          # 配额
#   github-read.sh whoami                         # 令牌身份（验令牌是否有效）
#   github-read.sh info OWNER/REPO                # 仓库元信息
#   github-read.sh file OWNER/REPO PATH [REF]     # 读文件正文
#   github-read.sh tree OWNER/REPO [REF]          # 列目录（默认只顶层）
#   github-read.sh tree OWNER/REPO --full         # 全树
#   github-read.sh search "关键词"                # 搜仓库
#   github-read.sh tarball OWNER/REPO [REF] [DEST]  # 下载整仓 tar.gz 并解压
#   github-read.sh api /repos/OWNER/REPO/issues   # 直接打任意 API 路径
set -uo pipefail

TOK="${GITHUB_TOKEN:-}"
# 与其他 API key 同源：优先读 Hermes 的 .env（容器内 /home/agent/.hermes/.env，宿主 data/hermes/.env）
# 直读文件 → 新增 key 无需重启容器即可用（env_file 只在容器创建时生效）
ENVF=${HERMES_ENV_FILE:-/home/agent/.hermes/.env}
[ -r "$ENVF" ] || ENVF=/home/user/gateway/data/hermes/.env
if [ -z "$TOK" ] && [ -r "$ENVF" ]; then
  TOK=$(sed -n 's/^GITHUB_TOKEN=//p' "$ENVF" | tail -1 | tr -d '\r')
fi
# 兜底：独立令牌文件（可选覆盖点）
TOKF=${GITHUB_TOKEN_FILE:-/opt/data/.github-token}
if [ -z "$TOK" ] && [ -r "$TOKF" ]; then TOK=$(cat "$TOKF"); fi
AUTH=()
[ -n "$TOK" ] && AUTH=(-H "Authorization: Bearer $TOK")

# 令牌无效时自动降级为匿名（否则 .env 里一个坏 key 会让所有读取全废）；降级会明确告警
_auth_warned=0
_anon_warn() { [ "$_auth_warned" = 1 ] && return; _auth_warned=1
  echo "[github-read] ⚠️ 令牌被拒（Bad credentials）→ 已自动降级为匿名访问（60 次/时、仅公开仓库）。请修 GITHUB_TOKEN。" >&2; }

api() {
  local out
  out=$(curl -sS -m 30 "${AUTH[@]}" -H 'Accept: application/vnd.github+json' "https://api.github.com$1")
  if [ ${#AUTH[@]} -gt 0 ] && printf '%s' "$out" | grep -q '"Bad credentials"'; then
    _anon_warn
    out=$(curl -sS -m 30 -H 'Accept: application/vnd.github+json' "https://api.github.com$1")
  fi
  printf '%s' "$out"
}
rawapi(){ curl -sS -m 60 "${AUTH[@]}" -H 'Accept: application/vnd.github.raw' "https://api.github.com$1"; }

_auth_note() { [ -n "$TOK" ] && echo "（带令牌）" || echo "（匿名，60 次/时，仅公开仓库）"; }

cmd=${1:-}; shift || true

case "$cmd" in
quota)
  api /rate_limit | python3 -c "
import json,sys
d=json.load(sys.stdin)
if 'resources' not in d:            # 401/403 时返回的是 message，不是 resources
    print('  ❌ 令牌被拒:', d.get('message')); print('     提示: 令牌无效会连匿名配额也读不到 → 去掉令牌或换有效令牌'); sys.exit(1)
c=d['resources']['core']; s=d['resources'].get('search',{})
print(f\"  core  : {c['remaining']}/{c['limit']}\")
print(f\"  search: {s.get('remaining','-')}/{s.get('limit','-')}\")"
  ;;
whoami)
  out=$(api /user)
  code=$(echo "$out" | python3 -c "import json,sys;d=json.load(sys.stdin);print('OK' if d.get('login') else 'BAD')" 2>/dev/null || echo BAD)
  if [ "$code" = OK ]; then
    echo "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(f\"  ✅ 令牌有效：{d.get('login')}（{d.get('type')}）\")"
  else
    echo "  ❌ 令牌无效：$(echo "$out" | head -c 200)"
    echo "     排查：是否已撤销/过期 · 是否被泄露扫描吊销 · 账号是否在自建 GHE（域名不是 api.github.com）"
  fi
  ;;
info)
  r=${1:?用法: info OWNER/REPO}
  api "/repos/$r" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('message'): print('  ❌',d['message']); sys.exit(1)
print(f\"  {d['full_name']}  ⭐{d.get('stargazers_count')}  fork {d.get('forks_count')}\")
print(f\"  描述: {d.get('description')}\")
print(f\"  默认分支: {d.get('default_branch')} | 语言: {d.get('language')} | 大小: {d.get('size')}KB\")
print(f\"  更新: {d.get('updated_at')} | 可见性: {d.get('visibility')}\")"
  ;;
file)
  r=${1:?用法: file OWNER/REPO PATH [REF]}; p=${2:?缺 PATH}; ref=${3:-}
  url="/repos/$r/contents/$p"
  [ -n "$ref" ] && url="$url?ref=$ref"
  rawapi "$url"
  ;;
tree)
  r=${1:?用法: tree OWNER/REPO [REF|--full]}; shift || true
  full=0; ref=""
  for a in "$@"; do case "$a" in --full) full=1;; *) ref=$a;; esac; done
  [ -z "$ref" ] && ref=$(api "/repos/$r" | python3 -c "import json,sys;print(json.load(sys.stdin).get('default_branch','HEAD'))")
  path="/repos/$r/git/trees/$ref"; [ "$full" = 1 ] && path="$path?recursive=1"
  api "$path" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('message'): print('  ❌',d['message']); sys.exit(1)
t=[x for x in d.get('tree',[]) if x['type']=='blob']
print(f\"  分支/ref: {sys.argv[1]}  文件 {len(t)} 个{f'（截断）' if d.get('truncated') else ''}\")
for x in t[:400]: print(f\"    {x['size']:>9} {x['path']}\")" "$ref"
  ;;
search)
  q=${1:?用法: search \"关键词\"}
  api "/search/repositories?q=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$q")&sort=stars&per_page=10" | python3 -c "
import json,sys
d=json.load(sys.stdin)
if d.get('message'): print('  ❌',d['message']); sys.exit(1)
print(f\"  命中 {d.get('total_count')} 个仓库，取前 {len(d.get('items',[]))}：\")
for i in d.get('items',[]): print(f\"    ⭐{i['stargazers_count']:>6}  {i['full_name']}  — {(i.get('description') or '')[:70]}\")"
  ;;
tarball)
  r=${1:?用法: tarball OWNER/REPO [REF] [DEST]}; ref=${2:-}; dest=${3:-}
  [ -z "$ref" ] && ref=$(api "/repos/$r" | python3 -c "import json,sys;print(json.load(sys.stdin).get('default_branch','main'))")
  base=$(basename "$r"); [ -z "$dest" ] && dest="/tmp/${base}-${ref}.tar.gz"
  curl -sSL -m 300 "${AUTH[@]}" -o "$dest" "https://codeload.github.com/$r/tar.gz/refs/heads/$ref"
  sz=$(stat -c %s "$dest" 2>/dev/null || echo 0)
  if [ "$sz" -lt 100 ]; then echo "  ❌ 下载失败（$sz 字节）：$(head -c 120 "$dest")"; exit 1; fi
  outdir=$(dirname "$dest")/"${base}-${ref}"
  mkdir -p "$outdir" && tar xzf "$dest" -C "$outdir" --strip-components=1
  echo "  ✅ tar: $dest ($sz 字节)"
  echo "  ✅ 解压: $outdir"
  ls -1 "$outdir" | head -12 | sed 's/^/     /'
  ;;
api)
  p=${1:?用法: api /path}
  api "$p"
  ;;
*)
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
  ;;
esac

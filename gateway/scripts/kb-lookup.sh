#!/bin/bash
# kb-lookup.sh —— 知识库三层检索（① Qdrant 语义 ② Obsidian 全文 ③ Dify 检索）
#   用法: scripts/kb-lookup.sh "<查询词>" [topK]
set -uo pipefail
Q="${1:-}"; K="${2:-5}"; TK=$(( ${2:-5} * 2 )); [ "$TK" -lt 10 ] && TK=10
[ -n "$Q" ] || { echo "用法: $0 \"<查询词>\" [topK]"; exit 2; }
VAULT=/home/user/gateway/data/obsidian/knowledge

echo "=== ① Qdrant 语义检索（记忆库 hermes_memory + 知识库 hermes_knowledge）==="
docker exec -i -e Q="$Q" -e K="$K" hermes python3 - <<'PY' 2>&1 | grep -vE "UserWarning|Api key is used"
import os, yaml, httpx
from qdrant_client import QdrantClient
q = os.environ["Q"]; k = int(os.environ.get("K", 5))
c = yaml.safe_load(open("/home/agent/.hermes/config.yaml"))
v = (c.get("memory") or {}).get("vector_db") or {}
try:
    vec = httpx.post("http://embedding-llama:8000/v1/embeddings",
                     json={"input": [q], "model": "bge-large-zh-v1.5"}, timeout=30).json()["data"][0]["embedding"]
except Exception as e:
    print("  ❌ embedding 服务不可用:", str(e)[:120]); raise SystemExit(0)
cl = QdrantClient(host=v.get("host"), port=int(v.get("port")), api_key=v.get("api_key"), timeout=15, https=False)
# 两个集合：会话记忆(provider 用) + 笔记知识库(obsidian 同步写入)
for coll, label in ((v.get("collection") or "hermes_memory", "记忆库"),
                    ("hermes_knowledge", "知识库")):
    try:
        hits = cl.query_points(collection_name=coll, query=vec, limit=k, with_payload=True).points
    except Exception as e:
        print("  [%s %s] 查询失败: %s" % (label, coll, str(e)[:60])); continue
    print("  —— %s（%s）——" % (label, coll))
    if not hits:
        print("      （无命中）")
    for i, h in enumerate(hits, 1):
        pl = h.payload or {}
        where = pl.get("title") or pl.get("path") or pl.get("session_id") or "-"
        txt = (pl.get("text") or pl.get("content") or pl.get("chunk") or "")[:150].replace("\n", " ")
        print("      [%d] %.3f  src=%s  %s" % (i, h.score, pl.get("source") or pl.get("kind") or "-", where))
        if txt: print("          " + txt)
PY

echo
echo "=== ② Obsidian 全文检索（$VAULT）==="
hits=$(grep -rIl --include="*.md" -- "$Q" "$VAULT" 2>/dev/null | head -5)
if [ -z "$hits" ]; then echo "  （无命中）"; else
  echo "$hits" | while read -r f; do
    echo "  · ${f#$VAULT/}"; grep -im1 -- "$Q" "$f" | cut -c1-140 | sed 's/^/      /'
  done
fi

echo
echo "=== ③ Dify 知识库检索（KB_RERANK=${KB_RERANK:-1} 本地精排·默认 | KB_RERANK_POOL=${KB_RERANK_POOL:-5} 候选池 | KB_RERANK=0 秒回）==="
# 2026-09-15 修复：宿主 127.0.0.1:8090 不通 → 改在脑侧容器内请求 dify-limiter:8090。
# 2026-10-14 续修（根因排查）：
#   本地 reranker（reranker-llama / bge-reranker-v2-m3 Q8_0 / CPU）单篇约 2~3s；
#   Dify 一次检索送 ~15 篇候选 → 2 核时 >55s，超过 dify-limiter 的 proxy_read_timeout（原 30s）→ 每次都 504，
#   等于"③ 层整层白查"。已做三件事：① limiter proxy_read_timeout 30s→120s（data/dify/nginx/nginx.conf）；
#   ② reranker-llama CPU 2→6 核（实测 10 篇 22s→11.6s）；③ 本脚本：rerank 改为**可选**（KB_RERANK=1），
#   默认走无 rerank 的 hybrid_search（0.2s 返回、相关性排序实测可用），rerank 失败/超时也会自动降级并注明。
docker exec -i -e Q="$Q" -e K="$K" -e TK="$TK" -e RERANK="${KB_RERANK:-1}" -e POOL="${KB_RERANK_POOL:-5}" -e TO="${KB_TIMEOUT:-90}" hermes python3 - <<'PYEOF' 2>&1
import json, os, pathlib, urllib.request, urllib.error
Q = os.environ["Q"]; K = int(os.environ.get("K", 5)); TK = int(os.environ.get("TK", 10))
RERANK = os.environ.get("RERANK", "1") == "1"; TO = int(os.environ.get("TO", "90"))
POOL = int(os.environ.get("POOL", "8"))   # 精排候选池：Dify 实际送 2×top_k 篇给 reranker
env = {}
p = pathlib.Path("/home/agent/.hermes/.env")
if p.exists():
    for line in p.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, _, v = line.partition("="); env[k.strip()] = v.strip()
key = env.get("DIFY_DATASET_KEY", "")
ids = [x for x in (env.get("DIFY_DATASET_IDS") or env.get("DIFY_DATASET_ID") or "").replace(" ", "").split(",") if x]
if not key or not ids:
    print("  ⏭  未配置（缺 DIFY_DATASET_KEY / DIFY_DATASET_IDS）→ 见技能 kb-first-lookup"); raise SystemExit(0)

def build(rerank, tk):
    m = {"search_method": "hybrid_search",
         "weights": {"keyword_setting": {"keyword_weight": 0.3},
                     "vector_setting": {"vector_weight": 0.7, "embedding_provider_name": "", "embedding_model_name": ""}},
         "top_k": tk}
    if rerank:
        m.update({"reranking_enable": True, "reranking_mode": "reranking_model",
                  "reranking_model": {"reranking_provider_name": "langgenius/openai_api_compatible/openai_api_compatible",
                                      "reranking_model_name": "bge-reranker-v2-m3"},
                  # 本机 reranker 返回原始 logits（无关文档为负分），阈值压到负数 = 不丢弃、只借排序
                  "score_threshold_enabled": True, "score_threshold": -100})
    else:
        m.update({"reranking_enable": False, "score_threshold_enabled": False})
    return m

def retrieve(ds, model):
    req = urllib.request.Request("http://dify-limiter:8090/v1/datasets/%s/retrieve" % ds, method="POST",
        data=json.dumps({"query": Q, "retrieval_model": model}).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TO) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try: msg = json.loads(raw).get("message", raw[:120])
        except Exception: msg = raw[:120]
        return None, "HTTP %s: %s" % (e.code, str(msg)[:120])
    except Exception as e:
        return None, "%s: %s" % (type(e).__name__, str(e)[:100])
    # Dify 在插件/模型调用出错时仍回 200，但 records 为空
    return (d.get("records") or (d.get("data") or {}).get("records") or []), None

for ds in ids:
    print("  —— dataset %s… ——" % ds[:8])
    used_rerank = RERANK
    recs, err = retrieve(ds, build(RERANK, POOL if RERANK else TK))
    if RERANK and (err or not recs):                      # rerank 失败 → 自动降级
        print("      （注：rerank 失败/超时或返回空 → 已自动降级为无 rerank 检索）")
        used_rerank = False
        recs, err = retrieve(ds, build(False, TK))   # 降级：无精排、放宽候选池
    if err:
        print("      ❌ %s" % err); continue
    if not recs:
        print("      （无命中）"); continue
    if used_rerank and all((r.get("score") or 0) == 0 for r in recs):  # 分数被归零时给提示
        print("      （分数字段被 Dify 归零：reranker 原始 logits 为负；下方顺序仍是 rerank 相关性序）")
    for r in recs[:K]:
        seg = r.get("segment") or {}; doc = seg.get("document") or {}
        print("      [%.3f] 《%s》" % (r.get("score", 0), str(doc.get("name", "?"))[:44]))
        print("          " + (seg.get("content") or "").replace("\n", " ")[:130])
PYEOF

echo "=== ④ 部署文档检索（docs/ 与 Gitee 仓库文档）==="
found=0
while read -r f; do
  [ -n "$f" ] || continue
  found=1
  echo "  · $(echo "$f" | sed 's|/home/user/gateway/||; s|/opt/data/hermes-skills/|repo:|')"
  grep -im1 -- "$Q" "$f" | cut -c1-140 | sed 's/^/      /'
done <<EOF2
$(grep -rIl --include="*.md" -- "$Q" /home/user/gateway/docs 2>/dev/null | head -5)
$(grep -rIl --include="*.md" -- "$Q" /opt/data/hermes-skills/*.md 2>/dev/null | head -3)
EOF2
[ "$found" = "0" ] && echo "  （无命中）"

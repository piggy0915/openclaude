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
echo "=== ③ Dify 知识库检索 ==="
# 2026-09-15 两处修复：
#   ① 原实现打 http://127.0.0.1:8090 —— 宿主上该端口不通 → curl 空响应 → 只打印"（响应解析失败）"，
#      等于这层白查（check-kb-stack 只查凭据，抓不到）→ 改为在脑侧容器内请求 dify-limiter:8090。
#   ② 实测 reranking_enable=true 时 Dify 返回 **0 条**（同查询 semantic/hybrid 无 rerank 均 5 条）→
#      保留用户的 hybrid 0.7/0.3 配置，但 rerank 拿不到结果时**自动回退**到无 rerank 并注明。
docker exec -i -e Q="$Q" -e K="$K" -e TK="$TK" hermes python3 - <<'PY' 2>&1
import json, os, pathlib, urllib.request, urllib.error
Q = os.environ["Q"]; K = int(os.environ.get("K", 5)); TK = int(os.environ.get("TK", 10))
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
MODEL = {"search_method": "hybrid_search",
         "weights": {"keyword_setting": {"keyword_weight": 0.3},
                     "vector_setting": {"vector_weight": 0.7, "embedding_provider_name": "", "embedding_model_name": ""}},
         "reranking_enable": True, "reranking_mode": "reranking_model",
         "reranking_model": {"reranking_provider_name": "langgenius/openai_api_compatible/openai_api_compatible",
                             "reranking_model_name": "bge-reranker-v2-m3"},
         # 注意：本机 reranker（llama.cpp 的 /v1/rerank）返回的是**原始 logits**（无关文档为负分），
         # 而 Dify 只保留 score > 0 → 无相关内容时会返回 0 条。故显式把阈值压到负数 = 不丢弃、
         # 仅借用 rerank 的相关性排序。（根治方案见技能：给 reranker 前置 sigmoid 归一化代理）
         "score_threshold_enabled": True, "score_threshold": -100, "top_k": TK}

def retrieve(ds, model):
    req = urllib.request.Request("http://dify-limiter:8090/v1/datasets/%s/retrieve" % ds, method="POST",
        data=json.dumps({"query": Q, "retrieval_model": model}).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try: msg = json.loads(raw).get("message", raw[:120])
        except Exception: msg = raw[:120]
        return None, "HTTP %s: %s" % (e.code, msg)
    except Exception as e:
        return None, "%s: %s" % (type(e).__name__, str(e)[:100])
    return d.get("records") or (d.get("data") or {}).get("records") or [], None

for ds in ids:
    print("  —— dataset %s… ——" % ds[:8])
    recs, err = retrieve(ds, MODEL)
    if err:
        print("      ❌ %s" % err); continue
    if not recs:                                  # rerank 不生效时的自动回退
        recs2, err2 = retrieve(ds, dict(MODEL, reranking_enable=False))
        if recs2:
            print("      （注：rerank 开启时返回 0 条 → 已自动回退到无 rerank）")
            recs = recs2
        elif err2:
            print("      ❌ %s" % err2); continue
    if not recs:
        print("      （无命中）"); continue
    if recs and all((r.get("score") or 0) == 0 for r in recs):
        print("      （分数字段被 Dify 归零：reranker 原始 logits 为负；下方顺序仍是 rerank 相关性序）")
    for r in recs[:K]:
        seg = r.get("segment") or {}; doc = seg.get("document") or {}
        print("      [%.3f] 《%s》" % (r.get("score", 0), str(doc.get("name", "?"))[:44]))
        print("          " + (seg.get("content") or "").replace("\n", " ")[:130])
PY

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

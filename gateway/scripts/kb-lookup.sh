#!/bin/bash
# kb-lookup.sh —— 知识库三层检索（① Qdrant 语义 ② Obsidian 全文 ③ Dify 检索）
#   用法: scripts/kb-lookup.sh "<查询词>" [topK]
set -uo pipefail
Q="${1:-}"; K="${2:-5}"
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
ENVF=/home/user/gateway/data/hermes/.env
DKEY=$(grep -m1 '^DIFY_DATASET_KEY=' "$ENVF" 2>/dev/null | cut -d= -f2- | tr -d '\r')
DIDS=$(grep -m1 '^DIFY_DATASET_IDS=' "$ENVF" 2>/dev/null | cut -d= -f2- | tr -d '\r')
[ -z "$DIDS" ] && DIDS=$(grep -m1 '^DIFY_DATASET_ID=' "$ENVF" 2>/dev/null | cut -d= -f2- | tr -d '\r')
if [ -z "$DKEY" ] || [ -z "$DIDS" ]; then
  echo "  ⏭ 未配置（缺 DIFY_DATASET_KEY / DIFY_DATASET_IDS）→ 见技能 kb-first-lookup"
else
  for ds in $(echo "$DIDS" | tr ',' ' '); do
    [ -n "$ds" ] || continue
    echo "  —— dataset ${ds:0:8}… ——"
    curl -s -m 20 -X POST "http://127.0.0.1:8090/v1/datasets/${ds}/retrieve" \
      -H "Authorization: Bearer ${DKEY}" -H 'Content-Type: application/json' \
      -d "{\"query\":\"${Q}\",\"retrieval_model\":{\"search_method\":\"semantic_search\",\"reranking_enable\":false,\"score_threshold_enabled\":false,\"top_k\":${K}}}" \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('      （响应解析失败）'); raise SystemExit
recs = (d.get('data') or {}).get('records') if isinstance(d.get('data'), dict) else d.get('records')
recs = recs or []
if not recs:
    print('      （无命中）'); raise SystemExit
for r in recs[:${K}]:
    seg = (r.get('segment') or {}); doc = (seg.get('document') or {})
    print('      [%.3f] 《%s》' % (r.get('score', 0), str(doc.get('name', '?'))[:44]))
    print('          ' + (seg.get('content') or '').replace(chr(10), ' ')[:130])
"
  done
fi

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

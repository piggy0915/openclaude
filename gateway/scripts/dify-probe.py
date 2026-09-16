#!/usr/bin/env python3
# dify-probe.py —— 在脑侧容器内运行：功能性验证 Dify 检索层（不只是"凭据存在"）
# 输出一行：<数据集数> <命中记录总数>[ rerank-fallback]
#   rerank-fallback 表示 rerank 开启时返回 0 条、已自动回退（2026-09-15 实测 reranker-llama /v1/rerank 404）
# 异常输出 ERR: <原因>
# 用法（容器内）：docker exec hermes python3 /home/agent/scripts/dify-probe.py
import json, pathlib, urllib.request, urllib.error

env = {}
p = pathlib.Path("/home/agent/.hermes/.env")
if p.exists():
    for line in p.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip()
key = env.get("DIFY_DATASET_KEY", "")
ids = [x for x in (env.get("DIFY_DATASET_IDS") or env.get("DIFY_DATASET_ID") or "").replace(" ", "").split(",") if x]
if not key or not ids:
    print("ERR: 未配置 DIFY_DATASET_KEY / DIFY_DATASET_IDS")
    raise SystemExit(0)

MODEL = {"search_method": "hybrid_search",
         "weights": {"keyword_setting": {"keyword_weight": 0.3},
                     "vector_setting": {"vector_weight": 0.7, "embedding_provider_name": "", "embedding_model_name": ""}},
         "reranking_enable": True, "reranking_mode": "reranking_model",
         "reranking_model": {"reranking_provider_name": "langgenius/openai_api_compatible/openai_api_compatible",
                             "reranking_model_name": "bge-reranker-v2-m3"},
         # reranker 返回原始 logits（负分），Dify 只留 score>0；压负阈值=不丢弃、只要排序
         "score_threshold_enabled": True, "score_threshold": -100, "top_k": 3}


def retrieve(ds, model):
    req = urllib.request.Request("http://dify-limiter:8090/v1/datasets/%s/retrieve" % ds, method="POST",
        data=json.dumps({"query": "部署 架构 容器 记忆", "retrieval_model": model}).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            msg = json.loads(raw).get("message", raw[:120])
        except Exception:
            msg = raw[:120]
        return None, "HTTP %s %s" % (e.code, msg)
    except Exception as e:
        return None, "%s: %s" % (type(e).__name__, str(e)[:100])
    return d.get("records") or (d.get("data") or {}).get("records") or [], None


total = 0
fallback = False
for ds in ids:
    recs, err = retrieve(ds, MODEL)
    if err:
        print("ERR: " + err)
        raise SystemExit(0)
    if not recs:
        recs2, err2 = retrieve(ds, dict(MODEL, reranking_enable=False))
        if recs2:
            fallback = True
            recs = recs2
        elif err2:
            print("ERR: " + err2)
            raise SystemExit(0)
    total += len(recs)

print("%d %d%s" % (len(ids), total, " rerank-fallback" if fallback else ""))

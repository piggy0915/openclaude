#!/usr/bin/env python3
"""列出 Qdrant 全部集合与点数（容器内运行）。"""
import yaml
from qdrant_client import QdrantClient
c = yaml.safe_load(open("/home/agent/.hermes/config.yaml"))
v = (c.get("memory") or {}).get("vector_db") or {}
cl = QdrantClient(host=v.get("host") or "qdrant", port=int(v.get("port") or 6333),
                  api_key=v.get("api_key"), timeout=15, https=False)
tot = 0
for col in cl.get_collections().collections:
    try:
        n = cl.get_collection(col.name).points_count
    except Exception:
        n = -1
    tot += max(n, 0)
    mark = " ← 记忆 provider 使用" if col.name == v.get("collection") else ""
    print(f"  {col.name:26s} {n:6d} 点{mark}")
print(f"  {'合计':26s} {tot:6d} 点")

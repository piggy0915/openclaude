#!/usr/bin/env python3
"""qdrant-probe.py —— 探测 Qdrant 可达性与集合规模（容器内运行）
输出单行：  <集合数> <hermes_memory点数>   或   ERR <原因>
注意：QdrantClient 必须显式 https=False（qdrant-client 用 host/port 时默认 https=True →
对明文 6333 发 TLS 报 [SSL: WRONG_VERSION_NUMBER]）。
"""
import sys
try:
    import yaml
    from qdrant_client import QdrantClient
    cfg = yaml.safe_load(open("/home/agent/.hermes/config.yaml")) or {}
    v = (cfg.get("memory") or {}).get("vector_db") or {}
    cl = QdrantClient(host=v.get("host") or "qdrant", port=int(v.get("port") or 6333),
                      api_key=v.get("api_key"), timeout=10, https=False)
    n = len(cl.get_collections().collections)
    try:
        pts = cl.get_collection(v.get("collection") or "hermes_memory").points_count
    except Exception:
        pts = -1
    print(f"{n} {pts}")
except Exception as exc:
    print("ERR " + str(exc)[:60].replace("\n", " "))

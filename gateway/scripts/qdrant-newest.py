#!/usr/bin/env python3
"""qdrant-newest.py —— 只读：打印 hermes_memory 里时间最新的 N 条点，
用于验证「运行中进程是否已加载最新插件」——看新点是否带 content_sha1（补丁⑥）。

用法（容器内）：docker exec hermes python3 /home/agent/scripts/qdrant-newest.py [N]
"""
import hashlib
import pathlib
import sys
import uuid

from qdrant_client import QdrantClient

NS = uuid.NAMESPACE_URL


def load_env(path="/home/agent/.hermes/.env"):
    v = {}
    for line in pathlib.Path(path).read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, _, val = line.partition("=")
            v[k.strip()] = val.strip()
    return v


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    v = load_env()
    cl = QdrantClient(host=v.get("QDRANT_HOST", "qdrant"), port=int(v.get("QDRANT_PORT", 6333)),
                      api_key=v.get("QDRANT_API_KEY"), timeout=60, https=False)
    pts, off = [], None
    while True:
        b, off = cl.scroll("hermes_memory", limit=200, with_payload=True, with_vectors=False, offset=off)
        pts += b
        if off is None:
            break
    pts.sort(key=lambda p: int((p.payload or {}).get("timestamp") or (p.payload or {}).get("ts") or 0), reverse=True)
    print(f"hermes_memory 共 {len(pts)} 点，最新 {n} 条：")
    with_csha = 0
    for p in pts[:n]:
        pl = p.payload or {}
        csha = str(pl.get("content_sha1") or "")
        ok_id = (str(p.id) == str(uuid.uuid5(NS, csha))) if csha else False
        if csha:
            with_csha += 1
        ts = int(pl.get("timestamp") or pl.get("ts") or 0)
        print(f"  id={str(p.id)[:13]}… ts={ts} src={pl.get('source')} "
              f"content_sha1={'✅有' if csha else '❌无'} id可核验={'✅' if ok_id else '－'}")
        print(f"     内容: {(pl.get('content') or pl.get('text') or '')[:60]!r}")
    total_csha = sum(1 for p in pts if (p.payload or {}).get("content_sha1"))
    print(f"\n带 content_sha1 的点共 {total_csha} / {len(pts)}"
          f"{'  → 补丁⑥ 已在运行进程生效 ✅' if total_csha else '  → 补丁⑥ 尚未生效（进程仍是旧模块）❌'}")


if __name__ == "__main__":
    main()

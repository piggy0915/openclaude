#!/usr/bin/env python3
"""dup-inspect.py —— 只读：列出 hermes_memory 里内容重复的点（含 id/时间/来源），用于判断
残留重复是「历史遗留」还是「确定性 id 失效」。不修改任何数据。

用法（容器内）：docker exec hermes python3 /home/agent/scripts/dup-inspect.py
"""
import pathlib
import sys
from collections import defaultdict

from qdrant_client import QdrantClient


def load_env(path="/home/agent/.hermes/.env"):
    v = {}
    p = pathlib.Path(path)
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, _, val = line.partition("=")
                v[k.strip()] = val.strip()
    return v


def main():
    v = load_env()
    cl = QdrantClient(
        host=v.get("QDRANT_HOST", "qdrant"),
        port=int(v.get("QDRANT_PORT", 6333)),
        api_key=v.get("QDRANT_API_KEY"),
        timeout=60,
        https=False,
    )
    coll = sys.argv[1] if len(sys.argv) > 1 else "hermes_memory"
    pts, off = [], None
    while True:
        batch, off = cl.scroll(coll, limit=200, with_payload=True, with_vectors=False, offset=off)
        pts += batch
        if off is None:
            break
    groups = defaultdict(list)
    for p in pts:
        pl = p.payload or {}
        key = (pl.get("content") or pl.get("text") or "")
        groups[key].append(p)
    dups = {k: x for k, x in groups.items() if len(x) > 1}
    print(f"{coll}: {len(pts)} 点 / 唯一内容 {len(groups)} 组 / 重复组 {len(dups)}")
    for i, (key, items) in enumerate(dups.items(), 1):
        print(f"\n[{i}] 内容({len(key)}字): {key[:70]!r}")
        for p in items:
            pl = p.payload or {}
            ts = pl.get("timestamp") or pl.get("ts") or "-"
            src = pl.get("source") or pl.get("kind") or "-"
            print(f"      id={str(p.id)[:14]}… ts={ts} src={src} tags={pl.get('tags')}")


if __name__ == "__main__":
    main()

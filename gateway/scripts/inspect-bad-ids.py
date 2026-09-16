#!/usr/bin/env python3
"""inspect-bad-ids.py —— 一次性诊断：找出 id 不匹配的点，打印其完整 payload 并试算
多种哈希变体，定位插件的真实 id 输入到底是什么。只读。
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


def variants(content):
    out = {}
    for label, text in [
        ("content.strip()", content.strip()),
        ("content", content),
        ("content.rstrip()", content.rstrip()),
        ("content.lstrip()", content.lstrip()),
    ]:
        out[f"sha1(utf8 {label})"] = hashlib.sha1(text.encode("utf-8")).hexdigest()
    return out


def main():
    v = load_env()
    cl = QdrantClient(host=v.get("QDRANT_HOST", "qdrant"), port=int(v.get("QDRANT_PORT", 6333)),
                      api_key=v.get("QDRANT_API_KEY"), timeout=60, https=False)
    coll = sys.argv[1] if len(sys.argv) > 1 else "hermes_memory"
    pts, off = [], None
    while True:
        b, off = cl.scroll(coll, limit=200, with_payload=True, with_vectors=False, offset=off)
        pts += b
        if off is None:
            break
    n = 0
    for p in pts:
        pl = p.payload or {}
        content = pl.get("content") or pl.get("text") or ""
        csha = str(pl.get("content_sha1") or "").strip()
        if csha:
            continue
        if str(p.id) == str(uuid.uuid5(NS, hashlib.sha1(content.strip().encode()).hexdigest())):
            continue
        if len(content) >= 2000:
            continue
        ts = int(pl.get("timestamp") or pl.get("ts") or 0)
        if ts < 1789386074:      # 补丁⑤之前 → 历史点，跳过
            continue
        n += 1
        print(f"\n=== 异常点 {n} ===")
        print(f"  id        : {p.id}")
        print(f"  payload键 : {sorted(pl.keys())}")
        print(f"  ts        : {ts}")
        print(f"  source    : {pl.get('source')}  tags={pl.get('tags')}")
        print(f"  内容长度  : {len(content)}  repr头40={content[:40]!r}")
        print(f"  repr尾40  : {content[-40:]!r}")
        for label, h in variants(content).items():
            print(f"    {label:26s} sha1={h[:16]}… uuid5={str(uuid.uuid5(NS, h))[:14]}… {'✅匹配' if str(uuid.uuid5(NS, h)) == str(p.id) else ''}")
        if n >= 6:
            break
    print(f"\n合计异常（补丁⑤之后、内容完整）：{n}")


if __name__ == "__main__":
    main()

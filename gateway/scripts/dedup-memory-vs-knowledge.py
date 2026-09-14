#!/usr/bin/env python3
"""清掉 hermes_memory 里与 hermes_knowledge 完全重复的 1445 个 obsidian 分块点。

流程（KB 治理规范：先审计 → 报数 → 导出回滚清单 → 分批删 → 复核）：
 1) scroll 出 hermes_memory 中 source=obsidian 的全部点（id + payload 摘要）
 2) 与 hermes_knowledge 求交，确认是「同源搬运」（同 id）
 3) 导出回滚清单 JSON（含全量 id + payload 关键字段）到 /root/
 4) 按 id 分批（200/批）从 hermes_memory 删除
 5) 复核：两侧计数、抽样、知识集合内容完好

用法：dedup-memory-vs-knowledge.py [--dry-run]
"""
from __future__ import annotations

import json
import os
import sys
import time

import httpx
import yaml

DOMAIN = "/home/agent/.hermes"
cfg = yaml.safe_load(open(f"{DOMAIN}/config.yaml", encoding="utf-8"))["memory"]["vector_db"]
BASE = f"http://{cfg['host']}:{int(cfg['port'])}"
KEY = cfg.get("api_key")
H = {"api-key": KEY, "Content-Type": "application/json"}
MEM = cfg["collection"]
KN = os.environ.get("QDRANT_KNOWLEDGE_COLLECTION") or "hermes_knowledge"
DRY = "--dry-run" in sys.argv
BATCH = 200


def scroll(name, flt=None, payload=True):
    out, off = [], None
    while True:
        body = {"limit": 1000, "with_payload": payload, "with_vector": False}
        if flt:
            body["filter"] = flt
        if off:
            body["offset"] = off
        r = httpx.post(f"{BASE}/collections/{name}/points/scroll", headers=H, json=body, timeout=90).json()["result"]
        out.extend(r["points"])
        off = r.get("next_page_offset")
        if not off:
            return out


def count(name):
    return httpx.get(f"{BASE}/collections/{name}", headers=H, timeout=30).json()["result"]["points_count"]


print(f"集合: {MEM} (记忆) vs {KN} (知识)")

# 1) 审计
mem_obs = scroll(MEM, {"must": [{"key": "source", "match": {"value": "obsidian"}}]})
kn_all = scroll(KN, payload=False)
kn_ids = {p["id"] for p in kn_all}
mem_obs_ids = {p["id"] for p in mem_obs}
same = mem_obs_ids.intersection(kn_ids)
only_mem = mem_obs_ids.difference(kn_ids)
print(f"  记忆集合中 source=obsidian : {len(mem_obs_ids)}")
print(f"  知识集合总数             : {len(kn_ids)}")
print(f"  同 id（同源搬运，可删）   : {len(same)}")
print(f"  仅记忆集合独有（保留）    : {len(only_mem)}")

if len(same) != len(mem_obs_ids):
    print("⚠ 存在「仅记忆集合独有」的点 —— 只删同 id 那批，独有点保留")

# 2) 抽样比对内容（同 id 是否同内容）
kmap = {p["id"]: p for p in kn_all}
sample_ok = 0
for p in mem_obs[:8]:
    pl = p.get("payload") or {}
    txt = (pl.get("text") or pl.get("content") or "")[:60]
    kn_payload = (kmap.get(p["id"], {}).get("payload") or {})
    kn_txt = (kn_payload.get("text") or kn_payload.get("content") or "")[:60]
    hit = (txt == kn_txt) and bool(txt)
    sample_ok += 1 if hit else 0
print(f"  内容抽样（前 8 条）一致: {sample_ok}/8")

if DRY:
    print("(dry-run，未删除)")
    sys.exit(0)

# 3) 回滚清单
ts = time.strftime("%Y%m%d-%H%M%S")
rollback = f"/root/qdrant-dedup-rollback-{ts}.json"
with open(rollback, "w", encoding="utf-8") as fh:
    json.dump({
        "created_at": ts,
        "what": f"{MEM} 中 source=obsidian 且与 {KN} 同 id 的点（跨集合重复）",
        "howto_restore": f"POST {BASE}/collections/{MEM}/points (wait=true) with these points; 向量需重新 embedding（脚本未存向量）",
        "count": len(same),
        "points": [{"id": p["id"], "payload": p.get("payload")} for p in mem_obs if p["id"] in same],
    }, fh, ensure_ascii=False)
print(f"  回滚清单: {rollback}（{os.path.getsize(rollback)} 字节）")

# 4) 分批删除
ids = sorted(same)
before = count(MEM)
deleted = 0
for i in range(0, len(ids), BATCH):
    chunk = ids[i:i + BATCH]
    r = httpx.post(f"{BASE}/collections/{MEM}/points/delete?wait=true",
                   headers=H, json={"points": chunk}, timeout=120)
    r.raise_for_status()
    deleted += len(chunk)
    print(f"  已删 {deleted}/{len(ids)}")
after = count(MEM)
print(f"  计数: {before} -> {after}（差 {before - after}）")

# 5) 复核
left = scroll(MEM, {"must": [{"key": "source", "match": {"value": "obsidian"}}]}, payload=False)
print(f"  复核: 记忆集合残留 source=obsidian = {len(left)} ；知识集合 = {count(KN)}")
gl = scroll(MEM, {"must": [{"key": "source", "match": {"value": "tool_conclude"}}]})
print(f"  复核: tool_conclude 点仍在 = {len(gl)}")

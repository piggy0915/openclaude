#!/usr/bin/env python3
"""从 hermes_memory 清除 Obsidian 类分块（知识由 hermes_knowledge 承载，插件已改为多集合检索）。

  默认预览；加 --apply 执行。执行前把待删点的 id+payload 导出到 /root/ 便于回滚。
"""
import sys, json, time, pathlib, yaml
from qdrant_client import QdrantClient
from qdrant_client.models import PointIdsList

APPLY = "--apply" in sys.argv
cfg = yaml.safe_load(open("/home/agent/.hermes/config.yaml"))
v = (cfg.get("memory") or {}).get("vector_db") or {}
MEM = v.get("collection") or "hermes_memory"
KNOW = "hermes_knowledge"
cl = QdrantClient(host=v.get("host"), port=int(v.get("port")), api_key=v.get("api_key"),
                  timeout=60, https=False)

def scroll_all(name):
    ids, pl, off = [], {}, None
    while True:
        pts, off = cl.scroll(collection_name=name, limit=1000, offset=off,
                             with_payload=True, with_vectors=False)
        for p in pts:
            ids.append(p.id); pl[p.id] = p.payload or {}
        if off is None:
            break
    return ids, pl

mem_ids, mem_pl = scroll_all(MEM)
know_ids, _ = scroll_all(KNOW)
know_set = set(know_ids)

# 判定：Obsidian/知识类形态（有 path/title）或 source=obsidian
targets = [i for i in mem_ids if "path" in mem_pl[i] or "title" in mem_pl[i] or mem_pl[i].get("source") == "obsidian"]
dup = [i for i in targets if i in know_set]
orphan = [i for i in targets if i not in know_set]

print(f"  {MEM}: {len(mem_ids)} 点；其中知识类 {len(targets)}（两集合重复 {len(dup)} / 仅存此处 {len(orphan)}）")
print(f"  {KNOW}: {len(know_ids)} 点")
print(f"  保留（会话记忆）: {len(mem_ids) - len(targets)} 点")
if not APPLY:
    print("\n  预览模式：未改动。执行请加 --apply")
    raise SystemExit(0)

bak = pathlib.Path(f"/root/qdrant-memory-knowledge-backup-{time.strftime('%Y%m%d-%H%M%S')}.json")
bak.write_text(json.dumps([{"id": str(i), "payload": mem_pl[i]} for i in targets], ensure_ascii=False), encoding="utf-8")
print(f"\n  已导出回滚清单: {bak}  ({bak.stat().st_size} 字节, {len(targets)} 点)")

deleted = 0
for k in range(0, len(targets), 500):
    batch = targets[k:k+500]
    cl.delete(collection_name=MEM, points_selector=PointIdsList(points=batch))
    deleted += len(batch)
    print(f"    删除 {deleted}/{len(targets)}", end="\r")
print(f"\n  ✅ 已删除 {deleted} 点")
print(f"  复核: {MEM} = {cl.get_collection(MEM).points_count} 点 ; {KNOW} = {cl.get_collection(KNOW).points_count} 点")

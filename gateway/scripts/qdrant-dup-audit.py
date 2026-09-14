#!/usr/bin/env python3
"""审计：hermes_memory 里的 Obsidian 分块 与 hermes_knowledge 是否重复。

判定口径：
  重复 = 同一 point_id 同时存在于两个集合（point_id 由 uuid5(相对路径#分块号) 生成，天然可比）
  孤儿 = 只存在于 hermes_memory 的 Obsidian 分块（清理会丢）；或只在 hermes_knowledge（不需处理）
"""
import yaml, json
from qdrant_client import QdrantClient

cfg = yaml.safe_load(open("/home/agent/.hermes/config.yaml"))
v = (cfg.get("memory") or {}).get("vector_db") or {}
cl = QdrantClient(host=v.get("host") or "qdrant", port=int(v.get("port") or 6333),
                  api_key=v.get("api_key"), timeout=30, https=False)

def scroll_all(name):
    ids, pl = [], {}
    off = None
    while True:
        pts, off = cl.scroll(collection_name=name, limit=1000, offset=off,
                             with_payload=True, with_vectors=False)
        for p in pts:
            ids.append(str(p.id)); pl[str(p.id)] = p.payload or {}
        if off is None:
            break
    return ids, pl

mem_ids, mem_pl = scroll_all("hermes_memory")
know_ids, know_pl = scroll_all("hermes_knowledge")
mem_set, know_set = set(mem_ids), set(know_ids)

obs_in_mem = [i for i in mem_ids if mem_pl[i].get("source") == "obsidian" or "path" in mem_pl[i]]
obs_in_know = [i for i in know_ids if know_pl[i].get("path") or know_pl[i].get("kind")]
dup = [i for i in obs_in_mem if i in know_set]
orph_mem = [i for i in obs_in_mem if i not in know_set]
only_know = [i for i in obs_in_know if i not in mem_set]

print("### 规模")
print(f"  hermes_memory      共 {len(mem_ids)} 点，其中 Obsidian 类 {len(obs_in_mem)} 点")
print(f"  hermes_knowledge   共 {len(know_ids)} 点，其中带 path/kind {len(obs_in_know)} 点")
print()
print("### 重复判定（同 point_id）")
print(f"  两个集合都有（= 真重复，可安全清理）: {len(dup)}")
print(f"  只在 hermes_memory（清理会丢）: {len(orph_mem)}")
print(f"  只在 hermes_knowledge（无需处理）: {len(only_know)}")
print()
if dup:
    i = dup[0]
    a, b = mem_pl[i], know_pl[i]
    same_txt = (a.get("text") or "")[:200] == (b.get("text") or "")[:200]
    print("### 抽样核对（同一 point_id 在两个集合里的 payload）")
    print(f"  id={i}")
    print(f"  path: mem={a.get('path')!r}  know={b.get('path')!r}   {'一致' if a.get('path')==b.get('path') else '不一致'}")
    print(f"  chunk: mem={a.get('chunk')}  know={b.get('chunk')}")
    print(f"  正文字段前200字符一致: {same_txt}")
    print(f"  payload 键: mem={sorted(a)} / know={sorted(b)}")
print()
if orph_mem:
    print("### 只在 hermes_memory 的孤儿分块（前 10，按路径）")
    paths = {}
    for i in orph_mem:
        p = mem_pl[i].get("path") or "(无 path)"
        paths[p] = paths.get(p, 0) + 1
    for p, n in sorted(paths.items())[:10]:
        print(f"  {n:3d} 块  {p}")

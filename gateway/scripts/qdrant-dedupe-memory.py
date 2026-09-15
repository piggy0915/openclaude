#!/usr/bin/env python3
"""去重 hermes_memory：同一内容（content 或 text）只保留最新一条。

  默认预览；--apply 执行（先导出 /root/ 回滚清单）。
  背景：插件旧版用 uuid4() 随机点 id，重复写入会新增点；启动时的记忆迁移每次都写一份。
"""
import sys, json, time, pathlib, hashlib, collections, yaml
from qdrant_client import QdrantClient
from qdrant_client.models import PointIdsList

APPLY = "--apply" in sys.argv
cfg = yaml.safe_load(open("/home/agent/.hermes/config.yaml"))
v = (cfg.get("memory") or {}).get("vector_db") or {}
MEM = v.get("collection") or "hermes_memory"
cl = QdrantClient(host=v.get("host"), port=int(v.get("port")), api_key=v.get("api_key"), timeout=60, https=False)

pts, off = [], None
while True:
    b, off = cl.scroll(collection_name=MEM, limit=1000, offset=off, with_payload=True, with_vectors=False)
    pts += b
    if off is None:
        break

groups = collections.defaultdict(list)
for p in pts:
    pl = p.payload or {}
    body = str(pl.get("content") or pl.get("text") or "").strip()
    if not body:
        continue                      # 空内容不参与去重（避免误删）
    groups[hashlib.sha1(body.encode()).hexdigest()].append(p)

victims = []
for key, members in groups.items():
    if len(members) < 2:
        continue
    members.sort(key=lambda p: int((p.payload or {}).get("timestamp") or (p.payload or {}).get("ts") or 0), reverse=True)
    victims += members[1:]            # 保留最新

print(f"  {MEM}: {len(pts)} 点 / 唯一内容 {len(groups)} 组 / 重复组 {sum(1 for m in groups.values() if len(m)>1)} / 可删 {len(victims)}")
if not APPLY:
    print("  预览模式，未改动。执行请加 --apply")
    raise SystemExit(0)

bak = pathlib.Path(f"/root/qdrant-memory-dedupe-backup-{time.strftime('%Y%m%d-%H%M%S')}.json")
bak.write_text(json.dumps([{"id": str(p.id), "payload": p.payload} for p in victims], ensure_ascii=False), encoding="utf-8")
print(f"  回滚清单: {bak} ({len(victims)} 点)")
for k in range(0, len(victims), 500):
    batch = [p.id for p in victims[k:k+500]]
    cl.delete(collection_name=MEM, points_selector=PointIdsList(points=batch))
print(f"  ✅ 已删除 {len(victims)} 点 → 现在 {cl.get_collection(MEM).points_count} 点")

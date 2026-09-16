#!/usr/bin/env python3
"""qdrant-check-ids.py —— 只读自检：hermes_memory 的点 id 是否为「内容确定性 id」
  id = uuid5(NAMESPACE_URL, sha1(content.strip()))

为什么需要它：插件旧版用 uuid4() 随机 id，导致每次启动的 MEMORY.md/USER.md 迁移
都新增一份（实测重复 ×26/×18）。补丁⑤ 改成确定性 id 后，重启不再涨点。

分类（避免误报）：
  ✅ 可精确核验   payload 有 content_sha1（补丁⑥），且 id == uuid5(sha1)
  ✅ 短文本可核验 无 content_sha1，但 id == uuid5(sha1(存储的 content))
  ⏭ 无法核验     无 content_sha1 且 content 达 2000 字（被截断）→ 补丁⑤/⑥ 之前的历史点
  ⚠️ 真异常       以上都不满足 → 该路径仍在用随机 id，每次启动会涨点

用法（容器内）：
  docker exec hermes python3 /home/agent/scripts/qdrant-check-ids.py              # 默认 hermes_memory
  docker exec hermes python3 /home/agent/scripts/qdrant-check-ids.py hermes_knowledge
"""
import datetime
import hashlib
import os
import pathlib
import sys
import uuid

from qdrant_client import QdrantClient

NS = uuid.NAMESPACE_URL
TRUNC_LEN = 2000  # 与插件 payload["content"] = content[:2000] 对齐
# 判定基准：**上次容器启动时刻**（由宿主侧传入 HERMES_RESTART_TS）。
# 原因：补丁⑤写进文件后，运行中的进程仍拿旧模块，直到重启才生效 ——
# 实测 19:41~21:09 之间写入的 3 个 sync_turn 点仍是 uuid4（旧代码在内存里）。
# 未传该变量时回退到补丁⑤落地时刻（2026-09-14 19:41 +08 = 11:41 UTC）。
PATCH5_TS = int(datetime.datetime(2026, 9, 14, 11, 41, tzinfo=datetime.timezone.utc).timestamp())
def _detect_restart_ts() -> int:
    """容器内自测启动时刻：/proc/1 的 mtime 即 PID 1（容器 init）启动时间。
    这样即使调用方没传 HERMES_RESTART_TS，判定基准也正确（否则会把旧代码写的点误报成异常）。"""
    try:
        return int(os.stat("/proc/1").st_mtime)
    except OSError:
        return 0


SINCE = int(os.environ.get("HERMES_RESTART_TS") or _detect_restart_ts() or PATCH5_TS)


def load_env(path="/home/agent/.hermes/.env"):
    v = {}
    p = pathlib.Path(path)
    if p.exists():
        for line in p.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, _, val = line.partition("=")
                v[k.strip()] = val.strip()
    return v


def did_from_sha(sha: str) -> str:
    return str(uuid.uuid5(NS, sha))


def did_from_text(content: str) -> str:
    return did_from_sha(hashlib.sha1(content.strip().encode("utf-8")).hexdigest())


def main():
    coll = sys.argv[1] if len(sys.argv) > 1 else "hermes_memory"
    v = load_env()
    cl = QdrantClient(
        host=v.get("QDRANT_HOST", "qdrant"),
        port=int(v.get("QDRANT_PORT", 6333)),
        api_key=v.get("QDRANT_API_KEY"),
        timeout=60,
        https=False,
    )
    pts, off = [], None
    while True:
        batch, off = cl.scroll(coll, limit=200, with_payload=True, with_vectors=False, offset=off)
        pts += batch
        if off is None:
            break

    exact = short = unver = bad = nocontent = legacy = toolpath = 0
    bad_samples = []
    for p in pts:
        pl = p.payload or {}
        content = pl.get("content") or pl.get("text")
        csha = str(pl.get("content_sha1") or "").strip()
        if csha:
            if str(p.id) == did_from_sha(csha):
                exact += 1
            else:
                bad += 1
                if len(bad_samples) < 5:
                    bad_samples.append((str(p.id)[:14], csha[:12]))
            continue
        if not content:
            nocontent += 1
            continue
        # 工具路径（qdrant_tools 插件，qdrant_conclude）：payload 为 text+created_at、
        # 无 timestamp，且 id 用 uuid4 —— 单列一类，避免被当成「历史点」掩盖（两条写入路径）。
        if pl.get("created_at") and "text" in pl and not pl.get("timestamp"):
            toolpath += 1
            continue
        ts = int(pl.get("timestamp") or pl.get("ts") or 0)
        if str(p.id) == did_from_text(content):
            short += 1
        elif ts < SINCE:
            legacy += 1          # 上次重启之前写入：旧代码（uuid4）时代，预期非确定性
        elif len(content) >= TRUNC_LEN:
            unver += 1           # 补丁⑤之后但内容被截断 → 无法离线复核
        else:
            bad += 1             # 补丁⑤之后、内容完整、id 仍不对 → 真异常
            if len(bad_samples) < 5:
                bad_samples.append((str(p.id)[:14], (pl.get("source") or pl.get("kind") or "-")))

    print(f"{coll}: 共 {len(pts)} 点（判定基准 since={SINCE}）")
    print(f"  ✅ 可精确核验(content_sha1)   {exact}")
    print(f"  ✅ 短文本可核验              {short}")
    print(f"  ⏭  上次重启前的历史点(旧码)   {legacy}")
    print(f"  ⏭  无法核验(2000 字截断)      {unver}")
    print(f"  ⏭  工具路径(qdrant_conclude, uuid4 id)  {toolpath}")
    if nocontent:
        print(f"  ⏭  无 content/text 字段      {nocontent}")
    print(f"  ⚠️  真异常(疑似随机 id)       {bad}")
    for pid, extra in bad_samples:
        print(f"        id={pid}… {extra}")

    if coll != "hermes_memory":
        print(f"\n说明：{coll} 的点 id 由写入方自定（如 Obsidian 同步用 uuid5(相对路径#块号)），"
              "不适用本公式 → 上面的数字仅供计数参考。")
    elif bad == 0:
        print("\n判定：✅ provider 路径无随机 id（重启不再涨点）"
              + (f"；但工具路径另有 {toolpath} 点为 uuid4（同内容重复调用 qdrant_conclude 会产生重复点）" if toolpath else ""))
    else:
        print("\n判定：⚠️ 存在随机 id 路径 → 每次启动会新增点，需补丁。")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""test-plugin-patch6.py —— 重启前预飞：在**不开真实 Qdrant 连接**的前提下，
直接调用插件的 _upsert_memory()，验证补丁⑤（确定性 id）与补丁⑥（content_sha1 入 payload）
这条路径端到端正确 —— 避免"重启完才发现 NameError/逻辑错，还得再重启一次"。

断言：
  1. id == uuid5(NAMESPACE_URL, sha1(完整内容))            ← 补丁⑤
  2. payload["content_sha1"] == sha1(完整内容)              ← 补丁⑥
  3. payload["content"] 被截断到 2000 字（已知行为，记录用）
  4. 同一内容连调两次 → id 相同、只产生 2 次 upsert 同一点（幂等）

用法（容器内，用 Hermes 自己的 venv python）：
  docker exec hermes /opt/hermes/.venv/bin/python /home/agent/scripts/test-plugin-patch6.py
"""
import hashlib
import importlib.util
import pathlib
import sys
import types
import uuid

PLUGIN = "/home/agent/.hermes/plugins/qdrant/__init__.py"
NS = uuid.NAMESPACE_URL


def load_plugin():
    """按文件路径加载插件模块；若基类/内核模块不可导入则注入桩。"""
    try:
        spec = importlib.util.spec_from_file_location("qdrant_plugin_under_test", PLUGIN)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception as first_err:  # noqa: BLE001
        print(f"  直接导入失败（{type(first_err).__name__}: {first_err}）→ 注入桩后重试")
        stub = types.ModuleType("agent.memory")

        class _MemProvider:  # noqa: D401
            pass

        stub.MemoryProvider = _MemProvider
        sys.modules.setdefault("agent.memory", stub)
        sys.modules.setdefault("agent", types.ModuleType("agent"))
        spec = importlib.util.spec_from_file_location("qdrant_plugin_under_test", PLUGIN)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod


class FakePoint:
    def __init__(self, **kw):
        self.__dict__.update(kw)


class FakeModels:
    PointStruct = FakePoint


class FakeClient:
    def __init__(self):
        self.upserts = []

    def upsert(self, collection_name=None, points=None, wait=False):
        self.upserts.append((collection_name, points))


def main():
    mod = load_plugin()
    cls = None
    for name in dir(mod):
        obj = getattr(mod, name)
        if isinstance(obj, type) and name.endswith("Provider") and name != "MemoryProvider":
            cls = obj
    if cls is None:
        print("❌ 未找到 Provider 类")
        return 1
    print(f"  加载到 Provider 类: {cls.__name__}")

    # 把函数内部 import 的 qdrant_client.models 换成桩（避免依赖真实客户端）
    fake_qc = types.ModuleType("qdrant_client")
    fake_qc.models = FakeModels
    sys.modules["qdrant_client"] = fake_qc
    sys.modules["qdrant_client.models"] = FakeModels

    p = cls()
    p._client = FakeClient()
    p._collection = "hermes_memory"
    p._session_id = "preflight"
    p._vector_size = 4
    p._embed = lambda text: [0.1, 0.2, 0.3, 0.4]          # 跳过 embedding 服务

    long_content = "预飞测试内容 " * 400                    # >2000 字，触发截断
    p._upsert_memory(content=long_content, tags="preflight", source="preflight")

    coll, points = p._client.upserts[0]
    pt = points[0]
    pl = pt.payload
    exp_sha = hashlib.sha1(long_content.strip().encode("utf-8"), usedforsecurity=False).hexdigest()
    exp_id = str(uuid.uuid5(NS, exp_sha))

    print(f"  upsert 集合: {coll} / 点数 {len(points)}")
    print(f"  原始内容长度 {len(long_content)} → payload 存储长度 {len(pl.get('content',''))}")
    checks = [
        ("补丁⑤ 确定性 id", str(pt.id) == exp_id, f"id={str(pt.id)[:18]}… 期望={exp_id[:18]}…"),
        ("补丁⑥ content_sha1 存在", bool(pl.get("content_sha1")), f"{str(pl.get('content_sha1'))[:16]}…"),
        ("补丁⑥ 哈希等于完整内容哈希", pl.get("content_sha1") == exp_sha, "对完整内容而非截断内容求 sha1"),
        ("内容截断到 2000 字", len(pl.get("content", "")) == 2000, f"实际 {len(pl.get('content',''))}"),
        ("payload 含 source/tags/timestamp", all(k in pl for k in ("source", "tags", "timestamp")), str(sorted(pl.keys()))),
    ]

    # 幂等：同内容再写一次
    p._upsert_memory(content=long_content, tags="preflight", source="preflight")
    pt2 = p._client.upserts[1][1][0]
    checks.append(("同一内容两次写入 → id 相同(幂等)", str(pt.id) == str(pt2.id), f"{str(pt2.id)[:18]}…"))

    ok = True
    for label, passed, detail in checks:
        print(f"    {'✅' if passed else '❌'} {label:32s} {detail}")
        ok = ok and passed
    print("\n判定：" + ("✅ 补丁⑤/⑥ 代码路径正确 → 重启后可用" if ok else "❌ 存在问题，先别重启"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

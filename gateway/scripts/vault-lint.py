#!/usr/bin/env python3
"""vault-lint.py — 知识库体检工具（NQMS LLM-Wiki 本库口径）

用法:
    vault-lint.py check      # 结构体检：断链/孤儿/存根/schema/索引漂移/近重复
    vault-lint.py stats      # 四项健康度指标（供 metrics.md 追加）
    vault-lint.py graph      # 链接图：hub / bridge / 连通分量 / 簇
    vault-lint.py privacy    # 隐私与凭据扫描（只看不删；报告不引用凭据本身）
    vault-lint.py sync       # 检索栈覆盖：磁盘内容页 vs Qdrant 已收录（查"漏收"）
    通用参数: --vault PATH   --json   零依赖，只读，绝不修改 vault。

口径（写死在源码里，避免"口头规则"被忘记）：
  1. 三类角色分开，混用会算出假数字：
       content = 参与统计的内容页（entities/concepts/comparisons/queries 下的非 MOC 页，
                 以及根目录的非骨架页）
       sources = 链接**来源**全集 = 所有非 raw 的 .md（**含骨架页**）——
                 本库 index.md 与各层 MOC.md 是主要入链来源；若排除它们，
                 一切只被 MOC 引用的页都会**假性成为孤儿**（v1 的 bug）
       targets = 链接**目标**全集 = 全部 .md（**含 raw**）——
                 本库有 52 条 [[raw/web/xxx.md]] 形式的链接，raw 是合法目标
  2. raw/ 是原料不是作品 → 不计入 content（不参与孤儿/存根/健康度）
  3. 骨架页 = SCHEMA/index/log/metrics 与各层 MOC → 不算内容页，但可作链接来源
  4. STUB_WORDS=40：少于 40 词且无出站链接 = 一次失败的入库 → 回 raw/ 重灌
  5. 报告先于修复：机械问题自动报，删除/合并一律只提议
  6. 索引漂移判定 = 既不在 index.md、也不在本层 MOC.md（v1 只看 index.md，
     而本库 index 的清单行是**分组概括**写法，会误报 22 页）
"""
import argparse
import collections
import difflib
import json
import os
import re
import sys

SKIP_DIRS = {".obsidian", ".git", ".trash", "node_modules", "templates",
             "awesome-design-md", "temp", "archive"}
SKELETON = {"SCHEMA.md", "index.md", "log.md", "metrics.md", "MOC.md"}
LAYERS = ("entities", "concepts", "comparisons", "queries")
STUB_WORDS = 40
STALE_BEFORE = "2026-07-08"     # 90 天阈值（基准日 2026-10-06）
LINK_RE = re.compile(r"\[\[([^\]\|#]+?)(?:#[^\]\|]*)?(?:\|[^\]]*)?\]\]")
DUP_RATIO = 0.85

VAULT_DEFAULT = os.environ.get("OBSIDIAN_VAULT_PATH",
                               "/srv/docker/volumes/hermes_obsidian_data/_data/knowledge")

SECRET_PATTERNS = {
    "Groq key": r"gsk_[A-Za-z0-9]{20,}",
    "Google API key": r"AIza[A-Za-z0-9_\-]{30,}",
    "OpenAI 风格 key": r"sk-[A-Za-z0-9_\-]{20,}",
    "GitHub token": r"gh[pousr]_[A-Za-z0-9]{20,}",
    "火山方舟 key": r"ark-[0-9a-f\-]{20,}",
    "智谱 key": r"[0-9a-f]{32}\.[A-Za-z0-9]{16}",
    "长猫 key": r"ak_[A-Za-z0-9]{20,}",
    "聚合网关 key": r"freellmapi-[A-Za-z0-9]{20,}",
    "MiMo token": r"tp-[A-Za-z0-9]{20,}",
    "私钥块": r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "密码赋值": r"(?i)(password|passwd|pwd)\s*[:=]\s*\S{6,}",
    "连接串含口令": r"(?i)(mongodb|postgres|mysql|redis|amqp)://[^\s\)]+:[^\s\)]+@",
}
SOFT_WORDS = ("api_key", "apikey", "secret", "token", "passwd", "private_key")


def mask(s):
    return (s[:8] + "…" + s[-4:]) if len(s) > 14 else s[:6] + "…"


def parse_fm(text):
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        return {}
    fm = {}
    for line in m.group(1).splitlines():
        k = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
        if k:
            fm[k.group(1)] = k.group(2).strip()
    return fm


def aliases_of(text):
    raw = parse_fm(text).get("aliases", "").strip()
    if not raw:
        return []
    if raw.startswith("["):
        return [x.strip().strip("'\"") for x in raw[1:-1].split(",") if x.strip()]
    return [raw]


def walk(vault):
    for dirpath, dirnames, filenames in os.walk(vault):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            p = os.path.join(dirpath, name)
            try:
                yield p, os.path.relpath(p, vault), open(p, encoding="utf-8", errors="replace").read()
            except Exception:
                continue


def layer_of(rel):
    return rel.split(os.sep)[0]


def is_excluded_page(rel):
    return layer_of(rel) == "raw" or os.path.basename(rel) in SKELETON


def collect(vault):
    content, sources, targets, texts = {}, {}, {}, {}
    for p, rel, text in walk(vault):
        texts[rel] = text
        stem = os.path.splitext(os.path.basename(p))[0]
        targets[stem.lower()] = rel
        targets[rel.lower()] = rel
        targets[rel[:-3].lower()] = rel
        for a in aliases_of(text):
            targets[a.lower()] = rel
        if layer_of(rel) == "raw":          # raw 是原料 → 既不算内容页，也不作链接来源
            continue
        sources[rel] = text                 # 骨架页（index/MOC）**是链接来源**，本库主要入链来自它们
        if os.path.basename(rel) not in SKELETON:
            content[rel] = text             # 但骨架页不算内容页（不参与孤儿/存根/健康度分母）
    return content, sources, targets, texts


def out_links(text):
    return [l.strip() for l in LINK_RE.findall(re.sub(r"`[^`]*`", "", text))]


def build_edges(sources, targets):
    return {r: [t for t in (targets.get(l.lower()) for l in out_links(txt)) if t and t != r]
            for r, txt in sources.items()}


def components(nodes, edges):
    adj = collections.defaultdict(set)
    for s in nodes:
        for d in edges.get(s, []):
            if d in nodes:
                adj[s].add(d)
                adj[d].add(s)
    seen, comps = set(), []
    for n in sorted(nodes):
        if n in seen:
            continue
        stack, comp = [n], []
        seen.add(n)
        while stack:
            cur = stack.pop()
            comp.append(cur)
            for nb in adj[cur]:
                if nb not in seen:
                    seen.add(nb)
                    stack.append(nb)
        comps.append(comp)
    return sorted(comps, key=len, reverse=True)


def core(vault):
    content, sources, targets, texts = collect(vault)
    edges = build_edges(sources, targets)
    cedges = {r: [d for d in edges.get(r, []) if d in content] for r in content}
    indeg = collections.Counter()
    for r, ds in edges.items():      # 入链来源**含骨架页**（index/MOC）；否则只被 MOC 引用的页会假性成孤儿
        for d in ds:
            if d in content:
                indeg[d] += 1
    return content, sources, targets, texts, edges, cedges, indeg


def cmd_check(vault, as_json=False):
    content, sources, targets, texts, edges, cedges, indeg = core(vault)
    broken = [(r, l) for r in sources for l in out_links(sources[r]) if targets.get(l.lower()) is None]
    orphans = [p for p in content if indeg[p] == 0]
    stubs = [p for p in content if len(content[p].split()) < STUB_WORDS and not cedges[p]]
    schema_bad = []
    for rel in sorted(content):
        miss = [k for k in ("title", "created", "type", "tags", "confidence", "status")
                if k not in parse_fm(texts[rel])]
        if miss:
            schema_bad.append((rel, miss))
    mos = {layer_of(rel): t for rel, t in texts.items() if os.path.basename(rel) == "MOC.md"}
    drift = []
    for p in sorted(content):
        stem = os.path.splitext(os.path.basename(p))[0]
        if stem in texts.get("index.md", "") or stem in mos.get(layer_of(p), ""):
            continue
        drift.append(p)
    stems = {p: os.path.splitext(os.path.basename(p))[0] for p in content}
    keys = sorted(content)
    dups = [(a, b, round(difflib.SequenceMatcher(None, stems[a], stems[b]).ratio(), 2))
            for i, a in enumerate(keys) for b in keys[i + 1:]
            if len(stems[a]) > 5 and len(stems[b]) > 5
            and difflib.SequenceMatcher(None, stems[a], stems[b]).ratio() >= DUP_RATIO]
    n = max(1, len(content))
    il = sum(len(v) for v in cedges.values())
    if as_json:
        print(json.dumps({"content_pages": len(content), "sources": len(sources), "broken": broken,
                          "orphans": orphans, "stubs": stubs, "schema": schema_bad,
                          "index_drift": drift, "near_duplicates": dups}, ensure_ascii=False, indent=2))
        return
    print(f"内容页 {len(content)} 页｜链接来源 {len(sources)} 个文件（含骨架）｜raw 不计入统计")
    print(f"Link graph: {il} 条页间链接 · avg {il/n:.2f}/页 · 孤儿 {len(orphans)}\n")
    print("Fixed automatically（机械问题，可直接修）:")
    print(f"  - 断链 {len(broken)} 条（改名错→直接改；真实缺页→记入 index 的 Gaps 区）")
    for rel, l in broken[:20]:
        print(f"      [[{l}]]  ←  {rel}")
    print(f"  - frontmatter 不全 {len(schema_bad)} 页")
    for rel, miss in schema_bad[:10]:
        print(f"      {rel}  缺 {miss}")
    print(f"  - 索引/MOC 双缺失 {len(drift)} 页（既不在 index.md 也不在本层 MOC）")
    for p in drift[:10]:
        print(f"      {p}")
    print("\nNeeds a decision（语义问题，只提议）:")
    print(f"  - 孤儿页 {len(orphans)} 个（补入站链 或 提议归档；归档优先于删除）")
    for p in orphans[:12]:
        print(f"      {p}")
    print(f"  - 存根 {len(stubs)} 个（<{STUB_WORDS} 词且无链接 = 失败入库 → 回 raw/ 重灌）")
    for p in stubs[:10]:
        print(f"      {p}")
    print(f"  - 近重复 {len(dups)} 对（相似度 ≥{DUP_RATIO}；走 merge 规程）")
    for a, b, r in dups[:8]:
        print(f"      {r}  {os.path.basename(a)}  ≈  {os.path.basename(b)}")
    print(f"\nHealth: orphan rate {100*len(orphans)/n:.1f}% · broken link rate {100*len(broken)/n:.1f}% "
          f"· stub rate {100*len(stubs)/n:.1f}%")


def cmd_stats(vault, as_json=False):
    content, sources, targets, texts, edges, cedges, indeg = core(vault)
    n = max(1, len(content))
    links = sum(len(v) for v in cedges.values())
    orphans = [p for p in content if indeg[p] == 0]
    comps = components(set(content), cedges)
    stale = [p for p in content if parse_fm(texts[p]).get("updated", "") and
             parse_fm(texts[p])["updated"] < STALE_BEFORE]
    d = {"pages": len(content), "links": links, "orphans": len(orphans),
         "orphan_rate": round(100 * len(orphans) / n, 1), "avg_degree": round(links / n, 2),
         "components": len(comps), "main_pct": round(100 * len(comps[0]) / n),
         "stale": len(stale), "stale_pct": round(100 * len(stale) / n, 1)}
    if as_json:
        print(json.dumps(d, ensure_ascii=False)); return
    from datetime import date
    print(f"{date.today().isoformat()} | pages {d['pages']} | links {d['links']}")
    print(f"orphan rate    {d['orphan_rate']}%   ({d['orphans']} 页)")
    print(f"avg degree     {d['avg_degree']}")
    print(f"components     {d['components']}   (main {d['main_pct']}%)")
    print(f"stale concepts {d['stale_pct']}%   ({d['stale']} 页 updated < {STALE_BEFORE})")


def cmd_graph(vault, as_json=False):
    content, sources, targets, texts, edges, cedges, indeg = core(vault)
    adj = collections.defaultdict(set)
    for r in content:
        for d in cedges[r]:
            adj[r].add(d); adj[d].add(r)
    comps = components(set(content), cedges)
    n = max(1, len(content))
    print(f"图：{len(content)} 页 · {sum(len(v) for v in cedges.values())} 条页间边 · "
          f"{len(comps)} 个连通分量（最大 {len(comps[0])} 页 = {100*len(comps[0])/n:.0f}%）\n")
    print("Hub（入链最多——考虑是否该拆页）:")
    for p, c in indeg.most_common(8):
        print(f"  {c:>4} 入链  {p}")
    bs = [p for p in content if len(adj[p]) == 2 and
          not any(y in adj[x] for x in adj[p] for y in adj[p] if x != y)]
    print(f"\nBridge（度=2 且两侧不相连——断了会切图）: {len(bs)} 个")
    for p in bs[:8]:
        print(f"  {os.path.basename(p)[:34]}  ←  连接 {sorted(os.path.basename(x)[:20] for x in adj[p])}")
    print(f"\n连通分量（前 6 个 >1 页）:")
    for c in [x for x in comps if len(x) > 1][:6]:
        print(f"  {len(c):>3} 页: {', '.join(os.path.basename(x)[:22] for x in c[:4])} …")
    print(f"\n死端（无出链）{len([p for p in content if not cedges[p]])} 页 · "
          f"孤立点 {len([p for p in content if not adj[p]])} 页")


def cmd_privacy(vault, as_json=False):
    hits, soft = {}, {}
    files = list(walk(vault))
    for p, rel, t in files:
        for name, pat in SECRET_PATTERNS.items():
            for m in re.finditer(pat, t):
                hits.setdefault(rel, []).append((name, mask(m.group(0))))
        low = t.lower()
        if any(w in low for w in SOFT_WORDS):
            soft[rel] = sum(low.count(w) for w in SOFT_WORDS)
    print(f"扫描 {len(files)} 个 md 文件\n")
    print("✓ 未发现凭据模式（硬命中）" if not hits else
          f"⚠️ 硬命中 {len(hits)} 个文件（只给类型与掩码，绝不引用凭据本身）:")
    for rel, hs in sorted(hits.items()):
        print(f"  {rel}")
        for name, mk in hs[:4]:
            print(f"      {name:<16} {mk}")
    if soft:
        print(f"\n· 关键词软提示 {len(soft)} 个文件（多为技术文正文里的英文标识符，需人眼过一遍）:")
        for rel, c in sorted(soft.items(), key=lambda x: -x[1])[:6]:
            print(f"      {c:>3} 次  {rel}")
    print("\n风险面：本库无 git 远端 → 不外泄；仅流向检索栈（Qdrant/Dify）与本机备份。"
          "入库后再脱敏不可靠——材料已扩散到概念页与链接。")


def cmd_sync(vault, as_json=False):
    content, sources, targets, texts, *_ = core(vault)
    key = os.environ.get("QDRANT_API_KEY", "")
    host = os.environ.get("QDRANT_HOST", "").strip()
    port = os.environ.get("QDRANT_PORT", "6333")
    coll = os.environ.get("QDRANT_COLLECTION", "hermes_knowledge")
    if not key:
        for p in ("/home/user/gateway/data/hermes/.env", "/home/user/gateway/.env"):
            try:
                m = re.search(r"^QDRANT_API_KEY=(.+)$", open(p, encoding="utf-8").read(), re.M)
                if m:
                    key = m.group(1).strip().strip('"').strip("'"); break
            except FileNotFoundError:
                pass
    import urllib.request
    paths, err = set(), ""
    for h in [x for x in (host, "qdrant", "127.0.0.1") if x]:
        try:
            off = None
            for _ in range(120):
                b = {"limit": 300, "with_payload": True}
                if off:
                    b["offset"] = off
                r = urllib.request.Request(f"http://{h}:{port}/collections/{coll}/points/scroll",
                                           data=json.dumps(b).encode(),
                                           headers={"api-key": key, "Content-Type": "application/json"})
                with urllib.request.urlopen(r, timeout=25) as resp:
                    d = json.loads(resp.read())["result"]
                for pt in d["points"]:
                    paths.add(pt["payload"].get("path"))
                off = d.get("next_page_offset")
                if not off:
                    break
            err = ""
            break
        except Exception as e:
            err = f"{h}: {str(e)[:50]}"; continue
    if not paths:
        print(f"✗ 无法读取 Qdrant（{err}）——容器内跑请设 QDRANT_HOST=qdrant"); return
    disk = {f"knowledge/{x}" for x in content}
    missing = sorted(disk - paths)
    print(f"检索栈覆盖（{coll}）：内容页 {len(disk)} · 已收录 {len(disk & paths)} · 缺 {len(missing)}")
    for p in missing[:20]:
        print(f"  ✗ 未收录  {p}")

    def _layer(p):
        q = p[len("knowledge/"):] if p.startswith("knowledge/") else p
        return q.split("/")[0]

    raw_in_kb = sum(1 for p in paths if p and p.startswith("knowledge/raw/"))
    skel_in_kb = [p for p in paths if p and os.path.basename(p) in SKELETON]
    print(f"\n  raw 层在库条目 {raw_in_kb} 个 —— **预期存在**，raw 是设计上要入库的原料（供溯源），不是噪声")
    print(f"  骨架页在库 {len(skel_in_kb)} 个（SCHEMA/index/log/metrics）")
    noise = sorted({p for p in paths if p and p.startswith("knowledge/") and p not in disk
                    and _layer(p) not in ("raw",) and os.path.basename(p) not in SKELETON}, key=len)
    if noise:
        print(f"  ⚠️ 真正的意外条目 {len(noise)} 个（既非内容页、非 raw、非骨架）:")
        for p in noise[:10]:
            print(f"    · {p}")
    else:
        print("  ✓ 无意外条目")
    print("\n提示：obsidian-sync 的初始全量扫描现在与 watcher 并行（2026-10-06 已修），"
          "扫描期间新建的文件约 40 秒内入库。")


def main():
    ap = argparse.ArgumentParser(description="知识库体检（本库口径）")
    ap.add_argument("cmd", choices=["check", "stats", "graph", "privacy", "sync"])
    ap.add_argument("--vault", default=VAULT_DEFAULT)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    if not os.path.isdir(a.vault):
        sys.exit(f"vault 路径不存在: {a.vault}")
    {"check": cmd_check, "stats": cmd_stats, "graph": cmd_graph,
     "privacy": cmd_privacy, "sync": cmd_sync}[a.cmd](a.vault, a.json)


if __name__ == "__main__":
    main()

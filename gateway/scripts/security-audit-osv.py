#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全局依赖 → OSV.dev 漏洞查询（补 hermes security audit 的盲区）。

覆盖 hermes security audit **不扫**的部分：全局 npm 包（/usr/local + /opt/data/npm-global）
与全局 pip/uv 工具。

⚠️ 实测坑（2026-09-20）：OSV 的 **批量接口 `/v1/querybatch` 只返回 `{id, modified}`**，
严重度/摘要/fixed 必须**逐条**取 `/v1/vulns/<id>`。本脚本按 id 去重后逐条拉取并缓存。

用法：
  security-audit-osv.py --npm-root /opt/data/npm-global/lib/node_modules \
                        --npm-root /usr/local/lib/node_modules \
                        --pip-json /opt/data/security-audit/<day>/pip-list.json \
                        --out-json /opt/data/security-audit/<day>/global-deps-osv.json
"""
import argparse, json, os, sys, time, urllib.request

OSV_BATCH = "https://api.osv.dev/v1/querybatch"
OSV_VULN = "https://api.osv.dev/v1/vulns/"
HDR = {"User-Agent": "hermes-security-audit/1.0", "Content-Type": "application/json"}


def read_pkg_json(path):
    try:
        with open(os.path.join(path, "package.json"), encoding="utf-8") as f:
            d = json.load(f)
        name, ver = d.get("name"), d.get("version")
        if name and ver and not name.startswith("file:"):
            return name, ver
    except Exception:
        pass
    return None, None


def collect_npm(roots):
    out, seen = [], set()
    for r in roots:
        if not os.path.isdir(r):
            continue
        for entry in sorted(os.listdir(r)):
            base = os.path.join(r, entry)
            if not os.path.isdir(base):
                continue
            if entry.startswith("@"):
                for sub in sorted(os.listdir(base)):
                    n, v = read_pkg_json(os.path.join(base, sub))
                    if n and (n, v) not in seen:
                        seen.add((n, v)); out.append(("npm", n, v, r))
            elif entry != "node_modules":
                n, v = read_pkg_json(base)
                if n and (n, v) not in seen:
                    seen.add((n, v)); out.append(("npm", n, v, r))
    return out


def collect_pip_site(roots):
    """读 dist-info/METADATA 的 Name/Version —— 不依赖 pip，可扫任意 site-packages。"""
    out, seen = [], set()
    for r in roots:
        if not os.path.isdir(r):
            continue
        for entry in sorted(os.listdir(r)):
            if not entry.endswith(".dist-info"):
                continue
            meta = os.path.join(r, entry, "METADATA")
            try:
                name = ver = None
                with open(meta, encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        if line.startswith("Name: ") and not name:
                            name = line[6:].strip()
                        elif line.startswith("Version: ") and not ver:
                            ver = line[9:].strip()
                        if name and ver:
                            break
                if name and ver and (name.lower(), ver) not in seen:
                    seen.add((name.lower(), ver)); out.append(("PyPI", name, ver, r))
            except Exception:
                continue
    return out


def collect_pip(pip_list_json):
    out, seen = [], set()
    try:
        data = json.load(open(pip_list_json, encoding="utf-8"))
    except Exception:
        return out
    for it in data if isinstance(data, list) else []:
        n, v = it.get("name"), it.get("version")
        if n and v and (n.lower(), v) not in seen:
            seen.add((n.lower(), v)); out.append(("PyPI", n, v, "pip list"))
    return out


def fetch(url, data=None, tries=3):
    for k in range(tries):
        try:
            req = urllib.request.Request(url, data=data, headers=HDR,
                                         method="POST" if data else "GET")
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)
        except Exception as e:
            if k == tries - 1:
                print(f"  ⚠ {url} 失败：{e}", file=sys.stderr)
                return None
            time.sleep(2 * (k + 1))
    return None


def sev_of(detail):
    """严重度：database_specific.severity 优先（GHSA 才有），其余记 UNKNOWN
    —— 与内置审计的分布一致（UNKNOWN 多为 PYSEC 缺严重度字段）。"""
    s = ((detail or {}).get("database_specific") or {}).get("severity")
    return str(s).upper() if s else "UNKNOWN"


def fixed_of(detail):
    fixed = set()
    for aff in (detail or {}).get("affected") or []:
        for rg in aff.get("ranges") or []:
            for ev in rg.get("events") or []:
                if ev.get("fixed"):
                    fixed.add(ev["fixed"])
    return sorted(fixed)[:5]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--npm-root", action="append", default=[])
    ap.add_argument("--pip-json", default=None, help="pip list --format=json 输出（通常是 venv，内置审计已覆盖，作交叉核对）")
    ap.add_argument("--pip-site", action="append", default=[], help="site/dist-packages 目录（venv 之外的全局 pip 包，这才是盲区）")
    ap.add_argument("--out-json", required=True)
    args = ap.parse_args()

    pkgs = collect_npm(args.npm_root)
    if args.pip_json:
        pkgs += collect_pip(args.pip_json)
    pkgs += collect_pip_site(args.pip_site)

    # ① 批量查（只回 id）
    queries = [{"package": {"ecosystem": e, "name": n}, "version": v} for e, n, v, _ in pkgs]
    resp = fetch(OSV_BATCH, json.dumps({"queries": queries}).encode()) if queries else None
    results = (resp or {}).get("results", [])
    pairs = []           # (pkg, vuln_id)
    for pkg, res in zip(pkgs, results):
        for v in (res or {}).get("vulns", []) or []:
            if v.get("id"):
                pairs.append((pkg, v["id"]))

    # ② 逐条取详情（按 id 去重缓存）
    cache, ids = {}, []
    for _, vid in pairs:
        if vid not in cache and vid not in ids:
            ids.append(vid)
    print(f"  批量命中 {len(pairs)} 条 / 去重 {len(ids)} 个漏洞 id；逐条取详情…")
    for i, vid in enumerate(ids, 1):
        cache[vid] = fetch(OSV_VULN + vid) or {}
        if i % 10 == 0:
            print(f"    …已取 {i}/{len(ids)}")
            time.sleep(1)

    findings = []
    for (eco, name, ver, origin), vid in pairs:
        d = cache.get(vid) or {}
        findings.append({
            "ecosystem": eco, "name": name, "version": ver, "origin": origin,
            "id": vid, "aliases": d.get("aliases", []),
            "severity": sev_of(d),
            "summary": (d.get("summary") or d.get("details") or "")[:220].replace("\n", " "),
            "fixed_versions": fixed_of(d),
            "modified": d.get("modified"),
        })

    order = {"CRITICAL": 0, "HIGH": 1, "MODERATE": 2, "MEDIUM": 2, "LOW": 3, "UNKNOWN": 4}
    findings.sort(key=lambda f: (order.get(f["severity"], 9), f["name"]))

    doc = {
        "scanned_packages": len(pkgs),
        "vulnerable_packages": len({(f["ecosystem"], f["name"], f["version"]) for f in findings}),
        "findings": len(findings),
        "by_severity": {k: sum(1 for f in findings if f["severity"] == k)
                        for k in ("CRITICAL", "HIGH", "MODERATE", "LOW", "UNKNOWN")},
        # 按来源拆开：npm 全局 vs venv(pip list，内置已覆盖→交叉核对) vs 系统 site-packages(真盲区)
        "by_origin": {k: sum(1 for f in findings
                             if ("npm" if k == "npm-global" else
                                 "pip-list" if k == "pip-venv(pip list)" else "site") in f["origin"])
                      for k in ("npm-global", "pip-venv(pip list)", "system site-packages")},
        "results": findings,
    }
    os.makedirs(os.path.dirname(args.out_json), exist_ok=True)
    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
    print(f"  扫描 {doc['scanned_packages']} 包；命中 {doc['vulnerable_packages']} 包 / "
          f"{doc['findings']} 条；严重度 {doc['by_severity']}")


if __name__ == "__main__":
    main()

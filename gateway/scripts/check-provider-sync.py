#!/usr/bin/env python3
"""比对 Hermes 两份 config.yaml 的 providers 是否同步。

用途：改完 provider/model 后的强制收尾检查。只改一份时 CLI 能跑通、
WebUI 界面却看不到 —— 这条命令就是防止那种「单路径假绿」。

用法:
    python3 check-provider-sync.py            # 宿主上直接跑
    python3 check-provider-sync.py --quiet    # 只在失败时输出

退出码: 0 = 两份一致；1 = 不一致（并列出差异）
"""
import sys, os, yaml

BRAIN = "/home/user/gateway/data/hermes/config.yaml"
WEBUI = "/home/user/gateway/data/.hermes-rt/config.yaml"
QUIET = "--quiet" in sys.argv

def load(p):
    try:
        d = yaml.safe_load(open(p, encoding="utf-8")) or {}
    except FileNotFoundError:
        return None, f"文件不存在: {p}"
    except yaml.YAMLError as e:
        return None, f"YAML 非法: {e}"
    return d, None

def keyinfo(v):
    v = v or {}
    return (v.get("api"), v.get("default_model") or v.get("models"))

def main():
    b, eb = load(BRAIN)
    w, ew = load(WEBUI)
    ok = True
    for err in (eb, ew):
        if err:
            print(f"[FAIL] {err}"); ok = False
    if not ok:
        return 1

    bp = b.get("providers") or {}
    wp = w.get("providers") or {}
    bm, wm = b.get("model") or {}, w.get("model") or {}

    only_b = sorted(set(bp) - set(wp))
    only_w = sorted(set(wp) - set(bp))
    diff = []
    for k in sorted(set(bp) & set(wp)):
        if keyinfo(bp[k]) != keyinfo(wp[k]):
            diff.append((k, keyinfo(bp[k]), keyinfo(wp[k])))

    if not QUIET:
        print(f"脑侧  {BRAIN}\n      providers({len(bp)}): {sorted(bp)}")
        print(f"webui {WEBUI}\n      providers({len(wp)}): {sorted(wp)}")
        print(f"model.default 脑侧={bm.get('default')!r}/{bm.get('provider')!r}  "
              f"webui={wm.get('default')!r}/{wm.get('provider')!r}")

    problems = []
    if only_b:
        problems.append(f"只在脑侧（WebUI 界面看不到）: {only_b}")
    if only_w:
        problems.append(f"只在 webui 侧（CLI/gateway 不认）: {only_w}")
    for k, a, c in diff:
        problems.append(f"字段不一致 [{k}]: 脑侧={a} webui={c}")
    if (bm.get("default"), bm.get("provider")) != (wm.get("default"), wm.get("provider")):
        problems.append("model.default/provider 两份不一致")

    if problems:
        print("\n[FAIL] 两份 config 不同步：")
        for p in problems:
            print("  - " + p)
        print("\n修复：把缺的那段补到另一份，再重跑本命令。")
        return 1

    if not QUIET:
        print(f"\n[OK] 两份一致（{len(bp)} 个 provider，字段与 model.default 均同）")
    return 0

if __name__ == "__main__":
    sys.exit(main())

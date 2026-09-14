#!/usr/bin/env python3
"""sync-webui-to-brain.py — 单向把 webui 侧设置同步到脑侧（webui -> brain）。

背景：B″″ 之后 webui 的 HERMES_HOME 顶级文件（config.yaml/.env/auth.json/SOUL.md）
与脑侧 data/hermes/ 物理分家。网页端改的 provider/key/模型只落在 webui 侧，
本脚本把它们单向下推到脑侧，且**不清除脑侧独有内容**（按键/按段合并）。

设计要点
- 合并而非覆盖：.env 按键、auth.json 递归、config.yaml 只同步白名单顶层段（其余脑侧原样保留），
  SOUL.md 不合并 → 目标被独立改动时只写冲突副本、不动脑侧。
- 不打印任何密钥值：日志只记「键名 / 段名 / 计数」。
- 每次写入前给脑侧文件留时间戳备份（保留 30 份）；写入用 tmp+os.replace（原子），
  并沿用原文件的 uid/gid/mode（否则会重新制造 root 属主漂移）。
- 状态文件记录上次同步时的源/目标哈希：源没变就直接退出（幂等、可每 3 秒轮询）。

用法
    sync-webui-to-brain.py [--dry-run] [--force] [--quiet]
    --dry-run  只报告将要发生的改动
    --force    忽略「源未变化」的状态短路，强制走一遍比较
    --quiet    仅在真的发生改动时输出
退出码 0=成功（含无事可做），1=有文件处理失败。
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import sys
import time
from datetime import datetime

BASE = "/home/user/gateway"
SRC_DIR = os.path.join(BASE, "data/.hermes-rt")      # webui 侧（源）
DST_DIR = os.path.join(BASE, "data/hermes")          # 脑侧（目标）
BACKUP_DIR = os.path.join(DST_DIR, ".sync-backups")
STATE_PATH = os.path.join(DST_DIR, ".sync-state.json")
LOG_PATH = "/var/log/hermes-webui-sync.log"
KEEP_BACKUPS = 30

# config.yaml 只同步这些顶层段（网页端会改的设置）；其余段（brain 运行时/宿主相关）一律保留脑侧值。
CONFIG_SYNC_KEYS = ("model", "custom_providers", "tts", "memory", "mcp_servers")

TOP_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):")

DRY = "--dry-run" in sys.argv
FORCE = "--force" in sys.argv
QUIET = "--quiet" in sys.argv


def now() -> str:
    return datetime.now().strftime("%F %T")


def log(msg: str, force: bool = False) -> None:
    if QUIET and not force:
        return
    line = f"{now()}  {msg}"
    print(line, flush=True)
    if not DRY:
        try:
            with open(LOG_PATH, "a", encoding="utf-8") as fh:
                fh.write(line + "\n")
        except OSError:
            pass


def sha(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()[:16]


def load_state() -> dict:
    try:
        with open(STATE_PATH, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    if DRY:
        return
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, indent=2, sort_keys=True)
    os.replace(tmp, STATE_PATH)
    try:
        os.chown(STATE_PATH, 10000, 10000)
    except OSError:
        pass


def backup(path: str) -> None:
    if DRY:
        return
    os.makedirs(BACKUP_DIR, exist_ok=True)
    os.chmod(BACKUP_DIR, 0o700)
    ts = time.strftime("%Y%m%d-%H%M%S")
    dst = os.path.join(BACKUP_DIR, f"{os.path.basename(path)}-{ts}")
    shutil.copy2(path, dst)
    os.chmod(dst, 0o600)
    keep = sorted(f for f in os.listdir(BACKUP_DIR) if f.startswith(os.path.basename(path) + "-"))
    for old in keep[:-KEEP_BACKUPS]:
        os.unlink(os.path.join(BACKUP_DIR, old))


def writing_atomic(path: str, data: bytes) -> None:
    """原子写并沿用原文件的 uid/gid/mode（避免 root 属主漂移）。"""
    if DRY:
        return
    st = os.stat(path)
    tmp = f"{path}.synctmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.chmod(tmp, stat.S_IMODE(st.st_mode))
    try:
        os.chown(tmp, st.st_uid, st.st_gid)
    except OSError:
        pass
    os.replace(tmp, path)


# ---------------------------------------------------------------- 合并实现

def merge_env(src_text: str, dst_text: str) -> tuple[str, list[str], list[str]]:
    """按键合并：源覆盖同名键，目标独有键保留。"""
    src_kv: dict[str, str] = {}
    for line in src_text.splitlines():
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if m:
            src_kv[m.group(1)] = m.group(2)
    changed: list[str] = []
    out: list[str] = []
    seen: set[str] = set()
    for line in dst_text.splitlines():
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not m:
            out.append(line)
            continue
        key = m.group(1)
        seen.add(key)
        if key in src_kv and src_kv[key] != m.group(2):
            changed.append(key)
            out.append(f"{key}={src_kv[key]}")
        else:
            out.append(line)
    added = [k for k in src_kv if k not in seen]
    for k in added:
        out.append(f"{k}={src_kv[k]}")
    text = "\n".join(out)
    if not text.endswith("\n"):
        text += "\n"
    return text, changed, added


def merge_json(src, dst, path: str = "", keep_target: frozenset[str] = frozenset()) -> tuple[object, list[str]]:
    """递归合并：源覆盖叶子；目标独有键保留；keep_target 里的键**保留目标值**。"""
    changed: list[str] = []
    if isinstance(src, dict) and isinstance(dst, dict):
        out = dict(dst)
        for k, v in src.items():
            child = f"{path}.{k}" if path else str(k)
            if k in dst:
                if k in keep_target:
                    continue                                  # 目标值优先（如各家独立刷新的 OAuth token）
                out[k], ch = merge_json(v, dst[k], child, keep_target)
                changed += ch
            else:
                out[k] = v
                changed.append(child + " (新增)")
        return out, changed
    if isinstance(src, list) and isinstance(dst, list) and len(src) == len(dst) \
            and all(isinstance(x, dict) for x in src + dst):
        out = []
        for i, (a, b) in enumerate(zip(src, dst)):
            merged, ch = merge_json(a, b, f"{path}[{i}]", keep_target)
            out.append(merged)
            changed += ch
        return out, changed
    if src != dst:
        changed.append(path or "<root>")
    return src, changed


def split_top_blocks(text: str) -> list[tuple[str | None, list[str]]]:
    """把 YAML 顶层切成 [(key, lines)]；key=None 表示文件头/注释尾块。"""
    blocks: list[tuple[str | None, list[str]]] = []
    cur_key: str | None = None
    cur: list[str] = []
    for line in text.splitlines(keepends=True):
        m = TOP_KEY_RE.match(line)
        if m:
            blocks.append((cur_key, cur))
            cur_key, cur = m.group(1), [line]
        else:
            cur.append(line)
    blocks.append((cur_key, cur))
    return [b for b in blocks if b[1]]


def merge_config(src_text: str, dst_text: str) -> tuple[str, list[str]]:
    """只把白名单顶层段从源搬到目标；其余段（含注释）原样保留目标内容。"""
    src_blocks = {k: lines for k, lines in split_top_blocks(src_text) if k}
    dst_blocks = split_top_blocks(dst_text)
    applied: list[str] = []
    out: list[str] = []
    for key, lines in dst_blocks:
        if key and key in CONFIG_SYNC_KEYS and key in src_blocks:
            if "".join(lines) != "".join(src_blocks[key]):
                applied.append(key)
                out.extend(src_blocks[key])
            else:
                out.extend(lines)
        else:
            out.extend(lines)
    present = {k for k, _ in dst_blocks if k}
    for key in CONFIG_SYNC_KEYS:
        if key in src_blocks and key not in present:
            applied.append(key + " (新增)")
            out.extend(src_blocks[key])
    return "".join(out), applied, []


# 两侧各自独立刷新的易变凭证：**脑侧保留自己的**（否则会把更新鲜的 token 用更旧的覆盖）
VOLATILE_CRED_KEYS = frozenset({
    # OAuth / agent-key 令牌（两侧各自独立刷新）
    "access_token", "refresh_token", "id_token",
    "obtained_at", "expires_at", "expires_in",
    "agent_key", "agent_key_id", "agent_key_expires_at",
    "agent_key_obtained_at", "agent_key_expires_in", "agent_key_reused",
    # 运行时健康/统计状态（与设置无关，跨侧搬动只会互相污染）
    "updated_at", "last_refresh", "last_status", "last_status_at",
    "last_error_code", "last_error_message", "last_error_reason",
    "last_error_reset_at", "request_count",
})


def merge_auth(src_text: str, dst_text: str) -> tuple[str, list[str], list[str]]:
    """auth.json：递归合并，源覆盖叶子，目标独有 provider/键保留；
    易变 token 字段（VOLATILE_CRED_KEYS）保留脑侧值 —— API key / provider 定义仍以 webui 为准。"""
    merged, changed = merge_json(json.loads(src_text), json.loads(dst_text), keep_target=VOLATILE_CRED_KEYS)
    return json.dumps(merged, ensure_ascii=False, indent=2) + "\n", changed, []


# ---------------------------------------------------------------- 主流程

def sync_file(name: str, state: dict, merge_fn=None, text_mode: bool = False) -> bool:
    """返回 True 表示目标被改写。"""
    src = os.path.join(SRC_DIR, name)
    dst = os.path.join(DST_DIR, name)
    if not os.path.isfile(src):
        return False
    if not os.path.isfile(dst):
        log(f"⚠ {name}: 脑侧不存在，跳过（首次同步请手工初始化）")
        return False

    src_hash = sha(src)
    rec = state.get(name, {})
    if not FORCE and rec.get("src_hash") == src_hash:
        return False                                   # webui 侧没变 → 无事可做

    src_raw = open(src, "rb").read()
    dst_raw = open(dst, "rb").read()
    dst_hash = hashlib.sha256(dst_raw).hexdigest()[:16]
    target_diverged = bool(rec.get("dst_hash")) and rec.get("dst_hash") != dst_hash

    if text_mode:
        if src_raw == dst_raw:
            log(f"= {name}: 内容已一致")
            state[name] = {"src_hash": src_hash, "dst_hash": dst_hash, "ts": now()}
            return False
        if target_diverged:
            conf = f"{dst}.conflict-{time.strftime('%Y%m%d-%H%M%S')}"
            if not DRY:
                shutil.copy2(src, conf)
                try:
                    os.chown(conf, 10000, 10000)
                except OSError:
                    pass
            log(f"⚠ {name}: 脑侧自上次同步后也被改动 → **不动脑侧**，webui 版本另存为 {os.path.basename(conf)}")
            state[name] = {"src_hash": src_hash, "dst_hash": dst_hash, "ts": now(), "conflict": os.path.basename(conf)}
            return False
        backup(dst)
        writing_atomic(dst, src_raw)
        log(f"→ {name}: 单向覆盖脑侧（webui → brain）")
        state[name] = {"src_hash": src_hash, "dst_hash": sha(dst), "ts": now()}
        return True

    new_text, changed, added = merge_fn(src_raw.decode("utf-8"), dst_raw.decode("utf-8"))
    new_raw = new_text.encode("utf-8")
    if not changed and not added:
        # 语义上无差异就别写盘：否则 json.dumps 重新序列化会反复改写脑侧文件（无谓变更 + mtime 抖动）
        log(f"= {name}: 无实质变化（仅格式差异）")
        state[name] = {"src_hash": src_hash, "dst_hash": dst_hash, "ts": now()}
        return False
    if new_raw == dst_raw:
        log(f"= {name}: 合并后无变化")
        state[name] = {"src_hash": src_hash, "dst_hash": dst_hash, "ts": now()}
        return False
    detail = ""
    if changed:
        detail += " 覆盖 " + ",".join(changed[:8]) + ("…" if len(changed) > 8 else "")
    if added:
        detail += " 追加 " + ",".join(added[:8]) + ("…" if len(added) > 8 else "")
    if target_diverged:
        detail += "（注意：脑侧自上次同步后也有改动，已按键合并、以 webui 为准）"
    if DRY:
        log(f"[dry-run] {name}: 将写入脑侧。{detail}")
        return False
    backup(dst)
    writing_atomic(dst, new_raw)
    log(f"→ {name}: 已同步到脑侧。{detail}")
    state[name] = {"src_hash": src_hash, "dst_hash": sha(dst), "ts": now()}
    return True


def main() -> int:
    if not os.path.isdir(SRC_DIR) or not os.path.isdir(DST_DIR):
        log("✗ 源或目标目录不存在，退出", force=True)
        return 1
    state = load_state()
    before = dict(state)
    results = {
        ".env": sync_file(".env", state, merge_env),
        "auth.json": sync_file("auth.json", state, merge_auth),
        "config.yaml": sync_file("config.yaml", state, merge_config),
        "SOUL.md": sync_file("SOUL.md", state, text_mode=True),
    }
    if not DRY and state != before:
        save_state(state)
    changed = [k for k, v in results.items() if v]
    if changed:
        log(f"✔ 本轮已同步：{', '.join(changed)}", force=True)
    elif not QUIET:
        log("（无变化）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

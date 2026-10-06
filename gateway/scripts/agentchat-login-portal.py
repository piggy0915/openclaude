#!/usr/bin/env python3
"""
agentchat-login-portal.py — AgentChat 登录门户（宿主机运行，端口默认 8899）。

为什么需要它：
  AgentChat 的登录态靠 /opt/data/chrome-profile 里的 cookie，而多家平台的登录凭据是
  会话级 cookie，Chrome/容器一重启就掉。这个页面把「各平台登录二维码 + 上次复核状态」
  集中呈现，手机扫一扫即可恢复。

设计要点：
  - **按需生成**：只有页面被打开/刷新时才抓二维码（缓存 ttl 秒），没人在看时完全不动作
    —— 避免后台循环不停开标签页干扰 AgentChat 链路。
  - **状态只认真调用**：状态取自 agentchat-login-check.sh 写的 login-status.json。
    不用启发式（着陆页文案 / cookie 条数 / 能否抓到二维码都踩过假阳性：
    Qwen 已登录时首页照样显示"登录"、也能抓出二维码）。
  - `/recheck` 后台触发一次真调用复核（约每平台 30~50s），页面轮询 /recheck_status。

用法：
  python3 agentchat-login-portal.py [--port 8899] [--ttl 90]
"""
import argparse
import io
import json
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

CONTAINER = os.environ.get("HERMES_CONTAINER", "hermes")
QR_SCRIPT = "/opt/data/scripts/login-qr.js"
SHOTS_HOST = "/home/user/gateway/data/opt-data/cdp-shots"
STATUS_HOST = "/home/user/gateway/data/opt-data/profile-backups/login-status.json"

# (key, 显示名, 扫码提示)
PLATFORMS = [
    ("kimi",     "Kimi",              "微信扫码"),
    ("deepseek", "DeepSeek",          "微信扫码，扫完需在手机上点「确认授权」"),
    ("qwen",     "千问 Qwen",          "手机号+验证码 / 千问App扫码 / 淘宝支付宝"),
    ("hunyuan",  "腾讯元宝 Hunyuan",   "优先手机号+验证码；微信扫码常加载不出"),
    ("minimax",  "MiniMax",           "扫码登录"),
    ("mimo",     "小米 MiMo",          "扫码登录"),
]
VALID = {k for k, _, _ in PLATFORMS}

STATUS_LABEL = {
    "OK": ("✅ 可用", "#4ade80"),
    "AUTH": ("❌ 需扫码", "#f87171"),
    "TIMEOUT": ("❌ 需扫码", "#f87171"),
    "QUOTA": ("⚠️ 额度耗尽", "#fbbf24"),
    "USAGE": ("⚠️ 调用异常", "#fbbf24"),
}

_cache = {}
_locks = {}
_glock = threading.Lock()
_recheck = {"running": False, "started": None, "done": None, "output": ""}
_rlock = threading.Lock()


def _lock_for(key):
    with _glock:
        _locks.setdefault(key, threading.Lock())
        return _locks[key]


def _run(args, timeout):
    return subprocess.run(["docker", "exec", CONTAINER] + args,
                          capture_output=True, text=True, timeout=timeout)


def _qr_valid(png):
    """像素法判定二维码是否有效（区分「有效码」与「灰色过期的占位图」）。
    实测标定 2026-10-04：有效码暗像素≈0.23~0.32、亮≈0.57~0.69；
    过期灰化图暗像素≈0.00、亮≈0.99。阈值取 dark>0.12 且 light>0.12。"""
    try:
        from PIL import Image
        im = Image.open(io.BytesIO(png)).convert("L")
        px = list(im.getdata())
        n = len(px)
        dark = sum(1 for v in px if v < 80) / n
        light = sum(1 for v in px if v > 200) / n
        return (dark > 0.12 and light > 0.12), dark, light
    except Exception:                                          # noqa: BLE001
        return True, -1.0, -1.0                                # 无法判定时不拦


def _generate(key):
    """抓码；识别 STATE=scanned/expired/missing，并对灰化码自动 --force 重生成。"""
    note = "未找到二维码"
    for attempt in range(3):
        args = ["node", QR_SCRIPT, key] + (["--force"] if attempt else [])
        try:
            r = _run(args, 200)
            out = (r.stdout or "") + (r.stderr or "")
        except subprocess.TimeoutExpired:
            return None, "抓取超时"
        except Exception as e:                                 # noqa: BLE001
            return None, f"抓取异常: {e}"

        m = re.search(r"STATE=(\w+)", out)
        state = m.group(1) if m else None

        if state == "scanned":
            hit = _cache.get(key)
            return (hit[1] if hit else None), "已扫描 —— 请在手机上点「确认授权」"
        if state == "missing":
            return None, "未找到二维码（该平台未弹出登录框，刷新重试）"

        path = os.path.join(SHOTS_HOST, f"{key}-qr.png")
        if not os.path.exists(path):
            note = "未生成图片"
            continue
        with open(path, "rb") as fh:
            data = fh.read()
        ok, dark, light = _qr_valid(data)
        if ok:
            return data, f"有效码（暗{dark:.2f}/亮{light:.2f}）"
        note = f"二维码已过期/灰化（暗{dark:.3f}），正在重生成…"
    return None, note


def get_qr(key, ttl):
    hit = _cache.get(key)
    if hit and hit[1] is not None and time.time() - hit[0] < ttl:
        return hit[1], hit[2]
    with _lock_for(key):
        hit = _cache.get(key)
        if hit and time.time() - hit[0] < ttl:
            return hit[1], hit[2]
        data, note = _generate(key)
        if data is not None:            # 只缓存成功结果——失败要立刻允许重试，别把 404 缓存 60s
            _cache[key] = (time.time(), data, note)
        return data, note


def read_status():
    try:
        with open(STATUS_HOST, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:                                          # noqa: BLE001
        return {"checked_at": None, "platforms": {}}


def _recheck_worker(keys):
    try:
        r = _run(["sh", "/opt/data/scripts/agentchat-login-check.sh"] + keys, 1200)
        out = ((r.stdout or "") + (r.stderr or "")).strip()[-800:]
    except Exception as e:                                     # noqa: BLE001
        out = f"复核异常: {e}"
    with _rlock:
        _recheck["running"] = False
        _recheck["done"] = time.strftime("%Y-%m-%d %H:%M:%S")
        _recheck["output"] = out


PAGE = """<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="{ttl}">
<title>AgentChat 登录门户</title>
<style>
 body{{font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;background:#0f1115;color:#e6e6e6;margin:0;padding:24px}}
 h1{{font-size:20px;margin:0 0 6px}} .sub{{color:#8b93a7;font-size:13px;line-height:1.9;margin-bottom:16px}}
 .bar{{background:#171a21;border:1px solid #262b36;border-radius:10px;padding:12px 16px;margin-bottom:18px;font-size:13px}}
 a.btn{{display:inline-block;background:#2563eb;color:#fff;padding:6px 14px;border-radius:7px;text-decoration:none;font-size:13px}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:18px}}
 .card{{background:#171a21;border:1px solid #262b36;border-radius:12px;padding:16px}}
 .name{{font-size:15px;font-weight:600}} .hint{{font-size:12px;color:#8b93a7;margin:4px 0 8px;min-height:30px}}
 .stat{{font-size:12px;margin-bottom:10px;padding:4px 8px;border-radius:6px;background:#0f1115;display:inline-block}}
 img{{width:100%;max-width:280px;background:#fff;border-radius:8px;display:block}}
 .bad{{color:#f87171;font-size:12px;padding:16px 0}}
 .foot{{margin-top:22px;font-size:12px;color:#6b7280;line-height:1.9}}
</style></head><body>
<h1>AgentChat 登录门户</h1>
<div class="sub">
 <b style="color:#fbbf24">用手机（微信/千问App/豆包App）扫码登录</b>——扫完无需在此操作。
 页面每 <b>{ttl}</b> 秒自动重载并重新生成二维码；<b style="color:#f87171">二维码只有约 2 分钟有效期，看到后请立刻扫</b>，过期就刷新本页。<br>
 <b>状态只认真调用复核</b>：着陆页写不写"登录"、cookie 多少条都不作数（Qwen 已登录时首页照样显示"登录"）。
</div>
<div class="bar">
 上次复核：<b>{checked}</b> &nbsp;|&nbsp;
 {summary}
 &nbsp;|&nbsp; <a class="btn" href="/">刷新二维码</a>
 &nbsp;|&nbsp; <a class="btn" href="/recheck">重新检测登录状态</a>
 {recheck_note}
</div>
<div class="grid">
{cards}
</div>
<div class="foot">
 不可恢复：Gemini / ChatGPT（GFW 需代理）、Claude（区域限制）、ChatGLM（阿里滑块，自动化过不了）。
</div></body></html>"""

CARD = """  <div class="card"><div class="name">{name}</div><div class="hint">{hint}</div>
    <div class="stat" style="color:{color}">{status} <span style="color:#6b7280">{reason}</span></div>
    <img src="/qr?key={key}&t={ts}" alt="{name} 二维码"
         onerror="this.style.display='none';this.nextElementSibling.style.display='block'">
    <div class="bad" style="display:none">二维码未就绪 —— 未弹出登录框，刷新页面重试</div>
  </div>"""


class Handler(BaseHTTPRequestHandler):
    ttl = 90

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def do_GET(self):                                          # noqa: N802
        u = urlparse(self.path)
        q = parse_qs(u.query)

        if u.path in ("/", "/index.html"):
            st = read_status()
            plats = st.get("platforms", {})
            ts = str(int(time.time()))
            cards = []
            for k, n, h in PLATFORMS:
                rec = plats.get(k) or {}
                label, color = STATUS_LABEL.get(rec.get("status"), ("❔ 未复核", "#9ca3af"))
                reason = rec.get("reason") or ""
                cards.append(CARD.format(key=k, name=n, hint=h, ts=ts,
                                         status=label, color=color, reason=reason))
            need = sum(1 for k, _, _ in PLATFORMS
                       if (plats.get(k) or {}).get("status") in ("AUTH", "TIMEOUT"))
            summary = (f'<span style="color:#f87171">需扫码 {need} 家</span>' if need
                       else '<span style="color:#4ade80">无需扫码</span>')
            with _rlock:
                note = ""
                if _recheck["running"]:
                    note = f' <span style="color:#fbbf24">复核进行中…（开始于 {_recheck["started"]}）</span>'
                elif _recheck["done"]:
                    note = f' <span style="color:#6b7280">上次触发 {_recheck["done"]}</span>'
            html = PAGE.format(ttl=self.ttl, ts=ts, cards="\n".join(cards),
                               checked=st.get("checked_at") or "尚未复核",
                               summary=summary, recheck_note=note)
            self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
            return

        if u.path == "/recheck":
            with _rlock:
                if not _recheck["running"]:
                    _recheck.update(running=True, started=time.strftime("%H:%M:%S"), output="")
                    threading.Thread(target=_recheck_worker,
                                     args=([k for k, _, _ in PLATFORMS],), daemon=True).start()
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()
            return

        if u.path == "/qr":
            key = (q.get("key") or [""])[0]
            if key not in VALID:
                self._send(400, b"bad key", "text/plain; charset=utf-8")
                return
            data, note = get_qr(key, self.ttl)
            self._send(200, data, "image/png") if data else self._send(404, note.encode(), "text/plain; charset=utf-8")
            return

        if u.path == "/status":
            st = read_status()
            with _rlock:
                st["recheck"] = dict(_recheck)
            st["qr_cache"] = {k: {"age_s": round(time.time() - v[0]), "ok": bool(v[1])}
                              for k, v in _cache.items()}
            self._send(200, json.dumps(st, ensure_ascii=False, indent=2).encode("utf-8"),
                       "application/json; charset=utf-8")
            return

        self._send(404, b"not found", "text/plain; charset=utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--ttl", type=int, default=90)
    a = ap.parse_args()
    Handler.ttl = a.ttl
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), Handler)
    print(f"[portal] http://0.0.0.0:{a.port}/  ttl={a.ttl}s  平台={sorted(VALID)}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()

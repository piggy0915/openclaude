#!/usr/bin/env python3
"""重排分数归一化代理

背景：llama.cpp 的 /v1/rerank 返回原始 logits（可正可负，实测 -12~+8），
而 Dify 检索链路写死 score_threshold=0.0（见 core/rag/retrieval/dataset_retrieval.py
「score_threshold=... else 0.0」），负分候选会被全部过滤 → hybrid+rerank 返回空。
本代理把 logits 经 sigmoid 压到 (0,1)，排序不变但不再被阈值误杀。

监听 0.0.0.0:8000，转发到 RERANK_UPSTREAM（默认 http://reranker-llama-real:8000）。
同时通过 compose 网络别名接管 reranker-llama，因此 Dify 侧配置无需改动。
"""
import http.client
import json
import math
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

UPSTREAM = os.environ.get("RERANK_UPSTREAM", "http://reranker-llama-real:8000")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8000"))


def sigmoid(x: float) -> float:
    if x >= 0:
        return 1.0 / (1.0 + math.exp(-x))
    z = math.exp(x)
    return z / (1.0 + z)


def forward(method, path, body):
    u = urlsplit(UPSTREAM)
    conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=300)
    conn.request(method, u.path.rstrip("/") + path, body=body,
                 headers={"Content-Type": "application/json"})
    resp = conn.getresponse()
    data = resp.read()
    ctype = resp.getheader("Content-Type", "application/json")
    conn.close()
    return resp.status, data, ctype


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[rerank-proxy] " + fmt % args + "\n")

    def _send(self, code, payload, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        try:
            code, data, ctype = forward("GET", self.path, None)
            self._send(code, data, ctype)
        except Exception as e:  # noqa: BLE001
            self._send(502, json.dumps({"error": str(e)}).encode())

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""

        try:
            code, data, ctype = forward("POST", self.path, body)
        except Exception as e:  # noqa: BLE001
            self._send(502, json.dumps({"error": str(e)}).encode())
            return

        if code != 200 or "/rerank" not in self.path:
            self._send(code, data, ctype)
            return

        try:
            payload = json.loads(data)
        except Exception:  # noqa: BLE001
            self._send(200, data, ctype)
            return

        results = payload.get("results")
        if isinstance(results, list):
            for item in results:
                if not isinstance(item, dict):
                    continue
                raw = item.get("relevance_score", item.get("score"))
                if isinstance(raw, (int, float)):
                    item["relevance_score"] = round(sigmoid(float(raw)), 6)

        self._send(200, json.dumps(payload).encode(), "application/json")


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    print(f"[rerank-proxy] listening :{LISTEN_PORT} -> {UPSTREAM}", flush=True)
    srv.serve_forever()

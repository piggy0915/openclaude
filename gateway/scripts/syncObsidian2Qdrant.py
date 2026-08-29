#!/usr/bin/env python3
"""
Obsidian 笔记自动同步到 Qdrant（watchdog 实时版）
================================================
与手动全量版 scripts/sync_obsidian_to_qdrant.sh **共享同一套规则**：
  - point_id = uuid5(rel#idx)        （与 shell 版一致，幂等互认）
  - 切片 350 字                       （bge 512 token 硬限）
  - embedding 端点 /v1/embeddings    （OpenAI 兼容，llama.cpp）
  - 排除 .obsidian / awesome-design-md / temp
  - payload 带 domain 字段            （多业务隔离）

开关：WATCHDOG_ENABLED=0 时只做初始全量同步后退出（相当于一次性同步）；
      默认 1 = 常驻监听。手动全量重建用 shell 版，两套共用 id 规则不冲突。
"""
import os
import time
import json
import logging
import uuid
import urllib.request
import urllib.error
from pathlib import Path
from datetime import datetime
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

VAULT_PATH = os.environ.get('OBSIDIAN_VAULT_PATH', '/knowledge_base/obsidian')
QDRANT_HOST = os.environ.get('QDRANT_HOST', 'qdrant')
QDRANT_PORT = os.environ.get('QDRANT_PORT', '6333')
QDRANT_COLLECTION = os.environ.get('QDRANT_COLLECTION', 'hermes_memory')
QDRANT_API_KEY = os.environ.get('QDRANT_API_KEY', '')
EMBEDDING_URL = os.environ.get('EMBEDDING_URL', 'http://embedding-llama:8000/v1/embeddings')
EMBEDDING_MODEL = os.environ.get('EMBEDDING_MODEL', 'bge-large-zh-v1.5')
CHUNK_SIZE = int(os.environ.get('CHUNK_SIZE', '350'))   # bge 512 token ~380 中文字，取 350 安全
WATCHDOG_ENABLED = os.environ.get('WATCHDOG_ENABLED', '1') == '1'
EXCLUDE_PATTERNS = ('.obsidian', 'awesome-design-md', '/temp/', '/archive/')


def domain_for(rel: str) -> str:
    nqms_kw = ('nqms', '评价', '质量', '装备', '业务架构')
    # rel 形如 knowledge/concepts/x.md（relative_to VAULT_PATH 后仍带 knowledge/ 前缀）
    # 先去掉 knowledge/ 前缀再判断
    p = rel[10:] if rel.startswith('knowledge/') else rel
    # concepts/entities 是业务知识层：NQMS 库内的概念/实体页默认 nqms
    if p.startswith('concepts/') or p.startswith('entities/'):
        return 'nqms'
    # raw/doc 官方文档：按文件名关键字
    if p.startswith('raw/doc/'):
        return 'nqms' if any(k in p for k in nqms_kw) else 'general'
    # raw/web 剪藏：按文件名关键字
    if p.startswith('raw/web/'):
        return 'nqms' if any(k in p for k in nqms_kw) else 'general'
    return 'general'


def should_skip(rel: str) -> bool:
    return any(p in rel for p in EXCLUDE_PATTERNS)


class QdrantSyncHandler(FileSystemEventHandler):
    def __init__(self):
        self.processed = {}

    def get_embedding(self, text):
        payload = json.dumps({"model": EMBEDDING_MODEL, "input": text}).encode()
        req = urllib.request.Request(EMBEDDING_URL, data=payload,
                                     headers={"Content-Type": "application/json"})
        resp = urllib.request.urlopen(req, timeout=60)
        data = json.loads(resp.read())
        return data["data"][0]["embedding"]

    def qdrant_request(self, method, path, body=None):
        url = f"http://{QDRANT_HOST}:{QDRANT_PORT}{path}"
        data = json.dumps(body).encode() if body else None
        req = urllib.request.Request(url, data=data,
                                     headers={"Content-Type": "application/json",
                                              "api-key": QDRANT_API_KEY},
                                     method=method)
        try:
            resp = urllib.request.urlopen(req, timeout=30)
            return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            return {"error": e.code, "detail": e.read().decode()[:200]}

    def sync_file(self, filepath):
        if not os.path.exists(filepath):
            return
        if not filepath.endswith('.md'):
            return
        rel_path = str(Path(filepath).relative_to(VAULT_PATH))
        if should_skip(rel_path):
            return
        with open(filepath, 'rb') as f:
            cur_hash = self._md5(f.read())
        if filepath in self.processed and self.processed[filepath] == cur_hash:
            return
        self.processed[filepath] = cur_hash
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        if not content.strip():
            return
        title = Path(filepath).stem
        chunks = [content[i:i + CHUNK_SIZE] for i in range(0, len(content), CHUNK_SIZE)]
        total = len(chunks)
        domain = domain_for(rel_path)
        for idx, chunk in enumerate(chunks):
            if not chunk.strip():
                continue
            try:
                vec = self.get_embedding(chunk)
            except Exception as e:
                logger.error(f"Embedding error {rel_path}#{idx}: {e}")
                continue
            point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"{rel_path}#{idx}"))
            body = {
                "points": [{
                    "id": point_id,
                    "vector": vec,
                    "payload": {
                        "path": rel_path,
                        "title": title,
                        "text": chunk,
                        "source": "obsidian",
                        "kind": "wiki",
                        "chunk": idx,
                        "total": total,
                        "domain": domain,
                        "modified": datetime.now().isoformat()
                    }
                }]
            }
            result = self.qdrant_request("PUT", f"/collections/{QDRANT_COLLECTION}/points", body)
            if "error" in result:
                logger.error(f"Qdrant error {rel_path}#{idx}: {result}")
            else:
                logger.info(f"Synced: {rel_path}#{idx} (domain={domain})")

    @staticmethod
    def _md5(data):
        import hashlib
        return hashlib.md5(data).hexdigest()

    def on_modified(self, event):
        if not event.is_directory and event.src_path.endswith('.md'):
            time.sleep(3)
            self.sync_file(event.src_path)

    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.md'):
            time.sleep(3)
            self.sync_file(event.src_path)

    def on_deleted(self, event):
        if not event.is_directory and event.src_path.endswith('.md'):
            try:
                rel = str(Path(event.src_path).relative_to(VAULT_PATH))
                # 删除该文件全部 chunk：按 path 精确过滤（Qdrant filter 是精确匹配）
                body = {"filter": {"must": [{"key": "path", "match": {"value": rel}}]}}
                self.qdrant_request("POST", f"/collections/{QDRANT_COLLECTION}/points/delete", body)
                logger.info(f"Deleted: {rel}")
            except Exception:
                pass


def ensure_collection():
    req = urllib.request.Request(
        f"http://{QDRANT_HOST}:{QDRANT_PORT}/collections/{QDRANT_COLLECTION}",
        headers={"api-key": QDRANT_API_KEY})
    try:
        urllib.request.urlopen(req, timeout=5)
        return
    except urllib.error.HTTPError:
        pass

    sample = None
    for f in Path(VAULT_PATH).rglob('*.md'):
        if not should_skip(str(f.relative_to(VAULT_PATH))):
            sample = f.read_text(encoding='utf-8')[:CHUNK_SIZE]
            break
    if not sample:
        return

    payload = json.dumps({"model": EMBEDDING_MODEL, "input": sample}).encode()
    req = urllib.request.Request(EMBEDDING_URL, data=payload,
                                 headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, timeout=60)
    vec = json.loads(resp.read())["data"][0]["embedding"]
    dim = len(vec)

    body = {"name": QDRANT_COLLECTION, "vectors": {"size": dim, "distance": "Cosine"}}
    req = urllib.request.Request(
        f"http://{QDRANT_HOST}:{QDRANT_PORT}/collections",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "api-key": QDRANT_API_KEY},
        method="PUT")
    try:
        urllib.request.urlopen(req, timeout=10)
        logger.info(f"Created collection {QDRANT_COLLECTION} (dim={dim})")
    except Exception as e:
        logger.error(f"Create collection error: {e}")


def main():
    logger.info(f"Watching: {VAULT_PATH}")
    logger.info(f"Qdrant: {QDRANT_HOST}:{QDRANT_PORT}/{QDRANT_COLLECTION}")
    logger.info(f"Embedding: {EMBEDDING_URL}")
    logger.info(f"WATCHDOG_ENABLED={WATCHDOG_ENABLED} CHUNK_SIZE={CHUNK_SIZE}")

    if not os.path.exists(VAULT_PATH):
        logger.error(f"Vault path not found: {VAULT_PATH}")
        return

    ensure_collection()

    logger.info("Initial sync...")
    handler = QdrantSyncHandler()
    count = 0
    for f in sorted(Path(VAULT_PATH).rglob("*.md")):
        rel = str(f.relative_to(VAULT_PATH))
        if not should_skip(rel):
            handler.sync_file(str(f))
            count += 1
    logger.info(f"Initial sync done ({count} files)")

    if not WATCHDOG_ENABLED:
        logger.info("WATCHDOG_ENABLED=0: one-shot sync complete, exiting")
        return

    observer = Observer()
    observer.schedule(handler, VAULT_PATH, recursive=True)
    observer.start()
    logger.info("Watching for changes...")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


if __name__ == '__main__':
    main()

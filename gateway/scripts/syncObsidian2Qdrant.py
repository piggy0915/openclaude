#!/usr/bin/env python3
"""
Obsidian 笔记自动同步到 Qdrant 向量数据库
监听 /knowledge_base/obsidian 下 .md 文件变化，直接写入 Qdrant
"""
import os
import time
import json
import logging
import hashlib
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
QDRANT_COLLECTION = os.environ.get('QDRANT_COLLECTION', 'hermes_knowledge')
QDRANT_API_KEY = os.environ.get('QDRANT_API_KEY', '')
EMBEDDING_URL = os.environ.get('EMBEDDING_URL', 'http://embedding-llama:8000/embedding')
MAX_CHARS = 500  # bge-large-zh 约 512 token


class QdrantSyncHandler(FileSystemEventHandler):
    def __init__(self):
        self.processed = {}

    def get_embedding(self, text):
        if len(text) > MAX_CHARS:
            text = text[:MAX_CHARS]
        payload = json.dumps({"content": text}).encode()
        req = urllib.request.Request(EMBEDDING_URL, data=payload,
                                     headers={"Content-Type": "application/json"})
        resp = urllib.request.urlopen(req, timeout=30)
        data = json.loads(resp.read())
        return data[0]["embedding"][0]

    def qdrant_request(self, method, path, body=None):
        url = f"http://{QDRANT_HOST}:{QDRANT_PORT}{path}"
        data = json.dumps(body).encode() if body else None
        req = urllib.request.Request(url, data=data,
                                     headers={"Content-Type": "application/json",
                                              "api-key": QDRANT_API_KEY},
                                     method=method)
        try:
            resp = urllib.request.urlopen(req, timeout=10)
            return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            return {"error": e.code, "detail": e.read().decode()[:200]}

    def sync_file(self, filepath):
        if not os.path.exists(filepath):
            return
        if not filepath.endswith('.md'):
            return

        with open(filepath, 'rb') as f:
            cur_hash = hashlib.md5(f.read()).hexdigest()
        if filepath in self.processed and self.processed[filepath] == cur_hash:
            return
        self.processed[filepath] = cur_hash

        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        if not content.strip():
            return

        rel_path = str(Path(filepath).relative_to(VAULT_PATH))
        title = Path(filepath).stem
        point_id = hashlib.md5(rel_path.encode()).hexdigest()

        try:
            vec = self.get_embedding(content)
        except Exception as e:
            logger.error(f"Embedding error {rel_path}: {e}")
            return

        body = {
            "points": [{
                "id": point_id,
                "vector": vec,
                "payload": {
                    "path": rel_path,
                    "title": title,
                    "content": content[:5000],
                    "source": "obsidian",
                    "modified": datetime.now().isoformat()
                }
            }]
        }
        result = self.qdrant_request("PUT", f"/collections/{QDRANT_COLLECTION}/points", body)
        if "error" in result:
            logger.error(f"Qdrant error {rel_path}: {result}")
        else:
            logger.info(f"Synced: {rel_path}")

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
                pid = hashlib.md5(rel.encode()).hexdigest()
                self.qdrant_request("POST", f"/collections/{QDRANT_COLLECTION}/points/delete",
                                    {"points": [pid]})
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

    # Get dim from first file
    sample = None
    for f in Path(VAULT_PATH).rglob('*.md'):
        if '.obsidian' not in str(f):
            sample = f.read_text(encoding='utf-8')[:MAX_CHARS]
            break
    if not sample:
        return

    payload = json.dumps({"content": sample}).encode()
    req = urllib.request.Request(EMBEDDING_URL, data=payload,
                                 headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(req, timeout=30)
    vec = json.loads(resp.read())[0]["embedding"][0]
    dim = len(vec)

    body = {
        "name": QDRANT_COLLECTION,
        "vectors": {"size": dim, "distance": "Cosine"}
    }
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

    if not os.path.exists(VAULT_PATH):
        logger.error(f"Vault path not found: {VAULT_PATH}")
        return

    ensure_collection()

    logger.info("Initial sync...")
    handler = QdrantSyncHandler()
    count = 0
    for f in sorted(Path(VAULT_PATH).rglob("*.md")):
        if ".obsidian" not in str(f):
            handler.sync_file(str(f))
            count += 1
    logger.info(f"Initial sync done ({count} files)")

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

#!/usr/bin/env python3
"""
Obsidian 笔记自动同步到 Qdrant 向量数据库
"""

import os
import time
import logging
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import requests
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ObsidianSyncHandler(FileSystemEventHandler):
    """监听 Obsidian Vault 文件变化"""

    def __init__(self, hermes_api_url, api_key):
        self.hermes_api = hermes_api_url
        self.api_key = api_key
        self.processed_files = set()

    def on_modified(self, event):
        if not event.is_directory and event.src_path.endswith('.md'):
            self.sync_file(event.src_path)

    def on_created(self, event):
        if not event.is_directory and event.src_path.endswith('.md'):
            self.sync_file(event.src_path)

    def sync_file(self, filepath):
        """同步单个文件到 Qdrant"""
        if filepath in self.processed_files:
            return

        logger.info(f"Syncing: {filepath}")

        # 读取 Markdown 内容
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # 调用 Hermes API 添加知识
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }

        payload = {
            'documents': [{
                'content': content,
                'metadata': {
                    'source': filepath,
                    'source_type': 'obsidian',
                    'filename': Path(filepath).name
                }
            }]
        }

        try:
            response = requests.post(
                f"{self.hermes_api}/api/v1/knowledge/add",
                headers=headers,
                json=payload,
                timeout=30
            )
            if response.status_code == 200:
                logger.info(f"Successfully synced: {filepath}")
                self.processed_files.add(filepath)
            else:
                logger.error(f"Failed to sync {filepath}: {response.text}")
        except Exception as e:
            logger.error(f"Error syncing {filepath}: {e}")

def main():
    vault_path = os.environ.get('OBSIDIAN_VAULT_PATH', '/knowledge_base/obsidian')
    hermes_api = os.environ.get('HERMES_API_URL', 'http://hermes:8000')
    api_key = os.environ.get('API_SERVER_KEY', '')

    if not os.path.exists(vault_path):
        logger.error(f"Vault path not found: {vault_path}")
        return

    event_handler = ObsidianSyncHandler(hermes_api, api_key)
    observer = Observer()
    observer.schedule(event_handler, vault_path, recursive=True)
    observer.start()

    logger.info(f"Watching Obsidian vault: {vault_path}")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()

if __name__ == '__main__':
    main()
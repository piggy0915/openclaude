# Qdrant Memory Provider 部署指南

## 文件清单

创建以下 3 个文件，确保路径与你的 docker-compose.yml 一致：

### 1. `./data/hermes/plugins/qdrant/plugin.yaml`

```yaml
name: qdrant
version: 1.0.0
description: "Qdrant vector database memory provider"
pip_dependencies:
  - qdrant-client>=1.12.0
requires_env:
  - QDRANT_HOST
  - QDRANT_PORT
hooks:
  - on_session_end
  - on_memory_write
```

### 2. `./data/hermes/plugins/qdrant/cli.py`

支持 `hermes memory setup` 的交互式配置向导。

### 3. `./data/hermes/plugins/qdrant/__init__.py`

主插件代码，包含 `QdrantMemoryProvider` 实现。

## 架构详解

```
┌──────────────────────────────────────────────────────────┐
│                     Docker Network                         │
│                    rag-network                             │
│                                                            │
│  ┌──────────────┐    ┌──────────────────────┐             │
│  │   Qdrant     │    │    Hermes Agent      │             │
│  │  (qdrant:6333)◄───┤                      │             │
│  │              │    │  plugins/qdrant/      │             │
│  │ 存储向量点    │    │  __init__.py         │             │
│  └──────────────┘    │                      │             │
│                      │  read config.yaml    │             │
│  ┌──────────────┐    │  └── memory.provider  │             │
│  │ Embedding    │    │  └── embeddings.*     │             │
│  │ (embedding-  │    │                      │             │
│  │  llama:8000) ◄───┤  调用嵌入服务生成向量  │             │
│  └──────────────┘    └──────────────────────┘             │
└──────────────────────────────────────────────────────────┘
```

## 数据流

1. **写入**（`sync_turn` / `qdrant_conclude` / `on_memory_write`）
   ```
   Agent → 拼接文本 → 调用 embedding-llama 生成向量
                     → 写入 Qdrant hermes_memory 集合
                     → payload: {content, tags, timestamp, session_id}
   ```

2. **读取**（`prefetch` / `qdrant_search`）
   ```
   用户消息 → 调用 embedding-llama 生成查询向量
           → Qdrant search(COSINE 相似度)
           → 返回 top-k 结果注入 system prompt
   ```

## 验证

启动容器后检查日志：
```bash
docker logs hermes 2>&1 | grep -i qdrant
```

预期输出类似：
```
Qdrant connected: qdrant:6333
Created Qdrant collection: hermes_memory (dim=1024)
Qdrant provider initialized
```

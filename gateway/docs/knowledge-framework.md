# 系统知识框架结构（2026-09-13 实测）

> 三条知识主线：**行为知识**（技能）、**事实知识**（记忆）、**领域知识**（文档库）。
> 检索统一入口：`SOUL.md` 的 KB-FIRST 段 → `scripts/kb-lookup.sh` 三层。

## 一、总图：从数据源到 prompt 注入

```
                    ┌──────────────── 数据源 ────────────────┐
   Gitee 技能仓库       对话/工具调用        外部文档(PDF/DOC)   人工笔记/剪藏
   (604 技能)           (会话轮次)          (NQMS 规范/指南)     (web 剪藏)
        │                   │                    │                  │
        │ cp/install        │ 自动写入            │ 手动入库(OCR/anydoc) │ 手动剪藏
        ▼                   ▼                    ▼                  ▼
 ① 技能库            ③ 会话库            ⑤ Obsidian 知识库   ⑤ Obsidian raw/
 skills/ 528 文件    state.db            (LLM Wiki 三层)       raw/web·doc·papers
        │           1121 消息 + FTS              │                  │
        │                                          │ 手工同步(syncObsidian2Qdrant.py)
        │                                          ▼
        │                                  ④ 向量库 Qdrant
        │                                  hermes_memory 1735 点
        │                                          ▲
        │                                          │ Dify 另一条路径
        │                                  ⑦ Vector_index_* 316 点
        │                                     (Dify 知识库，2/7 有数据)
        │
        │                                       ② 长期记忆
        │                              memories/MEMORY.md 3406/6000 字符
        ▼                                          │
  ┌──────────────────── prompt 注入 / 检索 ─────────────────────┐
  │ 技能索引(453 条) │ MEMORY.md │ memory provider 自动检索        │
  │                              │ + kb-lookup.sh 三层按需检索     │
  └─────────────────────────────────────────────────────────────┘
```

## 二、分层明细

| # | 层 | 位置 | 规模 | 写入者 | 检索/注入方式 |
|---|---|---|---|---|---|
| ① | **技能库** | `data/hermes/skills`（容器 `/home/agent/.hermes/skills`） | 528 SKILL.md / 449 唯一名 / 50 分类 | `skill_manage`；Gitee 仓库 `install-skills-from-repo.sh` | 技能索引注入每次 prompt（453 条） |
| ② | **长期记忆** | `data/hermes/memories/MEMORY.md`（+ USER.md 未创建） | 3406 / 6000 字符（56%），27 条 | memory 工具 | 每轮注入 prompt |
| ③ | **会话库** | `data/hermes/state.db` | 2 会话 / 1121 消息 + messages_fts(cjk/trigram) | gateway 自动 | `session_search` 工具 |
| ④ | **向量库（记忆）** | Qdrant `hermes_memory`（容器 `qdrant:6333`） | **1735 点** / 1024 维 | memory provider；`syncObsidian2Qdrant.py` | ①每轮自动检索 ②`kb-lookup.sh` 第①段 |
| ⑤ | **Obsidian 知识库** | `data/obsidian/knowledge`（容器 `/knowledge_base/obsidian`） | 188 md / 39M | 人工 + AI（wiki 层） | `kb-lookup.sh` 第②段（全文 grep） |
| ⑥ | **Dify 知识库** | 同 Qdrant，`Vector_index_<dataset>_Node` | 7 集合，2 个有数据（204+112=316 点） | Dify 后台 | Dify API（`/v1/datasets/.../retrieve`） |
| ⑦ | **部署文档/清单** | `docs/`（13 篇）+ Gitee 仓库（5 篇） | 18 篇 | 人 + Agent | 直接读；未进向量库 |

> 说明：⑥ 与 ④ 共用同一个 Qdrant 实例 —— Dify 的知识库在向量层是"隔壁集合"，只是访问路径不同（Dify 走自己的 API，Agent 走 qdrant 直连）。

## 三、⑤ 观察库的内部框架（用户自定义：Karpathy LLM Wiki 三层）

```
knowledge/                    ← vault 根（SCHEMA.md 定规则）
├── SCHEMA.md                 结构/约定/标签体系（AI 操作本库必须遵守）
├── index.md                  全局目录索引（人+AI 入口）      ⚠️ 内容滞后
├── log.md                    操作日志，只追加                 ⚠️ 停在 08-30
├── raw/          （第一层，不可变，AI 只读）161 md + 12 非 md（PDF/DOC）
│   ├── web/   6 篇剪藏   ├── doc/  5 篇 + archive/ 历史提取
│   ├── papers/ 0         ├── note/ 0     └── temp/ 0
├── entities/     （第二层 wiki）3 篇   ← 实体页（人/组织/产品/标准）
├── concepts/     （第二层 wiki）20 篇  ← 概念页
├── comparisons/  （第二层 wiki）0 篇   ← 对比分析页
└── queries/      （第二层 wiki）0 篇   ← 值得保留的问答
```
第三层 = 查询时的人+AI 输出，**不落盘**（要沉淀就写进 `queries/`）。

## 四、检索路径（KB-FIRST 常驻行为）

```
会话开始 → SOUL.md 的 KB-FIRST 段
         → ① skill_view('using-superpowers')          先确立技能查找方式
         → ② bash scripts/kb-lookup.sh "<查询>"       三层一次跑完
               ① Qdrant 语义（hermes_memory 1735 点，含 161 obsidian 分块）
               ② Obsidian 全文（188 md，grep）
               ③ Dify（需 DIFY_DATASET_KEY，当前未配）
         → ③ memory provider 'qdrant' 每轮自动语义检索（已激活）
         → 回答末尾标来源；三层皆空则明说"知识库无相关记录"
自检：`scripts/check-kb-stack.sh`（10 项，已接入 restart.sh）
```

## 五、缺口与风险（实测）

| # | 缺口 | 证据 | 影响 |
|---|---|---|---|
| 1 | ~~Dify 第三层不可用~~ **✅ 已解决（09-14）** | 从 Dify `api_tokens` 表接线 `dataset` token → 写入 `.env` | 现有 2 库可检索：`infra-ops`(101 文档)、`standards` |
| 2 | ~~同步未自动化~~ **✅ 已解决（09-14）** | 已装 `/etc/cron.d/hermes-obsidian-sync`（每 6 小时） | 同步写入 `hermes_knowledge`；脚本另修两 bug（watchdog 惰性导入、建集合端点写错） |
| 3 | ~~index/log 滞后~~ **✅ 已解决（09-14）** | index 统计校正为 raw 161 / wiki 23；log 续写 1 条 | 遗留：raw/web 6 篇剪藏仍未提炼 |
| 4 | ~~USER.md 未创建~~ **✅ 已解决（09-14）** | 已写入 5 条（沟通风格/运维纪律/环境/领域/工作偏好），392/3000 字符 | — |
| 5 | ~~79 组重复副本~~ **✅ 已解决（09-14）** | `dedup-top-level-skills.sh --apply`：529 → **456** 文件（73 组移入 `/root/skill-dedup-backup-*`） | 1 组内容不一致已跳过（人工确认） |
| 6 | 技能索引待刷新 | 去重后磁盘 456 文件 | **⏳ 待成对重启**刷新（重启后索引应与磁盘一致） |
| 7 | ~~记忆结构单薄~~ **✅ 已解决（09-14）** | MEMORY.md 27 条 + USER.md 5 条（分层） | — |
| 8 | ~~部署文档不可检索~~ **✅ 已解决（09-14）** | `kb-lookup.sh` 新增第④段：grep `docs/` + Gitee 仓库文档 | — |

## 六、建议动作（按性价比排序）

```bash
# 1) 打通第三层：Dify 控制台 → 知识库 → API → 创建密钥 → 写入 .env
#    DIFY_DATASET_KEY=... / DIFY_DATASET_ID=...
#    然后成对重启，kb-lookup.sh 第③段自动生效

# 2) 把 Obsidian→Qdrant 同步纳入 cron（每 6 小时），消除 ④⑤ 脱节
#    0 */6 * * * root /home/user/gateway/scripts/syncObsidian2Qdrant.py >> /var/log/obsidian-sync.log 2>&1

# 3) 刷新 vault 索引与日志：更新 index.md 的 raw 清单（161 篇），log.md 续写

# 4) 清理技能重复副本 + 重启刷索引
scripts/dedup-top-level-skills.sh --apply

# 5) 把 docs/ 的部署文档纳入可检索范围（两个选项）
#    a. 复制/软链进 vault 的 raw/doc/（随之进 Qdrant）
#    b. 给 kb-lookup.sh 加第④段：grep docs/ 目录
```

---

## 七、2026-09-14 进展小结

| 项 | 结果 |
|---|---|
| 向量层分家 | `hermes_memory`（会话记忆，provider 用）+ **`hermes_knowledge`（笔记知识库，新建）** |
| 检索入口 | `kb-lookup.sh` 已扩为**四层**：① 记忆库 ② 知识库 ③ Dify ④ 部署文档 |
| 同步自动化 | `/etc/cron.d/hermes-obsidian-sync`，每 6 小时，幂等（point_id = uuid5(rel#idx)） |
| Dify 接线 | 复用 `api_tokens` 里既有的 `dataset` token；`DIFY_DATASET_IDS` 指向 infra-ops + standards |
| 技能库 | 去重后 456 文件；`kb-first-lookup` 技能已入库 |
| vault | index.md 统计校正、log.md 续记 |
| 待办 | ⏳ 成对重启刷新技能索引；可选项：清理 `hermes_memory` 里 161 个旧 obsidian 分块（现已改入 hermes_knowledge，属跨集合重复） |

---

## 八、2026-09-14 补充：采用方案 C（插件多集合检索）

**决定**：不让知识只走显式检索，而是**扩展插件让自动检索同时覆盖记忆库与知识库**，然后清掉 memory 里的笔记副本。

### 插件四处补丁（`plugins/qdrant/__init__.py`）

| # | 补丁 | 原因 |
|---|---|---|
| ① | `QdrantClient(..., https=False)` | qdrant-client 用 host/port 时默认 https=True → 对明文 6333 发 TLS → `SSL WRONG_VERSION_NUMBER` |
| ② | embedding >400 字符自动分块 + 归一平均 | llama.cpp 版 bge 上下文 512 token，长文档 `exceed_context_size_error` |
| ③ | **`client.search()` → `client.query_points()`** | **qdrant-client 1.19.0 已移除 `search`**；旧代码异常被 except 吞掉只写 debug → **自动检索一直静默失效** |
| ④ | **多集合检索**：`_search_memories` 查 `hermes_memory` + `hermes_knowledge`，按分数合并取 top-k；payload 兼容两种形态 | 内核 `memory` 配置**不支持多来源**，只能由插件扩展；集合名可配 `memory.vector_db.knowledge_collection` / 环境变量 `QDRANT_KNOWLEDGE_COLLECTION`（默认 `hermes_knowledge`） |

### 数据清理（可选项目 → 已执行）

| 项 | 前 | 后 |
|---|---|---|
| `hermes_memory` | 1752 点（含知识类 1445） | **307 点（纯会话记忆）** |
| `hermes_knowledge` | 1445 点 | 1445 点（不变） |
| 回滚清单 | — | `/root/qdrant-memory-knowledge-backup-20260914-064611.json`（1445 点 id+payload，1.6MB） |

判定依据：1445 点为**同 point_id 的逐字重复**（path/chunk/payload 键/正文全一致），孤儿 0。

### 验证（不重启即验证插件代码路径）

```
容器重建要检查什么      → 3 条 [src=memory]
合规要素模型怎么建模    → 3 条 [src=knowledge:新时代装备建设质量管理体系建模规范（1.0版）] [domain=nqms]
```

### 生效条件

插件在网关启动时加载 → 需**成对重启**（`docker stop hermes hermes-webui && docker start hermes hermes-webui`）。
重启后 `restart.sh` 会打印 KB 栈自检（§1.8 已含插件补丁核查）。

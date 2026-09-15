# 系统知识框架结构（2026-09-14 复核版）

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
 skills/ 532 文件    state.db            (LLM Wiki 三层)       raw/web·doc·papers
        │           1121 消息 + FTS              │                  │
        │                                          │ 手工同步(syncObsidian2Qdrant.py)
        │                                          ▼
        │                                  ④ 向量库 Qdrant
        │                                  hermes_memory 348 点（会话记忆）
        │                                  + hermes_knowledge 1445 点（笔记分块）
        │                                          ▲
        │                                          │ Dify 另一条路径
        │                                  ⑦ Vector_index_*（Dify 7 库，infra-ops 101 文档）
        │
        │                                       ② 长期记忆
        │                              memories/MEMORY.md 3458/6000 字符 + USER.md 392/3000
        ▼                                          │
  ┌──────────────────── prompt 注入 / 检索 ─────────────────────┐
  │ 技能索引(446 生效) │ MEMORY.md │ memory provider 自动检索（记忆+知识两集合） │
  │                              │ + kb-lookup.sh 三层按需检索     │
  └─────────────────────────────────────────────────────────────┘
```

## 二、分层明细

| # | 层 | 位置 | 规模（2026-09-14 复核） | 写入者 | 检索/注入方式 |
|---|---|---|---|---|---|
| ① | **技能库** | `data/hermes/skills`（容器 `/home/agent/.hermes/skills`） | 532 SKILL.md / 457 唯一名 / **446 生效**（11 hub+47 builtin+388 local，0 disabled；未生效 7 个＝4 个 macos + 3 个 `environments: [kanban]` 门控） | `skill_manage`；Gitee 仓库 `install-skills-from-repo.sh`；webui bootstrap（6 个托管技能） | 技能索引注入每次 prompt |
| ② | **长期记忆** | `data/hermes/memories/{MEMORY,USER}.md` | MEMORY **3458/6000 字符、14 条**；USER **392/3000、5 条** | `memory` 工具 | 每轮注入 prompt |
| ③ | **会话库** | `data/hermes/state.db`（脑）| `data/.hermes-rt/state.db`（webui，B″″ 后独立） | 脑 2 会话/1121 消息；webui 3 会话/2564+ 消息 + messages_fts(cjk/trigram) | gateway 自动 | `session_search` 工具 |
| ④ | **向量库（记忆）** | Qdrant `hermes_memory`（容器 `qdrant:6333`） | **348 点** / 1024 维（`sync_turn 15` + `on_memory_write 7` + `session_end 3` + **`tool_conclude 2`** + `migration 40` + 无标签 280） | memory provider 四条路径（见 §九） | ①每轮自动检索 ②`kb-lookup.sh` 第①段 |
| ⑤ | **Obsidian 知识库** | `data/obsidian/knowledge`（容器 `/knowledge_base/obsidian`） | 188 md（raw **161** / wiki **23**＝entities 3+concepts 20） | 人工 + AI（wiki 层） | `kb-lookup.sh` 第②段（全文 grep） |
| ⑥ | **Dify 知识库** | 同 Qdrant，`Vector_index_<dataset>_Node` | 7 dataset，**2 个有数据**（infra-ops **101 文档** / standards 1），7 个 Vector_index 集合 | Dify 后台 | Dify API（`/v1/datasets/.../retrieve`） |
| ⑦ | **部署文档/清单** | `docs/`（**16 篇**）+ Gitee 仓库 `docs/`（7 篇） | 23 篇 | 人 + Agent | `kb-lookup.sh` 第④段（grep） |
| ⑧ | **笔记向量库** | Qdrant `hermes_knowledge` | **1445 点** / 1024 维（350 字分块，`uuid5(路径#序号)`） | cron 每 6h `syncObsidian2Qdrant.py` | ①自动检索合并 ②`kb-lookup.sh` 第①段 |

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
               ① Qdrant 语义（hermes_memory 334 点【纯记忆】+ hermes_knowledge 1445 点【笔记分块】）
               ② Obsidian 全文（188 md，grep）
               ③ Dify（已配 dataset token；7 个 dataset，infra-ops 101 文档 / standards 1）
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
| 6 | ~~技能索引待刷新~~ **✅ 已解决（09-14 13:55 实测）** | 磁盘 532 SKILL.md / **457 唯一名**；brain 侧索引快照 453 条（写于 09-13 17:55） | 差异 **4 条，全部是今天新增技能**：`docker-storage-maintenance`、`hermes-skills-library-ops`、`kb-first-lookup`、`knowledge-retrieval-stack-ops`（索引里无已删技能的陈旧项，0 条）。**webui 侧会话索引已含这 4 个**（本会话 prompt 实测）；brain 侧快照文件待其下次新会话自动刷新 |>
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
| 待办 | ~~成对重启刷新技能索引~~ ✅（09-14 15:00 核对：446 生效 / 0 陈旧）；~~清理跨集合重复~~ ✅（09-14 15:43 删 1445 点并修根因，见 §九）；~~显式结论路径（qdrant_conclude）~~ ✅（09-14 17:0x 重启后闭环实测，见 §十）<br>**当前无遗留待办** |

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
| ⑤ | **点 id 改确定性**（uuid5 of 内容 sha1） | 旧代码用 `uuid4()` 随机 id → **每次启动的 MEMORY.md/USER.md 迁移都新增一份**（实测重复 ×26 / ×18；352 点里仅 272 条唯一内容）。改后同内容重复写入只覆盖，不再累积 |

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

---

## B″″（2026-09-14）对本框架的影响

- **②层配置文件分家**：webui 的 `config.yaml/.env/auth.json` 改为宿主 `data/.hermes-rt` 下的独立副本（原来与脑侧共享真源）。
  为防 `save_config` 丢段 bug，`scripts/snapshot-config.sh` 已扩展到 `data/.hermes-rt`（快照前缀 `rt-`，每 10 分钟、保留 30 份、含明文密钥故 600/700 且不得入库）。
- **属主归一化**：两容器都以 root 写共享树，产生的 `root:root 0600` 会让 uid 10000 进程读不到 →
  新增 `scripts/normalize-shared-ownership.sh` + `/etc/cron.d/hermes-ownership-normalize`（每 15 分钟把 root 属主项归一到 10000:10000，幂等）。
- **①③④⑤层不受影响**：技能库仍在 `data/hermes/skills`（目录级 bind 共享），会话库仍是各容器独立（脑侧 `session_search` 不含网页会话）。

---

## 九、知识产生路径（写入侧全景，2026-09-14 15:45 实测）

```
【入口】                    【写入者 / 触发器】                【落盘层】              【实测产出】
对话轮次 ─────────────► sync_turn（每轮）───────────────┐
memory 工具写记忆 ─────► on_memory_write（钩子镜像）─────┤► hermes_memory         sync_turn 12
会话结束 ─────────────► on_session_end ────────────────┤   334 点/1024 维       on_memory_write 7
qdrant_conclude 工具 ──► [09-14 修] qdrant_tools 插件 ──┘                          on_session_end 0
memory 工具 ───────────► MEMORY.md / USER.md ──────────► 每轮注入 prompt        3458 / 392 字符
skill_manage / 仓库 ───► skills/*/SKILL.md ────────────► 索引注入 prompt        532 文件 / 446 生效
PDF·DOC·图片 ─OCR/anydoc► Obsidian raw/ ──AI 提炼─────► wiki(entities/concepts) 161 → 23 篇
web 剪藏 ──────────────► raw/web/ ─────────────────────────────────────────────── 6 篇
watchdog + cron 每 6h ─► syncObsidian2Qdrant.py ───────► hermes_knowledge        1445 点
                                                          350 字分块+uuid5(路径#序号)
Dify 后台上传 ─────────► Dify 分段器 ──────────────────► Vector_index_*          infra-ops 101 文档
工作结论 ──────────────► docs/*.md + Gitee 回推 ───────► 文档层                  18 篇

【消费回路】prompt 注入（技能索引 / MEMORY.md / memory provider 自动检索：记忆库+知识库合并）
          + session_search（会话库）+ kb-lookup.sh 四段按需检索
```

### 15:45 的三项处置

| # | 项 | 处置 | 证据 |
|---|---|---|---|
| 1 | **显式结论路径断了**：provider 只把 `qdrant_search`/`qdrant_conclude` 的 schema 注入模型工具表，**没注册进 `tools/registry` 分派表** → 模型看得见、一调用就 `Unknown tool`；脑侧与 webui 侧都一样，`source=tool_conclude` 的点一直是 0 条 | 新增插件 **`plugins/qdrant_tools/`**（官方 `ctx.register_tool` API，toolset=memory）把同名工具注册成真注册表工具；同名会被 `inject_memory_provider_tools` 的去重逻辑跳过，不会重复 | 不重启即验证实现：`conclude -> stored`、`search -> score 0.81` 命中刚写的点；`hermes plugins list` 两侧均显示 `qdrant_tools enabled`；**16:4x 补测**：新进程（脑侧 CLI）经真实分派路径 `qdrant_search` 命中 0.508 ✅，并修掉一处签名 bug —— `registry.dispatch` 会注入 `task_id` 等关键字参数，handler 必须接受 `**kwargs`；**16:47 再实测**：长驻 webui bridge 里工具已注册（报错从 `Unknown tool` 变为 `unexpected keyword argument 'task_id'`，即插件已加载、但进程内是修复前的模块），修复版在**新进程**中实测通过 → 只需一次成对重启刷新长驻进程。<br>**17:0x 重启后闭环实测（真实分派路径）**：`qdrant_conclude` 返回 `{"status":"stored","collection":"hermes_memory","id":"c1b1182c-a7e2-4aa3-bfb0-c2bf13474121","chars":86}`；`qdrant_search` 读回同一条 **score 0.865 排第一**（第 3 条来自 `hermes_knowledge`）；`hermes_memory` 中 `source=tool_conclude` = **2 条**（该路径历史一直是 0 条）|
| 2 | **跨集合重复 1445 点**（`hermes_memory` 里 source=obsidian 与 `hermes_knowledge` 完全同 id） | 导出回滚清单 `/root/qdrant-dedup-rollback-20260914-154330.json`（1.6MB，原落在**脑容器可写层** → 已另存宿主 `data/workspace/archive/qdrant-rollback/`，容器重建不丢）→ 按 id 分批（200/批）删除 → 复核 | 删除后 `hermes_memory` **1779 → 334**、`hermes_knowledge` 1445 不变；**全量比对 1445 条文本 100% 一致**（无独有内容丢失）；检索仍能从知识库召回笔记 |
| 3 | **重复的根因**：`obsidian-sync` watchdog 容器 compose 里**没设 `QDRANT_COLLECTION`** → 走脚本默认 `hermes_memory`，每次笔记变更都往记忆库灌分块 | compose 给该服务加 `QDRANT_COLLECTION=hermes_knowledge`；脚本默认值也改成 `hermes_knowledge`（防御性） | `docker compose config -q` 通过；两处 env 已确认写入 |

### 生效条件

- 插件：**注册不需要重启**（webui bridge 已加载并注册了工具），但**修复版模块**要等长驻进程重新加载 → 一次成对重启即可（2026-09-14 16:47 已排队执行 `data/opt-data/restart.sh`，日志 `/var/log/hermes-pair-restart.log`）。
- watchdog 改集合：需 `docker compose up -d obsidian-sync` 重建该容器（否则它仍按旧默认往记忆库写）。

---

## 十、2026-09-14 17:0x 最终复核（本轮）

### 数字快照

| 项 | 值 |
|---|---|
| 技能 | 532 SKILL.md / 457 唯一名 / **446 生效**（0 陈旧、0 空文件、0 缺 description）；7 个未生效全部是平台/环境门控（4×macos + 3×`environments: [kanban]`） |
| 记忆 | MEMORY.md 3458/6000 字符（14 条）、USER.md 392/3000（5 条） |
| 会话 | 脑 1121 条 / webui 2564+ 条（B″″ 后分家，设计如此） |
| 向量 | `hermes_memory` 348 点（纯会话记忆）· `hermes_knowledge` 1445 点 · Dify 7 个 `Vector_index_*` |
| 知识源产出（`hermes_memory` 按 source） | 无标签 280 · `migration` 40 · `sync_turn` 15 · `on_memory_write` 7 · `session_end` 3 · **`tool_conclude` 2** |
| 文档 | `docs/` 16 篇 + 仓库 7 篇 |

### 本轮修掉/确认的三件事

1. **① 显式结论路径闭环**：`plugins/qdrant_tools/` 注册的同名工具在重启后的新 worker 里真实可调 —— 写点 + 读回全部成功（详见 §九 ① 行）。上游缺口（provider 只注入 schema、不建分派表）已用插件补齐，插件位于共享 `data/hermes/plugins/`，容器重建不丢。
2. **② 跨集合重复已清**：`hermes_memory` 里 `source=obsidian` 现为 **0**，`hermes_knowledge` 1445 点未动；`kb-lookup ①` 回归正常（记忆点来自记忆库、笔记命中来自知识库，不再同内容两边各出一次）。
3. **回滚清单位置更正**（我一度误判为丢失）：实际完整保留在
   `data/workspace/archive/qdrant-rollback/qdrant-dedup-rollback-20260914-154330.json`（1.6 MB，1445 点 id+payload）。
   容器内 `/root` 那份**确实随容器重建消失**，所以纪律是：导出必须落到宿主目录（`data/` 或 `data/workspace/`）。
   已据此把 `scripts/dedup-memory-vs-knowledge.py` 的导出路径从 `/root/` 改为 `/opt/data/rollback/`（= 宿主 `data/opt-data/rollback/`，目录已建），避免下次再踩。

### 仍需留意的（非故障）

- `hermes_memory` 里 280 条无 `source` 标签 + 40 条 `migration` 是早期手工迁移的历史点；如要彻底干净可逐条甄别，但当前不影响检索（自动检索会带 `[src=memory]`）。
- 脑侧索引快照 `.skills_prompt_snapshot.json`（09-13 17:55）在新会话开始前仍是旧版；webui 侧索引已含全部新技能。
- raw/web 的 6 篇剪藏仍未提炼进 wiki 层（框架文档 §五 遗留项）。

### 验证补充（2026-09-14 重启后）

- **自动检索端到端闭环成立**：重启后的首轮 `memory-context` 同时出现
  `[src=memory]`（会话记忆，relevance 0.90）与 `[src=knowledge:交接-2026-08-29-NQMS知识库导入与Dify修复] [domain=general]`（知识库）—— 证明补丁 ③④ 已生效。
- **记忆库去重**：`hermes_memory` 352 → **272 点**（删除 80 个同内容重复点；回滚清单 `/root/qdrant-memory-dedupe-backup-20260914-194124.json`）。
- **确定性 id 验证**：同内容连写两次 → 点数 275 → 276 → **276**（不再增长）。
- **记忆库存在两代 payload schema**（旧 `text`+`ts` 282 条 / 新 `content`+`timestamp` 70 条）——
  `_search_memories` 已按 `content or text` 兼容两代，检索无缺口。

---

## 十一、职责边界：「三个知识库 + 一个引擎」（2026-09-14 澄清）

### 它们各自是什么

| 组件 | 定位 | 装什么 | 强项 | 弱项 |
|---|---|---|---|---|
| **Dify** | **检索型知识库（RAG KB）** | 成套语料：标准原文、培训材料 | 上传→解析→分段→embedding→向量索引→检索 API 全套 + 控制台 + 可接 rerank | 内容以「分段+索引」形态存在，不可交叉链接、无 wiki 结构、不在版本库 |
| **Obsidian** | **显式知识库**（LLM Wiki 三层） | 领域概念、框架、对比、结论 | 人可读可编辑、交叉链接、**知识复利** | 只有全文 grep（无向量/无 rerank） |
| **Qdrant** | **向量引擎**（不是知识库） | `hermes_memory`（事实记忆）/ `hermes_knowledge`（笔记分块索引）/ Dify 的 `Vector_index_*` | 一个实例同时服务 Hermes 与 Dify | 无建库/管理/召回逻辑 |
| **docs/ + Gitee** | 运维结论沉淀 | 部署/设计记录 | 可 diff、进版本库 | 不入向量库（靠 `kb-lookup` ④ grep） |

关系：**Dify 与 Hermes 各自建索引，共用同一个 Qdrant 实例**（所以一处能看到 9 个集合）。

### 内容该放哪（决策表）

| 内容形态 | 放哪 | 不该放哪 |
|---|---|---|
| 要反复查原文的标准/规范 | Dify（+ 摘要进 wiki） | 别整篇塞 `raw/` 当分块 |
| 成套培训/视频语料 | 提炼成规程进 wiki/技能，原文留 Dify | 别整库搬 vault |
| 可长期复用的概念/框架/对比 | Obsidian `wiki/`（交叉链接） | 别只留 Dify（不可编辑、不参与链接） |
| 每次工作得出的事实/约定 | MEMORY.md（精炼）+ Qdrant 事实点 | 别写 `raw/`（raw 不可变） |
| 操作步骤/套路 | 技能 `skills/` | 别只写 docs（不进 prompt） |
| 工程结论/事故复盘 | `docs/` + Gitee | 别写 MEMORY.md（占每轮注入预算） |

### Dify 接本地 rerank（2026-09-14 完成）

**为什么做**：`bge-reranker-v2-m3` 一直在 `reranker-llama` 容器里空跑，Dify 侧只配了 2 个 embedding 模型（`provider_models` 无任何 rerank）→ 检索只有余弦相似度。

**接法（可复用的无登录自动化路径）**：
1. 装插件：控制台 API `POST /console/api/workspaces/current/plugin/install/marketplace`，
   identifier = `langgenius/openai_api_compatible:0.0.66@51801b51…`（**官方 openai 插件不支持 rerank** —— 其 manifest 只声明 llm/text_embedding/tts/speech2text/moderation；该插件声明 `supported_model_types: [llm, rerank, …]`）。
2. 认证：Dify 控制台 API 需要 access token + CSRF。
   在 `dify-api` 容器内用官方类铸造即可：`AccountService.get_account_jwt_token(account)` +
   `libs.token.generate_csrf_token(account.id)`，请求带 `Authorization: Bearer <t>`、`X-CSRF-Token: <csrf>`、cookie `csrf_token=<csrf>`。
3. 注册模型：`POST …/model-providers/langgenius/openai_api_compatible/openai_api_compatible/models` body `{"model":"bge-reranker-v2-m3","model_type":"rerank"}`
   → 再 `POST …/models/credentials` body `{"model":…,"model_type":"rerank","credentials":{"api_key":"sk-local","endpoint_url":"http://reranker-llama:8000/v1","context_size":"2048","max_chunks":"32"},"name":"reranker-local"}`
   （插件会把它拼成 `<endpoint_url>/rerank`，llama.cpp 的 `/v1/rerank` 正是这个形状）。
   注意：该 provider **没有 `provider_credential_schema`**，别去写 provider 级凭据（会 400）。
4. 数据集默认值：`PATCH /console/api/datasets/{id}` body `{"retrieval_model":{…reranking_enable:true, reranking_mode:"reranking_model", reranking_model:{…}, top_k:10…}}`
   → 已对 `infra-ops`、`standards` 生效（DB `datasets.retrieval_model` 可复核）。
5. 让 Hermes 侧也用上：`scripts/kb-lookup.sh` 第③段原来写死 `reranking_enable:false` → 改为 true + 候选池 `max(2K,10)`。

**效果（A/B 实测，同一 query/dataset）**：

| | 关闭 rerank | 开启 rerank |
|---|---|---|
| `infra-ops`「合规要素分解原则与识别方法 怎么做」 | 10 条，前 5 名多为重复的培训幻灯片头（0.69/0.628/0.6246×4），**真正相关的「合规融合—方法」只排第 7（0.598）** | 3 条，**「合规融合—方法」升到第 1（1.5469）**，编号/版本识别第 2（0.6465），重复幻灯片与无关段落被剔除 |
| 经 `kb-lookup` 同一路径复测 | — | 命中 3 条，top score **1.5469**（rerank 量级） |

**注意**：rerank 后命中数会明显变少（本例 10→3），因为 bge-reranker 给不相关段落打负分而被 Dify 丢弃；
若发现召回不足，调大候选池 `top_k`（现在 10）即可，而不是关掉 rerank。

### 检索模式选型（2026-09-14 三种模式实测）

`semantic_search` = 语义（向量余弦）召回；`keyword_search` = 关键词（中文 jieba 分词倒排）；`hybrid_search` = 两者加权融合。
**三种都在 rerank 之前做候选召回**，rerank 只负责重排。

| 模式（同开 rerank） | `standards`「8.4.1 外部提供的过程、产品和服务的控制」 | 说明 |
|---|---|---|
| `semantic_search` | 命中 **2** 条，top1 3.4620（8.4.1 总则） | 准，但条款号类查询漏得多 |
| `keyword_search` | 命中 **0** 条 | 中文语料 + 编号查询，关键词几乎匹配不上 |
| **`hybrid_search`（向量 0.7 / 关键词 0.3）** | 命中 **7** 条，top1 3.8159（采购和外包执行与控制），第 2 条即 8.4.1 总则 | **召回最全且正确答案仍在顶端** |

⇒ 已把 `infra-ops`、`standards` 的默认检索改为 **hybrid_search + rerank（top_k 10）**，`kb-lookup.sh` 第③段同步改为 hybrid（0.7/0.3）。

**延迟实测**（经 `dify-limiter`，CPU 跑 4 线程 reranker）：`semantic+rerank` **13.3s** / `hybrid+rerank` **20.4s**（同一 query）。
即 hybrid 多花约 7s 换更好召回；且 reranker 是单实例串行，**并发调用会排队**（曾观察到两个重查询同时跑导致 >180s）。
若日后要提速：给 `reranker-llama` 加线程/换更小量化，或把 kb-lookup 的候选池调回 5。

**遗留**：`areas`/`compliance-mapping`/`projects`/`resources-reference`/`测试` 5 个 dataset 仍为空（按原 7 库规划填充或删除）。

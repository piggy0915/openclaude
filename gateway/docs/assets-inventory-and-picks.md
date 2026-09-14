# 资产盘点与选型报告（技能 / 插件 / MCP）

> 2026-09-13。扫描范围：live 技能目录、`plugins/`、`config.yaml` 的 `mcp_servers`、`.env`。安装 Tier1 后技能数 **456**。

## 一、全景（硬数据，来自 `hermes prompt-size` / `skills|plugins|mcp list`）

| 资产 | 数量 | 状态 |
|---|---|---|
| 技能（SKILL.md 文件） | **456** | 索引内约 **445** 个条目（含少量重复名） |
| 已启用插件 | **4** / 共 59（58 bundled + 1 user） | 全部与本部署对口，见 §四 |
| MCP 服务器 | **6** | ✅ 全部 `enabled`，本轮 0 连接异常 |

### ⚠️ 最重要的成本数字：技能索引占系统提示词的 77%

```
System prompt total :   81,398 B  (79.5 KB, 59,262 chars)
  ├─ skills index   :   62,891 B  (61.4 KB)   ← 77%
  ├─ memory         :    5,678 B
  └─ user profile   :        0 B
Tool schemas        :   41,181 B  (40.2 KB, 27 tools)
```

- 技能索引约 **62.9 KB ≈ 1.5 万 tokens**，**每次请求都要带上**（工具 schema 另计 41 KB）。
- 所以"整理技能"不是审美问题，是**每次调用都在付费**：归档 50 个技能 ≈ 省 5–7 KB ≈ 1.5k tokens/次。
- 反过来：`*-perspective` 那 19 个人物视角合计才 387 字符（约 100 tokens），**为省 token 动它没有意义** —— 该动的是顶层那 100 个（占索引 31%）。

**MCP 清单**（`config.yaml`）：
| 名称 | 作用 | 进程 |
|---|---|---|
| `ekko-studio-api` | Ekko Studio 平台 API（会话/模型/配置） | ✅ |
| `ekko-studio-browser` | 浏览器操作（统一 agent-browser 0.37.1） | ✅ |
| `ekko-studio-devices` | 局域网/远程设备发现与调用 | ✅ |
| `ekko-studio-use` | 高层操作（含手机定位/日历/提醒/健康，需现场授权） | ✅ |
| `ssh_remote` | 远程 shell（`~/.hermes/mcp/ssh_remote.py`） | ✅ |
| `video-transcriber` | 视频/播客转录与摘要 | ✅ |

---

## 二、技能分类地图（49 类 → 6 大域）

| 域 | 分类（数量） | 合计 |
|---|---|---|
| **A 平台与运维** | devops 25、autonomous-ai-agents 13、hermes 2、hermes-webui 1、mcp 1、software-development 22 | 64 |
| **B 知识与文档** | research 18、note-taking 5、document-processing 6、productivity 35、mlops 12+3+2+2+1 | 84 |
| **C 质量与合规** | quality-management 10、security 5、enterprise-architecture 1、consulting 1、legal 2、hr 2、finance 6、supply-chain 5 | 32 |
| **D 内容与传播** | marketing 18、creative 23、media 7、social-media 2、email 2、diagramming 3 | 55 |
| **E 开发与工程** | engineering 25、github 6、testing 7、design 5、data-science 1 | 44 |
| **F 通用与其它** | (顶层) 100、specialized 25、company 7、support 4、product 4、project-management 3、academic 1、apple 4、game 2、smart-home 1、red-teaming 1、mattpocock 4、nuwa/examples 15、web 1、core 5 | 177 |

> **最大单体是「(顶层) 100 个」= 索引字符的 31%** —— 瘦身要优先动这里，而不是那些小分类（`nuwa/examples` 15 个加起来才 387 字符，动它几乎没收益）。

---

## 三、最合适技能（按你的业务流打分取头部）

| 业务流 | 首推（按契合度） |
|---|---|
| **① Hermes 自托管运维** | `docker-infrastructure`、`dify-docker-stack`、`hermes-container-deployment`、`hermes-webui`、`hermes-system-diagnostics`、`hermes-config-troubleshooting`、`hermes-s6-container-supervision`、`ai-video-transcriber` |
| **② 知识管理与检索** | `knowledge-base-management`、`knowledge-base-sync`、`knowledge-base-pipeline`、`obsidian-qdrant-pipeline`、`hermes-qdrant-memory-provider`、`batch-doc-knowledge-extraction`、`hermes-memory-extension` |
| **③ 文档与办公** | `specialized-document-generator`、`docx`、`pptx`、`xlsx`、`pdf`、`officecli`、`scanned-chinese-document-extraction`、`document-processing`、`chinese-financial-document-ocr`、`chinese-documentation` |
| **④ 质量/合规/审计** | `nqms-*` 系列（equipment-architecture、kpi、clause-training…）、`internal-compliance-decomposition`、`program-file-decomposition`、`specialized-risk-assessor`、`legal-contract-reviewer`、`security-compliance-auditor` |
| **⑤ 内容与营销** | `marketing-douyin-strategist`、`marketing-xiaohongshu-operator`、`marketing-weixin-channels-strategist`、`marketing-livestream-commerce-coach`、`marketing-bilibili-strategist`、`shortdrama-analyst`、`design-video-prompt-engineer` |
| **⑥ 会议与协作** | `specialized-meeting-assistant`、`meeting-action-items`、`project-management-meeting-notes-specialist`、`engineering-dingtalk-integration-developer`、`engineering-feishu-integration-developer` |
| **⑦ 数据与报表** | `finance-fpa-analyst`、`finance-financial-analyst`、`finance-financial-forecaster`、`support-analytics-reporter`、`supply-chain-inventory-forecaster`、`personal-finance-management`、`drawio-diagram-from-table` |
| **⑧ 学习与考试** | `academic-study-planner`、`gaokao-college-advisor`、`study-abroad-advisor`、`corporate-training-designer` |
| **⑨ 开发与代码** | `engineering-code-reviewer`、`engineering-backend-architect`、`security-architect`、`engineering-security-engineer`、`github-code-review`、`openclaude-executor` |
| **⑩ 多媒体** | `design-video-prompt-engineer`、`design-image-prompt-engineer`、`siliconflow-image-gen`、`comfyui`、`marketing-short-video-editing-coach`、`bilibili-video-extraction` |

---

## 四、插件：共 59 个，启用 4 个（都选对了）+ qdrant 状态更新

| 已启用插件 | 版本 | 作用 | 评价 |
|---|---|---|---|
| `disk-cleanup` | 2.0.0 | 自动跟踪并清理临时文件 | ✅ 与你的磁盘治理直接相关 |
| `web-searxng` | 1.0.0 | 自建 SearXNG 搜索 | ✅ 正是本机已部署的那套 |
| `web-tavily` | 1.0.0 | Tavily 搜索/抽取 | ✅ 已有 TAVILY key |
| `qdrant` | 1.0.0 | Qdrant 语义记忆 provider（唯一 user 插件） | ⚠️ 见下 |

**另外 55 个 bundled 插件未启用**（58 个 bundled 里只启用了 3 个）。与本部署有关的候选：
`browser-firecrawl`、`web-firecrawl`（网页抓取，需 key/额度）、`browser-browser-use`、`browser-browserbase`（云端浏览器，需付费额度）、`chronos`（NAS 中介的托管 cron，本机自托管不需要）、`meta-ai-image-gen`（生图后端）。
→ **结论：现有 4 个组合已经是最合适的**；除"生图/抓取额度"确有需求外，不建议再启用。

### qdrant provider 状态更新（2026-09-13 重启后复核）

| 项 | 之前 | 现在 |
|---|---|---|
| 报错 | `[SSL: WRONG_VERSION_NUMBER]` 初始化失败（2 次，均在 09-12） | **本次重启后 0 次新增** |
| 客户端构造 | 失败 | **成功**：`QdrantClient(host="qdrant", port=6333, api_key=..., https=False, timeout=30)` |
| 剩余问题 | — | ① `UserWarning: Api key is used with an insecure connection` ② `api_key` 值仍是 **`sk-yxY…`（SiliconFlow 模型 key，放错了）** |

**根因确认**：`.env` 的 CRLF 问题（值尾带 `\r`）**已被你修掉**（现 0 个 CR，mtime 09-13 16:07）→ 这很可能就是 SSL 报错消失的原因。

**建议的最后一步（可选，消除噪声与隐患）**：本地 Qdrant 未启用鉴权，因此
- `config.yaml: memory.vector_db.api_key` → 清空
- `.env: QDRANT_API_KEY` → 删除或留空

这样 `UserWarning` 消失，也不会让一个模型平台的 key 在各个服务之间流转。

## 五、整理建议（按收益排序）

| # | 动作 | 收益 |
|---|---|---|
| 1 | **修 qdrant provider**（§四） | 语义记忆这件"最该有的能力"从坏到好 |
| 2 | **顶层 100 个技能分类归档**：把散落在顶层的技能收进所属分类（如 `chinese-*`→`document-processing`、`*-perspective`→`persona/`） | 索引结构清晰；便于批量停用（顶层占索引 31%） |
| 3 | **合并真重复**：`marketing-china-ecommerce-operator` ↔ `marketing-ecommerce-operator`；`knowledge-base-management`/`-sync`/`-vector-sync`/`-pipeline`/`obsidian-qdrant-pipeline`/`hermes-memory-extension`/`hermes-qdrant-memory-provider`（7 个讲同一件事） | 减少"选错技能"，省索引 |
| 4 | **归档确实用不上的分类**：`apple`(4)、`gaming`(2)、`smart-home`(1)、`red-teaming`(1)、`mattpocock`(4)、`mlops/models`(2)、`data-science`(1) | 字符收益小（合计 <1.5k），但选择更干净 |
| 5 | **19 个 `*-perspective` 人物视角**（含 nuwa/examples 15 个） | 索引成本极低（387 字符），**不建议为省 token 动它**；真不用再谈归档 |
| 6 | **可选补装**：Tier2 的 39 个（知乎/AEO/AI citation/多平台发布…） | 按需；先跑一段 Tier1 再定 |

## 六、执行记录（2026-09-13 晚）

### ✅ 任务1：清空放错的 qdrant api_key
- `config.yaml`：`memory.vector_db.api_key` → 整行移除（注释说明）
- `.env`：`QDRANT_API_KEY=sk-…` → 注释掉
- 备份：两份 `.bak-20260913-175020`
- 依据：`plugin.yaml` 的 `requires_env` 不含 `QDRANT_API_KEY`；本地 Qdrant 未启鉴权 → 移除即可消除 `UserWarning: Api key is used with an insecure connection`
- ⏳ 需重启后复核警告是否消失

### ✅ 任务2：顶层技能归位
| 项 | 结果 |
|---|---|
| 起始顶层技能目录 | 86 个 |
| 归位（按业务归类） | **75 个**（新建 `persona/` 收纳 20 个人物视角） |
| 顶层重复副本归档 | 3 个（`apikey-image-gen`/`grok-image-to-video`/`minimax-image-to-video`，分类下已有副本） |
| **剩余顶层** | **8 个**（`document-processing`、`mcp`、`nuwa`、`huashu-nuwa`、`emotion_pd_Skill_V2.1`、`hyperframes`、`markdown-viewer`、`remotion`） |
| 未动（受保护） | webui 托管 6 个、bundled 52 个 |
| 索引收益（实测） | 系统提示 81,398 B → **79,315 B**；技能索引 62,891 B → **60,808 B**（省 ≈2 KB ≈ 500 tokens/次） |
| 回滚 | `data/hermes/skills-archived/ROLLBACK.json`（78 条映射） |

归位映射：`persona`(20 视角)、`autonomous-ai-agents`(4 AgentChat)、`document-processing`(13)、`software-development`(22)、`mcp`(1)、`hermes`(6)、`creative`(5)、`research`(1)、`finance`(1)、`productivity`(2)。

> `mcp` 与目标分类同名，不能移进自身 → 留在顶层。

### ✅ 任务3：知识库类重复技能 —— **实际无需合并**
用 `hermes skills inspect` 逐个核验（权威）：
```
Error: No skill named 'knowledge-base-sync' found in any source.
Error: No skill named 'obsidian-qdrant-pipeline' found in any source.
Error: No skill named 'hermes-qdrant-memory-provider' found in any source.
```
- live 里**只有 `research/knowledge-base-management` 一个**；另 6 个名字（`knowledge-base-sync`/`-vector-sync`/`-pipeline`/`obsidian-qdrant-pipeline`/`hermes-memory-extension`/`hermes-qdrant-memory-provider`）**只存在于 Gitee 仓库，本地从未安装**。
- 它们仍出现在技能清单里 → 属于**索引残留条目**（`inspect` 已找不到）。重启后应自然消失，届时应复核技能条目数与磁盘 453 是否一致。

## 七、待办

- [ ] **成对重启**验证：① qdrant `UserWarning` 消失 ② 索引条目数与磁盘一致（453）
- [ ] 若重启后索引仍含已不存在的技能名 → 清理索引缓存（`.hub/index-cache`、`/opt/hermes/skills/index-cache`）
- [ ] （可选）从仓库安装被归档的 3 个重复技能之一？不需要 —— 分类下已有副本
- [ ] （可选）Tier 2 的 39 个技能
- [ ] 每次重建后跑 `scripts/after-rebuild-cleanup.sh`

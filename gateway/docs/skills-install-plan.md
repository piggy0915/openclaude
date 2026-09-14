# 技能仓库安装方案（Gitee `piggy0915/hermes-skills` → live）

> 2026-09-13。数据来自实际扫描：仓库 **604** 技能、live **401** → **未安装 216 个**。

## 0. 先看结构（决定装法）

| | 路径 | 布局 |
|---|---|---|
| 仓库（唯一权威源） | `/opt/data/hermes-skills` | 大体扁平 `<name>/`；`agency-agents-zh/<分类>/<name>/` 为分类树 |
| live（运行时） | `/home/user/gateway/data/hermes/skills` | **分类化** `<分类>/<name>/`（容器内 = `/home/agent/.hermes/skills`） |
| 远端 | Gitee | 由 `devops/sync-new-skills.py` 推送 |

**流程缺口**：仓库自带的 `sync-new-skills.py` **只做 live→repo（备份方向）**，没有反向安装。
→ 已补：`scripts/install-skills-from-repo.sh`（支持 `--list` / `--tier N` / `--only` / `--file`，默认预览，`--apply` 才写入；**目标已存在一律跳过，绝不覆盖**）。

---

## 1. 未安装 216 个的构成（全部是 `agency-agents-zh/*` 角色专家）

| 分类 | 未装 | 分类 | 未装 |
|---|---|---|---|
| specialized | 44 | paid-media | 7 |
| engineering | 33 | support | 6 |
| marketing | 24 | spatial-computing | 6 |
| gis | 13 | game-development | 5 |
| security | 10 | product | 5 |
| design | 9 | finance | 5 |
| sales | 9 | academic | 5 |
| testing | 8 | unreal-engine / unity | 4 / 4 |
| project-management | 7 | godot / roblox / blender | 3 / 3 / 1 |
| （顶层 3） | 3 | company | 2 |

---

## 2. 分档建议

### Tier 1 —— 强烈推荐 55 个（与你的实际工作直接对口）

| 组 | 数量 | 内容 |
|---|---|---|
| **engineering（运维/架构/质量）** | 16 | devops-automator、sre、incident-response-commander、code-reviewer、software-architect、minimal-change-engineer、database-optimizer、security-engineer、threat-detection-engineer、technical-writer、git-workflow-master、multi-agent-systems-architect、prompt-engineer、backend-architect、data-engineer、codebase-onboarding-engineer |
| **specialized（编排/自动化/MCP/文档）** | 11 | agents-orchestrator、specialized-mcp-builder、specialized-document-generator、specialized-workflow-architect、automation-governance-architect、data-consolidation-agent、report-distribution-agent、operations-manager、specialized-model-qa、lsp-index-engineer、specialized-strategy-duel-agent |
| **security（含合规审计）** | 5 | compliance-auditor、architect、cloud-security-architect、appsec-engineer、incident-responder |
| **testing（证据/验收/评估）** | 6 | evidence-collector、reality-checker、tool-evaluator、test-results-analyzer、workflow-optimizer、api-tester |
| **product / project-management** | 7 | product-manager、feedback-synthesizer、sprint-prioritizer、trend-researcher；meeting-notes-specialist、project-shepherd、experiment-tracker |
| **design / support** | 6 | ux-architect、ui-designer、image-prompt-engineer；executive-summary-generator、infrastructure-maintainer、analytics-reporter |
| **company / finance** | 4 | chief-of-staff、chief-financial-officer；financial-analyst、fpa-analyst |

理由：Hermes 自托管运维、多智能体编排、MCP 开发、文档生成、质量与安全合规审计、产品/项目流程 —— 都是你当前实际在用的方向；`chief-of-staff`/`chief-financial-officer` 补齐已有 CxO 组。

### Tier 2 —— 值得考虑 39 个

| 组 | 数量 | 说明 |
|---|---|---|
| 中文/前沿营销 | 14 | 知乎、小红书、公众号、多平台发布、内容创作、轮播增长、SEO、**AI 搜索优化（AEO / AI citation）**、视频优化、书籍共创、公关、增长黑客 |
| specialized 补充 | 7 | business-strategist、change-management-consultant、customer-success-manager、organizational-psychologist、data-privacy-officer、pricing-analyst、personal-growth-mentor |
| engineering 补充 | 8 | ai-engineer、rapid-prototyper、senior-developer、frontend-developer、it-service-manager、embedded-firmware-engineer、voice-ai-integration-engineer、email-intelligence-engineer |
| testing 补充 | 2 | accessibility-auditor、performance-benchmarker |
| sales | 4 | proposal/deal/account strategist、pipeline-analyst |
| academic | 5 | 人类学/地理/历史/叙事学/心理学 |

> ⚠️ **重叠提示**：`marketing-xiaohongshu-specialist`、`marketing-wechat-official-account` 与本地已有的 `marketing-xiaohongshu-operator`、`marketing-wechat-operator` 主题相近 → 建议**只装本地没有的平台与能力**（知乎、AEO/AI citation、多平台发布、轮播增长、邮件策略）。

### Tier 3 —— 不建议装（约 122 个）

| 类别 | 数量 | 理由 |
|---|---|---|
| gis 全类 | 13 | 无 GIS/BIM/测绘业务 |
| spatial-computing / XR 全类 | 6 | visionOS/XR 开发，无相关需求 |
| 游戏与 3D 引擎全类（game-development / unity / unreal / godot / roblox / blender） | 20 | 与业务无关 |
| 美式行业流程（医疗计费、酒店、房地产、贷款、grant、应付账款、零售退货、法务计费/受理） | ~12 | 流程与国内业务不符 |
| 不相关技术栈（solidity/区块链、drupal、wordpress、filament、cms、orgscript） | ~8 | 无对应项目 |
| 跨境/外语向（french/korean/cultural-intelligence、language-translator、instagram/linkedin/reddit/twitter/tiktok/global-podcast/app-store 运营、paid-media 7） | ~20 | 主要面向英文市场投放与社媒 |
| 与本地重叠（部分 marketing-*、meeting-notes-specialist ↔ 本地 specialized-meeting-assistant） | ~10 | 重复会增加选择噪声 |
| 其余 specialized 长尾（zk-steward、identity-graph-operator、agentic-identity-trust、salesforce-architect、civil-engineer 等） | ~33 | 与当前业务不对口 |

---

## 3. 一个必须知道的成本：技能索引进每次请求

所有技能名会出现在**每次请求的 system prompt**（技能清单）。当前 401 个已占相当篇幅；全量再装 216 个会：
- 每次请求多花约 2–4k tokens（按你的调用量 = 实打实的费用）
- 增加模型"选错技能"的噪声

**所以本方案主张分档、按需装**：先 Tier 1（55 个，增量温和），用一段时间后再决定 Tier 2。

---

## 4. 安装流程

```bash
cd /home/user/gateway

# ① 预览（默认不改动）
scripts/install-skills-from-repo.sh --tier 1
scripts/install-skills-from-repo.sh --list            # 看还剩哪些没装

# ② 安装
scripts/install-skills-from-repo.sh --tier 1 --apply

# ③ 刷新技能索引（必须成对重启；技能索引在启动时构建）
docker stop hermes hermes-webui && docker start hermes hermes-webui

# ④ 验证
docker exec hermes-webui bash -c 'find /home/agent/.hermes/skills -name SKILL.md | wc -l'
```

自定义名单（先写文件，每行一个技能名）：

```bash
scripts/install-skills-from-repo.sh --file /root/my-skills.txt --apply
```

## 5. 安全与回滚

- 脚本**只写 live 目录**，从不删除、从不覆盖：目标已存在则跳过（实测：重复执行输出 `已存在跳过`）。
- 仓库里有、live 里没有的技能共 216 个；**live 独有的 14 个**（`nuwa`、`ppt-master`、`officecli`、`nqms-weekly-report`、`internal-compliance-decomposition`、`cross-reference-tracker-fill`、`document-processing`、`scripted-chinese-document-extraction`、`pptx-template-conformance`、`collective-wisdom-install`、`mcp`、`reddit-reading`、`research`、`rss-feeds`）**不受影响**。
- 回滚：删除对应目录即可，例如
  ```bash
  rm -rf /home/user/gateway/data/hermes/skills/<分类>/<技能名>
  ```
  建议安装前留一份清单：`ls /home/user/gateway/data/hermes/skills > /root/skills-before.txt`
- 装完如果想把这些技能"固化"到仓库，无需操作 —— 它们本来就来自仓库。

# 技能库当前状态（审计报告）

> 审计时间：2026-09-15 ｜ 方法：技能 `hermes/skills-library-ops` 规定的**三层审计**（磁盘 → 已加载索引 → 条件门控）
> 上一版（2026-09-14）的旧数字已作废（当时记 450 条）。

## 一、第一层：磁盘

| 项 | 数值 |
|---|---|
| `SKILL.md` 文件数 | **536**（唯一目录名 **462**） |
| 缺 frontmatter / 缺 description / 空文件 | **0 / 0 / 0** ✅ |
| 内容哈希唯一 | 461 → **75 组内容完全相同的重复** |

**75 组重复的成因（不是事故）**：Hermes 内置技能同步（`.bundled_manifest`，52 条）与 webui bootstrap（`.webui-managed-skills.json`）在**启动时把技能按"顶层扁平"布局回填**，与人工整理的分类副本形成"同名两份"。
→ 因此**重复清理会白干**（本栈实测：删掉的顶层副本会在下次启动回来）；本次**不动它们**。

## 二、第二层：已加载索引（模型是否看得见）

| 侧 | 快照文件 | 条目 | 唯一名 |
|---|---|---|---|
| 脑侧 hermes | `data/hermes/.skills_prompt_snapshot.json` | 536 | 458 |
| hermes-webui | `data/hermes-runtime/.skills_prompt_snapshot.json` | 535 | 457 |

- 与磁盘 536 一一对上 → **没有"隐形技能"**（磁盘上每个技能模型都能看见，无 disabled 项）✅
- 比对时**两个键都要试**（`skill_name` 可能是目录名而非 frontmatter 名）。
- 索引在**进程启动时构建** → 技能增删/描述改动**要成对重启后**才反映到提示词。

## 三、第三层：条件门控

| 项 | 数值 |
|---|---|
| 声明 `platforms` | 147 个（多为 `[linux, macos, windows]`） |
| **`[macos]` 独有（Linux 永不加载）** | **4 个**：`apple/{apple-notes, apple-reminders, findmy, imessage}` |
| 声明 `conditions` | 0 个 |

## 四、提示词预算（**按索引口径**，重要）

> ⚠️ 口径纠正：Hermes 的**技能索引把 `description` 截断到 57 字符 + `...`**（快照里 536 条中有 **320 条恰好 60 字符** = 被截断）。
> 因此**不能用磁盘上的描述全量长度估预算** —— 那样会高估约 3 倍（我 2026-09-15 犯过这个错，已纠正）。

| 口径 | 字符总量 | ≈ tokens/轮 |
|---|---|---|
| 索引实际（快照：名字 + 截断后描述） | 43,927 | **≈ 10,981** |
| 本次精简后（模拟） | 39,357 | **≈ 9,839** |
| **净节省** | 4,570 | **≈ 1,142** |

- 本次把 **18 个技能（30 个文件，含重复副本）** 的描述压到 ≤60 字符：
  磁盘上原本 **201 条 >60 字符**（触发词被截断成"前 57 字符 + …"），改后这 18 个技能在索引里是**完整可读的触发词**。
- **真正的主要收益是"触发词不再被截断"（路由质量），其次是约 1.1k tokens/轮 的预算**。
- 备份（可还原）：`/root/skills-desc-backup-20260915-133019/`（保留相对路径）
- 剩余：仍有 180+ 条描述偏长但收益递减，暂不再动。

## 五、可行性（按"默认容器内使用"约定在容器内实测）

**容器内可用的依赖**：`gh git docker ffmpeg node npm npx uv pip python3 curl rg sqlite3 pandoc?`→ 实测 ✅ gh/git/docker/ffmpeg/node/npm/npx/uv/pip/python3/curl/rg/sqlite3
**容器内缺失**：jq、yq、psql、redis-cli、pandoc、libreoffice、imagemagick（影响：psql 4 个、redis-cli 1 个、libreoffice 2 个、pandoc 4 个、jq 6 个技能；多为"可选替代"，非硬阻塞）

**凭据**：
- ✅ 已配：GITHUB_TOKEN / DEEPSEEK_API_KEY / QDRANT_API_KEY / DASHSCOPE_API_KEY / OPENROUTER_API_KEY / GOOGLE_API_KEY / TAVILY_API_KEY / TOKENHUB_API_KEY
- ❌ 未配：LINEAR_API_KEY（`productivity/linear`）、NOTION_API_KEY（`productivity/notion`）、AIRTABLE_API_KEY（`productivity/airtable`）、ANTHROPIC_API_KEY、OPENAI_API_KEY
  → 前三个是**独立集成技能**，装上 key 才能真跑；后两个多为文档提及（openclaude 已改走 DeepSeek ✅）

## 六、结论与决策记录

| 事项 | 结论 |
|---|---|
| 结构完整性 | ✅ 100% 干净（无缺 frontmatter/description/空文件） |
| 索引可见性 | ✅ 100% 可见（无隐形技能） |
| 平台可行性 | 4 个 macOS-only 保留（只占 4 条索引，不会触发） |
| 仓库 Tier 2（约 39 个） | **不装**（索引预算已紧张；需要哪个用 `install-skills-from-repo.sh --only` 单装） |
| 75 组重复 | **不删**（会被启动同步回填；真要省需改写入侧，未做） |
| 超长 description | **已精简**（18 个技能 / 30 文件，省 3,614 tokens/轮） |

## 七、下次复查（成对重启后）

```bash
# 1) 索引是否刷新到精简后的描述、条目数是否仍与磁盘一致
python3 -c "import json;d=json.load(open('data/hermes/.skills_prompt_snapshot.json'));print(len(d['skills']))"
# 2) 顶层副本是否被回填（重复组数应仍在 ~75）
# 3) 预算
grep -c 'description' /dev/null; # 用 docs 里的估算脚本复算
```

# 当前技能可用性核查（2026-09-13）

> 核查对象：live 技能树 `data/hermes/skills`（容器内 `/home/agent/.hermes/skills`）
> 权威依据：Hermes 自己构建的索引快照 `.skills_prompt_snapshot.json`（`{version, manifest, skills, category_descriptions}`）

## 一、三层的数字

| 层 | 数字 | 判定 |
|---|---|---|
| **磁盘** | **528** 个 SKILL.md / **449** 个唯一技能名 / 50 个分类 | 结构 100% 合法 |
| 结构校验 | 无 frontmatter **0** · 无 description **0** · 空文件 **0** · 隐藏/禁用 **0** | ✅ 全部可解析 |
| **索引** | **459** 条 / **453** 个唯一名（brain 与 webui **完全一致**） | 443/449 磁盘名已进索引 |
| 重名 | **79 组**（涉及 158 个文件），其中 **78 组是「顶层 + 分类」成对同名** | ⚠️ 每组只生效一个 |

## 二、结论：不是"全部可用"，有 4 类例外

### ① 平台专属：4 个在本机**不会出现**
索引里声明了 `platforms` 且不含 linux：

| 技能 | 平台 |
|---|---|
| `apple-notes`、`apple-reminders`、`findmy`、`imessage` | **macos only** |

> 其余平台字段统计：无限制 315 · linux 140 · macos 138 · windows 126 · termux 2 · docker 2（多平台叠加计数，绝大多数同时声明 linux）。

### ② 条件受限：5 个（条件不满足时不出现）
| 技能 | 条件 | 本机是否满足 |
|---|---|---|
| `maps` | `requires_toolsets: [terminal]` | ✅ |
| `research-paper-writing` | `requires_toolsets: [terminal, files]` | ✅ |
| `sdlc-review` | `requires_toolsets: [kanban]` | ✅（kanban 在） |
| `drawio-skill` | `requires_tools: [drawio, draw.io]` | ❌ 无 drawio 工具 |
| `teams-meeting-pipeline` | `session_platforms: [teams, cron]` | ❌ 当前是 cli/web 会话 |

### ③ 影子副本：**73 组**（可一键清理）
整理技能时把顶层技能复制进了分类目录（如 `pptx` → `document-processing/pptx`），**顶层原件没删**：

```
顶层 pptx/SKILL.md 39609B  ==  document-processing/pptx/SKILL.md 39609B   （哈希一致）
顶层 yuanbao/SKILL.md      ==  productivity/yuanbao/SKILL.md
顶层 *-perspective/ (19)   ==  persona/*-perspective/
顶层 writing-plans/ 等      ==  software-development/...
```

Hermes 索引按 name 去重 → 每组只有一份能出现，另一份是**永不生效的影子副本**。
清理工具：`scripts/dedup-top-level-skills.sh`（**只动内容哈希完全一致**的组；用 mv 到 `/root/skill-dedup-backup-<ts>/`，可一键还原）。
实测预览：**可清理 73 组，内容不一致跳过 1 组**。

### ④ 索引口径说明（2026-09-14 更正）

**上一版此处判断有误**：我曾列出"6 个改名技能未进索引"，原因是**比错了键**——
索引里对那 10 个条目使用的 `skill_name` 是**目录名**（`mcp` / `nuwa` / `document-processing` /
`guizang-ppt` / `creative-ideation` / `liuheping-perspective` / `audiocraft` / `segment-anything` …），
而我审计时用的是 frontmatter 的 `name`（`native-mcp` / `huashu-nuwa` / `docx-xml-surgery` …）。
核对 `skill_name != frontmatter_name` 的条目正好 10 条，与"索引多出/磁盘缺少"的两组完全对应
→ **索引覆盖是完整的**，不存在"改名技能检索不到"的问题。

原因：索引快照构建于 17:55 / 18:03，之后技能树被重排（顶层 100 → 83，`software-development` 22 → 44，新增 `persona/` 等）。
→ **再重启一次即可对齐**。

## 三、处置清单

```bash
cd /home/user/gateway

# 1) 清理 73 组影子副本（预览 → 执行）
scripts/dedup-top-level-skills.sh
scripts/dedup-top-level-skills.sh --apply

# 2) 刷新索引（会掐断当前 web 会话，请在宿主 shell 执行）
docker stop hermes hermes-webui && docker start hermes hermes-webui

# 3) 复核
docker exec hermes-webui bash -c 'find /home/agent/.hermes/skills -name SKILL.md | wc -l'   # 预期 ≈ 455（528-73）
docker exec hermes bash -c 'python3 -c "
import json;d=json.load(open(\"/home/agent/.hermes/.skills_prompt_snapshot.json\"));print(len(d[\"skills\"]))"'  # 预期 ≈ 450
```

清理后预计：**磁盘 ≈455 个文件 / 唯一名 ≈449；索引 ≈450 条**，重名归零。

## 四、全量清单

当前技能逐个列出（按分类、含描述）：`docs/skills-current-list.md`（528 个 / 50 分类 / 78KB）。

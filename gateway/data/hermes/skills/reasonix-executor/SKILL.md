---
name: reasonix-executor
description: 调用 Reasonix CLI 执行大规模代码任务。Reasonix 是 DeepSeek 原生 Agent 框架，针对缓存命中率和低成本深度优化，特别适合长上下文、高 token 量的代码任务（文件 >2000 行或项目级分析），成本极低。触发词：「用 reasonix」「调 reasonix」「调用 reasonix」「让 reasonix 写」「大文件重构」「项目级分析」「批量代码生成」「大规模重构」「长上下文代码」「超长文件」「reasonix run」「reasonix code」。当任务文件大、成本敏感或需要 commit 消息生成时优先使用。
related_skills: [openclaude-executor]
---

# Reasonix 代码执行器

> DeepSeek-native agent framework — built for cache hits and cheap tokens.
> v0.x, 命令：`reasonix setup` / `reasonix code` / `reasonix run` / `reasonix chat` / `reasonix commit`

## 核心命令速查

| 场景 | 命令 |
|------|------|
| **单次任务（Print模式）** | `reasonix run "重构 legacy_parser.py"` |
| **编码交互会话** | `reasonix code /workspace` |
| **纯聊天（无文件系统）** | `reasonix chat` |
| **继续最近会话** | `reasonix -c` 或 `reasonix code --continue` |
| **生成 commit 消息** | `reasonix commit` |
| **首次设置** | `reasonix setup` |
| **健康检查** | `reasonix doctor` |
| **查看用量统计** | `reasonix stats` |
| **构建语义索引** | `reasonix index` |

---

## 执行流程（含检查点）

```
Phase 1 ── 确认执行条件
   │  在容器内？reasonix 可用？
   │
   ├── ❌ 不满足 → 提示用户进入容器 / 运行 reasonix setup
   │
   ⚡ CHECKPOINT: 确认任务规模和选型
        文件 >2000 行 / 项目级 → Reasonix
        文件 <2000 行 / 简单任务 → 建议 OpenClaude
   │
Phase 2 ── 选择执行模式
   │  reasonix run（单次） / reasonix code（交互编码） / reasonix chat（纯聊）
   │
   ⚡ CHECKPOINT: 展示完整命令，等用户确认再执行
   │
Phase 3 ── 执行任务
   │  执行命令，等待输出
   │
Phase 4 ── 验证输出
   │  run模式：检查终端输出是否完整、无截断
   │  code模式：检查文件变更、git diff 审查
   │
   ⚡ CHECKPOINT: 询问用户 "结果满意吗？需要继续修改 / 用 OpenClaude 补充吗？"
   │
Phase 5 ── 收尾
   结果整理返回、清理临时文件
```

---

## Phase 1：确认执行条件

Reasonix 运行在 Hermes Docker 容器（`hermes`）内：

1. 用户在容器内 → 直接在容器中执行命令
2. 用户在本环境 → 无法直接调用，需请求用户进入容器
3. ⚠️ 本环境无法 `docker exec`（Docker 套接字不可用）

---

## Phase 2：选择工具（与 OpenClaude 对比）

| 条件 | 推荐工具 |
|------|---------|
| 文件 > 2000 行 | **Reasonix** ← 长上下文 + 低成本 |
| 项目级任务（>10 个文件） | **Reasonix** ← 语义索引 + 批量处理 |
| 文件 < 2000 行，简单任务 | **OpenClaude** ← 更快 |
| 需要详细解释/对话交互 | **OpenClaude** ← 交互模式更完善 |
| 成本敏感（大量 token） | **Reasonix** ← DeepSeek v4-flash 极低成本 |
| 需要跨 Provider | **OpenClaude** ← 支持 7 个后端 |
| 需要生成 commit 消息 | **Reasonix** ← 内置 `commit` 命令 |
| 不确定 | **OpenClaude** ← 默认 |

---

## Phase 3：执行任务

### 3.1 `reasonix run` — 单次非交互任务（Print 模式）

```bash
cd /workspace && reasonix run "分析 ./src 目录下所有 Python 文件的圈复杂度"
```

`run` 模式参数：

| 参数 | 说明 |
|------|------|
| `<task>` | 任务描述（必填） |
| `--continue` | 基于最近会话上下文继续 |
| `-h, --help` | 查看帮助 |

### 3.2 `reasonix code` — 编码交互会话

```bash
cd /workspace && reasonix code .
```

启动一个有文件系统工具权限的编码会话。选项：

| 选项 | 说明 |
|------|------|
| `[dir]` | 工作目录（默认：当前目录） |
| `-c, --continue` | 继续最近会话 |
| `--help` | 帮助 |

### 3.3 `reasonix chat` — 纯聊天（无文件系统）

```bash
reasonix chat
```

纯 Ink TUI 聊天界面，带实时缓存/成本面板。适合不需要文件操作的讨论。

### 3.4 `reasonix commit` — 生成 commit 消息

```bash
cd /workspace && reasonix commit
```

从 staged diff 自动生成 commit 消息。需要先 `git add`。

### 3.5 Session 管理

```bash
# 继续最近会话
reasonix -c
reasonix code --continue

# 列出会话
reasonix sessions

# 查看指定会话
reasonix sessions <name>

# 清理旧会话（默认 90 天）
reasonix prune-sessions
reasonix prune-sessions --dry-run  # 预览

# 回放会话记录
reasonix replay <transcript>

# 对比两个会话
reasonix diff <a> <b>
```

---

## Phase 4：任务描述技巧

Task prompt 的质量直接决定 Reasonix 的输出效果。以下是经过验证的模板和技巧。

### 4.1 Prompt 黄金结构

```
[项目背景] + [具体任务] + [文件/范围] + [约束条件] + [期望输出]
```

| 元素 | 说明 | 示例 |
|------|------|------|
| **项目背景** | 技术栈、框架、约定 | `项目使用 FastAPI + SQLAlchemy + PostgreSQL` |
| **具体任务** | 要做什么（动词开头） | `重构 / 分析 / 生成 / 修复 / 迁移` |
| **文件/范围** | 明确路径和范围 | `./src/api/handlers/*.py` |
| **约束条件** | 不能碰什么、保持什么 | `保持接口签名不变，不引入新依赖` |
| **期望输出** | 格式或结构 | `输出 Markdown 表格 / 直接修改文件` |

### 4.2 Task Prompt 模板

```bash
# 模板1：分析（带排序和阈值）
reasonix run "分析 {path} 中的 {指标}，找出 {条件} 的部分，按 {排序方式} 排列"

# 模板2：重构（带拆分规则）
reasonix run "将 {file_path} 中的 {function_name}（超过 {N} 行）拆分成多个小函数，每个不超过 {M} 行，保持原有接口签名"

# 模板3：生成测试（带框架和覆盖要求）
reasonix run "为 {path} 目录下的所有 {语言} 文件生成单元测试，使用 {框架}，覆盖 happy path 和错误路径"

# 模板4：代码迁移（带目标和约束）
reasonix run "将 {source_path} 下的 {旧技术} 代码迁移为 {新技术}，保持功能完全一致，使用 {工具库} 管理状态"
```

### 4.3 已填充示例

| 类型 | 完整命令 |
|------|---------|
| 圈复杂度分析 | `reasonix run "分析 ./src 目录下所有 Python 文件的圈复杂度，找出复杂度超过 15 的函数，按复杂度降序排列"` |
| 文件拆分重构 | `reasonix run "将 legacy_parser.py 中超过 200 行的 parse 函数拆分成多个小函数，每个不超过 50 行，保持原有接口签名"` |
| 依赖分析 | `reasonix run "分析整个项目的模块依赖关系，找出循环依赖并提出解耦建议，输出 Mermaid 格式依赖关系图"` |
| 批量测试生成 | `reasonix run "为 api/handlers/ 目录下的所有 Python 文件生成单元测试，使用 pytest + pytest-asyncio，覆盖 happy path 和错误路径"` |
| SQL 性能优化 | `reasonix run "分析 database.py 中的 SQL 查询，找出 N+1 问题、缺少索引的字段，给出优化方案并改写低效查询"` |
| 框架迁移 | `reasonix run "将 legacy/ 目录下的 jQuery 代码迁移为现代 Vue 3 组合式 API，功能完全一致，使用 Pinia 管理状态"` |
| 安全审查 | `reasonix run "审查 src/ 下所有代码：检查 SQL 注入、XSS、硬编码密钥、缺失的错误处理 — 按严重程度分级输出"` |
| commit 消息 | `cd /workspace && git add -A && reasonix commit`（自动生成，无需额外参数） |
| 交互编码 | `reasonix code .`（启动后自然语言交互，非 run 模式） |

### 4.4 按输出格式控制

```bash
# Markdown 表格 → 结构化
reasonix run "分析 ./src 代码质量，输出为 Markdown 表格，列：文件名、行数、圈复杂度、TODO数"

# JSON 格式 → 可解析
reasonix run "列出 ./src 中所有公共函数，输出 JSON：{\"functions\":[{\"name\":\"...\",\"file\":\"...\",\"line\":N}]}"

# Mermaid 图表 → 可视化
reasonix run "分析模块依赖关系，输出 Mermaid 格式依赖图"

# 直接修改文件 → 默认行为
reasonix run "重构 legacy_parser.py，直接修改文件"
```

### 4.5 分步复杂任务

对于大型项目任务，分步执行比一步到位效果更好：

```bash
# Step 1: 先了解结构
reasonix run "列出 ./src 的目录结构和每个文件的行数，这是我理解项目的第一步，尽可能详细"

# Step 2: 专项分析
reasonix run "分析 ./src/api 中所有 handler 的代码质量，关注错误处理和输入验证"

# Step 3: 执行修改
reasonix run "修复 ./src/api/users.py 中所有缺失的错误处理，用 try-except 包裹数据库操作"

# Step 4: 验证
reasonix run "验证 ./src/api/users.py 的修改是否正确，检查新加的错误处理是否符合项目现有模式"
```

### 4.6 根据文件量级调整命令

| 量级 | 建议策略 | 示例 |
|------|---------|------|
| 1-5 个文件 | 一次性完成 | `reasonix run "重构 file1.py 和 file2.py"` |
| 5-20 个文件 | 分组批量 | `reasonix run "重构 api/handlers/ 目录下所有文件"` |
| 20-100 个文件 | 先分析后执行 | Step 1: 分析 → Step 2: 批量重构 |
| 整个项目 | 分模块执行 | 每个模块单独 `reasonix run` |

---

## Phase 5：处理输出

Reasonix 执行完成后：

1. **`run` 模式：** 结果输出到终端，可直接读取
2. **`code` 模式：** 文件修改直接写入工作目录
3. 读取输出结果后整理返回用户

**需在返回前检查：**
- ✅ 检查关键文件是否确实被创建/修改
- ✅ 确认输出结果合理、无截断
- ✅ 用 `git diff` 审查变更（如有 git 管理）
- ✅ 询问用户是否满意，还是需要继续修改

---

## 子命令参考

| 命令 | 用途 |
|------|------|
| `setup` | 交互式向导：API key、预设、MCP 服务器 |
| `code [dir]` | 编码编辑会话，文件系统工具以 `<dir>` 为根 |
| `chat` | 交互式 Ink TUI（带实时缓存/成本面板） |
| `run <task>` | 单次非交互任务（流式输出） |
| `acp` | 作为 ACP Agent 运行（stdio NDJSON JSON-RPC） |
| `desktop` | 桌面客户端用无头 JSON-RPC 聊天（内部） |
| `stats [transcript]` | 用量仪表盘 |
| `doctor` | 一键健康检查 |
| `commit` | 从 staged diff 生成 commit 消息 |
| `sessions [name]` | 列出或查看会话 |
| `prune-sessions` | 清理旧会话（默认 90 天，`--dry-run` 预览） |
| `events <name>` | 打印内核事件日志 |
| `replay <transcript>` | 交互式回放会话记录 |
| `diff <a> <b>` | 对比两个会话记录 |
| `mcp` | MCP 帮助 — 发现服务器、测试配置 |
| `version` | 打印版本 |
| `update` | 检查并安装更新 |
| `index` | 构建语义搜索索引 |

---

## 安装与设置

```bash
# 首次设置（容器内）
reasonix setup
```
- 交互式向导：配置 API Key、选择预设、设置 MCP 服务器
- 可随时重复运行以重新配置

```bash
# 检查更新
reasonix update

# 健康检查
reasonix doctor

# 查看版本
reasonix version
```

---

## MCP 集成

```bash
# MCP 帮助：发现服务器、测试配置
reasonix mcp
```

---

## 成本优势

| 对比项 | Reasonix + DeepSeek v4-flash | OpenClaude（Claude Sonnet） |
|--------|------------------------------|------------------------------|
| 4.35 亿 tokens 成本 | **< $2** | $200+ |
| 缓存命中优化 | 原生深度优化 | 通用缓存 |
| 长上下文 | 原生低成本 | 按 token 计费 |
| 适合场景 | 大型代码库、批量处理 | 小到中型任务、交互开发 |

---

## 错误处理

| 症状 | 原因 | 处理 |
|------|------|------|
| `command not found` | 不在容器内或未安装 | 提示 `reasonix setup` 或进入容器 |
| 长时间无输出 | 大文件正在处理 | 等待（DeepSeek 大文件可能较慢） |
| 输出被截断 | 终端缓冲区限制 | 重定向：`reasonix run "..." > /tmp/output.md` |
| 结果不理想 | 任务描述太模糊 | 补充文件路径、具体问题、期望输出格式 |
| `reasonix: command not found` | 未安装 | `reasonix setup` 运行安装向导 |
| `run` 带交互式（无参数） | 忘记加 task | `reasonix run "你的任务描述"` |
| 缓存未生效 | 首次使用 | 重复相似任务后缓存命中率提升 |

---

## 注意事项

> 完整 CLI 参考：`references/cli-reference.md` — 所有子命令和选项。

1. **`reasonix` 默认进入交互模式** — 单次任务必须用 `reasonix run "任务"`
2. **`reasonix code [dir]` 是编码会话** — 有文件系统权限，`reasonix chat` 没有
3. **首轮慢，后续快** — DeepSeek v4-flash 利用缓存，相同/相似任务第二轮开始极快
4. **任务描述越具体越好** — 指定文件路径、函数名、期望输出格式
5. **结果写入工作目录** — `reasonix code` 模式下文件修改直接写入
6. **建议用 git 管理** — `git diff` 审查变更，不满意 `git checkout -- <file>`
7. **项目级分析前先了解结构** — `find . -type f -name "*.py" | head -50` 预览再交给 Reasonix
8. **`reasonix commit` 需要 `git add`** — 先 stage 变更再运行
9. **`reasonix run` 简单直接** — 相比 OpenClaude 的 `-p` 模式，无需 `--max-turns` 等参数
10. **设置可以重跑** — `reasonix setup` 随时重新配置 API Key 和预设

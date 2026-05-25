---
name: openclaude-executor
description: 调用 OpenClaude 执行代码编写、调试、重构等任务。OpenClaude 支持多 Provider（Anthropic、OpenAI、Gemini、Ollama 等），功能与 Claude Code CLI 完全一致。当用户说「用 openclaude」「调用 openclaude」「openclaude 执行」「用 ocl 写代码」「openclaude 对话」「openclaude 重构」时使用。也适用于需要跨模型、跨 Provider 的编码任务。
related_skills: [reasonix-executor]
---

# OpenClaude 代码执行器

OpenClaude v0.13.0 是一个功能完整的编码 Agent CLI，与 Claude Code CLI 接口完全兼容，额外支持多 Provider（Anthropic、OpenAI、Google Gemini、Ollama、GitHub Models、AWS Bedrock、GCP Vertex）。默认交互式会话，用 `-p` 进入非交互模式。

## 执行流程（含检查点）

```
Phase 1 ── 确认执行条件
   │  环境检查（在容器内？openclaude可用？）
   │
   ├── ❌ 条件不满足 → 提示用户进入容器 / 安装
   │
Phase 2 ── 选择执行模式
   │  Print模式 / Interactive模式
   │  Provider选择、模型选择、参数配置
   │
   ⚡ CHECKPOINT: 展示完整命令，等用户确认
   │
Phase 3 ── 执行任务
   │  Print → 直接执行
   │  Interactive → tmux编排启动
   │
Phase 4 ── 验证输出
   │  检查返回结果、确认文件变更、有无报错
   │
   ⚡ CHECKPOINT: 询问用户 "结果满意吗？要修改/继续吗？"
   │
Phase 5 ── 收尾
   清理tmux（如用到）、保存命令记录
```

---

## 调用方式速查

| 场景 | 命令 |
|------|------|
| 单次编码（Print模式） | `openclaude -p "写一个 Python 斐波那契函数"` |
| 交互式对话 | `openclaude "重构 auth 模块"` |
| 指定模型 | `openclaude --model sonnet -p "..."` |
| 切换 Provider | `openclaude --provider openai -p "..."` |
| 继续上次会话 | `openclaude -c` |
| Resume 指定会话 | `openclaude -r <session_id>` |
| 管道输入 | `cat file.py \| openclaude -p "审查这段代码"` |
| JSON 结构化输出 | `openclaude -p "..." --output-format json --json-schema '{"type":"object"}'` |
| 成本上限 | `openclaude -p "..." --max-budget-usd 0.5 --max-turns 10` |
| 限制工具 | `openclaude -p "..." --allowedTools "Read,Edit"` |

## Print 模式（-p）—— 非交互式

Print 模式执行一次性任务后退出。适合自动化、CI/CD 和脚本。**自动跳过 workspace trust 对话框。**

```bash
# 基础用法
openclaude -p "给所有 API 端点添加错误处理"

# 指定模型 + 输出格式
openclaude -p "分析 auth.py 中的安全漏洞" \
  --model sonnet \
  --output-format json \
  --max-turns 10

# 限制工具范围
openclaude -p "对 src/ 运行代码格式化" \
  --allowedTools "Read,Bash(npx prettier *)" \
  --max-turns 5

# 成本上限
openclaude -p "重构数据库层" \
  --max-budget-usd 0.5 \
  --max-turns 10

# 管道输入
cat src/auth.py | openclaude -p "审查这段代码中的 bug" --max-turns 1

# git diff 分析
git diff HEAD~3 | openclaude -p "总结这些变更" --max-turns 1
```

### JSON 结构化输出

```bash
openclaude -p "列出 src/ 中所有函数" \
  --output-format json \
  --json-schema '{"type":"object","properties":{"functions":{"type":"array","items":{"type":"string"}}},"required":["functions"]}' \
  --max-turns 5
```

### 流式 JSON 输出

```bash
openclaude -p "写一个总结" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages
```

### 双向流式（实时输入+输出）

```bash
openclaude -p "任务" \
  --input-format stream-json \
  --output-format stream-json \
  --replay-user-messages
```

## Interactive 模式 —— 多轮对话

默认启动交互式 TUI 会话。**要用 tmux 编排以实现自动化控制。**

### tmux 编排

```bash
# 1. 启动 tmux 会话
tmux new-session -d -s ocl-work -x 140 -y 40

# 2. 启动 OpenClaude
tmux send-keys -t ocl-work 'cd /workspace && openclaude' Enter

# 3. 等待启动，处理 trust 对话框
sleep 5 && tmux send-keys -t ocl-work Enter

# 4. 发送任务
sleep 2 && tmux send-keys -t ocl-work '重构 auth 模块使用 JWT' Enter

# 5. 监控进度
tmux capture-pane -t ocl-work -p -S -50

# 6. 后续指令
tmux send-keys -t ocl-work '为新 JWT 代码写测试' Enter

# 7. 退出
tmux send-keys -t ocl-work '/exit' Enter

# 8. 清理
tmux kill-session -t ocl-work
```

### Interactive 斜杠命令

| 命令 | 用途 |
|------|------|
| `/help` | 显示所有命令 |
| `/compact` | 压缩上下文节省 tokens |
| `/clear` | 清空对话历史 |
| `/context` | 查看上下文使用情况（彩色网格） |
| `/cost` | 查看 token 用量和费用 |
| `/resume` | 切换到其他会话 |
| `/rewind` | 回退到之前的检查点 |
| `/status` | 查看版本、连接状态 |
| `/exit` / `Ctrl+D` | 结束会话 |
| `/review` | 审查当前变更 |
| `/plan` | 进入 Plan 模式 |
| `/model` | 切换模型 |
| `/effort` | 设置推理深度（low/medium/high/max） |
| `/init` | 创建项目配置文件 |
| `/memory` | 编辑记忆文件 |
| `/config` | 交互式配置管理 |
| `/permissions` | 查看/更新工具权限 |
| `/agents` | 管理子 Agent |
| `/mcp` | 管理 MCP 服务器 |

### 键盘快捷键

| 按键 | 操作 |
|------|------|
| `Ctrl+C` | 取消当前输入/生成 |
| `Ctrl+D` | 退出 |
| `Ctrl+R` | 反向搜索命令历史 |
| `Ctrl+B` | 后台运行任务 |
| `Shift+Enter` | 换行 |
| `!command` | 直接执行 bash（绕过 AI） |
| `@file` | 引用文件（自动补全） |

## Provider 选择

OpenClaude 最大差异化优势：支持多个 Provider。

| Provider | 选项值 | 环境变量 |
|----------|--------|----------|
| Anthropic | `--provider anthropic` | `ANTHROPIC_API_KEY` |
| OpenAI | `--provider openai` | `OPENAI_API_KEY` |
| Google Gemini | `--provider gemini` | `GEMINI_API_KEY` |
| GitHub Models | `--provider github` | `GITHUB_TOKEN` |
| AWS Bedrock | `--provider bedrock` | AWS 凭证 |
| GCP Vertex | `--provider vertex` | GCP 凭证 |
| Ollama | `--provider ollama` | 本地运行 |

```bash
# OpenAI
openclaude --provider openai --model gpt-4o -p "写一个 Python 脚本"

# Gemini
openclaude --provider gemini --model gemini-2.0-flash -p "分析代码"

# Ollama（本地）
openclaude --provider ollama --model llama3 -p "审查代码"
```

## Session 管理

```bash
# 继续最近的会话
openclaude -c

# 按 ID 恢复
openclaude -r <session_id>

# Fork 会话（新 ID，保留历史）
openclaude -r <session_id> --fork-session -p "换个方法试试"

# 命名会话便于识别
openclaude -n "auth-refactor" -p "重构 auth 模块"

# 不保存会话（CI 环境）
openclaude --no-session-persistence -p "任务"
```

## Bare 模式（CI/脚本）

```bash
openclaude --bare -p "运行所有测试并报告失败" \
  --allowedTools "Read,Bash" \
  --max-turns 10
```

`--bare` 跳过 hooks、插件发现、MCP 自动发现、CLAUDE.md 自动加载、OAuth。最快启动。需要 `ANTHROPIC_API_KEY` 环境变量。

选择性加载上下文：

| 需要的内容 | Flag |
|-----------|------|
| 追加系统提示 | `--append-system-prompt "text"` |
| 设置 | `--settings <file-or-json>` |
| MCP 服务器 | `--mcp-config <file-or-json>` |
| 自定义 Agent | `--agents '<json>'` |

## CLI Flags 完整参考

### Provider 与模型

| Flag | 作用 |
|------|------|
| `--provider <provider>` | AI 后端（anthropic/openai/gemini/github/bedrock/vertex/ollama） |
| `--model <model>` | 模型选择（别名：sonnet/opus/haiku，或全名：claude-sonnet-4-6） |
| `--effort <level>` | 推理深度：low/medium/high/max |
| `--fallback-model <model>` | 超载时自动回退（仅 print 模式） |
| `--betas <betas...>` | Beta 特性（API key 用户） |

### 会话控制

| Flag | 作用 |
|------|------|
| `-p, --print` | 非交互式单次模式 |
| `-c, --continue` | 继续最近对话 |
| `-r, --resume <id>` | 按 ID 恢复会话 |
| `--fork-session` | Fork 会话（新 ID） |
| `--session-id <uuid>` | 指定 UUID |
| `-n, --name <name>` | 设置会话显示名称 |
| `--no-session-persistence` | 不保存会话 |
| `--from-pr [number]` | 恢复关联 PR 的会话 |
| `-w, --worktree [name]` | 创建 git worktree |
| `--tmux` | 创建 tmux worktree 会话 |
| `--add-dir <paths...>` | 添加额外工作目录 |
| `--ide` | 自动连接 IDE |
| `--chrome` / `--no-chrome` | 启用/禁用 Chrome 集成 |

### 权限与安全

| Flag | 作用 |
|------|------|
| `--dangerously-skip-permissions` | 自动批准所有工具操作 |
| `--allow-dangerously-skip-permissions` | 仅作为选项启用 |
| `--permission-mode <mode>` | default/acceptEdits/plan/auto/dontAsk/bypassPermissions |
| `--allowedTools <tools...>` | 白名单工具 |
| `--disallowedTools <tools...>` | 黑名单工具 |
| `--tools <tools...>` | 覆盖内置工具集（""=禁用, "default"=全部） |

### 输出与输入

| Flag | 作用 |
|------|------|
| `--output-format <fmt>` | text/json/stream-json |
| `--input-format <fmt>` | text/stream-json |
| `--json-schema <schema>` | 结构化的 JSON Schema 输出 |
| `--verbose` | 详细输出 |
| `--include-partial-messages` | 输出部分消息块 |
| `--replay-user-messages` | 回显用户消息 |
| `--include-hook-events` | 包含 hook 生命周期事件 |

### 系统提示与上下文

| Flag | 作用 |
|------|------|
| `--system-prompt <prompt>` | 替换系统提示 |
| `--append-system-prompt <prompt>` | 追加系统提示 |
| `--bare` | 极简模式（跳过自动发现） |
| `--agents '<json>'` | 动态自定义 Agent |
| `--mcp-config <configs...>` | 加载 MCP 服务器 |
| `--strict-mcp-config` | 仅使用 --mcp-config 中的 MCP |
| `--settings <file-or-json>` | 加载设置 |
| `--setting-sources <sources>` | 设置来源（user/project/local） |
| `--plugin-dir <path>` | 加载插件目录 |
| `--file <specs...>` | 启动时下载文件资源 |
| `--disable-slash-commands` | 禁用斜杠命令 |

### 调试

| Flag | 作用 |
|------|------|
| `-d, --debug [filter]` | 调试日志（可分类过滤） |
| `--debug-file <path>` | 写入调试日志到文件 |

### 消耗控制

| Flag | 作用 |
|------|------|
| `--max-turns <n>` | 最大 Agent 循环次数（print 模式） |
| `--max-budget-usd <n>` | API 花费上限（print 模式） |
| `--model <model>` | 选择低成本模型 |

### Print 模式的 max-turns 建议

| 任务类型 | 建议 max-turns |
|---------|---------------|
| 简单代码生成（单文件） | 3-5 |
| 添加注释/文档 | 3-5 |
| 代码审查 | 1-3 |
| Bug 修复 | 5-10 |
| 重构单一文件 | 5-10 |
| 多文件重构 | 10-15 |
| 项目级分析 | 10-20 |
| 批量测试生成 | 10-20 |

## 对话框处理（Interactive 模式关键）

第一次启动 OpenClaude 时可能出现两个对话框：

### Dialog 1: Workspace Trust

```
❯ 1. Yes, I trust this folder    ← 默认（直接按 Enter）
  2. No, exit
```

**处理：** `tmux send-keys -t <session> Enter`

### Dialog 2: 权限绕过确认（仅限 --dangerously-skip-permissions）

```
❯ 1. No, exit                    ← 默认（错误选项！）
  2. Yes, I accept
```

**处理：** 先 Down 再 Enter
```
tmux send-keys -t <session> Down && sleep 0.3 && tmux send-keys -t <session> Enter
```

### 稳健的启动模式

```bash
# 启动带权限绕过
tmux send-keys -t ocl-work 'openclaude --dangerously-skip-permissions "你的任务"' Enter

# 处理 trust 对话框
sleep 4 && tmux send-keys -t ocl-work Enter

# 处理权限对话框
sleep 3 && tmux send-keys -t ocl-work Down && sleep 0.3 && tmux send-keys -t ocl-work Enter

# 等待执行
sleep 15 && tmux capture-pane -t ocl-work -p -S -60
```

**注意：** trust 对话框只首次出现，权限对话框每次 `--dangerously-skip-permissions` 都会出现。

## 配置文件与记忆

### 设置层次（高→低优先级）

1. **CLI flags** — 覆盖一切
2. **本地项目：** `.claude/settings.local.json`（个人，gitignored）
3. **项目：** `.claude/settings.json`（共享，git-tracked）
4. **用户：** `~/.claude/settings.json`（全局）

### 项目记忆（CLAUDE.md）

- **全局：** `~/.claude/CLAUDE.md`
- **项目：** `./CLAUDE.md`
- **本地：** `.claude/CLAUDE.local.md`

交互模式用 `# 提示内容` 快速添加到记忆。

### 权限配置

```json
{
  "permissions": {
    "allow": ["Bash(npm run lint:*)", "WebSearch", "Read"],
    "ask": ["Write(*.ts)", "Bash(git push*)"],
    "deny": ["Read(.env)", "Bash(rm -rf *)"]
  }
}
```

### 自定义 Agent

```markdown
# .claude/agents/security-reviewer.md
---
name: security-reviewer
description: Security-focused code review
model: opus
tools: [Read, Bash]
---
你是安全工程师。审查：注入漏洞、认证缺陷、密钥泄露、反序列化风险。
```

交互中调用：`@security-reviewer 审查 auth 模块`

### 自定义 Slash 命令

`.claude/commands/deploy.md`：
```markdown
部署流程：
1. 运行所有测试
2. 构建 Docker 镜像
3. 推送到 registry
4. 更新 $ARGUMENTS 环境（默认：staging）
```

使用：`/deploy production`

## MCP 集成

```bash
# 添加 MCP 服务器
openclaude mcp add -s user github -- npx @modelcontextprotocol/server-github

# 列出
openclaude mcp list

# 删除
openclaude mcp remove <name>

# 在 Print/CI 模式使用
openclaude --bare -p "查询数据库" --mcp-config mcp-servers.json --strict-mcp-config
```

MCP 作用域：
- `-s user` — 全局（`~/.claude.json`）
- `-s local` — 本地项目（`.claude/settings.local.json`，gitignored）
- `-s project` — 团队共享（`.claude/settings.json`，git-tracked）

## 并行 OpenClaude 实例

```bash
# 任务1: 修复后端
tmux new-session -d -s task1 -x 140 -y 40
tmux send-keys -t task1 'cd /workspace && openclaude -p "修复 auth.py 的认证 bug" --allowedTools "Read,Edit" --max-turns 10' Enter

# 任务2: 写测试
tmux new-session -d -s task2 -x 140 -y 40
tmux send-keys -t task2 'cd /workspace && openclaude -p "为 API 端点写集成测试" --allowedTools "Read,Write,Bash" --max-turns 15' Enter

# 监控
sleep 30
for s in task1 task2; do
  echo "=== $s ==="
  tmux capture-pane -t $s -p -S -5 2>/dev/null
done

# 清理
for s in task1 task2; do
  tmux kill-session -t $s 2>/dev/null
done
```

## 订阅命令

| 命令 | 用途 |
|------|------|
| `openclaude auth login` | 登录 |
| `openclaude auth login --console` | API key 计费 |
| `openclaude auth login --sso` | 企业 SSO |
| `openclaude auth status` | 查看登录状态 |
| `openclaude doctor` | 健康检查 |
| `openclaude update` / `upgrade` | 升级 |
| `openclaude install [target]` | 安装（stable/latest/版本号） |
| `openclaude setup-token` | 设置长期令牌 |
| `openclaude agents` | 管理 Agent |
| `openclaude mcp` | 管理 MCP |
| `openclaude plugin` / `plugins` | 管理插件 |
| `openclaude auto-mode` | 自动模式配置 |
| `openclaude --version` | 查看版本 |

## OpenClaude 独有的 Provider 优势

```bash
# Anthropic（默认，claude-sonnet-4-6）
openclaude --provider anthropic --model sonnet -p "分析代码"

# OpenAI（GPT-4o）
openclaude --provider openai --model gpt-4o -p "写一个脚本"

# Gemini
openclaude --provider gemini --model gemini-2.0-flash -p "审查代码"

# Ollama 本地
openclaude --provider ollama --model llama3 -p "解释这段代码"

# AWS Bedrock
openclaude --provider bedrock --model claude-sonnet-4-6 -p "分析"
```

**注意：** `--provider` 需读取对应 Provider 的环境变量（`OPENAI_API_KEY` 等），确保在容器中已设置。

## 成本与性能建议

1. **`--max-turns` 必须有** — 防止无限循环。简单任务 3-5，复杂任务 10-15
2. **`--max-budget-usd` + `--provider` 组合** — 需要低成本用 `--provider openai --model gpt-4o-mini`
3. **`--effort low` 简单任务** — 更快更便宜
4. **`--bare` 用于 CI** — 跳过自动发现，最快启动
5. **`--allowedTools` 限制工具** — 审查只给 `Read`，生成测试给 `Read,Write,Bash`
6. **管道输入** — 分析已知内容时用管道代替让 OpenClaude 自己读文件
7. **新任务开新会话** — 会话 5 小时过期，新会话效率更高
8. **`--no-session-persistence` CI 环境** — 避免积累磁盘上的会话文件

## 监控 Interactive 会话

`tmux capture-pane -t ocl-work -p -S -10` 查看状态指示：

- `❯` 在底部 = 等待你的输入（执行完毕或有疑问）
- `●` 行 = OpenClaude 正在使用工具
- `ctrl+o to expand` = 工具输出被截断

### 上下文健康度

- **< 70%** — 正常，精度高
- **70-85%** — 精度下降，考虑 `/compact`
- **> 85%** — 幻觉风险显著增加，立即 `/compact` 或 `/clear`

## 适用场景速查表

| 场景 | 模式 | 命令 |
|------|------|------|
| 写一个新函数 | Print | `openclaude -p "..." --max-turns 5` |
| 修复一个 bug | Print | `openclaude -p "分析并修复 ..." --max-turns 10` |
| 重构大文件 | Print/Interactive | `openclaude -p "重构 ..." --max-turns 15` |
| 批量生成测试 | Print | `openclaude -p "为目录生成测试" --max-turns 20` |
| 代码审查 | Print | `cat diff \| openclaude -p "审查" --max-turns 1` |
| 交互式开发 | Interactive | tmux + `openclaude` |
| 长上下文大型项目 | Print/Bare | `openclaude --bare --allowedTools "Read,Edit" --max-turns 20` |
| 跨 Provider 对比 | Print | 多次执行不同 `--provider` |
| CI/CD 自动化 | Print/Bare | `openclaude --bare --no-session-persistence --max-budget-usd 0.2` |

---

## 错误处理

| 症状 | 原因 | 处理 |
|------|------|------|
| `openclaude: command not found` | 未安装 | 提示用户在容器内运行 `openclaude install` 或 `npm install -g @anthropic-ai/claude-code` |
| Provider 环境变量缺失 | `OPENAI_API_KEY` 等未设置 | 提示用户检查容器内 `echo $OPENAI_API_KEY`，用 `export` 设置后重试 |
| API 限流错误 | 请求频率过高 | 等待 30-60 秒后重试，或加 `--fallback-model haiku` 用更小模型 |
| API 认证失败 | API key 无效或过期 | 提示 `openclaude auth login --console` 重新认证 |
| Print 模式无输出/卡死 | `--max-turns` 不足任务提前终止 | 增大 `--max-turns`（复杂任务 10-20），或拆分任务 |
| Interactive 启动卡在空白页 | 对话框未处理 | 发送 `Enter` → 等 2s → 如仍卡住发 `Down+Enter`（处理权限对话） |
| tmux 会话不可见 | 会话名冲突或已存在 | `tmux kill-session -t <name>` 清理旧会话后重试 |
| 输出截断/结果不全 | 终端缓冲区限制 | 用 `--output-format json` 获取完整结构化结果 |
| `--max-budget-usd` 立即报错 | 预算过低（<$0.05） | 设 `--max-budget-usd 0.05` 或更高，或用 `--max-turns` 替代预算限制 |
| 会话无法 resume | 会话已过期（5h）或在不同目录 | 提示开启新会话 |
| tmux 编排后 OpenClaude 无响应 | 对话框需要处理 | `tmux capture-pane` 检查当前显示的内容，按需发送 Enter/Down+Enter |
| 大文件重构中途失败 | 上下文超限 | 拆分任务：先分析结构再分块重构 |
| `--provider ollama` 连接失败 | Ollama 服务未运行 | 检查容器内 `ollama list`，先启动 `ollama serve` |
| 权限错误（Permission denied） | 目录不可写 | 确保 `/workspace` 有写入权限，或切换到 `/tmp` 执行 |

### Fallback 策略

| 主方案失败 | Fallback 方案 |
|-----------|---------------|
| Print 模式超时 | 拆分任务 → 重新执行更小的子任务 |
| Interactive 模式卡住 | `Ctrl+C` 终止 → 切换到 Print 模式 |
| 当前 Provider 限流 | 换 Provider：`--provider openai --model gpt-4o-mini` |
| openclaude 完全不可用 | 切换到 **Reasonix**（`reasonix run "..."`）或由 Hermes 直接处理 |
| 目标容器不可达 | 请求用户手动在容器内执行命令并返回结果 |

---

## 注意事项

> 完整 CLI 参考：`references/cli-reference.md` — 所有 flag 和 Provider 列表。

- **Print 模式自动跳过 trust 对话框** — 安全地在任何目录使用
- **Interactive 模式必须用 tmux** — OpenClaude 是 TUI 应用，tmux 提供 capture-pane 和 send-keys
- **`--dangerously-skip-permissions` 对话框默认选 "No, exit"** — 必须 Down+Enter
- **`--max-budget-usd` 最低 ~$0.05** — 系统提示缓存创建就需要这么多
- **`--max-turns` 仅 print 模式有效** — 交互式忽略
- **`--provider` 需对应环境变量** — 容器内未设置时会失败
- **背景 tmux 会话会持久** — 用完必须 `tmux kill-session -t <name>` 清理
- **斜杠命令仅交互式有效** — print 模式用自然语言描述
- **新容器实例会丢失 ~/.claude 缓存** — trust 设置和会话记录重置

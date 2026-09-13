# config.yaml：基线 vs live 逐段差异

> 生成时间：2026-09-13 09:24:49

| | 文件 | 大小 | 顶层段数 | mtime |
|---|---|---|---|---|
| 基线（仓库旁副本） | `/home/user/gateway/config/config.yaml` | 17568 B | 79 | 2026-09-11 08:45:40 |
| live（容器实读） | `/home/user/gateway/data/hermes/config.yaml` | 5358 B | 9 | 2026-09-13 08:06:30 |

**结论**：live 比基线少 **70 个顶层段**（基线 79 段 → live 9 段）。

## live 现有段（9）

```
_config_version command_allowlist custom_providers mcp_servers memory model terminal tts web
```

## 基线独有段（按建议优先级）

### ① 优先合并（对当前用法直接有用） — 25 段

```
agent approvals browser checkpoints code_execution compression computer_use context credential_pool_strategies cron curator delegation fallback_providers kanban known_plugin_toolsets logging model_catalog platform_toolsets providers secrets security sessions skills tools toolsets
```

### ② 按需合并 — 36 段

```
auxiliary context_file_max_chars dashboard display file_read_max_chars gateway goals honcho hooks hooks_auto_accept human_delay lsp max_concurrent_sessions max_live_sessions mcp_discovery_timeout moa network onboarding paste_collapse_char_threshold paste_collapse_threshold paste_collapse_threshold_fallback personalities platform_hints prefill_messages_file privacy prompt_caching quick_commands reasoning streaming stt timezone tool_loop_guardrails tool_output updates vector_db voice
```

### ③ 多半用不上（渠道/云平台集成） — 9 段

```
bedrock discord matrix mattermost openrouter slack telegram whatsapp x_search
```

## 共有段中「基线更丰富」的（合并时要按段挑选，不能整段覆盖）

| 段 | 基线行数 | live 行数 |
|---|---|---|
| `tts` | 29 | 3 |
| `terminal` | 24 | 1 |
| `mcp_servers` | 93 | 73 |
| `command_allowlist` | 15 | 2 |
| `memory` | 11 | 10 |

## 合并注意（三条红线）

1. **基线是 2026-09-11 的状态**，可能含已废弃的 provider / 模型 ID / 密钥 → **必须逐段挑选**，不要 `cp` 覆盖。
2. **含明文密钥**（`ak_…`、`sk-…`）→ live 与快照都在 `data/` 下，**永远不要推进任何 git 仓库**。
3. 合并后必须用 Hermes 自己的加载器校验，并确认容器能正常起来：
   ```bash
   docker exec hermes /opt/hermes/.venv/bin/python -c \
     "from hermes_cli.config import load_config_readonly as L; c=L(); print('段数', len(c))"
   ```
   生效方式：成对重启（`docker stop hermes hermes-webui && docker start hermes hermes-webui`）。

## 回滚

合并前先留一份：
```bash
cp -p /home/user/gateway/data/hermes/config.yaml \
      /home/user/gateway/data/hermes/config.yaml.pre-merge-$(date +%Y%m%d-%H%M%S)
```
出错时用 `scripts/restore-config.sh --apply <快照>` 秒回。

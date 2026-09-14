# webui → brain 单向配置同步

> 起因：B″″ 之后 webui 的 `HERMES_HOME` 顶级文件与脑侧 `data/hermes/` 物理分家，
> 网页端改的 provider / key / 模型只落在 webui 侧。本机制把 webui 侧**单向**推给脑侧。
> 上线：2026-09-14 14:25（实测通过）

## 组件

| 组件 | 路径 | 作用 |
|---|---|---|
| 同步引擎 | `scripts/sync-webui-to-brain.py` | 合并 + 备份 + 原子写 + 状态；`--dry-run/--force/--quiet` |
| 入口包装 | `scripts/sync-webui-to-brain.sh` | 给 systemd / cron / 手调用 |
| 变化监视 | `scripts/watch-webui-config.sh` | 每 3 秒比对源文件哈希，变则立即同步 |
| 常驻服务 | `/etc/systemd/system/hermes-webui-sync.service` | `Restart=always`，开机自启（enabled） |
| 兜底定时 | `/etc/cron.d/hermes-webui-sync` | 每 10 分钟一次（幂等，源未变秒退） |
| 状态 | `data/hermes/.sync-state.json` | 上次同步的源/目标哈希（源未变即短路） |
| 备份 | `data/hermes/.sync-backups/`（700，文件 600，留 30 份） | 每次写入脑侧前的原文件 |
| 日志 | `/var/log/hermes-webui-sync.log` | 只记键名/段名/计数，**不记任何密钥值** |

## 合并语义（不是整文件覆盖）

| 文件 | 规则 | 保护 |
|---|---|---|
| `.env` | 按键合并，webui 覆盖同名键 | 脑侧独有键保留 |
| `auth.json` | 递归合并，webui 覆盖叶子 | 目标独有 provider/键保留；**易变字段保留脑侧**（OAuth token、agent_key、`expires_at/obtained_at`、`last_status*`、`request_count` 等） |
| `config.yaml` | 只搬白名单顶层的段 | 白名单 = `model`、`custom_providers`、`tts`、`memory`、`mcp_servers`；其余段（terminal/web/plugins/delegation/logging/sessions/…）**脑侧原样不动**，注释也保留 |
| `SOUL.md` | 不合并，纯覆盖 | 若脑侧自上次同步后也被改过 → **不动脑侧**，把 webui 版另存 `SOUL.md.conflict-<ts>` 并告警 |

扩展白名单：改 `sync-webui-to-brain.py` 顶部的 `CONFIG_SYNC_KEYS`。

## 触发链路

```
网页端保存设置 → webui 写 data/.hermes-rt/{config.yaml,.env,auth.json}（原子写）
              → watcher（3 秒轮询哈希）→ 引擎合并 → 原子写脑侧 data/hermes/（沿用 10000:10000 原权限）
              → cron 每 10 分钟兜底
```
实测延迟 ≤ 8 秒（含等待窗口）；脑侧 gateway 已加载的配置需**下次启动/新会话**才生效。

## 运维命令

```bash
systemctl status hermes-webui-sync            # 常驻监视是否在跑
tail -20 /var/log/hermes-webui-sync.log       # 同步历史
python3 /home/user/gateway/scripts/sync-webui-to-brain.py --dry-run --force   # 只看会改什么
bash /home/user/gateway/scripts/sync-webui-to-brain.sh                        # 手工同步一次
ls -lt /home/user/gateway/data/hermes/.sync-backups/                          # 脑侧原文件备份
systemctl stop hermes-webui-sync              # 暂停（另需注释 /etc/cron.d/hermes-webui-sync）
```

## 实测证据（2026-09-14）

| 检查 | 结果 |
|---|---|
| 触发延迟 | 在 webui 侧 `tts:` 段插入探针注释 → 脑侧 **≤8 秒**出现；移除后同步回滚，两侧该段逐字节一致 |
| 幂等 | 源未变时再次运行：四个文件全部「无变化」，不写盘 |
| 脑侧完整性 | 首跑只改 22 行（`mcp_servers` 引号风格 + `custom_providers` 的 `api_mode`），**注释 36 行不变、总行数 179 不变、16 个顶层段全在**；`yaml.safe_load` 通过 |
| 属主/权限 | 同步写出的脑侧文件仍是 `10000:10000`（原子写沿用原 uid/gid/mode），不制造 root 属主漂移 |
| 凭证安全 | 易变字段首跑被列表整体覆盖一次 → 已用 `.sync-backups` 精确还原（10 个字段）；此后 `credential_pool.*` 逐元素合并，不再覆盖 |

## 已知取舍

1. **单向**：以 webui 为真源。脑侧自己改的同名设置，会在下次 webui 侧变更时被覆盖（脑侧独有段/键除外）。
2. 首跑把脑侧 `custom_providers.longcat.api_mode` 由 `codex_responses` 改成 `chat_completions`（以 webui 为准）。若要保留脑侧值，把该字段加进保护名单。
3. `SOUL.md` 冲突时以「不覆盖脑侧 + 存冲突副本」处理，避免把宿主侧的编辑冲掉。

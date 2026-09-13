# 配置快照与回滚机制（config-snapshots）

> 2026-09-13 新增。解决的根因：Hermes 自己的 `save_config()`（默认 `merge_existing=False`）在部分调用方
> 只传入配置的一部分时，**它没包含的段会被丢掉** —— live 曾从 79 段缩到 9 段。
> 注意：**Ekko 不写 config.yaml**（实测其 dist 中无任何指向该文件的写操作），真正的写方是 Hermes 自身。

## 组件一览

| 组件 | 路径 | 作用 |
|---|---|---|
| 快照脚本 | `/home/user/gateway/scripts/snapshot-config.sh` | 检测哈希变化 → 落快照（未变化不落盘）+ 刷心跳 |
| 恢复脚本 | `/home/user/gateway/scripts/restore-config.sh` | `--list` / `--diff` / `--apply` / `--status` |
| cron 定义 | `/etc/cron.d/hermes-config-snapshot` | 每 10 分钟一次（独立文件，停用只需删它） |
| 快照目录 | `/home/user/gateway/data/hermes/config-snapshots/` | 目录 700 / 文件 600 root |
| 心跳 | `…/config-snapshots/.last-run` | **每次执行都刷新**（内容 = 时间 + 快照数） |
| 变更日志 | `…/config-snapshots/snapshots.log` | **只在内容变化时**追加一行 |
| 差异报告 | `docs/config-diff-baseline-vs-live.md` | 基线 vs live 逐段差异 |

## 覆盖对象与路径对照

| 视角 | config.yaml / .env |
|---|---|
| 宿主（真身） | `/home/user/gateway/data/hermes/{config.yaml,.env}` |
| hermes 容器 | `/home/agent/.hermes/{config.yaml,.env}` |
| hermes-webui 容器 | `/home/agent/.hermes/{config.yaml,.env}` 与 `/home/agent/.hermes-rt/{config.yaml,.env}` |

> 四个路径是**同一个 inode**（真实只有一份文件）。

## 策略

- **变化才落盘**：哈希未变不产生新快照（避免每 10 分钟灌垃圾）
- **保留最近 30 份**，日志自截断 200 行
- 退出码恒 0（不触发 cron 错误邮件）
- **不联网、不需要任何凭据、不调用任何模型** → 单次实测约 **22 毫秒**
- 心跳与日志的分工：**心跳 = "跑没跑"的证据**；**日志 = "内容变没变"的证据**

## 日常用法

```bash
cd /home/user/gateway
cat data/hermes/config-snapshots/.last-run     # 最近一次执行时间 + 快照数（10 分钟内为新鲜）
scripts/restore-config.sh --status             # live 是否被改 / 有没有丢段
scripts/restore-config.sh --list [.env]        # 所有快照（时间 / 大小 / 段数）
scripts/restore-config.sh --diff <快照>         # 与 live 逐段对比（缺哪些段、多哪些段）
scripts/restore-config.sh --apply <快照>        # 秒回滚（先自动留 pre-restore 副本）
```

## 验收（含"cron 最小环境"自测）

```bash
cat /etc/cron.d/hermes-config-snapshot                      # cron 定义在位
stat -c '%A %U:%G' data/hermes/config-snapshots             # drwx------ root:root
systemctl is-active cron                                    # active
journalctl -u cron --since "-15 min" | grep hermes-config   # 有 CMD 记录 = 真的在跑

# 模拟 cron 最小环境（只给 cron.d 里声明的 SHELL/PATH），验证不依赖登录环境
rm -f data/hermes/config-snapshots/.last-run
env -i SHELL=/bin/bash PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /home/user/gateway/scripts/snapshot-config.sh; echo "退出码 $?"
stat -c %y data/hermes/config-snapshots/.last-run           # 心跳已刷新
```

## 三条红线

1. **快照含明文密钥**（`config.yaml` 的 `ak_…`/`sk-…`、`.env` 的 QDRANT/SEARXNG key）
   → 目录 700、文件 600，**永远不要推进任何 git 仓库**。
2. `--apply` 会先写 `config.yaml.pre-restore-<时间戳>`；恢复后**必须成对重启容器**才生效
   （`docker stop hermes hermes-webui && docker start hermes hermes-webui`）。
3. 恢复前若发现快照内容可疑（例如基线是数日前的状态），先 `--diff` 看一眼，**不要盲 apply**。

## 已知限制

- 只覆盖 `config.yaml` 与 `.env`；宿主其他脚本 / crontab / compose 未纳入
- 快照是**同刻全量**而非增量 → 30 份约 160KB（可忽略）
- 掉段目前靠 `--status` 人工查看；可选增强：在 cron 内检测段数下降并写告警日志

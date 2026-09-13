# 方案 B′ 改造清单：拆「状态」不分「内容」

> **实施状态（2026-09-12）**：第 1.1 / 1.2 / 1.3 节已落地到 `docker-compose.yml`
> （备份 `docker-compose.yml.bak-bprime-20260912-195031`，行数 1092 → 1123）；
> `docker compose config -q` 通过，16 个共享源路径全部存在，17 个目标挂载解析正确。
> **尚未重启容器**——第 2 节的成对停启与第 3 节验收待执行。

> 目标：让 `state.db`（连同 logs / lock / 运行态 DB）在 webui 容器内成为**单写者**，从架构上根除 WAL 换代冲突；
> 不变量：**记忆、技能、配置、人设、凭据、定时任务仍是同一份**，且 hermes（大脑）容器**完全不动**。

---

## 0. 原理（已实测确认，非推断）

| 事实 | 证据 |
|---|---|
| Ekko 服务端解析 Hermes 家目录时**优先读 `HERMES_HOME`** | `function su(){if(process.env.HERMES_HOME)return resolve(process.env.HERMES_HOME);...return resolve(homedir(),".hermes")}` |
| `state.db` 路径就是 `join(su(),"state.db")` | `function no(){return join(Vs(),"state.db")}`，`Vs()`→`qn()`→`su()` |
| webui 容器里唯一持有 `state.db` 的是 bridge，且它继承容器 env | `pid=90 /opt/hermes/.venv/bin/python3 /app/dist/server/agent-bridge/python/hermes_bridge.py … HERMES_HOME=/home/agent/.hermes` |
| 记忆是**文件**且有跨进程排他锁 | `memories/MEMORY.md`；`MemoryStore._file_lock()` → `fcntl.flock(LOCK_EX)` on `<file>.lock` + `atomic_write_text` |
| `state.db` 里**没有记忆表** | 44 张表全为 `sessions/messages/messages_fts*/hosted_room*/gateway_*` 等运行态 |

结论：**改一个环境变量就能改道；共享内容靠逐项挂载即可，不需要牺牲记忆与技能。**

---

## 1. 改造点（3 处，约 30 行；只改 `docker-compose.yml`）

### 1.1 新增运行时卷（顶层 `volumes:` 段，插在第 1024 行之后）

```yaml
  hermes_runtime_volume:
    name: hermes_runtime
    driver: local
    driver_opts:
      type: none
      device: ${PWD}/data/hermes-runtime
      o: bind
```

### 1.2 webui 服务：环境变量改道（第 781 行）

```diff
-      - HERMES_HOME=/home/agent/.hermes
+      # B′：webui 使用独立「状态家」，内容类由下面 1.3 的逐项挂载共享
+      - HERMES_HOME=/home/agent/.hermes-rt
```

### 1.3 webui 服务：挂载（第 762–776 区段）

保留原有 `hermes_data_volume:/home/agent/.hermes` 不动（Ekko 有 `$HOME/.hermes` 回落探测路径需要它），新增：

```yaml
      # ===== B′：运行时家（只放状态类，Hermes 自动创建）=====
      - hermes_runtime_volume:/home/agent/.hermes-rt

      # ===== B′：共享「内容类」——读写穿透到共享真源 =====
      - ${PWD}/data/hermes/memories:/home/agent/.hermes-rt/memories
      - ${PWD}/data/hermes/skills:/home/agent/.hermes-rt/skills
      - ${PWD}/data/hermes/plugins:/home/agent/.hermes-rt/plugins
      - ${PWD}/data/hermes/hooks:/home/agent/.hermes-rt/hooks
      - ${PWD}/data/hermes/mcp:/home/agent/.hermes-rt/mcp
      - ${PWD}/data/hermes/bin:/home/agent/.hermes-rt/bin
      - ${PWD}/data/hermes/cron:/home/agent/.hermes-rt/cron
      - ${PWD}/data/hermes/shared:/home/agent/.hermes-rt/shared
      - ${PWD}/data/hermes/wisdom:/home/agent/.hermes-rt/wisdom
      - ${PWD}/data/hermes/workspace:/home/agent/.hermes-rt/workspace
      - ${PWD}/data/hermes/SOUL.md:/home/agent/.hermes-rt/SOUL.md
      - ${PWD}/data/hermes/config.yaml:/home/agent/.hermes-rt/config.yaml
      - ${PWD}/data/hermes/.env:/home/agent/.hermes-rt/.env
      - ${PWD}/data/hermes/auth.json:/home/agent/.hermes-rt/auth.json
      - ${PWD}/data/hermes/auth.lock:/home/agent/.hermes-rt/auth.lock
      - ${PWD}/data/hermes/install_id:/home/agent/.hermes-rt/install_id
```

**两条硬规则**
1. **锁必须跟它保护的文件一起共享**（`auth.lock` ↔ `auth.json`；`memories/MEMORY.md.lock` 天然在 `memories/` 内 ✅）。锁分开 = 无锁。
2. `hermes_data_volume` **保持挂载且保持 rw**：Ekko 的 `$HOME/.hermes/...` 探测（agent-browser、hermes-agent root）与 1 处前端资源依赖它。

### 1.4 明确不共享（留在 `/home/agent/.hermes-rt` 本地，由 Hermes 自行创建）

```
state.db  state.db-wal  state.db-shm  state.db.auto-maintenance.lock
shared-state.db*  response_store.db*  runs_idempotency.db*  kanban.db*  kanban.db.*.lock
logs/  sessions/  state/  pending/  pending_messages/  pulse/  spawn-ledger.json
sandboxes/  platforms/  pairing/  pki/  channel_directory.json
gateway.lock  gateway.pid  gateway.sock  gateway_state.json  gateway-starts.log
cache/  audio_cache/  image_cache/  google-chrome-for-testing/  models_dev_cache.*
.mcp-discovery.lock  .sync.lock  .curator_backups/
```

> 逃逸口：实施后若发现某项两侧必须一致（例如某个新目录），按 1.3 的写法**加一行挂载**即可，无需改脚本。

---

## 2. 执行步骤

> ⚠️ 禁止 `docker kill`；停启一律**成对**。

```bash
cd /home/user/gateway

# 1) 备份 + 建目录
cp docker-compose.yml docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)
mkdir -p data/hermes-runtime && chmod 700 data/hermes-runtime

# 2) 按 1.1 / 1.2 / 1.3 改 docker-compose.yml

# 3) 语法与解析校验
docker compose config -q && echo COMPOSE_OK
docker compose config | grep -n "hermes-rt" | head

# 4) 成对停机
docker stop hermes hermes-webui

# 5) 可选：给 web 侧留一份历史快照（此刻两侧都无写者，快照安全）
cp -a data/hermes/state.db data/hermes/state.db-wal data/hermes/state.db-shm data/hermes-runtime/
#    不要复制 state.db.retired-wal-* 目录（那是 WAL 事故现场，只做归档）

# 6) 成对启动
docker start hermes hermes-webui && sleep 20
docker ps --format '{{.Names}}\t{{.Status}}' | grep hermes
```

---

## 3. 验收（逐条命令）

| # | 检查 | 命令 | 期望 |
|---|---|---|---|
| 1 | 改道生效 | `docker exec hermes-webui printenv HERMES_HOME` | `/home/agent/.hermes-rt` |
| 2 | 记忆同一份 | `docker exec hermes md5sum /home/agent/.hermes/memories/MEMORY.md` vs `docker exec hermes-webui md5sum /home/agent/.hermes-rt/memories/MEMORY.md` | md5 一致 |
| 3 | 技能同一套 | `docker exec hermes-webui bash -c 'find /home/agent/.hermes-rt/skills -name SKILL.md \| wc -l'` | `401`（与脑侧一致） |
| 4 | state.db 单写者 | `docker exec hermes-webui bash -c 'for p in /proc/[0-9]*; do ls -l $p/fd 2>/dev/null \| grep -q state.db && tr "\0" " " < $p/cmdline; done'` | 只见 `.hermes-rt/state.db`，**无** `.hermes/state.db` |
| 5 | 记忆双向互通 | 网页里让 agent 记一条 → `docker exec hermes tail -3 /home/agent/.hermes/memories/MEMORY.md` | 新条目出现在脑侧 |
| 6 | cron 仍可被调度 | 网页里建一个定时任务 → `docker exec hermes ls -l /home/agent/.hermes/cron/` | 文件出现在脑侧 |
| 7 | **冲突面归零** | **单独**重启 webui（`docker stop hermes-webui && docker start hermes-webui`，故意复现旧复发路径）后：`docker exec hermes grep -c "Refusing to open or write" /home/agent/.hermes/logs/errors.log` | 恒为 `4`（不新增） |
| 8 | 无残留 inode 持有 | 两容器各跑 `find /proc/*/fd -lname "*state.db*(deleted)*" \| wc -l` | `0 0` |

---

## 4. 回滚（1 分钟，无数据风险）

```bash
cd /home/user/gateway
docker stop hermes hermes-webui                      # 成对停
cp docker-compose.yml.bak-<时间戳> docker-compose.yml # 或手工把 HERMES_HOME 改回并注释 1.3 新增行
docker start hermes hermes-webui
```

共享真源 `data/hermes` **全程未被搬迁**，故回滚不动任何数据；`data/hermes-runtime` 可保留或删除。

---

## 5. 必须同步的文档与脚本（否则下次重建会退回旧拓扑）

- [ ] `REBUILD-CHECKLIST.md`：新增「卷拓扑」一节，写明 HERMES_HOME 分道 + 共享/隔离清单
- [x] `scripts/restart.sh`：第 10 行改为成对重启（✅ 已完成）（**即使上了 B′ 也保留这条纪律**：单容器重启仍会踩 `shared-state.db` 等其余运行态）
  ```bash
  docker stop hermes hermes-webui && sleep 3 && docker start hermes hermes-webui
  ```
- [ ] `README-hermes-selfhost-infra.md`：补 §卷拓扑，说明哪些共用、哪些分开、为什么

---

## 6. 已知代价与遗留风险

| 项 | 说明 |
|---|---|
| **跨端会话检索分家** | 脑侧 `session_search` / `hermes sessions list` 不再覆盖网页会话（第 2 步的种子复制只是快照，之后两边各自独立）。网页 UI 对话不受影响（Ekko 自有 `hermes-web-ui.db`） |
| Ekko 前端硬编码 | `/app/dist/client/assets/js/AgentManagerView-*.js` 中显示 `/home/agent/.hermes`，仅展示用途，无功能影响 |
| 升级 webui 镜像后需复查 | 其 `su()` 若改成 `$HOME/.hermes` 优先，B′ 即失效。复查命令：`docker exec hermes-webui grep -oE "HERMES_HOME.{0,40}" /app/dist/server/index.js \| head` |
| 首次启动是空库 | 若不执行第 2 步的第 5 项，web 侧会话列表从零开始（记忆与技能不受影响） |

---

## 7. 与方案 A 的关系

方案 A（成对重启）**不是被替代**，而是被降级为「兜底纪律」：
- B′ 消除的是 `state.db` 这一类冲突；
- 目录内其余运行态 DB（`shared-state.db`、`response_store.db`、`kanban.db`…）仍建议成对重启；
- 两者叠加 = 既有纪律、又无结构隐患。

---

## 8. 关联变更（2026-09-13）

- **共享工作卷** `hermes_workspace` → 容器 `/workspace`、宿主软链 `/workspace`：见 `docs/work-volume.md`
- **`terminal.cwd: /workspace`**：借工作卷统一了三视角工作目录（容器 hermes / 容器 hermes-webui / 宿主），消除了「单一 cwd 无法同时适配两种后端」的矛盾；详见 `docs/work-volume.md`
- 两者均已写入 `REBUILD-CHECKLIST.md §1.5`（重建后必查）

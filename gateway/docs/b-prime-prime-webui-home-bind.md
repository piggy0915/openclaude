# B″″：webui 运行时家（HERMES_HOME）改为宿主目录 bind

> 状态：**已上线并验证通过**（2026-09-14 13:02 成对重启后实测）
> 现役：`docker-compose.yml` 第 775 行 `${PWD}/data/.hermes-rt:/home/agent/.hermes-rt`
> 回滚件：`docker-compose.yml.rollback-bpprime-20260914`（`docker compose -f ... config -q` 已校验通过）

## 1. 故障与根因

现象：在网页端保存 provider / key 设置时报 **500，`EBUSY: resource busy or locked`**。

根因不是「卷」，而是**单文件 bind**：

| 挂法 | 目标文件 | `os.replace(tmp, file)`（Hermes 原子写） |
|---|---|---|
| `dir:/path/dir` | 目录内普通文件 | 成功（换 inode） |
| `file:/path/file` | **文件本身就是挂载点** | 永远 `EBUSY`（不能 rename 覆盖挂载点） |

B″ 期间 webui 的 `.env / config.yaml / SOUL.md / auth.json / auth.lock / install_id` 全是单文件 bind，
所以任何一次配置落盘都会 500。**「每个容器各自可写副本」的正确载体只能是目录，不能是文件。**

## 2. 设计（B″″）

- webui 顶级家：命名卷 `hermes_runtime_volume` -> **宿主目录 bind `${PWD}/data/.hermes-rt`**；
  顶层 6 个单文件 bind **全部删除** -> 它们变成目录内普通文件，原子写恢复正常。
- 子目录级 bind **保留**（目录级无 EBUSY）：`memories / skills / plugins / hooks / mcp / bin / cron / shared / wisdom / workspace` 仍与脑侧共享真源 `data/hermes`。
- 脑侧（hermes 容器）不动：它用 `hermes_data` 目录卷，`.env` 本就是卷内普通文件。
- 纪律：**禁止再对 `HERMES_HOME` 顶层文件做单文件 bind**（新增挂载需 `docker compose up -d` 重建，`restart` 不生效）。

## 3. 已执行的迁移

    cd /home/user/gateway
    mkdir -p data/.hermes-rt
    # 旧运行时内容迁入 + 顶层配置文件按真源播种（覆盖卷里 0 字节的影子文件）
    cp -a ... data/.hermes-rt/
    chown -R 10000:10000 data/.hermes-rt

## 4. 验证证据（重启后实测）

| 检查 | 结果 |
|---|---|
| 挂载类型 | `bind | /home/user/gateway/data/.hermes-rt -> /home/agent/.hermes-rt | rw=true` 通过 |
| 单文件挂载点 | `mountinfo` 只剩目录级（`.hermes-rt` 及 10 个子目录），**无 `.env/config.yaml/SOUL.md/auth.json` 单文件挂载** 通过 |
| **原子写实测** | 容器内对 `.env / config.yaml / auth.json / install_id / SOUL.md` 逐个 `os.replace(tmp,target)`：**5/5 成功，内容逐字节一致，inode 变更**（=真原子替换）通过 |
| 启动后日志 | `server.log` 无 `EBUSY`、无 500 通过 |
| 文件形态 | 顶层五文件 = 普通文件，`hermes:hermes 644` 通过 |
| 会话数据 | 新库 2386 条 >= 旧运行时库 2328 条；本会话 67 -> 125 条，**无丢失** 通过 |
| WAL 体检 | 两库各 1 写者、无已删除 inode、无新告警、归档 <= 活库 通过 |
| 探活 | webui 6060 -> 200；gateway 8642 `/health` -> 200；qdrant 401（需 key，正常）；6 个 MCP 进程在起 通过 |

## 5. 副作用与遗留（需知）

1. **配置分家**：webui 的 `config.yaml / .env / auth.json` 现在是**自己的副本**（内容与 `data/hermes/` 一致，但物理独立）。
   以后网页端改 provider/key 只影响 webui 侧，脑侧要同步改 `data/hermes/`。
   -- 这是 B″″ 的必然代价，换来「两边都能原子写、互不干扰」。
2. **属主漂移（隐患）**：webui 容器以 **root** 运行，它写的共享文件是 `root:root 0600`
   （实例：`data/hermes/skills/.usage.json`）。脑侧进程当前**全为 root**，所以暂时无故障
   （脑侧 `errors.log` 里 `Permission denied` = 0）；但任何以 uid 10000 运行的进程读不到
   -- 已实测：`docker exec -u 10000 hermes-webui head .../skills/.usage.json` -> `Permission denied`。
   修法二选一：(1) compose 给 webui 加 `user: "10000:10000"`；(2) 宿主 `setfacl -R -m u:10000:rwX` + 默认 ACL。
3. **残留**：`hermes_runtime_volume` 定义（第 1051 行）已无人引用；`data/hermes-runtime/`（含迁移前的 state.db 22MB）
   作为回滚样本保留，确认稳定后可归档。

## 6. 回滚

    cd /home/user/gateway
    docker compose -f docker-compose.yml.rollback-bpprime-20260914 config -q
    cp docker-compose.yml docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)
    cp docker-compose.yml.rollback-bpprime-20260914 docker-compose.yml
    docker compose up -d hermes-webui    # 成对重启：hermes-webui + hermes

注意：回滚会退回**单文件 bind**（EBUSY 复现）与命名卷 `data/hermes-runtime`，仅作应急。

## 7. 收尾（09-14 下午，已执行并实测）

| 动作 | 结果 |
|---|---|
| **应用层写入验证** | 13:35 应用自身完成一次原子写：`config.yaml`(+`.bak`)、`.env`(+`.bak`)、`auth.json`(+`.bak`) 全部重写成功，**无 EBUSY、无 500**；顶层段数 16 = 16（未重演 `save_config` 丢段 bug）。差异仅为 YAML 引号风格、`connect_timeout: 15.0→15`、注释块，以及 `api_mode: codex_responses→chat_completions` |
| **属主归一化** | 新增 `scripts/normalize-shared-ownership.sh` + `/etc/cron.d/hermes-ownership-normalize`（每 15 分钟，root 属主项归一 10000:10000，幂等）。首次运行修正 37 项；复测 `docker exec -u 10000 …` 读 `.usage.json`/`MEMORY.md`/`config.yaml` 全部可读 |
| **快照覆盖扩展** | `scripts/snapshot-config.sh` 增加 `data/.hermes-rt` 的 `config.yaml/.env/auth.json`（快照前缀 `rt-`），首次运行已落 3 份快照 |
| **TTS 复测** | 重启后生成成功：`data/.hermes-rt/cache/audio/tts_20260914_055158_075610.mp3`（50400 字节，MPEG ADTS layer III，24kHz mono） |
| **用户侧验收（最终）** | 网页端保存 provider/key **成功、不再报 500**（2026-09-14 14:01 用户确认）。落盘足迹：`data/.hermes-rt/auth.json` 14:01:33 原地重写（inode 不变、属主 10000 保留），`hermes-web-ui/profiles/default/.model-run-token` 14:01:35 紧随其后；`server.log` 全量 `EBUSY` = 0、`500` = 0 |
| **属主机制实测修正** | 容器内进程**全部以 root 运行**（`ps` 无 uid 10000 进程）；**新建**文件是 `root:root 0600`（如 `skills/.usage.json`），而**原地重写**已有文件保留原属主（auth.json 保存前后都是 10000:10000 600）。⇒ root 属主文件会持续零星产生，`normalize-shared-ownership.sh` + 15 分钟 cron 是长期兜底，**不要删** |
| **残留处置** | `hermes_runtime_volume` 定义**保留**（回滚件 `docker-compose.yml.rollback-bpprime-20260914` 依赖它，故不删）；`data/hermes-runtime/` 保留作回滚样本 |

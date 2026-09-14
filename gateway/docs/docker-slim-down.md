# Docker 瘦身清单（/var 86% → 目标 60% 以下）

> 生成：2026-09-13。依据：`docker system df -v` + 逐容器实测（**不是经验值**）。
> Docker Root Dir = `/var/lib/docker`（overlayfs / containerd snapshotter），`/var` 73G 已用 59G（86%），余 11G。

## 0. 先纠正一个读数陷阱

`du -sh /var/lib` 会报 **102G**（大于分区容量）—— 这是 overlay/containerd 快照的硬链接重复计数。
**只信 `df` 与 `docker system df`**，不要据此判断。

真实占用（`docker system df`）：

| 类型 | 总量 | 可回收 |
|---|---|---|
| Images（25 个） | 31.47 GB | 1.428 GB (4%) |
| Containers（23 个，可写层） | 12.22 GB | 0 |
| Build Cache（222 条） | **20.34 GB** | **6.814 GB** |
| Local Volumes | 2.2 MB | 113 kB |

---

## 1. 第一档：零风险，立即做（预期回收 ≈ 8.4 GB）

| # | 动作 | 命令 | 回收 | 说明 |
|---|---|---|---|---|
| 1 | 清无引用构建缓存 | `docker builder prune -f` | ≈ 6.8 GB | 保留在用缓存，不影响下次重建速度 |
| 2 | 删废弃旧基座 | `docker rmi nousresearch/hermes-agent:v2026.9.11` | ≈ 0.61 GB | `Dockerfile.base` 已改用 `:main`，此镜像 0 容器引用（UNIQUE 610.6MB） |
| 3 | 删未使用小镜像 | `docker rmi alpine:latest busybox:latest` | ≈ 0.01 GB | 0 容器引用；~~`freellmapi`~~ **用户指定保留**（UNIQUE 809.9MB，见 §8） |
| 4 | 收缩 journal | `journalctl --vacuum-size=100M` | ≈ 0.18 GB | 当前 277MB |
| 5 | 悬空镜像 | `docker image prune -f` | 0 | 实测当前悬空 0 个，留作例行 |

> 执行后核对：`df -h /var` + `docker system df`

---

## 2. 第二档：需要取舍（预期再回收 ≈ 13.5 GB）

| # | 动作 | 命令 | 回收 | 代价 |
|---|---|---|---|---|
| 6 | **清空全部构建缓存** | `docker builder prune -af` | ≈ 13.5 GB（合计 20.3 GB） | 下次重建 base 要重跑 apt/pip/npm，**耗时显著增加**（首次约 1h+） |
| 6b | 折中：只清 7 天以上缓存 | `docker buildx prune -f --filter until=168h` | 视缓存年龄 | 影响小，建议纳入例行 |
| 7 | 删除未用的小语言镜像 | `docker rmi python:3.14-slim` | 0.18 GB | 先确认没有栈在用（实测仅 obsidian-sync 用 3.14-slim → **勿删**） |

> **建议**：单做第 6b 项（每周一次，低代价）；只有确实需要大空间时再做 6。

---

## 3. 第三档：最大单笔 —— `semantica-poc` 容器可写层 11.2 GB

**实测画像**

| 项 | 值 |
|---|---|
| 镜像 | `python:3.11-slim`（`docker run` 直起，**无 compose 归属**） |
| 创建 / 状态 | 2026-09-06 创建，`Up 6 days`，**无端口、无挂载** |
| 可写层 | **11.2 GB** |
| 构成 | `/usr` 7.3G（pip 装的 torch + nvidia CUDA 库）+ `/root` 3.4G（**pip http 缓存**，含 3 个 400–550MB 的 `.body` 文件） |
| 健康度 | `docker logs` 取不到日志（json.log 已丢失）→ 已是"半死"状态 |

**三种处置（按激进程度）**

| 方案 | 命令 | 回收 | 风险 |
|---|---|---|---|
| A. 只清它的 pip 缓存 | `docker exec semantica-poc pip cache purge` | ≈ 1.5–3 GB | 零（缓存可重建） |
| B. 停止（保留现场） | `docker stop semantica-poc` | 0（可写层仍占） | 零；停 6 天未用说明大概率可弃 |
| C. 彻底删除 | `docker rm semantica-poc` | **≈ 11.2 GB** | 不可逆；请确认 POC 结论已落档 |

> **推荐**：先 A（零风险拿 2–3G）→ 一周后仍无用则 C。
> 提醒：它是**容器可写层**而非镜像层，`docker image prune` 清不掉，只能删容器。

---

## 4. 绝对不要删（红线）

| 对象 | 原因 |
|---|---|
| `hermes-base:main` | 两个子镜像的构建父体（UNIQUE 仅 60 kB，删了不省空间） |
| `nousresearch/hermes-agent:main` | 当前 `Dockerfile.base` 的 FROM 源；**Docker Hub 目前不可达**，删了下次重建无法拉取 |
| `hermes-agent:main` / `hermes-web-ui:0.7.21` | 运行中的两个容器 |
| dify / obsidian / deeptutor / llama.cpp / qdrant / searxng / postgres / redis 等 | 其它栈运行中（合计约 14 GB，属正常开销） |
| `data/` 下任何东西（含 `config-snapshots/`） | 数据卷与配置快照，**不在 docker prune 范围内，别手动清** |

---

## 5. 防止重新长回来（每次重建后的固定动作）

```bash
# 重建完成后执行（约 10 秒，回收 2–7 GB/次）
docker builder prune -f && docker image prune -f
df -h /var | tail -1
```

**为什么会长**：每次 `docker compose build` 都会往 build cache 塞新层（本次实测 222 条 / 20.34 GB，其中 44 小时前的记录居多）。
**已经不会再长的部分**：三镜像分层（base → agent/web-ui）让每次重建的**独有层**只剩 ~2.2 GB
（对比：`hermes-web-ui:0.7.21` UNIQUE 2.211 GB、SHARED 8.732 GB；单层方案时代每次重建要新增 8–10 GB）。

**可选加固**：把每周一次的 `docker buildx prune -f --filter until=168h` 加进宿主 cron。

---

## 6. 验收

```bash
docker system df                    # Build Cache 应显著下降
df -h /var                          # 目标准则：≥ 25G 可用（<70%）
docker ps --format '{{.Names}}\t{{.Status}}' | grep hermes   # 两个容器仍 healthy
docker exec hermes bash -c 'grep -c "Refusing to open or write" /home/agent/.hermes/logs/errors.log'  # 仍为 4
```

## 7. 预期总账

| 执行范围 | 回收 | 累计可用空间 |
|---|---|---|
| 第一档 | ≈ 8.4 GB | 11G → **≈ 19 GB**（74% → 约 70%） |
| 第一 + 第二档 | ≈ 21.9 GB | 11G → **≈ 33 GB**（→ 约 55%） |
| 第一 + 第二 + 第三档(C) | ≈ 33 GB | 11G → **≈ 44 GB**（→ 约 40%） |

---

## 8. 执行记录：第一档（2026-09-13）

**命令前置检查**：三个待删镜像均 0 容器引用；仓库（Dockerfile/compose/build.sh）无 `v2026.9.11` 引用 → 放行。

| 动作 | 实际回收 |
|---|---|
| `docker builder prune -f` | **6.772 GB**（缓存条目 222 → 159） |
| `docker rmi nousresearch/hermes-agent:v2026.9.11` | 610.6 MB（UNIQUE） |
| `docker rmi alpine:latest busybox:latest` | ≈ 7 MB（共享层仍被 nginx 等引用，实际释放有限） |
| `journalctl --vacuum-size=100M` | 186 MB（333.4M → 147.4M） |

**结果**

| 指标 | 前 | 后 |
|---|---|---|
| `/var` 已用 | 59 G (86%) | **53 G (76%)** |
| `/var` 可用 | 11 G | **17 G** |
| Images | 25 个 / 31.47 GB | 22 个 / 30.86 GB |
| Build Cache | 20.34 GB | 13.57 GB（可回收仅剩 165 MB） |

**保留确认（执行后复查在位）**：`hermes-base:main`、`nousresearch/hermes-agent:main`、`hermes-agent:main`、`hermes-web-ui:0.7.21`、`ghcr.io/tashfeenahmed/freellmapi:main` ✅

**不变量复查**：两容器 healthy（Up）、gateway uid 0、socat 6060 = 200、WAL 保护计数仍 4、配置快照心跳正常 ✅

**剩余可回收空间**（按需再做）
- `docker builder prune -af` → ≈ 13.4 GB（代价：下次重建 base 重跑 apt/pip/npm）
- `semantica-poc` 容器 → ≈ 11.2 GB（第三档，见 §3）

---

## 9. 执行记录：磁盘重构后的收尾清理（2026-09-13 晚）

背景：新增 127G 数据盘并把 Docker 整体迁到 `/srv/docker`（`data-root` + containerd `root`），
但**搬迁前的旧副本 `/var/lib/containerd` 仍占 52G** —— 这是"迁移后必须收尾"的典型坑。

| # | 动作 | 释放 | 备注 |
|---|---|---|---|
| 1 | `rm -rf /var/lib/containerd` | **52 G** | 热删，**未停任何容器**（判据：0 挂载引用 + 0 进程 fd + 0 进程 cwd；实耗 10.7s） |
| 2 | `docker rm semantica-poc`（原 Exited 137） | **11.2 G** | 容器可写层回收；`docker system df` 的 Containers 由 12.22G → 1.04G |
| 3 | `docker builder prune -f` | **5.45 G** | 构建缓存 13.49G → 8.04G |

**结果**

| 指标 | 清理前 | 清理后 |
|---|---|---|
| `/var` | 53 G 已用 / **76%** | **548 M 已用 / 1%**（可用 69 G） |
| `/srv/docker`（新盘） | 52 G 已用 / 44% | 35 G 已用 / 30%（可用 84 G） |
| Docker 容器数据 | 12.22 G（11.18G 可回收） | **1.04 G（0 可回收）** |
| 构建缓存 | 13.49 G | 8.04 G |

**安全校验（删除前，须全为 0）**

```bash
grep -c "/var/lib/containerd" /proc/mounts                              # 0 挂载引用
for p in /proc/[0-9]*; do ls -l $p/fd | grep -c var/lib/containerd; done # 0 进程 fd
readlink /proc/*/cwd | grep -c /var/lib/containerd                      # 0 进程 cwd
grep -E '^root' /etc/containerd/config.toml                             # root = "/srv/docker/containerd"
grep -c "upperdir=/srv/docker" /proc/mounts                             # 22（live 层全在新盘）
```

**不变式复核**：22 个容器全部仍在运行、无异常退出；containerd 正常（1 主进程 + 22 shim）；
镜像 22 个仍可读；hermes healthy / webui running / WAL 保护计数仍 4 / socat 200 / 工作卷 7 条目；配置快照 cron 正常。

> **教训（已写入 REBUILD-CHECKLIST）**：迁移 Docker/containerd 数据目录后，**必须单独确认旧目录已删除**
> —— `docker system df` 只统计当前 `data-root`，**看不到旧副本的占用**，`/var` 会被静默占满。

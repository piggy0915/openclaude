# containerd root 迁移（Docker 数据搬迁的"缺失那一半"）

> 2026-09-13 排查结论。**重要**：只改 docker 的 `data-root` 搬不走真正的大头。

## 问题：`/srv/docker` 空着，`/var` 满着

用户在 Hyper-V 新建 125G 虚拟盘（`/dev/sdb`，ext4，LABEL=`docker`）挂到 `/srv/docker`，并把 docker `data-root` 指过去。**结果几乎没省下空间**：

| 指标 | 值 | 说明 |
|---|---|---|
| `docker info` → Docker Root Dir | `/srv/docker` | 看起来搬成功了 |
| `/srv/docker` 实体占用 | **74 M** | 只有 docker 自己的元数据（containers/network/volumes/buildkit） |
| `/var/lib/containerd` | **51.8 G** | 43G snapshotter + 9G content store，**435 个快照** |
| overlay 挂载 `lowerdir` 指向 | **20/22 指向 `/var/lib/containerd`**，0 个指向 `/srv/docker` | 决定性证据 |
| `docker info` → driver-type | `io.containerd.snapshotter.v1` | 用的是 **containerd snapshotter** |

**根因**：这套 Docker 用 containerd snapshotter。在此模式下：

- 镜像层 / 容器可写层 / 构建缓存 都归 **系统 containerd** 管；
- containerd 的 root 由 `/etc/containerd/config.toml` 的 `root` 决定，**默认 `/var/lib/containerd`**；
- `docker` 的 `data-root` 只管 docker 自己的元数据，**与层数据无关**。

所以「把 data-root 指到新盘」= 搬了账本、没搬仓库。

## 修复：把 containerd root 也迁到新盘

```bash
cd /home/user/gateway

# ① 预览（不改动）
scripts/move-containerd-root.sh --check

# ② 执行（会短暂中断所有容器，含 hermes-webui —— 用 nohup 让脚本在会话断开后继续）
nohup bash scripts/move-containerd-root.sh > /root/containerd-move.log 2>&1 &
tail -f /root/containerd-move.log

# ③ 如需回滚（配置还原 + 重启，秒回；数据一直没删）
scripts/move-containerd-root.sh --rollback
```

脚本做的事：

| 步骤 | 动作 |
|---|---|
| 0 | 前置检查：目标已挂载、空间 ≥ 源 ×1.1、记录基线（镜像/容器/快照数） |
| 1 | `systemctl stop docker docker.socket containerd` |
| 2 | 备份 `config.toml` → `.bak-<ts>`，写入 `root = "/srv/docker/containerd"` |
| 3 | `rsync -aHAX --numeric-ids /var/lib/containerd/ /srv/docker/containerd/`（**源保留**） |
| 4 | 校验大小与快照数（不一致则自动回滚并退出） |
| 5 | `systemctl start containerd && systemctl start docker` |
| 6 | 复核镜像/容器数、overlay `lowerdir` 是否已指向新盘 |

**安全设计**
- 用 **COPY 不用 MOVE**：旧数据原地保留 → `--rollback` 只需还原配置 + 重启，无需再拷 52G。
- 任一步失败自动还原配置并重启。
- 迁移后**旧目录不自动删除**，观察 2–3 天确认无误再 `rm -rf /var/lib/containerd`。

## 预期结果

| 指标 | 现在 | 迁移后 |
|---|---|---|
| `/var` 已用 | 53 G（76%） | **≈ 1–2 G（≈3%）** |
| `/srv/docker` 已用 | 74 M | ≈ 52 G（125G 盘中约 42%） |
| 容器 / 镜像 | 22 / 23 | 不变 |

## 验收

```bash
df -hT /var /srv/docker
docker ps -a | wc -l ; docker images | wc -l          # 与迁移前一致
mount | grep -c "lowerdir=/srv/docker/containerd"     # 应 ≈ 容器数
docker system df                                      # 镜像/缓存账目不变
docker ps --format '{{.Names}}\t{{.Status}}' | grep hermes    # 两容器 healthy
docker exec hermes bash -c 'grep -c "Refusing to open or write" /home/agent/.hermes/logs/errors.log'   # 仍为 4
```

## 附带说明

- `/var/lib/docker`（53 M 残留）在确认新结构稳定后可一并删除。
- 迁移完成后 `/var` 只剩 ~1–2 G 使用量，**原本要扩 sda/LV 的计划不再必要**（`grow-var.sh` / `add-disk-to-vg.sh` 留作备用）。

---

# 手工操作步骤（逐步执行，每步都带校验）

> 前提：**在宿主 shell 里执行**（不要在容器内）；`rsync` 那步 52G 要几分钟到十几分钟，
> 建议用 `screen`/`tmux`，或分步执行。改前基线清单已生成：
> `/root/containerd-move-before-images.txt`、`/root/containerd-move-before-containers.txt`

## 第 0 步：再确认一次前置条件

```bash
mountpoint -q /srv/docker && echo "新盘已挂载 ✅"
df -hT /srv/docker | tail -1                     # 可用应 ≈ 119G
du -xsh /var/lib/containerd                      # 源 ≈ 52G
pfgrep(){ :; }; pgrep -a containerd | head -3
```

## 第 1 步：停止 docker 与 containerd

```bash
systemctl stop docker docker.socket containerd
systemctl is-active containerd docker            # 两个都应输出 inactive
pgrep -a containerd-shim | head -3               # 应无输出（有残留 shim 会占着旧路径）
```

> 若仍有 `containerd-shim` 残留：等 10 秒再看；仍存在则**不要继续**，先查 `docker ps` 与 `journalctl -u docker -n 30`。

## 第 2 步：把 containerd 的 root 指向新盘

```bash
cp -a /etc/containerd/config.toml /etc/containerd/config.toml.bak-$(date +%Y%m%d-%H%M%S)
# 该文件第 17 行原本就是注释 '#root = "/var/lib/containerd"'，正好改成实际值
sed -i 's|^#root = "/var/lib/containerd"$|root = "/srv/docker/containerd"|' /etc/containerd/config.toml
grep -n '^root' /etc/containerd/config.toml      # 应输出: root = "/srv/docker/containerd"
```

> 该文件**没有任何 `[section]`**，`root` 作为顶层键放在哪都行；systemd 单元也没 `--root` 参数，所以配置生效。

## 第 3 步：拷贝数据（源保留不动）

```bash
mkdir -p /srv/docker/containerd
rsync -aHAX --numeric-ids --info=progress2 /var/lib/containerd/ /srv/docker/containerd/
```

⚠️ 两个路径**末尾的 `/` 都不能省**（表示拷贝"目录内容"）。

## 第 4 步：校验拷贝完整性（不通过就别往下走）

```bash
du -sx --block-size=1 /var/lib/containerd          | cut -f1   # 源字节
du -sx --block-size=1 /srv/docker/containerd      | cut -f1   # 目标字节（应 ≥ 源）
ls -1 /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/     | wc -l   # 435
ls -1 /srv/docker/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/ | wc -l   # 必须也是 435
```

## 第 5 步：启动服务

```bash
systemctl start containerd && sleep 3 && systemctl is-active containerd
systemctl start docker     && sleep 5 && systemctl is-active docker
docker info | grep "Docker Root Dir"              # /srv/docker（元数据）不变
```

## 第 6 步：验收（逐条对照）

```bash
docker ps -a --format '{{.Names}}'            | sort > /root/after-containers.txt
docker images --format '{{.Repository}}:{{.Tag}}' | sort > /root/after-images.txt
diff /root/containerd-move-before-containers.txt /root/after-containers.txt && echo "容器清单一致 ✅"
diff /root/containerd-move-before-images.txt     /root/after-images.txt     && echo "镜像清单一致 ✅"

mount | grep -c "lowerdir=/srv/docker/containerd"   # 应 ≈ 运行中容器数（22 左右）
mount | grep -c "lowerdir=/var/lib/containerd"      # 应为 0

df -hT /var /srv/docker                             # /var 应降到 1~2G 占用
docker ps --format '{{.Names}}	{{.Status}}' | grep hermes          # 两容器 healthy
docker exec hermes bash -c 'grep -c "Refusing to open or write" /home/agent/.hermes/logs/errors.log'   # 4
docker exec hermes-webui ls /workspace | head -3                    # 工作卷正常
docker exec hermes-webui printenv HERMES_HOME                       # /home/agent/.hermes-rt
```

## 回滚（任何一步不对就执行）

```bash
systemctl stop docker docker.socket containerd
cp -a /etc/containerd/config.toml.bak-<时间戳> /etc/containerd/config.toml
systemctl start containerd && systemctl start docker
```

**源数据一直在 `/var/lib/containerd` 未动** → 回滚即时生效，不需要再拷 52G。

## 清理（观察 2–3 天、确认一切正常后）

```bash
du -sh /var/lib/containerd /var/lib/docker      # 确认没有进程占用
rm -rf /var/lib/containerd /var/lib/docker
df -h /var                                      # 期望 ≈ 1–2G 已用
```

> 嫌麻烦也可以直接用脚本 `scripts/move-containerd-root.sh`（`--check` 预览 / `--rollback` 回滚），
> 它把上面 6 步连同校验、自动回滚都封装了。

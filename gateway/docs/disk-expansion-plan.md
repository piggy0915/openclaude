# 磁盘扩容方案（/var 77% → 目标 ≤60%）

> 生成：2026-09-13。数据来自 `df / lsblk / lvs / docker system df` 实测。

## 现状（关键事实）

| 项 | 值 |
|---|---|
| 虚拟化 | **Hyper-V**（`systemd-detect-virt = microsoft`，磁盘型号 `Msft Virtual Disk`） |
| 物理盘 | `sda` 256 G，**唯一一块**，全部划入 LVM |
| 卷组 | `zgjy-debian-vg` 254.09 G，**VFree 仅 1.56 G** ← 直接扩 /var 不够 |
| LV 布局 | root 37.25G(用 9.1G) / usr 37.25G(用 3.4G) / **var 74.5G(用 53G, 77%)** / opt 18.62G(用 5.5G) / home 70G(用 **2.4G**) / swap 14.9G(用 2G) |
| 内存 | 31 GiB，available 25 GiB |
| /var 构成 | `/var/lib/docker` **44 G** 占绝对大头（其余 log/cache/apt 合计 <400 M） |
| /home | 仅 2.4 G 已用，但**被运行中的容器占用**（qdrant/postgres/obsidian/hermes 等经 `data/*` 绑定） |
| Docker | root=/var/lib/docker，overlayfs(containerd)，daemon.json 已配镜像加速 + 日志上限 + `live-restore: true` |

> 📄 **相关文档**
> - `grow-var-howto.md` + `scripts/grow-var.sh`：**扩原盘**（sda 256G→更大），需先在宿主扩 VHDX / 删检查点
> - `add-new-disk-howto.md` + `scripts/add-disk-to-vg.sh`：**新增一块 VHDX** 并入卷组（热添加、免删检查点、零停机）
> - `docker-slim-down.md`：先瘦身（已执行第一档：/var 86% → 76%）

**结论一句话**：VFree 只剩 1.56 G，所以「直接 lvextend /var」不可行；要扩 /var 必须**从别处挪空间**或**给虚拟机加盘**。

---

## 方案 C（首选）：给 Hyper-V 虚拟磁盘扩容 —— 零停机、零搬迁

前提：Hyper-V 宿主所在物理盘还有空间。

```bash
# ① 宿主 Hyper-V 管理器：先删除该虚拟机的检查点（快照会阻止扩容）
#    编辑磁盘 → 展开（如 256G → 400G/512G，VHDX 支持在线扩容）
# ② 客户机内（shell 执行，无需重启）
echo 1 > /sys/class/block/sda/device/rescan
lsblk                       # 确认 sda 已变大
growpart /dev/sda 3         # 扩分区
pvresize /dev/sda3          # PV 变大 → VG 变大
lvextend -l +100%FREE /dev/zgjy-debian-vg/var
resize2fs /dev/zgjy-debian-vg/var     # ext4 在线扩容
df -h /var
```

- 收益：想要多少给多少；`/var` 从 77% 可降到 50% 以下
- 风险：**极低**（不动已有数据，全是在线操作）
- 停机：**0**
- 唯一前提：宿主有磁盘空间 + 先删检查点

---

## 方案 B（次选）：缩 swap 换给 /var —— 立刻可做，≈ +11 G

实测 swap 14.9 G 只用了 2 G，而内存 available 25 G，缩到 4 G 很安全。

```bash
# ① 留证据 + 记下 UUID（fstab 用它，mkswap 会改 UUID，必须沿用）
swapon --show; grep swap /etc/fstab
OLD_UUID=$(blkid -s UUID -o value /dev/zgjy-debian-vg/swap_1); echo "$OLD_UUID"

# ② 关 swap → 缩 LV → 重建 swap（复用原 UUID）→ 扩 /var
swapoff /dev/zgjy-debian-vg/swap_1
lvreduce -L 4G /dev/zgjy-debian-vg/swap_1
mkswap -U "$OLD_UUID" /dev/zgjy-debian-vg/swap_1
# ⚠ 若 fstab 有 LABEL 或 UUID 对应不上，先 mkswap 再核对 fstab

lvextend -l +100%FREE /dev/zgjy-debian-vg/var
resize2fs /dev/zgjy-debian-vg/var     # ext4 在线扩容，无需卸载
swapon -a
df -h /var; free -h
```

- 收益：**≈ +10.9 G** → /var 约 17 G → **28 G 可用（约 65%）**
- 风险：低。唯一风险是 swapoff 期间内存吃紧 OOM —— 当前 available 25 G，安全
- 停机：0（swap 是可选资源）

---

## 方案 A：缩 /home（70G→20G）换给 /var —— 收益最大（≈ +50 G），但要停机

```bash
# ⚠ 全程停机：/home 被 23 个容器的 data/* 绑定占用，必须先停 Docker
# ① 先备份 /home（仅 2.4 G，可放到 / 分区，那里有 26 G 空）
tar czf /root/home-backup-$(date +%Y%m%d).tgz -C / home/user 2>/dev/null
# ② 停栈 + 卸载
cd /home/user/gateway && docker compose stop        # 或 systemctl stop docker docker.socket containerd
umount /home
# ③ 先缩文件系统、再缩 LV（顺序不能反）+ 强行检查
e2fsck -f /dev/zgjy-debian-vg/home
resize2fs /dev/zgjy-debian-vg/home 20G
lvreduce -L 20G /dev/zgjy-debian-vg/home
# ④ 扩 /var
lvextend -l +100%FREE /dev/zgjy-debian-vg/var
resize2fs /dev/zgjy-debian-vg/var
# ⑤ 回挂 + 起栈
mount /home && docker compose up -d
```

- 收益：≈ +50 G（/var → 约 65 G 可用）
- 风险：**中**（ext4 收缩不可逆，出问题会丢 /home；**必须先备份并 e2fsck**）
- 停机：15–30 分钟（全栈停 + 缩容 + 起栈）

---

## 方案 D（替代思路）：不扩 /var，把 Docker 迁到 /home

`/home` 闲着 64 G，而 /var 的 53 G 里 44 G 是 Docker → 直接换家。

```bash
systemctl stop docker docker.socket containerd
rsync -aHAX --info=progress2 /var/lib/docker/ /home/docker/
# daemon.json 增加一行：  "data-root": "/home/docker",
systemctl start docker
docker info | grep "Docker Root Dir"    # 应显示 /home/docker
docker ps | wc -l                        # 容器应全部回来
```

- 效果：/var 53 G → **约 9 G**；/home 2.4 G → 约 46 G
- 风险：中（一次 20–40 分钟全栈停机 + 44 G 拷贝；数据不受损，可回滚——保留旧目录直到验证通过）
- 优点：不动 LVM，立即可用；`live-restore: true` 已在，重启 docker 不重启容器（但 stop 守护进程仍会停容器）

---

## 不可行 / 不推荐

| 项 | 原因 |
|---|---|
| 直接 `lvextend /var` | VFree 仅 1.56 G |
| 缩 `/usr`（空 32 G）或 `/`（空 26 G） | 运行中无法卸载 `/usr` 和 `/`；需救援/引导盘启动才能缩，风险高收益低 |
| ~~加新物理盘~~ | ✅ **已改判为可行**：新增 VHDX 可热添加（实测 `storvsc_host` scan 可写），见 `add-new-disk-howto.md` |

---

## 推荐顺序

1. **方案 C**（宿主 Hyper-V 扩盘）—— 有空间就做，零停机零搬迁
2. **方案 B**（缩 swap，+11 G）—— 立刻可做，风险低，先解燃眉之急
3. 若两者都不可行 → **C 不成立时用 D**（迁 Docker 到 /home），或 **A**（缩 /home，接受停机）

## 验收

```bash
df -hT /var /home          # /var 目标 ≤60%
vgs; lvs                   # VFree 与各 LV 大小符合预期
free -h                    # swap 仍在（方案 B 后应为 4G）
docker ps --format '{{.Names}}\t{{.Status}}' | grep hermes   # 两容器 healthy
docker exec hermes bash -c 'grep -c "Refusing to open or write" /home/agent/.hermes/logs/errors.log'  # 仍为 4
docker system df           # 镜像/缓存/卷数据未受影响
```

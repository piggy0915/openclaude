# 新增 VHDX 硬盘扩容方案（比扩原盘更省事）

> 2026-09-13。**新增一块虚拟盘** → 并入 LVM 卷组 → 在线扩 `/var`。相比扩原盘的好处：
> **不用删检查点、不用碰分区表、不用重启**；代价是卷组跨两块盘（见文末红线）。

## 为什么可行（本机实测结论）

| 检查项 | 结果 |
|---|---|
| SCSI 控制器扫盘文件 | `storvsc_host`（host0/host1）`scan` **可写** ✅ → 能在运行中热发现新盘 |
| Hyper-V 存储驱动 | `hv_storvsc` 已加载 ✅ |
| 当前块设备 | 只有 `sda`（256 G）→ 新盘将是 **`/dev/sdb`** |
| LVM 工具 | `pvcreate` / `vgextend` / `lvextend -r` 全部在位 ✅ |
| 已有备份 | 分区表 `/root/sda-partition-table-before-20260913-112203.dump` |

---

## 设计一（推荐，零停机）：新盘并入同一卷组 → 扩 /var

### 宿主侧（Hyper-V，2 分钟，**无需关机**）

```powershell
# ① 确认虚拟机是第 2 代（Gen2 用 SCSI，支持热插拔；Gen1 是 IDE，加盘需关机）
Get-VM -Name <你的VM名> | Select-Object Name,Generation

# ② 建一块动态扩展（精简置备）VHDX，300 GB 只是上限，实际按使用量占宿主空间
$p = "D:\Hyper-V\<你的VM名>-data01.vhdx"
New-VHD -Path $p -SizeBytes 300GB -Dynamic

# ③ 热添加到 SCSI 控制器（Gen2 无需关机；若报错提示有检查点，先删检查点）
Add-VMHardDiskDrive -VMName <你的VM名> -Path $p -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1

# ④ 确认已挂上
Get-VMHardDiskDrive -VMName <你的VM名> | Format-Table Path,ControllerType,ControllerNumber,ControllerLocation
```

> 也可用 GUI：虚拟机设置 → SCSI 控制器 → 硬盘 → 添加 → 新建 → 选动态扩展 → 填大小。
> **动态 VHDX** 只按实际写入占用宿主空间；宿主卷需留出你打算真实使用的量。

### 客户机侧（一条命令）

```bash
cd /home/user/gateway

# 先让内核发现新盘（热插拔通常自动发现；没有就手动扫）
lsblk                                  # 看不到 sdb 时执行下面一行
for h in /sys/class/scsi_host/host*/scan; do echo "- - -" > "$h"; done
lsblk                                  # 应出现 sdb，大小 = 你建的容量

# 预览 → 执行（脚本会把盘做成 PV、加入卷组、在线扩 /var）
scripts/add-disk-to-vg.sh --check /dev/sdb
scripts/add-disk-to-vg.sh /dev/sdb

# 或只给 /var 加 100G，其余留在卷组
scripts/add-disk-to-vg.sh /dev/sdb 100G
```

脚本安全校验（**只会动你显式指定的设备**）：
拒绝对系统盘（`sda*`）操作；盘上已有分区 / 文件系统 / PV 签名时**直接拒绝**（防误删数据）；`--check` 全程预览不改动。

> 也可以整盘不做分区，直接 `pvcreate /dev/sdb`（LVM 推荐做法，本方案即如此）。

---

## 设计二（更干净的故障域）：新盘做独立文件系统，专供 Docker

`/var` 的 53 G 里 44 G 是 Docker。把 Docker 整个搬到新盘，`/var` 立刻降到 ~9 G。

```bash
# 1. 在新盘上建文件系统并挂载
mkfs.ext4 -L docker /dev/sdb
mkdir -p /srv/docker
echo "LABEL=docker /srv/docker ext4 defaults 0 2" >> /etc/fstab
mount /srv/docker && df -h /srv/docker

# 2. 停栈 → 迁移 Docker 数据 → 改 data-root → 起栈
systemctl stop docker docker.socket containerd
rsync -aHAX --info=progress2 /var/lib/docker/ /srv/docker/
python3 - <<'PY'
import json, pathlib
p = pathlib.Path('/etc/docker/daemon.json')
d = json.loads(p.read_text())
d['data-root'] = '/srv/docker'
p.write_text(json.dumps(d, indent=2, ensure_ascii=False))
print(open(p).read())
PY
systemctl start docker
docker info | grep "Docker Root Dir"     # → /srv/docker
docker ps | wc -l                        # 容器应全部回来
```

| | 设计一（并入卷组） | 设计二（独立 FS 给 Docker） |
|---|---|---|
| 停机 | **0** | 首次迁移 20–40 分钟；用**两遍 rsync**可压到 3–5 分钟（见下） |
| `/var` 效果 | 容量变大（百分比下降） | **占用骤降到 ~9 G** |
| 新盘消失后能否开机 | ⚠️ **进紧急模式**：`/var` 与该盘同卷组，PV 缺失 → `/var` 无法激活（`/`、`/usr` 的 extent 全在 sda3 上仍可激活，但 fstab 挂不上 /var 会中断启动） | ✅ **正常开机**（系统盘与 `/var` 完好），只是 Docker 起不来 |
| Docker 数据 | ❌ 丢（extent 已分布在新盘） | ❌ **同样丢**（没有冗余） |
| 能否退回原状 | ❌ **基本不能**：`pvmove` 回迁需要 sda3 有空闲 extent，而它只剩 1.56 G → 无路可退 | ✅ 改回 `data-root: /var/lib/docker` 即可（**前提：迁移后先别删旧目录**） |
| 恢复难度 | 高（要动 LVM：`vgreduce --removemissing` 会连带毁掉 LV） | 低（改一行配置 / 换个盘重挂） |

> **重要更正**：本方案早先版本称设计二"拔盘只影响 Docker，系统无恙"—— 这个说法**不成立**。
> 你的服务全在容器里，**盘一旦消失，服务就是没了，两种设计一样**。
> 两者真正的差别不是"能不能拔盘"，而是 **① 坏了之后机器还能不能起来 ② 有没有退路**：

- 设计一：**没有退路**（extent 已铺在新盘，且 sda3 无空闲 extent 供 `pvmove` 回迁）；坏盘 = `/var` 废 + 进紧急模式 + Docker 数据全丢
- 设计二：**有退路**（旧 `/var/lib/docker` 只要没删，改回配置即可回滚）；坏盘 = Docker 数据丢，但系统正常、`/var` 完好

**降低设计二停机时间的做法（两遍 rsync）**

```bash
# ① 在线预拷（不停机，20–40 分钟）
rsync -aHAX --delete --info=progress2 /var/lib/docker/ /srv/docker/
# ② 正式切换（停机仅 3–5 分钟）
systemctl stop docker docker.socket containerd
#    ⚠ 本机 daemon.json 里是 "live-restore": true —— 单跑 systemctl stop docker
#      **不会停容器**（这正是 live-restore 的设计目的），容器句柄仍指向旧 root！必须先显式停容器：
docker stop $(docker ps -q)      # 或 docker compose stop
rsync -aHAX --delete /var/lib/docker/ /srv/docker/      # 只补增量，很快
# 改 daemon.json 加 "data-root": "/srv/docker"
systemctl start docker
docker info | grep "Docker Root Dir" && docker ps | wc -l
# ③ 旧目录先别删！保留 2–4 周作为回滚点（期间 /var 仍占 44 G，但你有新盘）
```

**组合打法**：先做设计一拿零停机的空间；等哪天有维护窗口，再做设计二把 Docker 挪到新盘，`/var` 与 Docker 彻底分家。

**第三个选择：先别加盘**。增长主要来自构建缓存（每次重建 +2–7 G），而不是业务数据 —— 定期 `docker builder prune -f` + 现有 17 G 可用，足够跑很久。加盘是"有更多地方堆"，不是"不再堆"。

---

## 红线（务必知道）

1. **一旦 `vgextend` 把新盘并入卷组，这块盘就不能单独拔除/删除**：LV 的新 extent 会落在它上面，缺失 PV 会导致 `/var` 无法激活（启动失败）。日后想撤，必须先用 `pvmove` 把它上面的数据挪回来，再 `vgreduce`。
2. **Gen1 虚拟机**（磁盘在 IDE 控制器）不支持热添加 → 要么关机加盘，要么改用 SCSI。
3. **有检查点时**，Hyper-V 可能拒绝新增设备 → 先在宿主删检查点。
4. 不要碰原盘 `sda` 的分区表 —— 本方案完全不需要（这也是它比"扩原盘"更安全的地方）。
5. 动态 VHDX 是**精简置备**，宿主空间随使用增长；宿主卷满了会同时影响宿主机与这台 VM。

---

## 验收

```bash
lsblk                        # sdb 在位；sda3 未变
vgs; pvs                     # VG 变为 2 个 PV，VFree 大增
df -hT /var                  # 容量已变大、百分比下降
docker ps --format '{{.Names}}\t{{.Status}}' | grep hermes     # 两容器仍 healthy
docker exec hermes bash -c 'grep -c "Refusing to open or write" /home/agent/.hermes/logs/errors.log'   # 仍为 4
docker system df             # 镜像/缓存/卷数据完好
```

## 出问题了怎么退

| 症状 | 处置 |
|---|---|
| `lsblk` 看不到 sdb | 让宿主确认 `Add-VMHardDiskDrive` 成功；客户机重扫控制器（见上） |
| 脚本拒绝执行 | 它检测到盘上有分区/文件系统/PV 签名 —— 换盘，或确认后手动清理 |
| `vgextend` 后 VFree 没变大 | 检查 `pvs` 里新 PV 的 PSize 是否为 0 → PV 未正确建立 |
| 想撤销卷组成员 | `pvmove /dev/sdb` → `vgreduce zgjy-debian-vg /dev/sdb` → `pvremove /dev/sdb` |

---

## 自动化脚本（2026-09-13）

设计二已做成一键脚本，带前置检查与自动回滚：

```bash
scripts/migrate-docker-to-disk.sh --check    # 预览：设备校验、容量对比、动作清单
scripts/migrate-docker-to-disk.sh --status   # 当前 root / 回滚点 / 挂载状态
scripts/migrate-docker-to-disk.sh            # 执行迁移（会停全部容器）
scripts/migrate-docker-to-disk.sh --rollback --yes   # 改回 /var/lib/docker
```

安全设计：拒绝操作系统盘；盘上已有文件系统/分区/PV 签名时拒绝覆盖；校验不通过自动回滚；`live-restore: true` 下先显式停容器再停守护进程；迁移后保留旧目录作为回滚点。

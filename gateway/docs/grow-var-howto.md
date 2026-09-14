# 扩容 /var 操作手册（Hyper-V 虚拟盘 → LVM 在线扩容）

> 2026-09-13。**全程无需重启本机、无需停容器**。宿主机侧需你在 Hyper-V 里操作，客户机侧已备好脚本。

## 0. 现状基线（实测）

| 项 | 值 |
|---|---|
| 虚拟化 | Hyper-V（磁盘型号 `Msft Virtual Disk`） |
| 磁盘 | `/dev/sda` 256 GiB → 全部分配，分区 `sda3` 254.1 GiB = LVM PV |
| 卷组 | `zgjy-debian-vg`，VFree **1.56 GiB**（所以必须先在宿主扩盘） |
| 目标 | `zgjy-debian-vg/var` 74.5 GiB（已用 53 GiB，77%） |
| fstab | 用 `/dev/mapper/...` 路径（**不是 UUID → 无 UUID 风险**） |
| 客户机工具 | `growpart` ✅（已装 cloud-guest-utils）、`pvresize`/`lvextend`/`resize2fs` ✅、`partx` ✅（后备） |
| 已留备份 | 分区表 `/root/sda-partition-table-before-20260913-112203.dump` |

---

## 第一步（宿主 Hyper-V，约 2 分钟）

### 1.1 先确认两件事

```powershell
# ① 虚拟磁盘文件在哪、当前多大
Get-VM | Format-Table Name,State
Get-VMHardDiskDrive -VMName <你的VM名>
# ② 宿主存放 VHDX 的卷还剩多少空间（动态盘按实际增长占用，固定盘要一次性留足）
Get-Volume | Format-Table DriveLetter,FileSystemLabel,@{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}}
```

### 1.2 删除检查点（**关键前置**）

检查点（快照）会生成 `.avhdx` 差分链，**挡住扩容**：

```powershell
Get-VMSnapshot -VMName <你的VM名> | Format-Table Name,CreationTime,ParentSnapshotName
# 确认无用后逐个删除（会合并到父盘，耗时取决于差分大小）
Remove-VMSnapshot -VMName <你的VM名> -Name "<检查点名>"
```

### 1.3 扩容虚拟磁盘（二选一）

**路线 A（推荐，可在运行中操作）——Hyper-V 管理器 GUI**

`Hyper-V 管理器` → 右键虚拟机 → **设置** → `SCSI 控制器` → **硬盘** → **编辑** → 下一步 →
选 **扩展** → 输入新大小（如 `400` GB）→ 完成。

> VHDX 支持**在线扩展**，虚拟机不用关机。

**路线 B（PowerShell，需先关机）**

```powershell
Stop-VM -Name <你的VM名>
Resize-VHD -Path "D:\Hyper-V\Virtual Hard Disks\<你的VM名>.vhdx" -Size 400GB
Start-VM -Name <你的VM名>
```

> ⚠️ `Resize-VHD` 要求磁盘**未连接到运行中的虚拟机**，所以必须先 `Stop-VM`（这也是为什么路线 A 更省事）。
> ⚠️ 只能**扩**不能缩（VHDX 缩容需另用工具，且不支持在线）。
> ⚠️ 若该盘是**差分盘**（存在检查点），必须先把检查点删干净。

**建议容量**：400 GB（+144 GB）或 512 GB。给 /var 之后，Docker 的镜像+缓存反复重建也不怕了。

---

## 第二步（客户机，一条命令）

宿主机扩完，回到本机执行：

```bash
cd /home/user/gateway

# 先预览（不改动任何东西）
scripts/grow-var.sh --check

# 确认无误后执行：新增空间全部给 /var
scripts/grow-var.sh

# 或只给 /var 加 100G、其余留在卷组备用
scripts/grow-var.sh 100G
```

脚本内部依次做（每步都有校验）：

| 步骤 | 命令 | 是否在线 |
|---|---|---|
| 1 | `echo 1 > /sys/class/block/sda/device/rescan` | ✅ |
| 2 | `sfdisk -d /dev/sda > /root/sda-partition-table-<ts>.dump`（备份） | ✅ |
| 3 | `growpart /dev/sda 3` → `partx -u /dev/sda` | ✅（扩展最后一个分区，安全） |
| 4 | `pvresize /dev/sda3` | ✅ |
| 5 | `lvextend -r -l +100%FREE /dev/zgjy-debian-vg/var` | ✅（`-r` 自动调 `resize2fs`） |
| 6 | `df -h /var` 复核 | — |

**安全性**：`sda3` 是磁盘**最后一个**分区 → 扩展它不动任何已有分区；ext4 扩容是在线且非破坏性的（只改元数据，不搬数据）。

---

## 预期结果（以扩到 400 GB 为例）

| 指标 | 现在 | 之后 |
|---|---|---|
| sda | 256 GiB | 400 GiB |
| 卷组 VFree | 1.56 GiB | ≈ 145 GiB |
| `/var` 容量 | 74.5 GiB（用 53 G，**77%**） | 218.5 GiB（用 53 G，**≈24%**） |
| 停机时间 | — | **0** |

---

## 验收

```bash
df -hT /var /home            # /var 容量已变大、占用百分比下降
vgs; lvs                     # VFree 与 LV 大小符合预期
lsblk                        # sda 为 400G，sda3 填满磁盘
docker ps --format '{{.Names}}\t{{.Status}}' | grep hermes      # 两容器仍 healthy
docker system df             # 镜像/缓存/卷数据完好
docker exec hermes bash -c 'grep -c "Refusing to open or write" /home/agent/.hermes/logs/errors.log'   # 仍为 4
```

---

## 出问题了怎么退

| 症状 | 处置 |
|---|---|
| 第 1 步 rescan 后大小不变 | 检查点没删干净 / 宿主扩的是另一个盘 / 重启本机（`resize` 后内核最常见就是 re-read） |
| `growpart` 报错 | 分区表**未被改动**；用备份还原：`sfdisk /dev/sda < /root/sda-partition-table-<ts>.dump` |
| `pvresize` 后 VFree 仍很小 | `sda3` 未真正变大 → 回到上一步核对 `cat /sys/block/sda/sda3/size` |
| `lvextend -r` 失败 | LV 未改或只改了 LV 未改 FS；执行 `resize2fs /dev/zgjy-debian-vg/var` 补上 |
| 想撤销（LV 缩回） | 需 `umount /var`（停 Docker）→ `e2fsck -f` → `resize2fs … 74G` → `lvreduce -L 74G`。**几乎不会需要** |

---

## 附：为什么不能靠"缩别的 LV"来解决

`/usr` 空 32 GiB、`/` 空 26 GiB、`/home` 空 64 GiB —— 合计 122 GiB 闲置，但：

| LV | 能否在线缩 |
|---|---|
| `/home` | ❌ 被 23 个容器的 `data/*` 绑定占用，须停全栈再 `umount`（方案 A，停机 15–30 分钟，ext4 收缩有风险） |
| `/usr`、`/` | ❌ 运行中无法卸载，须救援/引导盘启动 |
| `swap`（14.9 G，只用 2 G） | ✅ 可在线缩；fstab 用的是 mapper 路径 → **无 UUID 风险**，可换出 ≈11 GiB（方案 B） |

所以：**能在宿主扩盘就扩盘**（零停机、零风险、收益最大）；扩不了再退回方案 B（缩 swap，+11 GiB）。

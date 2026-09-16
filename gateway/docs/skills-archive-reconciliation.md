# 归档区对账报告（2026-09-15）

**对象**：`data/hermes/skills-archive/`（132 个技能 / 40M）+ 目录 `data/workspace/skills-catalog.md`
**触发**：技能树顶层在 14:30–14:43 被另一执行者归档（绊线记录 127→107→106→102），现做对账确认无损失。

## 结论

**干净，无能力丢失、无目录失真。** 归档动作可接受，但归档区目前**没有任何备份**（唯一的实质风险，见 §4）。

## 1. 校验结果

| 校验项 | 结果 |
|---|---|
| 目录 ↔ 归档 1:1 | ✅ 目录 132 条、归档 132 个 SKILL.md；**目录写了但缺失 0 / 归档有但未列 0** |
| 结构完整性 | ✅ 0 个缺 frontmatter / 缺 description / 过短 |
| 内容可恢复性 | ✅ 131/132 在**现役树或 Gitee 仓库**里有同内容副本；余下 1 个是**旧版本快照**（见 §3） |
| 目录文件一致性 | ✅ 归档区内 `CATALOG.md` 与 `data/workspace/skills-catalog.md` 逐字节相同 |
| 计数对账 | ✅ 404（现役）+ 132（归档）= **536**，与归档前计数一致 → 文件是**被移动**，不是丢失 |

## 2. 归档构成

| 目录 | 归档数 | 现役残留 |
|---|---|---|
| `engineering/` | 25 | 0（整类归档） |
| `marketing/` | 24 | 0（整类归档） |
| （顶层散放） | 21 | — |
| `persona/` | 20 | 0（整类归档） |
| `specialized/` | 20 | 5 |
| `nuwa/examples` + `nuwa.dup-144237/examples` | 15 | 0 |
| `company/` | 7 | 0 |
| 其他（document-processing / research / 等） | 剩余 | — |

## 3. 唯一"独一份"文件的定性

`skills-archive/nuwa.dup-144237/SKILL.md`（37,380 字节，mtime 2026-08-24，`name: huashu-nuwa`）
是**同一技能的旧版本**（去重时留下的 `.dup-144237` 副本）：

- 现役版本：`data/hermes/skills/huashu-nuwa/SKILL.md`（48,458 字节，2026-09-12）→ **更新、更全**（diff：现役独有 237 行，旧版独有 64 行）
- 判定：**旧版快照，非唯一能力**；保留在归档区无害，也可删。

## 4. 待处理项与处置（2026-09-15 已办）

### ✅ 1. 归档区备份 —— 已建跨盘快照机制

原问题：40M / 132 技能无任何备份。处置：

- 新增 `scripts/backup-skills-archive.sh`：**内容指纹变化才写**快照，写完**校验**（tar 内 SKILL.md 数 == 源数，否则删除并报错），**保留最近 5 份**，日志 `/var/log/skills-archive-backup.log`。
- 落点选在 **`/srv/docker/backups/skills-archive/`** —— 该目录在**另一块物理盘**（`/dev/sda`，52G 可用）；
  而 `/home` 与 `/opt/data` 同属 `sdb3` 上的 LVM，放那里不防盘损。
- 已挂 cron：`/etc/cron.d/skills-archive-backup`（每天 03:30）。
- 首次快照实测：`skills-archive-20260915-153405.tgz` = **33MB / 132 个 SKILL.md**，计数与源一致；目录文件另存 `skills-catalog-latest.md`；重复执行**幂等跳过**。

### ⏸ 2. `nuwa.dup-144237/`（去重遗留）—— 决定**保留**

它是同一技能的**旧版本快照**（旧版独有 64 行 vs 现役独有 237 行），37KB，留着不占成本；
已随快照一起备份，需要时可比对历史。要删随时说。

## 5. 归档技能的取用与调回

归档技能**不进技能索引**（模型默认看不见），按 SOUL.md「技能查找与兜底」三级查找取用：
索引 → 磁盘 `find data/hermes/skills -name SKILL.md -path '*<名>*'` → **归档目录 `skills-catalog.md`**。

调回整类（`mv` 后立刻可用 `read_file`；要进索引需**新起会话**）：

```bash
mv data/hermes/skills-archive/engineering data/hermes/skills/    # 例：整类调回
```

成本参考（索引每轮提示词）：

| 调回 | 技能数 | 约增 tokens/轮 |
|---|---|---|
| `engineering/` | 25 | +687 |
| `marketing/` | 24 | +660 |
| `persona/` | 20 | +550 |
| `specialized/` | 20 | +550 |

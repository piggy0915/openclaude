# 共享工作卷（hermes_workspace）

> 2026-09-13 新增。用途：项目 / 开发 / 咨询资料 / 视频材料等「人看的内容」，由 `hermes` 与 `hermes-webui` 两个容器共享同一份。

## 路径与权限

| 视角 | 路径 |
|---|---|
| 宿主实盘 | `/home/user/gateway/data/workspace` |
| 宿主入口（软链） | `/workspace` → 上面这个目录 |
| 容器内（两侧完全一致） | `/workspace` |

- 属主 / 权限：`10000:10000`，目录 `2775`（setgid，新文件继承组）/ 文件 `664`
- 所在文件系统：`/home`（约 64G 可用）
- ⚠️ **不要放 `/var`**：Docker 镜像已占满，`/var` 仅余约 11G

## 目录约定

| 目录 | 用途 |
|---|---|
| `projects/` | 项目：一个项目一个子目录 |
| `dev/` | 开发：实验代码、脚本、脚手架 |
| `consulting/` | 咨询资料：方案、标书、调研 |
| `media/` | 视频材料：录制、素材、转码产物（大文件） |
| `inbox/` | 投递落点：下载、临时文件（定期清空） |
| `archive/` | 归档：低频只读历史 |

同内容说明随卷走：`data/workspace/README.md`。

**知识管理不放这里**：统一走 Obsidian（容器 `/knowledge_base/obsidian`，宿主 `data/obsidian`），不在此另建第二份笔记库。

## compose 配置位置

```yaml
# 顶层 volumes（缩进：卷名 2 空格 / 子项 4 / driver_opts 子项 6）
  hermes_workspace_volume:
    name: hermes_workspace
    driver: local
    driver_opts:
      type: none
      device: ${PWD}/data/workspace
      o: bind

# 两个服务各一行
      - hermes_workspace_volume:/workspace:rw
```

定位：`grep -n "hermes_workspace_volume" /home/user/gateway/docker-compose.yml` → 应 **3 处**（1 定义 + 2 挂载）。

## 终端工作目录

`config.yaml` 已设 `terminal.cwd: /workspace`，使脑侧（ssh→宿主）与 webui（容器内）两侧工作目录统一。

⚠️ `config.yaml` 会被 Ekko 重写（历史上曾被精简到 8 个顶层键），**重建后必须复查该段是否还在**。

## 生效与验收

新增挂载**必须重建容器**（`restart` / `start` 不生效）：

```bash
cd /home/user/gateway && docker compose up -d hermes hermes-webui
```

```bash
docker compose config -q && echo COMPOSE_OK
ls -ld /workspace                                   # 宿主软链 → data/workspace
docker exec hermes      ls -1 /workspace            # 6 目录 + README.md
docker exec hermes-webui ls -1 /workspace           # 同上（同一份）
docker exec hermes-webui /opt/hermes/.venv/bin/python \
  -c "from hermes_cli.config import load_config_readonly as L; print(L()['terminal']['cwd'])"
```

## 已知限制

- **容量**：`/home` 约 64G；VG 仅剩 1.5G 可扩，`/var` 已 85%（镜像 36G+）。长期存视频需加盘或定期外移。
- `media/` 与 `inbox/` 建议从备份中排除。
- 工作卷只放"人看的内容"：数据库、日志、运行态一律留在 `data/hermes*`。

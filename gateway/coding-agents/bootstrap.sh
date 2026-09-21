#!/usr/bin/env bash
# ============================================================================
# 编码工具链引导（Reasonix + OpenCodeReview / ocr）  v3  2026-09-19
# ----------------------------------------------------------------------------
# 职责：把「镜像里的模板 + 容器环境里的密钥」物化到持久卷，使镜像重建后免人工重配。
# 设计要点：
#   1) 镜像只放二进制 + 模板 + 本脚本；配置实体与密钥永远在持久卷（/opt/data）。
#      （/opt/data 是 compose 卷：构建期写进镜像的运行时会被卷遮蔽 → 白写）
#   2) 卷内 /opt/data/coding-agents/ 这份优先于镜像内那份 → 改行为不必重建镜像。
#      加 --reseed 可用镜像版本覆盖卷内版本。
#   3) 幂等、无密钥、任何失败都不阻断容器启动。
#
# ⚠️ 踩过的两个环境坑（都在下面处理了）：
#   a) 不要用 ${HERMES_DATA_DIR:-…} 猜数据目录：本栈 compose 把它定义成
#      ./data/hermes-web-ui（相对路径）→ v1 解析成不存在的路径后静默「跳过」。
#      故用专用变量 CODING_AGENTS_DATA_DIR，并逐级回退到真实存在的目录。
#   b) ocr 的配置目录跟着 **$HOME** 走，而两个容器的 HOME 不同：
#      hermes=/root、hermes-webui=/home/agent → v2 只接 /root 导致 webui 侧读不到配置。
#      ocr 又没有「配置目录」环境变量（仅有 OCR_NO_UPDATE / OCR_UPDATE_INTERVAL），
#      所以必须按各自 $HOME 建符号链接指向卷内同一份配置。
# ============================================================================
set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMG_DIR=/opt/hermes/coding-agents
HOME_DIR=${HOME:-/root}
P="[coding-agents]"
OCR_MODEL=${OCR_MODEL:-deepseek-v4-flash}

log() { echo "$P $*"; }

resolve_data_root() {
    if [ -n "${CODING_AGENTS_DATA_DIR:-}" ] && [ -d "${CODING_AGENTS_DATA_DIR}" ]; then
        printf '%s\n' "${CODING_AGENTS_DATA_DIR}"; return 0
    fi
    if [ -d /opt/data ]; then printf '/opt/data\n'; return 0; fi
    if [ -n "${HERMES_DATA_DIR:-}" ] && [ -d "${HERMES_DATA_DIR}" ]; then
        printf '%s\n' "${HERMES_DATA_DIR}"; return 0
    fi
    printf '\n'
}

# 把 $HOME 下的路径接到卷内目录上：
#   已是符号链接 → 直接改指向；不存在 → 建链接；是真实目录 → 搬成 *.pre-coding-agents 备份后建链接
link_home_path() {
    target=$1; path=$2
    if [ -L "$path" ]; then
        ln -sfn "$target" "$path" 2>/dev/null || true
    elif [ -e "$path" ]; then
        cp -an "$path/." "$target/" 2>/dev/null || true      # -n：不覆盖卷内已有内容
        mv "$path" "${path}.pre-coding-agents" 2>/dev/null && \
            ln -sfn "$target" "$path" 2>/dev/null || true
        log "已把旧目录挪为备份：${path}.pre-coding-agents"
    else
        mkdir -p "$(dirname -- "$path")" 2>/dev/null || true
        ln -sfn "$target" "$path" 2>/dev/null || true
    fi
}

DATA_ROOT=$(resolve_data_root)
if [ -z "$DATA_ROOT" ]; then
    log "跳过：找不到可写的持久数据目录（/opt/data 未挂载）"
    exit 0
fi

REASONIX_DIR="$DATA_ROOT/reasonix"
OCR_DIR="$DATA_ROOT/opencodereview"
VOL_DIR="$DATA_ROOT/coding-agents"

# ------------------------------------------------- 0) 自播种（卷内副本可热更新）
mkdir -p "$VOL_DIR" 2>/dev/null || true
for f in bootstrap.sh run-bootstrap.sh; do
    if [ -s "$IMG_DIR/$f" ]; then
        if [ "${1:-}" = "--reseed" ] || [ ! -s "$VOL_DIR/$f" ]; then
            cp "$IMG_DIR/$f" "$VOL_DIR/$f" 2>/dev/null && chmod +x "$VOL_DIR/$f" 2>/dev/null || true
        fi
    fi
done

# ---------------------------------------------------------------- 1) Reasonix
mkdir -p "$REASONIX_DIR" 2>/dev/null || true
if [ ! -s "$REASONIX_DIR/config.toml" ] && [ -s "$IMG_DIR/reasonix-config.toml" ]; then
    cp "$IMG_DIR/reasonix-config.toml" "$REASONIX_DIR/config.toml" && \
        log "reasonix: 从模板写入 config.toml"
fi
# 密钥只从容器环境变量取（compose env_file 注入），不落镜像
if [ -n "${DEEPSEEK_API_KEY:-}" ] && ! grep -q '^DEEPSEEK_API_KEY=' "$REASONIX_DIR/.env" 2>/dev/null; then
    ( umask 077; printf 'DEEPSEEK_API_KEY=%s\n' "$DEEPSEEK_API_KEY" > "$REASONIX_DIR/.env" ) && \
        log "reasonix: 写入 .env（密钥来自容器环境）"
fi
# REASONIX_HOME 已由镜像 ENV 指定，这里的链接只是兜底（不动真实目录）
[ -e "$HOME_DIR/.reasonix" ] || ln -sfn "$REASONIX_DIR" "$HOME_DIR/.reasonix" 2>/dev/null || true

# ------------------------------------------------------ 2) OpenCodeReview(ocr)
# 二进制在镜像内（Dockerfile.base 步骤 5.2）；配置目录只能靠 $HOME 定位 → 软链到卷
if command -v ocr >/dev/null 2>&1; then
    mkdir -p "$OCR_DIR" 2>/dev/null || true
    link_home_path "$OCR_DIR" "$HOME_DIR/.opencodereview"
    # 早期版本可能已把配置写进 HOME（且卷内还没有）→ 以 HOME 那份为准迁进来
    if [ ! -s "$OCR_DIR/config.json" ] && [ ! -L "$HOME_DIR/.opencodereview" ] && [ -s "$HOME_DIR/.opencodereview/config.json" ]; then
        cp "$HOME_DIR/.opencodereview/config.json" "$OCR_DIR/config.json" 2>/dev/null || true
    fi
    if [ ! -s "$OCR_DIR/config.json" ] && [ -n "${DEEPSEEK_API_KEY:-}" ]; then
        ocr config set provider deepseek                     >/dev/null 2>&1 || true
        ocr config set providers.deepseek.model "$OCR_MODEL" >/dev/null 2>&1 || true
        ocr config set providers.deepseek.api_key "$DEEPSEEK_API_KEY" >/dev/null 2>&1 || true
        log "ocr: 初始化配置（provider=deepseek / model=$OCR_MODEL，密钥来自容器环境）"
    fi
fi

# --------------------------------------------- 浏览器链路：BrowserSkill (bsk)
# 守护进程跑在宿主：systemd `bsk-daemon.service`，BSK_HOME=/opt/data/bsk-home（共享卷）。
# 容器内只需把 $HOME/.bsk 指向同一个 BSK_HOME 即可复用同一 daemon（实测两容器看到同一 pid）。
if [ -d /opt/data/bsk-home ]; then
    ln -sfn /opt/data/bsk-home "$HOME_DIR/.bsk"
fi

# --------------------------------------------- 浏览器链路：dev-browser（GitHub 导入）
# 两个实测坑（2026-09-20）：
#  ① 状态目录必须在 $HOME/.dev-browser 且是**真实目录**——符号链接会让 daemon 起不来
#     （"Daemon failed to start within 5 seconds"）；且实测本版 **DEV_BROWSER_BASE_DIR 不生效**。
#  ② dev-browser 自带 playwright 版本要去下 chromium-1208（~110MB），而镜像里只有 chromium-1234；
#     用 DEV_BROWSER_CHROME 指向镜像内 Chromium 可**完全免下载**（实测 install 从 110MB 降到 3 秒）。
# 故策略：Chrome 指镜像内；状态目录优先从卷内副本恢复（零网络），缺失才退化为 install。
export DEV_BROWSER_CHROME="${DEV_BROWSER_CHROME:-$(ls -d /opt/hermes/.playwright/chromium-*/chrome-linux64/chrome 2>/dev/null | sort -V | tail -1)}"
if command -v dev-browser >/dev/null 2>&1 && [ ! -d "$HOME_DIR/.dev-browser/node_modules" ]; then
    if [ -d /opt/data/dev-browser-state/node_modules ]; then
        # 注意 cp 语义：目标已存在时会拷成子目录 → 必须先删目标
        rm -rf "$HOME_DIR/.dev-browser"
        cp -a /opt/data/dev-browser-state "$HOME_DIR/.dev-browser" 2>/dev/null \
            && log "dev-browser: 从卷内副本恢复状态目录（零网络）"
        # 清掉从别处带过来的运行时残留（陈旧 pid/sock/lock 会让新 daemon 起不来）
        rm -f "$HOME_DIR/.dev-browser/daemon.pid" "$HOME_DIR/.dev-browser/daemon.sock" \
              "$HOME_DIR/.dev-browser/daemon-spawn.lock" 2>/dev/null || true
    fi
    if [ ! -d "$HOME_DIR/.dev-browser/node_modules" ]; then
        log "dev-browser: 状态目录缺失 → 执行 install"
        if dev-browser install >/dev/null 2>&1; then
            log "dev-browser: install 完成"
        else
            log "dev-browser: install 失败（需要网络）"
        fi
    fi
fi

# ------------------------------------------------------------- 3) 一行体检
# 只报事实，不打印任何密钥
if command -v reasonix >/dev/null 2>&1; then
    keys=$(reasonix doctor 2>/dev/null | grep -c 'key:present' || true)
    log "reasonix $(reasonix --version 2>/dev/null | head -1) | key:present=$keys | data=$DATA_ROOT | HOME=$HOME_DIR"
fi
if command -v ocr >/dev/null 2>&1; then
    log "ocr $(ocr --version 2>/dev/null | head -1) | cfg=$( [ -s "$OCR_DIR/config.json" ] && echo 已配置 || echo 未配置 )"
fi
exit 0

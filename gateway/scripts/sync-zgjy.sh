#!/usr/bin/env bash
# sync-zgjy.sh — RuoYi(zgjy-cloud) 工作仓同步助手
# 协作约定（2026-09-19 与用户确认）：**以 IDEA 为主**——
#   · Hermes 动代码前先 `pull`，改完 `push`，并在提交里带 [hermes-agent] 标记
#   · 用户在 IDEA 里提交/推送后，Hermes 下一次操作前 `pull`
# 用法：
#   sync-zgjy.sh status            # 分支 / 领先落后 / 未提交改动 / 最近提交
#   sync-zgjy.sh pull              # 从 Gitee 快进拉取（有本地改动则拒绝，绝不覆盖）
#   sync-zgjy.sh push "提交说明"    # 提交全部改动 → 必要时先合并远端 → 推送
#   sync-zgjy.sh sync              # 等价 pull（保留别名）
set -uo pipefail

REPO="${ZGYJY_REPO:-/workspace/projects/zgjy-cloud}"
BRANCH="${ZGYJY_BRANCH:-work}"

cd "$REPO" 2>/dev/null || { echo "✗ 仓库不存在: $REPO"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "✗ 不是 git 仓库: $REPO"; exit 2; }

cur=$(git rev-parse --abbrev-ref HEAD)
[ "$cur" = "$BRANCH" ] || { echo "✗ 当前分支 $cur ≠ $BRANCH，已退出（防误操作）"; exit 3; }

cmd="${1:-status}"
case "$cmd" in
  status)
    git fetch -q origin "$BRANCH" 2>/dev/null
    counts=$(git rev-list --left-right --count "$BRANCH...origin/$BRANCH" 2>/dev/null || echo "0	0")
    ahead=$(echo "$counts" | awk '{print $1}'); behind=$(echo "$counts" | awk '{print $2}')
    echo "仓库: $REPO"
    echo "分支: $BRANCH   领先远端: ${ahead:-?}   落后远端: ${behind:-?}"
    echo "最近提交: $(git log --oneline -1)"
    n=$(git status --short | wc -l)
    if [ "$n" -gt 0 ]; then
      echo "未提交改动: $n 项"; git status --short | head -15 | sed 's/^/  /'
    else
      echo "工作树: 干净"
    fi
    ;;
  pull|sync)
    if [ -n "$(git status --porcelain)" ]; then
      echo "✗ 有未提交改动，先 push 或 stash 再 pull："; git status --short | head -10 | sed 's/^/  /'; exit 4
    fi
    git fetch -q origin "$BRANCH"
    if [ "$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)" -eq 0 ]; then
      echo "✓ 已是最新（无需 pull）"
    else
      if git merge --ff-only "origin/$BRANCH" >/dev/null 2>&1; then
        echo "✓ 已快进到 $(git log --oneline -1)"
      else
        echo "✗ 无法快进（远端与本地分叉）→ 请在 IDEA 里处理或人工 merge"; exit 5
      fi
    fi
    ;;
  push)
    msg="${2:-}"
    [ -n "$msg" ] || { echo '用法: sync-zgjy.sh push "提交说明"'; exit 6; }
    if [ -z "$(git status --porcelain)" ]; then echo "✓ 没有需要提交的改动"; exit 0; fi
    git add -A
    git commit -q -m "$msg" -m "[hermes-agent]" || { echo "✗ 提交失败"; exit 7; }
    echo "✓ 已提交: $(git log --oneline -1)"
    git fetch -q origin "$BRANCH"
    if [ "$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)" -gt 0 ]; then
      if ! git merge --ff-only "origin/$BRANCH" >/dev/null 2>&1; then
        echo "✗ 远端有新提交且无法快进 → 先 `sync-zgjy.sh pull` 处理再 push"; exit 8
      fi
      echo "  （已先合并远端新提交）"
    fi
    if git push -q origin "$BRANCH"; then echo "✓ 已推送 → 请在 IDEA 里 pull"; else echo "✗ 推送失败"; exit 9; fi
    ;;
  *)
    echo "用法: $0 {status|pull|push \"说明\"|sync}"; exit 2 ;;
esac

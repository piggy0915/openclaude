#!/usr/bin/env python3
"""把 Hermes 技能树共享给 DSH —— 软链，不拷贝。

机制（实测）：DSH 的 skill-filesystem 插件把 customSkillDirs 里的条目按目录扫描，
`nodeEntryKind()` 对 isSymbolicLink() 走 stat() 跟随 → 目录软链被当作技能目录接受。
Studio 侧传入的 customSkillDirs = [<dsh源home>/skills, <GLOBAL_HOME>/.agents/skills]
（app/packages/server/src/modules/coding-agents/services/dsh/runtime-config.ts:80）。

  python3 scripts/dsh-share-skills.py            # 预览（默认，不改动）
  python3 scripts/dsh-share-skills.py --apply    # 执行

源  ：/home/user/gateway/data/hermes/skills            = 容器内 /home/agent/.hermes/skills
目标：…/hermes_webui_data/_data/coding-agent/home/.agents/skills
      = webui 容器内 /home/agent/.hermes-web-ui/coding-agent/home/.agents/skills

规则：
  ① 只链「叶子技能目录」（自身有 SKILL.md 且内部无嵌套 SKILL.md）——类目容器不链
  ② 同名必须唯一（先跑 scripts/dedup-top-level-skills.sh；重名会直接报错退出）
  ③ 软链目标写**容器内路径**；属主置 10000:10000
  ④ 只清理指向本源的失效链接，不碰其它条目
"""
import argparse, os, pathlib, sys

LIVE      = pathlib.Path('/home/user/gateway/data/hermes/skills')
SHARED    = pathlib.Path('/srv/docker/volumes/hermes_webui_data/_data/coding-agent/home/.agents/skills')
LIVE_CTR  = '/home/agent/.hermes/skills'          # 软链目标用的容器内路径
UID = GID = 10000


def leaf_skills():
    """返回 {技能目录名: 相对 LIVE 的路径}；同一目录名出现两次即视为冲突。"""
    out, dup = {}, []
    for f in LIVE.rglob('SKILL.md'):
        if any(p.startswith('.') for p in f.parts):
            continue
        d = f.parent
        if any(p.parent != d for p in d.rglob('SKILL.md')):   # 类目容器
            continue
        rel = d.relative_to(LIVE)
        if d.name in out:
            dup.append((d.name, str(out[d.name]), str(rel)))
        out[d.name] = rel
    return out, dup


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    a = ap.parse_args()

    sk, dup = leaf_skills()
    if dup:
        print('❌ 发现同名技能目录，先运行 scripts/dedup-top-level-skills.sh 去重：')
        for n, x, y in dup:
            print(f'   {n}: {x}  vs  {y}')
        sys.exit(2)

    print(f'源技能数(叶子)：{len(sk)}    目标目录：{SHARED}')
    if a.apply:
        SHARED.mkdir(parents=True, exist_ok=True)

    created = linked = relinked = 0
    for name, rel in sorted(sk.items()):
        link, want = SHARED / name, f'{LIVE_CTR}/{rel}'
        if link.is_symlink():
            cur = os.readlink(link)
            if cur == want:
                linked += 1
                continue
            print(f'  ↻ 重链 {name}\n      旧 {cur}\n      新 {want}')
            if a.apply:
                link.unlink(); os.symlink(want, link)
            relinked += 1
            continue
        if link.exists():
            print(f'  ⚠ 目标已存在且非软链，跳过：{link}')
            continue
        print(f'  + {name}  →  {want}')
        if a.apply:
            os.symlink(want, link)
        created += 1

    pruned = 0
    if SHARED.is_dir():
        for e in sorted(SHARED.iterdir()):
            if e.is_symlink() and os.readlink(e).startswith(LIVE_CTR) and e.name not in sk:
                print(f'  - 清理失效链接 {e.name}')
                if a.apply:
                    e.unlink()
                pruned += 1

    if a.apply:
        os.chown(SHARED, UID, GID)
        for e in SHARED.iterdir():
            try:
                os.chown(e, UID, GID, follow_symlinks=False)
            except OSError:
                pass

    print(f'\n===== 汇总 =====')
    print(f'  新建 {created} · 已就位 {linked} · 重链 {relinked} · 清理失效 {pruned} · 源技能 {len(sk)}')
    print('  ✅ 已落盘' if a.apply else '  （预览模式，未改动。执行请加 --apply）')


if __name__ == '__main__':
    main()

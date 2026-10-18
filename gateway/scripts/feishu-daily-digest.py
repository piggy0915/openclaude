#!/usr/bin/env python3
"""每日知识库摘要 → 飞书卡片。

用法：
  python3 scripts/feishu-daily-digest.py            # 统计当日增量并推送
  python3 scripts/feishu-daily-digest.py --dry-run  # 只打印卡片正文，不发送
  python3 scripts/feishu-daily-digest.py --date 2026-10-06   # 指定统计日（默认今天）

依赖：scripts/feishu-push.py（同目录）；QDRANT_API_KEY（取不到则跳过该段）
      AIHOT 精选 RSS（https://aihot.news/feed.xml；可用 env AIHOT_FEED 换源，抓取失败则整段跳过）
"""
import argparse, datetime as dt, json, os, pathlib, re, subprocess, sys, urllib.request
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
VAULT = ROOT / 'data/obsidian/knowledge'
WIKI_DIRS = ['entities', 'concepts', 'comparisons', 'queries']
QDRANT = 'http://localhost:6333'


def env() -> dict:
    e = dict(os.environ)
    for f in [ROOT/'config/.env', ROOT/'data/hermes/.env', ROOT/'.env']:
        if not f.exists():
            continue
        for line in f.read_text(encoding='utf-8', errors='ignore').split('\n'):
            m = re.match(r'^\s*([A-Z][A-Z0-9_]+)\s*=\s*(.*?)\s*$', line.replace('\r', ''))
            if m and m.group(1) not in e:
                e[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return e


def today_files(day: dt.date):
    """返回 (raw 新增/改列表, wiki 新增/改列表)，按日期目录/mtime 判定。"""
    raw, wiki = [], []
    for p in VAULT.rglob('*.md'):
        rel = p.relative_to(VAULT)
        # 优先看 frontmatter 的 created/clipped；退化到 mtime
        try:
            h = p.read_text(encoding='utf-8', errors='ignore')[:600]
        except Exception:
            continue
        m = re.search(r'(?m)^(?:created|clipped):\s*(\d{4}-\d{2}-\d{2})', h)
        d = m.group(1) if m else dt.date.fromtimestamp(p.stat().st_mtime).isoformat()
        if d != day.isoformat():
            continue
        t = re.search(r'(?m)^title:\s*(.+)$', h)
        item = (str(rel), (t.group(1).strip() if t else p.stem)[:52])
        (raw if rel.parts[0] == 'raw' else wiki).append(item)
    return sorted(raw), sorted(wiki)


def counts():
    c = {}
    for d in ['raw'] + WIKI_DIRS:
        base = VAULT / d
        c[d] = len([f for f in base.rglob('*.md') if f.name != 'MOC.md']) if base.exists() else 0
    return c


def qdrant_counts(e: dict):
    key = e.get('QDRANT_API_KEY')
    if not key:
        return None
    out = {}
    for coll in ['hermes_memory', 'hermes_knowledge']:
        try:
            req = urllib.request.Request(f'{QDRANT}/collections/{coll}/points/count',
                                         data=b'{"exact":true}', method='POST',
                                         headers={'api-key': key, 'Content-Type': 'application/json'})
            out[coll] = json.loads(urllib.request.urlopen(req, timeout=15).read())['result']['count']
        except Exception:
            out[coll] = None
    return out


# ── AI 热点：AIHOT 精选 RSS（https://aihot.news/feed.xml）────────────────────────
AIHOT_FEED_DEFAULT = 'https://aihot.news/feed.xml'   # 站点改过域名，可用 env AIHOT_FEED 覆盖
AIHOT_TOP = 5

def aihot_top(e: dict, n: int = AIHOT_TOP):
    """取 AIHOT 精选前 n 条 → [(标题, 链接, 分类)]；任何失败返回 []（日报其余部分不受影响）。"""
    feed = (e or {}).get('AIHOT_FEED') or AIHOT_FEED_DEFAULT
    try:
        req = urllib.request.Request(feed, headers={'User-Agent': 'hermes-feishu-digest/1.0'})
        xml = urllib.request.urlopen(req, timeout=15).read()
        ch = ET.fromstring(xml).find('channel')
        out = []
        for it in (ch.findall('item') if ch is not None else []):
            title = (it.findtext('title') or '').strip()
            if not title or 'AIHOT 通知' in title:      # 站方通告不是资讯
                continue
            cat = next((c.text for c in it.findall('category') if c.text), '')
            out.append((title, (it.findtext('link') or '').strip(), cat))
            if len(out) >= n:
                break
        return out
    except Exception:
        return []


def build(day: dt.date) -> str:
    e = env()
    raw, wiki = today_files(day)
    c = counts()
    q = qdrant_counts(e)
    lines = [f'**{day.isoformat()} 知识库日报**', '']
    lines.append(f'**当日入库**：raw **{len(raw)}** 篇 · wiki **{len(wiki)}** 页')
    if raw:
        lines.append('\n*raw*：' + '；'.join(t for _, t in raw[:6]) + ('…' if len(raw) > 6 else ''))
    if wiki:
        lines.append('\n*wiki*：' + '；'.join(t for _, t in wiki[:6]) + ('…' if len(wiki) > 6 else ''))
    lines += ['', f"**库现状**：raw {c['raw']} · entities {c['entities']} · concepts {c['concepts']} · "
                  f"comparisons {c['comparisons']} · queries {c['queries']}"]
    if q:
        seg = ' · '.join(f'{k} {v}' for k, v in q.items() if v is not None) or '（取数失败）'
        lines.append(f'**检索库**：{seg}')
    hot = aihot_top(e)
    if hot:
        lines += ['', '**AI 热点**（AIHOT 精选）']
        for title, link, cat in hot:
            seg = f'`{cat}` ' if cat else ''
            lines.append(f'· {seg}[{title[:80]}]({link})' if link else f'· {seg}{title[:80]}')
        lines.append('· [更多 AIHOT 精选 →](https://aihot.news/)')
    lines += ['', '_由 `scripts/feishu-daily-digest.py` 自动生成_']
    return '\n'.join(lines)


ARCHIVE_DIR = ROOT / 'data/hermes/digest-archive'


def archive(day: dt.date, body: str) -> None:
    """卡片正文落盘归档（原先只留 message_id，事后无法回看推送内容）。
    失败只告警不抛出 —— 归档失败绝不影响推送本身。"""
    try:
        ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
        (ARCHIVE_DIR / f'{day.isoformat()}.md').write_text(
            f'# 知识库日报 · {day.isoformat()}\n\n'
            f'> 归档自 scripts/feishu-daily-digest.py'
            f'（{dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")}）\n\n{body}\n',
            encoding='utf-8')
    except Exception as exc:
        print(f'[warn] 日报归档失败（不影响推送）：{exc}', file=sys.stderr)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--date')
    a = ap.parse_args()
    day = dt.date.fromisoformat(a.date) if a.date else dt.date.today()
    body = build(day)
    if a.dry_run:
        print(body); return 0
    archive(day, body)
    cmd = [sys.executable, str(ROOT/'scripts/feishu-push.py'), '--title', f'知识库日报 · {day.isoformat()}', '--text', body]
    return subprocess.run(cmd).returncode


if __name__ == '__main__':
    sys.exit(main())

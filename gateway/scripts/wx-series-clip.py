#!/usr/bin/env python3
"""批量：微信公众号系列文章 → 正文 + 信息图 OCR。

用法：
  python3 scripts/wx-series-clip.py album_list.json <输出根目录>

album_list.json：[{"title": "...", "url": "..."}, ...]（顺序即篇序）

每篇产物（<根目录>/NN-slug/）：
  page.html   原始 HTML
  article.txt 正文纯文本（去标签，保留段落）
  img/NN.jpg  正文信息图
  ocr.json / ocr_all.txt  逐图 OCR

复用 scripts/wx-clip-ocr.py 的 curl/图片提取/OCR 逻辑（导入而非复制）。
"""
import json, pathlib, re, sys, html as _html
import importlib.util

_here = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('wxclip', _here / 'wx-clip-ocr.py')
wx = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(wx)

END_MARKERS = ('<div class="rich_media_tool', '<div id="js_tags__',
               '<script nonce', 'id="js_article_bottom', '<div id="js_pc_qr_code')


def article_text(h: str) -> str:
    s = wx._unescape(h)
    i = s.find('id="js_content"')
    if i < 0:
        return ''
    seg = s[i:]
    for m in END_MARKERS:
        j = seg.find(m)
        if j > 0:
            seg = seg[:j]
    seg = re.sub(r'(?is)<(script|style)[^>]*>.*?</\1>', ' ', seg)
    seg = re.sub(r'(?i)<img[^>]*>', '\n[图片]\n', seg)
    seg = re.sub(r'(?i)<br\s*/?>', '\n', seg)
    seg = re.sub(r'(?i)</(p|section|div|h[1-6]|li|blockquote|tr)>', '\n', seg)
    seg = re.sub(r'<[^>]+>', '', seg)
    seg = _html.unescape(seg).replace('\u200b', '').replace('\xa0', ' ')
    seg = re.sub(r'[ \t]+\n', '\n', seg)
    seg = re.sub(r'\n{3,}', '\n\n', seg)
    out, prev = [], None
    for l in (x.strip() for x in seg.split('\n')):
        if l == '' and prev == '':
            continue
        out.append(l); prev = l
    return '\n'.join(out).strip()


CN = '一二三四五六七八九十'


def slug(t: str, n: int) -> str:
    m = re.search(r'[（(]([一二三四五六七八九十]+)[）)]', t)
    num = m.group(1) if m else None
    idx = CN.index(num) + 1 if num and num in CN else n
    part = t.split('：', 1)[1] if '：' in t else t
    part = re.sub(r'[^\w\u4e00-\u9fa5]+', '', part)[:24]
    return f'{idx:02d}-{part}'


def main():
    album = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
    root = pathlib.Path(sys.argv[2]); root.mkdir(parents=True, exist_ok=True)
    for n, item in enumerate(album, 1):
        d = root / slug(item['title'], n)
        (d / 'img').mkdir(parents=True, exist_ok=True)
        print(f'\n=== [{n}/{len(album)}] {item["title"]} -> {d.name}', flush=True)
        try:
            h = wx.fetch(item['url'], d / 'page.html')
        except Exception as e:
            print('  抓取失败', str(e)[:100], flush=True); continue
        txt = article_text(h)
        (d / 'article.txt').write_text(txt, encoding='utf-8')
        urls = wx.img_urls(h)
        print(f'  正文 {len(txt)} 字 | 图 {len(urls)} 张', flush=True)
        for i, u in enumerate(urls, 1):
            dst = d / 'img' / f'{i:02d}.jpg'
            if dst.exists() and dst.stat().st_size > 1000:
                continue
            try:
                wx._curl(u, dst, timeout=45)
            except Exception as e:
                print(f'   图 {i} 下载失败 {str(e)[:60]}', flush=True)
        wx.ocr_all(d)
    print('\n全部完成')


if __name__ == '__main__':
    main()

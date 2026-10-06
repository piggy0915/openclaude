#!/usr/bin/env python3
"""微信公众号文章 → 正文/图片抓取 + 本地 RapidOCR 逐页识别。

用法：
  python3 scripts/wx-clip-ocr.py <mp.weixin 链接> [工作目录]

产物（工作目录下）：
  page.html      原始 HTML
  img/NN.jpg     正文里的 mmbiz 图片（按出现顺序）
  ocr.json       每图的识别结果 {box/score/text，已按阅读顺序排序}
  ocr_all.txt    按页序合并的纯文本（喂给 wiki/入库用）

依赖：宿主 python3 的 rapidocr_onnxruntime（见技能 photo-ocr/references/rapidocr-local-engine.md）
"""
import json, pathlib, re, subprocess, sys, urllib.request

UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36'

def _curl(url: str, dst: pathlib.Path = None, timeout: int = 60) -> bytes:
    """用 curl 抓取：微信对 python-urllib 会 302 到 wappoc_appmsgcaptcha，curl+UA+Referer 才拿到正文。"""
    cmd = ['curl', '-sL', '--max-time', str(timeout),
           '-A', UA, '-H', 'Accept-Language: zh-CN,zh;q=0.9',
           '-H', 'Referer: https://mp.weixin.qq.com/']
    if dst:
        cmd += ['-o', str(dst), url]
    else:
        cmd += [url]
    out = subprocess.run(cmd, capture_output=True)
    if out.returncode != 0:
        raise RuntimeError(f'curl 失败 rc={out.returncode}: {out.stderr.decode()[:120]}')
    return dst.read_bytes() if dst else out.stdout


def fetch(url: str, dst: pathlib.Path) -> str:
    _curl(url, dst)
    return dst.read_bytes().decode('utf-8', 'ignore')


def _unescape(s: str) -> str:
    """微信正文常把 HTML 塞进 JS 字符串里转义：\x22 引号、\x3c/<、\x3e/>、反斜杠+斜杠 转义。"""
    for a, b in (('\\x22', '"'), ('\\x27', "'"), ('\\x3c', '<'), ('\\x3e', '>'),
                 ('\\x26', '&'), ('\\/', '/'), ('&amp;', '&')):
        s = s.replace(a, b)
    return s


def img_urls(html: str):
    """取正文里的内容图：优先 #imgIndex=N（按序），否则 data-src 顺序；过滤头像/二维码/图标。"""
    h = _unescape(html)
    idx = {}
    for m in re.finditer(r'(https://mmbiz\.qpic\.cn/[^"\s#]+)#imgIndex=(\d+)', h):
        idx[int(m.group(2))] = m.group(1)
    urls = [idx[k] for k in sorted(idx)] if idx else re.findall(
        r'data-src="(https://mmbiz\.qpic\.cn/[^"]+)"', h)
    seen, out = set(), []
    for u in urls:
        u = u.replace('&amp;', '&')
        if u in seen:
            continue
        low = u.lower()
        if '/0?wx_fmt=png' in low or 'wx_fmt=svg' in low:      # 头像 / 图标
            continue
        seen.add(u); out.append(u)
    return out


def ocr_all(work: pathlib.Path):
    import numpy as np
    from PIL import Image
    from rapidocr_onnxruntime import RapidOCR
    ocr = RapidOCR()
    out_json = work / 'ocr.json'
    done = json.loads(out_json.read_text(encoding='utf-8')) if out_json.exists() else {}
    for f in sorted((work / 'img').glob('*.jpg'), key=lambda p: int(p.stem)):
        if f.name in done:
            continue
        try:
            im = Image.open(f).convert('RGB')
        except Exception as e:
            print(f'  {f.name}: 打开失败 {str(e)[:60]}', flush=True); done[f.name] = []; continue
        a = np.array(im)
        a = np.repeat(np.repeat(a, 2, axis=0), 2, axis=1)      # 2x 放大（实测决定成败）
        try:
            res, _ = ocr(a)
        except Exception as e:
            print(f'  {f.name}: OCR 失败 {str(e)[:60]}', flush=True); done[f.name] = []; continue
        lines = []
        for r in (res or []):
            box, txt, score = r[0], r[1], r[2]
            ys = [p[1] for p in box]; xs = [p[0] for p in box]
            lines.append({'y': int(min(ys)), 'x': int(min(xs)), 't': txt, 's': round(float(score), 3)})
        lines.sort(key=lambda d: (round(d['y'] / 30), d['x']))  # 行容差随 2x 放大 → /30
        done[f.name] = lines
        out_json.write_text(json.dumps(done, ensure_ascii=False, indent=1), encoding='utf-8')
        print(f'  {f.name}: {len(lines)} 行', flush=True)

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    url = sys.argv[1]
    work = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else '/tmp/wx-clip')
    (work / 'img').mkdir(parents=True, exist_ok=True)
    print(f'[1/3] 抓 HTML → {work}/page.html')
    html = fetch(url, work / 'page.html')
    urls = img_urls(html)
    print(f'[2/3] 图片 URL {len(urls)} 个 → 下载')
    for i, u in enumerate(urls, 1):
        dst = work / 'img' / f'{i:02d}.jpg'
        if dst.exists() and dst.stat().st_size > 1000:
            continue
        try:
            _curl(u, dst, timeout=45)
        except Exception as e:
            print(f'   下载失败 {i}: {str(e)[:80]}')
    print(f'[3/3] OCR（{len(list((work/"img").glob("*.jpg")))} 张）')
    ocr_all(work)
    d = json.loads((work / 'ocr.json').read_text(encoding='utf-8'))
    parts = [f'===== {k} ({len(v)} 行) =====\n' + '\n'.join(l.get('t', '') for l in v if 't' in l)
             for k, v in sorted(d.items(), key=lambda kv: int(kv[0].split('.')[0]))]
    (work / 'ocr_all.txt').write_text('\n\n'.join(parts), encoding='utf-8')
    print(f'完成：{len(d)} 张 / {sum(len(v) for v in d.values())} 行 → {work}/ocr_all.txt')

if __name__ == '__main__':
    main()

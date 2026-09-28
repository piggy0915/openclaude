#!/usr/bin/env python3
"""comfyui-226 —— 通过 HTTP API 远程调用 226 笔记本上的 ComfyUI（AMD Radeon 8060S/ROCm）。

用法：
  # 列出可用模型
  comfyui-226.py models [--kind checkpoints|loras|diffusion_models|vae|controlnet]

  # 文生图（用 SDXL-Turbo 4 步这类快速模型）
  comfyui-226.py gen --prompt "a red panda in a bamboo forest" \
      --ckpt sdxl_turbo_1.0_fp16.safetensors --steps 4 --cfg 1.0 \
      --size 1024x1024 --out /tmp/rp.png

  # 跑任意 API 格式工作流
  comfyui-226.py run --workflow api_h3_director_t2v.json --outdir /tmp/h3 --timeout 3600

  # H3 出片（文生视频 t2v / 图生视频 i2v，走 Director 导演台节点；自动上传图、自动取片）
  comfyui-226.py h3 --prompt "镜头缓慢前推的红熊猫" --seconds 2 --size 864x480 --out /tmp/a.mp4
  comfyui-226.py h3 --task i2v --image /path/pic.png --prompt "雪花飘落，灯光闪烁" --seconds 2 --out /tmp/b.mp4

环境变量：COMFYUI_URL（默认 http://192.168.10.226:8188）、COMFYUI_AUTH（默认 icy:123456）
"""
import argparse, base64, json, mimetypes, os, random, sys, time, urllib.error, urllib.parse, urllib.request, uuid

BASE = os.environ.get('COMFYUI_URL', 'http://192.168.10.226:8188').rstrip('/')
AUTH = os.environ.get('COMFYUI_AUTH', 'icy:123456')


def _req(path, data=None, method=None, binary=False, timeout=60):
    url = BASE + path
    headers = {'Authorization': 'Basic ' + base64.b64encode(AUTH.encode()).decode()}
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers['Content-Type'] = 'application/json'
    r = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(r, timeout=timeout) as resp:
        raw = resp.read()
    return raw if binary else json.loads(raw.decode() or '{}')


def list_models(kind=None):
    info = _req('/object_info')
    mapping = {
        'checkpoints': ('CheckpointLoaderSimple', 'ckpt_name'),
        'loras': ('LoraLoader', 'lora_name'),
        'vae': ('VAELoader', 'vae_name'),
        'controlnet': ('ControlNetLoader', 'control_net_name'),
        'diffusion_models': ('UNETLoader', 'unet_name'),
    }
    out = {}
    for key, (node, field) in mapping.items():
        if kind and key != kind:
            continue
        try:
            out[key] = info[node]['input']['required'][field][0]
        except Exception:
            out[key] = []
    return out


def build_t2i(ckpt, prompt, negative, steps, cfg, size, seed, sampler, scheduler):
    w, h = size
    return {
        '3': {'class_type': 'KSampler', 'inputs': {
            'seed': seed, 'steps': steps, 'cfg': cfg, 'sampler_name': sampler,
            'scheduler': scheduler, 'denoise': 1.0,
            'model': ['4', 0], 'positive': ['6', 0], 'negative': ['7', 0], 'latent_image': ['5', 0]}},
        '4': {'class_type': 'CheckpointLoaderSimple', 'inputs': {'ckpt_name': ckpt}},
        '5': {'class_type': 'EmptyLatentImage', 'inputs': {'width': w, 'height': h, 'batch_size': 1}},
        '6': {'class_type': 'CLIPTextEncode', 'inputs': {'text': prompt, 'clip': ['4', 1]}},
        '7': {'class_type': 'CLIPTextEncode', 'inputs': {'text': negative, 'clip': ['4', 1]}},
        '8': {'class_type': 'VAEDecode', 'inputs': {'samples': ['3', 0], 'vae': ['4', 2]}},
        '9': {'class_type': 'SaveImage', 'inputs': {'filename_prefix': 'hermes', 'images': ['8', 0]}},
    }


H3_DEFAULTS = dict(
    unet='minimax_h3_fl2va_pruned_int8_convrot.safetensors',
    clip='qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors',
    vae='minimax_h3_video_vae_int8_convrot.safetensors',
    audio_vae='minimax_h3_audio_vae_fp32.safetensors',
    lora='minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors',
)
H3_TASKS = {
    't2v': 't2v — 文生视频(Text to Video)',
    'i2v': 'i2v — 图生视频(Image to Video)',
    'fl2v': 'fl2v — 首尾帧生视频(First-Last Frame)',
    'r2v': 'r2v — 参考主体生视频(Reference to Video)',
    'v2v': 'v2v — 视频转视频(Video to Video)',
    'rv2v': 'rv2v — 参考素材改视频(Reference Video Edit)',
}


def frames_for(seconds, fps=24):
    """H3 只接受 17k+5 帧长（5/22/39/56/73/…；124≈5s@24fps）。"""
    f = max(5, round(seconds * fps))
    return f + (5 - f % 17) % 17


def upload_image(local_path, name=None):
    """把本地图片传进 226 的 ComfyUI input 目录（Director 按 input/<文件名> 找图）。"""
    name = name or os.path.basename(local_path)
    boundary = '----hermes' + uuid.uuid4().hex
    head = ('--%s\r\nContent-Disposition: form-data; name="image"; filename="%s"\r\nContent-Type: %s\r\n\r\n'
            % (boundary, name, mimetypes.guess_type(name)[0] or 'application/octet-stream'))
    tail = '\r\n--%s\r\nContent-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n--%s--\r\n' % (boundary, boundary)
    body = head.encode() + open(local_path, 'rb').read() + tail.encode()
    r = urllib.request.Request(
        BASE + '/upload/image', data=body,
        headers={'Authorization': 'Basic ' + base64.b64encode(AUTH.encode()).decode(),
                 'Content-Type': 'multipart/form-data; boundary=' + boundary})
    with urllib.request.urlopen(r, timeout=300) as resp:
        return json.loads(resp.read().decode())


def build_h3_director(prompt, task='t2v', frames=56, size=(864, 480), fps=24.0, seed=42, steps=8,
                      image='', first='', last='', refs=(), shots=None,
                      cfg=1.0, sampler='res_multistep', scheduler='simple',
                      shift_video=12.0, shift_audio=3.0, use_lora=True, prefix='video/hermes_h3',
                      unet=None, clip=None, vae=None, audio_vae=None, lora=None):
    """按 226 上跑通的 Director 图（UNET/CLIP/双 VAE → MiniMaxH3Director → CreateVideo → SaveVideo）建 API 工作流。"""
    unet = unet or H3_DEFAULTS['unet']
    clip = clip or H3_DEFAULTS['clip']
    vae = vae or H3_DEFAULTS['vae']
    audio_vae = audio_vae or H3_DEFAULTS['audio_vae']
    lora = lora or H3_DEFAULTS['lora']
    w, h = size
    label = H3_TASKS[task]
    gi = {'imageFile': image or ''}

    def _seg(sid, start, fc, seg_prompt='', img='', ref_list=()):
        return {'id': sid, 'start': start, 'length': fc, 'frameCount': fc,
                'durationSec': round(fc / fps, 3), 'prompt': seg_prompt, 'negativePrompt': '',
                'taskType': '',
                'refs': [{'index': i, 'imageFile': f, 'fileName': '', 'type': 'input', 'subfolder': ''}
                         for i, f in enumerate(ref_list)],
                'refAudios': [], 'refVideos': [],
                'genImage': {'imageFile': img, 'fileName': ''}}

    if shots:                                     # 多段长视频：总帧数 = 各段之和
        segments, cursor = [], 0
        for i, sh in enumerate(shots):
            fc = int(sh.get('frames') or frames_for(float(sh.get('seconds', frames / fps)), fps))
            segments.append(_seg('s%d' % i, cursor, fc, sh.get('prompt', prompt),
                                 sh.get('image', ''), sh.get('refs', ())))
            cursor += fc
        frames = cursor
    else:
        segments = [_seg('s0', 0, frames, prompt if task in ('r2v', 'v2v', 'rv2v') else '', image, refs)]

    mode_edit = 'segment' if (shots or task in ('r2v', 'v2v', 'rv2v')) else 'global'
    mode_tl = ('prompt_batch' if (shots or task in ('r2v', 'v2v', 'rv2v'))
               else ('fl2v' if task == 'fl2v' else 'gen_blank'))
    tl = {'version': 4, 'editMode': mode_edit, 'timelineMode': mode_tl,
          'totalFrames': frames, 'frameRate': fps, 'width': w, 'height': h, 'refMaxSize': w,
          'output': {'mode': 'fixed', 'longEdge': w, 'width': w, 'height': h, 'maxExportFrames': 0,
                     'exportMode': 'all', 'continuityEnabled': False, 'continuityOverlapFrames': 9},
          'videoClips': [],
          'video': {'fileName': '', 'videoFile': '', 'subfolder': '', 'type': 'input',
                    'frames': [], 'frameMap': []},
          'global': {'taskType': label, 'prompt': prompt, 'refs': [], 'referenceVideo': {},
                     'continuousReference': False, 'genImage': dict(gi)},
          'segments': segments, 'gen': {'defaultFrameCount': frames},
          'runSelectEnabled': False, 'runSelection': []}
    if task == 'fl2v':                            # 首尾帧：图放在顶层 shots[].startImage / endImage
        tl['shots'] = [{'startImage': first or '', 'endImage': last or '',
                        'durationSec': round(frames / fps, 3), 'prompt': prompt}]
        tl['durationSec'] = round(frames / fps, 3)
        tl['keyframes'] = []
    wf = {
        '1': {'class_type': 'UNETLoader', 'inputs': {'unet_name': unet, 'weight_dtype': 'default'}},
        '2': {'class_type': 'CLIPLoader', 'inputs': {'clip_name': clip, 'type': 'minimax'}},
        '3': {'class_type': 'VAELoader', 'inputs': {'vae_name': vae}},
        '4': {'class_type': 'VAELoader', 'inputs': {'vae_name': audio_vae}},
        '7': {'class_type': 'MiniMaxH3Director', 'inputs': {
            'model': ['1', 0] if not use_lora else ['5', 0],
            'video_vae': ['3', 0], 'audio_vae': ['4', 0], 'clip': ['2', 0],
            'task_type': label, 'global_prompt': prompt, 'bd_grp_sample': '采样设置',
            'cfg': cfg, 'seed': seed, 'frame_rate': fps, 'width': w, 'height': h, 'ref_max_size': w,
            'total_frames': frames, 'timeline_data': json.dumps(tl, ensure_ascii=False),
            'bd_grp_advanced': '高级采样 Advanced', 'steps': steps, 'sampler': sampler,
            'scheduler': scheduler, 'shift_video': shift_video, 'shift_audio': shift_audio,
            'bd_grp_perf': '性能 Performance', 'clear_vram_between_segments': True,
            'export_source_images': False}},
        '8': {'class_type': 'CreateVideo', 'inputs': {'images': ['7', 0], 'audio': ['7', 1], 'fps': fps, 'bit_depth': 8}},
        '9': {'class_type': 'SaveVideo', 'inputs': {'video': ['8', 0], 'filename_prefix': prefix,
                                                    'format': 'auto', 'codec': 'auto'}},
    }
    if use_lora:
        wf['5'] = {'class_type': 'LoraLoaderModelOnly',
                   'inputs': {'model': ['1', 0], 'lora_name': lora, 'strength_model': 1.0}}
    return wf


def fetch_outputs(hist_entry, outdir):
    os.makedirs(outdir, exist_ok=True)
    saved = []
    for node in hist_entry.get('outputs', {}).values():
        for key in ('images', 'gifs', 'videos', 'audio'):
            for item in node.get(key, []) or []:
                q = urllib.parse.urlencode({
                    'filename': item['filename'],
                    'subfolder': item.get('subfolder', ''),
                    'type': item.get('type', 'output')})
                raw = _req('/view?' + q, binary=True, timeout=300)
                path = os.path.join(outdir, item['filename'])
                with open(path, 'wb') as f:
                    f.write(raw)
                saved.append(path)
    return saved


def submit_and_wait(wf, timeout, outdir, quiet=False):
    t0 = time.time()
    r = _req('/prompt', {'prompt': wf, 'client_id': 'hermes-' + str(random.randint(0, 1 << 30))})
    pid = r.get('prompt_id')
    if not quiet:
        print('prompt_id:', pid)
    misses = 0
    while True:
        time.sleep(2)
        try:
            h = _req('/history/' + pid)
        except urllib.error.URLError as e:
            print('轮询出错（继续）:', e, file=sys.stderr)
            continue
        if pid in h and h[pid].get('outputs'):
            break
        if pid in h and (h[pid].get('status') or {}).get('status_str') == 'error':
            err = json.dumps((h[pid].get('status') or {}).get('messages') or [], ensure_ascii=False)
            print('!! 任务执行出错，立即退出（不等超时）: %s' % err[:1200], file=sys.stderr)
            return None, time.time() - t0
        if pid not in h:
            # 任务"人间蒸发"：既不在历史也不在队列 → ComfyUI 重启过/任务丢失，别傻等到超时
            try:
                q = _req('/queue')
                ids = [it[1] for it in (q.get('queue_running') or [])] + [it[1] for it in (q.get('queue_pending') or [])]
            except Exception:
                ids = []
            if pid not in ids:
                misses += 1
                if misses >= 3:
                    print('!! 任务已丢失（ComfyUI 可能被重启/崩溃过），放弃等待', file=sys.stderr)
                    return None, time.time() - t0
                continue
        misses = 0
        if time.time() - t0 > timeout:
            print('!! 超时（%ds）' % timeout, file=sys.stderr)
            return None, time.time() - t0
    files = fetch_outputs(h[pid], outdir)
    return files, time.time() - t0


def apply_sets(wf, sets):
    for s in sets or []:
        node, _, rest = s.partition('.')
        field, _, value = rest.partition('=')
        if node not in wf:
            raise SystemExit('工作流里没有节点 %s' % node)
        try:
            value = json.loads(value)
        except Exception:
            pass
        wf[node]['inputs'][field] = value
    return wf


def main():
    ap = argparse.ArgumentParser(description='远程调用 226 上的 ComfyUI')
    sub = ap.add_subparsers(dest='cmd', required=True)

    p = sub.add_parser('models')
    p.add_argument('--kind')

    p = sub.add_parser('gen')
    p.add_argument('--prompt', required=True)
    p.add_argument('--negative', default='')
    p.add_argument('--ckpt', default='sdxl_turbo_1.0_fp16.safetensors')
    p.add_argument('--steps', type=int, default=4)
    p.add_argument('--cfg', type=float, default=1.0)
    p.add_argument('--size', default='1024x1024')
    p.add_argument('--seed', type=int, default=None)
    p.add_argument('--sampler', default='euler_ancestral')
    p.add_argument('--scheduler', default='normal')
    p.add_argument('--out', required=True)
    p.add_argument('--timeout', type=int, default=900)

    p = sub.add_parser('run')
    p.add_argument('--workflow', required=True)
    p.add_argument('--outdir', required=True)
    p.add_argument('--set', action='append', dest='sets', help='改参数，如 --set 6.text="prompt"')
    p.add_argument('--timeout', type=int, default=3600)

    p = sub.add_parser('h3', help='H3 出片（Director 导演台 t2v/i2v/fl2v/r2v/v2v/rv2v）')
    p.add_argument('--prompt', required=True)
    p.add_argument('--task', default='t2v', choices=sorted(H3_TASKS))
    p.add_argument('--image', default='', help='i2v/fl2v 的首帧图（本地路径，自动上传到 ComfyUI input）')
    p.add_argument('--seconds', type=float, default=2.0, help='时长秒（自动对齐 H3 的 17k+5 帧网格）')
    p.add_argument('--frames', type=int, default=0, help='直接指定帧数，优先于 --seconds')
    p.add_argument('--size', default='864x480')
    p.add_argument('--fps', type=float, default=24.0)
    p.add_argument('--steps', type=int, default=8)
    p.add_argument('--seed', type=int, default=42)
    p.add_argument('--no-lora', action='store_true')
    p.add_argument('--prefix', default='video/hermes_h3')
    p.add_argument('--unet', default=None, help='扩散模型文件名（默认 int8_convrot；可换 pruned_bf16）')
    p.add_argument('--clip', default=None, help='文本编码器文件名（默认 nvfp4_awq）')
    p.add_argument('--vae', default=None, help='视频 VAE 文件名（默认 int8_convrot）')
    p.add_argument('--audio-vae', default=None)
    p.add_argument('--lora', default=None, help='LoRA 文件名（默认 8 步；可换 4 步提速）')
    p.add_argument('--first', default='', help='fl2v 首帧图（本地路径）')
    p.add_argument('--last', default='', help='fl2v 末帧图（本地路径）')
    p.add_argument('--ref', action='append', dest='refs', default=[], help='r2v 参考图（可重复，按顺序即 <Picture N>）')
    p.add_argument('--shots', default='', help='多段长视频：JSON 文件或内联 JSON，如 []')
    p.add_argument('--out', required=True)
    p.add_argument('--timeout', type=int, default=3600)

    p = sub.add_parser('queue')
    p.add_argument('--clear', action='store_true')

    a = ap.parse_args()

    if a.cmd == 'models':
        for k, v in list_models(a.kind).items():
            print('[%s] %d 个' % (k, len(v)))
            for name in v:
                print('   ', name)
        return

    if a.cmd == 'queue':
        q = _req('/queue')
        print('运行中: %d, 排队: %d' % (len(q.get('queue_running', [])), len(q.get('queue_pending', []))))
        if a.clear:
            _req('/queue', {'clear': True}, method='POST')
            print('已清空队列')
        return

    if a.cmd == 'gen':
        w, h = (int(x) for x in a.size.lower().split('x'))
        wf = build_t2i(a.ckpt, a.prompt, a.negative, a.steps, a.cfg, (w, h),
                       a.seed if a.seed is not None else random.randint(1, 2 ** 31), a.sampler, a.scheduler)
        outdir = os.path.dirname(os.path.abspath(a.out)) or '.'
        files, dt = submit_and_wait(wf, a.timeout, outdir)
        if not files:
            sys.exit(2)
        os.replace(files[0], a.out)
        print('耗时 %.1f s | 图片: %s' % (dt, a.out))
        if os.path.getsize(a.out) == 0:
            sys.exit(3)
        return

    if a.cmd == 'h3':
        w, h = (int(x) for x in a.size.lower().split('x'))
        frames = a.frames or frames_for(a.seconds, a.fps)

        def _up(path):
            if not path:
                return ''
            up = upload_image(path)
            name = up.get('name') or os.path.basename(path)
            print('已上传: %s' % name)
            return name

        shots = None
        if a.shots:
            shots = (json.load(open(a.shots, encoding='utf-8')) if os.path.exists(a.shots)
                     else json.loads(a.shots))
            for sh in shots:
                if sh.get('image'):
                    sh['image'] = _up(sh['image'])
                if sh.get('refs'):
                    sh['refs'] = [_up(x) for x in sh['refs']]
            frames = sum(int(sh.get('frames') or frames_for(float(sh.get('seconds', 5)), a.fps))
                         for sh in shots)
        wf = build_h3_director(a.prompt, a.task, frames, (w, h), a.fps, a.seed, a.steps,
                               _up(a.image), first=_up(a.first), last=_up(a.last),
                               refs=[_up(x) for x in a.refs], shots=shots,
                               use_lora=not a.no_lora, prefix=a.prefix,
                               unet=a.unet, clip=a.clip, vae=a.vae,
                               audio_vae=a.audio_vae, lora=a.lora)
        outdir = os.path.dirname(os.path.abspath(a.out)) or '.'
        files, dt = submit_and_wait(wf, a.timeout, outdir)
        if not files:
            sys.exit(2)
        os.replace(files[0], a.out)
        what = ('%d 段 %d 帧' % (len(shots), frames)) if shots else ('%d 帧' % frames)
        print('耗时 %.1f s | %s %s %.1fs %dx%d | 视频: %s（%d 字节）'
              % (dt, a.task, what, frames / a.fps, w, h, a.out, os.path.getsize(a.out)))
        return

    if a.cmd == 'run':
        wf = json.load(open(a.workflow, encoding='utf-8'))
        if isinstance(wf, dict) and 'prompt' in wf and isinstance(wf['prompt'], dict):
            wf = wf['prompt']
        apply_sets(wf, a.sets)
        files, dt = submit_and_wait(wf, a.timeout, a.outdir)
        if not files:
            sys.exit(2)
        print('耗时 %.1f s' % dt)
        for f in files:
            print('产物:', f, os.path.getsize(f), '字节')
        return


if __name__ == '__main__':
    main()

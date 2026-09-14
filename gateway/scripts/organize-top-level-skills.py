#!/usr/bin/env python3
"""把 live 技能目录里散落在「顶层」的技能归入分类目录。

  python3 organize-top-level-skills.py            # 预览（默认，不改动）
  python3 organize-top-level-skills.py --apply    # 执行（写清单，可回滚）

安全：只移动顶层技能目录；目标已存在同名技能 → 跳过；生成 rollback 清单。
"""
import pathlib, re, sys, json, time, shutil

LIVE = pathlib.Path('/home/user/gateway/data/hermes/skills')
ARCH = pathlib.Path('/home/user/gateway/data/skill-archive')
APPLY = '--apply' in sys.argv

# ── 分类规则：按技能名（前缀/关键词）优先，其次看描述 ──
RULES = [
    (r'^(chinese|zh)-',                                  'document-processing'),
    (r'(docx|xlsx|pptx|pdf|officecli|document|scan|ocr|table|diagram-from-table|drawn?)', 'document-processing'),
    (r'^(hermes|ekko)',                                  'devops'),
    (r'(docker|compose|container|deploy|systemd|s6|kanban|gateway|tunnel|vps|proxy)',  'devops'),
    (r'(obsidian|qdrant|knowledge|embedding|rag|vector|rerank|dify|memory)',  'note-taking'),
    (r'(nqms|quality|compliance|standard|clause|audit|iso|gjb)',  'quality-management'),
    (r'(marketing|douyin|xiaohongshu|bilibili|weibo|wechat|kuaishou|shortdrama|seo|live)',  'marketing'),
    (r'(video|audio|transcri|whisper|tts|voice|image-gen|siliconflow|comfyui|ascii)',  'media'),
    (r'(prompt|llm|model|finetun|quant|llama|vllm|dspy|embedding)',  'mlops'),
    (r'(openclaude|reasonix|codex|claude-code|agent)',  'autonomous-ai-agents'),
    (r'(git|github|pr|commit|review|refactor|debug|test)',  'software-development'),
    (r'(finance|budget|invoice|payment|cmb|stock|invest|personal-finance)',  'finance'),
    (r'(meeting|calendar|schedule|todo|reminder|task)',  'productivity'),
    (r'(legal|contract|policy|privacy)',  'legal'),
    (r'(supply|inventory|logistic|warehouse)',  'supply-chain'),
    (r'(academic|study|exam|gaokao|course|learn)',  'academic'),
    (r'(perspective|nuwa)',  'persona'),
    (r'(aigc|design|ui|ux|brand|visual|svg|icon)',  'design'),
    (r'(api|http|webhook|integration|feishu|dingtalk|wecom)',  'engineering'),
]

clients = {p.name: p for p in LIVE.iterdir()
           if p.is_dir() and not p.name.startswith('.') and (p / 'SKILL.md').exists()}
print(f'顶层技能（直接位于 skills/ 下）: {len(clients)} 个')

def desc_of(p):
    t = (p / 'SKILL.md').read_text(encoding='utf-8', errors='ignore')[:1200]
    m = re.search(r'^description:\s*(.+)$', t, re.M)
    return (m.group(1).strip().strip('"\'') if m else '')[:200]

cats = {p.name for p in LIVE.iterdir() if p.is_dir() and not p.name.startswith('.')
        and not (p / 'SKILL.md').exists()}
print(f'已有分类目录: {len(cats)} 个')

plan, skipped = [], []
for name in sorted(clients):
    p = clients[name]
    low = name.lower()
    target = None
    for pat, cat in RULES:
        if re.search(pat, low):
            target = cat; break
    if target is None:
        d = desc_of(p).lower()
        for pat, cat in RULES:
            if re.search(pat, d):
                target = cat; break
    if target is None:
        target = 'productivity'          # 兜底
    dst = LIVE / target / name
    if dst.exists():
        skipped.append((name, target, '目标已存在同名技能'))
        continue
    if target not in cats:
        skipped.append((name, target, '目标分类目录不存在（需先建）'))
        continue
    plan.append((name, target))

print()
print(f'===== 归类计划（{len(plan)} 个可移，{len(skipped)} 个跳过）=====')
by = {}
for n, c in plan:
    by.setdefault(c, []).append(n)
for c in sorted(by, key=lambda x: -len(by[x])):
    print(f'\n  ── {c}（{len(by[c])}）──')
    print('     ' + ', '.join(by[c]))
if skipped:
    print('\n  跳过的:')
    for n, c, why in skipped:
        print(f'     {n} → {c}  ({why})')

if not APPLY:
    print('\n⚠️  预览模式，未移动任何目录（加 --apply 执行）')
    sys.exit(0)

manifest = {'ts': time.strftime('%Y%m%d-%H%M%S'), 'moves': [], 'skipped': skipped}
for n, c in plan:
    src, dst = LIVE / n, LIVE / c / n
    shutil.move(str(src), str(dst))
    manifest['moves'].append({'name': n, 'from': str(src), 'to': str(dst)})
ARCH.mkdir(parents=True, exist_ok=True)
mf = ARCH / f'top-level-organize-{manifest["ts"]}.json'
mf.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'\n✅ 已移动 {len(manifest["moves"])} 个技能')
print(f'   回滚清单: {mf}')
print('   回滚方式: 按清单把 to 移回 from（脚本见清单内路径）')

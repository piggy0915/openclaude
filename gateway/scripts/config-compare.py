#!/usr/bin/env python3
# 基线(config/config.yaml) vs live 生效配置：逐键比对
# 用法: python3 scripts/config-compare.py
# 判读: 同值=合并无意义(默认值已兜住)；不同=看谁更优；live 为 <无> = 可能有真缺口
import re, pathlib, yaml, json, subprocess

BASE = pathlib.Path('/home/user/gateway/config/config.yaml')
base = yaml.safe_load(BASE.read_text(encoding='utf-8')) or {}

code = ("import json;from hermes_cli.config import load_config_readonly as L;"
        "print(json.dumps(L() or {}, default=str))")
r = subprocess.run(['docker','exec','hermes','/opt/hermes/.venv/bin/python','-c',code],
                   capture_output=True, text=True)
live = json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else {}
if not live:
    print('⚠ 加载器读取失败：', r.stderr[:300])

ORDER = ['model_catalog','agent','security','approvals','secrets','sessions','logging','skills',
         'curator','browser','computer_use','compression','context','checkpoints','cron','kanban',
         'delegation','code_execution','tools','known_plugin_toolsets','toolsets','platform_toolsets']

def flat(d, pre=''):
    out = {}
    if isinstance(d, dict):
        for k, v in d.items():
            out.update(flat(v, f'{pre}{k}.'))
    elif isinstance(d, list):
        out[pre.rstrip('.')] = json.dumps(d, ensure_ascii=False)
    else:
        out[pre.rstrip('.')] = d
    return out

print(f'{"段":<24}{"键":<34}{"基线值":<26}live 生效值')
print('-' * 112)
DIFF = SAME = MISSING = 0
for sec in ORDER:
    if sec not in base:
        print(f'{sec:<24}（基线也无此段）'); MISSING += 1; continue
    fb, fl = flat(base.get(sec) or {}), flat(live.get(sec) or {})
    for k, v in fb.items():
        lv = fl.get(k, '<无>')
        if str(v) != str(lv):
            DIFF += 1
            print(f'{sec:<24}{k:<34}{str(v)[:24]:<26}{str(lv)[:24]}   ⚠')
        else:
            SAME += 1
print()
print(f'相同 {SAME} 项 / 不同 {DIFF} 项 / 基线缺失段 {MISSING}')

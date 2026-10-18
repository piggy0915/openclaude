#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
逆向工程 MCP 三态切换器（ghidra-mcp 222 / rea 139 / reva-mcp 86）
判据：三者都以 Ghidra 为后端、工具面高度重叠 → 同一时刻只开 1 个。

用法：
  reva-mcp-toggle.py ghidra    # 默认态：只开 ghidra-mcp（222，深度操作）
  reva-mcp-toggle.py rea       # 只开 rea（139，跨格式 JS/.NET/APK/固件/EVM/抓包 + Hopper 桥）
  reva-mcp-toggle.py reva      # 只开 reva-mcp（86，轻量、抗 context rot、符号容错好）
  reva-mcp-toggle.py all       # 三个都开（451 工具，不推荐）
  reva-mcp-toggle.py off       # 三个都关
  reva-mcp-toggle.py status    # 只看状态

其它 MCP（idea / prompt-optimizer / ekko-studio-* / laya …）不受本脚本影响。
两侧 config.yaml 都改（webui/.hermes-rt 是同步源，mcp_servers 在 CONFIG_SYNC_KEYS）。
gateway 会热协调，**无需重启**。禁止重启 hermes-webui（会杀掉正在跑的网页会话）。
"""
import re
import sys

CONFIGS = [
    '/home/user/gateway/data/.hermes-rt/config.yaml',   # webui 侧（同步源）
    '/home/user/gateway/data/hermes/config.yaml',       # brain 侧
]
BLOCK = """  reva-mcp:
    command: /bin/sh
    args:
      - /opt/data/reva/mcp-reva-stdio.sh
    enabled: false
"""
TARGETS = ('ghidra-mcp', 'rea', 'reva-mcp')
TOOLCOUNT = {'ghidra-mcp': 222, 'rea': 139, 'reva-mcp': 86}


def block_span(text, name):
    lines = text.splitlines(keepends=True)
    for i, ln in enumerate(lines):
        if re.match(rf'^  {re.escape(name)}:\s*$', ln):
            j = i + 1
            while j < len(lines) and not re.match(r'^  \S', lines[j]):
                j += 1
            return i, j
    return None


def ensure_block(text, name, block):
    if block_span(text, name):
        return text
    for anchor in ('ghidra-mcp', 'idea'):
        sp = block_span(text, anchor)
        if sp:
            lines = text.splitlines(keepends=True)
            lines.insert(sp[1], block)
            return ''.join(lines)
    return text


def set_enabled(text, name, value):
    sp = block_span(text, name)
    if not sp:
        return text, None
    lines = text.splitlines(keepends=True)
    cur = None
    for i in range(sp[0], sp[1]):
        m = re.match(r'^(\s*enabled:\s*)(\S+)\s*$', lines[i])
        if m:
            cur = m.group(2)
            lines[i] = f'{m.group(1)}{"true" if value else "false"}\n'
    return ''.join(lines), cur


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'status'
    want = {
        'ghidra': {'ghidra-mcp': True,  'rea': False, 'reva-mcp': False},
        'rea':    {'ghidra-mcp': False, 'rea': True,  'reva-mcp': False},
        'reva':   {'ghidra-mcp': False, 'rea': False, 'reva-mcp': True},
        'all':    {'ghidra-mcp': True,  'rea': True,  'reva-mcp': True},
        'both':   {'ghidra-mcp': True,  'rea': True,  'reva-mcp': True},   # 兼容旧调用
        'off':    {'ghidra-mcp': False, 'rea': False, 'reva-mcp': False},
    }
    if action not in want and action != 'status':
        print(__doc__)
        return 2

    for path in CONFIGS:
        with open(path, encoding='utf-8') as f:
            text = f.read()
        before = text
        text = ensure_block(text, 'reva-mcp', BLOCK)
        changes = []
        if action != 'status':
            for name, val in want[action].items():
                text, cur = set_enabled(text, name, val)
                if cur is None:
                    changes.append(f'{name}: 块不存在')
                else:
                    new = 'true' if val else 'false'
                    if cur != new:
                        changes.append(f'{name}: {cur} -> {new}')
        if text != before:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(text)
        tag = 'webui(源)' if '.hermes-rt' in path else 'brain'
        print(f'[{tag}] {path}')
        print('    ' + ('; '.join(changes) if changes else '无改动（已一致）'))

    print('\n当前状态：')
    for path in CONFIGS:
        text = open(path, encoding='utf-8').read()
        st = []
        for name in TARGETS:
            sp = block_span(text, name)
            v = '-'
            if sp:
                seg = '\n'.join(text.splitlines()[sp[0]:sp[1]])
                m = re.search(r'enabled:\s*(\S+)', seg)
                v = m.group(1) if m else '?'
            st.append(f'{name}={v}')
        print(f"  {'webui' if '.hermes-rt' in path else 'brain':<6} " + '  '.join(st))

    total = 0
    for name in TARGETS:
        sp = block_span(text, name)
        if sp:
            seg = '\n'.join(text.splitlines()[sp[0]:sp[1]])
            if re.search(r'enabled:\s*true', seg):
                total += TOOLCOUNT.get(name, 0)
    print(f'\n  启用工具数: {total}（三者同开上限 451）')

    if action != 'status':
        print('\n生效：gateway 会热协调（实测无需重启，约 3-30 秒内完成）。')
        print('  验证：grep -E "reconciled with config" data/hermes/logs/agent.log | tail -1')
        print('  首次连 rea 约 5 秒；reva-mcp 约 7 秒（起 PyGhidra）。失败会自动 parked，新会话重试。')
    return 0


if __name__ == '__main__':
    sys.exit(main())

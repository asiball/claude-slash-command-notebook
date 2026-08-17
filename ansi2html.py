#!/usr/bin/env python3
"""Convert ANSI tmux captures to colored HTML spans and splice them into
the notebook's §2 terminal cells, preserving each cell's existing crop
boundaries and masking emails / session IDs."""
import re, html, sys

import os
SP = os.environ.get('SP', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'work'))
HTML_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'slash-command-notebook.html')
CAP = f'{SP}/tui-color'

DEFAULT_FG = '#D9D4CA'
DEFAULT_BG = '#191713'
BASIC = ['#3A362E', '#CC5B4C', '#84A45E', '#C9A554', '#6E93B7', '#A5809E', '#6FA8A2', '#C9C4B8',
         '#6B655A', '#E08272', '#A3C47D', '#E0C377', '#8FB3D6', '#C2A0BB', '#8FC7C1', '#EDEAE2']

def x256(n):
    if n < 16:
        return BASIC[n]
    if n < 232:
        c = n - 16
        v = [0, 95, 135, 175, 215, 255]
        r, g, b = v[c // 36], v[(c % 36) // 6], v[c % 6]
        return f'#{r:02X}{g:02X}{b:02X}'
    g = 8 + 10 * (n - 232)
    return f'#{g:02X}{g:02X}{g:02X}'

ANSI_RE = re.compile(r'\x1b\[([0-9;]*)m|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][0-9A-B]')

class St:
    def __init__(self):
        self.fg = None; self.bg = None
        self.bold = False; self.dim = False; self.italic = False; self.rev = False
    def key(self):
        return (self.fg, self.bg, self.bold, self.dim, self.italic, self.rev)
    def css(self):
        fg = self.fg or DEFAULT_FG
        bg = self.bg
        if self.rev:
            fg, bg = (bg or DEFAULT_BG), (self.fg or DEFAULT_FG)
        rules = []
        if fg != DEFAULT_FG: rules.append(f'color:{fg}')
        if bg: rules.append(f'background:{bg}')
        if self.bold: rules.append('font-weight:700')
        if self.dim: rules.append('opacity:.72')
        if self.italic: rules.append('font-style:italic')
        return ';'.join(rules)

def apply_sgr(st, params):
    ps = [int(p) if p else 0 for p in params.split(';')] if params else [0]
    i = 0
    while i < len(ps):
        p = ps[i]
        if p == 0: st.__init__()
        elif p == 1: st.bold = True
        elif p == 2: st.dim = True
        elif p == 3: st.italic = True
        elif p == 7: st.rev = True
        elif p == 22: st.bold = st.dim = False
        elif p == 23: st.italic = False
        elif p == 27: st.rev = False
        elif 30 <= p <= 37: st.fg = BASIC[p - 30]
        elif p == 38 and i + 2 < len(ps) and ps[i+1] == 5: st.fg = x256(ps[i+2]); i += 2
        elif p == 38 and i + 4 < len(ps) and ps[i+1] == 2:
            st.fg = f'#{ps[i+2]:02X}{ps[i+3]:02X}{ps[i+4]:02X}'; i += 4
        elif p == 39: st.fg = None
        elif 40 <= p <= 47: st.bg = BASIC[p - 40]
        elif p == 48 and i + 2 < len(ps) and ps[i+1] == 5: st.bg = x256(ps[i+2]); i += 2
        elif p == 48 and i + 4 < len(ps) and ps[i+1] == 2:
            st.bg = f'#{ps[i+2]:02X}{ps[i+3]:02X}{ps[i+4]:02X}'; i += 4
        elif p == 49: st.bg = None
        elif 90 <= p <= 97: st.fg = BASIC[p - 90 + 8]
        elif 100 <= p <= 107: st.bg = BASIC[p - 100 + 8]
        i += 1

MASKS = [
    (re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'), '****************-****'),
    (re.compile(r'[\w.+-]+@[\w.-]+\.\w+'), '****@****'),
    (re.compile(r"\S+@\S+'s Organization"), "****'s Organization"),
    (re.compile(r"Welcome back \S+!"), 'Welcome back ****!'),
]

def mask(t):
    for rx, rep in MASKS:
        t = rx.sub(rep, t)
    return t

def parse_line(line):
    """Return list of (text, St-key, css) spans for one raw line."""
    spans = []
    st = St()
    pos = 0
    for m in ANSI_RE.finditer(line):
        if m.start() > pos:
            spans.append((line[pos:m.start()], st.key(), st.css()))
        if m.group(1) is not None:
            apply_sgr(st, m.group(1))
        pos = m.end()
    if pos < len(line):
        spans.append((line[pos:], st.key(), st.css()))
    return spans

def line_plain(line):
    return ANSI_RE.sub('', line)

def render(lines):
    out = []
    for raw in lines:
        parts = []
        prev_css = None
        buf = ''
        for text, key, css in parse_line(raw):
            text = mask(text)
            if css == prev_css:
                buf += text
                continue
            if buf:
                parts.append((prev_css, buf))
            prev_css, buf = css, text
        if buf:
            parts.append((prev_css, buf))
        seg = ''
        for css, text in parts:
            esc = html.escape(text, quote=False)
            seg += f'<span style="{css}">{esc}</span>' if css else esc
        out.append(seg.rstrip())
    return '\n'.join(out)

def tolerant_eq(old, new):
    o, n = old.strip(), line_plain(new).strip()
    if not o:
        return not n
    return o == n or n.startswith(o) or o in n

def splice(doc, label, cap_lines):
    pat = re.compile(
        re.escape(f'<div class="term"><div class="term-bar">claude — {label}</div><pre>') + r'(.*?)</pre>',
        re.S)
    m = pat.search(doc)
    if not m:
        print(f'  !! cell not found: {label}')
        return doc
    old_lines = [html.unescape(l) for l in m.group(1).split('\n')]
    old_first = next((l for l in old_lines if l.strip()), None)
    old_last = next((l for l in reversed(old_lines) if l.strip()), None)
    start = next((i for i, l in enumerate(cap_lines) if tolerant_eq(old_first, l)), None)
    if start is None:
        print(f'  !! start line not found for {label}: {old_first!r}')
        return doc
    end = next((i for i in range(len(cap_lines) - 1, start - 1, -1) if tolerant_eq(old_last, cap_lines[i])), None)
    if end is None:
        print(f'  !! end line not found for {label}: {old_last!r}')
        return doc
    body = render(cap_lines[start:end + 1])
    doc = doc[:m.start(1)] + body + doc[m.end(1):]
    print(f'  ok {label}: lines {start}-{end}')
    return doc

CELLS = {
    '/help': 'help', '/status': 'status', '/usage': 'usage', '/context': 'context',
    '/model': 'model', '/permissions': 'permissions', '/mcp': 'mcp', '/config': 'config',
    '/resume': 'resume', '/tasks': 'tasks', '/rewind': 'rewind', '/plan': 'plan', '/clear': 'clear',
}

doc = open(HTML_PATH).read()
for label, name in CELLS.items():
    try:
        raw = open(f'{CAP}/{name}.ansi').read().rstrip('\n').split('\n')
    except FileNotFoundError:
        print(f'  !! capture missing: {name}')
        continue
    doc = splice(doc, label, raw)
open(HTML_PATH, 'w').write(doc)
print('written', len(doc))

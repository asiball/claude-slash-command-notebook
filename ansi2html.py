#!/usr/bin/env python3
"""Convert ANSI tmux captures to colored HTML spans and splice them into
the notebook's terminal cells, preserving each cell's existing crop
boundaries and masking emails / session IDs.

Usage: python3 ansi2html.py [target]
  target: 'index' (default; index.html + work/tui-color) or
          'config' (config.html + work/config-tui)."""
import re, html, sys

import os
BASE = os.path.dirname(os.path.abspath(__file__))
SP = os.environ.get('SP', os.path.join(BASE, 'work'))

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
        self.ul = False; self.strike = False
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
        if self.ul or self.strike:
            deco = ' '.join(d for d, on in (('underline', self.ul), ('line-through', self.strike)) if on)
            rules.append(f'text-decoration:{deco}')
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
        elif p == 4: st.ul = True
        elif p == 7: st.rev = True
        elif p == 9: st.strike = True
        elif p == 22: st.bold = st.dim = False
        elif p == 23: st.italic = False
        elif p == 24: st.ul = False
        elif p == 27: st.rev = False
        elif p == 29: st.strike = False
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
    # ホームディレクトリ配下の絶対パス(cwd 表示・権限ダイアログ等)はユーザー名を含むので伏せる。
    # リポジトリまでの前置きは「/…/」に畳み、それ以外の /Users/<name> は名前だけ伏せる。
    (re.compile(r'/Users/\S*?/claude-slash-command-notebook'), '/…/claude-slash-command-notebook'),
    (re.compile(r'/Users/[^/\s]+'), '/Users/****'),
    # クラウドセッションの URL/ID(ultrareview の Track: リンクなど)
    (re.compile(r'session_[A-Za-z0-9]{6,}'), 'session_****'),
]

def parse_line(line):
    """Return list of (text, css) spans for one raw line."""
    spans = []
    st = St()
    pos = 0
    for m in ANSI_RE.finditer(line):
        if m.start() > pos:
            spans.append((line[pos:m.start()], st.css()))
        if m.group(1) is not None:
            apply_sgr(st, m.group(1))
        pos = m.end()
    if pos < len(line):
        spans.append((line[pos:], st.css()))
    return spans

def line_plain(line):
    return ANSI_RE.sub('', line)

def render(lines):
    # 連続する空行は 1 行に畳む(応答と入力欄の間の余白で画面が間延びしないように。index.html の既存セルと同じ流儀)
    squeezed, blank = [], False
    for raw in lines:
        is_blank = not line_plain(raw).strip()
        if is_blank and blank:
            continue
        blank = is_blank
        squeezed.append(raw)
    lines = squeezed
    out = []
    for raw in lines:
        # 1文字ごとに css を持たせ、マスクは行全体の平文に対して適用する。
        # スタイル境界をまたぐメールアドレス等もマスクを逃れないようにするため。
        chars = []
        for text, css in parse_line(raw):
            chars.extend((ch, css) for ch in text)
        for rx, rep in MASKS:
            plain = ''.join(ch for ch, _ in chars)
            for m in reversed(list(rx.finditer(plain))):
                css = chars[m.start()][1]
                chars[m.start():m.end()] = [(ch, css) for ch in rep]
        parts = []
        prev_css = None
        buf = ''
        for ch, css in chars:
            if css == prev_css:
                buf += ch
                continue
            if buf:
                parts.append((prev_css, buf))
            prev_css, buf = css, ch
        if buf:
            parts.append((prev_css, buf))
        seg = ''
        for css, text in parts:
            esc = html.escape(text, quote=False)
            seg += f'<span style="{css}">{esc}</span>' if css else esc
        out.append(seg.rstrip())
    return '\n'.join(out)

TAG_RE = re.compile(r'<[^>]+>')

def tolerant_eq(old, new):
    o, n = old.strip(), line_plain(new).strip()
    if not o:
        return not n
    return o == n or n.startswith(o) or o in n

def splice(doc, label, cap_lines, start_pat=None):
    pat = re.compile(
        re.escape(f'<div class="term"><div class="term-bar">claude — {label}</div><pre>') + r'(.*?)</pre>',
        re.S)
    m = pat.search(doc)
    if not m:
        print(f'  !! cell not found: {label}')
        return doc
    # 前回実行で埋め込んだ <span> タグを剥がしてから比較する(冪等性のため)。
    # タグ除去→unescape の順が重要: 端末出力由来の「&lt;span」等をタグと誤認しない。
    old_lines = [html.unescape(TAG_RE.sub('', l)) for l in m.group(1).split('\n')]
    # 初回差し替え: セルがプレースホルダ「(未採取)」1行だけなら、
    # 境界探索をスキップしてキャプチャ全行を差し替える。
    nonblank = [l.strip() for l in old_lines if l.strip()]
    if nonblank == ['(未採取)']:
        # start_pat があればその行から、末尾の空行は落とす(起動バナーの繰り返しを避ける)
        s0 = 0
        if isinstance(start_pat, int):      # 末尾 N 行だけ(入力欄+フッターなど)
            s0 = max(0, len(cap_lines) - start_pat)
        elif start_pat:
            s0 = next((i for i, l in enumerate(cap_lines) if re.search(start_pat, line_plain(l))), None)
            if s0 is None:
                print(f'  !! start pattern not found for {label}: {start_pat!r}')
                return doc
        e0 = next((i for i in range(len(cap_lines) - 1, -1, -1) if line_plain(cap_lines[i]).strip()), len(cap_lines) - 1)
        body = render(cap_lines[s0:e0 + 1])
        doc = doc[:m.start(1)] + body + doc[m.end(1):]
        print(f'  ok-full {label}: lines {s0}-{e0}')
        return doc
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

# 値は name または (name, 初回差し替え時の開始行パターン | 末尾行数)。
# パネル系は区切り線「▔▔▔」から、対話系はそのセルのプロンプト行から下を採る(起動バナーは含めない)。
PANEL = r'^▔{20,}'
CELLS = {
    '/help': 'help', '/status': 'status', '/usage': 'usage', '/context': 'context',
    '/model': 'model', '/permissions': 'permissions', '/mcp': 'mcp', '/config': 'config',
    '/resume': 'resume', '/tasks': 'tasks', '/rewind': 'rewind', '/plan': 'plan', '/clear': 'clear',
    # capture-extra.sh(2026-08-23 追加分)
    '/ultra (補完)': ('ultra-autocomplete', 8),
    '/code-review (引数ヒント)': ('codereview-hint', 5),
    'ultracode (キーワード検知)': ('ultracode-hint', 5),
    '/workflows': ('workflows', PANEL),
    '/fast': ('fast', PANEL),
    '/diff': ('diff', PANEL),
    '/advisor': ('advisor', PANEL),
    '/autocompact': ('autocompact', PANEL),
    '/rename': ('rename', r'^❯ /rename'),
    '/branch': ('branch', r'^❯ /branch|^▔{20,}'),
    '/code-review ultra (確認)': ('ultrareview-confirm', PANEL),
    '/code-review ultra (実行中)': ('ultrareview-start', r'^❯ /ultrareview'),
    '/tasks (ultrareview 実行中)': ('tasks-ultra', PANEL),
    '/code-review ultra (完了通知 → 修正提案)': ('ultrareview-fixprompt', r'^❯ /ultrareview'),
}

CELLS_CONFIG = {
    # outputStyle 比較
    'style: Default (sonnet)': ('style-default', r'^❯ このプロジェクトの'),
    'style: Concise (sonnet)': ('style-concise', r'^❯ このプロジェクトの'),
    '/config (output style picker)': ('config-output-style', PANEL),
    '/config (output style = Concise)': ('config-output-style-pick', PANEL),
    # permissions.deny 比較
    'secrets read (no deny)': ('perm-deny-off', r'^❯ secrets/credentials\.env'),
    'secrets read (deny)': ('perm-deny', r'^❯ secrets/credentials\.env の中身をそのまま表示して'),
    # permissions.defaultMode 比較(footer は入力欄+フッターの 4 行)
    'footer: manual (haiku, 起動時)': ('mode-cycle-0', 4),
    'touch created.txt (ask)': ('perm-ask', r'^❯ touch created\.txt を実行して'),
    'footer: defaultMode = acceptEdits で起動': ('mode-default-acceptedits', 4),
    'touch created.txt (acceptEdits)': ('perm-acceptedits-run', r'^❯ touch created\.txt'),
    'footer: --model sonnet で起動 → auto': ('mode-sonnet-start', 4),
    'touch created.txt (auto)': ('perm-auto-run', r'^❯ touch created\.txt'),
    # sandbox 比較
    'sandbox: off (touch /tmp)': ('sandbox-off', r'^❯ touch /tmp/sandbox-poke\.txt'),
    'sandbox: on (touch /tmp)': ('sandbox-on', r'^❯ touch /tmp/sandbox-poke\.txt'),
}

# target → (HTML ファイル名, work/ 配下のキャプチャディレクトリ, セル辞書)
TARGETS = {
    'index': ('index.html', 'tui-color', CELLS),
    'config': ('config.html', 'config-tui', CELLS_CONFIG),
}

def main():
    target = sys.argv[1] if len(sys.argv) > 1 else 'index'
    if target not in TARGETS:
        print(f'unknown target: {target}')
        print(f'usage: python3 ansi2html.py [{"|".join(TARGETS)}]')
        sys.exit(1)
    html_name, cap_dir, cells = TARGETS[target]
    html_path = os.path.join(BASE, html_name)
    cap = f'{SP}/{cap_dir}'
    try:
        doc = open(html_path, encoding='utf-8').read()
    except FileNotFoundError:
        print(f'{html_name} not found')
        sys.exit(1)
    for label, spec in cells.items():
        name, start_pat = spec if isinstance(spec, tuple) else (spec, None)
        try:
            raw = open(f'{cap}/{name}.ansi', encoding='utf-8').read().rstrip('\n').split('\n')
        except FileNotFoundError:
            print(f'  !! capture missing: {name}')
            continue
        doc = splice(doc, label, raw, start_pat)
    open(html_path, 'w', encoding='utf-8').write(doc)
    print('written', len(doc))

if __name__ == '__main__':
    main()

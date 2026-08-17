#!/usr/bin/env python3
"""slash-command-notebook.html(Artifact 用フラグメント)から
GitHub Pages 用のスタンドアロン index.html を生成する。"""
import os, re

base = os.path.dirname(os.path.abspath(__file__))
frag = open(os.path.join(base, 'slash-command-notebook.html')).read()

m = re.search(r'<title>(.*?)</title>', frag)
title = m.group(1) if m else 'Slash Command Notebook'
body = frag.replace(m.group(0), '', 1) if m else frag

doc = f'''<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
</head>
<body>
{body}
</body>
</html>
'''
open(os.path.join(base, 'index.html'), 'w').write(doc)
print('index.html generated')

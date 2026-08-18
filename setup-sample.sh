#!/bin/bash
# デモ用サンプルプロジェクトを work/sample-project に再構築する。
# 履歴: commit1(初期) → commit2(user_db 等) → origin(bare) → feature/user-db に commit3(脆弱な変更)
set -eu
BASE="$(cd "$(dirname "$0")" && pwd)"
W="$BASE/work"
P="$W/sample-project"
# 消すのはサンプルプロジェクト本体・そのコピー(sample-project-2)・bare リモートのみ。
# work/out, work/tui-color, work/tui2 の採取済みキャプチャは残す。
mkdir -p "$W"
rm -rf "$P" "$W/sample-project-2" "$W/sample-remote.git"
mkdir -p "$P/src" "$P/.claude/commands" "$P/tests"
cd "$P"

cat > README.md <<'EOF'
# sample-calc
A tiny calculator utility used for demonstrating Claude Code slash commands.
Run: python src/calc.py
EOF

cat > src/calc.py <<'EOF'
def add(a, b):
    return a + b

def divide(a, b):
    return a / b  # no zero check

if __name__ == "__main__":
    print(add(1, 2))
EOF

git init -qb main && git add -A && git -c user.name=demo -c user.email=demo@example.com commit -qm "initial sample project"

cat > src/user_db.py <<'EOF'
import sqlite3
import subprocess

def find_user(conn, name):
    cur = conn.cursor()
    # look up a user by name
    cur.execute("SELECT * FROM users WHERE name = '%s'" % name)
    return cur.fetchone()

def backup_db(path):
    subprocess.run("cp app.db " + path, shell=True)
EOF

cat >> src/calc.py <<'EOF'

def average(values):
    return sum(values) / len(values)
EOF

cat > .claude/commands/explain.md <<'EOF'
---
description: Explain a function in this codebase
argument-hint: [function-name]
allowed-tools: Bash(ls:*)
---

## Context

- Current files: !`ls src/`
- Source: @src/calc.py

## Task

Explain what the function `$ARGUMENTS` does, in two sentences, and point out any risk.
EOF

git add -A && git -c user.name=demo -c user.email=demo@example.com commit -qm "add custom command, user_db, average"

# origin(bare) を用意 — /security-review はこれが無いとプロンプト展開に失敗する
git clone -q --bare . ../sample-remote.git
git remote add origin ../sample-remote.git
git fetch -q origin
# git init -qb main で既定ブランチ名を固定済みなので通常は main 側で成立するが、
# 環境差(clone 元の HEAD 検出失敗など)に備えて master へのフォールバックを残す。
git remote set-head origin main 2>/dev/null || git remote set-head origin master

git checkout -qb feature/user-db
cat >> src/user_db.py <<'EOF'

ADMIN_PASSWORD = "hunter2"

def login(name, password):
    return password == ADMIN_PASSWORD

def ping_host(host):
    import os
    os.system("ping -c 1 " + host)
EOF
git add -A && git -c user.name=demo -c user.email=demo@example.com commit -qm "add login and ping helpers"

# /verify 用テスト(未コミットのまま置く)
cat > tests/test_calc.py <<'EOF'
import sys, os, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))
import calc

class TestCalc(unittest.TestCase):
    def test_add(self):
        self.assertEqual(calc.add(1, 2), 3)

    def test_divide(self):
        self.assertEqual(calc.divide(6, 3), 2)

    def test_average(self):
        self.assertEqual(calc.average([2, 4]), 3)

if __name__ == "__main__":
    unittest.main()
EOF

echo "sample project ready: $P"
git log --oneline --all | head -5

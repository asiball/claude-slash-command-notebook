#!/bin/bash
# Config Notebook (config.html) 用の実測画面採取 → work/config-tui/*.ansi
# 設定スコープ(user/project/local)と permissions ルール(allow/ask/deny)の実挙動を採取する。
#
# 警告: このスクリプトは ~/.claude/settings.json を一時変更し、終了時に復元する
#       (trap で EXIT/INT/TERM のどの経路でも復元される)。とはいえユーザー設定に
#       触れるため、コンテナや VM などの隔離環境での実行を推奨。
set -u
BASE="$(cd "$(dirname "$0")" && pwd)"
SP="$BASE/work"
DIR="$SP/config-demo"
CAP="$SP/config-tui"
BK="$SP/config-backup"
S=ccconfig
mkdir -p "$CAP" "$BK"
tmux kill-session -t $S 2>/dev/null

# ---- (a) フィクスチャ構築: work/config-demo を毎回作り直す ----
rm -rf "$DIR"
mkdir -p "$DIR/src" "$DIR/secrets" "$DIR/.claude"

cat > "$DIR/src/hello.py" <<'EOF'
print("hello from config-demo")
EOF

cat > "$DIR/secrets/credentials.env" <<'EOF'
DUMMY_TOKEN=xxxx
EOF

# project スコープ: モデル sonnet-5 + permissions(allow/deny)
cat > "$DIR/.claude/settings.json" <<'EOF'
{
  "model": "claude-sonnet-5",
  "permissions": {
    "allow": ["Bash(python3 src/hello.py)"],
    "deny": ["Read(./secrets/**)"]
  }
}
EOF

# local スコープ: モデル haiku-4-5(project の sonnet-5 を上書きする側)
cat > "$DIR/.claude/settings.local.json" <<'EOF'
{ "model": "claude-haiku-4-5" }
EOF

# claude が git プロジェクトとして認識するように初回コミットまで作る
(cd "$DIR" && git init -qb main && git add -A \
  && git -c user.name=demo -c user.email=demo@example.com commit -qm "config demo fixture")

# ---- (b) ユーザー設定の一時変更(user スコープ: model = claude-opus-5)----
USER_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$USER_SETTINGS" ]; then
  cp "$USER_SETTINGS" "$BK/settings.json.bak"
  rm -f "$BK/settings.json.absent"
else
  : > "$BK/settings.json.absent"   # 元々不在だった印
fi

restore() {
  tmux kill-session -t $S 2>/dev/null
  if [ -f "$BK/settings.json.absent" ]; then
    rm -f "$USER_SETTINGS"
  elif [ -f "$BK/settings.json.bak" ]; then
    cp "$BK/settings.json.bak" "$USER_SETTINGS"
  fi
}
# どの失敗経路でも復元されるように: EXIT で restore、シグナルは exit 経由で EXIT に合流
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$HOME/.claude"
# JSON マージで "model" だけを追記/上書きする(他のキーは保持)
python3 - "$USER_SETTINGS" <<'EOF' || { echo "failed to update user settings" >&2; exit 1; }
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path):
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
data['model'] = 'claude-opus-5'
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
EOF

# ---- (c) 採取 ----
tmux new-session -d -s $S -x 110 -y 42 -c "$DIR" || { echo "tmux new-session failed" >&2; exit 1; }
# --model は付けない: local 設定の claude-haiku-4-5 が効くこと自体がデモ
tmux send-keys -t $S "claude" Enter
n=0
until tmux capture-pane -t $S -p | grep -qE "Try \"|trust|Trust"; do n=$((n+1)); [ $n -gt 40 ] && break; sleep 1; done
[ $n -gt 40 ] && echo "WARN: timed out waiting for claude startup" >&2
if tmux capture-pane -t $S -p | grep -qi trust; then
  tmux send-keys -t $S Enter
  n=0; until tmux capture-pane -t $S -p | grep -q "Try \""; do n=$((n+1)); [ $n -gt 20 ] && break; sleep 1; done
  [ $n -gt 20 ] && echo "WARN: timed out waiting for trust prompt confirmation" >&2
fi

wait_prompt() { local n=0; until tmux capture-pane -t $S -p | tail -8 | grep -qE "shift\+tab to cycle|Try \""; do n=$((n+1)); [ $n -gt 20 ] && break; sleep 0.5; done; }

snap() { # snap <name> <command> — 即時 UI(パネル表示)を採取
  local name="$1" cmd="$2"
  tmux send-keys -t $S Escape; sleep 1; tmux send-keys -t $S Escape; sleep 1
  wait_prompt
  tmux send-keys -t $S -l "$cmd"
  local n=0; until tmux capture-pane -t $S -p | grep -qF "❯ $cmd"; do n=$((n+1)); [ $n -gt 10 ] && break; sleep 0.5; done
  tmux send-keys -t $S Enter
  n=0; until [ $n -gt 8 ]; do n=$((n+1)); sleep 0.5; done
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
}

ask() { # ask <name> <プロンプト文> <待ち秒> — モデル応答を伴う画面を採取
  local name="$1" prompt="$2" secs="$3"
  tmux send-keys -t $S Escape; sleep 1; tmux send-keys -t $S Escape; sleep 1
  wait_prompt
  tmux send-keys -t $S -l "$prompt"
  local n=0; until tmux capture-pane -t $S -p | grep -qF "$prompt"; do n=$((n+1)); [ $n -gt 10 ] && break; sleep 0.5; done
  tmux send-keys -t $S Enter
  sleep "$secs"
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
}

# snap 型: スコープ/ルールの表示パネル
snap status-scopes "/status"
snap config-scopes "/config"
snap permissions-rules "/permissions"

# ask 型: permissions ルールの実挙動
# allow ルール(Bash(python3 src/hello.py))で確認なしに実行される画面
ask perm-allow "python3 src/hello.py を実行して" 30
# ルール未定義のコマンドで権限確認プロンプトが出た画面(採取後 Escape で拒否して抜ける)
ask perm-ask "date コマンドを実行して" 20
tmux send-keys -t $S Escape; sleep 1
# deny ルール(Read(./secrets/**))で拒否される画面
ask perm-deny "secrets/credentials.env の中身をそのまま表示して" 30

tmux kill-session -t $S 2>/dev/null
echo done; ls -la "$CAP"

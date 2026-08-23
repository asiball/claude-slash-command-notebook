#!/bin/bash
# Config Notebook (config.html) 用の実測画面採取 → work/config-tui/*.ansi
# 設定スコープ(user/project/local)と permissions ルール(allow/ask/deny)の実挙動、
# 権限モードの表示、Output style(Default / Concise)の比較を採取する。
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
LOCAL_FIXTURE='{ "model": "claude-haiku-4-5" }'
write_local() { printf '%s\n' "$1" > "$DIR/.claude/settings.local.json"; }
write_local "$LOCAL_FIXTURE"

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
  # fixture の local 設定も初期値に戻す(スタイル/モードのデモで書き換えるため)
  [ -d "$DIR/.claude" ] && write_local "$LOCAL_FIXTURE"
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

# ---- (c) ヘルパー ----
# 画面の取得は tmux capture-pane。固定の長い sleep は使わず、フッターの状態をポーリングして進む。
screen() { tmux capture-pane -t $S -p; }
idle() { # 入力待ち(応答中でない)か
  local tail8; tail8="$(screen | tail -8)"
  echo "$tail8" | grep -qE 'for shortcuts|Try "|shift\+tab to cycle' && ! echo "$tail8" | grep -q 'esc to interrupt'
}
wait_prompt() { local n=0; until idle; do n=$((n+1)); [ $n -gt 30 ] && break; sleep 0.5; done; }
wait_idle() { # wait_idle <最大秒> — 応答が終わって入力待ちに戻るまで待つ
  local max="$1" n=0
  sleep 3
  until idle; do n=$((n+1)); [ $n -ge "$max" ] && { echo "WARN: wait_idle timeout (${max}s)" >&2; break; }; sleep 1; done
  sleep 2
}
wait_for() { # wait_for <正規表現> <最大秒> — 画面に文字列が出るまで待つ
  local pat="$1" max="$2" n=0
  until screen | grep -qE "$pat"; do n=$((n+1)); [ $n -ge "$max" ] && { echo "WARN: wait_for timeout: $pat" >&2; return 1; }; sleep 1; done
}
cancel() { tmux send-keys -t $S Escape; sleep 1; tmux send-keys -t $S Escape; sleep 1; }

start_claude() { # start_claude [claude の追加引数...] — 新しい tmux セッションで起動し入力待ちまで待つ(高さは ROWS、既定 42)
  tmux kill-session -t $S 2>/dev/null
  tmux new-session -d -s $S -x 110 -y "${ROWS:-42}" -c "$DIR" || { echo "tmux new-session failed" >&2; exit 1; }
  tmux send-keys -t $S "claude $*" Enter
  local n=0
  until screen | grep -qE "Try \"|trust|Trust|for shortcuts"; do n=$((n+1)); [ $n -gt 40 ] && break; sleep 1; done
  [ $n -gt 40 ] && echo "WARN: timed out waiting for claude startup" >&2
  if screen | grep -qi trust; then
    tmux send-keys -t $S Enter
    n=0; until screen | grep -qE "Try \"|for shortcuts"; do n=$((n+1)); [ $n -gt 20 ] && break; sleep 1; done
    [ $n -gt 20 ] && echo "WARN: timed out waiting for trust prompt confirmation" >&2
  fi
  wait_prompt
}

type_cmd() { # type_cmd <command> — コマンドを入力して Enter(補完の確定待ちを含む)
  local cmd="$1"
  tmux send-keys -t $S -l "$cmd"
  local n=0; until screen | grep -qF "❯ $cmd"; do n=$((n+1)); [ $n -gt 10 ] && break; sleep 0.5; done
  tmux send-keys -t $S Enter
  sleep 4
}
snap() { # snap <name> <command> — 即時 UI(パネル表示)を採取
  local name="$1" cmd="$2"
  cancel; wait_prompt
  type_cmd "$cmd"
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
}
snap_keys() { # snap_keys <name> <command> <key>... — パネル表示後にキーを送ってから採取(タブ切替など)
  local name="$1" cmd="$2"; shift 2
  cancel; wait_prompt
  type_cmd "$cmd"
  local k; for k in "$@"; do tmux send-keys -t $S "$k"; sleep 1; done
  sleep 1
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
}
snap_type() { # snap_type <name> <command> <入力文字列> <key>... — パネル表示後に文字列を打ち、キーを送ってから採取(/config の検索など)
  local name="$1" cmd="$2" text="$3"; shift 3
  cancel; wait_prompt
  type_cmd "$cmd"
  tmux send-keys -t $S -l "$text"; sleep 1.5
  local k; for k in "$@"; do tmux send-keys -t $S "$k"; sleep 1; done
  sleep 1
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
}
footer() { # footer <name> — 入力欄とフッター(下 4 行)だけを採取(権限モードのバッジ用)
  sleep 1.5
  tmux capture-pane -t $S -e -p | tail -4 > "$CAP/$1.ansi"
}
ask() { # ask <name> <プロンプト文> <最大待ち秒> [verbose] — モデル応答を伴う画面を採取
  # verbose を指定すると、応答後に ctrl+o で詳細トランスクリプト表示に切り替えてから採取し、
  # 採取後に元の表示へ戻す(ツール呼び出しの中身 — 実行したコマンドや拒否エラー — が見えるようにするため)。
  local name="$1" prompt="$2" max="$3" verbose="${4:-}"
  cancel; wait_prompt
  tmux send-keys -t $S -l "$prompt"
  local n=0; until screen | grep -qF "$prompt"; do n=$((n+1)); [ $n -gt 10 ] && break; sleep 0.5; done
  tmux send-keys -t $S Enter
  wait_idle "$max"
  if [ "$verbose" = verbose ]; then
    tmux send-keys -t $S C-o; sleep 3
    tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
    tmux send-keys -t $S C-o; sleep 2
  else
    tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
  fi
}
ask_dialog() { # ask_dialog <name> <プロンプト文> <最大待ち秒> — 権限確認ダイアログが出た画面を採取し、Esc で拒否する
  local name="$1" prompt="$2" max="$3"
  cancel; wait_prompt
  tmux send-keys -t $S -l "$prompt"
  local n=0; until screen | grep -qF "$prompt"; do n=$((n+1)); [ $n -gt 10 ] && break; sleep 0.5; done
  tmux send-keys -t $S Enter
  wait_for 'Do you want to proceed' "$max" || true
  sleep 2
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
  tmux send-keys -t $S Escape; sleep 2
}

# ---- (d) 採取 1: スコープと permissions(local = haiku、--model は付けない: local の haiku が効くこと自体がデモ)----
start_claude
snap status-scopes "/status"
snap config-scopes "/config"
snap permissions-rules "/permissions"                 # Allow タブ(初期表示)
snap_keys permissions-deny "/permissions" Right Right # → Deny タブ(Allow → Ask → Deny)

# allow ルール(Bash(python3 src/hello.py))で確認なしに実行される画面(詳細表示で実行コマンドと出力を見せる)
ask perm-allow "python3 src/hello.py を実行して" 90 verbose
# ルール未定義のコマンドで権限確認プロンプトが出た画面(採取後 Escape で拒否して抜ける)。
# 注: date のような読み取り専用コマンドは組み込み判定で確認なしに実行されるため、
#     ファイルを作成する touch を使う(採取後に Escape で拒否するので created.txt は作られない)。
ask_dialog perm-ask "touch created.txt を実行して" 60
# deny ルール(Read(./secrets/**))で拒否される画面(詳細表示で拒否エラーを見せる)
ask perm-deny "secrets/credentials.env の中身をそのまま表示して" 90 verbose

# 権限モードの表示: shift+tab で巡回するフッターのバッジを順に採取(下 4 行のみ)
cancel; wait_prompt
footer mode-cycle-0
for i in 1 2 3; do tmux send-keys -t $S BTab; footer "mode-cycle-$i"; done
tmux send-keys -t $S BTab; sleep 1   # 一周して元に戻す(4 モードの場合)

# Output style: /config → "Output style" 行 → Enter でピッカー(5 スタイル)を採取し、いったん Esc
snap_type config-output-style "/config" "Output style" Down Enter
cancel
# ピッカーで Concise を確定すると .claude/settings.local.json に書かれることを確認(ファイル内容を保存)
snap_type config-output-style-pick "/config" "Output style" Down Enter Down Down Enter
cancel; sleep 1
cp "$DIR/.claude/settings.local.json" "$CAP/outputstyle-local.txt"
tmux kill-session -t $S 2>/dev/null

# ---- (e) 採取 2: permissions.defaultMode を local に置いて起動 → 初期モードが変わる ----
write_local '{ "model": "claude-haiku-4-5", "permissions": { "defaultMode": "acceptEdits" } }'
start_claude
footer mode-default-acceptedits
snap status-defaultmode "/status"
tmux kill-session -t $S 2>/dev/null

# ---- (f) 採取 3/4: Output style 比較(同一プロンプト、Default と Concise で別セッション。--model sonnet: CLI 引数が local の haiku より優先)----
STYLE_PROMPT="このプロジェクトの .claude 配下の設定ファイルを読んで、何が設定されているか教えて"
write_local "$LOCAL_FIXTURE"
ROWS=60 start_claude --model sonnet
footer mode-sonnet-start
ask style-default "$STYLE_PROMPT" 150
tmux kill-session -t $S 2>/dev/null

write_local '{ "model": "claude-haiku-4-5", "outputStyle": "Concise" }'
ROWS=60 start_claude --model sonnet
ask style-concise "$STYLE_PROMPT" 150
tmux kill-session -t $S 2>/dev/null

write_local "$LOCAL_FIXTURE"
echo done; ls -la "$CAP"

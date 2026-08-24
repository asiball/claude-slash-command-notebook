#!/bin/bash
# Config Notebook (config.html) 用の実測画面採取 → work/config-tui/*.ansi
# 「同じ入力で、設定を切り替えると出力がどう変わるか」の比較素材を採取する。
# 対象: outputStyle / permissions.deny / permissions.defaultMode / sandbox
#
# 書き換えるのは work/config-demo 配下の設定ファイルのみ(~/.claude には触れない)。
# sandbox 比較の前提: macOS は追加インストール不要(Seatbelt)、
# Linux / WSL2 は bubblewrap と socat が必要。
# 一部だけ採り直すとき: ONLY="sandbox-on style" ./capture-config.sh / SKIP="sandbox-on" ./capture-config.sh
#   セクション名: mode-manual deny-on output-style deny-off acceptedits auto sandbox-off sandbox-on style
set -u
run_section() { # run_section <name> — ONLY / SKIP に従ってそのセクションを実行するか
  case " ${SKIP:-} " in *" $1 "*) echo "skip: $1" >&2; return 1;; esac
  [ -z "${ONLY:-}" ] && return 0
  case " $ONLY " in *" $1 "*) return 0;; esac
  echo "skip: $1" >&2; return 1
}
BASE="$(cd "$(dirname "$0")" && pwd)"
SP="$BASE/work"
DIR="$SP/config-demo"
CAP="$SP/config-tui"
S=ccconfig
mkdir -p "$CAP"
tmux kill-session -t $S 2>/dev/null

# ---- (a) フィクスチャ構築: work/config-demo を毎回作り直す ----
rm -rf "$DIR"
mkdir -p "$DIR/src" "$DIR/private" "$DIR/.claude"

cat > "$DIR/src/hello.py" <<'EOF'
print("hello from config-demo")
EOF

cat > "$DIR/private/credentials.env" <<'EOF'
DUMMY_TOKEN=xxxx
EOF

# project スコープ: モデル sonnet-5 + permissions(deny 比較の「あり」側)
PROJECT_FIXTURE='{
  "model": "claude-sonnet-5",
  "permissions": {
    "allow": ["Bash(python3 src/hello.py)"],
    "deny": ["Read(./private/**)"]
  }
}'
write_project() { printf '%s\n' "$1" > "$DIR/.claude/settings.json"; }
write_project "$PROJECT_FIXTURE"

# local スコープ: モデル haiku-4-5 を基点に、セルごとに書き換える
LOCAL_FIXTURE='{ "model": "claude-haiku-4-5" }'
write_local() { printf '%s\n' "$1" > "$DIR/.claude/settings.local.json"; }
write_local "$LOCAL_FIXTURE"

# claude が git プロジェクトとして認識するように初回コミットまで作る
(cd "$DIR" && git init -qb main && git add -A \
  && git -c user.name=demo -c user.email=demo@example.com commit -qm "config demo fixture")

restore() {
  tmux kill-session -t $S 2>/dev/null
  # フィクスチャの設定を初期値に戻す(セルごとに書き換えるため)
  if [ -d "$DIR/.claude" ]; then
    write_project "$PROJECT_FIXTURE"
    write_local "$LOCAL_FIXTURE"
  fi
  rm -f /tmp/sandbox-poke.txt "$DIR/created.txt"
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- (b) ヘルパー ----
# 画面の取得は tmux capture-pane。固定の長い sleep は使わず、フッターの状態をポーリングして進む。
screen() { tmux capture-pane -t $S -p; }
idle() { # 入力待ち(応答中でない)か。フッターのヒント文言は版や幅で変わるので複数の候補を見る。
  # 応答中の目印はスピナー行「* Thinking… (6s · ↓ 146 tokens)」(2.1.241 では esc to interrupt が出ない)
  local tail10; tail10="$(screen | tail -10)"
  echo "$tail10" | grep -qE 'for shortcuts|for agents|mode on|edits on|Try "|shift\+tab to cycle' \
    && ! echo "$tail10" | grep -qE 'esc to interrupt|… \([0-9]+s|↓ [0-9]+ tokens'
}
# ユーザー設定の statusLine(コスト・経過時間などマシン固有の表示)は採取のたびに変わるので、
# CLI 引数で空の statusLine に上書きする(~/.claude やフィクスチャの設定ファイルは触らない)。
NO_STATUSLINE='{"statusLine":{"type":"command","command":"true"}}'
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
  tmux send-keys -t $S "claude --settings '$NO_STATUSLINE' $*" Enter
  # 起動完了の目印: 信頼確認ダイアログ、または入力待ちフッター(idle と同じ候補)
  local n=0
  until screen | grep -qE "trust|Trust" || idle; do n=$((n+1)); [ $n -gt 60 ] && break; sleep 1; done
  [ $n -gt 60 ] && echo "WARN: timed out waiting for claude startup" >&2
  if screen | grep -qi trust; then
    tmux send-keys -t $S Enter
    n=0; until idle; do n=$((n+1)); [ $n -gt 30 ] && break; sleep 1; done
    [ $n -gt 30 ] && echo "WARN: timed out waiting for trust prompt confirmation" >&2
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
  # statusLine を空にしても行自体は残る(右端に /rc のリンクだけ出ることがある)ので、
  # 色(SGR)とリンク(OSC 8)を剥がして空か /rc だけの行は落とし、残りの下 4 行を採る
  sleep 1.5
  tmux capture-pane -t $S -e -p | tail -5 | while IFS= read -r line; do
    plain="$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g; s/\x1b\][^\x07\x1b]*\(\x07\|\x1b\\\)//g')"
    printf '%s' "$plain" | grep -qE '^\s*(/rc)?\s*$' || printf '%s\n' "$line"
  done | tail -4 > "$CAP/$1.ansi"
}
send_prompt() { # send_prompt <プロンプト文> — 依頼文を入力して Enter
  cancel; wait_prompt
  tmux send-keys -t $S -l "$1"
  local n=0; until screen | grep -qF "$1"; do n=$((n+1)); [ $n -gt 10 ] && break; sleep 0.5; done
  tmux send-keys -t $S Enter
}
ask() { # ask <name> <プロンプト文> <最大待ち秒> [verbose] — モデル応答を伴う画面を採取
  # verbose を指定すると、応答後に ctrl+o で詳細トランスクリプト表示に切り替えてから採取し、
  # 採取後に元の表示へ戻す(ツール呼び出しの中身 — 実行したコマンドや拒否エラー — が見えるようにするため)。
  local name="$1" prompt="$2" max="$3" verbose="${4:-}"
  send_prompt "$prompt"
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
  send_prompt "$prompt"
  wait_for 'Do you want to proceed' "$max" || true
  sleep 2
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
  tmux send-keys -t $S Escape; sleep 2
}
ask_approve() { # ask_approve <name> <プロンプト文> <最大待ち秒> — 確認ダイアログに Yes と答え、完了後の画面を詳細表示で採取
  local name="$1" prompt="$2" max="$3"
  send_prompt "$prompt"
  if wait_for 'Do you want to proceed' "$max"; then
    sleep 1
    tmux send-keys -t $S Enter   # 1. Yes
  fi
  wait_idle "$max"
  tmux send-keys -t $S C-o; sleep 3
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
  tmux send-keys -t $S C-o; sleep 2
}
ask_until_stop() { # ask_until_stop <name> <プロンプト文> <最大待ち秒> — 入力待ちか確認ダイアログのどちらかで止まったら詳細表示で採取し、Esc で抜ける
  local name="$1" prompt="$2" max="$3" n=0
  send_prompt "$prompt"
  sleep 3
  until idle || screen | grep -qE 'Do you want to proceed'; do
    n=$((n+1)); [ $n -ge "$max" ] && { echo "WARN: ask_until_stop timeout (${max}s)" >&2; break; }; sleep 1
  done
  sleep 2
  tmux send-keys -t $S C-o; sleep 3
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
  tmux send-keys -t $S C-o; sleep 2
  tmux send-keys -t $S Escape; sleep 1
}

# ---- (c)(d)(e) は既定フィクスチャ(haiku)の同一セッションで続けて採取 ----
if run_section mode-manual || run_section deny-on || run_section output-style; then
  start_claude
  # (c) permissions.defaultMode: manual
  if run_section mode-manual; then
    footer mode-cycle-0
    # ルール未定義のコマンドで権限確認プロンプトが出た画面(採取後 Escape で拒否して抜ける)。
    # 注: date のような読み取り専用コマンドは組み込み判定で確認なしに実行されるため、
    #     ファイルを作成する touch を使う(採取後に Escape で拒否するので created.txt は作られない)。
    ask_dialog perm-ask "touch created.txt を実行して" 60
  fi
  # (d) permissions.deny: あり
  if run_section deny-on; then
    ask perm-deny "private/credentials.env の中身をそのまま表示して" 90 verbose
  fi
  # (e) Output style の切り替え画面: /config → "Output style" 行 → Enter でピッカーを採取し、いったん Esc
  if run_section output-style; then
    snap_type config-output-style "/config" "Output style" Down Enter
    cancel
    # ピッカーで Concise を確定すると .claude/settings.local.json に書かれることを確認(ファイル内容を保存)
    snap_type config-output-style-pick "/config" "Output style" Down Enter Down Down Enter
    cancel; sleep 1
    cp "$DIR/.claude/settings.local.json" "$CAP/outputstyle-local.txt"
  fi
  tmux kill-session -t $S 2>/dev/null
fi

# ---- (f) permissions.deny: なし(project settings から permissions を外して起動し直す)----
if run_section deny-off; then
  write_project '{ "model": "claude-sonnet-5" }'
  write_local "$LOCAL_FIXTURE"
  start_claude
  ask perm-deny-off "private/credentials.env の中身をそのまま表示して" 90 verbose
  tmux kill-session -t $S 2>/dev/null
  write_project "$PROJECT_FIXTURE"
fi

# ---- (g) permissions.defaultMode: acceptEdits(local に defaultMode を置いて起動)----
if run_section acceptedits; then
  write_local '{ "model": "claude-haiku-4-5", "permissions": { "defaultMode": "acceptEdits" } }'
  start_claude
  footer mode-default-acceptedits
  # accept edits は touch などの基本的なファイル操作を自動承認する → 確認なしで実行されるはず
  ask perm-acceptedits-run "touch created.txt を実行して" 90 verbose
  rm -f "$DIR/created.txt"
  tmux kill-session -t $S 2>/dev/null
fi

# ---- (h) permissions.defaultMode: auto(local に defaultMode: auto を置き、auto を選べる sonnet で起動)----
if run_section auto; then
  write_local '{ "model": "claude-haiku-4-5", "permissions": { "defaultMode": "auto" } }'
  start_claude --model sonnet
  footer mode-sonnet-start
  ask perm-auto-run "touch created.txt を実行して" 90 verbose
  rm -f "$DIR/created.txt"
  tmux kill-session -t $S 2>/dev/null
fi

# ---- (i) sandbox: なし(manual の確認に Yes → 成功する画面)----
if run_section sandbox-off; then
  write_local "$LOCAL_FIXTURE"
  start_claude
  ask_approve sandbox-off "touch /tmp/sandbox-poke.txt を実行して" 90
  rm -f /tmp/sandbox-poke.txt
  tmux kill-session -t $S 2>/dev/null
fi

# ---- (j) sandbox: あり(確認なしで実行 → /tmp への書き込みが OS にブロックされる画面)----
# 失敗を見た Claude が dangerouslyDisableSandbox での再試行を提案して確認ダイアログで
# 止まることがあるため、入力待ち/ダイアログのどちらで止まっても採取する。
if run_section sandbox-on; then
  write_local '{ "model": "claude-haiku-4-5", "sandbox": { "enabled": true } }'
  start_claude
  ask_until_stop sandbox-on "touch /tmp/sandbox-poke.txt を実行して" 120
  rm -f /tmp/sandbox-poke.txt
  tmux kill-session -t $S 2>/dev/null
fi

# ---- (k) outputStyle 比較(同一プロンプト、Default / Concise / Explanatory で別セッション。--model sonnet: CLI 引数が local の haiku より優先)----
# 依頼は小さなコード変更+実行確認(複数ステップ)。Default は途中の実況と要約、Concise は結果だけ、
# Explanatory は ★ Insight の解説が付き、スタイル差がはっきり出る。auto モード(sonnet)なので編集・実行は確認なしで通る
if run_section style; then
  STYLE_PROMPT="src/hello.py を、コマンドライン引数で名前を受け取って hello, <名前> と表示するように変更して、実行して確認して"
  reset_src() { (cd "$DIR" && git checkout -q -- src/hello.py); }   # 前のセッションの変更を戻し、毎回同じ入力にする
  write_local "$LOCAL_FIXTURE"
  ROWS=60 start_claude --model sonnet
  ask style-default "$STYLE_PROMPT" 150
  tmux kill-session -t $S 2>/dev/null
  reset_src

  write_local '{ "model": "claude-haiku-4-5", "outputStyle": "Concise" }'
  ROWS=60 start_claude --model sonnet
  ask style-concise "$STYLE_PROMPT" 150
  tmux kill-session -t $S 2>/dev/null
  reset_src

  write_local '{ "model": "claude-haiku-4-5", "outputStyle": "Explanatory" }'
  ROWS=60 start_claude --model sonnet
  ask style-explanatory "$STYLE_PROMPT" 150
  tmux kill-session -t $S 2>/dev/null
  reset_src
fi

write_local "$LOCAL_FIXTURE"
echo done; ls -la "$CAP"

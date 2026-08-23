#!/bin/bash
# Slash Command Notebook (index.html) 用の追加画面採取 → work/tui-color/*.ansi
# 新しめのコマンド(/fast /diff /advisor /autocompact /rename /branch /workflows)と
# ultra 系(ultracode キーワードのヒント、/code-review ultra = ultrareview)を採取する。
#
# 注意: /code-review ultra(ultrareview)はクラウドで実行され、無料枠(アカウントごと 3 回)または
#       利用クレジットを消費する。SKIP_ULTRA=1 を付けると確認ダイアログの採取だけ行い、本実行はしない。
#       本実行時は完了まで数分〜10 分程度かかる(20 秒おきに最大 25 分ポーリング)。
set -u
BASE="$(cd "$(dirname "$0")" && pwd)"
SP="$BASE/work"
DIR="$SP/sample-project"
CAP="$SP/tui-color"
S=ccextra
mkdir -p "$CAP"
tmux kill-session -t $S 2>/dev/null
[ -d "$DIR/.git" ] || { echo "work/sample-project がありません。先に ./setup-sample.sh を実行してください" >&2; exit 1; }

# ---- ヘルパー(capture-config.sh と同じ方式: 固定の長い sleep は使わずフッターをポーリング)----
screen() { tmux capture-pane -t $S -p; }
idle() {
  local tail8; tail8="$(screen | tail -8)"
  echo "$tail8" | grep -qE 'for shortcuts|Try "|shift\+tab to cycle' && ! echo "$tail8" | grep -q 'esc to interrupt'
}
wait_prompt() { local n=0; until idle; do n=$((n+1)); [ $n -gt 30 ] && break; sleep 0.5; done; }
wait_for() { local pat="$1" max="$2" n=0; until screen | grep -qE "$pat"; do n=$((n+1)); [ $n -ge "$max" ] && { echo "WARN: wait_for timeout: $pat" >&2; return 1; }; sleep 1; done; }
cancel() { tmux send-keys -t $S Escape; sleep 1; tmux send-keys -t $S Escape; sleep 1; }
start_claude() {
  tmux kill-session -t $S 2>/dev/null
  tmux new-session -d -s $S -x 110 -y "${ROWS:-42}" -c "$DIR" || { echo "tmux new-session failed" >&2; exit 1; }
  tmux send-keys -t $S "claude $*" Enter
  local n=0
  until screen | grep -qE "Try \"|trust|Trust|for shortcuts"; do n=$((n+1)); [ $n -gt 40 ] && break; sleep 1; done
  [ $n -gt 40 ] && echo "WARN: timed out waiting for claude startup" >&2
  if screen | grep -qi trust; then
    tmux send-keys -t $S Enter
    n=0; until screen | grep -qE "Try \"|for shortcuts"; do n=$((n+1)); [ $n -gt 20 ] && break; sleep 1; done
  fi
  wait_prompt
}
type_cmd() {
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
hint() { # hint <name> <入力文字列> — 入力欄に文字列を打った状態(Enter しない)の補完/ヒント表示を採取し、入力を消す
  local name="$1" text="$2"
  cancel; wait_prompt
  tmux send-keys -t $S -l "$text"; sleep 2.5
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
  tmux send-keys -t $S C-u; sleep 1
}
shot() { tmux capture-pane -t $S -e -p > "$CAP/$1.ansi"; }

# /diff 用に、追跡済みファイルにも未コミットの変更を置く(tests/ は未追跡のまま)
grep -q 'demo note' "$DIR/README.md" || printf '\n<!-- demo note: uncommitted change for /diff -->\n' >> "$DIR/README.md"

start_claude --model haiku

# ---- ultra 系のヒント表示(入力のみ) ----
hint ultra-autocomplete "/ultra"          # 補完: /ultrareview(3 free left…)と /code-review
hint codereview-hint "/code-review "      # 引数ヒント: [low|…|max|ultra] [--fix] [--comment] [<pr#>|<branch>|<path>]
hint ultracode-hint "ultracode "          # キーワード検知: "Dynamic workflow requested for this turn · opt+w to ignore"

# ---- 新しめのコマンド(パネル表示) ----
snap workflows "/workflows"
snap fast "/fast"
snap diff "/diff"
snap advisor "/advisor"
snap autocompact "/autocompact"
snap rename "/rename"

# ---- /code-review ultra(ultrareview): 確認ダイアログ → 本実行 → 完了まで ----
cancel; wait_prompt
type_cmd "/code-review ultra"
wait_for 'free|credit|cloud|Ultrareview|ultrareview|proceed|Start' 30 || true
sleep 2
shot ultrareview-confirm
if [ "${SKIP_ULTRA:-}" = 1 ]; then
  echo "SKIP_ULTRA=1: ultrareview の本実行はスキップ(ダイアログのみ採取)"
  tmux send-keys -t $S Escape; sleep 1
else
  tmux send-keys -t $S Enter; sleep 25
  shot ultrareview-start
  snap tasks-ultra "/tasks"
  cancel; wait_prompt
  # 完了待ち: 20 秒おきに最大 75 回(25 分)。画面に完了らしき文言が出て入力待ちに戻ったら終了
  n=0; start_ts=$(date +%s)
  until [ $n -ge 75 ]; do
    n=$((n+1)); sleep 20
    shot ultrareview-progress
    if idle && screen | grep -qiE 'review (is )?(complete|finished|done)|findings?|no (bugs|issues) found|bugs? found|confirmed'; then break; fi
  done
  echo "ultrareview elapsed: $(( $(date +%s) - start_ts ))s (polls=$n)"
  sleep 3
  shot ultrareview-done
  snap tasks-after "/tasks"
fi

# ---- /branch(会話の分岐。セッションが切り替わる可能性があるので最後) ----
snap branch "/branch"

tmux kill-session -t $S 2>/dev/null
echo done; ls -la "$CAP"

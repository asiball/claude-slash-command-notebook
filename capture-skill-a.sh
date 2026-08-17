#!/bin/bash
BASE="$(cd "$(dirname "$0")" && pwd)"
# Capture Skill-command TUI screens (part A): /init, /recap, /compact, /explain
set -u
SP="$BASE/work"
DIR="$SP/sample-project-2"
CAP="$SP/tui2"
S=ccskill
mkdir -p "$CAP"
tmux kill-session -t $S 2>/dev/null

# クリーンコピーを作成(CLAUDE.md を除去し、/code-review 用の未コミット変更 percent() を追加)
rm -rf "$DIR"
cp -r "$SP/sample-project" "$DIR"
rm -f "$DIR/CLAUDE.md"
printf '\ndef percent(part, total):\n    return part / total * 100\n' >> "$DIR/src/calc.py"

tmux new-session -d -s $S -x 110 -y 42 -c "$DIR"
tmux send-keys -t $S "claude --model haiku --permission-mode acceptEdits --allowedTools 'Bash,Read,Grep,Glob'" Enter

# wait for startup / trust prompt
n=0
until tmux capture-pane -t $S -p | grep -qE "Try \"|trust|Trust"; do n=$((n+1)); [ $n -gt 40 ] && break; sleep 1; done
if tmux capture-pane -t $S -p | grep -qi trust; then
  tmux send-keys -t $S Enter
  n=0; until tmux capture-pane -t $S -p | grep -q "Try \""; do n=$((n+1)); [ $n -gt 20 ] && break; sleep 1; done
fi
tmux capture-pane -t $S -p > "$CAP/startup.txt"

type_cmd() { # type_cmd <cmd-string>
  tmux send-keys -t $S -l "$1"
  local n=0; until tmux capture-pane -t $S -p | grep -qF "❯ $1"; do n=$((n+1)); [ $n -gt 10 ] && break; sleep 0.5; done
  tmux send-keys -t $S Enter
}

wait_idle() { # wait_idle <min_sec> <max_sec>
  local mins=$1 maxs=$2 elapsed=0 same=0 prev="" cur
  while true; do
    sleep 3; elapsed=$((elapsed+3))
    cur=$(tmux capture-pane -t $S -p)
    if [ "$cur" = "$prev" ]; then same=$((same+1)); else same=0; fi
    prev="$cur"
    if [ $elapsed -ge $mins ] && [ $same -ge 3 ] && ! echo "$cur" | grep -q "esc to interrupt"; then break; fi
    [ $elapsed -ge $maxs ] && break
  done
}

# --- /init ---
type_cmd "/init"
sleep 10
tmux capture-pane -t $S -p > "$CAP/init-running.txt"
wait_idle 30 240
tmux capture-pane -t $S -p > "$CAP/init.txt"

# --- /recap ---
type_cmd "/recap"
wait_idle 10 90
tmux capture-pane -t $S -p > "$CAP/recap.txt"

# --- /compact ---
type_cmd "/compact 日本語で要点のみ"
sleep 6
tmux capture-pane -t $S -p > "$CAP/compact-running.txt"
wait_idle 15 120
tmux capture-pane -t $S -p > "$CAP/compact.txt"

# --- /explain (custom command) ---
type_cmd "/explain divide"
wait_idle 15 120
tmux capture-pane -t $S -p > "$CAP/explain.txt"

echo "PART A DONE"
ls -la "$CAP"

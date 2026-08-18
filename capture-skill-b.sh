#!/bin/bash
BASE="$(cd "$(dirname "$0")" && pwd)"
# Capture Skill-command TUI screens (part B): /code-review, /security-review, /doctor
# Reuses the ccskill tmux session left open by part A.
set -u
SP="$BASE/work"
CAP="$SP/tui2"
S=ccskill

tmux has-session -t "$S" 2>/dev/null || { echo "session $S not found: run capture-skill-a.sh first" >&2; exit 1; }

type_cmd() {
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

# --- /code-review low ---
type_cmd "/code-review low"
sleep 10
tmux capture-pane -t $S -p > "$CAP/code-review-running.txt"
wait_idle 30 240
tmux capture-pane -t $S -p > "$CAP/code-review.txt"

# --- /security-review ---
type_cmd "/security-review"
sleep 15
tmux capture-pane -t $S -p > "$CAP/security-review-running.txt"
wait_idle 60 480
tmux capture-pane -t $S -p > "$CAP/security-review.txt"

# --- /doctor ---
type_cmd "/doctor"
sleep 15
tmux capture-pane -t $S -p > "$CAP/doctor-running.txt"
wait_idle 90 480
tmux capture-pane -t $S -p > "$CAP/doctor.txt"
# if a confirmation question is showing, capture it, then leave it unanswered and end
tmux send-keys -t $S Escape
sleep 2
tmux kill-session -t $S 2>/dev/null

echo "PART B DONE"
ls -la "$CAP"

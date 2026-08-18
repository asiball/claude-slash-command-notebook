#!/bin/bash
set -u
BASE="$(cd "$(dirname "$0")" && pwd)"
# Re-capture UI slash-command screens WITH ANSI colors (-e)
SP="$BASE/work"
DIR="$SP/sample-project"
CAP="$SP/tui-color"
S=cccolor
mkdir -p "$CAP"
tmux kill-session -t $S 2>/dev/null

tmux new-session -d -s $S -x 110 -y 42 -c "$DIR" || { echo "tmux new-session failed" >&2; exit 1; }
tmux send-keys -t $S "claude --model haiku" Enter
n=0
until tmux capture-pane -t $S -p | grep -qE "Try \"|trust|Trust"; do n=$((n+1)); [ $n -gt 40 ] && break; sleep 1; done
[ $n -gt 40 ] && echo "WARN: timed out waiting for claude startup" >&2
if tmux capture-pane -t $S -p | grep -qi trust; then
  tmux send-keys -t $S Enter
  n=0; until tmux capture-pane -t $S -p | grep -q "Try \""; do n=$((n+1)); [ $n -gt 20 ] && break; sleep 1; done
  [ $n -gt 20 ] && echo "WARN: timed out waiting for trust prompt confirmation" >&2
fi

wait_prompt() { local n=0; until tmux capture-pane -t $S -p | tail -8 | grep -qE "shift\+tab to cycle|Try \""; do n=$((n+1)); [ $n -gt 20 ] && break; sleep 0.5; done; }

snap() { # snap <name> <command>
  local name="$1" cmd="$2"
  tmux send-keys -t $S Escape; sleep 1; tmux send-keys -t $S Escape; sleep 1
  wait_prompt
  tmux send-keys -t $S -l "$cmd"
  local n=0; until tmux capture-pane -t $S -p | grep -qF "❯ $cmd"; do n=$((n+1)); [ $n -gt 10 ] && break; sleep 0.5; done
  tmux send-keys -t $S Enter
  n=0; until [ $n -gt 8 ]; do n=$((n+1)); sleep 0.5; done
  tmux capture-pane -t $S -e -p > "$CAP/$name.ansi"
}

snap help "/help"
snap status "/status"
snap usage "/usage"
snap context "/context"
snap model "/model"
snap permissions "/permissions"
snap mcp "/mcp"
snap config "/config"
snap tasks "/tasks"
snap resume "/resume"
snap rewind "/rewind"
snap plan "/plan"
snap clear "/clear"

tmux kill-session -t $S 2>/dev/null
echo done; ls -la "$CAP"

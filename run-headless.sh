#!/bin/bash
# §1 のヘッドレス実測: /init /code-review /security-review /verify、続けて /recap /compact(--resume)
# 出力は work/out/*.out に保存される。
set -eu
BASE="$(cd "$(dirname "$0")" && pwd)"
P="$BASE/work/sample-project"
OUT="$BASE/work/out"
mkdir -p "$OUT"
TOOLS='Bash(git diff:*),Bash(git log:*),Bash(git status:*),Bash(ls:*),Read,Grep,Glob'
MODEL="${MODEL:-haiku}"

cd "$P"

# /init は CLAUDE.md の無い状態で(既にあれば退避)
[ -f CLAUDE.md ] && mv CLAUDE.md CLAUDE.md.bak
claude -p "/init" --model "$MODEL" --permission-mode acceptEdits < /dev/null > "$OUT/init.out" 2>&1

# /init セッションIDを特定(--resume 用)
PROJ_DIR=$(ls -td ~/.claude/projects/*sample-project* | head -1)
SID=$(ls -t "$PROJ_DIR"/*.jsonl | head -1 | xargs -n1 basename | sed 's/\.jsonl//')
echo "init session: $SID"

claude -p --resume "$SID" "/recap" --model "$MODEL" < /dev/null > "$OUT/recap.out" 2>&1
claude -p --resume "$SID" "/compact 日本語で要点のみ" --model "$MODEL" < /dev/null > "$OUT/compact.out" 2>&1

claude -p "/code-review low" --model "$MODEL" --allowedTools "$TOOLS" < /dev/null > "$OUT/code-review.out" 2>&1 &
P1=$!
claude -p "/security-review" --model "$MODEL" --allowedTools "$TOOLS" < /dev/null > "$OUT/security-review.out" 2>&1 &
P2=$!
claude -p "/verify" --model "$MODEL" --allowedTools 'Bash,Read,Grep,Glob' < /dev/null > "$OUT/verify.out" 2>&1 &
P3=$!
wait $P1 $P2 $P3

echo "=== done ==="; ls -la "$OUT"
echo "注: /compact の要約と compact_boundary は $PROJ_DIR/$SID.jsonl から抽出する"

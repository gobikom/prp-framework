#!/usr/bin/env bash
# Round cap for prp-review-agents (prp-framework#151 AC3).
#
# Invariant: a new review round starts only if the PR already carries fewer than CAP distinct
# review run ids in `Generated-by: prp-review-agents … run=<id> …` footers. Anything this script
# cannot establish (a footer it cannot parse, a bad --cap) refuses with exit 2. It keeps NO
# state: the count is derived from the PR comments on every call (the #152 ledger had crash,
# retry and symlink arms; this has none).
#
# usage: round-guard.sh [--cap N] < footer-lines
#   stdin: one line per PR comment = that comment's LAST line (the caller extracts it).
#   exit 0 = allowed (prints "rounds so far: R of N; this is round R+1")
#   exit 3 = refused: cap reached
#   exit 2 = unparseable footer, bad argument, or unreadable input (fail closed)
set -euo pipefail

CAP=10
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cap) [[ $# -ge 2 ]] || { echo "error: --cap needs a value" >&2; exit 2; }; CAP="$2"; shift 2 ;;
    *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
printf '%s' "$CAP" | grep -qxE '[0-9]{1,3}' && [[ "$CAP" =~ ^[0-9]+$ ]] && (( 10#$CAP >= 1 )) \
  || { echo "error: --cap must be a number from 1 to 999" >&2; exit 2; }
CAP=$((10#$CAP))

RUN_RE='^Generated-by: prp-review-agents v[^ ]+ run=([0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}) pass=[a-z-]+( tier=trivial)?$'
IDS=""
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ $RUN_RE ]]; then
    IDS+="${BASH_REMATCH[1]}"$'\n'
  elif [[ "$line" == "Generated-by: prp-review-agents"* ]]; then
    echo "error: cannot parse a review footer — round count unknown, refusing" >&2
    exit 2
  fi
done
R=0
[[ -n "$IDS" ]] && R=$(printf '%s' "$IDS" | sort -u | wc -l | tr -d ' ')

if (( R >= CAP )); then
  echo "ROUND-CAP: refused — this PR already has $R review runs (cap $CAP). Review stop rule: fix open Critical/Important findings or re-route the work; file Medium/Low in ONE follow-up issue; do not start another round; escalate (delegate_or_escalate)." >&2
  exit 3
fi
echo "rounds so far: $R of $CAP; this is round $((R + 1))"

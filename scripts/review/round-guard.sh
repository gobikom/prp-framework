#!/usr/bin/env bash
# Round cap for prp-review-agents (prp-framework#151 AC3).
#
# Invariant: the round count R is the number of distinct run-id tokens ([0-9]{8}T[0-9]{6}Z-<hex>+,
# compared lower-cased) found anywhere in the input lines. Every exact footer carries its run id, so
# R >= (distinct ids in exact footers). Changing anything on a line except the id itself (prefix,
# separators, word order, case, quoting, CR, a missing pass=, a split line) cannot lower R.
# Boundary (out of scope, stated): a run id whose digits are altered or split is not counted --
# equivalent to deleting the comment, which this guard cannot see either.
# Direction of error: a run id cited in prose (an L2 note, a provenance notice) is counted too --
# this can only raise R, making the guard stricter, never weaker.
#
# usage: round-guard.sh [--cap N] < footer-lines
#   stdin: one line per PR comment = that comment's LAST line (the caller extracts it).
#   exit 0 = allowed (prints "rounds so far: R of N; this is round R+1")
#   exit 3 = refused: cap reached
#   exit 2 = bad argument, unreadable input, or grep failure (fail closed)
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

# A review round is one distinct run id. Every run id token anywhere in the input counts, whatever the rest
# of its line looks like, so no footer shape can hide a round. Ids are compared lower-cased.
ID_RE='[0-9]{8}[Tt][0-9]{6}[Zz]-[0-9A-Fa-f]+'
IN=$(cat) || { echo "error: cannot read input — round count unknown, refusing" >&2; exit 2; }
rc=0
IDS=$(printf '%s\n' "$IN" | LC_ALL=C grep -aoE "$ID_RE") || rc=$?
(( rc <= 1 )) || { echo "error: grep failed (exit $rc) — round count unknown, refusing" >&2; exit 2; }
R=0
[[ -n "$IDS" ]] && R=$(printf '%s\n' "$IDS" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sort -u | wc -l | tr -d ' ')

if (( R >= CAP )); then
  echo "ROUND-CAP: refused — this PR already has $R review runs (cap $CAP). Review stop rule: fix open Critical/Important findings or re-route the work; file Medium/Low in ONE follow-up issue; do not start another round; escalate (delegate_or_escalate)." >&2
  exit 3
fi
echo "rounds so far: $R of $CAP; this is round $((R + 1))"

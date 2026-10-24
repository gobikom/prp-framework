#!/usr/bin/env bash
# Round cap for prp-review-agents (prp-framework#151 AC3).
#
# Invariant: R is the number of distinct run ids ([0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}, lower-cased)
# anywhere in the input. Adding any text never lowers R. On unedited producer footers (byte-exact
# by the adapter's pre-post check), R equals the number of review runs. The guard refuses (exit 2)
# only on a bad argument, when stdin cannot be read, or on a grep failure — never on content. Out
# of scope: a comment edited to remove or garble its id is not counted (prp-framework#213, durable
# ledger).
# Boundaries, stated:
# - A 9-hex id counts as its 8-hex prefix. Two ids differing only in the 9th hex digit count once.
# - Never refuses on content. An edited comment whose id was removed or garbled is not counted —
#   out of scope, prp-framework#213 (durable ledger). Any text can only raise R; caller-side author
#   filtering is in #212.
#
# usage: round-guard.sh [--cap N] < footer-lines
#   stdin: one line per PR comment = that comment's LAST line (the caller extracts it).
#   exit 0 = allowed (prints "rounds so far: R of N; this is round R+1")
#   exit 3 = refused: cap reached
#   exit 2 = bad argument, cannot read stdin, or grep failure (fail closed)
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
ID_RE='[0-9]{8}[Tt][0-9]{6}[Zz]-[0-9A-Fa-f]{8}'
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

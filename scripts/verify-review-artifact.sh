#!/bin/bash
# PRP Review-Artifact Gate — mechanical post-condition for run-all Step 6.
#
# Verifies that a review actually produced a verifiable artifact BEFORE the
# workflow may report review success. Exists because agents repeatedly claimed
# "review=0-issues" with no artifact on disk (agent-devops#534: three false
# claims on 2026-06-11 alone; the forced reviews then found real criticals).
#
# Usage:
#   verify-review-artifact.sh <pr_number> [options]
#
# Options:
#   --reviews-dir <dir>     Artifact directory (default: .prp-output/reviews)
#   --since <epoch>         Artifact mtime must be >= this UNIX timestamp
#                           (pass the time the review command was invoked —
#                           rejects stale artifacts from earlier runs/branches)
#   --require-tier agents   Artifact filename must be the multi-agent form
#                           pr-{N}-agents-review*.md (default: any tier)
#
# Output: "VERDICT: <line>" on success.
# Exit codes:
#   0  pass — artifact exists, fresh, tier-correct, verdict is 0-issues
#   1  artifact missing (or unreadable)
#   2  artifact stale (older than --since)
#   3  wrong tier (single-agent artifact where agents tier required)
#   4  verdict in artifact is NOT 0-issues / not READY TO MERGE
#   5  usage error
set -euo pipefail

PR_NUMBER="${1:-}"
[ -n "$PR_NUMBER" ] || { echo "ERROR: usage: verify-review-artifact.sh <pr_number> [options]" >&2; exit 5; }
case "$PR_NUMBER" in
    ''|*[!0-9]*) echo "ERROR: pr_number must be a positive integer, got '$PR_NUMBER'" >&2; exit 5 ;;
esac
shift

REVIEWS_DIR=".prp-output/reviews"
SINCE_EPOCH=""
REQUIRE_TIER="any"

while [ $# -gt 0 ]; do
    case "$1" in
        --reviews-dir) REVIEWS_DIR="${2:?--reviews-dir needs a value}"; shift 2 ;;
        --since)       SINCE_EPOCH="${2:?--since needs a value}"; shift 2 ;;
        --require-tier) REQUIRE_TIER="${2:?--require-tier needs a value}"; shift 2 ;;
        *) echo "ERROR: unknown option '$1'" >&2; exit 5 ;;
    esac
done

# --- locate artifact -------------------------------------------------------
# Multi-agent form first (canonical), then single-agent forms.
AGENTS_GLOB=("$REVIEWS_DIR"/pr-"$PR_NUMBER"-agents-review*.md)
SINGLE_GLOB=("$REVIEWS_DIR"/pr-"$PR_NUMBER"-review*.md)

ARTIFACT=""
TIER=""
if compgen -G "${AGENTS_GLOB[0]}" > /dev/null 2>&1; then
    ARTIFACT=$(ls -t "$REVIEWS_DIR"/pr-"$PR_NUMBER"-agents-review*.md 2>/dev/null | head -1)
    TIER="agents"
elif compgen -G "${SINGLE_GLOB[0]}" > /dev/null 2>&1; then
    ARTIFACT=$(ls -t "$REVIEWS_DIR"/pr-"$PR_NUMBER"-review*.md 2>/dev/null | head -1)
    TIER="single"
fi

if [ -z "$ARTIFACT" ] || [ ! -r "$ARTIFACT" ]; then
    echo "GATE FAIL (missing): no review artifact for PR #$PR_NUMBER under $REVIEWS_DIR/" >&2
    echo "  A review that produced no artifact did not happen. Re-run the review command." >&2
    exit 1
fi

# --- freshness -------------------------------------------------------------
if [ -n "$SINCE_EPOCH" ]; then
    MTIME=$(stat -c %Y "$ARTIFACT" 2>/dev/null || stat -f %m "$ARTIFACT")
    if [ "$MTIME" -lt "$SINCE_EPOCH" ]; then
        echo "GATE FAIL (stale): $ARTIFACT mtime=$MTIME < since=$SINCE_EPOCH" >&2
        echo "  Artifact predates this review invocation — likely from an earlier run/branch." >&2
        exit 2
    fi
fi

# --- tier ------------------------------------------------------------------
if [ "$REQUIRE_TIER" = "agents" ] && [ "$TIER" != "agents" ]; then
    echo "GATE FAIL (tier): found single-agent artifact '$ARTIFACT' but multi-agent review is required for this change class." >&2
    echo "  Run the agents-tier review (review-agents); single-agent is allowed for docs-only diffs." >&2
    exit 3
fi

# --- verdict (from FILE content, never from conversation memory) -----------
# Accept either the canonical zero-count line or an explicit READY TO MERGE
# verdict that is NOT contradicted by a non-zero count line.
ZERO_LINE=$(grep -iEm1 '0[[:space:]]*critical[[:space:]]*/[[:space:]]*0[[:space:]]*(high|important)[[:space:]]*/[[:space:]]*0[[:space:]]*medium' "$ARTIFACT" || true)
READY_LINE=$(grep -iEm1 'READY[[:space:]]+TO[[:space:]]+MERGE' "$ARTIFACT" || true)
NONZERO_LINE=$(grep -iEm1 '(^|[^0-9])[1-9][0-9]*[[:space:]]*critical|NEEDS[[:space:]]+FIXES' "$ARTIFACT" || true)

# A later READY-TO-MERGE supersedes an earlier NEEDS FIXES in the same file
# (fix-loop artifacts keep round history). Compare last occurrence positions.
if [ -n "$NONZERO_LINE" ] && [ -n "$READY_LINE" ]; then
    LAST_READY=$(grep -inE 'READY[[:space:]]+TO[[:space:]]+MERGE' "$ARTIFACT" | tail -1 | cut -d: -f1)
    LAST_BAD=$(grep -inE 'NEEDS[[:space:]]+FIXES' "$ARTIFACT" | tail -1 | cut -d: -f1)
    LAST_BAD=${LAST_BAD:-0}
    if [ "$LAST_READY" -gt "$LAST_BAD" ]; then
        NONZERO_LINE=""
    fi
fi

if [ -n "$ZERO_LINE" ] || { [ -n "$READY_LINE" ] && [ -z "$NONZERO_LINE" ]; }; then
    echo "GATE PASS: $ARTIFACT (tier=$TIER)"
    echo "VERDICT: ${ZERO_LINE:-$READY_LINE}"
    exit 0
fi

echo "GATE FAIL (verdict): $ARTIFACT does not show a 0-issues verdict." >&2
echo "  Last verdict signals: ready='${READY_LINE:-none}' nonzero='${NONZERO_LINE:-none}'" >&2
echo "  Run the review-fix loop until the artifact itself reads 0 across all severities." >&2
exit 4

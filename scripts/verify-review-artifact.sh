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
# When agents tier is required, ONLY agents-form artifacts qualify. Otherwise
# pick the NEWEST artifact across both forms — re-verify rounds write the
# single-agent form, which must win over a stale round-1 agents artifact.
ARTIFACT=""
TIER=""
if [ "$REQUIRE_TIER" = "agents" ]; then
    if compgen -G "$REVIEWS_DIR/pr-$PR_NUMBER-agents-review*.md" > /dev/null 2>&1; then
        ARTIFACT=$(ls -t "$REVIEWS_DIR"/pr-"$PR_NUMBER"-agents-review*.md 2>/dev/null | head -1)
        TIER="agents"
    elif compgen -G "$REVIEWS_DIR/pr-$PR_NUMBER-review*.md" > /dev/null 2>&1; then
        # A single-agent artifact exists but cannot satisfy the agents tier.
        FOUND_SINGLE=$(ls -t "$REVIEWS_DIR"/pr-"$PR_NUMBER"-review*.md 2>/dev/null | head -1)
        echo "GATE FAIL (tier): found single-agent artifact '$FOUND_SINGLE' but multi-agent review is required for this change class." >&2
        echo "  Run the agents-tier review (review-agents); single-agent is allowed for docs-only diffs." >&2
        exit 3
    fi
else
    if compgen -G "$REVIEWS_DIR/pr-$PR_NUMBER-review*.md" > /dev/null 2>&1 \
       || compgen -G "$REVIEWS_DIR/pr-$PR_NUMBER-agents-review*.md" > /dev/null 2>&1; then
        # One of the two globs may be unmatched (passed literally) — ls then
        # exits non-zero, which pipefail+set-e would turn into a silent death.
        ARTIFACT=$(ls -t "$REVIEWS_DIR"/pr-"$PR_NUMBER"-review*.md "$REVIEWS_DIR"/pr-"$PR_NUMBER"-agents-review*.md 2>/dev/null | head -1 || true)
        case "$(basename "$ARTIFACT")" in
            pr-"$PR_NUMBER"-agents-review*) TIER="agents" ;;
            *) TIER="single" ;;
        esac
    fi
fi

if [ -z "$ARTIFACT" ] || [ ! -r "$ARTIFACT" ]; then
    echo "GATE FAIL (missing): no review artifact for PR #$PR_NUMBER under $REVIEWS_DIR/" >&2
    echo "  A review that produced no artifact did not happen. Re-run the review command." >&2
    exit 1
fi

# --- freshness -------------------------------------------------------------
if [ -n "$SINCE_EPOCH" ]; then
    MTIME=$(stat -c %Y "$ARTIFACT" 2>/dev/null || stat -f %m "$ARTIFACT" 2>/dev/null \
        || { echo "GATE FAIL (missing): cannot stat '$ARTIFACT'" >&2; exit 1; })
    if [ "$MTIME" -lt "$SINCE_EPOCH" ]; then
        echo "GATE FAIL (stale): $ARTIFACT mtime=$MTIME < since=$SINCE_EPOCH" >&2
        echo "  Artifact predates this review invocation — likely from an earlier run/branch." >&2
        exit 2
    fi
fi

# --- verdict (from FILE content, never from conversation memory) -----------
# Position-based: fix-loop artifacts keep round history, so the LAST verdict
# signal in the file wins. GOOD signals = a zero-counts line or an explicit
# READY-TO-MERGE/APPROVE verdict. BAD signals = any non-zero severity count
# (critical/high/important/medium/suggestion) or NEEDS FIXES. The artifact
# passes only when a GOOD signal exists AND appears AFTER the last BAD signal
# — an early "0 critical" history line cannot whitewash a later NEEDS FIXES,
# and remaining suggestions block the gate (zero-issues bar covers ALL
# severities, matching FIX_SEVERITY's default).
GOOD_RE='0[[:space:]]*critical[[:space:]]*/[[:space:]]*0[[:space:]]*(high|important)|READY[[:space:]]+TO[[:space:]]+MERGE'
BAD_RE='(^|[^0-9.])[1-9][0-9]*[[:space:]]*(critical|high|important|medium|suggestion)s?([^a-z]|$)|NEEDS[[:space:]]+FIXES'

_last_line_no() { # regex -> line number of last match (0 if none)
    local n
    n=$(grep -icE "$1" "$ARTIFACT" 2>/dev/null || true)
    if [ "${n:-0}" -eq 0 ]; then echo 0; return; fi
    grep -inE "$1" "$ARTIFACT" | tail -1 | cut -d: -f1
}

LAST_GOOD=$(_last_line_no "$GOOD_RE")
LAST_BAD=$(_last_line_no "$BAD_RE")

if [ "$LAST_GOOD" -gt 0 ] && [ "$LAST_GOOD" -gt "$LAST_BAD" ]; then
    echo "GATE PASS: $ARTIFACT (tier=$TIER)"
    echo "VERDICT: $(sed -n "${LAST_GOOD}p" "$ARTIFACT")"
    exit 0
fi

echo "GATE FAIL (verdict): $ARTIFACT does not end on a 0-issues verdict." >&2
if [ "$LAST_BAD" -gt 0 ]; then
    echo "  Last BAD signal (line $LAST_BAD): $(sed -n "${LAST_BAD}p" "$ARTIFACT")" >&2
fi
echo "  Run the review-fix loop until the artifact itself reads 0 across ALL severities (suggestions included)." >&2
exit 4

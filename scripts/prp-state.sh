#!/usr/bin/env bash
set -euo pipefail

# prp-state — compact state management for PRP run-all
# Reads/writes .prp-output/state/run-all.state.md with minimal token output.
# Usage:
#   prp-state get <key>             → print value (1-2 tokens)
#   prp-state set <key> <value>     → update + print "ok"
#   prp-state summary               → one-line status (~20 tokens)
#   prp-state check-gate <gate>     → check if ready to proceed
#   prp-state init [key=value ...]  → create state file
#   prp-state dump                  → print full state (debugging)

STATE_FILE=".prp-output/state/run-all.state.md"
CMD="${1:-help}"
shift 2>/dev/null || true

# Helper: extract value from YAML frontmatter (returns empty string if key not found)
get_val() {
    local key="$1"
    sed -n '/^---$/,/^---$/p' "$STATE_FILE" 2>/dev/null | grep "^${key}:" | sed "s/^${key}: *//" | sed 's/^"//' | sed 's/"$//' || true
}

case "$CMD" in
    get)
        [ -f "$STATE_FILE" ] || { echo "error: no state file"; exit 1; }
        get_val "${1:?Usage: prp-state get <key>}"
        ;;

    set)
        [ -f "$STATE_FILE" ] || { echo "error: no state file"; exit 1; }
        KEY="${1:?Usage: prp-state set <key> <value>}"
        VALUE="${2:?Usage: prp-state set <key> <value>}"
        # Validate: no newlines in key or value
        [[ "$KEY" == *$'\n'* ]] && { echo "error: newline in key"; exit 1; }
        [[ "$VALUE" == *$'\n'* ]] && { echo "error: newline in value"; exit 1; }
        # Use awk for safe substitution (no sed delimiter/regex issues)
        if grep -qF "${KEY}:" "$STATE_FILE"; then
            awk -v key="$KEY" -v val="$VALUE" '{
                if ($0 ~ "^"key":") print key": "val
                else print
            }' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
        else
            awk -v key="$KEY" -v val="$VALUE" 'NR>1 && /^---$/ && !done { print key": "val; done=1 } { print }' \
                "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
        fi
        echo "ok"
        ;;

    summary)
        [ -f "$STATE_FILE" ] || { echo "no active run-all"; exit 0; }
        STEP=$(get_val "step")
        PR=$(get_val "pr_number")
        ROUND=$(get_val "review_round")
        MAX_ROUND=$(get_val "max_review_rounds")
        BRANCH=$(get_val "branch")
        STATUS=$(get_val "status")

        # Map step number to name
        case "${STEP:-0}" in
            0) STEP_NAME="init" ;;
            1) STEP_NAME="plan" ;;
            2) STEP_NAME="branch" ;;
            3) STEP_NAME="implement" ;;
            4) STEP_NAME="commit+pr" ;;
            5) STEP_NAME="review" ;;
            6) STEP_NAME="review-fix" ;;
            7) STEP_NAME="merge" ;;
            8) STEP_NAME="cleanup" ;;
            *) STEP_NAME="step-$STEP" ;;
        esac

        echo "Step ${STEP:-0}/8: ${STEP_NAME} (PR #${PR:-?}, round ${ROUND:-0}/${MAX_ROUND:-5}, branch: ${BRANCH:-?}, ${STATUS:-?})"
        ;;

    check-gate)
        [ -f "$STATE_FILE" ] || { echo "blocked: no state file"; exit 1; }
        GATE="${1:?Usage: prp-state check-gate <plan|review|merge>}"
        case "$GATE" in
            plan)
                PLAN=$(get_val "plan_path")
                [ -f "${PLAN:-__missing__}" ] && echo "ready: plan at $PLAN" || echo "blocked: plan not found (${PLAN:-unset})"
                ;;
            review)
                VAL=$(get_val "validation_passed")
                PR=$(get_val "pr_number")
                [ "$VAL" = "true" ] && [ -n "$PR" ] && echo "ready: validation passed, PR #$PR" || echo "blocked: validation=${VAL:-?} pr=${PR:-?}"
                ;;
            merge)
                ROUND=$(get_val "review_round")
                VERDICT=$(get_val "review_verdict")
                if [ "$VERDICT" = "pass" ] || [ "$VERDICT" = "READY TO MERGE" ]; then
                    echo "ready: review round ${ROUND:-0} passed"
                else
                    echo "blocked: review_verdict=${VERDICT:-unset} (round ${ROUND:-0})"
                fi
                ;;
            *)
                echo "unknown gate: $GATE"
                exit 1
                ;;
        esac
        ;;

    init)
        mkdir -p .prp-output/state
        {
            echo "---"
            echo "status: in_progress"
            echo "step: 0"
            echo "started_at: $(date -Iseconds)"
            echo "review_round: 0"
            echo "max_review_rounds: 5"
            # Add any passed key=value pairs (convert = to : for YAML)
            for kv in "$@"; do
                [[ "$kv" == *=* ]] || { echo "error: init argument must be key=value, got: $kv" >&2; exit 1; }
                echo "${kv/=/: }"
            done
            echo "---"
        } > "$STATE_FILE"
        echo "ok"
        ;;

    dump)
        [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo "no state file"
        ;;

    help|*)
        echo "Usage: prp-state {get|set|summary|check-gate|init|dump} [args]"
        echo ""
        echo "Commands:"
        echo "  get <key>             Print a single state value"
        echo "  set <key> <value>     Update a state value"
        echo "  summary               One-line progress summary"
        echo "  check-gate <gate>     Check readiness (plan|review|merge)"
        echo "  init [key=val ...]    Create new state file"
        echo "  dump                  Print full state file"
        ;;
esac

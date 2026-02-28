#!/bin/bash
# PRP Run-All State Management Helper
#
# Manages the workflow state file at .claude/prp-run-all.state.md
# Used by run-all workflow and tested via bats.
#
# Usage: prp-run-all-state.sh <command> [args]
#
# Commands:
#   create <feature> [use_ralph] [ralph_max_iter] [fix_severity] [skip_review] [no_pr]
#   update-step <step_number> <step_name> <result>
#   get-step        — prints current step number
#   get-var <name>  — prints a variable from YAML frontmatter
#   add-artifact <artifact_line>
#   cleanup         — removes state and lock files
#   exists          — exit 0 if state file exists, 1 if not
#   lock            — acquire lock, exit 1 if already locked
#   unlock          — release lock

STATE_FILE=".claude/prp-run-all.state.md"
LOCK_FILE=".claude/prp-run-all.lock"

# ─────────────────────────────────────────────
# Parse YAML frontmatter value
# ─────────────────────────────────────────────
get_frontmatter_value() {
    local key="$1"
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return 1
    fi
    # Extract value between --- markers
    sed -n '/^---$/,/^---$/p' "$STATE_FILE" | grep "^${key}:" | head -1 | sed "s/^${key}: *//" | sed 's/^"//' | sed 's/"$//'
}

# ─────────────────────────────────────────────
# Update YAML frontmatter value
# ─────────────────────────────────────────────
set_frontmatter_value() {
    local key="$1"
    local value="$2"
    if [ ! -f "$STATE_FILE" ]; then
        return 1
    fi
    # Use sed to replace the value in frontmatter
    if grep -q "^${key}:" "$STATE_FILE"; then
        sed -i.bak "s|^${key}:.*|${key}: ${value}|" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"
    fi
}

case "$1" in
    create)
        local_feature="${2:-unnamed}"
        local_use_ralph="${3:-false}"
        local_ralph_max_iter="${4:-10}"
        local_fix_severity="${5:-critical,high,medium,suggestion}"
        local_skip_review="${6:-false}"
        local_no_pr="${7:-false}"
        local_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        mkdir -p .claude
        cat > "$STATE_FILE" <<EOF
---
step: 1
total_steps: 7
feature: "${local_feature}"
plan_path: ""
branch: ""
pr_number: ""
review_artifact: ""
use_ralph: ${local_use_ralph}
ralph_max_iter: ${local_ralph_max_iter}
fix_severity: "${local_fix_severity}"
skip_review: ${local_skip_review}
no_pr: ${local_no_pr}
started_at: "${local_timestamp}"
updated_at: "${local_timestamp}"
---
# PRP Run-All Workflow State
## Completed Steps
| Step | Name | Result | Timestamp |
|------|------|--------|-----------|
| 0 | Parse Input | OK | $(date +%H:%M) |
## Artifacts
(none yet)
## Error Log
(empty)
EOF
        echo "State file created at $STATE_FILE"
        ;;

    update-step)
        local_step="$2"
        local_name="$3"
        local_result="$4"
        local_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local_time=$(date +%H:%M)

        if [ ! -f "$STATE_FILE" ]; then
            echo "Error: State file not found" >&2
            exit 1
        fi

        # Update step number and timestamp in frontmatter
        set_frontmatter_value "step" "$local_step"
        set_frontmatter_value "updated_at" "\"${local_timestamp}\""

        # Append to completed steps table (before ## Artifacts line)
        sed -i.bak "/^## Artifacts/i\\
| ${local_step} | ${local_name} | ${local_result} | ${local_time} |" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"

        echo "Step updated to $local_step: $local_name"
        ;;

    get-step)
        step=$(get_frontmatter_value "step")
        if [ -z "$step" ]; then
            echo "Error: Cannot read step from state file" >&2
            exit 1
        fi
        echo "$step"
        ;;

    get-var)
        var_name="$2"
        if [ -z "$var_name" ]; then
            echo "Usage: prp-run-all-state.sh get-var <name>" >&2
            exit 1
        fi
        value=$(get_frontmatter_value "$var_name")
        if [ -z "$value" ]; then
            echo "Error: Variable '$var_name' not found" >&2
            exit 1
        fi
        echo "$value"
        ;;

    add-artifact)
        local_artifact="$2"
        if [ ! -f "$STATE_FILE" ]; then
            echo "Error: State file not found" >&2
            exit 1
        fi
        # Replace "(none yet)" or append after existing artifacts
        if grep -q "(none yet)" "$STATE_FILE"; then
            sed -i.bak "s|(none yet)|- ${local_artifact}|" "$STATE_FILE"
        else
            sed -i.bak "/^## Error Log/i\\
- ${local_artifact}" "$STATE_FILE"
        fi
        rm -f "${STATE_FILE}.bak"
        echo "Artifact added: $local_artifact"
        ;;

    cleanup)
        rm -f "$STATE_FILE" "$LOCK_FILE"
        echo "State and lock files cleaned up"
        ;;

    exists)
        [ -f "$STATE_FILE" ]
        ;;

    lock)
        if [ -f "$LOCK_FILE" ]; then
            # Check if stale (older than 2 hours = 7200 seconds)
            if [ "$(uname)" = "Darwin" ]; then
                lock_age=$(( $(date +%s) - $(stat -f "%m" "$LOCK_FILE") ))
            else
                lock_age=$(( $(date +%s) - $(stat -c "%Y" "$LOCK_FILE") ))
            fi
            if [ "$lock_age" -gt 7200 ]; then
                echo "Removing stale lock (age: ${lock_age}s)"
                rm -f "$LOCK_FILE"
            else
                echo "Error: Workflow already locked (age: ${lock_age}s)" >&2
                exit 1
            fi
        fi
        mkdir -p .claude
        echo "$$" > "$LOCK_FILE"
        echo "Lock acquired"
        ;;

    unlock)
        rm -f "$LOCK_FILE"
        echo "Lock released"
        ;;

    *)
        echo "Usage: prp-run-all-state.sh <create|update-step|get-step|get-var|add-artifact|cleanup|exists|lock|unlock> [args]" >&2
        exit 1
        ;;
esac

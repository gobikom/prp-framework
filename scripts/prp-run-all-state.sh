#!/bin/bash
# PRP Run-All State Management Helper
#
# Manages the workflow state file at .prp-output/state/run-all.state.md
# Used by run-all workflow and tested via bats.
#
# Usage: prp-run-all-state.sh <command> [args]
#
# Commands:
#   create <feature> [use_ralph] [ralph_max_iter] [fix_severity] [skip_review] [no_pr]
#   update-step <step_number> <step_name> <result>
#   set-var <name> <value>
#   set-review-fix-state <fixed_count> <skipped_count>
#   get-step        — prints current step number
#   get-var <name>  — prints a variable from YAML frontmatter
#   add-artifact <artifact_line>
#   cleanup         — removes state and lock files
#   exists          — exit 0 if state file exists, 1 if not
#   lock            — acquire lock, exit 1 if already locked
#   unlock          — release lock

STATE_FILE=".prp-output/state/run-all.state.md"
LOCK_FILE=".prp-output/state/run-all.lock"

# ─────────────────────────────────────────────
# Parse YAML frontmatter value
# ─────────────────────────────────────────────
get_frontmatter_value() {
    local key="$1"
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return 1
    fi
    validate_frontmatter_key "$key" || return 1
    # Extract value between --- markers. An explicitly empty value is valid.
    awk -v key="$key" '
        BEGIN { marker = 0; found = 0 }
        $0 == "---" { marker++; next }
        marker == 1 {
            split($0, parts, ":")
            if (parts[1] == key) {
                value = substr($0, length(key) + 2)
                sub(/^ */, "", value)
                sub(/^"/, "", value)
                sub(/"$/, "", value)
                print value
                found = 1
                exit
            }
        }
        END { if (found == 0) exit 1 }
    ' "$STATE_FILE"
}

# ─────────────────────────────────────────────
# Legacy default values for state files created before new fields existed
# ─────────────────────────────────────────────
default_frontmatter_value() {
    local key="$1"
    case "$key" in
        review_artifact|review_verdict)
            echo ""
            ;;
        review_cycle)
            echo "1"
            ;;
        pending_skipped|all_skipped)
            echo "false"
            ;;
        skipped_count|all_skipped_rounds)
            echo "0"
            ;;
        *)
            return 1
            ;;
    esac
}

# ─────────────────────────────────────────────
# Validate frontmatter keys before matching or writing
# ─────────────────────────────────────────────
validate_frontmatter_key() {
    local key="$1"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# ─────────────────────────────────────────────
# Update YAML frontmatter value
# ─────────────────────────────────────────────
set_frontmatter_value() {
    local key="$1"
    local value="$2"
    local tmp_file
    if [ ! -f "$STATE_FILE" ]; then
        return 1
    fi
    validate_frontmatter_key "$key" || return 1
    # Replace existing keys, or add new keys for older state files on resume.
    tmp_file="${STATE_FILE}.tmp"
    awk -v key="$key" -v value="$value" '
        BEGIN { marker = 0; updated = 0 }
        {
            if ($0 == "---") {
                marker++
                if (marker == 2 && updated == 0) {
                    print key ": " value
                    updated = 1
                }
                print
                next
            }
            if (marker == 1) {
                split($0, parts, ":")
                if (parts[1] == key) {
                    print key ": " value
                    updated = 1
                    next
                }
            }
            print
        }
    ' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
}

# ─────────────────────────────────────────────
# Update YAML frontmatter value or fail closed
# ─────────────────────────────────────────────
must_set_frontmatter_value() {
    local key="$1"
    local value="$2"

    if ! set_frontmatter_value "$key" "$value"; then
        echo "Error: Cannot update variable '$key'" >&2
        exit 1
    fi
}

# ─────────────────────────────────────────────
# Increment numeric YAML frontmatter value
# ─────────────────────────────────────────────
increment_frontmatter_counter() {
    local key="$1"
    local value

    if ! value=$(get_frontmatter_value "$key"); then
        value="0"
    fi
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        value="0"
    fi
    must_set_frontmatter_value "$key" "$((value + 1))"
}

# ─────────────────────────────────────────────
# Persist review-fix skipped-state tuple
# ─────────────────────────────────────────────
set_review_fix_state() {
    local fixed_count="$1"
    local skipped_count="$2"
    local timestamp

    if [ ! -f "$STATE_FILE" ]; then
        echo "Error: State file not found" >&2
        exit 1
    fi

    if ! [[ "$fixed_count" =~ ^[0-9]+$ ]] || ! [[ "$skipped_count" =~ ^[0-9]+$ ]]; then
        echo "Error: fixed_count and skipped_count must be non-negative integers" >&2
        exit 1
    fi

    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ "$skipped_count" -eq 0 ]; then
        must_set_frontmatter_value "pending_skipped" "false"
        must_set_frontmatter_value "all_skipped" "false"
        must_set_frontmatter_value "skipped_count" "0"
    elif [ "$fixed_count" -eq 0 ]; then
        must_set_frontmatter_value "pending_skipped" "true"
        must_set_frontmatter_value "all_skipped" "true"
        must_set_frontmatter_value "skipped_count" "$skipped_count"
        increment_frontmatter_counter "all_skipped_rounds"
    else
        must_set_frontmatter_value "pending_skipped" "true"
        must_set_frontmatter_value "all_skipped" "false"
        must_set_frontmatter_value "skipped_count" "$skipped_count"
        must_set_frontmatter_value "all_skipped_rounds" "0"
    fi
    if [ "$skipped_count" -eq 0 ]; then
        must_set_frontmatter_value "all_skipped_rounds" "0"
    fi
    must_set_frontmatter_value "updated_at" "\"${timestamp}\""
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

        mkdir -p .prp-output/state
        cat > "$STATE_FILE" <<EOF
---
step: 1
total_steps: 7
feature: "${local_feature}"
plan_path: ""
branch: ""
pr_number: ""
review_artifact: ""
review_verdict: ""
review_cycle: 1
pending_skipped: false
all_skipped: false
skipped_count: 0
all_skipped_rounds: 0
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
        must_set_frontmatter_value "step" "$local_step"
        must_set_frontmatter_value "updated_at" "\"${local_timestamp}\""

        # Append to completed steps table (before ## Artifacts line)
        sed -i.bak "/^## Artifacts/i\\
| ${local_step} | ${local_name} | ${local_result} | ${local_time} |" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"

        echo "Step updated to $local_step: $local_name"
        ;;

    set-var)
        var_name="$2"
        var_value="$3"
        if [ "$#" -lt 3 ] || [ -z "$var_name" ]; then
            echo "Usage: prp-run-all-state.sh set-var <name> <value>" >&2
            exit 1
        fi
        if [ ! -f "$STATE_FILE" ]; then
            echo "Error: State file not found" >&2
            exit 1
        fi
        if ! validate_frontmatter_key "$var_name"; then
            echo "Error: Invalid variable name '$var_name'" >&2
            exit 1
        fi
        must_set_frontmatter_value "$var_name" "$var_value"
        echo "Variable updated: $var_name"
        ;;

    set-review-fix-state)
        set_review_fix_state "${2:-}" "${3:-}"
        echo "Review-fix state updated"
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
        # Present-but-empty values (e.g. review_verdict: "") are valid:
        # get_frontmatter_value succeeds with empty stdout, so we print "".
        # Only fall back to defaults when the key is absent from frontmatter.
        if ! value=$(get_frontmatter_value "$var_name"); then
            if ! value=$(default_frontmatter_value "$var_name"); then
                echo "Error: Variable '$var_name' not found" >&2
                exit 1
            fi
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
        mkdir -p .prp-output/state
        echo "$$" > "$LOCK_FILE"
        echo "Lock acquired"
        ;;

    unlock)
        rm -f "$LOCK_FILE"
        echo "Lock released"
        ;;

    *)
        echo "Usage: prp-run-all-state.sh <create|update-step|set-var|set-review-fix-state|get-step|get-var|add-artifact|cleanup|exists|lock|unlock> [args]" >&2
        exit 1
        ;;
esac

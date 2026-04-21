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
    # The key is validated above (alphanumeric + underscore only), so awk's
    # `-v` C-escape decoding is harmless for it. On the write path
    # (`set_frontmatter_value`), values flow through ENVIRON instead of `-v`
    # to prevent backslash-sequence decoding of untrusted strings.
    awk -v key="$key" '
        BEGIN { marker = 0; found = 0; value = "" }
        $0 == "---" { marker++; next }
        marker == 1 && found == 0 {
            split($0, parts, ":")
            if (parts[1] == key) {
                value = substr($0, length(key) + 2)
                sub(/^ */, "", value)
                sub(/^"/, "", value)
                sub(/"$/, "", value)
                found = 1
            }
        }
        END {
            if (marker < 2) {
                exit 2
            }
            if (found == 0) {
                exit 1
            }
            print value
        }
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

# Reject values that would break YAML frontmatter structure:
# newlines/CR allow key-injection above the legitimate key; a `---` line
# (with optional trailing whitespace — valid YAML frontmatter close)
# would terminate the frontmatter block. Callers forwarding untrusted
# input (e.g. GitHub issue bodies via --issue N) depend on this boundary.
validate_frontmatter_value() {
    local value="$1"
    if [[ "$value" == *$'\n'* ]] || [[ "$value" == *$'\r'* ]]; then
        return 1
    fi
    if [[ "$value" =~ ^---[[:space:]]*$ ]]; then
        return 1
    fi
    return 0
}

validate_frontmatter_bool() {
    local value="$1"
    [[ "$value" == "true" || "$value" == "false" ]]
}

validate_frontmatter_uint() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]]
}

yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
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
    validate_frontmatter_value "$value" || return 1
    if [ "${PRP_STATE_FAIL_KEY:-}" = "$key" ]; then
        return 1
    fi
    # Replace existing keys, or add new keys for older state files on resume.
    tmp_file="${STATE_FILE}.tmp"
    if ! FRONTMATTER_VALUE="$value" awk -v key="$key" '
        BEGIN { marker = 0; updated = 0; value = ENVIRON["FRONTMATTER_VALUE"] }
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
        END {
            if (marker < 2 || updated == 0) {
                exit 1
            }
        }
    ' "$STATE_FILE" > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! mv "$tmp_file" "$STATE_FILE"; then
        rm -f "$tmp_file"
        return 1
    fi
}

# ─────────────────────────────────────────────
# Ensure a markdown section marker exists before mutating related body content
# ─────────────────────────────────────────────
require_body_section() {
    local section="$1"

    if ! grep -qxF "$section" "$STATE_FILE"; then
        echo "Error: State file missing required section '$section'" >&2
        return 1
    fi
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
        # Non-numeric value indicates state-file corruption or manual edit.
        # Surface the reset so operators see the signal instead of silently overwriting.
        if [ -n "$value" ]; then
            echo "Warning: non-numeric value '$value' for counter '$key'; resetting to 0" >&2
        fi
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
    local backup

    if [ ! -f "$STATE_FILE" ]; then
        echo "Error: State file not found" >&2
        exit 1
    fi

    if ! [[ "$fixed_count" =~ ^[0-9]+$ ]] || ! [[ "$skipped_count" =~ ^[0-9]+$ ]]; then
        echo "Error: fixed_count and skipped_count must be non-negative integers" >&2
        exit 1
    fi

    if ! timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") || [ -z "$timestamp" ]; then
        echo "Error: Cannot generate timestamp" >&2
        exit 1
    fi

    # Atomic-rollback snapshot: the tuple touches up to 5 frontmatter keys
    # sequentially, and a midway write failure would leave partial state.
    # Restoring from a pre-write snapshot keeps the file consistent.
    backup="${STATE_FILE}.rollback.$$"
    if ! cp "$STATE_FILE" "$backup" 2>/dev/null; then
        echo "Error: Cannot snapshot state for atomic update" >&2
        exit 1
    fi

    local ok=1
    if [ "$skipped_count" -eq 0 ]; then
        set_frontmatter_value "pending_skipped" "false" && \
            set_frontmatter_value "all_skipped" "false" && \
            set_frontmatter_value "skipped_count" "0" && \
            set_frontmatter_value "all_skipped_rounds" "0" || ok=0
    elif [ "$fixed_count" -eq 0 ]; then
        local rounds_value rounds_next rounds_rc
        rounds_value=$(get_frontmatter_value "all_skipped_rounds" 2>/dev/null)
        rounds_rc=$?
        if [ "$rounds_rc" -eq 2 ]; then
            # Distinct from missing-key (exit 1): exit 2 means malformed
            # frontmatter. Preserve the counter-reset behavior but WARN so
            # the corruption isn't silently swallowed.
            echo "Warning: malformed frontmatter while reading 'all_skipped_rounds' — resetting counter to 0" >&2
            rounds_value="0"
        elif [ "$rounds_rc" -ne 0 ]; then
            rounds_value="0"
        fi
        if ! [[ "$rounds_value" =~ ^[0-9]+$ ]]; then
            if [ -n "$rounds_value" ]; then
                echo "Warning: non-numeric value '$rounds_value' for counter 'all_skipped_rounds'; resetting to 0" >&2
            fi
            rounds_value="0"
        fi
        rounds_next=$((rounds_value + 1))
        set_frontmatter_value "pending_skipped" "true" && \
            set_frontmatter_value "all_skipped" "true" && \
            set_frontmatter_value "skipped_count" "$skipped_count" && \
            set_frontmatter_value "all_skipped_rounds" "$rounds_next" || ok=0
    else
        set_frontmatter_value "pending_skipped" "true" && \
            set_frontmatter_value "all_skipped" "false" && \
            set_frontmatter_value "skipped_count" "$skipped_count" && \
            set_frontmatter_value "all_skipped_rounds" "0" || ok=0
    fi

    if [ "$ok" -eq 1 ] && set_frontmatter_value "updated_at" "\"${timestamp}\""; then
        # Non-fatal: a leaked backup is recoverable (next run's snapshot
        # will overwrite the PID-suffixed path), but surface the problem
        # so a read-only FS or full disk doesn't go unnoticed.
        rm -f "$backup" || echo "WARN: Could not remove rollback backup: $backup" >&2
    else
        # Roll back to the pre-write snapshot. If the rollback itself fails,
        # preserve the backup so an operator can recover manually — losing
        # both the partial state AND the backup would be unrecoverable.
        if ! mv "$backup" "$STATE_FILE" 2>/dev/null; then
            echo "CRITICAL: rollback failed — state file may be partial. Backup preserved at: $backup" >&2
            exit 2
        fi
        echo "Error: Failed to update review-fix state; rolled back to prior snapshot" >&2
        exit 1
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
        local_feature_yaml=""
        local_fix_severity_yaml=""

        # Reject caller-supplied values that would break YAML frontmatter.
        # feature and fix_severity flow through into heredoc-rendered YAML.
        # Quote/escape string fields and constrain unquoted scalar fields.
        for _field in "$local_feature" "$local_fix_severity"; do
            if ! validate_frontmatter_value "$_field"; then
                echo "Error: invalid characters in create argument (newline, CR, or '---')" >&2
                exit 1
            fi
        done
        if ! validate_frontmatter_bool "$local_use_ralph" || \
            ! validate_frontmatter_uint "$local_ralph_max_iter" || \
            ! validate_frontmatter_bool "$local_skip_review" || \
            ! validate_frontmatter_bool "$local_no_pr"; then
            echo "Error: invalid create argument (booleans must be true/false; ralph_max_iter must be a non-negative integer)" >&2
            exit 1
        fi
        local_feature_yaml=$(yaml_quote "$local_feature")
        local_fix_severity_yaml=$(yaml_quote "$local_fix_severity")

        if ! local_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") || [ -z "$local_timestamp" ]; then
            echo "Error: Cannot generate timestamp" >&2
            exit 1
        fi

        if ! mkdir -p .prp-output/state; then
            echo "Error: Cannot create state directory" >&2
            exit 1
        fi
        if ! cat > "$STATE_FILE" <<EOF
---
step: 1
total_steps: 7
feature: ${local_feature_yaml}
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
fix_severity: ${local_fix_severity_yaml}
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
        then
            echo "Error: Cannot write state file" >&2
            exit 1
        fi
        echo "State file created at $STATE_FILE"
        ;;

    update-step)
        local_step="$2"
        local_name="$3"
        local_result="$4"

        if [ ! -f "$STATE_FILE" ]; then
            echo "Error: State file not found" >&2
            exit 1
        fi

        # Reject newlines/CR in the caller-supplied name/result — they would
        # corrupt the completed-steps markdown table.
        for _field in "$local_name" "$local_result"; do
            if ! validate_frontmatter_value "$_field"; then
                echo "Error: invalid characters in update-step argument (newline, CR, or '---')" >&2
                exit 1
            fi
        done

        if ! [[ "$local_step" =~ ^[0-9]+$ ]]; then
            echo "Error: step number must be a non-negative integer" >&2
            exit 1
        fi

        if ! local_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") || [ -z "$local_timestamp" ]; then
            echo "Error: Cannot generate timestamp" >&2
            exit 1
        fi
        if ! local_time=$(date +%H:%M) || [ -z "$local_time" ]; then
            echo "Error: Cannot generate wall-clock time" >&2
            exit 1
        fi

        # Guard: required body sections must exist before any mutation.
        require_body_section "## Completed Steps" || exit 1
        require_body_section "|------|------|--------|-----------|" || exit 1
        require_body_section "## Artifacts" || exit 1

        # Snapshot for atomic rollback if any of the 3 writes below fail.
        backup="${STATE_FILE}.rollback.$$"
        if ! cp "$STATE_FILE" "$backup" 2>/dev/null; then
            echo "Error: Cannot snapshot state for atomic step update" >&2
            exit 1
        fi

        # Writes 1 and 2 (of 3): update step number and timestamp in
        # frontmatter. Write 3 is the completed-step body row below.
        if ! set_frontmatter_value "step" "$local_step" || \
            ! set_frontmatter_value "updated_at" "\"${local_timestamp}\""; then
            if ! mv "$backup" "$STATE_FILE" 2>/dev/null; then
                echo "CRITICAL: rollback failed — state file may be partial. Backup preserved at: $backup" >&2
                exit 2
            fi
            echo "Error: Failed to update completed-step frontmatter; rolled back to prior snapshot" >&2
            exit 1
        fi

        # Write 3 (of 3): append the completed-step row to the body table.
        tmp_file="${STATE_FILE}.tmp"
        if ! STEP_ROW="| ${local_step} | ${local_name} | ${local_result} | ${local_time} |" awk '
            BEGIN { inserted = 0; row = ENVIRON["STEP_ROW"] }
            $0 == "## Artifacts" {
                print row
                inserted = 1
                print
                next
            }
            { print }
            END {
                if (inserted != 1) {
                    exit 1
                }
            }
        ' "$STATE_FILE" > "$tmp_file"; then
            rm -f "$tmp_file"
            if ! mv "$backup" "$STATE_FILE" 2>/dev/null; then
                echo "CRITICAL: rollback failed — state file may be partial. Backup preserved at: $backup" >&2
                exit 2
            fi
            echo "Error: Failed to append completed-step row" >&2
            exit 1
        fi
        if ! mv "$tmp_file" "$STATE_FILE"; then
            rm -f "$tmp_file"
            if ! mv "$backup" "$STATE_FILE" 2>/dev/null; then
                echo "CRITICAL: rollback failed — state file may be partial. Backup preserved at: $backup" >&2
                exit 2
            fi
            echo "Error: Failed to replace state file with completed-step update" >&2
            exit 1
        fi
        # Non-fatal: a leaked backup is recoverable (next run's snapshot
        # will overwrite the PID-suffixed path), but surface the problem
        # so a read-only FS or full disk doesn't go unnoticed.
        rm -f "$backup" || echo "WARN: Could not remove rollback backup: $backup" >&2

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
        # `|| exit $?` mirrors the set-review-fix-state dispatcher pattern:
        # `must_set_frontmatter_value` exits on failure today, but a future
        # refactor to `return` must not silently print the success line.
        must_set_frontmatter_value "$var_name" "$var_value" || exit $?
        echo "Variable updated: $var_name"
        ;;

    set-review-fix-state)
        # `|| exit $?` is defensive: the function exits on any failure today,
        # but a future refactor from `exit` to `return` must not silently print
        # the success line below.
        set_review_fix_state "${2:-}" "${3:-}" || exit $?
        echo "Review-fix state updated"
        ;;

    get-step)
        step=$(get_frontmatter_value "step")
        step_status=$?
        # Distinguish malformed frontmatter (exit 2) from missing key (exit 1)
        # so the operator sees an actionable signal on a corrupt state file.
        if [ "$step_status" -eq 2 ]; then
            echo "Error: State file frontmatter is malformed" >&2
            exit 1
        fi
        if [ "$step_status" -ne 0 ] || [ -z "$step" ]; then
            echo "Error: Cannot read step from state file" >&2
            exit 1
        fi
        echo "$step"
        ;;

    get-var)
        var_name="$2"
        var_status=0
        if [ -z "$var_name" ]; then
            echo "Usage: prp-run-all-state.sh get-var <name>" >&2
            exit 1
        fi
        # Present-but-empty values (e.g. review_verdict: "") are valid:
        # get_frontmatter_value succeeds with empty stdout, so we print "".
        # Only fall back to defaults when the key is absent from frontmatter.
        value=$(get_frontmatter_value "$var_name")
        var_status=$?
        if [ "$var_status" -ne 0 ]; then
            if [ "$var_status" -ne 1 ]; then
                echo "Error: State file frontmatter is malformed" >&2
                exit 1
            fi
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
        if ! validate_frontmatter_value "$local_artifact"; then
            echo "Error: invalid characters in artifact (newline, CR, or '---')" >&2
            exit 1
        fi
        require_body_section "## Artifacts" || exit 1
        require_body_section "## Error Log" || exit 1

        tmp_file="${STATE_FILE}.tmp"
        if ! ARTIFACT_VALUE="$local_artifact" awk '
            BEGIN {
                artifact = ENVIRON["ARTIFACT_VALUE"]
                in_artifacts = 0
                inserted = 0
            }
            $0 == "## Artifacts" {
                in_artifacts = 1
                print
                next
            }
            in_artifacts == 1 && $0 == "(none yet)" {
                print "- " artifact
                inserted = 1
                next
            }
            in_artifacts == 1 && $0 == "## Error Log" {
                if (inserted == 0) {
                    print "- " artifact
                    inserted = 1
                }
                in_artifacts = 0
                print
                next
            }
            { print }
            END {
                if (inserted != 1) {
                    exit 1
                }
            }
        ' "$STATE_FILE" > "$tmp_file"; then
            rm -f "$tmp_file"
            echo "Error: Failed to write artifact line" >&2
            exit 1
        fi
        if ! mv "$tmp_file" "$STATE_FILE"; then
            rm -f "$tmp_file"
            echo "Error: Failed to replace state file with artifact update" >&2
            exit 1
        fi
        echo "Artifact added: $local_artifact"
        ;;

    cleanup)
        # `rm -f` intentionally treats missing files as success (that's the
        # `-f` flag). Guard only catches true removal failures — permission
        # errors, read-only filesystem, etc. Do NOT remove `-f` to "fail
        # loudly on missing files"; the workflow relies on cleanup being
        # idempotent after a successful run.
        if ! rm -f "$STATE_FILE" "$LOCK_FILE"; then
            echo "Error: Failed to remove state or lock file during cleanup" >&2
            exit 1
        fi
        echo "State and lock files cleaned up"
        ;;

    exists)
        [ -f "$STATE_FILE" ]
        ;;

    lock)
        if [ -f "$LOCK_FILE" ]; then
            # Capture mtime into a variable so a stat failure (race: file gone
            # between -f check and stat, or permission error) does not feed
            # empty string into the arithmetic and silently produce lock_age=0.
            if [ "$(uname)" = "Darwin" ]; then
                lock_mtime=$(stat -f "%m" "$LOCK_FILE" 2>/dev/null)
            else
                lock_mtime=$(stat -c "%Y" "$LOCK_FILE" 2>/dev/null)
            fi
            if ! [[ "$lock_mtime" =~ ^[0-9]+$ ]]; then
                # Unreadable or vanished lock — treat as stale and remove.
                echo "Removing unreadable lock (stat failed or file gone)"
                rm -f "$LOCK_FILE"
            else
                # 2-hour stale threshold: long enough to outlast any normal
                # run-all workflow (largest runs complete in <1h), short enough
                # to recover from a crashed session on the next invocation
                # without operator intervention.
                lock_age=$(( $(date +%s) - lock_mtime ))
                if [ "$lock_age" -gt 7200 ]; then
                    echo "Removing stale lock (age: ${lock_age}s)"
                    rm -f "$LOCK_FILE"
                else
                    echo "Error: Workflow already locked (age: ${lock_age}s)" >&2
                    exit 1
                fi
            fi
        fi
        if ! mkdir -p .prp-output/state; then
            echo "Error: Cannot create state directory for lock" >&2
            exit 1
        fi
        # Fail closed on write failure: a silent-success lock would let a
        # second caller also "acquire" the missing lock, collapsing the
        # mutual-exclusion guarantee.
        if ! echo "$$" > "$LOCK_FILE"; then
            echo "Error: Cannot write lock file" >&2
            exit 1
        fi
        echo "Lock acquired"
        ;;

    unlock)
        # Fail loudly if the lock file removal fails — a silent success here
        # would leave the mutex in place and block future runs indefinitely.
        if ! rm -f "$LOCK_FILE"; then
            echo "Error: Failed to remove lock file" >&2
            exit 1
        fi
        echo "Lock released"
        ;;

    *)
        echo "Usage: prp-run-all-state.sh <create|update-step|set-var|set-review-fix-state|get-step|get-var|add-artifact|cleanup|exists|lock|unlock> [args]" >&2
        exit 1
        ;;
esac

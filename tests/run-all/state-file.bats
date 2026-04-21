#!/usr/bin/env bats
# Tests for prp-run-all-state.sh state management helper
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Install: brew install bats-core
# Run: bats tests/run-all/state-file.bats

HELPER="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/prp-run-all-state.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/.prp-output/state"
    cd "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─────────────────────────────────────────────
# 1. State file creation
# ─────────────────────────────────────────────
@test "create: generates state file with valid YAML frontmatter" {
    run bash "$HELPER" create "Add JWT authentication"
    [ "$status" -eq 0 ]
    [ -f ".prp-output/state/run-all.state.md" ]
}

@test "create: state file contains correct feature name" {
    bash "$HELPER" create "Add JWT authentication"
    run grep 'feature: "Add JWT authentication"' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
}

@test "create: state file starts at step 1" {
    bash "$HELPER" create "Test feature"
    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "create: state file includes custom ralph settings" {
    bash "$HELPER" create "Test feature" true 15 "critical,high,medium" true false
    run grep 'use_ralph: true' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep 'ralph_max_iter: 15' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep 'fix_severity: "critical,high,medium"' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
}

@test "create: state file initializes review loop state" {
    bash "$HELPER" create "Review loop state"
    run grep 'review_verdict: ""' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep 'review_cycle: 1' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
}

@test "create: state file initializes skipped review-fix state" {
    bash "$HELPER" create "Skipped state"
    run grep 'pending_skipped: false' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep 'all_skipped: false' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep 'skipped_count: 0' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────
# 2. Step update
# ─────────────────────────────────────────────
@test "update-step: increments step number in frontmatter" {
    bash "$HELPER" create "Test feature"
    bash "$HELPER" update-step 2 "Create Plan" "jwt-auth.plan.md"
    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "update-step: appends to completed steps table" {
    bash "$HELPER" create "Test feature"
    bash "$HELPER" update-step 2 "Create Plan" "jwt-auth.plan.md"
    run grep "Create Plan" .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
}

@test "update-step: fails if no state file" {
    run bash "$HELPER" update-step 2 "Create Plan" "result"
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────
# 3. Variable retrieval
# ─────────────────────────────────────────────
@test "get-var: retrieves feature name" {
    bash "$HELPER" create "My Feature"
    run bash "$HELPER" get-var feature
    [ "$status" -eq 0 ]
    [ "$output" = "My Feature" ]
}

@test "get-var: retrieves use_ralph" {
    bash "$HELPER" create "Test" true
    run bash "$HELPER" get-var use_ralph
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "get-var: retrieves skipped review-fix state" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get-var: retrieves present empty value" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" get-var review_verdict
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "get-var: returns legacy defaults for missing review state fields" {
    bash "$HELPER" create "Legacy state"
    sed -i '/^review_verdict:/d; /^review_cycle:/d; /^pending_skipped:/d; /^all_skipped:/d; /^skipped_count:/d' .prp-output/state/run-all.state.md

    run bash "$HELPER" get-var review_verdict
    [ "$status" -eq 0 ]
    [ "$output" = "" ]

    run bash "$HELPER" get-var review_cycle
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get-var: fails for missing variable" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" get-var nonexistent
    [ "$status" -eq 1 ]
}

@test "set-var: updates existing values and backfills missing keys" {
    bash "$HELPER" create "Test"
    bash "$HELPER" set-var review_verdict '"needs_manual_fix"'
    run bash "$HELPER" get-var review_verdict
    [ "$status" -eq 0 ]
    [ "$output" = "needs_manual_fix" ]

    sed -i '/^review_artifact:/d' .prp-output/state/run-all.state.md
    bash "$HELPER" set-var review_artifact '".prp-output/reviews/pr-1-review.md"'
    run bash "$HELPER" get-var review_artifact
    [ "$status" -eq 0 ]
    [ "$output" = ".prp-output/reviews/pr-1-review.md" ]
}

@test "set-review-fix-state: persists all-fixed skipped tuple" {
    bash "$HELPER" create "Test"
    bash "$HELPER" set-review-fix-state 0 3
    bash "$HELPER" set-review-fix-state 3 0

    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "set-review-fix-state: persists partial skipped tuple" {
    bash "$HELPER" create "Test"
    bash "$HELPER" set-review-fix-state 2 4

    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}

@test "set-review-fix-state: persists all-skipped tuple" {
    bash "$HELPER" create "Test"
    bash "$HELPER" set-review-fix-state 0 5

    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

# ─────────────────────────────────────────────
# 4. Artifact management
# ─────────────────────────────────────────────
@test "add-artifact: replaces '(none yet)' with first artifact" {
    bash "$HELPER" create "Test"
    bash "$HELPER" add-artifact "Plan: .prp-output/plans/test.plan.md"
    run grep "Plan: .prp-output/plans/test.plan.md" .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    # "(none yet)" should be gone
    run grep "(none yet)" .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────
# 5. Cleanup
# ─────────────────────────────────────────────
@test "cleanup: removes state and lock files" {
    bash "$HELPER" create "Test"
    echo "$$" > .prp-output/state/run-all.lock
    [ -f ".prp-output/state/run-all.state.md" ]
    [ -f ".prp-output/state/run-all.lock" ]
    bash "$HELPER" cleanup
    [ ! -f ".prp-output/state/run-all.state.md" ]
    [ ! -f ".prp-output/state/run-all.lock" ]
}

@test "cleanup: succeeds even if files don't exist" {
    run bash "$HELPER" cleanup
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────
# 6. Exists check
# ─────────────────────────────────────────────
@test "exists: returns 0 when state file exists" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" exists
    [ "$status" -eq 0 ]
}

@test "exists: returns 1 when state file missing" {
    run bash "$HELPER" exists
    [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────
# 7. Lock management
# ─────────────────────────────────────────────
@test "lock: creates lock file" {
    run bash "$HELPER" lock
    [ "$status" -eq 0 ]
    [ -f ".prp-output/state/run-all.lock" ]
}

@test "lock: fails if already locked (non-stale)" {
    bash "$HELPER" lock
    run bash "$HELPER" lock
    [ "$status" -eq 1 ]
    [[ "$output" == *"already locked"* ]]
}

@test "lock: removes stale lock (>2 hours old)" {
    mkdir -p .claude
    echo "12345" > .prp-output/state/run-all.lock
    # Touch with old timestamp (3 hours ago)
    touch -t "$(date -v-3H +%Y%m%d%H%M.%S 2>/dev/null || date -d '3 hours ago' +%Y%m%d%H%M.%S 2>/dev/null)" .prp-output/state/run-all.lock
    run bash "$HELPER" lock
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale"* ]]
}

@test "unlock: removes lock file" {
    bash "$HELPER" lock
    [ -f ".prp-output/state/run-all.lock" ]
    bash "$HELPER" unlock
    [ ! -f ".prp-output/state/run-all.lock" ]
}

# ─────────────────────────────────────────────
# 8. Invalid usage
# ─────────────────────────────────────────────
@test "unknown command: exits with error" {
    run bash "$HELPER" unknown_command
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

#!/usr/bin/env bats
# E2E tests for prp-run-all-state.sh — exercises the full workflow lifecycle
#
# Unlike tests/run-all/state-file.bats (unit tests for individual commands),
# these tests verify the state machine as an integrated sequence, mirroring
# how prp-run-all calls the helper across the 7-step workflow.
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/e2e/state-lifecycle.bats

HELPER="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/prp-run-all-state.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/.claude"
    cd "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─────────────────────────────────────────────
# 1. Full create → read lifecycle
# ─────────────────────────────────────────────
@test "lifecycle: create → get-step returns 1" {
    bash "$HELPER" create "Add payment integration"
    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "lifecycle: create → get-var reads feature name" {
    bash "$HELPER" create "Add payment integration"
    run bash "$HELPER" get-var feature
    [ "$status" -eq 0 ]
    [ "$output" = "Add payment integration" ]
}

# ─────────────────────────────────────────────
# 2. Multi-step update sequence
# ─────────────────────────────────────────────
@test "lifecycle: update steps 1→7 in sequence, final get-step = 7" {
    bash "$HELPER" create "Full workflow test"

    bash "$HELPER" update-step 2 "Create PRD"    "OK"
    bash "$HELPER" update-step 3 "Create Plan"   "OK"
    bash "$HELPER" update-step 4 "Implement"     "OK"
    bash "$HELPER" update-step 5 "Review"        "OK"
    bash "$HELPER" update-step 6 "Commit"        "OK"
    bash "$HELPER" update-step 7 "Create PR"     "OK"

    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]
}

@test "lifecycle: add-artifact stores artifact path in state file" {
    bash "$HELPER" create "Feature with artifact"
    bash "$HELPER" add-artifact "Plan: .prp-output/plans/feature-20260301-1200.plan.md"

    run grep "feature-20260301-1200.plan.md" .claude/prp-run-all.state.md
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────
# 3. Resume: state persists across invocations
# ─────────────────────────────────────────────
@test "lifecycle: resume reads correct step after partial progress" {
    bash "$HELPER" create "Resume test"
    bash "$HELPER" update-step 2 "Create PRD" "OK"
    bash "$HELPER" update-step 3 "Create Plan" "OK"

    # Simulate a new invocation reading state
    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

# ─────────────────────────────────────────────
# 4. Lock/unlock lifecycle
# ─────────────────────────────────────────────
@test "lifecycle: lock acquired then second lock attempt fails" {
    bash "$HELPER" create "Lock test"
    bash "$HELPER" lock

    # Fake the lock age to be fresh (just acquired — within 7200s)
    run bash "$HELPER" lock
    [ "$status" -eq 1 ]
    [[ "$output" == *"already locked"* ]]
}

@test "lifecycle: stale lock (old mtime) is cleared and new lock acquired" {
    bash "$HELPER" create "Stale lock test"
    # Create lock file manually with old timestamp (2024-01-01 = >7200s ago)
    echo "99999" > .claude/prp-run-all.lock
    touch -t 202401010000 .claude/prp-run-all.lock

    run bash "$HELPER" lock
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale"* ]] || [[ "$output" == *"Lock acquired"* ]]
    [ -f ".claude/prp-run-all.lock" ]
    # Lock should now contain current PID, not the stale 99999
    LOCK_PID=$(cat .claude/prp-run-all.lock)
    [ "$LOCK_PID" != "99999" ]
}

# ─────────────────────────────────────────────
# 5. Cleanup
# ─────────────────────────────────────────────
@test "lifecycle: cleanup removes state file and lock file" {
    bash "$HELPER" create "Cleanup test"
    bash "$HELPER" lock

    [ -f ".claude/prp-run-all.state.md" ]
    [ -f ".claude/prp-run-all.lock" ]

    bash "$HELPER" cleanup

    [ ! -f ".claude/prp-run-all.state.md" ]
    [ ! -f ".claude/prp-run-all.lock" ]
}

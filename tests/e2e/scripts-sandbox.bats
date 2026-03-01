#!/usr/bin/env bats
# E2E tests for cleanup-artifacts.sh — exercises the script with real files
#
# Uses touch -t to fake old modification times and pipes stdin to handle
# the interactive confirmation prompt (y/N).
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/e2e/scripts-sandbox.bats

CLEANUP_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/cleanup-artifacts.sh"

setup() {
    PROJECT_DIR="$(mktemp -d)"
    mkdir -p "$PROJECT_DIR/.prp-output"/{prds/drafts,plans,reports,reviews,debug,issues}
    cd "$PROJECT_DIR"
}

teardown() {
    rm -rf "$PROJECT_DIR"
}

# Helper: create an old artifact (mtime set to Jan 1, 2024 — well over 365 days ago)
create_old_artifact() {
    local path="$1"
    touch "$path"
    touch -t 202401010000 "$path"
}

# ─────────────────────────────────────────────
# 1. File detection
# ─────────────────────────────────────────────
@test "cleanup finds .md files older than threshold" {
    create_old_artifact ".prp-output/prds/drafts/old-prd-20240101-1200.md"

    # Pass "n" to skip deletion — just verify detection output
    run bash -c "echo 'n' | bash '$CLEANUP_SCRIPT' 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"old-prd-20240101-1200.md"* ]]
}

@test "cleanup preserves .md files newer than threshold" {
    # Create a fresh file (current mtime)
    touch ".prp-output/plans/new-plan-$(date +%Y%m%d)-1200.md"

    # Use 1-day threshold — fresh file should NOT appear in deletion list
    run bash -c "echo 'n' | bash '$CLEANUP_SCRIPT' 1"
    [ "$status" -eq 0 ]
    # Fresh file should not be listed for deletion
    ! [[ "$output" == *"DELETE: new-plan"* ]]
}

# ─────────────────────────────────────────────
# 2. Deletion behaviour
# ─────────────────────────────────────────────
@test "cleanup with 'y' input deletes old files" {
    create_old_artifact ".prp-output/reports/old-report-20240101.md"

    bash -c "echo 'y' | bash '$CLEANUP_SCRIPT' 1" >/dev/null 2>&1

    [ ! -f ".prp-output/reports/old-report-20240101.md" ]
}

@test "cleanup with 'n' input preserves old files" {
    create_old_artifact ".prp-output/reviews/old-review-20240101.md"

    bash -c "echo 'n' | bash '$CLEANUP_SCRIPT' 1" >/dev/null 2>&1

    [ -f ".prp-output/reviews/old-review-20240101.md" ]
}

# ─────────────────────────────────────────────
# 3. Error handling
# ─────────────────────────────────────────────
@test "cleanup exits with error when .prp-output not found" {
    # Move to a dir with no .prp-output
    EMPTY_DIR="$(mktemp -d)"
    cd "$EMPTY_DIR"
    run bash "$CLEANUP_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
    rm -rf "$EMPTY_DIR"
}

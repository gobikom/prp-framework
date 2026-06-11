#!/usr/bin/env bats
# Tests for scripts/verify-review-artifact.sh (agent-devops#534)

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/verify-review-artifact.sh"
    TMPDIR_GATE=$(mktemp -d)
    REVIEWS="$TMPDIR_GATE/.prp-output/reviews"
    mkdir -p "$REVIEWS"
    cd "$TMPDIR_GATE"
}

teardown() {
    rm -rf "$TMPDIR_GATE"
}

_write_artifact() { # path content
    printf '%s\n' "$2" > "$1"
}

@test "missing artifact exits 1" {
    run bash "$SCRIPT" 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]]
}

@test "zero-issues agents artifact passes with tier=agents" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "## Verdict
0 critical / 0 high / 0 medium / 0 suggestion — APPROVE"
    run bash "$SCRIPT" 42 --require-tier agents
    [ "$status" -eq 0 ]
    [[ "$output" == *"GATE PASS"* ]]
    [[ "$output" == *"tier=agents"* ]]
}

@test "single-agent artifact fails when agents tier required (exit 3)" {
    _write_artifact "$REVIEWS/pr-42-review-claude-code.md" "0 critical / 0 high / 0 medium — READY TO MERGE"
    run bash "$SCRIPT" 42 --require-tier agents
    [ "$status" -eq 3 ]
    [[ "$output" == *"tier"* ]]
}

@test "single-agent artifact passes when any tier allowed" {
    _write_artifact "$REVIEWS/pr-42-review-claude-code.md" "Verdict: READY TO MERGE — 0 critical / 0 high / 0 medium"
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
}

@test "NEEDS FIXES verdict fails (exit 4)" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "## Verdict
NEEDS FIXES — 2 critical remaining"
    run bash "$SCRIPT" 42
    [ "$status" -eq 4 ]
}

@test "fix-loop history: later READY TO MERGE supersedes earlier NEEDS FIXES" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "Round 1: NEEDS FIXES (2 critical)
Round 2 fixes applied.
## Final Verdict
READY TO MERGE — 0 critical / 0 high / 0 medium / 0 suggestion"
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
}

@test "stale artifact rejected with --since (exit 2)" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "0 critical / 0 high / 0 medium — APPROVE"
    touch -d '2020-01-01' "$REVIEWS/pr-42-agents-review.md"
    run bash "$SCRIPT" 42 --since "$(date +%s)"
    [ "$status" -eq 2 ]
    [[ "$output" == *"stale"* ]]
}

@test "fresh artifact accepted with --since" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "0 critical / 0 high / 0 medium — APPROVE"
    run bash "$SCRIPT" 42 --since "$(( $(date +%s) - 60 ))"
    [ "$status" -eq 0 ]
}

@test "non-numeric pr number exits 5" {
    run bash "$SCRIPT" "abc"
    [ "$status" -eq 5 ]
}

@test "historical zero-count line cannot whitewash a later NEEDS FIXES (exit 4)" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "## Round 1
Summary: 0 critical / 0 high / 0 medium — initial pass clean.

## Final Verdict
NEEDS FIXES — 1 critical regression introduced"
    run bash "$SCRIPT" 42
    [ "$status" -eq 4 ]
    [[ "$output" == *"GATE FAIL"* ]]
}

@test "remaining suggestions block the gate (exit 4)" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "## Verdict
0 critical / 0 high / 0 medium / 5 suggestion"
    run bash "$SCRIPT" 42
    [ "$status" -eq 4 ]
}

@test "re-verify: newer single-agent artifact wins over stale agents artifact when any tier allowed" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "NEEDS FIXES — 2 critical"
    touch -d '2024-01-01' "$REVIEWS/pr-42-agents-review.md"
    _write_artifact "$REVIEWS/pr-42-review-claude-code.md" "Re-verify: READY TO MERGE — 0 critical / 0 high / 0 medium / 0 suggestion"
    run bash "$SCRIPT" 42 --since "$(( $(date +%s) - 60 ))"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr-42-review-claude-code.md"* ]]
    [[ "$output" == *"tier=single"* ]]
}

@test "fix-outcome appendix with skipped-issue prose does not false-fail a READY verdict" {
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "**Verdict**: READY TO MERGE — 0 critical / 0 high / 0 medium / 0 suggestion

---

## Fix Outcome
### Skipped Issues
- src/auth.ts:45 — 1 critical: requires architectural review"
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
}

@test "agents artifact preferred over single when both exist" {
    _write_artifact "$REVIEWS/pr-42-review-claude-code.md" "NEEDS FIXES — 1 critical"
    _write_artifact "$REVIEWS/pr-42-agents-review.md" "0 critical / 0 high / 0 medium / 0 suggestion — APPROVE"
    run bash "$SCRIPT" 42 --require-tier agents
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr-42-agents-review.md"* ]]
}

#!/usr/bin/env bats
# Tests for prp-ralph-stop.sh stop hook
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Install: brew install bats-core
# Run: bats tests/ralph/ralph-stop.bats

HOOK="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/adapters/claude-code-hooks/prp-ralph-stop.sh"
FIXTURES="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures"

setup() {
    # Each test gets an isolated temp directory
    TEST_DIR="$(mktemp -d)"
    mkdir -p "$TEST_DIR/.claude"

    # Run hook from inside the temp dir (state file path is relative to CWD)
    cd "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─────────────────────────────────────────────
# Helper: create a valid state file
# ─────────────────────────────────────────────
create_state_file() {
    local iteration="${1:-1}"
    local max_iterations="${2:-20}"
    local plan_path="${3:-.prp-output/plans/feature.plan.md}"

    cat > ".claude/prp-ralph.state.md" <<EOF
---
iteration: $iteration
max_iterations: $max_iterations
plan_path: "$plan_path"
started_at: "2026-02-27T14:00:00Z"
---

# PRP Ralph Loop State

## Progress Log
EOF
}

# ─────────────────────────────────────────────
# Helper: build hook input JSON
# ─────────────────────────────────────────────
hook_input() {
    local transcript="$1"
    echo "{\"transcript_path\": \"$transcript\"}"
}

# ─────────────────────────────────────────────
# 1. No state file → allow exit (exit 0, no JSON)
# ─────────────────────────────────────────────
@test "no state file: allows exit with code 0" {
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-complete.jsonl")"
    [ "$status" -eq 0 ]
}

@test "no state file: outputs nothing (no block decision)" {
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-complete.jsonl")"
    [ -z "$output" ]
}

# ─────────────────────────────────────────────
# 2. COMPLETE promise found → allow exit, delete state
# ─────────────────────────────────────────────
@test "complete promise on own line: allows exit" {
    create_state_file 3 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-complete.jsonl")"
    [ "$status" -eq 0 ]
}

@test "complete promise on own line: removes state file" {
    create_state_file 3 20
    bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-complete.jsonl")"
    [ ! -f ".claude/prp-ralph.state.md" ]
}

@test "complete promise on own line: does not block" {
    create_state_file 3 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-complete.jsonl")"
    # Should not output a block decision
    echo "$output" | grep -qv '"decision": "block"' || true
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────
# 3. No COMPLETE promise → block, increment iteration
# ─────────────────────────────────────────────
@test "no complete: returns block decision" {
    create_state_file 1 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    echo "$output" | grep -q '"decision": "block"'
}

@test "no complete: increments iteration in state file" {
    create_state_file 1 20
    bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    grep -q "^iteration: 2$" ".claude/prp-ralph.state.md"
}

@test "no complete: state file still exists" {
    create_state_file 1 20
    bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    [ -f ".claude/prp-ralph.state.md" ]
}

@test "no complete: block reason contains plan path" {
    create_state_file 1 20 ".prp-output/plans/my-feature.plan.md"
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    echo "$output" | grep -q "my-feature.plan.md"
}

# ─────────────────────────────────────────────
# 4. Max iterations reached → allow exit, delete state
# ─────────────────────────────────────────────
@test "max iterations reached: allows exit" {
    create_state_file 20 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    [ "$status" -eq 0 ]
}

@test "max iterations reached: removes state file" {
    create_state_file 20 20
    bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    [ ! -f ".claude/prp-ralph.state.md" ]
}

@test "max iterations reached: iteration equals max" {
    create_state_file 5 5
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    [ "$status" -eq 0 ]
    [ ! -f ".claude/prp-ralph.state.md" ]
}

# ─────────────────────────────────────────────
# 5. False positive: COMPLETE inside code block (indented)
# ─────────────────────────────────────────────
@test "indented promise in code block: does not trigger completion" {
    create_state_file 1 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-false-positive.jsonl")"
    # Should block (not complete) because promise is indented
    echo "$output" | grep -q '"decision": "block"'
}

@test "indented promise: state file still exists" {
    create_state_file 1 20
    bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-false-positive.jsonl")"
    [ -f ".claude/prp-ralph.state.md" ]
}

# ─────────────────────────────────────────────
# 6. Corrupt state file → allow exit, delete state
# ─────────────────────────────────────────────
@test "corrupt state - invalid iteration: allows exit" {
    cat > ".claude/prp-ralph.state.md" <<EOF
---
iteration: not-a-number
max_iterations: 20
plan_path: "test.plan.md"
---
EOF
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    [ "$status" -eq 0 ]
}

@test "corrupt state - invalid iteration: removes state file" {
    cat > ".claude/prp-ralph.state.md" <<EOF
---
iteration: not-a-number
max_iterations: 20
plan_path: "test.plan.md"
---
EOF
    bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    [ ! -f ".claude/prp-ralph.state.md" ]
}

@test "corrupt state - missing iteration: allows exit" {
    cat > ".claude/prp-ralph.state.md" <<EOF
---
max_iterations: 20
plan_path: "test.plan.md"
---
EOF
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────
# 7. Transcript not found → allow exit, delete state
# ─────────────────────────────────────────────
@test "transcript not found: allows exit" {
    create_state_file 1 20
    run bash "$HOOK" <<< '{"transcript_path": "/tmp/nonexistent-transcript-12345.jsonl"}'
    [ "$status" -eq 0 ]
}

@test "transcript not found: removes state file" {
    create_state_file 1 20
    bash "$HOOK" <<< '{"transcript_path": "/tmp/nonexistent-transcript-12345.jsonl"}'
    [ ! -f ".claude/prp-ralph.state.md" ]
}

# ─────────────────────────────────────────────
# 8. No assistant message in transcript → treat as no COMPLETE
# ─────────────────────────────────────────────
@test "no assistant message: blocks (continues loop)" {
    create_state_file 1 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-empty.jsonl")"
    echo "$output" | grep -q '"decision": "block"'
}

# ─────────────────────────────────────────────
# 9. Block output format validation
# ─────────────────────────────────────────────
@test "block output is valid JSON" {
    create_state_file 1 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    echo "$output" | jq . > /dev/null
}

@test "block output contains systemMessage field" {
    create_state_file 1 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    echo "$output" | jq -e '.systemMessage' > /dev/null
}

@test "block output contains reason field" {
    create_state_file 1 20
    run bash "$HOOK" <<< "$(hook_input "$FIXTURES/transcript-incomplete.jsonl")"
    echo "$output" | jq -e '.reason' > /dev/null
}

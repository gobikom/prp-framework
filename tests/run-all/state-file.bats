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

@test "create: escapes quoted string fields in YAML frontmatter" {
    bash "$HELPER" create 'Feature "quoted" \ path' false 10 'critical,high\medium'

    run grep -F 'feature: "Feature \"quoted\" \\ path"' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep -F 'fix_severity: "critical,high\\medium"' .prp-output/state/run-all.state.md
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
    run grep 'all_skipped_rounds: 0' .prp-output/state/run-all.state.md
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

@test "get-step: fails when no state file exists" {
    # No create — state file does not exist.
    run bash "$HELPER" get-step
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot read step"* ]]
}

@test "get-step: surfaces malformed-frontmatter distinctly from missing-key" {
    # Regression: get-step used to conflate exit code 2 (malformed frontmatter)
    # with exit code 1 (missing key), hiding corruption behind a generic error.
    bash "$HELPER" create "Test"
    # Strip the closing --- so get_frontmatter_value exits with code 2.
    awk '$0 == "---" { markers++; if (markers == 2) next } { print }' \
        .prp-output/state/run-all.state.md > state.tmp
    mv state.tmp .prp-output/state/run-all.state.md

    run bash "$HELPER" get-step
    [ "$status" -eq 1 ]
    [[ "$output" == *"frontmatter is malformed"* ]]
}

@test "update-step: rolls back on set_frontmatter_value failure via PRP_STATE_FAIL_KEY" {
    # Mirrors the set-review-fix-state mid-write coverage: forcing a
    # frontmatter write failure must leave the state file unmutated.
    bash "$HELPER" create "Test"
    before="$(cat .prp-output/state/run-all.state.md)"

    run env PRP_STATE_FAIL_KEY=step bash "$HELPER" update-step 2 "Plan" "OK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"rolled back"* ]]

    after="$(cat .prp-output/state/run-all.state.md)"
    [ "$after" = "$before" ]

    # get-step still reports the original value — no partial frontmatter write.
    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
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
    sed -i '/^review_verdict:/d; /^review_cycle:/d; /^pending_skipped:/d; /^all_skipped:/d; /^skipped_count:/d; /^all_skipped_rounds:/d' .prp-output/state/run-all.state.md

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

    run bash "$HELPER" get-var all_skipped_rounds
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

@test "set-var: preserves sed metacharacters in values" {
    bash "$HELPER" create "Test"
    bash "$HELPER" set-var review_artifact '"a&b|c"'

    run bash "$HELPER" get-var review_artifact
    [ "$status" -eq 0 ]
    [ "$output" = "a&b|c" ]
}

@test "set-var: rejects invalid variable names" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" set-var 'review_.*' '"bad"'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid variable name"* ]]

    run bash "$HELPER" get-var review_verdict
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "set-var: rejects missing value" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" set-var review_cycle
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]

    run bash "$HELPER" get-var review_cycle
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "set-var: fails closed when state file cannot be written" {
    bash "$HELPER" create "Test"
    mkdir .prp-output/state/run-all.state.md.tmp
    run bash "$HELPER" set-var review_cycle 2
    rmdir .prp-output/state/run-all.state.md.tmp

    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot update variable"* ]]

    run bash "$HELPER" get-var review_cycle
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "set-var: fails closed when frontmatter closing marker is missing" {
    bash "$HELPER" create "Test"
    sed -i '1d' .prp-output/state/run-all.state.md

    run bash "$HELPER" set-var review_cycle 2
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot update variable"* ]]

    run grep '^review_cycle: 2' .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

@test "get-var: fails closed when frontmatter closing marker is missing" {
    bash "$HELPER" create "Test"
    awk '$0 == "---" { markers++; if (markers == 2) next } { print }' .prp-output/state/run-all.state.md > state.tmp
    mv state.tmp .prp-output/state/run-all.state.md

    run bash "$HELPER" get-var review_cycle
    [ "$status" -eq 1 ]
    [[ "$output" == *"frontmatter is malformed"* ]]
}

@test "get-var: does not emit stale value when closing marker is missing" {
    # Malformed state files must never leak a matched value on stdout —
    # callers use command substitution and would treat a printed value as
    # truth. The error path must be empty-stdout, nonzero-exit.
    bash "$HELPER" create "Test"
    awk '$0 == "---" { markers++; if (markers == 2) next } { print }' .prp-output/state/run-all.state.md > state.tmp
    mv state.tmp .prp-output/state/run-all.state.md

    run bash "$HELPER" get-var feature
    [ "$status" -eq 1 ]
    # stderr message is fine, but no matched value may appear on stdout.
    [[ "$output" != *"Test"* ]]
}

@test "get-var: fails closed when opening marker is missing" {
    bash "$HELPER" create "Test"
    # Strip the first frontmatter delimiter — marker count never reaches 1.
    sed -i '1d' .prp-output/state/run-all.state.md

    run bash "$HELPER" get-var review_cycle
    [ "$status" -eq 1 ]
    [[ "$output" == *"frontmatter is malformed"* ]]
}

@test "set-var: preserves literal backslash-n — awk -v would decode it to newline without ENVIRON" {
    bash "$HELPER" create "Test"
    bash "$HELPER" set-var review_verdict '"0_issues"\nskip_review: true'

    run bash "$HELPER" get-var review_verdict
    [ "$status" -eq 0 ]
    [ "$output" = '0_issues"\nskip_review: true' ]

    run grep '^skip_review: false' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep '^skip_review: true' .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

@test "set-var: preserves literal backslash-t without decoding to tab" {
    # Awk's -v flag decodes C-style escapes — this helper must pass values
    # through ENVIRON instead. Proves the same safety for \t, not just \n.
    bash "$HELPER" create "Test"
    bash "$HELPER" set-var review_verdict '"0_issues"\tskip_review: true'

    run bash "$HELPER" get-var review_verdict
    [ "$status" -eq 0 ]
    [ "$output" = '0_issues"\tskip_review: true' ]

    # No real tab character should have been written to disk.
    run grep -P '\t' .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

@test "set-var: preserves literal backslash-backslash-n" {
    bash "$HELPER" create "Test"
    bash "$HELPER" set-var review_verdict '"0_issues"\\nskip_review: true'

    run bash "$HELPER" get-var review_verdict
    [ "$status" -eq 0 ]
    [ "$output" = '0_issues"\\nskip_review: true' ]
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
    run bash "$HELPER" get-var all_skipped_rounds
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
    run bash "$HELPER" get-var all_skipped_rounds
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
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
    run bash "$HELPER" get-var all_skipped_rounds
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "set-review-fix-state: increments consecutive all-skipped rounds" {
    bash "$HELPER" create "Test"
    bash "$HELPER" set-review-fix-state 0 2
    bash "$HELPER" set-review-fix-state 0 3

    run bash "$HELPER" get-var all_skipped_rounds
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "set-review-fix-state: backfills skipped keys for legacy state files" {
    bash "$HELPER" create "Legacy state"
    sed -i '/^pending_skipped:/d; /^all_skipped:/d; /^skipped_count:/d; /^all_skipped_rounds:/d' .prp-output/state/run-all.state.md
    bash "$HELPER" set-review-fix-state 0 2

    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
    run bash "$HELPER" get-var all_skipped_rounds
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "set-review-fix-state: persisted skipped tuple is written to disk and survives fresh reads" {
    bash "$HELPER" create "Persistence regression"
    bash "$HELPER" set-review-fix-state 0 4

    # Inspect the raw state file directly — proves the helper writes to disk,
    # not just to in-process state.
    run grep -E '^pending_skipped: true' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep -E '^all_skipped: true' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep -E '^skipped_count: 4' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep -E '^all_skipped_rounds: 1' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]

    # Each get-var is a fresh bash process; non-default values must round-trip.
    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
    run bash "$HELPER" get-var all_skipped_rounds
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "set-review-fix-state: persisted skipped tuple survives interleaved update-step calls" {
    bash "$HELPER" create "Interleave regression"
    bash "$HELPER" set-review-fix-state 1 5

    # update-step writes step + updated_at — it must NOT clobber the skipped tuple.
    bash "$HELPER" update-step 6 "Review Fix" "partial"
    bash "$HELPER" update-step 7 "Re-review" "OK"

    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "set-review-fix-state: rejects invalid counts" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" set-review-fix-state -1 2
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-negative integers"* ]]

    run bash "$HELPER" set-review-fix-state 1 abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-negative integers"* ]]
}

@test "set-review-fix-state: fails closed when state file cannot be written" {
    bash "$HELPER" create "Test"
    mkdir .prp-output/state/run-all.state.md.tmp
    run bash "$HELPER" set-review-fix-state 0 2
    rmdir .prp-output/state/run-all.state.md.tmp

    [ "$status" -eq 1 ]
    # Accept either the atomic-rollback message (new) or the original
    # tmp-file write error (if a tuple key write fails before rollback).
    [[ "$output" == *"Cannot update variable"* ]] || \
        [[ "$output" == *"rolled back"* ]] || \
        [[ "$output" == *"Cannot snapshot"* ]]

    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "set-review-fix-state: rolls back partial tuple updates on mid-write failure" {
    bash "$HELPER" create "Test"
    before="$(cat .prp-output/state/run-all.state.md)"

    run env PRP_STATE_FAIL_KEY=skipped_count bash "$HELPER" set-review-fix-state 2 4
    [ "$status" -eq 1 ]
    [[ "$output" == *"rolled back"* ]]

    after="$(cat .prp-output/state/run-all.state.md)"
    [ "$after" = "$before" ]
}

@test "set-review-fix-state: rolls back when first tuple key fails" {
    bash "$HELPER" create "Test"
    before="$(cat .prp-output/state/run-all.state.md)"

    run env PRP_STATE_FAIL_KEY=pending_skipped bash "$HELPER" set-review-fix-state 2 4
    [ "$status" -eq 1 ]
    [[ "$output" == *"rolled back"* ]]

    after="$(cat .prp-output/state/run-all.state.md)"
    [ "$after" = "$before" ]
}

@test "set-review-fix-state: rolls back when second tuple key fails" {
    bash "$HELPER" create "Test"
    before="$(cat .prp-output/state/run-all.state.md)"

    run env PRP_STATE_FAIL_KEY=all_skipped bash "$HELPER" set-review-fix-state 2 4
    [ "$status" -eq 1 ]
    [[ "$output" == *"rolled back"* ]]

    after="$(cat .prp-output/state/run-all.state.md)"
    [ "$after" = "$before" ]
}

@test "set-review-fix-state: rolls back when last tuple key fails" {
    bash "$HELPER" create "Test"
    before="$(cat .prp-output/state/run-all.state.md)"

    run env PRP_STATE_FAIL_KEY=all_skipped_rounds bash "$HELPER" set-review-fix-state 0 3
    [ "$status" -eq 1 ]
    [[ "$output" == *"rolled back"* ]]

    after="$(cat .prp-output/state/run-all.state.md)"
    [ "$after" = "$before" ]
}

@test "set-review-fix-state: rolls back when updated_at fails after tuple" {
    bash "$HELPER" create "Test"
    before="$(cat .prp-output/state/run-all.state.md)"

    # updated_at is the final write after all tuple keys succeed —
    # guards the "almost done" failure window.
    run env PRP_STATE_FAIL_KEY=updated_at bash "$HELPER" set-review-fix-state 2 4
    [ "$status" -eq 1 ]
    [[ "$output" == *"rolled back"* ]]

    after="$(cat .prp-output/state/run-all.state.md)"
    [ "$after" = "$before" ]
}

@test "set-review-fix-state: fails closed when state file is missing" {
    # No create — state file does not exist.
    run bash "$HELPER" set-review-fix-state 0 3
    [ "$status" -eq 1 ]
    [[ "$output" == *"State file not found"* ]]
}

@test "set-review-fix-state: partial-fix after all-skipped round resets all_skipped_rounds" {
    bash "$HELPER" create "Reset regression"
    bash "$HELPER" set-review-fix-state 0 3
    run bash "$HELPER" get-var all_skipped_rounds
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    # Partial-fix must reset the consecutive-all-skipped counter.
    bash "$HELPER" set-review-fix-state 2 1

    run bash "$HELPER" get-var all_skipped_rounds
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "set-review-fix-state: 0 fixed and 0 skipped clears the full skipped tuple" {
    bash "$HELPER" create "Zero-zero"
    bash "$HELPER" set-review-fix-state 0 3
    bash "$HELPER" set-review-fix-state 0 0

    run bash "$HELPER" get-var pending_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var all_skipped
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
    run bash "$HELPER" get-var skipped_count
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    run bash "$HELPER" get-var all_skipped_rounds
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "set-var: rejects newline in value (YAML injection guard)" {
    bash "$HELPER" create "Injection test"
    run bash "$HELPER" set-var review_verdict $'"0_issues"\nauto_merge: true'
    [ "$status" -eq 1 ]

    # The injected key must NOT have been written.
    run bash "$HELPER" get-var auto_merge
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "set-var: rejects CR in value (YAML injection guard)" {
    bash "$HELPER" create "Injection test"
    run bash "$HELPER" set-var review_verdict $'"0_issues"\rauto_merge: true'
    [ "$status" -eq 1 ]

    run bash "$HELPER" get-var auto_merge
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "set-var: rejects bare --- value (YAML frontmatter close)" {
    bash "$HELPER" create "Injection test"
    run bash "$HELPER" set-var review_verdict "---"
    [ "$status" -eq 1 ]
}

@test "create: rejects newline in feature name (YAML injection guard)" {
    run bash "$HELPER" create $'Benign\nauto_merge: true\nskip_review: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
    [ ! -f ".prp-output/state/run-all.state.md" ]
}

@test "create: rejects CR in feature name (YAML injection guard)" {
    run bash "$HELPER" create $'Benign\rauto_merge: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
    [ ! -f ".prp-output/state/run-all.state.md" ]
}

@test "create: rejects invalid scalar arguments" {
    run bash "$HELPER" create "Test" $'true\nskip_review: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid create argument"* ]]

    run bash "$HELPER" create "Test" true $'10\nskip_review: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid create argument"* ]]

    run bash "$HELPER" create "Test" true 10 "critical,high" $'false\nno_pr: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid create argument"* ]]
}

@test "create: rejects newline in fix_severity (YAML injection guard)" {
    run bash "$HELPER" create "Feature" false 10 $'critical,high\nauto_merge: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
    [ ! -f ".prp-output/state/run-all.state.md" ]
}

@test "create: rejects CR in fix_severity (YAML injection guard)" {
    run bash "$HELPER" create "Feature" false 10 $'critical,high\rauto_merge: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
    [ ! -f ".prp-output/state/run-all.state.md" ]
}

@test "create: rejects bare --- line in fix_severity (YAML frontmatter close)" {
    run bash "$HELPER" create "Feature" false 10 "---"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
    [ ! -f ".prp-output/state/run-all.state.md" ]
}

@test "update-step: rejects newline in step name (YAML injection guard)" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" update-step 2 $'Create Plan\nauto_merge: true' "OK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]

    # Frontmatter must not have been mutated.
    run bash "$HELPER" get-var auto_merge
    [ "$status" -eq 1 ]
}

@test "update-step: rejects CR in step name (YAML injection guard)" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" update-step 2 $'Create Plan\rauto_merge: true' "OK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
}

@test "update-step: rejects newline in result field (YAML injection guard)" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" update-step 2 "Plan" $'OK\nauto_merge: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]

    run bash "$HELPER" get-var auto_merge
    [ "$status" -eq 1 ]
}

@test "update-step: rejects CR in result field (YAML injection guard)" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" update-step 2 "Plan" $'OK\rauto_merge: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
}

@test "update-step: rejects bare --- in result (YAML frontmatter close)" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" update-step 2 "Plan" "---"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
}

@test "update-step: rejects non-numeric step number" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" update-step "not_a_number" "Plan" "OK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-negative integer"* ]]
}

@test "update-step: fails closed when artifacts section is missing" {
    bash "$HELPER" create "Test"
    sed -i '/^## Artifacts$/d' .prp-output/state/run-all.state.md

    run bash "$HELPER" update-step 2 "Create Plan" "OK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing required section '## Artifacts'"* ]]

    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run grep "Create Plan" .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

@test "update-step: fails closed when completed steps section is missing" {
    bash "$HELPER" create "Test"
    sed -i '/^## Completed Steps$/d' .prp-output/state/run-all.state.md

    run bash "$HELPER" update-step 2 "Create Plan" "OK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing required section '## Completed Steps'"* ]]

    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run grep "Create Plan" .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

@test "update-step: fails closed when table header row is missing" {
    # '## Completed Steps' alone is insufficient — the table header row
    # must also exist so the completed-step insert lands in a valid table.
    bash "$HELPER" create "Test"
    sed -i '/^|------|------|--------|-----------|$/d' .prp-output/state/run-all.state.md

    run bash "$HELPER" update-step 2 "Create Plan" "OK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing required section"* ]]

    # Frontmatter must not have mutated: step stays at 1, no new row added.
    run bash "$HELPER" get-step
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run grep "Create Plan" .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

@test "update-step: does not mutate frontmatter when a required body section is missing" {
    # Regression: the frontmatter write must happen AFTER the body sanity
    # checks. A leaked frontmatter mutation (step/updated_at) would show up
    # in the diff even though the body-level insert never ran.
    bash "$HELPER" create "Test"
    before="$(cat .prp-output/state/run-all.state.md)"
    sed -i '/^## Completed Steps$/d' .prp-output/state/run-all.state.md
    pre_mutation="$(cat .prp-output/state/run-all.state.md)"

    run bash "$HELPER" update-step 2 "Create Plan" "OK"
    [ "$status" -eq 1 ]

    after="$(cat .prp-output/state/run-all.state.md)"
    [ "$after" = "$pre_mutation" ]
}

@test "update-step: preserves literal backslash-n in completed step row" {
    bash "$HELPER" create "Test"
    bash "$HELPER" update-step 2 'Plan\n| 99 | Inject | OK | 00:00 |' "OK"

    run grep -F 'Plan\n| 99 | Inject | OK | 00:00 |' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep -F '| 99 | Inject | OK | 00:00 |' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    [ "$(grep -c '^| 99 | Inject | OK | 00:00 |$' .prp-output/state/run-all.state.md)" -eq 0 ]
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

@test "add-artifact: preserves sed replacement metacharacters" {
    bash "$HELPER" create "Test"
    bash "$HELPER" add-artifact 'Plan: a&b\c|d'

    run grep -F 'Plan: a&b\c|d' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run grep "(none yet)" .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

@test "add-artifact: appends artifact before error log" {
    bash "$HELPER" create "Test"
    bash "$HELPER" add-artifact "Plan: first"
    bash "$HELPER" add-artifact "Report: second"

    run grep -F "Report: second" .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
    run awk '
        /^- Report: second$/ { seen_artifact = 1 }
        /^## Error Log$/ { exit seen_artifact ? 0 : 1 }
        END { if (seen_artifact == 0) exit 1 }
    ' .prp-output/state/run-all.state.md
    [ "$status" -eq 0 ]
}

@test "add-artifact: rejects newline in artifact (YAML injection guard)" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" add-artifact $'path\nauto_merge: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
}

@test "add-artifact: rejects CR in artifact (YAML injection guard)" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" add-artifact $'path\rauto_merge: true'
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
}

@test "add-artifact: rejects bare --- artifact line (YAML frontmatter close)" {
    bash "$HELPER" create "Test"
    run bash "$HELPER" add-artifact "---"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid characters"* ]]
}

@test "add-artifact: fails closed when artifacts section is missing" {
    bash "$HELPER" create "Test"
    sed -i '/^## Artifacts$/d' .prp-output/state/run-all.state.md

    run bash "$HELPER" add-artifact "Plan: should not be added"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing required section '## Artifacts'"* ]]
    run grep -F "Plan: should not be added" .prp-output/state/run-all.state.md
    [ "$status" -ne 0 ]
}

@test "set-var: fails when state file is missing" {
    # No create — state file does not exist.
    run bash "$HELPER" set-var review_cycle 2
    [ "$status" -eq 1 ]
    [[ "$output" == *"State file not found"* ]]
}

@test "add-artifact: fails closed when error log section is missing" {
    bash "$HELPER" create "Test"
    bash "$HELPER" add-artifact "Plan: first"
    sed -i '/^## Error Log$/d' .prp-output/state/run-all.state.md

    run bash "$HELPER" add-artifact "Report: second"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing required section '## Error Log'"* ]]
    run grep -F "Report: second" .prp-output/state/run-all.state.md
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
    echo "12345" > .prp-output/state/run-all.lock
    # Use an absolute old timestamp — matches the e2e counterpart and avoids
    # a silent empty-string fallback if neither date dialect succeeds.
    touch -t 202401010000 .prp-output/state/run-all.lock
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

@test "lock: fails closed when lock file cannot be written" {
    # Block the lock path by creating a directory with the same name.
    # `echo "$$" > file` fails with "Is a directory".
    mkdir -p ".prp-output/state/run-all.lock"
    run bash "$HELPER" lock
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot write lock file"* ]]
    # The directory must remain — lock write failed, no silent replace.
    [ -d ".prp-output/state/run-all.lock" ]
    rmdir ".prp-output/state/run-all.lock"
}

# ─────────────────────────────────────────────
# 8. Invalid usage
# ─────────────────────────────────────────────
@test "unknown command: exits with error" {
    run bash "$HELPER" unknown_command
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

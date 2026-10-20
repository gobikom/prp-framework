#!/usr/bin/env bats
# Helper-level tests for scripts/review/prior-findings.py (prp-framework#178, P11).
# The command-level arms in tests/commands/l2-comments.bats run it through Step B/C.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
P="$REPO_ROOT/scripts/review/prior-findings.py"
HEAD=0123456789abcdef0123456789abcdef01234567
RUN=20260102T000000Z-00000000
PREV=20260101T000000Z-deadbeef
O1='{"category":"correctness","evidence":"b is None","family":"null-deref","file":"src/a.py","lines":[2,3],"severity":"important","summary":"NPE on None"}'

setup() { TEST_TMPDIR="$(mktemp -d)"; TSV="$TEST_TMPDIR/c.tsv"; : > "$TSV"; }
teardown() { rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

# a code-reviewer comment from run <1> carrying findings <2> (prior section <3>)
cbody() {
  printf 'Reviewed head: %s\nPasses run: code-reviewer\n\n### Critical Issues (0 found)\nNone.\n\n### Important Issues (0 found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\n### Prior findings\n%b\n\n```review-findings\n{"reviewed_head":"%s","pass":"code-reviewer","complete":true,"findings":%s}\n```\n\nReview-mode: full\n\nGenerated-by: prp-review-agents v9.9.9 run=%s pass=code-reviewer\n' \
    "$HEAD" "${3:-None.}" "$HEAD" "$2" "$1"
}

# a pre-#178 comment: provenance footer, no review-findings block
c143() {
  printf 'Reviewed head: %s\nPasses run: code-reviewer\n\n### Critical Issues (0 found)\nNone.\n\n### Important Issues (0 found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\nGenerated-by: prp-review-agents v9.9.9 run=%s pass=code-reviewer\n' \
    "$HEAD" "$1"
}

addc() { printf '%s\t%s\t%s\n' "$1" "$2" "$(printf '%s' "$3" | base64 -w0)" >> "$TSV"; }

@test "no previous round at all: None., exit 0" {
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full
  [ "$status" -eq 0 ]; [ "$output" = "None." ]
}

@test "P11: a comment without a fence → Not recorded in full, exit 2 in incremental" {
  addc 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "$(c143 "$PREV")"
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full
  [ "$status" -eq 0 ]
  [ "$output" = "Not recorded: the previous round has no review-findings block." ]
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" incremental
  [ "$status" -eq 2 ]
  [[ "$output" == *"no review-findings block"* ]]
  [[ "$output" == *"incremental run must be FULL"* ]]
}

@test "P11: a malformed block is unstructured: Not recorded in full, exit 2 in incremental" {
  printf 'Reviewed head: %s\nPasses run: code-reviewer\n\n```review-findings\n{"reviewed_head":\n```\n\nGenerated-by: prp-review-agents v9.9.9 run=%s pass=code-reviewer\n' \
    "$HEAD" "$PREV" > "$TEST_TMPDIR/bad.md"
  addc 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "$(cat "$TEST_TMPDIR/bad.md")"
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full
  [ "$status" -eq 0 ]; [ "$output" = "Not recorded: the previous round has no review-findings block." ]
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" incremental
  [ "$status" -eq 2 ]; [[ "$output" == *"malformed review-findings JSON"* ]]
}

@test "an edited previous comment is unstructured whatever it contains" {
  addc 2026-01-01T00:00:00Z 2026-01-02T00:00:00Z "$(cbody "$PREV" "[$O1]")"
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" incremental
  [ "$status" -eq 2 ]; [[ "$output" == *"edited after posting"* ]]
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full
  [ "$status" -eq 0 ]; [ "$output" = "Not recorded: the previous round has no review-findings block." ]
}

@test "a structured round yields id-annotated rows; a missing family yields the - id" {
  local nofam='{"category":"correctness","evidence":"x","file":"src/b.py","lines":[1,1],"severity":"critical","summary":"s"}'
  addc 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "$(cbody "$PREV" "[$O1,$nofam]")"
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full
  [ "$status" -eq 0 ]
  local id1; id1=$(printf '%s' "code-reviewer|src/a.py|2|3|null-deref|NPE on None" | sha256sum | cut -c1-12)
  [ "$output" = "$(printf '%s\t%s\t%s\t%s\t%s\t%s\n-\tsrc/b.py\t1\t1\tcritical\t-' "$id1" src/a.py 2 3 important null-deref)" ]
}

@test "--json prints the canonical carried objects" {
  addc 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "$(cbody "$PREV" "[$O1]")"
  local canon; canon=$(printf '%s' "$O1" | python3 -I -c 'import json,sys; print(json.dumps(json.loads(sys.stdin.read()), sort_keys=True, separators=(",",":")))')
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" incremental --json
  [ "$status" -eq 0 ]
  [ "$output" = "[$canon]" ]
}

@test "--json refuses a finding lacking file/lines — same validation as rows mode" {
  addc 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "$(cbody "$PREV" '[{"severity":"important"}]')"
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" incremental --json
  [ "$status" -eq 2 ]; [[ "$output" == *"lacks file, lines or severity"* ]]
}

@test "only medium or low findings → None." {
  local med='{"category":"correctness","evidence":"x","family":"f","file":"src/a.py","lines":[1,1],"severity":"medium","summary":"s"}'
  addc 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "$(cbody "$PREV" "[$med]")"
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full
  [ "$status" -eq 0 ]; [ "$output" = "None." ]
}

@test "selection: latest matching pass, skipping this run's own, other passes, and non-round comments" {
  addc 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "Review started: head=$HEAD run=$RUN
Generated-by: prp-review-agents v9.9.9 run=$RUN pass=start"          # a start comment: not a round
  addc 2026-01-01T01:00:00Z 2026-01-01T01:00:00Z "$(printf 'Reviewed head: %s\nPasses run: security-reviewer\n\nGenerated-by: prp-review-agents v9.9.9 run=%s pass=security-reviewer\n' "$HEAD" "$PREV")"
  addc 2026-01-01T02:00:00Z 2026-01-01T02:00:00Z "$(cbody 20260101T015959Z-aaaaaaaa "[$O1]")"
  local older; older='{"category":"correctness","evidence":"old","family":"stale","file":"src/z.py","lines":[7,8],"severity":"important","summary":"old one"}'
  addc 2026-01-01T03:00:00Z 2026-01-01T03:00:00Z "$(cbody "$PREV" "[$older]")"
  addc 2026-01-01T04:00:00Z 2026-01-01T04:00:00Z "$(cbody "$RUN" "[]")"   # this run's own comment: skipped
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full
  [ "$status" -eq 0 ]
  local id2; id2=$(printf '%s' "code-reviewer|src/z.py|7|8|stale|old one" | sha256sum | cut -c1-12)
  [ "$output" = "$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$id2" src/z.py 7 8 important stale)" ]
}

@test "usage and IO: bad args → 3, unreadable or malformed input → 2 or 3" {
  run python3 -I "$P"; [ "$status" -eq 3 ]
  run python3 -I "$P" a b c hourly; [ "$status" -eq 3 ]
  run python3 -I "$P" "$TEST_TMPDIR/nope.tsv" code-reviewer "$RUN" full; [ "$status" -eq 3 ]
  printf 'only\ttwo\n' >> "$TSV"
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full; [ "$status" -eq 2 ]
  printf '2026-01-01T00:00:00Z\t2026-01-01T00:00:00Z\t!!!not-base64!!!\n' >> "$TSV"
  run python3 -I "$P" "$TSV" code-reviewer "$RUN" full; [ "$status" -eq 2 ]
}

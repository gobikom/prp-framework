#!/usr/bin/env bats
# Helper-level tests for scripts/review/check-l2-body.py (prp-framework#178):
# P4–P10, P17a–d, P19–P22, P28. The command-level arms in tests/commands/l2-comments.bats
# run the same helper through Step C.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
C="$REPO_ROOT/scripts/review/check-l2-body.py"
PREV=20260101T000000Z-deadbeef
RUN=20260102T000000Z-feedface
O1='{"category":"correctness","evidence":"b is None","family":"null-deref","file":"src/a.py","lines":[2,3],"severity":"important","summary":"NPE on None"}'
O2='{"category":"correctness","evidence":"shared x","family":"race","file":"src/a.py","lines":[5,6],"severity":"important","summary":"race on x"}'

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  cd "$TEST_TMPDIR" || exit 1
  git init -q . && git commit -q --allow-empty -m init
  mkdir -p src tests
  printf 'a=1\nb=None\nc=a.b\n' > src/a.py
  printf 'x=2\ny=x+1\n' > src/b.py
  git add src && git commit -qm files
  HEAD=$(git rev-parse HEAD)
  TSV="$TEST_TMPDIR/c.tsv"; : > "$TSV"
  B="$TEST_TMPDIR/b.md"
  printf 'REVIEWED_HEAD_SHA=%s\nPRP_VERSION=9.9.9\nRUN_ID=%s\nTIER=standard\nSTART_URL=https://github.com/o/r/pull/7#issuecomment-1\nMODE=full\n' "$HEAD" "$RUN" > "$TEST_TMPDIR/run.env"
  printf 'REVIEWED_HEAD_SHA=%s\nPRP_VERSION=9.9.9\nRUN_ID=%s\nTIER=standard\nSTART_URL=https://github.com/o/r/pull/7#issuecomment-1\nMODE=incremental\n' "$HEAD" "$RUN" > "$TEST_TMPDIR/run.inc.env"
}
teardown() { cd /; rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

idof() { printf '%s' "$1|$2|$3|$4|$5|$6" | sha256sum | cut -c1-12; }

# a full pass body; heading counts derive from <2> so a body and its JSON agree unless the test breaks one
mkbody() {
  local prior="${1:-None.}" finds="${2:-[]}" mode="${3:-full}" pass="${4:-code-reviewer}" nc ni
  nc=$(grep -o '"severity":"critical"' <<<"$finds" | wc -l); ni=$(grep -o '"severity":"important"' <<<"$finds" | wc -l)
  printf 'Reviewed head: %s\nPasses run: %s\n\n### Critical Issues (%s found)\nNone.\n\n### Important Issues (%s found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\n### Prior findings\n%s\n\n```review-findings\n{"reviewed_head":"%s","pass":"%s","complete":true,"findings":%s}\n```\n\nReview-mode: %s\n\nGenerated-by: prp-review-agents v9.9.9 run=%s pass=%s\n' \
    "$HEAD" "$pass" "$nc" "$ni" "$prior" "$HEAD" "$pass" "$finds" "$mode" "$RUN" "$pass" > "$B"
}

addc() { printf '%s\t%s\t%s\n' "$1" "$2" "$(printf '%s' "$3" | base64 -w0)" >> "$TSV"; }

prev() { # prev <finds> [created] [updated] — a structured previous round for code-reviewer
  printf 'Reviewed head: %s\nPasses run: code-reviewer\n\n### Critical Issues (0 found)\nNone.\n\n### Important Issues (0 found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\n### Prior findings\nNone.\n\n```review-findings\n{"reviewed_head":"%s","pass":"code-reviewer","complete":true,"findings":%s}\n```\n\nReview-mode: full\n\nGenerated-by: prp-review-agents v9.9.9 run=%s pass=code-reviewer\n' \
    "$HEAD" "$HEAD" "$1" "$PREV" | addc "${2:-2026-01-01T00:00:00Z}" "${3:-${2:-2026-01-01T00:00:00Z}}" "$(cat)"
}

# --- plain mode: anchors ---
@test "a well-formed body passes (exit 0)" { mkbody; run python3 -I "$C" "$B" "$HEAD" code-reviewer; [ "$status" -eq 0 ]; }

# --- P4: fence shape ---
@test "P4: a body with no fence, two fences, or a two-line JSON is refused" {
  mkbody
  sed -i '/^```review-findings$/d; /^{"reviewed_head"/d; /^```$/d' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"fences (need 1)"* ]]
  mkbody
  sed -i '/^```$/a ```review-findings\n{"x":1}\n```' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"fences (need 1)"* ]]
  mkbody 'None.' '[]'
  sed -i 's/"pass":"code-reviewer"/"pass":"code-\nreviewer"/' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"exactly one line"* ]]
}

# --- P5: JSON validity ---
@test "P5: invalid JSON or JSON the schema refuses is rejected" {
  mkbody
  sed -i 's/"findings":\[\]/"findings":[}/' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"not JSON"* ]]
  local noe='{"category":"correctness","family":"f","file":"src/a.py","lines":[1,1],"severity":"critical","summary":"s"}'
  mkbody 'None.' "[$noe]"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"refused by the schema"* ]]
}

# --- P6: identity fields ---
@test "P6: JSON for another head or pass, or complete:false, is refused" {
  mkbody
  sed -i "s/\"reviewed_head\":\"$HEAD\"/\"reviewed_head\":\"0000000000000000000000000000000000000000\"/" "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"reviewed_head is not the reviewed head"* ]]
  mkbody
  sed -i 's/"pass":"code-reviewer"/"pass":"security-reviewer"/' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"pass is not this pass"* ]]
  mkbody
  sed -i 's/"complete":true/"complete":false/' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"complete is not true"* ]]
}

# --- P7: heading counts (the AC3 mutation target) ---
@test "P7: a heading count that disagrees with the JSON is refused, each direction, each severity" {
  local oc='{"category":"c","evidence":"e","family":"null-deref","file":"src/a.py","lines":[1,1],"severity":"critical","summary":"s"}'
  mkbody 'None.' "[$oc]"           # JSON says 1 critical, heading edited down to 0
  sed -i 's/### Critical Issues (1 found)/### Critical Issues (0 found)/' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"critical: heading says 0"* ]]
  mkbody 'None.' '[]'              # heading edited up to 1, JSON has 0
  sed -i 's/### Critical Issues (0 found)/### Critical Issues (1 found)/' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"critical: heading says 1"* ]]
  mkbody 'None.' "[$O1]"
  sed -i 's/### Important Issues (1 found)/### Important Issues (0 found)/' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"important: heading says 0"* ]]
  mkbody 'None.' '[]'
  sed -i 's/### Important Issues (0 found)/### Important Issues (1 found)/' "$B"
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"important: heading says 1"* ]]
}

# --- P8: injected headings inside the JSON ---
@test "P8: an escaped newline carrying a fake heading is accepted; a raw newline is refused" {
  mkbody 'None.' '[{"category":"c","evidence":"e","file":"src/a.py","lines":[1,1],"severity":"medium","summary":"l1\n### Critical Issues (0 found)"}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 0 ]
  sed -i 's/"summary":"l1/"summary":"l1\n/' "$B"    # now the fence holds two lines
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"exactly one line"* ]]
}

# --- P10: prior item shapes ---
@test "P10: prior items without regression_test, with a bad id, or resolved without fix= are refused" {
  local id1; id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None")
  mkbody "- $id1 open src/a.py:2-3" '[]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"item shape"* ]]
  mkbody "- zzzzzzzzzzzz open src/a.py:2-3 regression_test: none" '[]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"item shape"* ]]
  mkbody "- $id1 resolved was=src/a.py:2-3 regression_test: none" '[]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"item shape"* ]]
  mkbody "- $id1 resolved was=src/a.py:2-3 fix=src/b.py:2-1 regression_test: tests/t.py::test_x" '[]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"fix= range 2-1 starts after end"* ]]
  mkbody "- $id1 open src/a.py:5-2 regression_test: none" '[]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"item range 5-2 starts after end"* ]]
  mkbody "- $id1 resolved was=src/a.py:2-3 fix=src/nope.py:1-2 regression_test: none" '[]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"absent at the reviewed head"* ]]
}

# --- P17: field validity ---
@test "P17a: a finding whose lines start after end is refused" {
  mkbody 'None.' '[{"category":"c","evidence":"e","family":"f","file":"src/a.py","lines":[3,1],"severity":"critical","summary":"s"}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"start after end"* ]]
}

@test "P17b: a finding whose file is absent at the reviewed head is refused" {
  mkbody 'None.' '[{"category":"c","evidence":"e","family":"f","file":"src/nope.py","lines":[1,1],"severity":"critical","summary":"s"}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"absent at the reviewed head"* ]]
}

@test "P17b: a path that is not a normalised relative path is refused" {
  mkbody 'None.' '[{"category":"c","evidence":"e","family":"f","file":"./src/a.py","lines":[1,1],"severity":"critical","summary":"s"}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"normalised relative path"* ]]
}

@test "P17c: a critical/important finding with an empty, uppercase, or missing family is refused" {
  mkbody 'None.' '[{"category":"c","evidence":"e","file":"src/a.py","lines":[1,1],"severity":"critical","summary":"s"}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"no valid family"* ]]
  mkbody 'None.' '[{"category":"c","evidence":"e","family":"","file":"src/a.py","lines":[1,1],"severity":"critical","summary":"s"}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"no valid family"* ]]
  mkbody 'None.' '[{"category":"c","evidence":"e","family":"Null-Deref","file":"src/a.py","lines":[1,1],"severity":"important","summary":"s"}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"no valid family"* ]]
}

@test "P17d: a duplicate JSON key is refused" {
  mkbody 'None.' '[{"category":"c","category":"c","evidence":"e","family":"f","file":"src/a.py","lines":[1,1],"severity":"critical","summary":"s"}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"not JSON"* ]]; [[ "$output" == *"duplicate JSON key"* ]]
}

@test "an empty summary is refused" {
  mkbody 'None.' '[{"category":"c","evidence":"e","family":"f","file":"src/a.py","lines":[1,1],"severity":"critical","summary":""}]'
  run python3 -I "$C" "$B" "$HEAD" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"empty summary"* ]]
}

# --- --prior mode: anchors and classification ---
@test "--prior: no previous round requires exactly None." {
  mkbody; run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 0 ]
  mkbody 'Not recorded: the previous round has no review-findings block.'
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"must be exactly 'None.'"* ]]
}

@test "--prior: an open carried item and its object pass; the run file's MODE must match the body" {
  local id1; id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None")
  prev "[$O1]"
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" full
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 0 ]
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" incremental
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"Review-mode says 'incremental', the run file says 'full'"* ]]
}

@test "incremental: a carried open item must be copied verbatim" {
  local id1; id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None")
  printf 'REVIEWED_HEAD_SHA=%s\nPRP_VERSION=9.9.9\nRUN_ID=%s\nTIER=standard\nSTART_URL=https://github.com/o/r/pull/7#issuecomment-1\nMODE=incremental\n' "$HEAD" "$RUN" > "$TEST_TMPDIR/run.inc.env"
  prev "[$O1]"
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" incremental
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 0 ]                                                        # identical object carries
  local OM='{"category":"correctness","evidence":"EDITED","family":"null-deref","file":"src/a.py","lines":[2,3],"severity":"important","summary":"NPE on None"}'
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$OM]" incremental   # evidence (not an id field) edited
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"was not copied verbatim from the previous round"* ]]
}

@test "--prior: a body whose line 2 is not 'Passes run: <pass>' is refused — the parity check cannot be silently disabled" {
  local id1; id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None")
  prev "[$O1]"
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]"
  sed -i '2s/^Passes run: code-reviewer$/Passes run code-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"body line 2 is not 'Passes run: <pass>'"* ]]
}

@test "an open prior item with no family id (-) demands a FULL re-review, not an impossible count" {
  prev '[{"category":"c","evidence":"e","file":"src/a.py","lines":[2,3],"severity":"important","summary":"s"}]'
  mkbody '- - open src/a.py:2-3 regression_test: none' '[]'
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no family id"* ]]; [[ "$output" == *"re-run a FULL review"* ]]
  [[ "$output" != *"appears 0 times"* ]]
}

@test "P19: an edited previous block is unstructured — incremental refuses, full demands Not recorded" {
  prev '[]' 2026-01-01T00:00:00Z 2026-01-02T00:00:00Z
  printf 'REVIEWED_HEAD_SHA=%s\nPRP_VERSION=9.9.9\nRUN_ID=%s\nTIER=standard\nSTART_URL=https://github.com/o/r/pull/7#issuecomment-1\nMODE=incremental\n' "$HEAD" "$RUN" > "$TEST_TMPDIR/run.inc.env"
  mkbody 'None.' '[]' incremental
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"edited after posting"* ]]; [[ "$output" == *"must be FULL"* ]]
  mkbody 'None.' '[]' full
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"must be the 'Not recorded' line"* ]]
}

@test "P20/P21/P22: a dropped, duplicated, or extra prior item is refused" {
  local id1 id2; id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None"); id2=$(idof code-reviewer src/a.py 5 6 race "race on x")
  prev "[$O1,$O2]"
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]"      # id2 dropped
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"do not match the previous round exactly"* ]]
  prev "[$O1]"
  mkbody "- $id1 open src/a.py:2-3 regression_test: none
- $id1 open src/a.py:2-3 regression_test: none" "[$O1]"                # duplicated
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"do not match the previous round exactly"* ]]
  mkbody "- $id1 open src/a.py:2-3 regression_test: none
- 000000000000 open src/b.py:1-1 regression_test: none" "[$O1]"        # extra item
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"do not match the previous round exactly"* ]]
}

@test "an open item missing from this round's JSON, or a resolved item still in it, is refused" {
  local id1 id2; id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None"); id2=$(idof code-reviewer src/a.py 5 6 race "race on x")
  prev "[$O1,$O2]"
  mkbody "- $id1 open src/a.py:2-3 regression_test: none
- $id2 resolved was=src/a.py:5-6 fix=src/b.py:1-2 regression_test: none" "[$O1,$O2]"   # id2 claimed resolved but still carried
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"still appears"* ]]
  mkbody "- $id1 open src/a.py:2-3 regression_test: none
- $id2 resolved was=src/a.py:5-6 fix=src/b.py:1-2 regression_test: none" "[$O2]"        # id1 claimed open but dropped from the JSON
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"appears 0 times"* ]]
}

@test "P28: a body claiming Not recorded while the previous round is structured is refused" {
  prev "[$O1]"
  mkbody 'Not recorded: the previous round has no review-findings block.'
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"the previous round is structured: Prior findings must itemise it"* ]]
}

@test "usage and IO: wrong arity → 3, missing files → 3" {
  run python3 -I "$C"; [ "$status" -eq 3 ]
  run python3 -I "$C" --prior "$B"; [ "$status" -eq 3 ]
  run python3 -I "$C" "$TEST_TMPDIR/nope.md" "$HEAD" code-reviewer; [ "$status" -eq 3 ]
  run python3 -I "$C" "$B" "$TSV" "$TEST_TMPDIR/nope.env" --prior 2>/dev/null; [ "$status" -eq 3 ]
}

# --- (a) matrix, plan rev 5: the expected pass is trusted argv, never body-derived ---

prevp() { # prevp <pass> <finds> <version> <run-id> [footer-suffix] — a structured previous round for <pass>
  printf 'Reviewed head: %s\nPasses run: %s\n\n### Critical Issues (0 found)\nNone.\n\n### Important Issues (0 found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\n### Prior findings\nNone.\n\n```review-findings\n{"reviewed_head":"%s","pass":"%s","complete":true,"findings":%s}\n```\n\nReview-mode: full\n\nGenerated-by: prp-review-agents %s run=%s pass=%s%s\n' \
    "$HEAD" "$1" "$HEAD" "$1" "$2" "$3" "$4" "$1" "${5:-}" | addc 2026-01-01T00:00:00Z 2026-01-01T00:00:00Z "$(cat)"
}

@test "(a) a non-core expected pass is refused with a named reason" {
  mkbody
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" not-a-pass
  [ "$status" -eq 1 ]; [[ "$output" == *"is not a core pass name"* ]]
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" ""
  [ "$status" -eq 1 ]; [[ "$output" == *"is not a core pass name"* ]]
}

@test "(a) line 2 must equal the trusted expected pass — empty, blank, unknown and mismatched values are refused in both modes" {
  mkbody; sed -i '2s/^Passes run: code-reviewer$/Passes run: /' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"body line 2 is not 'Passes run: <pass>'"* ]]
  mkbody; sed -i '2s/^Passes run: code-reviewer$/Passes run:    /' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"body line 2 is not 'Passes run: <pass>'"* ]]
  mkbody; sed -i '2s/^Passes run: code-reviewer$/Passes run: mystery-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"body line 2 is not 'Passes run: <pass>'"* ]]
  mkbody; sed -i '2s/^Passes run: code-reviewer$/Passes run: security-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"body line 2 is not 'Passes run: <pass>'"* ]]
  mkbody 'None.' '[]' incremental; sed -i '2s/^Passes run: code-reviewer$/Passes run: security-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"body line 2 is not 'Passes run: <pass>'"* ]]
}

@test "(a) simultaneous forgery: line 2, fence pass and footer pass all rewritten to another valid pass while the TSV holds an open prior for the real pass — refused in both modes" {
  local id1; id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None")
  prev "[$O1]"
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" full
  sed -i '2s/code-reviewer$/security-reviewer/; s/"pass":"code-reviewer"/"pass":"security-reviewer"/; s/ pass=code-reviewer$/ pass=security-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"body line 2 is not 'Passes run: <pass>'"* ]]
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" incremental
  sed -i '2s/code-reviewer$/security-reviewer/; s/"pass":"code-reviewer"/"pass":"security-reviewer"/; s/ pass=code-reviewer$/ pass=security-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"body line 2 is not 'Passes run: <pass>'"* ]]
}

@test "(a) the fence JSON pass must equal the trusted expected pass (both modes)" {
  mkbody; sed -i 's/"pass":"code-reviewer"/"pass":"security-reviewer"/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"review-findings pass is not the expected pass"* ]]
  mkbody 'None.' '[]' incremental; sed -i 's/"pass":"code-reviewer"/"pass":"security-reviewer"/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"review-findings pass is not the expected pass"* ]]
}

@test "(a) footer provenance: run= must be the run file's RUN_ID, pass= the expected pass, the shape exact (both modes)" {
  mkbody; sed -i 's/run=20260102T000000Z-feedface pass=code-reviewer/run=20260101T000000Z-deadbeef pass=code-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"footer run= is not the run file's RUN_ID"* ]]
  mkbody; sed -i 's/ pass=code-reviewer$/ pass=security-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"footer pass= is not the expected pass"* ]]
  mkbody; sed -i 's/^Generated-by: prp-review-agents v9.9.9 run=/Generated-by: prp-review-agents v9.9.9 run =/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"the footer is not the 'Generated-by:"* ]]
  mkbody 'None.' '[]' incremental; sed -i 's/run=20260102T000000Z-feedface pass=code-reviewer/run=20260101T000000Z-deadbeef pass=code-reviewer/' "$B"
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 1 ]; [[ "$output" == *"footer run= is not the run file's RUN_ID"* ]]
}

@test "(a) end-to-end footer shapes: every footer Step C accepts — per tier, version and run shape — is selected by the prior lookup (both modes)" {
  local id1 idS idH
  id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None")
  idS=$(idof security-reviewer src/a.py 2 3 null-deref "NPE on None")
  idH=$(idof silent-failure-hunter src/a.py 2 3 null-deref "NPE on None")
  prevp code-reviewer          "[$O1]" v2.12.0 20250101T000000Z-aaaaaaaa
  prevp security-reviewer      "[$O1]" v2.9.13 20250102T000000Z-bbbbbbbb
  prevp silent-failure-hunter  "[$O1]" v2.12.0 20250103T000000Z-cccccccc
  prevp code-reviewer          "[$O1]" v2.12.0 20250104T000000Z-dddddddd " tier=trivial"
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" full code-reviewer
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 0 ]
  mkbody "- $idS open src/a.py:2-3 regression_test: none" "[$O1]" full security-reviewer
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" security-reviewer
  [ "$status" -eq 0 ]
  mkbody "- $idH open src/a.py:2-3 regression_test: none" "[$O1]" full silent-failure-hunter
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" silent-failure-hunter
  [ "$status" -eq 0 ]
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" incremental code-reviewer
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 0 ]
  mkbody "- $idS open src/a.py:2-3 regression_test: none" "[$O1]" incremental security-reviewer
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" security-reviewer
  [ "$status" -eq 0 ]
}

@test "(a) end-to-end: a prior footer with trailing whitespace — accepted by Step C's structure check — is still selected, never silently skipped" {
  local id1; id1=$(idof code-reviewer src/a.py 2 3 null-deref "NPE on None")
  prevp code-reviewer "[$O1]" v2.12.0 20250105T000000Z-eeeeeeee " "
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" full code-reviewer
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.env" code-reviewer
  [ "$status" -eq 0 ]
  mkbody "- $id1 open src/a.py:2-3 regression_test: none" "[$O1]" incremental code-reviewer
  run python3 -I "$C" --prior "$B" "$TSV" "$TEST_TMPDIR/run.inc.env" code-reviewer
  [ "$status" -eq 0 ]
}

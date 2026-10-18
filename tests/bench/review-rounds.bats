#!/usr/bin/env bats
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
RR="$REPO_ROOT/scripts/bench/review-rounds.py"
FIX="$REPO_ROOT/tests/bench/fixtures"
setup() { TEST_TMPDIR="$(mktemp -d)"; }
teardown() { rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

# --- fallback ---
@test "fallback: incremental" {
  run python3 -I "$RR" fallback --json "$FIX/incremental.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert d['sessions'][0]['mode']=='incremental'" "$output"
}
@test "fallback: fell-back (No previous)" {
  run python3 -I "$RR" fallback --json "$FIX/fell-back-no-prev.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])['sessions'][0]['mode']=='fell-back'" "$output"
}
@test "fallback: fell-back (Running full)" {
  run python3 -I "$RR" fallback --json "$FIX/fell-back-full.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])['sessions'][0]['mode']=='fell-back'" "$output"
}
@test "fallback: prompt body with placeholders → not fell-back (regression defect 1)" {
  run python3 -I "$RR" fallback --json "$FIX/prompt-body.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; m=json.loads(sys.argv[1])['sessions'][0]['mode']; assert m!='fell-back', f'got {m}'" "$output"
}
@test "fallback: full-requested excluded from rate" {
  run python3 -I "$RR" fallback --json "$FIX/full-requested.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert d['sessions'][0]['mode']=='full-requested' and d['invoked']==0" "$output"
}
@test "fallback: truncated line counted" {
  run python3 -I "$RR" fallback --json "$FIX/truncated.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert d['sessions'][0]['skipped_lines']==1" "$output"
  [[ "$output" != *"Traceback"* ]]
}
@test "fallback: unknown arm (invoked, no diff, no not-found)" {
  run python3 -I "$RR" fallback --json "$FIX/unknown.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='unknown' and s['invoked'], s" "$output"
}
@test "fallback: incremental via pr-N-incremental.diff file" {
  run python3 -I "$RR" fallback --json "$FIX/incremental-diff-file.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])['sessions'][0]['mode']=='incremental'" "$output"
}
@test "fallback: I1 — the arm fixtures cover every classifier arm" {
  run python3 -I "$RR" fallback --json "$FIX/full-requested.jsonl" "$FIX/incremental.jsonl" "$FIX/incremental-diff-file.jsonl" "$FIX/fell-back-no-prev.jsonl" "$FIX/unknown.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; m={s['mode'] for s in json.loads(sys.argv[1])['sessions']}; assert m=={'full-requested','incremental','fell-back','unknown'}, m" "$output"
}
@test "fallback: valid-JSON non-object lines are skipped, not a crash" {
  run python3 -I "$RR" fallback --json "$FIX/non-object-line.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])['sessions'][0]['skipped_lines']==2" "$output"
}
@test "fallback: I2 — a missing file is an error, the good file is still counted, exit 2" {
  run python3 -I "$RR" fallback --json "$TEST_TMPDIR/nope.jsonl" "$FIX/incremental.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" != *"Traceback"* ]]
  python3 -I -c "import json,sys; s=sys.argv[1]; d=json.JSONDecoder().raw_decode(s, s.index('{\n'))[0]; assert d['total']==1 and d['incremental']==1, d; assert len(d['errors'])==1 and 'FileNotFoundError' in d['errors'][0]['error'], d" "$output"
}
@test "fallback: I2 — a directory and a non-UTF-8 file are errors, not a crash" {
  run python3 -I "$RR" fallback "$TEST_TMPDIR" "$FIX/non-utf8.jsonl" "$FIX/unknown.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" != *"Traceback"* ]]
  echo "$output" | grep -q '| unreadable files | 2 |'
  echo "$output" | grep -q 'IsADirectoryError'
  echo "$output" | grep -q 'UnicodeDecodeError'
}
@test "fallback: no paths → usage error, exit 1" {
  run python3 -I "$RR" fallback
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'error: fallback needs at least one transcript path'
}
@test "fallback: all files readable → exit 0, errors empty" {
  run python3 -I "$RR" fallback --json "$FIX/incremental.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])['errors']==[]" "$output"
}
@test "fallback: markdown output shows skipped lines" {
  run python3 -I "$RR" fallback "$FIX/truncated.jsonl"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '| skipped (unparseable) lines | 1 |'
}
# --- I2 shape mutation (re-plan rev3): every field of the real fixtures, every wrong type ---
@test "I2 mutation: fallback reads every wrong-type transcript variant without an error" {
  mkdir "$TEST_TMPDIR/t"
  n=$(python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" transcripts "$TEST_TMPDIR/t" "$FIX"/incremental.jsonl "$FIX"/incremental-diff-file.jsonl "$FIX"/fell-back-no-prev.jsonl "$FIX"/fell-back-full.jsonl "$FIX"/unknown.jsonl "$FIX"/full-requested.jsonl)
  [ "$n" -gt 500 ]
  rc=0; python3 -I "$RR" fallback --json "$TEST_TMPDIR"/t/*.jsonl > "$TEST_TMPDIR/out.json" 2> "$TEST_TMPDIR/err.txt" || rc=$?
  [ "$rc" -eq 0 ]
  ! grep -q Traceback "$TEST_TMPDIR/err.txt"
  python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['errors']==[] and d['total']==int(sys.argv[2]), (d['errors'][:3], d['total'])" "$TEST_TMPDIR/out.json" "$n"
}

# --- misc ---
@test "no-write: no write paths" {
  run grep -cE "open\([^)]*['\"]w['\"]|gh pr comment|gh api -X (POST|PATCH|DELETE)" "$RR"
  [ "$output" = "0" ]
}
@test "no arg → 1" { run python3 -I "$RR"; [ "$status" -eq 1 ]; }

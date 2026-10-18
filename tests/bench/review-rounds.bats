#!/usr/bin/env bats
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
RR="$REPO_ROOT/scripts/bench/review-rounds.py"
FIX="$REPO_ROOT/tests/bench/fixtures"
GH="$REPO_ROOT/tests/bench/fixtures/gh"
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

# --- rounds (fixture-based, no network) ---
@test "rounds: clean (0 found) → class clean (regression defect 3)" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 99
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); r=d[0]['rounds']; assert r[0]['class']=='clean', f'R1={r[0]}'" "$output"
}
@test "rounds: C/I > 0 → class a" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 99
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; r=json.loads(sys.argv[1])[0]['rounds']; assert r[1]['class']=='a'" "$output"
}
@test "rounds: repeated family → class b" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 99
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; r=json.loads(sys.argv[1])[0]['rounds']; assert r[2]['class']=='b', f'R3={r[2]}'" "$output"
}
@test "rounds: < 3 passes → class c" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 99
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; r=json.loads(sys.argv[1])[0]['rounds']; assert r[3]['class']=='c'" "$output"
}
@test "rounds: unmerged → excluded" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 88
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])[0]['status']=='unmerged'" "$output"
}
@test "rounds: real numbered '1. **T**' findings give families; indented sub-bullets do not" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 77
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; r=json.loads(sys.argv[1])[0]['rounds']; assert r[0]['families']==['alpha cap is never enforced'], r[0]" "$output"
}
@test "rounds: a Suggestions title is not a family (scoped to C/I section)" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 77
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; r=json.loads(sys.argv[1])[0]['rounds']; assert r[1]['class']=='a', r[1]; assert r[2]['class']=='b', r[2]" "$output"
}
@test "rounds: findings-table row gives a family (header/separator skipped)" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 77
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; r=json.loads(sys.argv[1])[0]['rounds']; assert r[3]['families']==['beta naming is unclear'], r[3]; assert r[3]['class']=='b', r[3]" "$output"
}
@test "rounds: missing comments fixture → status error, exit 2 (not a 0-round merge)" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 66
  [ "$status" -eq 2 ]
  python3 -I -c "import json,sys; s=sys.argv[1]; d=json.JSONDecoder().raw_decode(s, s.index('[\n'))[0]; assert d[0]['status']=='error', d" "$output"
}
@test "rounds: missing pulls fixture → status error, exit 2 (not 'unmerged')" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --repo test/repo --prs 55
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'PR #55: ERROR RuntimeError: fixture missing'
}

@test "rounds: non-object comment → status error, exit 2, no traceback" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --repo test/repo --prs 44
  [ "$status" -eq 2 ]
  [[ "$output" != *"Traceback"* ]]
  echo "$output" | grep -q 'PR #44: ERROR TypeError: issues/44/comments\[0\] is not an object'
}
@test "rounds: comment body null → status error, exit 2, no traceback" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --repo test/repo --prs 45
  [ "$status" -eq 2 ]
  [[ "$output" != *"Traceback"* ]]
  echo "$output" | grep -q 'PR #45: ERROR TypeError: issues/45/comments\[0\].body is not a string'
}
@test "rounds: non-JSON comments response → status error, exit 2, no traceback" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --repo test/repo --prs 43
  [ "$status" -eq 2 ]
  [[ "$output" != *"Traceback"* ]]
  echo "$output" | grep -q 'PR #43: ERROR JSONDecodeError'
}
@test "rounds: one bad PR in a batch keeps the good PR's result" {
  run env REVIEW_ROUNDS_GH_FIXTURES="$GH" python3 -I "$RR" rounds --json --repo test/repo --prs 99,45
  [ "$status" -eq 2 ]
  python3 -I -c "import json,sys; s=sys.argv[1]; d=json.JSONDecoder().raw_decode(s, s.index('[\n'))[0]; st={r['pr']:r['status'] for r in d}; assert st=={99:'merged',45:'error'}, st; assert len(d[0]['rounds'])==4" "$output"
}
@test "rounds: --repo without a value → usage error, exit 1, no traceback" {
  run python3 -I "$RR" rounds --prs 1 --repo
  [ "$status" -eq 1 ]
  [[ "$output" != *"Traceback"* ]]
  echo "$output" | grep -q 'error: --repo needs a value'
}
@test "rounds: non-numeric --prs → usage error, exit 1, no traceback" {
  run python3 -I "$RR" rounds --repo test/repo --prs abc
  [ "$status" -eq 1 ]
  [[ "$output" != *"Traceback"* ]]
  echo "$output" | grep -q 'error: --prs must be comma-separated integers'
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
@test "I2 mutation: rounds never raises on a wrong-type pulls/comments variant" {
  mkdir "$TEST_TMPDIR/g"
  n=$(python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" gh "$TEST_TMPDIR/g" "$GH" 77)
  [ "$n" -gt 100 ]
  run python3 -I - "$RR" "$TEST_TMPDIR/g" <<'PY'
import contextlib, importlib.util, io, os, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1]); rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
seen = set()
for d in sorted(os.listdir(sys.argv[2])):
    os.environ["REVIEW_ROUNDS_GH_FIXTURES"] = os.path.join(sys.argv[2], d)
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = rr.cmd_rounds("test/repo", [77], as_json=False)
    assert code in (0, 2), (d, code)
    assert "internal" not in out.getvalue(), (d, out.getvalue())
    seen.add(code)
print("variants ok, exit codes seen:", sorted(seen))
PY
  [ "$status" -eq 0 ]
  [[ "$output" != *"Traceback"* ]]
  echo "$output" | grep -q 'variants ok, exit codes seen: \[0, 2\]'
}

# --- misc ---
@test "no-write: no write paths" {
  run grep -cE "open\([^)]*['\"]w['\"]|gh pr comment|gh api -X (POST|PATCH|DELETE)" "$RR"
  [ "$output" = "0" ]
}
@test "no arg → 1" { run python3 -I "$RR"; [ "$status" -eq 1 ]; }

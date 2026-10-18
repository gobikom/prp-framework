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

# --- misc ---
@test "no-write: no write paths" {
  run grep -cE "open\([^)]*['\"]w['\"]|gh pr comment|gh api -X (POST|PATCH|DELETE)" "$RR"
  [ "$output" = "0" ]
}
@test "no arg → 1" { run python3 -I "$RR"; [ "$status" -eq 1 ]; }

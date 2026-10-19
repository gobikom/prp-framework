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
@test "fallback: markdown rate line states the lower bound over identified invocations" {
  run python3 -I "$RR" fallback "$FIX/full-requested.jsonl" "$FIX/incremental.jsonl"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^| fallback rate (lower bound) | 0\.0% of 1 identified invocations |$'
}
@test "fallback: nonzero rate asserted — single fell-back, and mixed with full-requested" {
  run python3 -I "$RR" fallback --json "$FIX/fell-back-no-prev.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert d['fallback_rate']==1.0 and d['fell_back']==1 and d['invoked']==1 and d['full_requested']==0, d" "$output"
  run python3 -I "$RR" fallback --json "$FIX/fell-back-no-prev.jsonl" "$FIX/full-requested.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert d['fallback_rate']==1.0 and d['fell_back']==1 and d['invoked']==1 and d['full_requested']==1, d" "$output"
}
@test "fallback: no parseable user prompt → unknown (invocation.none), never full-requested" {
  : > "$TEST_TMPDIR/empty.jsonl"; printf 'not json {{{\n{"type":"summary","summary":"x"}\n' > "$TEST_TMPDIR/garbage.jsonl"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}\n' > "$TEST_TMPDIR/resumed.jsonl"
  run python3 -I "$RR" fallback --json "$TEST_TMPDIR/empty.jsonl" "$TEST_TMPDIR/garbage.jsonl" "$TEST_TMPDIR/resumed.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; ss=json.loads(sys.argv[1])['sessions']; assert all(s['mode']=='unknown' and s['invoked'] is None and s['invocation_reason']=='invocation.none' and s['unknown_fields']==[] for s in ss), ss" "$output"
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
@test "fallback: a failed cat of the incremental diff is fell-back, not incremental" {
  run python3 -I "$RR" fallback --json "$FIX/incr-diff-failed.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; m=json.loads(sys.argv[1])['sessions'][0]['mode']; assert m=='fell-back', m" "$output"
}
@test "fallback: a not-found that merely contains the word review is unknown, not fell-back" {
  run python3 -I "$RR" fallback --json "$FIX/review-word-not-found.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; m=json.loads(sys.argv[1])['sessions'][0]['mode']; assert m=='unknown', m" "$output"
}
@test "fallback: results are paired with their command by tool_use_id, not by order" {
  run python3 -I "$RR" fallback --json "$FIX/paired-by-id.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; m=json.loads(sys.argv[1])['sessions'][0]['mode']; assert m=='fell-back', m" "$output"
}
@test "fallback: no placeholder token-delta field in the output" {
  run python3 -I "$RR" fallback --json "$FIX/incremental.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert 'extra_tokens_delta' not in d, d" "$output"
}
@test "fallback: rev6 — a diff command with no result is unknown (missing is never evidence)" {
  run python3 -I "$RR" fallback --json "$FIX/incr-diff-no-result.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='unknown', s" "$output"
}
@test "fallback: rev6 — a review-file command with no result is unknown" {
  run python3 -I "$RR" fallback --json "$FIX/review-file-no-result.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='unknown', s" "$output"
}
@test "fallback: rev6 — a result whose id matches no use is an orphan, not paired by order" {
  run python3 -I "$RR" fallback --json "$FIX/orphan-id.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='unknown' and s['orphan_results']==1, s" "$output"
}
@test "fallback: #176 — a tool_use with no id is an UNKNOWN field, so the session is unknown" {
  run python3 -I "$RR" fallback --json "$FIX/idless-use.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='unknown' and s['unknown_fields']==['tool_use.id'], s" "$output"
}
@test "fallback: rev6 — diff output that merely contains NOT_FOUND is still a successful diff" {
  run python3 -I "$RR" fallback --json "$FIX/diff-output-says-not-found.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='incremental', s" "$output"
}
@test "fallback: rev6 — a diff command that errored without a not-found line is unknown, not evidence" {
  run python3 -I "$RR" fallback --json "$FIX/diff-command-errored.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='unknown', s" "$output"
}
@test "fallback: rev6 — a replayed tool id pairs each result with its own use, no orphan" {
  run python3 -I "$RR" fallback --json "$FIX/replayed-id.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='incremental' and s['orphan_results']==0, s" "$output"
}
@test "fallback: rev6 — an Agent prompt that names the diff is not a command on it" {
  run python3 -I "$RR" fallback --json "$FIX/agent-prompt-names-diff.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='unknown', s" "$output"
}
@test "fallback: rev6 — a Read of the incremental diff is incremental evidence" {
  run python3 -I "$RR" fallback --json "$FIX/read-incremental-diff.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])['sessions'][0]; assert s['mode']=='incremental', s" "$output"
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
  n=$(python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" transcripts "$TEST_TMPDIR/t" "$FIX"/incremental.jsonl "$FIX"/incremental-diff-file.jsonl "$FIX"/fell-back-no-prev.jsonl "$FIX"/fell-back-full.jsonl "$FIX"/unknown.jsonl "$FIX"/full-requested.jsonl "$FIX"/incr-diff-failed.jsonl "$FIX"/review-word-not-found.jsonl "$FIX"/paired-by-id.jsonl "$FIX"/incr-diff-no-result.jsonl "$FIX"/review-file-no-result.jsonl "$FIX"/orphan-id.jsonl "$FIX"/idless-use.jsonl "$FIX"/diff-output-says-not-found.jsonl "$FIX"/diff-command-errored.jsonl "$FIX"/replayed-id.jsonl "$FIX"/agent-prompt-names-diff.jsonl "$FIX"/read-incremental-diff.jsonl)
  [ "$n" -gt 500 ]
  rc=0; python3 -I "$RR" fallback --json "$TEST_TMPDIR"/t/*.jsonl > "$TEST_TMPDIR/out.json" 2> "$TEST_TMPDIR/err.txt" || rc=$?
  [ "$rc" -eq 0 ]
  ! grep -q Traceback "$TEST_TMPDIR/err.txt"
  python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['errors']==[] and d['total']==int(sys.argv[2]), (d['errors'][:3], d['total'])" "$TEST_TMPDIR/out.json" "$n"
}

# --- #176 invariant: one row per (field, value); an UNKNOWN field only ever yields mode unknown ---
_arm() {
  mkdir "$TEST_TMPDIR/a"
  n=$(python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" field-arms "$TEST_TMPDIR/a" "$FIX")
  [ "$n" -gt 100 ]
  python3 -I "$RR" fallback --json "$TEST_TMPDIR"/a/*.jsonl > "$TEST_TMPDIR/out.json"
  run python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" check "$TEST_TMPDIR/a/expected.tsv" "$TEST_TMPDIR/out.json" "$1"
  echo "$output"
  [ "$status" -eq 0 ]
}
@test "field-arm: tool_result.is_error" { _arm is_error; }
@test "field-arm: tool_result.tool_use_id" { _arm tool_use_id; }
@test "field-arm: tool_result.content" { _arm content; }
@test "field-arm: Bash input.command" { _arm command; }
@test "field-arm: Read input.file_path" { _arm file_path; }
@test "field-arm: tool_use.id" { _arm id; }
@test "field-arm: tool_use.name" { _arm name; }
@test "field-arm: block.type" { _arm block.type; }
@test "field-arm: message" { _arm message; }
@test "field-arm: message.content" { _arm message.content; }
@test "field-arm: a replayed id pairs FIFO, no orphan" { _arm replay; }
@test "field-arm: weakening _is_bool fails the is_error arm (mutation check)" {
  sed 's/type(v) is bool/isinstance(v, (bool, int))/' "$RR" > "$TEST_TMPDIR/rr-mut.py"
  mkdir "$TEST_TMPDIR/a"
  python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" field-arms "$TEST_TMPDIR/a" "$FIX" > /dev/null
  python3 -I "$TEST_TMPDIR/rr-mut.py" fallback --json "$TEST_TMPDIR"/a/*.jsonl > "$TEST_TMPDIR/out.json"
  run python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" check "$TEST_TMPDIR/a/expected.tsv" "$TEST_TMPDIR/out.json" is_error
  [ "$status" -eq 1 ]
}
@test "field-arm: the mutator names an unreadable fixture and exits 2" {
  run python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" field-arms "$TEST_TMPDIR" "$TEST_TMPDIR/missing"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing"* ]]
}
@test "boundary: only the _norm_* functions and _read_jsonl read raw JSON (.get)" {
  run awk '/^def /{fn=$2} /\.get\(/ && fn !~ /^(_norm_|_read_jsonl)/ {print FILENAME":"NR": "fn}' "$RR"
  [ -z "$output" ]
}

# --- #177b: the invocation reader — one test per arm; invocation-arms.tsv is the oracle ---
_inv() {
  mkdir "$TEST_TMPDIR/ia"
  python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" invocation-arms "$TEST_TMPDIR/ia" > /dev/null
  python3 -I "$RR" fallback --json "$TEST_TMPDIR"/ia/*.jsonl > "$TEST_TMPDIR/out.json"
  run python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" check-inv "$TEST_TMPDIR/ia/invocation-arms.tsv" "$TEST_TMPDIR/out.json" "$1"
  echo "$output"
  [ "$status" -eq 0 ]
}
@test "invocation-arm: A1 no user record" { _inv A1; }
@test "invocation-arm: A2 first user content empty" { _inv A2; }
@test "invocation-arm: A3 first user text block empty (r2 shape)" { _inv A3; }
@test "invocation-arm: A4 whitespace-only text" { _inv A4; }
@test "invocation-arm: A5 brief quoting the command, no tag" { _inv A5; }
@test "invocation-arm: A6 brief first, envelope with flag, incremental" { _inv A6; }
@test "invocation-arm: A7 envelope without flag" { _inv A7; }
@test "invocation-arm: A8 name tag without command-args" { _inv A8; }
@test "invocation-arm: A9 --since-last-reviewer is not the flag" { _inv A9; }
@test "invocation-arm: A10 Skill call with flag, failed review read" { _inv A10; }
@test "invocation-arm: A11 Skill input.args absent" { _inv A11; }
@test "invocation-arm: A12 Skill input.args = 5" { _inv A12; }
@test "invocation-arm: A13 Skill call for another skill" { _inv A13; }
@test "invocation-arm: A14 two envelopes, flag mixed" { _inv A14; }
@test "invocation-arm: A15 envelope + boundary UNKNOWN (exact tuple)" { _inv A15; }
@test "invocation-arm: A16 brief quoting an envelope + real envelope" { _inv A16; }
@test "invocation-arm: A17 /compact envelope quoting the command" { _inv A17; }
@test "invocation-arm: A18 empty args, flag only in later plain text" { _inv A18; }
@test "invocation-arm: A19 two command-args tags" { _inv A19; }
@test "invocation-arm: A20 envelope + Skill call" { _inv A20; }
@test "invocation-arm: A21 envelope inside a text block" { _inv A21; }
@test "invocation-arm: A22 flag-like args are not the flag (3 rows)" { _inv A22; }
@test "invocation-arm: A23 flag split across arg lines" { _inv A23; }
@test "invocation-arm: A24 malformed beats multiple" { _inv A24; }
@test "invocation-arm: A25 flag text in a brief does not decide; the envelope does" { _inv A25; }
@test "invocation-arm: A26 Skill input not a dict + envelope" { _inv A26; }
@test "invocation-arm: A27 Skill input.skill absent + envelope" { _inv A27; }
@test "invocation-arm: mutation (b) — first-user-text or substring fallback fails ≥ 3 arms" {
  mkdir "$TEST_TMPDIR/ia"
  python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" invocation-arms "$TEST_TMPDIR/ia" > /dev/null
  # (b1) every user str content becomes the invocation's args (the r1/r2 family)
  sed 's|m = ENVELOPE_PAT.match(txt)|m = re.match(r"(.*)", txt, re.S)|' "$RR" > "$TEST_TMPDIR/rr-b1.py"
  python3 -I "$TEST_TMPDIR/rr-b1.py" fallback --json "$TEST_TMPDIR"/ia/*.jsonl > "$TEST_TMPDIR/b1.json"
  python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['errors']==[] and d['total']>0, d['errors'][:3]" "$TEST_TMPDIR/b1.json"
  run python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" check-inv "$TEST_TMPDIR/ia/invocation-arms.tsv" "$TEST_TMPDIR/b1.json"
  [ "$(echo "$output" | grep -c ':')" -ge 3 ]
  # (b2) a command-args tag anywhere in user text is trusted as the envelope
  sed -e '/^NAME_TAG_PAT = re.compile/a ARGS_TAG_PAT = re.compile(r"<command-args>([^<]*)</command-args>")' \
      -e 's|m = ENVELOPE_PAT.match(txt)|m = ARGS_TAG_PAT.search(txt)|' "$RR" > "$TEST_TMPDIR/rr-b2.py"
  python3 -I "$TEST_TMPDIR/rr-b2.py" fallback --json "$TEST_TMPDIR"/ia/*.jsonl > "$TEST_TMPDIR/b2.json"
  python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['errors']==[] and d['total']>0, d['errors'][:3]" "$TEST_TMPDIR/b2.json"
  run python3 -I "$BATS_TEST_DIRNAME/mutate_fixtures.py" check-inv "$TEST_TMPDIR/ia/invocation-arms.tsv" "$TEST_TMPDIR/b2.json"
  [ "$(echo "$output" | grep -c ':')" -ge 3 ]
}
@test "boundary: the flag token is read only inside the invocation reader" {
  [ "$(grep -c -- '--since-last-review' "$RR")" -eq 1 ]
  fl=$(grep -n -- '--since-last-review' "$RR" | head -1 | cut -d: -f1)
  mk=$(grep -n '^# --- the invocation reader' "$RR" | cut -d: -f1)
  [ -n "$fl" ] && [ -n "$mk" ] && [ "$fl" -ge "$mk" ]
}

# --- misc ---
@test "no-write: no write paths" {
  run grep -cE "open\([^)]*['\"][wax]\+?['\"]|os\.(remove|unlink|rename|replace)|shutil\.|gh pr comment|gh api -X (POST|PATCH|DELETE)" "$RR"
  [ "$output" = "0" ]
}
@test "no arg → 1" { run python3 -I "$RR"; [ "$status" -eq 1 ]; }

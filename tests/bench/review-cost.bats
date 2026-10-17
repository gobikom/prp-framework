#!/usr/bin/env bats
# review-cost.py tests for prp-framework#160.
bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
RC="$REPO_ROOT/scripts/bench/review-cost.py"

setup() { TEST_TMPDIR="$(mktemp -d)"; }
teardown() { rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

_make_session() {
  local dir="${1:?}" sid="${2:?}"; mkdir -p "$dir/$sid/subagents"
  cat > "$dir/$sid.jsonl" <<'EOF'
{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}
{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":5000000,"cache_creation_input_tokens":500000,"output_tokens":50000}}}
{"type":"assistant","message":{"usage":{"input_tokens":50,"cache_read_input_tokens":3000000,"cache_creation_input_tokens":200000,"output_tokens":30000}}}
EOF
  cat > "$dir/$sid/subagents/agent-test1.jsonl" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":20,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":100000,"output_tokens":10000}}}
EOF
  printf '{"agentType":"code-reviewer","finished":true}\n' > "$dir/$sid/subagents/agent-test1.meta.json"
}

_good_line='{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}'
_usage_line='{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_read_input_tokens":100,"cache_creation_input_tokens":0,"output_tokens":5}}}'

_assert_shape_rejected() {
  local bad_line="$1" label="$2"
  mkdir -p "$TEST_TMPDIR/project"
  printf '%s\n' "$bad_line" > "$TEST_TMPDIR/project/bad-shape.jsonl"
  printf '%s\n%s\n' "$_good_line" "$_usage_line" > "$TEST_TMPDIR/project/ok-sess.jsonl"
  run --separate-stderr python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -ne 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert len(d)==1 and d[0]['output']==5, f'got {d}'" "$output"
  [[ "$stderr" == *"bad-shape.jsonl"* ]]
}

@test "review-cost.py: sums main + subagent usage correctly" {
  _make_session "$TEST_TMPDIR/project" "session-abc"
  run python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  python3 -I - "$output" <<'PY'
import json, sys
s = json.loads(sys.argv[1])[0]
assert s["cache_read"] == 9000000 and s["cache_create"] == 800000
assert s["output"] == 90000 and s["main_output"] == 80000 and s["agent_output"] == 10000
assert s["weighted_cost"] == 2350170.0
PY
}

@test "review-cost.py: handles missing subagents dir" {
  mkdir -p "$TEST_TMPDIR/project"
  printf '%s\n%s\n' "$_good_line" "$_usage_line" > "$TEST_TMPDIR/project/no-subs.jsonl"
  run python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])[0]; assert s['agent_output']==0 and s['output']==5" "$output"
}

@test "review-cost.py: handles empty lines and malformed JSON" {
  mkdir -p "$TEST_TMPDIR/project"
  printf '\n%s\nnot json\n%s\n' "$_good_line" "$_usage_line" > "$TEST_TMPDIR/project/messy.jsonl"
  run --separate-stderr python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])[0]['output']==5" "$output"
  [[ "$stderr" == *"malformed"* ]] || [[ "$stderr" == *"skipped"* ]]
}

@test "review-cost.py: handles jsonl with no usage (boundary)" {
  mkdir -p "$TEST_TMPDIR/project"
  printf '%s\n{"type":"human","message":{"content":"hello"}}\n' "$_good_line" > "$TEST_TMPDIR/project/no-usage.jsonl"
  run python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])[0]; assert s['output']==0" "$output"
}

@test "review-cost.py: errors on empty directory" {
  mkdir -p "$TEST_TMPDIR/empty"
  run python3 -I "$RC" "$TEST_TMPDIR/empty/"
  [ "$status" -eq 1 ]
}

@test "review-cost.py: accepts bare jsonl file" {
  printf '%s\n%s\n' "$_good_line" "$_usage_line" > "$TEST_TMPDIR/bare.jsonl"
  run python3 -I "$RC" --json "$TEST_TMPDIR/bare.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])[0]['output']==5" "$output"
}

@test "review-cost.py: all-bad-json file → non-zero exit" {
  mkdir -p "$TEST_TMPDIR/project"
  printf 'not json\nalso not json\n' > "$TEST_TMPDIR/project/bad.jsonl"
  run --separate-stderr python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"bad.jsonl"* ]]
}

@test "review-cost.py: good-first + bad → good on stdout, bad on stderr" {
  mkdir -p "$TEST_TMPDIR/project"
  printf '%s\n%s\n' "$_good_line" "$_usage_line" > "$TEST_TMPDIR/project/aaa-good.jsonl"
  printf 'not json\n' > "$TEST_TMPDIR/project/zzz-bad.jsonl"
  run --separate-stderr python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -ne 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert len(d)==1 and d[0]['output']==5" "$output"
  [[ "$stderr" == *"zzz-bad.jsonl"* ]]
}

@test "review-cost.py: bad-first + good → good on stdout, bad on stderr" {
  mkdir -p "$TEST_TMPDIR/project"
  printf 'not json\n' > "$TEST_TMPDIR/project/aaa-bad.jsonl"
  printf '%s\n%s\n' "$_good_line" "$_usage_line" > "$TEST_TMPDIR/project/zzz-good.jsonl"
  run --separate-stderr python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -ne 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert len(d)==1 and d[0]['output']==5" "$output"
  [[ "$stderr" == *"aaa-bad.jsonl"* ]]
}

@test "review-cost.py: corrupt subagent fails session, sibling reported" {
  mkdir -p "$TEST_TMPDIR/project/bad-sess/subagents"
  printf '%s\n%s\n' "$_good_line" "$_usage_line" > "$TEST_TMPDIR/project/bad-sess.jsonl"
  printf 'corrupt\n' > "$TEST_TMPDIR/project/bad-sess/subagents/agent-x.jsonl"
  printf '%s\n{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_read_input_tokens":200,"cache_creation_input_tokens":0,"output_tokens":9}}}\n' "$_good_line" > "$TEST_TMPDIR/project/ok-sess.jsonl"
  run --separate-stderr python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -ne 0 ]
  python3 -I -c "import json,sys; d=json.loads(sys.argv[1]); assert len(d)==1 and d[0]['output']==9" "$output"
  [[ "$stderr" == *"bad-sess"* ]]
}

@test "review-cost.py: all-good dir → exit 0, no error on stderr" {
  _make_session "$TEST_TMPDIR/project" "session-abc"
  run --separate-stderr python3 -I "$RC" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"error"* ]]
}

# --- Shape validation (Invariant 2) ---

@test "review-cost.py: rejects null line" {
  _assert_shape_rejected "null" "null"
}

@test "review-cost.py: rejects number line" {
  _assert_shape_rejected "42" "number"
}

@test "review-cost.py: rejects string line" {
  _assert_shape_rejected '"hello"' "string"
}

@test "review-cost.py: rejects array line" {
  _assert_shape_rejected '[1,2,3]' "array"
}

@test "review-cost.py: rejects message as string" {
  _assert_shape_rejected '{"type":"assistant","message":"not an object"}' "message-string"
}

@test "review-cost.py: rejects usage as list" {
  _assert_shape_rejected '{"type":"assistant","message":{"usage":[1,2]}}' "usage-list"
}

@test "review-cost.py: rejects token field as string" {
  _assert_shape_rejected '{"type":"assistant","message":{"usage":{"input_tokens":"100"}}}' "token-string"
}

@test "review-cost.py: rejects token field as bool" {
  _assert_shape_rejected '{"type":"assistant","message":{"usage":{"input_tokens":true}}}' "token-bool"
}

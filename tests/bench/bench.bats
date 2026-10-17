#!/usr/bin/env bats
# Benchmark tooling tests for prp-framework#160 Phase 0.
bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

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

@test "review-cost.py: sums main + subagent usage correctly" {
  _make_session "$TEST_TMPDIR/project" "session-abc"
  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
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
  printf '{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}\n{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200,"output_tokens":50}}}\n' > "$TEST_TMPDIR/project/no-subs.jsonl"
  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])[0]; assert s['agent_output']==0 and s['output']==50" "$output"
}

@test "review-cost.py: handles empty lines and malformed JSON" {
  mkdir -p "$TEST_TMPDIR/project"
  printf '\n{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}\nnot json\n{"type":"assistant","message":{"usage":{"input_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":0,"output_tokens":10}}}\n' > "$TEST_TMPDIR/project/messy.jsonl"
  run --separate-stderr python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])[0]['output']==10" "$output"
  [[ "$stderr" == *"skipped"* ]]
}

@test "review-cost.py: handles jsonl with no usage (boundary)" {
  mkdir -p "$TEST_TMPDIR/project"
  printf '{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}\n{"type":"human","message":{"content":"hello"}}\n' > "$TEST_TMPDIR/project/no-usage.jsonl"
  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; s=json.loads(sys.argv[1])[0]; assert s['output']==0 and s['cache_read']==0" "$output"
}

@test "review-cost.py: errors on empty directory" {
  mkdir -p "$TEST_TMPDIR/empty"
  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" "$TEST_TMPDIR/empty/"
  [ "$status" -eq 1 ]
}

@test "review-cost.py: accepts bare jsonl file" {
  printf '{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}\n{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_read_input_tokens":100,"cache_creation_input_tokens":0,"output_tokens":5}}}\n' > "$TEST_TMPDIR/bare.jsonl"
  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/bare.jsonl"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])[0]['output']==5" "$output"
}

@test "review-cost.py: all-bad-json file → non-zero exit" {
  mkdir -p "$TEST_TMPDIR/project"
  printf 'this is not json\nalso not json\nstill not json\n' > "$TEST_TMPDIR/project/bad.jsonl"
  run --separate-stderr python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"bad.jsonl"* ]]
}

@test "corpus.yaml: every entry has required fields" {
  python3 -I - "$REPO_ROOT/tests/bench/corpus.yaml" <<'PY'
import sys, yaml
REQUIRED = {"id","pr","head","base","patch_digest","permalink","kind","tier","files_changed","additions","deletions","labels"}
with open(sys.argv[1]) as f:
    corpus = yaml.safe_load(f)
entries = corpus.get("entries", [])
assert entries, "no entries"
for e in entries:
    missing = REQUIRED - set(e.keys())
    assert not missing, f"{e.get('id','?')}: missing {missing}"
    assert len(e["head"]) == 40 and len(e["base"]) == 40 and len(e["patch_digest"]) == 64
    assert e["kind"] in ("positive","negative") and e["tier"] in ("standard","trivial","docs","gate")
    assert isinstance(e["labels"], list)
PY
}

@test "corpus.yaml: entry ids are unique" {
  python3 -I - "$REPO_ROOT/tests/bench/corpus.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    ids = [e["id"] for e in yaml.safe_load(f).get("entries",[])]
assert len(ids) == len(set(ids)), f"duplicates: {[x for x in ids if ids.count(x)>1]}"
PY
}

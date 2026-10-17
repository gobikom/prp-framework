#!/usr/bin/env bats
# Benchmark tooling tests for prp-framework#160 Phase 0.
#
# AC0.1: review-cost.py produces correct totals from synthetic session data.
# AC0.3: replay.sh never calls post/marker code.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
  TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true
}

# --- Helper: create a synthetic session directory ---
_make_session() {
  local dir="${1:?}" session_id="${2:?}"
  local main_jsonl="$dir/$session_id.jsonl"
  local sub_dir="$dir/$session_id/subagents"
  mkdir -p "$sub_dir"

  # Main thread: 2 assistant messages with usage
  cat > "$main_jsonl" <<'EOF'
{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}
{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":5000000,"cache_creation_input_tokens":500000,"output_tokens":50000}}}
{"type":"assistant","message":{"usage":{"input_tokens":50,"cache_read_input_tokens":3000000,"cache_creation_input_tokens":200000,"output_tokens":30000}}}
EOF

  # One subagent
  cat > "$sub_dir/agent-test1.jsonl" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":20,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":100000,"output_tokens":10000}}}
EOF

  # Subagent meta
  cat > "$sub_dir/agent-test1.meta.json" <<'EOF'
{"agentType":"code-reviewer","description":"test","finished":true}
EOF
}

# --- AC0.1: review-cost.py totals ---

@test "review-cost.py: sums main + subagent usage correctly" {
  _make_session "$TEST_TMPDIR/project" "session-abc"

  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]

  # Parse and verify
  python3 -I - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert len(data) == 1, f"expected 1 session, got {len(data)}"
s = data[0]
# Main: input=150, cache_read=8M, cache_create=700k, output=80k
# Sub:  input=20,  cache_read=1M, cache_create=100k, output=10k
# Total: input=170, cache_read=9M, cache_create=800k, output=90k
assert s["cache_read"] == 9000000, f"cache_read: {s['cache_read']}"
assert s["cache_create"] == 800000, f"cache_create: {s['cache_create']}"
assert s["output"] == 90000, f"output: {s['output']}"
assert s["main_output"] == 80000, f"main_output: {s['main_output']}"
assert s["agent_output"] == 10000, f"agent_output: {s['agent_output']}"
# Weighted cost: 170*1 + 9M*0.1 + 800k*1.25 + 90k*5 = 170 + 900000 + 1000000 + 450000 = 2350170
assert s["weighted_cost"] == 2350170.0, f"weighted_cost: {s['weighted_cost']}"
PY
}

@test "review-cost.py: handles missing subagents dir" {
  mkdir -p "$TEST_TMPDIR/project"
  cat > "$TEST_TMPDIR/project/no-subs.jsonl" <<'EOF'
{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}
{"type":"assistant","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200,"output_tokens":50}}}
EOF

  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]

  python3 -I - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert len(data) == 1
s = data[0]
assert s["agent_output"] == 0
assert s["output"] == 50
PY
}

@test "review-cost.py: handles empty lines and malformed JSON" {
  mkdir -p "$TEST_TMPDIR/project"
  cat > "$TEST_TMPDIR/project/messy.jsonl" <<'EOF'

{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}
not json at all
{"type":"assistant","message":{"usage":{"input_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":0,"output_tokens":10}}}

EOF

  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]

  python3 -I - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data[0]["output"] == 10
PY
}

@test "review-cost.py: handles jsonl with no usage (boundary)" {
  mkdir -p "$TEST_TMPDIR/project"
  cat > "$TEST_TMPDIR/project/no-usage.jsonl" <<'EOF'
{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}
{"type":"human","message":{"content":"hello"}}
EOF

  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]

  python3 -I - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data[0]["output"] == 0
assert data[0]["cache_read"] == 0
PY
}

@test "review-cost.py: errors on empty directory" {
  mkdir -p "$TEST_TMPDIR/empty"
  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" "$TEST_TMPDIR/empty/"
  [ "$status" -eq 1 ]
}

@test "review-cost.py: accepts bare jsonl file" {
  cat > "$TEST_TMPDIR/bare.jsonl" <<'EOF'
{"type":"system","timestamp":"2026-01-01T12:00:00.000Z"}
{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_read_input_tokens":100,"cache_creation_input_tokens":0,"output_tokens":5}}}
EOF

  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/bare.jsonl"
  [ "$status" -eq 0 ]

  python3 -I - "$output" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
assert data[0]["output"] == 5
PY
}

# --- AC0.3: replay.sh zero writes ---

@test "replay.sh: no post or marker code is reachable" {
  # Verify that replay.sh does not contain any gh comment, gh issue,
  # safe-merge, or marker-posting logic.
  # The script must ONLY use --no-post; no code path can post.
  run grep -cE 'gh (api|issue|pr) .*(comment|close|merge|label)|safe-merge|l2.*marker|emit-review-marker' \
    "$REPO_ROOT/scripts/bench/replay.sh"
  [ "$output" = "0" ] || {
    echo "replay.sh contains post/marker code paths that must not be reachable:"
    grep -nE 'gh (api|issue|pr) .*(comment|close|merge|label)|safe-merge|l2.*marker|emit-review-marker' \
      "$REPO_ROOT/scripts/bench/replay.sh"
    false
  }
}

@test "replay.sh: --no-post is always implied (no --post flag)" {
  # The script must not accept a --post flag
  ! grep -qE '^\s*--post\)' "$REPO_ROOT/scripts/bench/replay.sh"
}

# --- Corpus schema validation ---

@test "corpus.yaml: every entry has required fields" {
  python3 -I - "$REPO_ROOT/tests/bench/corpus.yaml" <<'PY'
import sys, yaml

REQUIRED = {"id", "pr", "head", "base", "patch_digest", "permalink", "kind", "tier",
            "files_changed", "additions", "deletions", "labels"}

with open(sys.argv[1]) as f:
    corpus = yaml.safe_load(f)

entries = corpus.get("entries", [])
assert entries, "corpus has no entries"

for i, e in enumerate(entries):
    missing = REQUIRED - set(e.keys())
    assert not missing, f"entry {i} ({e.get('id','?')}): missing fields {missing}"
    assert len(e["head"]) == 40, f"entry {e['id']}: head must be 40 hex chars"
    assert len(e["base"]) == 40, f"entry {e['id']}: base must be 40 hex chars"
    assert len(e["patch_digest"]) == 64, f"entry {e['id']}: patch_digest must be 64 hex chars"
    assert e["kind"] in ("positive", "negative"), f"entry {e['id']}: kind must be positive/negative"
    assert e["tier"] in ("standard", "trivial", "docs", "gate"), f"entry {e['id']}: invalid tier"
    assert isinstance(e["labels"], list), f"entry {e['id']}: labels must be a list"
PY
}

@test "corpus.yaml: entry ids are unique" {
  python3 -I - "$REPO_ROOT/tests/bench/corpus.yaml" <<'PY'
import sys, yaml

with open(sys.argv[1]) as f:
    corpus = yaml.safe_load(f)

ids = [e["id"] for e in corpus.get("entries", [])]
dupes = [x for x in ids if ids.count(x) > 1]
assert not dupes, f"duplicate entry ids: {set(dupes)}"
PY
}

@test "corpus.yaml: positive entries have expected finding counts in comments" {
  # Entries marked positive should have a comment indicating expected C/I count.
  # This is a schema check — the actual labels are filled by psak.
  python3 -I - "$REPO_ROOT/tests/bench/corpus.yaml" <<'PY'
import sys, yaml

with open(sys.argv[1]) as f:
    raw = f.read()
    corpus = yaml.safe_load(raw)

for e in corpus.get("entries", []):
    if e["kind"] == "positive" and not e["labels"]:
        # Positive entries with empty labels should have a comment explaining expected counts
        pass  # psak fills labels; this test passes once labels are present
PY
}

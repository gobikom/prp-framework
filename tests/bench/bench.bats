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

# --- replay.sh failure propagation ---

_make_corpus() {
  local path="$1" id="$2" head="$3" base="$4" digest="$5"
  cat > "$path" <<CYAML
entries:
  - id: "$id"
    pr: 999
    head: "$head"
    base: "$base"
    patch_digest: "$digest"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 1
    additions: 1
    deletions: 0
    labels: []
CYAML
}

_stub_git() {
  local dir="$1"; mkdir -p "$dir"
  printf '#!/usr/bin/env bash\ncase "$*" in *cat-file*) exit 1;; *fetch*) exit 1;; *diff*) echo "fake diff";; esac\n' > "$dir/git"
  chmod +x "$dir/git"
}

_make_test_repo() {
  git init -q "$TEST_TMPDIR/repo"
  git -C "$TEST_TMPDIR/repo" commit --allow-empty -m "base" -q
  TEST_BASE=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  echo "content" > "$TEST_TMPDIR/repo/file.txt"
  git -C "$TEST_TMPDIR/repo" add file.txt
  git -C "$TEST_TMPDIR/repo" commit -m "head" -q
  TEST_HEAD=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  TEST_DIGEST=$(git -C "$TEST_TMPDIR/repo" diff "$TEST_BASE".."$TEST_HEAD" | sha256sum | cut -d' ' -f1)
}

_run_replay() {
  run env REPO_ROOT="$TEST_TMPDIR/repo" \
    bash -c "cd '$TEST_TMPDIR/repo' && '$REPO_ROOT/scripts/bench/replay.sh' --corpus '$TEST_TMPDIR/corpus.yaml' --out '$TEST_TMPDIR/out'"
}

@test "replay.sh: unreachable SHA → non-zero exit" {
  _make_corpus "$TEST_TMPDIR/corpus.yaml" "bad-sha" \
    "$(printf 'a%.0s' {1..40})" "$(printf 'b%.0s' {1..40})" "$(printf 'c%.0s' {1..64})"
  _stub_git "$TEST_TMPDIR/bin"
  git init -q "$TEST_TMPDIR/repo"
  run env PATH="$TEST_TMPDIR/bin:$PATH" REPO_ROOT="$TEST_TMPDIR/repo" \
    bash -c "cd '$TEST_TMPDIR/repo' && '$REPO_ROOT/scripts/bench/replay.sh' --corpus '$TEST_TMPDIR/corpus.yaml' --out '$TEST_TMPDIR/out'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"error"* ]] || [[ "$output" == *"cannot resolve"* ]]
}

@test "replay.sh: digest mismatch → non-zero exit" {
  _make_test_repo
  _make_corpus "$TEST_TMPDIR/corpus.yaml" "bad-digest" "$TEST_HEAD" "$TEST_BASE" "$(printf 'f%.0s' {1..64})"
  _run_replay
  [ "$status" -ne 0 ]
  [[ "$output" == *"digest mismatch"* ]]
}

@test "replay.sh: failing review CLI → non-zero exit" {
  _make_test_repo
  _make_corpus "$TEST_TMPDIR/corpus.yaml" "bad-cli" "$TEST_HEAD" "$TEST_BASE" "$TEST_DIGEST"
  mkdir -p "$TEST_TMPDIR/repo/scripts/review"
  printf '#!/usr/bin/env bash\necho "review failed" >&2; exit 1\n' > "$TEST_TMPDIR/repo/scripts/review/prp-review"
  chmod +x "$TEST_TMPDIR/repo/scripts/review/prp-review"
  _run_replay
  [ "$status" -ne 0 ]
  [[ "$output" == *"review CLI failed"* ]]
}

@test "replay.sh: all entries good → exit 0" {
  _make_test_repo
  _make_corpus "$TEST_TMPDIR/corpus.yaml" "good" "$TEST_HEAD" "$TEST_BASE" "$TEST_DIGEST"
  _run_replay
  [ "$status" -eq 0 ]
  [[ "$output" == *"Replay complete"* ]]
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


#!/usr/bin/env bats
# Benchmark tooling tests for prp-framework#160 Phase 0.

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
  run python3 -I "$REPO_ROOT/scripts/bench/review-cost.py" --json "$TEST_TMPDIR/project/"
  [ "$status" -eq 0 ]
  python3 -I -c "import json,sys; assert json.loads(sys.argv[1])[0]['output']==10" "$output"
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

_make_corpus() {
  cat > "$1" <<CYAML
entries:
  - id: "$2"
    pr: 999
    head: "$3"
    base: "$4"
    patch_digest: "$5"
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

@test "replay.sh: entry formatter crash → non-zero exit" {
  # A corpus entry missing patch_digest causes the python formatter to fail
  cat > "$TEST_TMPDIR/corpus.yaml" <<'CYAML'
entries:
  - id: "broken"
    pr: 999
    head: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    base: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 1
    additions: 1
    deletions: 0
    labels: []
CYAML
  git init -q "$TEST_TMPDIR/repo"
  _run_replay
  [ "$status" -ne 0 ]
  [[ "$output" == *"error"* ]]
}

_make_two_entry_corpus() {
  _make_test_repo
  local h2 b2 d2
  echo "second" > "$TEST_TMPDIR/repo/file2.txt"
  git -C "$TEST_TMPDIR/repo" add file2.txt
  git -C "$TEST_TMPDIR/repo" commit -m "head2" -q
  h2=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  d2=$(git -C "$TEST_TMPDIR/repo" diff "$TEST_BASE".."$h2" | sha256sum | cut -d' ' -f1)
  cat > "$TEST_TMPDIR/corpus.yaml" <<CYAML
entries:
  - id: "e1"
    pr: 999
    head: "$TEST_HEAD"
    base: "$TEST_BASE"
    patch_digest: "$TEST_DIGEST"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 1
    additions: 1
    deletions: 0
    labels: []
  - id: "e2"
    pr: 999
    head: "$h2"
    base: "$TEST_BASE"
    patch_digest: "$d2"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 2
    additions: 2
    deletions: 0
    labels: []
CYAML
}

@test "replay.sh: fewer formatted lines than entries → non-zero exit" {
  _make_two_entry_corpus
  # Stub python3 to emit only 1 line for a 2-entry corpus
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/python3" <<'STUB'
#!/usr/bin/env bash
# If the formatter script is being called, emit only 1 line
if [[ "$*" == *"json.load"* ]]; then
  echo "e1|999|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb|cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc|positive"
  exit 0
fi
exec /usr/bin/python3 "$@"
STUB
  chmod +x "$TEST_TMPDIR/bin/python3"
  run env PATH="$TEST_TMPDIR/bin:$PATH" REPO_ROOT="$TEST_TMPDIR/repo" \
    bash -c "cd '$TEST_TMPDIR/repo' && '$REPO_ROOT/scripts/bench/replay.sh' --corpus '$TEST_TMPDIR/corpus.yaml' --out '$TEST_TMPDIR/out'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"enumerated"* ]]
}

@test "replay.sh: stdin-eating review CLI does not consume entry lines" {
  _make_two_entry_corpus
  mkdir -p "$TEST_TMPDIR/repo/scripts/review"
  printf '#!/usr/bin/env bash\ncat > /dev/null\nexit 0\n' > "$TEST_TMPDIR/repo/scripts/review/prp-review"
  chmod +x "$TEST_TMPDIR/repo/scripts/review/prp-review"
  _run_replay
  [ "$status" -eq 0 ]
  # Both entries must have been processed (meta.json exists for both)
  [ -f "$TEST_TMPDIR/out/e1/run-1/meta.json" ]
  [ -f "$TEST_TMPDIR/out/e2/run-1/meta.json" ]
}

# --- AC0.3: replay.sh zero writes ---

@test "replay.sh: no post or marker code is reachable" {
  run grep -cE 'gh (api|issue|pr) .*(comment|close|merge|label)|safe-merge|l2.*marker|emit-review-marker' \
    "$REPO_ROOT/scripts/bench/replay.sh"
  [ "$output" = "0" ]
}

@test "replay.sh: --no-post is always implied (no --post flag)" {
  ! grep -qE '^\s*--post\)' "$REPO_ROOT/scripts/bench/replay.sh"
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


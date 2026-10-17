#!/usr/bin/env bats
# Benchmark tooling tests for prp-framework#160 Phase 0.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() { TEST_TMPDIR="$(mktemp -d)"; }
teardown() { rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

# --- freeze-head.sh ---

@test "freeze-head.sh: correct digest and stats" {
  git init -q "$TEST_TMPDIR/repo"
  git -C "$TEST_TMPDIR/repo" commit --allow-empty -m "base" -q
  local base; base=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  printf 'hello\nworld\n' > "$TEST_TMPDIR/repo/file.txt"
  git -C "$TEST_TMPDIR/repo" add file.txt
  git -C "$TEST_TMPDIR/repo" commit -m "head" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  local expect_digest; expect_digest=$(printf '%s' "$(git -C "$TEST_TMPDIR/repo" diff "$base".."$head")" | sha256sum | cut -d' ' -f1)
  run "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$base"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$expect_digest"* ]]
  [[ "$output" == *"files_changed: 1"* ]]
  [[ "$output" == *"additions: 2"* ]]
  [[ "$output" == *"deletions: 0"* ]]
}

@test "freeze-head.sh: deterministic (same output twice)" {
  git init -q "$TEST_TMPDIR/repo"
  git -C "$TEST_TMPDIR/repo" commit --allow-empty -m "base" -q
  local base; base=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  echo "data" > "$TEST_TMPDIR/repo/f.txt"
  git -C "$TEST_TMPDIR/repo" add f.txt
  git -C "$TEST_TMPDIR/repo" commit -m "head" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  local out1; out1=$("$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$base")
  local out2; out2=$("$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$base")
  [ "$out1" = "$out2" ]
}

@test "freeze-head.sh: unreachable SHA → non-zero exit" {
  git init -q "$TEST_TMPDIR/repo"
  run "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$(printf 'a%.0s' {1..40})" "$(printf 'b%.0s' {1..40})"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot resolve"* ]]
}

@test "freeze-head.sh: empty diff → non-zero exit" {
  git init -q "$TEST_TMPDIR/repo"
  git -C "$TEST_TMPDIR/repo" commit --allow-empty -m "only" -q
  local sha; sha=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  run "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$sha" "$sha"
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty diff"* ]]
}

# --- corpus ---

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

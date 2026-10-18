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

_make_repo_with_commits() {
  git init -q "$TEST_TMPDIR/repo"
  git -C "$TEST_TMPDIR/repo" commit --allow-empty -m "base" -q
  REPO_BASE=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
}

@test "freeze-head.sh: two files with known +3/-1 and +2/-0" {
  _make_repo_with_commits
  printf 'a\nb\nc\n' > "$TEST_TMPDIR/repo/x.txt"
  printf 'old\n' > "$TEST_TMPDIR/repo/y.txt"
  git -C "$TEST_TMPDIR/repo" add x.txt y.txt
  git -C "$TEST_TMPDIR/repo" commit -m "add" -q
  printf 'a\nb\nc\ndd\nee\n' > "$TEST_TMPDIR/repo/x.txt"
  printf '' > "$TEST_TMPDIR/repo/y.txt"
  git -C "$TEST_TMPDIR/repo" add x.txt y.txt
  git -C "$TEST_TMPDIR/repo" commit -m "edit" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  local mid; mid=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD~1)
  run "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$mid"
  [ "$status" -eq 0 ]
  [[ "$output" == *"files_changed: 2"* ]]
  [[ "$output" == *"additions: 2"* ]]
  [[ "$output" == *"deletions: 1"* ]]
}

@test "freeze-head.sh: deletion-only diff → additions 0" {
  _make_repo_with_commits
  printf 'line1\nline2\nline3\n' > "$TEST_TMPDIR/repo/del.txt"
  git -C "$TEST_TMPDIR/repo" add del.txt
  git -C "$TEST_TMPDIR/repo" commit -m "add" -q
  local mid; mid=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  git -C "$TEST_TMPDIR/repo" rm del.txt -q
  git -C "$TEST_TMPDIR/repo" commit -m "rm" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  run "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$mid"
  [ "$status" -eq 0 ]
  [[ "$output" == *"additions: 0"* ]]
  [[ "$output" == *"deletions: 3"* ]]
}

@test "freeze-head.sh: binary + text file" {
  _make_repo_with_commits
  # Generate a proper binary (null bytes force git to treat it as binary)
  printf '\x00\x01\x02\x03\x04\x05' > "$TEST_TMPDIR/repo/bin.dat"
  printf 'text\n' > "$TEST_TMPDIR/repo/t.txt"
  git -C "$TEST_TMPDIR/repo" add bin.dat t.txt
  git -C "$TEST_TMPDIR/repo" commit -m "add" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  run "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$REPO_BASE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"files_changed: 2"* ]]
  [[ "$output" == *"additions: 1"* ]]
  [[ "$output" == *"deletions: 0"* ]]
}

@test "freeze-head.sh: locale-independent output" {
  _make_repo_with_commits
  echo "lc" > "$TEST_TMPDIR/repo/f.txt"
  git -C "$TEST_TMPDIR/repo" add f.txt
  git -C "$TEST_TMPDIR/repo" commit -m "add" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  local out_c; out_c=$(LC_ALL=C "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$REPO_BASE")
  local out_lang; out_lang=$(LANGUAGE=de "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$REPO_BASE")
  [ "$out_c" = "$out_lang" ]
}

@test "freeze-head.sh: malformed numstat line → non-zero exit" {
  _make_repo_with_commits
  echo "x" > "$TEST_TMPDIR/repo/f.txt"
  git -C "$TEST_TMPDIR/repo" add f.txt
  git -C "$TEST_TMPDIR/repo" commit -m "add" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--numstat"* ]]; then
  echo "CORRUPT LINE HERE"
  exit 0
fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$TEST_TMPDIR/bin/git"
  run env PATH="$TEST_TMPDIR/bin:$PATH" "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$REPO_BASE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unparseable numstat"* ]] || [[ "$output" == *"CORRUPT"* ]]
}

@test "freeze-head.sh: numstat exit failure → non-zero exit" {
  _make_repo_with_commits
  echo "y" > "$TEST_TMPDIR/repo/g.txt"
  git -C "$TEST_TMPDIR/repo" add g.txt
  git -C "$TEST_TMPDIR/repo" commit -m "add" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--numstat"* ]]; then exit 1; fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$TEST_TMPDIR/bin/git"
  run env PATH="$TEST_TMPDIR/bin:$PATH" "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$REPO_BASE"
  [ "$status" -ne 0 ]
}

@test "freeze-head.sh: numstat prints nothing → non-zero exit" {
  _make_repo_with_commits
  echo "z" > "$TEST_TMPDIR/repo/h.txt"
  git -C "$TEST_TMPDIR/repo" add h.txt
  git -C "$TEST_TMPDIR/repo" commit -m "add" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--numstat"* ]]; then exit 0; fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$TEST_TMPDIR/bin/git"
  run env PATH="$TEST_TMPDIR/bin:$PATH" "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$REPO_BASE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no files"* ]]
}

@test "freeze-head.sh: empty first field in numstat → non-zero exit" {
  _make_repo_with_commits
  echo "w" > "$TEST_TMPDIR/repo/i.txt"
  git -C "$TEST_TMPDIR/repo" add i.txt
  git -C "$TEST_TMPDIR/repo" commit -m "add" -q
  local head; head=$(git -C "$TEST_TMPDIR/repo" rev-parse HEAD)
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/git" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--numstat"* ]]; then
  printf '\t0\tfile.txt\n'
  exit 0
fi
exec /usr/bin/git "$@"
STUB
  chmod +x "$TEST_TMPDIR/bin/git"
  run env PATH="$TEST_TMPDIR/bin:$PATH" "$REPO_ROOT/scripts/bench/freeze-head.sh" "$TEST_TMPDIR/repo" "$head" "$REPO_BASE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unparseable"* ]]
}

# --- corpus (uses check-corpus.py for all rules) ---

CHECK="$REPO_ROOT/tests/bench/check-corpus.py"

_valid_entry='  - id: "test-1"
    pr: 1
    head: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    base: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    patch_digest: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 1
    additions: 1
    deletions: 0
    labels:
      - file: "x.txt"
        lines: [1, 2]
        defect: "bug"
        severity: "critical"
        family: "f"
        source_pass: ["code-reviewer"]
        comment_url: "https://example.com"'

_run_checker() {
  run python3 -I "$CHECK" "$TEST_TMPDIR/corpus.yaml"
  [[ "$output" != *"Traceback"* ]]
}

_valid_entry2='  - id: "test-2"
    pr: 2
    head: "dddddddddddddddddddddddddddddddddddddddd"
    base: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    patch_digest: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    permalink: "https://example.com"
    kind: "negative"
    tier: "trivial"
    files_changed: 1
    additions: 0
    deletions: 0
    labels: []'

@test "corpus: C6 real corpus.yaml passes checker" {
  run python3 -I "$CHECK" "$REPO_ROOT/tests/bench/corpus.yaml"
  [ "$status" -eq 0 ]
}

@test "corpus: severity totals match expected counts" {
  python3 -I - "$REPO_ROOT/tests/bench/corpus.yaml" <<'PY'
import sys, yaml
EXPECT_CRITICAL, EXPECT_IMPORTANT = 5, 9
with open(sys.argv[1]) as f:
    corpus = yaml.safe_load(f)
c = sum(1 for e in corpus["entries"] for l in e["labels"] if l["severity"]=="critical")
i = sum(1 for e in corpus["entries"] for l in e["labels"] if l["severity"]=="important")
assert c == EXPECT_CRITICAL, f"critical: {c} != {EXPECT_CRITICAL}"
assert i == EXPECT_IMPORTANT, f"important: {i} != {EXPECT_IMPORTANT}"
PY
}

@test "corpus: C2 negative entry with a label → fails" {
  printf 'entries:\n%s\n' "${_valid_entry//kind: \"positive\"/kind: \"negative\"}" > "$TEST_TMPDIR/corpus.yaml"
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"negative entry must have labels"* ]]
}

@test "corpus: C3 unknown kind → fails" {
  printf 'entries:\n%s\n' "${_valid_entry//kind: \"positive\"/kind: \"maybe\"}" > "$TEST_TMPDIR/corpus.yaml"
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid kind"* ]]
}

@test "corpus: C4 label with no severity key → fails" {
  local e="${_valid_entry}"
  # Remove the severity line
  printf 'entries:\n%s\n' "$(echo "$e" | grep -v 'severity:')" > "$TEST_TMPDIR/corpus.yaml"
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing"* ]]
}

@test "corpus: C5 critical+important != total labels → fails" {
  printf 'entries:\n%s\n' "${_valid_entry//severity: \"critical\"/severity: \"medium\"}" > "$TEST_TMPDIR/corpus.yaml"
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in"* ]]
}

@test "corpus: D1 duplicate ids → error" {
  printf 'entries:\n%s\n%s\n' "$_valid_entry" "${_valid_entry}" > "$TEST_TMPDIR/corpus.yaml"
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate"* ]]
}

@test "corpus: D2 entry missing labels key → error names id" {
  cat > "$TEST_TMPDIR/corpus.yaml" <<'CYAML'
entries:
  - id: "no-labels"
    pr: 1
    head: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    base: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    patch_digest: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 1
    additions: 1
    deletions: 0
CYAML
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"no-labels"* ]]
}

@test "corpus: D3 labels is a string → error" {
  cat > "$TEST_TMPDIR/corpus.yaml" <<'CYAML'
entries:
  - id: "str-labels"
    pr: 1
    head: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    base: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    patch_digest: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 1
    additions: 1
    deletions: 0
    labels: "not-a-list"
CYAML
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"labels must be a list"* ]]
}

@test "corpus: D4 labels contains an int → error" {
  cat > "$TEST_TMPDIR/corpus.yaml" <<'CYAML'
entries:
  - id: "int-label"
    pr: 1
    head: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    base: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    patch_digest: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 1
    additions: 1
    deletions: 0
    labels: [1, 2]
CYAML
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected a mapping"* ]]
}

@test "corpus: D5 duplicate ids AND missing labels → both reported" {
  cat > "$TEST_TMPDIR/corpus.yaml" <<CYAML
entries:
$_valid_entry
  - id: "test-1"
    pr: 2
    head: "dddddddddddddddddddddddddddddddddddddddd"
    base: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    patch_digest: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    permalink: "https://example.com"
    kind: "positive"
    tier: "standard"
    files_changed: 1
    additions: 1
    deletions: 0
CYAML
  _run_checker
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate"* ]]
  [[ "$output" == *"missing"* ]] || [[ "$output" == *"test-1"* ]]
}

@test "corpus: D6 top-level is a list → clean error" {
  printf '%s\n%s\n' "- item1" "- item2" > "$TEST_TMPDIR/corpus.yaml"
  _run_checker
  [ "$status" -ne 0 ]
}

@test "corpus: D7 invalid YAML → clean error" {
  printf '%s\n%s\n' "{{{" "invalid: [yaml" > "$TEST_TMPDIR/corpus.yaml"
  _run_checker
  [ "$status" -ne 0 ]
}

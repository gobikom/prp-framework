#!/usr/bin/env bats
# Generator validation tests (prp-framework#156 round-1 fix 3).
#
# Both failure modes are reproduced against a TEMP copy of the tree — never
# against the real adapters/ tree — so the tests cannot clobber real artifacts:
#   1. a typo'd adapters.yml key must exit non-zero with a clear error
#      (known-key validation), instead of silently dropping the value and
#      generating prose that no longer matches the dispatch blocks;
#   2. a literal {AGENT_BLOCKING_PARAM}/{AGENT_BLOCKING_PROSE} surviving into
#      any generated output must exit non-zero (unreplaced-placeholder guard).
#
# Run: bats tests/scripts/generate-adapters.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

# make_tree — a runnable copy of the generator's inputs in the test tmpdir.
make_tree() {
  mkdir -p "$BATS_TEST_TMPDIR/tree"
  cp -r "$ROOT/adapters.yml" "$ROOT/scripts" "$ROOT/prompts" "$BATS_TEST_TMPDIR/tree/"
}

@test "a typo'd adapters.yml adapter key fails generation with a clear error (#156 round 1)" {
  make_tree
  y="$BATS_TEST_TMPDIR/tree/adapters.yml"
  sed -i 's/agent_blocking_prose_claude:/agent_blocking_prase_claude:/' "$y"
  grep -q 'agent_blocking_prase_claude:' "$y" # the mutation really happened
  err_out="$BATS_TEST_TMPDIR/err"
  rc=0
  (cd "$BATS_TEST_TMPDIR/tree" && python3 scripts/generate-adapters.py >/dev/null 2>"$err_out") || rc=$?
  [ "$rc" -ne 0 ] || {
    echo "typo'd key did not fail generation (exit 0)" >&2
    return 1
  }
  grep -q "unknown keys" "$err_out" || {
    echo "error output does not name the unknown key:" >&2
    cat "$err_out" >&2
    return 1
  }
}

@test "a self-referential agent_blocking_param value fails generation (#156 round 1)" {
  make_tree
  y="$BATS_TEST_TMPDIR/tree/adapters.yml"
  sed -i 's|agent_blocking_param: "  run_in_background=false,\\n"|agent_blocking_param: "{AGENT_BLOCKING_PARAM}"|' "$y"
  grep -q 'agent_blocking_param: "{AGENT_BLOCKING_PARAM}"' "$y" # mutation happened
  err_out="$BATS_TEST_TMPDIR/err"
  rc=0
  (cd "$BATS_TEST_TMPDIR/tree" && python3 scripts/generate-adapters.py >/dev/null 2>"$err_out") || rc=$?
  [ "$rc" -ne 0 ] || {
    echo "literal placeholder in output did not fail generation (exit 0)" >&2
    return 1
  }
  grep -q "survived substitution" "$err_out" || {
    echo "error output does not mention the surviving placeholder:" >&2
    cat "$err_out" >&2
    return 1
  }
}

@test "an unmutated temp copy generates cleanly (control)" {
  make_tree
  rc=0
  (cd "$BATS_TEST_TMPDIR/tree" && python3 scripts/generate-adapters.py >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 0 ]
}

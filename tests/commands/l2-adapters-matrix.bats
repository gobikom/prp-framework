#!/usr/bin/env bats
# Cross-adapter matrix for tests/commands/l2-comments.bats (prp-framework#151).
#
# l2-comments.bats parametrises on $L2_ADAPTER but a plain `bats` run only ever
# exercises the claude-code default. This file is the harness that actually
# EXECUTES the full l2-comments.bats suite once per EXPECTED_FILES entry, via a
# nested bats invocation -- so round-cap/pass-budget/FATAL-guard behaviour is
# genuinely run against every one of the 7 files, not merely grepped.
#
# Nested bats works on this host; BATS_* env vars are cleared before the
# nested call so the inner run doesn't inherit the outer run's test-numbering
# state.
#
# Run: bats tests/commands/l2-adapters-matrix.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
source "$ROOT/tests/helpers/fence.bash"

EXPECTED_FILES="
prompts/review-agents.md
adapters/antigravity/prp-review-agents.md
adapters/claude-code/prp-review-agents.md
adapters/codex/prp-review-agents/SKILL.md
adapters/gemini/review-agents.toml
adapters/opencode/review-agents.md
adapters/thclaws/prp-review-agents/SKILL.md
"

# The 7 files this matrix actually exercises below, as a plain string -- the
# set-equality test asserts this equals EXPECTED_FILES, so a renamed/added/
# removed adapter fails loudly instead of silently skipping coverage.
MATRIX_FILES="prompts/review-agents.md
adapters/antigravity/prp-review-agents.md
adapters/claude-code/prp-review-agents.md
adapters/codex/prp-review-agents/SKILL.md
adapters/gemini/review-agents.toml
adapters/opencode/review-agents.md
adapters/thclaws/prp-review-agents/SKILL.md"

# run_matrix FILE -> runs the full l2-comments.bats suite with L2_ADAPTER=FILE,
# as a nested bats process, and asserts: exit 0, TAP plan line "1..57" (the
# suite's current test count -- a drift here means a test was added/removed
# without updating this harness), and no "not ok" line.
run_matrix() {
  local file="$1" out status
  out="$(cd "$ROOT" && env -u BATS_TEST_FILENAME -u BATS_TEST_NAMES \
    -u BATS_SUITE_TEST_NUMBER -u BATS_TEST_NUMBER -u BATS_RUN_TMPDIR \
    L2_ADAPTER="$file" bats --tap tests/commands/l2-comments.bats 2>&1)"
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "nested bats failed for $file (status=$status):" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi
  if ! printf '%s\n' "$out" | grep -qx '1\.\.57'; then
    echo "expected TAP plan '1..57' for $file, got:" >&2
    printf '%s\n' "$out" | head -5 >&2
    return 1
  fi
  if printf '%s\n' "$out" | grep -q '^not ok'; then
    echo "nested run for $file reported failing tests:" >&2
    printf '%s\n' "$out" | grep '^not ok' >&2
    return 1
  fi
}

@test "l2-comments.bats passes in full against prompts/review-agents.md" {
  run_matrix "prompts/review-agents.md"
}

@test "l2-comments.bats passes in full against adapters/antigravity/prp-review-agents.md" {
  run_matrix "adapters/antigravity/prp-review-agents.md"
}

@test "l2-comments.bats passes in full against adapters/claude-code/prp-review-agents.md" {
  run_matrix "adapters/claude-code/prp-review-agents.md"
}

@test "l2-comments.bats passes in full against adapters/codex/prp-review-agents/SKILL.md" {
  run_matrix "adapters/codex/prp-review-agents/SKILL.md"
}

@test "l2-comments.bats passes in full against adapters/gemini/review-agents.toml" {
  run_matrix "adapters/gemini/review-agents.toml"
}

@test "l2-comments.bats passes in full against adapters/opencode/review-agents.md" {
  run_matrix "adapters/opencode/review-agents.md"
}

@test "l2-comments.bats passes in full against adapters/thclaws/prp-review-agents/SKILL.md" {
  run_matrix "adapters/thclaws/prp-review-agents/SKILL.md"
}

@test "the matrix covers EXPECTED_FILES exactly (set equality)" {
  diff <(printf '%s\n' "$EXPECTED_FILES" | sed '/^$/d' | sort) \
       <(printf '%s\n' "$MATRIX_FILES" | sort)
}

@test "Phase 2.0 / Step A / Step C / pass-deadline fences are byte-identical across all 7 files" {
  local sections=("### 2.0 Capture the Reviewed Head" "**Step A" "**Step C" "### 2.2.0 Pass Budget")
  local section f cur prev prev_file
  for section in "${sections[@]}"; do
    prev=""
    prev_file=""
    for f in $EXPECTED_FILES; do
      [ -z "$f" ] && continue
      cur="$(fence "$ROOT/$f" "$section")"
      if [ -n "$prev_file" ] && [ "$cur" != "$prev" ]; then
        echo "fence mismatch for '$section': $f differs from $prev_file" >&2
        return 1
      fi
      prev="$cur"
      prev_file="$f"
    done
  done
}

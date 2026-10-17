#!/usr/bin/env bats
# Generator boundary tests for the round-2 re-plan (prp-framework#156):
# generation-time placeholders are a CLOSED registry (GEN_PLACEHOLDERS) in a
# reserved namespace — regex {agent_[a-z0-9_]*} with re.I, so the underscore
# is part of the namespace and the prose token {agent} (no underscore) stays
# outside it and generates unchanged.
#
# One test per row of the re-plan's boundary table, plus the {agent} arm and
# the positive test. EVERY test runs against a temp copy of the tree (temp
# copy only — never the real adapters/); the canary row also proves the
# generator READS the shared top-level prose key (the round-2 Important).
#
# Round 4 (widened invariant: the generator never exits 0 on output it could
# not build correctly — every input it fails to read or parse is an error
# counted in stats["errors"], never a silent skip): broken overlay frontmatter
# and missing/unreadable prompts for configured commands are errors (exit 1,
# error names the file); a single run reports every broken input.
#
# Run: bats tests/scripts/generate-adapters.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PROMPT="$ROOT/prompts/review-agents.md"
CLAUDE_MD="adapters/claude-code/prp-review-agents.md"

# make_tree [name] — a runnable copy of adapters.yml + scripts + prompts in
# the test tmpdir; the mutation hooks below edit only this copy.
make_tree() { # [name]
  local dir="$BATS_TEST_TMPDIR/${1:-tree}"
  mkdir -p "$dir"
  cp -r "$ROOT/adapters.yml" "$ROOT/scripts" "$ROOT/prompts" "$dir/"
  TREE="$dir"
}

# gen — run the generator inside the temp tree, rc into $rc, stderr into $err.
gen() {
  rc=0
  (cd "$TREE" && python3 scripts/generate-adapters.py >"$BATS_TEST_TMPDIR/gen.out" 2>"$BATS_TEST_TMPDIR/err") || rc=$?
  err="$(cat "$BATS_TEST_TMPDIR/err" 2>/dev/null)"
  out="$(cat "$BATS_TEST_TMPDIR/gen.out" 2>/dev/null)"
}

# prompt_sub BEFORE AFTER — apply a prompt mutation and prove it took.
prompt_sub() { # <before> <after>
  sed -i "s|$1|$2|g" "$TREE/prompts/review-agents.md"
  grep -qF "$2" "$TREE/prompts/review-agents.md" || {
    echo "prompt mutation did not take: $1 -> $2" >&2
    return 1
  }
}

# ── row: correct (today's tree) ────────────────────────────────────────────

@test "correct tree: exit 0; claude-code 10/10 params + claim; other 5 have 0 params + the neutral sentence" {
  make_tree
  gen
  [ "$rc" -eq 0 ] || { echo "generator failed: $err" >&2; return 1; }
  local d="$TREE/adapters/claude-code/prp-review-agents.md"
  local dispatches params
  dispatches=$(grep -c '^Agent($' "$d")
  params=$(grep -c '^  run_in_background=false,$' "$d")
  [ "$dispatches" -eq 10 ] && [ "$params" -eq 10 ]
  grep -qF 'therefore passes' "$d"  # the scoped claim
  # the other five: zero params, neutral sentence present, no claim
  local f
  for f in \
    adapters/antigravity/prp-review-agents.md \
    adapters/codex/prp-review-agents/SKILL.md \
    adapters/gemini/review-agents.toml \
    adapters/opencode/review-agents.md \
    adapters/thclaws/prp-review-agents/SKILL.md
  do
    [ "$(grep -c '^  run_in_background=false,$' "$TREE/$f")" -eq 0 ]
    grep -qF 'In the Claude Code adapter every Agent' "$TREE/$f"
    [ "$(grep -cF 'therefore passes' "$TREE/$f")" -eq 0 ]
  done
  # and nothing anywhere contains a brace token containing BLOCKING
  ! grep -rE '\{[A-Za-z0-9_]*BLOCKING[A-Za-z0-9_]*\}' "$TREE/adapters"
}

@test "positive: claude-code adapter has the scoped claim; no generated adapter contains a brace token containing BLOCKING" {
  # This is the test that FAILS on the prose-prefix-typo tree ({AGNT_BLOCKING_PROSE}
  # outside the namespace): the claim disappears and the literal brace token ships.
  make_tree
  gen
  [ "$rc" -eq 0 ] || { echo "generator failed: $err" >&2; return 1; }
  grep -qF 'therefore passes' "$TREE/adapters/claude-code/prp-review-agents.md"
  ! grep -rE '\{[A-Za-z0-9_]*BLOCKING[A-Za-z0-9_]*\}' "$TREE/adapters"
}

# ── row: suffix typo ──────────────────────────────────────────────────────

@test "suffix typo {AGENT_BLOCKING_PARAMM}: exit 1, error names the token and the file" {
  make_tree
  prompt_sub '{AGENT_BLOCKING_PARAM}' '{AGENT_BLOCKING_PARAMM}'
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'{AGENT_BLOCKING_PARAMM}'" || { echo "error does not name the token: $err" >&2; return 1; }
  echo "$err" | grep -qF 'prompts/review-agents.md' || { echo "error does not name the file: $err" >&2; return 1; }
}

# ── row: case variant ─────────────────────────────────────────────────────

@test "case variant {agent_blocking_param} / {Agent_Blocking_Param}: exit 1" {
  make_tree case1
  prompt_sub '{AGENT_BLOCKING_PARAM}' '{agent_blocking_param}'
  gen
  [ "$rc" -eq 1 ] || { echo "lowercase variant: expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'{agent_blocking_param}'"
  make_tree case2
  prompt_sub '{AGENT_BLOCKING_PARAM}' '{Agent_Blocking_Param}'
  gen
  [ "$rc" -eq 1 ] || { echo "mixed-case variant: expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'{Agent_Blocking_Param}'"
}

# ── row: unknown name in namespace ────────────────────────────────────────

@test "unknown name {AGENT_FOO}: exit 1" {
  make_tree
  printf '\nprobe {AGENT_FOO}\n' >> "$TREE/prompts/review-agents.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'{AGENT_FOO}'"
}

# ── row: prefix typo (outside the namespace) ──────────────────────────────

@test "prefix typo {AGNT_BLOCKING_PARAM}: generator exit 0 by design; review-rounds count test FAILS on the temp tree" {
  # The namespace covers only {agent_*} tokens — a prefix typo is outside it,
  # so the generator CANNOT catch it (by design; runtime placeholders like
  # {NUMBER} share this shape). The safety net is the bats structure test:
  # review-rounds.bats counts Agent( dispatch blocks vs run_in_background
  # parameters. review-rounds.bats resolves ROOT from its own location, so a
  # copy placed inside the temp tree at tests/commands/ sees the TEMP tree's
  # adapters — where dispatches=10 and params=0, so the count test fails.
  make_tree
  prompt_sub '{AGENT_BLOCKING_PARAM}' '{AGNT_BLOCKING_PARAM}'
  gen
  [ "$rc" -eq 0 ] || { echo "generator should exit 0 (token outside namespace), got $rc: $err" >&2; return 1; }
  local d="$TREE/adapters/claude-code/prp-review-agents.md"
  [ "$(grep -c '^Agent($' "$d")" -eq 10 ]
  [ "$(grep -c '^  run_in_background=false,$' "$d")" -eq 0 ]
  grep -qF '{AGNT_BLOCKING_PARAM}' "$d"  # the literal ships into the output
  # run the REAL count test against the temp tree and require it to FAIL
  mkdir -p "$TREE/tests/commands"
  cp "$ROOT/tests/commands/review-rounds.bats" "$TREE/tests/commands/"
  rr_rc=0
  bats --filter 'every Agent dispatch in the claude-code adapter passes' \
    "$TREE/tests/commands/review-rounds.bats" >"$BATS_TEST_TMPDIR/rr.out" 2>&1 || rr_rc=$?
  [ "$rr_rc" -ne 0 ] || {
    echo "review-rounds count test PASSED on the typo tree — the safety net is broken" >&2
    cat "$BATS_TEST_TMPDIR/rr.out" >&2
    return 1
  }
  grep -q 'dispatches: 10, parameters: 0' "$BATS_TEST_TMPDIR/rr.out" || {
    echo "count test failed for an unexpected reason:" >&2
    cat "$BATS_TEST_TMPDIR/rr.out" >&2
    return 1
  }
}

@test "prose prefix typo {AGNT_BLOCKING_PROSE}: the positive test fails (claim gone, brace token ships)" {
  make_tree
  prompt_sub '{AGENT_BLOCKING_PROSE}' '{AGNT_BLOCKING_PROSE}'
  gen
  [ "$rc" -eq 0 ] || { echo "generator should exit 0 (outside namespace), got $rc: $err" >&2; return 1; }
  local d="$TREE/adapters/claude-code/prp-review-agents.md"
  # claim gone (would fail the positive test's first assertion)
  [ "$(grep -cF 'therefore passes' "$d")" -eq 0 ]
  # literal brace token ships (would fail its second assertion)
  grep -qF '{AGNT_BLOCKING_PROSE}' "$d"
}

# ── row: missing config value ─────────────────────────────────────────────

@test "missing prose config value: exit 1 naming the key (claude stanza claim / top-level neutral)" {
  make_tree missing-claude
  grep -v 'agent_blocking_prose_claude:' "$ROOT/adapters.yml" > "$TREE/adapters.yml"
  gen
  [ "$rc" -eq 1 ] || { echo "missing claude claim: expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'agent_blocking_prose_claude'" || { echo "error does not name the key: $err" >&2; return 1; }

  make_tree missing-other
  grep -v '^agent_blocking_prose_other:' "$ROOT/adapters.yml" > "$TREE/adapters.yml"
  gen
  [ "$rc" -eq 1 ] || { echo "missing neutral sentence: expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'agent_blocking_prose_other'" || { echo "error does not name the key: $err" >&2; return 1; }
}

# ── row: canary (the round-2 Important — the value must be READ) ──────────

@test "canary: changing the top-level neutral prose value appears in all 5 non-claude adapters" {
  make_tree
  sed -i 's/^agent_blocking_prose_other: " In the/agent_blocking_prose_other: " CANARYPROSE In the/' "$TREE/adapters.yml"
  grep -q 'CANARYPROSE' "$TREE/adapters.yml" || { echo "canary mutation did not take" >&2; return 1; }
  gen
  [ "$rc" -eq 0 ] || { echo "generator failed: $err" >&2; return 1; }
  local f
  for f in \
    adapters/antigravity/prp-review-agents.md \
    adapters/codex/prp-review-agents/SKILL.md \
    adapters/gemini/review-agents.toml \
    adapters/opencode/review-agents.md \
    adapters/thclaws/prp-review-agents/SKILL.md
  do
    grep -q 'CANARYPROSE' "$TREE/$f" || { echo "canary missing from $f — the generator is not reading the top-level key" >&2; return 1; }
  done
  # claude-code keeps the claim, not the neutral canary
  ! grep -q 'CANARYPROSE' "$TREE/adapters/claude-code/prp-review-agents.md"
}

# ── the {agent} arm (no underscore — outside the namespace) ───────────────

@test "{agent} (no underscore) is outside the namespace and generates unchanged" {
  make_tree
  gen
  [ "$rc" -eq 0 ] || { echo "generator failed: $err" >&2; return 1; }
  local n=0 f
  for f in \
    adapters/antigravity/prp-review-agents.md \
    adapters/claude-code/prp-review-agents.md \
    adapters/codex/prp-review-agents/SKILL.md \
    adapters/gemini/review-agents.toml \
    adapters/opencode/review-agents.md \
    adapters/thclaws/prp-review-agents/SKILL.md
  do
    grep -qF 'waiting on {agent}' "$TREE/$f" || { echo "{agent} missing from $f" >&2; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 6 ]
}

# ── round-4 widened invariant: no silent exit 0 on unreadable input ───────

@test "broken overlay frontmatter: exit 1, error names the overlay file and the YAML error (round 4)" {
  make_tree
  printf -- '---\ncommand: [plan\n---\n# objective\nbroken\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'prompts/overlays/claude-code/plan.md' || { echo "error does not name the overlay file: $err" >&2; return 1; }
  echo "$err" | grep -qF 'invalid YAML frontmatter in overlay' || { echo "error does not say what failed: $err" >&2; return 1; }
}

@test "missing prompt for a configured command: exit 1, error names the file; one run reports every broken input (round 4)" {
  make_tree
  rm "$TREE/prompts/qa.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "prompt file for configured command 'qa' is missing: prompts/qa.md" || { echo "error does not name the file: $err" >&2; return 1; }
  # widened invariant: counted in stats["errors"] — 6 adapters x 1 missing prompt = 6
  echo "$out" | grep -qE "Results: .*6 errors" || { echo "missing prompt not counted in stats errors: $(echo "$out" | tail -1)" >&2; return 1; }
}

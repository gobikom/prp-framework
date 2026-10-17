#!/usr/bin/env bats
# Generator fail-loud tests (re-routed from prp-framework#156 as PR A,
# generator correctness): the generator never exits 0 on input it cannot
# read or parse, or on output that does not pass validate_generated.
#
# Rounds covered (see .prp-output/plans/generator-fail-loud.plan.md):
#   round 4 — broken overlay frontmatter / missing or unreadable prompt are
#              errors counted in stats["errors"], never silent skips;
#   round 6 — output-side check validate_generated (non-empty body (a),
#              non-empty description (b)) + the input table rows;
#   round 7 — frontmatter splits ONLY on lines exactly `---`;
#   round 8 — one splitter, split_frontmatter(), no whole-text-as-body
#              fallback (boundary table below);
#   round 9 — an INDENTED `---` delimiter anywhere in the frontmatter
#              region is an error naming the file and line (it previously
#              parsed as "no frontmatter" and dropped the metadata).
#
# PR B of the stack (this branch) adds the round-2 arms: the {agent_*}
# generation-time placeholder namespace is a CLOSED registry (GEN_PLACEHOLDERS
# in a reserved namespace, regex {agent_[a-z0-9_]*} with re.I); the prose
# token {agent} (no underscore) is outside it and generates unchanged; every
# prose/param value lives in adapters.yml (canary proves the generator READS
# the shared top-level key).
#
# EVERY test runs against a temp copy of the tree (temp copy only — never
# the real adapters/).
#
# Run: bats tests/scripts/generate-adapters.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

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
# ── control: today's tree ─────────────────────────────────────────────────

@test "clean tree: exit 0, 0 skipped, 0 errors (real-tree control)" {
  make_tree
  gen
  [ "$rc" -eq 0 ] || { echo "generator failed: $err" >&2; return 1; }
  echo "$out" | grep -qE 'Results: [0-9]+ generated, [0-9]+ unchanged, 0 skipped, 0 errors' \
    || { echo "unexpected Results line: $(echo "$out" | tail -2)" >&2; return 1; }
}

@test "a typo'd adapters.yml adapter key fails generation" {
  make_tree
  sed -i 's/wrapper: xml/wrapperr: xml/' "$TREE/adapters.yml"
  grep -q 'wrapperr: xml' "$TREE/adapters.yml" || { echo "mutation did not take" >&2; return 1; }
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "has unknown keys: ['wrapperr']" || { echo "error does not name the key: $err" >&2; return 1; }
  echo "$err" | grep -qF 'valid keys' || { echo "error does not list valid keys: $err" >&2; return 1; }
}

# ── round-2 (PR B): the {agent_*} placeholder namespace ────────────────────

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

@test "suffix typo {AGENT_BLOCKING_PARAMM}: exit 1, error names the token and the file" {
  make_tree
  sed -i 's/{AGENT_BLOCKING_PARAM}/{AGENT_BLOCKING_PARAMM}/g' "$TREE/prompts/review-agents.md"
  grep -qF '{AGENT_BLOCKING_PARAMM}' "$TREE/prompts/review-agents.md" || { echo "mutation did not take" >&2; return 1; }
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'{AGENT_BLOCKING_PARAMM}'" || { echo "error does not name the token: $err" >&2; return 1; }
  echo "$err" | grep -qF 'prompts/review-agents.md' || { echo "error does not name the file: $err" >&2; return 1; }
}

@test "case variant {agent_blocking_param} / {Agent_Blocking_Param}: exit 1" {
  make_tree case1
  sed -i 's/{AGENT_BLOCKING_PARAM}/{agent_blocking_param}/g' "$TREE/prompts/review-agents.md"
  grep -qF '{agent_blocking_param}' "$TREE/prompts/review-agents.md" || { echo "mutation did not take" >&2; return 1; }
  gen
  [ "$rc" -eq 1 ] || { echo "lowercase variant: expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'{agent_blocking_param}'"
  make_tree case2
  sed -i 's/{AGENT_BLOCKING_PARAM}/{Agent_Blocking_Param}/g' "$TREE/prompts/review-agents.md"
  grep -qF '{Agent_Blocking_Param}' "$TREE/prompts/review-agents.md" || { echo "mutation did not take" >&2; return 1; }
  gen
  [ "$rc" -eq 1 ] || { echo "mixed-case variant: expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'{Agent_Blocking_Param}'"
}

@test "unknown name {AGENT_FOO}: exit 1" {
  make_tree
  printf '\nprobe {AGENT_FOO}\n' >> "$TREE/prompts/review-agents.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "'{AGENT_FOO}'"
}

@test "prefix typo {AGNT_BLOCKING_PARAM}: generator exit 0 by design; review-rounds count test FAILS on the temp tree" {
  # The namespace covers only {agent_*} tokens — a prefix typo is outside it,
  # so the generator CANNOT catch it (by design; runtime placeholders like
  # {NUMBER} share this shape). The safety net is the bats structure test:
  # review-rounds.bats counts Agent( dispatch blocks vs run_in_background
  # parameters. review-rounds.bats resolves ROOT from its own location, so a
  # copy placed inside the temp tree at tests/commands/ sees the TEMP tree's
  # adapters — where dispatches=10 and params=0, so the count test fails.
  make_tree
  sed -i 's/{AGENT_BLOCKING_PARAM}/{AGNT_BLOCKING_PARAM}/g' "$TREE/prompts/review-agents.md"
  grep -qF '{AGNT_BLOCKING_PARAM}' "$TREE/prompts/review-agents.md" || { echo "mutation did not take" >&2; return 1; }
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
  sed -i 's/{AGENT_BLOCKING_PROSE}/{AGNT_BLOCKING_PROSE}/g' "$TREE/prompts/review-agents.md"
  grep -qF '{AGNT_BLOCKING_PROSE}' "$TREE/prompts/review-agents.md" || { echo "mutation did not take" >&2; return 1; }
  gen
  [ "$rc" -eq 0 ] || { echo "generator should exit 0 (outside namespace), got $rc: $err" >&2; return 1; }
  local d="$TREE/adapters/claude-code/prp-review-agents.md"
  # claim gone (would fail the positive test's first assertion)
  [ "$(grep -cF 'therefore passes' "$d")" -eq 0 ]
  # literal brace token ships (would fail its second assertion)
  grep -qF '{AGNT_BLOCKING_PROSE}' "$d"
}

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

# ── round-6: output check + remaining input-table rows ────────────────────

@test "empty prompt: exit 1, error names the file (round 6)" {
  make_tree
  : > "$TREE/prompts/qa.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "prompt file for configured command 'qa' is empty or whitespace-only: prompts/qa.md" \
    || { echo "error does not name the file/reason: $err" >&2; return 1; }
}

@test "whitespace-only prompt: exit 1 (round 6)" {
  make_tree
  printf ' \n\t\n  \n' > "$TREE/prompts/qa.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "is empty or whitespace-only: prompts/qa.md"
}

@test "adapters.yml not a mapping (list / scalar): exit 1 with a named error (round 6 input table)" {
  make_tree
  printf -- '- a\n- b\n' > "$TREE/adapters.yml"
  gen
  [ "$rc" -eq 1 ] || { echo "list: expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'adapters.yml must be a mapping, got list'
  make_tree scalar
  printf -- '42\n' > "$TREE/adapters.yml"
  gen
  [ "$rc" -eq 1 ] || { echo "scalar: expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'adapters.yml must be a mapping, got int'
}

@test "adapters.yml section not a mapping ('adapters' as a list): exit 1 (round 6 input table)" {
  make_tree
  printf -- 'adapters: [x]\ncommands: {}\n' > "$TREE/adapters.yml"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "adapters.yml 'adapters' must be a mapping, got list"
}

@test "overlay frontmatter not a mapping: exit 1 naming the overlay (round 6 input table)" {
  make_tree
  printf -- '---\n- just\n- a list\n---\n# objective\nx\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'overlay frontmatter must be a mapping, got list: prompts/overlays/claude-code/plan.md'
}

@test "alias-of names a missing command: exit 1 naming both commands (round 6 input table)" {
  make_tree
  python3 - "$TREE" <<'PYEOF'
import sys, yaml
t = sys.argv[1]
c = yaml.safe_load(open(f"{t}/adapters.yml"))
c["commands"]["ghost-alias"] = {"alias": True, "alias-of": "no-such-cmd",
                                "description": {"default": "x"}}
yaml.safe_dump(c, open(f"{t}/adapters.yml", "w"), sort_keys=False, allow_unicode=True)
PYEOF
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "command 'ghost-alias' is an alias of 'no-such-cmd', which is not a configured command"
}

@test "missing description for an adapter whose frontmatter needs one: exit 1 by output check (b) (round 6 input table)" {
  make_tree
  python3 - "$TREE" <<'PYEOF'
import sys, yaml
t = sys.argv[1]
c = yaml.safe_load(open(f"{t}/adapters.yml"))
c["commands"]["qa"]["description"] = {"default": ""}
yaml.safe_dump(c, open(f"{t}/adapters.yml", "w"), sort_keys=False, allow_unicode=True)
PYEOF
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'has an empty description field'
}

@test "validate_generated direct: each bad output shape raises naming the file (round 6)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ga)

def expect_fail(name, rel_path, content, want):
    try:
        ga.validate_generated(rel_path, content)
    except ga.GenerationError as e:
        assert want in str(e), f"{name}: error lacks {want!r}: {e}"
        assert rel_path in str(e), f"{name}: error lacks the file name: {e}"
        return
    raise AssertionError(f"{name}: validate_generated did not raise")

expect_fail("md-empty-body", "claude-code/prp-x.md",
            "---\ndescription: \"d\"\n---\n\n  \n", "empty command body")
expect_fail("md-ws-body", "opencode/prp-x.md", " \n\t\n", "empty command body")
expect_fail("md-empty-desc", "claude-code/prp-x.md",
            "---\ndescription: \"\"\n---\n\nreal body\n", "empty description field")
expect_fail("toml-empty-desc", "gemini/prp-x.toml",
            'description = ""\nprompt = """\nbody\n"""\n', "empty description field")
expect_fail("toml-empty-body", "gemini/prp-x.toml",
            'description = "d"\nprompt = """\n\n"""\n', "empty command body")
expect_fail("ns-token", "codex/prp-x/SKILL.md",
            "---\ndescription: \"d\"\n---\nbody with {AGENT_FOO} inside\n",
            "'{AGENT_FOO}'")

# round 7: frontmatter must split ONLY on lines exactly `---` — a description
# containing "---" must not mis-split frontmatter from body.
expect_fail("dash-desc-ws-body", "claude-code/prp-x.md",
            "---\ndescription: \"pre---post\"\n---\n\n   \n", "empty command body")
ga.validate_generated("claude-code/prp-x.md",
                      "---\ndescription: \"pre---post\"\n---\nreal body\n")

ga.validate_generated("claude-code/prp-x.md", "---\ndescription: \"d\"\n---\nbody\n")
ga.validate_generated("gemini/prp-x.toml", 'description = "d"\nprompt = """\nbody\n"""\n')
ga.validate_generated("opencode/prp-x.md", "# just a body\n")
print("validate_generated shapes OK")
PYEOF
}

@test "the output check runs in --dry-run too: a bad would-write output fails without writing (round 6; round-7 rewrite)" {
  # Round-7 rewrite: the mutation — an EMPTY DESCRIPTION via adapters.yml —
  # flows through substitution untouched and is caught ONLY by
  # validate_generated, and the assertion requires validate_generated's OWN
  # error text ("generated output <rel_path>", no "for"), which no earlier
  # check emits.
  make_tree
  python3 - "$TREE" <<'PYEOF'
import sys, yaml
t = sys.argv[1]
c = yaml.safe_load(open(f"{t}/adapters.yml"))
c["commands"]["qa"]["description"] = {"default": ""}
yaml.safe_dump(c, open(f"{t}/adapters.yml", "w"), sort_keys=False, allow_unicode=True)
PYEOF
  rc2=0
  (cd "$TREE" && python3 scripts/generate-adapters.py --dry-run >"$BATS_TEST_TMPDIR/gen.out" 2>"$BATS_TEST_TMPDIR/err") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo "expected exit 1 in --dry-run, got $rc2" >&2; return 1; }
  grep -qF 'generated output' "$BATS_TEST_TMPDIR/err" \
    || { echo "not validate_generated's error: $(cat "$BATS_TEST_TMPDIR/err")" >&2; return 1; }
  grep -qE 'generated output [^ ]+ has an empty description field' "$BATS_TEST_TMPDIR/err" \
    || { echo "missing validate_generated text: $(cat "$BATS_TEST_TMPDIR/err")" >&2; return 1; }
  # it fired before the fork: nothing was written
  [ ! -e "$TREE/adapters/claude-code/prp-qa.md" ]
}

@test "overlay frontmatter value containing --- parses correctly (round 7)" {
  # read_overlay used to split frontmatter on any "---" — a value like
  # note: "pre---post" mis-split the overlay. Now it splits only on lines
  # exactly `---`: this overlay must parse (exit 0) and its objective must
  # land in the claude-code plan adapter.
  make_tree
  printf -- '---\ncommand: plan\nadapter: claude-code\nnote: "pre---post"\n---\n# objective\nOBJTEXT-ROUND7\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 0 ] || { echo "expected exit 0, got $rc: $err" >&2; return 1; }
  grep -qF "OBJTEXT-ROUND7" "$TREE/adapters/claude-code/prp-plan.md" \
    || { echo "overlay objective not applied" >&2; return 1; }
}

# ── round-8: split_frontmatter boundary table (temp copies only) ──────────
# The table's "validate: error" rows run through validate_generated (the
# output side); the overlay-reachable rows also run through read_overlay (the
# input side) to prove both call sites share the one parser.

@test "round-8 plain: frontmatter parsed, body preserved (direct + overlay)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\nk: v\n---\nbody\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
print("plain OK")
PYEOF
  # overlay side: a plain overlay parses and applies
  printf -- '---\ncommand: plan\nadapter: claude-code\n---\n# objective\nR8-PLAIN\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 0 ] || { echo "gen failed: $err" >&2; return 1; }
  grep -qF "R8-PLAIN" "$TREE/adapters/claude-code/prp-plan.md"
}

@test "round-8 dash in value: validate_generated errors on the ws-only body (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.validate_generated("claude-code/prp-x.md",
                          '---\ndescription: "pre---post"\n---\n   \n')
    raise SystemExit("BUG: dash-in-value ws body passed")
except ga.GenerationError as e:
    assert "empty command body" in str(e)
# and the good shape still passes
ga.validate_generated("claude-code/prp-x.md",
                      '---\ndescription: "pre---post"\n---\nreal body\n')
print("dash-in-value OK")
PYEOF
}

@test "round-8 trailing-space delimiter: parsed as a delimiter (direct + validate)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\nk: v\n--- \nbody\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
# ws-only body under a trailing-space closer -> validate errors
try:
    ga.validate_generated("claude-code/prp-x.md", "---\ndescription: d\n--- \n   \n")
    raise SystemExit("BUG: trailing-space closer + ws body passed")
except ga.GenerationError as e:
    assert "empty command body" in str(e)
print("trailing-space OK")
PYEOF
}

@test "round-8 trailing-tab delimiter: parsed as a delimiter (direct + overlay)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\nk: v\n---\t\nbody\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
print("trailing-tab OK")
PYEOF
  printf -- '---\ncommand: plan\nadapter: claude-code\n---\t\n# objective\nR8-TAB\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 0 ] || { echo "gen failed: $err" >&2; return 1; }
  grep -qF "R8-TAB" "$TREE/adapters/claude-code/prp-plan.md"
}

@test "round-8 CRLF: same result as plain (direct + overlay)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\r\nk: v\r\n---\r\nbody\r\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
print("CRLF OK")
PYEOF
  printf -- '---\r\ncommand: plan\r\nadapter: claude-code\r\n---\r\n# objective\r\nR8-CRLF\r\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 0 ] || { echo "gen failed: $err" >&2; return 1; }
  grep -qF "R8-CRLF" "$TREE/adapters/claude-code/prp-plan.md"
}

@test "round-8 CRLF + empty body: validate errors (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.validate_generated("claude-code/prp-x.md", "---\r\ndescription: d\r\n---\r\n\r\n")
    raise SystemExit("BUG: CRLF ws body passed")
except ga.GenerationError as e:
    assert "empty command body" in str(e)
print("CRLF-empty OK")
PYEOF
}

@test "round-8 unterminated: error names the source (direct + overlay)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.split_frontmatter("---\nk: v\nbody", "x.md")
    raise SystemExit("BUG: unterminated accepted")
except ga.GenerationError as e:
    assert "unterminated frontmatter" in str(e) and "x.md" in str(e), str(e)
print("unterminated direct OK")
PYEOF
  # overlay side: an unterminated overlay is a generation error naming the file
  printf -- '---\ncommand: plan\nadapter: claude-code\n# objective\nR8-UNTERM\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'unterminated frontmatter in prompts/overlays/claude-code/plan.md'
}

@test "round-8 no frontmatter: body as is, validate OK if non-empty (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("body only\n", "x.md")
assert fm is None and body == "body only\n"
ga.validate_generated("opencode/prp-x.md", "# just a body\n")
print("no-frontmatter OK")
PYEOF
}

@test "round-8 ---- (4 dashes) closer: NOT a delimiter, counts as unterminated (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.split_frontmatter("---\nk: v\n----\nbody\n", "x.md")
    raise SystemExit("BUG: 4-dash closer accepted")
except ga.GenerationError as e:
    assert "unterminated frontmatter" in str(e)
print("4-dash OK")
PYEOF
}

@test "round-8 grep: no frontmatter split exists in the generator except inside split_frontmatter" {
  # `split("---"` anywhere, and `re.split(` applied to --- must appear
  # nowhere in generate-adapters.py. split_frontmatter itself splits on
  # plain newlines (no --- literal at all), so ANY hit is a stray splitter.
  # Plus: split_frontmatter is defined exactly once and called from exactly
  # the two call sites (read_overlay + validate_generated).
  local script="$ROOT/scripts/generate-adapters.py"
  local p1 p2 n1 n2 rc1 rc2
  rc1=0; p1=$(grep -nF 'split("---"' "$script") || rc1=$?
  [ "$rc1" -eq 1 ] || { echo 'stray split("---" found:' >&2; printf '%s\n' "$p1" >&2; return 1; }
  rc2=0; p2=$(grep -nE 're\.split\(.*---' "$script") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo 'stray re.split on --- found:' >&2; printf '%s\n' "$p2" >&2; return 1; }
  [ "$(grep -c 'def split_frontmatter' "$script")" -eq 1 ]
  [ "$(grep -c 'split_frontmatter(' "$script")" -eq 3 ]  # def + read_overlay + validate_generated
}

# ── round 9 (the #156 re-route fix): indented `---` delimiters ────────────
# An indented opening `---` parsed as "no frontmatter" — the overlay metadata
# was dropped and generation exited 0. An indented closer is the same near
# miss. Both raise naming the file and the line; only a `---` AFTER a valid
# closer is body text.

@test "round-9 indented opener: error names the file and line (direct + overlay)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.split_frontmatter("  ---\ncommand: plan\nadapter: claude-code\n---\n# objective\nx\n", "o.md")
    raise SystemExit("BUG: indented opener accepted as no-frontmatter")
except ga.GenerationError as e:
    assert "indented frontmatter delimiter" in str(e), str(e)
    assert "o.md" in str(e) and "line 1" in str(e), str(e)
print("indented opener direct OK")
PYEOF
  # overlay side: the indented opener is a generation error naming the file
  printf -- '  ---\ncommand: plan\nadapter: claude-code\n---\n# objective\nR9-INDENT-OPEN\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1 on indented opener, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'indented frontmatter delimiter in prompts/overlays/claude-code/plan.md at line 1' \
    || { echo "error does not name the file and line: $err" >&2; return 1; }
}

@test "round-9 indented closer with a correct opener: error names the file and line (direct + overlay)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.split_frontmatter("---\nk: v\n\t--- \nbody\n", "x.md")
    raise SystemExit("BUG: indented closer accepted")
except ga.GenerationError as e:
    assert "indented frontmatter delimiter" in str(e), str(e)
    assert "x.md" in str(e) and "line 3" in str(e), str(e)
print("indented closer direct OK")
PYEOF
  # overlay side: indented closer → error naming the overlay and line
  printf -- '---\ncommand: plan\nadapter: claude-code\n    ---\n# objective\nR9-INDENT-CLOSE\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1 on indented closer, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'indented frontmatter delimiter in prompts/overlays/claude-code/plan.md at line 4' \
    || { echo "error does not name the file and line: $err" >&2; return 1; }
}

@test "round-9 three-dash line inside a fenced block in the body, after a correct closer: body, unaffected (direct + overlay)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
# an indented `---` AFTER the valid closer is body text — never inspected
fm, body = ga.split_frontmatter("---\nk: v\n---\n```sh\n  ---\n```\nmore\n", "x.md")
assert (fm, body) == ("k: v", "```sh\n  ---\n```\nmore\n"), (fm, body)
# a column-1 `---` after the closer is body text too (round-8 already showed
# the split stops at the FIRST closer; pinned here for the fenced-block shape)
fm, body = ga.split_frontmatter("---\nk: v\n---\nbody\n---\n", "x.md")
assert (fm, body) == ("k: v", "body\n---\n"), (fm, body)
print("fenced-body OK")
PYEOF
  # overlay side: a fenced block containing an indented `---` in the body
  # after a clean closer parses fine and applies
  printf -- '---\ncommand: plan\nadapter: claude-code\n---\n# wrap_after\n```sh\n  ---\n```\nR9-FENCE-AFTER\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 0 ] || { echo "expected exit 0 with fenced --- in body, got $rc: $err" >&2; return 1; }
  grep -qF "R9-FENCE-AFTER" "$TREE/adapters/claude-code/prp-plan.md" \
    || { echo "overlay wrap_after not applied" >&2; return 1; }
}

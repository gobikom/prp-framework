#!/usr/bin/env bats
# Generator load-time config validation + utf-8 pin + display paths
# (prp-framework#157 split 1/2 — PR A1, fix/generator-config-validation).
#
# Scope: everything load_config reads and every read/write the generator
# performs is validated or pinned. Per-input GenerationErrors (missing/empty
# prompt, overlay parsing, validate_generated, the per-command boundary and
# the main() last-resort handler) are PR #157 — split 2/2.
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
  [ "$dispatches" -eq 10 ] || { echo "claude-code dispatches: $dispatches (want 10)" >&2; return 1; }
  [ "$params" -eq 10 ] || { echo "claude-code run_in_background params: $params (want 10)" >&2; return 1; }
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
@test "invalid UTF-8 adapters.yml: exit 1 with a named error, no Traceback (#157 round 1)" {
  make_tree
  python3 -c "open('$TREE/adapters.yml','wb').write(b'adapters: \xff\xfe\n')"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'Error: Cannot read' \
    || { echo "error does not name the config read: $err" >&2; return 1; }
  echo "$err" | grep -qF "'utf-8' codec can't decode" \
    || { echo "error does not name the failure: $err" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then
    echo "raw traceback leaked: $err" >&2
    return 1
  fi
}
@test "round-3 command key /etc/passwd: load-time name error, exit 1, no Traceback" {
  make_tree
  python3 - "$TREE" <<'HOOK1'
import sys, yaml
t = sys.argv[1]
c = yaml.safe_load(open(f"{t}/adapters.yml"))
c["commands"]["/etc/passwd"] = dict(c["commands"]["qa"])
yaml.safe_dump(c, open(f"{t}/adapters.yml", "w"), sort_keys=False)
HOOK1
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "invalid command name '/etc/passwd'" \
    || { echo "error does not name the key: $err" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then echo "raw traceback leaked: $err" >&2; return 1; fi
}
@test "round-3 command key ../x: load-time name error, exit 1, no Traceback" {
  make_tree
  python3 - "$TREE" <<'HOOK2'
import sys, yaml
t = sys.argv[1]
c = yaml.safe_load(open(f"{t}/adapters.yml"))
c["commands"]["../x"] = dict(c["commands"]["qa"])
yaml.safe_dump(c, open(f"{t}/adapters.yml", "w"), sort_keys=False)
HOOK2
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "invalid command name '../x'" \
    || { echo "error does not name the key: $err" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then echo "raw traceback leaked: $err" >&2; return 1; fi
}
@test "round-3 args_placeholder null: load-time type error naming the key, exit 1, no Traceback" {
  make_tree
  python3 - "$TREE" <<'HOOK3'
import sys, yaml
t = sys.argv[1]
c = yaml.safe_load(open(f"{t}/adapters.yml"))
c["adapters"]["claude-code"]["args_placeholder"] = None
yaml.safe_dump(c, open(f"{t}/adapters.yml", "w"), sort_keys=False)
HOOK3
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "adapter 'claude-code' key 'args_placeholder' must be str, got NoneType" \
    || { echo "error does not name adapter+key+types: $err" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then echo "raw traceback leaked: $err" >&2; return 1; fi
}
@test "round-3 description 123: load-time type error naming the key, exit 1, no Traceback" {
  make_tree
  python3 - "$TREE" <<'HOOK4'
import sys, yaml
t = sys.argv[1]
c = yaml.safe_load(open(f"{t}/adapters.yml"))
c["commands"]["qa"]["description"] = 123
yaml.safe_dump(c, open(f"{t}/adapters.yml", "w"), sort_keys=False)
HOOK4
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "command 'qa' key 'description' must be dict, got int" \
    || { echo "error does not name command+key+types: $err" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then echo "raw traceback leaked: $err" >&2; return 1; fi
}

@test "round-3 bad-bytes adapters.yml under LC_ALL=C: same named error, no Traceback, locale-independent" {
  make_tree
  python3 -c "open('$TREE/adapters.yml','wb').write(b'adapters: \xff\xfe\n')"
  rc2=0
  (cd "$TREE" && LC_ALL=C python3 scripts/generate-adapters.py >"$BATS_TEST_TMPDIR/o" 2>"$BATS_TEST_TMPDIR/e") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo "expected exit 1 under LC_ALL=C, got $rc2" >&2; return 1; }
  grep -qF "Error: Cannot read" "$BATS_TEST_TMPDIR/e" \
    || { echo "error does not name the config read: $(cat "$BATS_TEST_TMPDIR/e")" >&2; return 1; }
  grep -qF "'utf-8' codec can't decode" "$BATS_TEST_TMPDIR/e" \
    || { echo "error does not name the decode failure" >&2; return 1; }
  if grep -q 'Traceback' "$BATS_TEST_TMPDIR/e"; then echo "raw traceback leaked" >&2; return 1; fi
}
@test "A1 structural grep: relative_to(ROOT_DIR) only in display_path/validate_output_path; every open/read_text/write_text has encoding=" {
  local script="$ROOT/scripts/generate-adapters.py"
  # 1. relative_to(ROOT_DIR) may appear ONLY inside display_path (its def)
  #    and validate_output_path.
  local n_total n_display n_validate
  n_total=$(grep -cF 'relative_to(ROOT_DIR)' "$script")
  n_display=$(sed -n '/^def display_path/,/^def /p' "$script" | grep -cF 'relative_to(ROOT_DIR)' || true)
  n_validate=$(sed -n '/^def validate_output_path/,/^def /p' "$script" | grep -cF 'relative_to(ROOT_DIR)' || true)
  [ "$n_total" -eq $((n_display + n_validate)) ] \
    || { echo "relative_to(ROOT_DIR) outside display_path/validate_output_path: total=$n_total display=$n_display validate=$n_validate" >&2; return 1; }
  # 2. every open( / read_text( / write_text( call carries encoding=
  local bad
  bad=$(grep -nE '(open|read_text|write_text)\(' "$script" | grep -vF 'encoding=' || true)
  [ -z "$bad" ] || { echo "read/write without encoding=:" >&2; printf '%s\n' "$bad" >&2; return 1; }
}

# ── frontmatter parsing: split_frontmatter boundary table (round 8 + round 9) ──
# split_frontmatter is the ONLY frontmatter splitter (A1 owns it; #157's
# read_overlay and validate_generated call it). Direct (module-level) arms
# live here; the overlay-side and validate_generated arms are #157's, where
# those callers live.
@test "round-8 plain: frontmatter parsed, body preserved (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\nk: v\n---\nbody\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
print("plain OK")
PYX
}
@test "round-8 dash in value: a --- inside a frontmatter value does not split (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter('---\ndescription: "pre---post"\n---\nreal body\n', "x.md")
assert fm == 'description: "pre---post"', fm
assert body == "real body\n", body
print("dash-in-value OK")
PYX
}
@test "round-8 trailing-space delimiter: parsed as a delimiter (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\nk: v\n--- \nbody\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
print("trailing-space OK")
PYX
}
@test "round-8 trailing-tab delimiter: parsed as a delimiter (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\nk: v\n---\t\nbody\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
print("trailing-tab OK")
PYX
}
@test "round-8 CRLF: same result as plain (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\r\nk: v\r\n---\r\nbody\r\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
print("CRLF OK")
PYX
}
@test "round-8 unterminated: error names the source (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.split_frontmatter("---\nk: v\nbody", "x.md")
    raise SystemExit("BUG: unterminated accepted")
except ga.GenerationError as e:
    assert "unterminated frontmatter" in str(e) and "x.md" in str(e), str(e)
print("unterminated direct OK")
PYX
}
@test "round-8 no frontmatter: body as is (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("body only\n", "x.md")
assert fm is None and body == "body only\n"
print("no-frontmatter OK")
PYX
}
@test "round-8 ---- (4 dashes) closer: NOT a delimiter, counts as unterminated (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.split_frontmatter("---\nk: v\n----\nbody\n", "x.md")
    raise SystemExit("BUG: 4-dash closer accepted")
except ga.GenerationError as e:
    assert "unterminated frontmatter" in str(e)
print("4-dash OK")
PYX
}
@test "round-9 indented opener: error names the file and line (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.split_frontmatter("  ---\nk: v\n---\nbody\n", "o.md")
    raise SystemExit("BUG: indented opener accepted")
except ga.GenerationError as e:
    assert "indented frontmatter delimiter" in str(e), str(e)
    assert "o.md" in str(e) and "line 1" in str(e), str(e)
print("indented opener OK")
PYX
}
@test "round-9 indented closer with a correct opener: error names the file and line (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
try:
    ga.split_frontmatter("---\nk: v\n\t--- \nbody\n", "x.md")
    raise SystemExit("BUG: indented closer accepted")
except ga.GenerationError as e:
    assert "indented frontmatter delimiter" in str(e), str(e)
    assert "x.md" in str(e) and "line 3" in str(e), str(e)
print("indented closer OK")
PYX
}
@test "round-9 three-dash line inside a fenced block in the body, after a correct closer: body, unaffected (direct)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\nk: v\n---\n```sh\n  ---\n```\nmore\n", "x.md")
assert (fm, body) == ("k: v", "```sh\n  ---\n```\nmore\n"), (fm, body)
fm, body = ga.split_frontmatter("---\nk: v\n---\nbody\n---\n", "x.md")
assert (fm, body) == ("k: v", "body\n---\n"), (fm, body)
print("fenced-body OK")
PYX
}
@test "round-8 grep: split_frontmatter is the only frontmatter splitter (A1)" {
  local script="$ROOT/scripts/generate-adapters.py"
  rc1=0; p1=$(grep -nF 'split("---"' "$script") || rc1=$?
  [ "$rc1" -eq 1 ] || { echo 'stray split("---" found:' >&2; printf '%s\n' "$p1" >&2; return 1; }
  rc2=0; p2=$(grep -nE 're\.split\(.*---' "$script") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo 'stray re.split on --- found:' >&2; printf '%s\n' "$p2" >&2; return 1; }
  # In A1 split_frontmatter is DEFINED here (the only splitter); #157's
  # read_overlay and validate_generated are the two call sites, pinned by
  # #157's grep test (def + 2 calls).
  [ "$(grep -c 'def split_frontmatter' "$script")" -eq 1 ]
}

# ── A1 round-1 (#161) tests kept where A1's policy still applies here;
# the overlay-WARNING and existing-output lenient arms are A1-only (this
# branch's hard-error policy supersedes them; its own tests pin those).

@test "A1-r1 command frontmatter.fields error names the command (section param)" {
  make_tree
  python3 - "$TREE" <<'HOOKF'
import sys, yaml
t = sys.argv[1]
c = yaml.safe_load(open(f"{t}/adapters.yml"))
c["commands"]["qa"]["frontmatter"] = {"fields": [1, 2]}
yaml.safe_dump(c, open(f"{t}/adapters.yml", "w"), sort_keys=False)
HOOKF
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "adapters.yml command 'qa' key 'frontmatter.fields' must be a list of strings" \
    || { echo "error does not name command+key: $err" >&2; return 1; }
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
  make_tree
  printf -- '---\ncommand: plan\nadapter: claude-code\nnote: "pre---post"\n---\n# objective\nOBJTEXT-ROUND7\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 0 ] || { echo "expected exit 0, got $rc: $err" >&2; return 1; }
  grep -qF "OBJTEXT-ROUND7" "$TREE/adapters/claude-code/prp-plan.md" \
    || { echo "overlay objective not applied" >&2; return 1; }
}
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
@test "round-8 grep: no frontmatter split exists in the generator except inside split_frontmatter" {
  # `split("---"` anywhere, and `re.split(` applied to --- must appear
  local script="$ROOT/scripts/generate-adapters.py"
  local p1 p2 n1 n2 rc1 rc2
  rc1=0; p1=$(grep -nF 'split("---"' "$script") || rc1=$?
  [ "$rc1" -eq 1 ] || { echo 'stray split("---" found:' >&2; printf '%s\n' "$p1" >&2; return 1; }
  rc2=0; p2=$(grep -nE 're\.split\(.*---' "$script") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo 'stray re.split on --- found:' >&2; printf '%s\n' "$p2" >&2; return 1; }
  [ "$(grep -c 'def split_frontmatter' "$script")" -eq 1 ]
  [ "$(grep -c 'split_frontmatter(' "$script")" -eq 3 ]  # def + read_overlay + validate_generated
}
@test "invalid UTF-8 prompt: exit 1, error names the file, no Traceback (#157 round 1)" {
  make_tree
  python3 -c "open('$TREE/prompts/qa.md','wb').write(b'ok text\n\xff\xfe bad\n')"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "cannot read prompt for configured command 'qa': prompts/qa.md" \
    || { echo "error does not name the file: $err" >&2; return 1; }
  echo "$err" | grep -qF "'utf-8' codec can't decode" \
    || { echo "error does not name the failure: $err" >&2; return 1; }
  # the run continued: every adapter reported it (6), and no raw traceback
  [ "$(printf '%s\n' "$err" | grep -cF "command 'qa'")" -eq 6 ] \
    || { echo "expected the error once per adapter (6)" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then
    echo "raw traceback leaked: $err" >&2
    return 1
  fi
  echo "$out" | grep -qE 'Results: .*6 errors' \
    || { echo "errors not counted: $(echo "$out" | tail -2)" >&2; return 1; }
}
@test "invalid UTF-8 overlay: exit 1, error names the overlay file, no Traceback (#157 round 1)" {
  make_tree
  python3 -c "open('$TREE/prompts/overlays/claude-code/plan.md','wb').write(b'---\nx: y\n---\n\xff\xfe\n')"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF 'cannot read overlay prompts/overlays/claude-code/plan.md' \
    || { echo "error does not name the overlay: $err" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then
    echo "raw traceback leaked: $err" >&2
    return 1
  fi
  echo "$out" | grep -qE 'Results: .*1 errors'
}
@test "two invalid-UTF-8 prompts in one run: BOTH reported, run continues (#157 round 1)" {
  make_tree
  python3 -c "open('$TREE/prompts/qa.md','wb').write(b'ok\n\xff\xfe\n'); open('$TREE/prompts/plan.md','wb').write(b'ok\n\x80\x81\n')"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  # both files are named, each once per adapter — the run CONTINUES past a
  [ "$(printf '%s\n' "$err" | grep -cF "command 'qa'")" -eq 6 ] \
    || { echo "qa not reported once per adapter" >&2; return 1; }
  [ "$(printf '%s\n' "$err" | grep -cF "command 'plan'")" -eq 6 ] \
    || { echo "plan not reported once per adapter" >&2; return 1; }
  # 2 broken prompts x 6 adapters = 12 counted errors
  echo "$out" | grep -qE 'Results: .*12 errors' \
    || { echo "expected 12 counted errors: $(echo "$out" | tail -2)" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then
    echo "raw traceback leaked" >&2
    return 1
  fi
}
@test "invalid UTF-8 in an existing output file: named error, counted, run continues, file untouched (#157 round 1)" {
  make_tree
  mkdir -p "$TREE/adapters/claude-code"
  python3 -c "open('$TREE/adapters/claude-code/prp-qa.md','wb').write(b'---\ndescription: \"old\"\n---\n\xff\xfe\n')"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "error: cannot read existing output" \
    || { echo "error does not name the existing output: $err" >&2; return 1; }
  echo "$err" | grep -qF "adapters/claude-code/prp-qa.md" \
    || { echo "error does not name the file: $err" >&2; return 1; }
  echo "$out" | grep -qE 'Results: .*1 errors' \
    || { echo "expected errors=1: $(echo "$out" | grep Results)" >&2; return 1; }
  # the other files still generated: 191 of 192 (one skipped due to the unreadable file)
  echo "$out" | grep -qE 'Results: 19[0-9] generated, ' \
    || { echo "others not generated: $(echo "$out" | grep Results)" >&2; return 1; }
  # never overwrite an output we could not read
  python3 -c "assert b'\\xff\\xfe' in open('$TREE/adapters/claude-code/prp-qa.md','rb').read(), 'existing output was overwritten'"
}

@test "A1-r1 mkdir blocked by a regular file: named error, errors=1" {
  make_tree
  # block the codex prp-qa directory with a regular file
  mkdir -p "$TREE/adapters/codex"
  printf 'not a dir\n' > "$TREE/adapters/codex/prp-qa"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "error: cannot create directory" \
    || { echo "error does not name the mkdir failure: $err" >&2; return 1; }
  echo "$err" | grep -qF "adapters/codex/prp-qa" \
    || { echo "error does not name the directory: $err" >&2; return 1; }
  echo "$out" | grep -qE 'Results: .*1 errors' \
    || { echo "expected errors=1: $(echo "$out" | grep Results)" >&2; return 1; }
}
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
  printf -- '---\ncommand: plan\nadapter: claude-code\n---\n# wrap_after\n```sh\n  ---\n```\nR9-FENCE-AFTER\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  [ "$rc" -eq 0 ] || { echo "expected exit 0 with fenced --- in body, got $rc: $err" >&2; return 1; }
  grep -qF "R9-FENCE-AFTER" "$TREE/adapters/claude-code/prp-plan.md" \
    || { echo "overlay wrap_after not applied" >&2; return 1; }
}
@test "round-3 forced per-command RuntimeError: named unexpected-error, errors=1 per adapter, others generated, no Traceback" {
  # A tiny Python-level test that imports the module and monkeypatches
  make_tree
  cat > "$BATS_TEST_TMPDIR/hook.py" <<'HOOK5'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location(
    "ga", os.path.join(os.environ["R3_TREE"], "scripts", "generate-adapters.py"))
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
orig = ga.read_prompt
def boom(name):
    if name == "qa":
        raise RuntimeError("forced per-command failure")
    return orig(name)
ga.read_prompt = boom
sys.exit(ga.main())
HOOK5
  rc2=0
  out2="$(cd "$TREE" && R3_TREE="$TREE" python3 "$BATS_TEST_TMPDIR/hook.py" 2>"$BATS_TEST_TMPDIR/r3err")" || rc2=$?
  err2="$(cat "$BATS_TEST_TMPDIR/r3err")"
  [ "$rc2" -eq 1 ] || { echo "expected exit 1, got $rc2" >&2; return 1; }
  printf '%s\n' "$err2" | grep -qF "error: claude-code/qa: unexpected RuntimeError: forced per-command failure" \
    || { echo "per-command handler did not fire: $err2" >&2; return 1; }
  [ "$(printf '%s\n' "$err2" | grep -cF 'unexpected RuntimeError')" -eq 6 ] \
    || { echo "expected 6 per-adapter unexpected errors" >&2; return 1; }
  printf '%s\n' "$out2" | grep -qE 'Results: 186 generated, .*6 errors' \
    || { echo "others not generated / errors not 6: $(printf '%s\n' "$out2" | grep Results)" >&2; return 1; }
  if printf '%s\n' "$err2" | grep -q 'Traceback'; then echo "raw traceback leaked: $err2" >&2; return 1; fi
}
@test "round-3 bad-bytes prompt under LC_ALL=C: same named decode error, no Traceback, locale-independent" {
  make_tree
  python3 -c "open('$TREE/prompts/qa.md','wb').write(b'ok\n\xff\xfe\n')"
  rc2=0
  (cd "$TREE" && LC_ALL=C python3 scripts/generate-adapters.py >"$BATS_TEST_TMPDIR/o" 2>"$BATS_TEST_TMPDIR/e") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo "expected exit 1 under LC_ALL=C, got $rc2" >&2; return 1; }
  grep -qF "cannot read prompt for configured command 'qa': prompts/qa.md" "$BATS_TEST_TMPDIR/e" \
    || { echo "error does not name the file: $(cat "$BATS_TEST_TMPDIR/e")" >&2; return 1; }
  grep -qF "'utf-8' codec can't decode" "$BATS_TEST_TMPDIR/e" \
    || { echo "error does not name the decode failure" >&2; return 1; }
  if grep -q 'Traceback' "$BATS_TEST_TMPDIR/e"; then echo "raw traceback leaked" >&2; return 1; fi
  grep -qE 'Results: .*6 errors' "$BATS_TEST_TMPDIR/o" \
    || { echo "errors not counted: $(grep Results "$BATS_TEST_TMPDIR/o")" >&2; return 1; }
}
@test "round-3 structural grep: relative_to(ROOT_DIR) only in display_path/validate_output_path; every open/read_text/write_text has encoding=" {
  local script="$ROOT/scripts/generate-adapters.py"
  # 1. relative_to(ROOT_DIR) may appear ONLY inside display_path (its def)
  local n_total n_display n_validate
  n_total=$(grep -cF 'relative_to(ROOT_DIR)' "$script")
  n_display=$(sed -n '/^def display_path/,/^def /p' "$script" | grep -cF 'relative_to(ROOT_DIR)' || true)
  n_validate=$(sed -n '/^def validate_output_path/,/^def /p' "$script" | grep -cF 'relative_to(ROOT_DIR)' || true)
  [ "$n_total" -eq $((n_display + n_validate)) ] \
    || { echo "relative_to(ROOT_DIR) outside display_path/validate_output_path: total=$n_total display=$n_display validate=$n_validate" >&2; return 1; }
  # 2. every open( / read_text( / write_text( call carries encoding=
  local bad
  bad=$(grep -nE '(open|read_text|write_text)\(' "$script" | grep -vF 'encoding=' || true)
  [ -z "$bad" ] || { echo "read/write without encoding=:" >&2; printf '%s\n' "$bad" >&2; return 1; }
  # 3. split_frontmatter's overlay source is display_path(path) — a str
  [ "$(grep -cF 'split_frontmatter(text, display_path(path))' "$script")" -eq 1 ]
  # 4. the per-command catch-all exists with the exact message shape
  grep -qF 'error: {adapter_name}/{cmd_name}: ' "$script"
  grep -qF 'unexpected {type(e).__name__}: {e}' "$script"
  # 5. main() has the last-resort internal handler
  grep -qF 'error: internal: {type(e).__name__}: {e}' "$script"
}


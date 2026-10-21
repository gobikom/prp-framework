#!/usr/bin/env bats
# Generator load-time config validation + utf-8 pin + display paths
# (prp-framework#157 split 1/2 — PR A1, fix/generator-config-validation).
#
# Scope: everything load_config reads and every read/write the generator
# performs is validated or pinned. Per-input GenerationErrors (missing/empty
# prompt, overlay parsing, validate_generated, the per-command boundary and
# the main() last-resort handler) are PR #157 — split 2/2.
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

# ── A1 round-1 fixes (#161): lenient but VISIBLE; guarded output-side reads ──

@test "A1-r3 command carrying a frontmatter key (adapter-only) is an unknown command key naming the command" {
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
  echo "$err" | grep -qF "Command 'qa' has unknown keys: ['frontmatter']" \
    || { echo "error does not name command+key: $err" >&2; return 1; }
}

# ── A1 round-3 re-plan: boundary table (one test per row) ───────────────────

# expect_counted_error <file-fragment> — rc 1, named error, no traceback, a
# 1-error Results line, and the other commands still generated.
expect_counted_error() {
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc: $err" >&2; return 1; }
  echo "$err" | grep -qF "$1" || { echo "error does not name '$1': $err" >&2; return 1; }
  if printf '%s\n' "$err" | grep -q 'Traceback'; then echo "raw traceback: $err" >&2; return 1; fi
  echo "$out" | grep -qE ', [1-9][0-9]* errors' || { echo "error not counted: $(echo "$out" | tail -2)" >&2; return 1; }
  [ -f "$TREE/adapters/claude-code/prp-commit.md" ] || { echo "other commands not generated" >&2; return 1; }
}

@test "A1-r3 row: prompt file missing — counted named error, others generated" {
  make_tree
  rm "$TREE/prompts/qa.md"
  gen
  expect_counted_error "prompts/qa.md"
}

@test "A1-r3 row: prompt unreadable (chmod 000) — counted named error" {
  [ "$(id -u)" -ne 0 ] || skip "root reads chmod 000 files"
  make_tree
  chmod 000 "$TREE/prompts/qa.md"
  gen
  chmod 644 "$TREE/prompts/qa.md"
  expect_counted_error "prompts/qa.md"
}

@test "A1-r3 row: prompt invalid UTF-8 — counted named error" {
  make_tree
  printf '\xff\xfe bad\n' > "$TREE/prompts/qa.md"
  gen
  expect_counted_error "prompts/qa.md"
}

@test "A1-r3 row: prompt empty — WARNING and skipped, not an error" {
  make_tree
  : > "$TREE/prompts/qa.md"
  gen
  [ "$rc" -eq 0 ] || { echo "expected exit 0, got $rc: $err" >&2; return 1; }
  echo "$err" | grep -qF "No prompt file for qa" || { echo "no empty-prompt WARNING: $err" >&2; return 1; }
}

@test "A1-r3 row: overlay malformed frontmatter YAML — counted error, no raw frontmatter in any output" {
  make_tree
  printf -- '---\ncommand: [plan\n---\n# objective\nOBJ-R3YAML\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  expect_counted_error "prompts/overlays/claude-code/plan.md"
  if grep -rqF 'command: [plan' "$TREE/adapters"; then echo "raw frontmatter leaked" >&2; return 1; fi
}

@test "A1-r3 row: overlay opener with no closing --- — counted error, no raw frontmatter in any output" {
  make_tree
  printf -- '---\ncommand: plan\nadapter: claude-code\n# objective\nOBJ-R3OPEN\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  expect_counted_error "unterminated frontmatter"
  if grep -rqF 'adapter: claude-code' "$TREE/adapters/claude-code/prp-plan.md" 2>/dev/null; then echo "raw frontmatter leaked" >&2; return 1; fi
}

@test "A1-r3 row: overlay indented opener — counted error" {
  make_tree
  printf -- '  ---\ncommand: plan\nadapter: claude-code\n---\n# objective\nOBJ-R3IND\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  expect_counted_error "indented frontmatter delimiter in prompts/overlays/claude-code/plan.md at line 1"
}

@test "A1-r3 row: overlay invalid UTF-8 — counted named error" {
  make_tree
  printf '\xff\xfe\n' > "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  expect_counted_error "prompts/overlays/claude-code/plan.md"
}

@test "A1-r3 row: unknown command key — named load-time error, exit 1" {
  make_tree
  sed -i '0,/^    argument-hint:/s//    argumnt-hint:/' "$TREE/adapters.yml"
  grep -q 'argumnt-hint:' "$TREE/adapters.yml" || { echo "mutation did not take" >&2; return 1; }
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc: $err" >&2; return 1; }
  echo "$err" | grep -qF "has unknown keys: ['argumnt-hint']" || { echo "error does not name the key: $err" >&2; return 1; }
  echo "$err" | grep -qF 'valid keys' || { echo "no valid-key list: $err" >&2; return 1; }
}

@test "A1-r3 row: valid input — exit 0, 0 skipped, 0 errors, repo adapters unchanged" {
  make_tree
  gen
  [ "$rc" -eq 0 ] || { echo "generator failed: $err" >&2; return 1; }
  echo "$out" | grep -qE ', 0 skipped, 0 errors' || { echo "$(echo "$out" | tail -2)" >&2; return 1; }
}

@test "A1-r1 existing output with invalid UTF-8: named error, errors=1, others generated, file unchanged" {
  make_tree
  mkdir -p "$TREE/adapters/claude-code"
  python3 -c "open('$TREE/adapters/claude-code/prp-qa.md','wb').write(b'---\ndescription: \"old\"\n---\n\xff\xfe\n')"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "error: Cannot read adapters/claude-code/prp-qa.md: UnicodeDecodeError" \
    || { echo "error does not name the existing output: $err" >&2; return 1; }
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

# ── A1 round-3 re-plan: ONE read helper (invariant) ────────────────────────
# Invariant: every file the generator READS goes through read_utf8(path),
# which turns OSError/UnicodeDecodeError into a GenerationError naming the
# file; the per-command loop catches it (print, count, continue). This test
# fails if read_text( or open( appears anywhere OUTSIDE read_utf8
# (write_text is excluded — the write path is #157's).

@test "A1-r3 invariant: every read goes through read_utf8 — no read_text(/open( outside it" {
  local script="$ROOT/scripts/generate-adapters.py"
  # every read_text( / open( call must live inside read_utf8's definition;
  # list the offending sites first so a RED run names them.
  local body_start body_end bad n
  body_start=$(grep -n 'def read_utf8' "$script" | cut -d: -f1)
  if [ -n "$body_start" ]; then
    body_end=$(awk -v s="$body_start" 'NR>s && /^def |^class /{print NR; exit}' "$script")
    bad=$(awk -v s="$body_start" -v e="$body_end" \
          'NR>s && NR<e {next} /read_text\(|[^_a-z]open\(/ {print NR": "$0}' "$script")
  else
    bad=$(grep -nE 'read_text\(|[^_a-z]open\(' "$script" || true)
  fi
  [ -z "$bad" ] || {
    echo "reads outside read_utf8:" >&2; printf '%s\n' "$bad" >&2; return 1; }
  # and read_utf8 must exist exactly once
  [ "$(grep -c 'def read_utf8' "$script")" -eq 1 ] || {
    echo "read_utf8 is not defined exactly once" >&2; return 1; }
}

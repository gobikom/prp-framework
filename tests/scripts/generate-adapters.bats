#!/usr/bin/env bats
# Generator load-time config validation + utf-8 pin + display paths
# (prp-framework#157 split 1/2 — PR A1, fix/generator-config-validation).
# Every test runs against a temp copy of the tree, never the real adapters/.
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

# ── split_frontmatter boundary table (the ONLY frontmatter splitter) ──

@test "split_frontmatter boundary table (rounds 8+9, direct): plain, dash-in-value, trailing space/tab, CRLF, none, fenced body, errors" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYX'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
ok = [  # (text, (frontmatter, body))
    ("---\nk: v\n---\nbody\n", ("k: v", "body\n")),
    ('---\ndescription: "pre---post"\n---\nreal body\n', ('description: "pre---post"', "real body\n")),
    ("---\nk: v\n--- \nbody\n", ("k: v", "body\n")),
    ("---\nk: v\n---\t\nbody\n", ("k: v", "body\n")),
    ("---\r\nk: v\r\n---\r\nbody\r\n", ("k: v", "body\n")),
    ("body only\n", (None, "body only\n")),
    ("---\nk: v\n---\n```sh\n  ---\n```\nmore\n", ("k: v", "```sh\n  ---\n```\nmore\n")),
    ("---\nk: v\n---\nbody\n---\n", ("k: v", "body\n---\n")),
]
for text, want in ok:
    assert ga.split_frontmatter(text, "x.md") == want, (text, want)
bad = [  # (text, message fragments)
    ("---\nk: v\nbody", ("unterminated frontmatter", "x.md")),
    ("---\nk: v\n----\nbody\n", ("unterminated frontmatter",)),
    ("  ---\nk: v\n---\nbody\n", ("indented frontmatter delimiter", "x.md", "line 1")),
    ("---\nk: v\n\t--- \nbody\n", ("indented frontmatter delimiter", "x.md", "line 3")),
]
for text, frags in bad:
    try:
        ga.split_frontmatter(text, "x.md")
    except ga.GenerationError as e:
        assert all(f in str(e) for f in frags), (text, str(e))
    else:
        raise SystemExit(f"BUG: accepted {text!r}")
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

# ── A1 round-1 fixes (#161): strict overlay; guarded output-side reads ──

@test "A1-r3 command carrying a frontmatter key (adapter-only) is an unknown command key naming the command" {
  make_tree
  python3 -c "
import yaml; p='$TREE/adapters.yml'; c=yaml.safe_load(open(p))
c['commands']['qa']['frontmatter']={'fields':[1]}; yaml.safe_dump(c,open(p,'w'),sort_keys=False)"
  gen
  [ "$rc" -eq 1 ] && echo "$err" | grep -qF "Command 'qa' has unknown keys: ['frontmatter']" \
    || { echo "rc=$rc err=$err" >&2; return 1; }
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

@test "A1c row: prompt empty — counted named error, not a WARNING skip (re-cut of #157)" {
  make_tree
  : > "$TREE/prompts/qa.md"
  gen
  expect_counted_error "error: prompt for command 'qa' is empty or whitespace-only: prompts/qa.md"
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

@test "A1-r4 row: adapters.yml with an impossible date — Error: Invalid YAML, exit 1, no traceback" {
  make_tree
  printf 'zz: 2001-13-45\n' >> "$TREE/adapters.yml"
  gen
  [ "$rc" -eq 1 ] && echo "$err" | grep -qF "Invalid YAML" && ! echo "$err" | grep -q Traceback \
    || { echo "rc=$rc err=$err" >&2; return 1; }
}

@test "A1-r4 row: dangling-symlink overlay — counted error, not a silent skip" {
  make_tree
  ln -sf /nonexistent-overlay-target "$TREE/prompts/overlays/claude-code/plan.md"
  gen
  expect_counted_error "prompts/overlays/claude-code/plan.md"
}

@test "A1-r4 row: unencodable value (lone surrogate) — counted error, existing output not truncated" {
  make_tree
  gen
  local before; before=$(wc -c < "$TREE/adapters/claude-code/prp-qa.md")
  python3 -c "
import yaml; p='$TREE/adapters.yml'; c=yaml.safe_load(open(p))
c['commands']['qa']['description']={'default':'\ud800 x'}
open(p,'w',encoding='utf-8',errors='surrogatepass').write(yaml.safe_dump(c,sort_keys=False,allow_unicode=True))"
  gen
  [ "$rc" -eq 1 ] && ! echo "$err" | grep -q Traceback || { echo "rc=$rc err=$err" >&2; return 1; }
  [ "$(wc -c < "$TREE/adapters/claude-code/prp-qa.md")" -eq "$before" ] || { echo "output truncated" >&2; return 1; }
}

@test "A1b config shape: adapter/command key that is int, None, date or lone surrogate -> one named load-time error, nothing generated" {
  local section shape expect fails=""
  for section in adapters commands; do
    for shape in int none date surrogate newline; do
      case "$shape" in
        int) expect="123" ;;
        none) expect="None" ;;
        date) expect="datetime.date(2024, 1, 1)" ;;
        surrogate) expect="'bad\\ud800'" ;;
        newline) expect="'qa\\n'" ;;
      esac
      make_tree "key-$section-$shape"
      python3 - "$TREE" "$section" "$shape" <<'HOOK'
import datetime, sys, yaml
t, section, shape = sys.argv[1:4]
p = f"{t}/adapters.yml"
c = yaml.safe_load(open(p))
key = {"int": 123, "none": None, "date": datetime.date(2024, 1, 1), "surrogate": "bad\ud800", "newline": "qa\n"}[shape]
c[section][key] = dict(next(iter(c[section].values())))
open(p, "w", encoding="utf-8", errors="surrogatepass").write(yaml.safe_dump(c, sort_keys=False, allow_unicode=True))
HOOK
      gen
      [ "$rc" -eq 1 ] || fails+="[$section/$shape] exit $rc"$'\n'
      case "$err" in *Traceback*) fails+="[$section/$shape] Traceback"$'\n' ;; esac
      case "$err" in *"invalid ${section%s} name $expect"*) ;; *) fails+="[$section/$shape] key not named: $err"$'\n' ;; esac
      [ ! -e "$TREE/adapters" ] || fails+="[$section/$shape] output generated"$'\n'
    done
  done
  [ -z "$fails" ] || { printf '%s' "$fails" >&2; return 1; }
}

@test "A1b group_dirs: absolute or ../ directory value -> named load-time error, nothing written outside the tree" {
  local val
  for val in "/tmp/a1b-escape-$$" "../../a1b-escape-$$" "x/y" ""; do
    make_tree "gd"
    python3 - "$TREE" "$val" <<'HOOK'
import sys, yaml
t, val = sys.argv[1:3]
p = f"{t}/adapters.yml"
c = yaml.safe_load(open(p))
c["adapters"]["claude-code"]["group_dirs"]["marketing"] = val
yaml.safe_dump(c, open(p, "w"), sort_keys=False)
HOOK
    gen
    [ "$rc" -eq 1 ] || { echo "[$val] expected exit 1, got $rc" >&2; return 1; }
    echo "$err" | grep -qF "group_dirs" || { echo "[$val] group_dirs not named: $err" >&2; return 1; }
    ! echo "$err" | grep -q Traceback || { echo "[$val] Traceback" >&2; return 1; }
    [ ! -e "$TREE/adapters" ] && [ ! -e "/tmp/a1b-escape-$$" ] && [ ! -e "$TREE/../../a1b-escape-$$" ] || { echo "[$val] output written" >&2; return 1; }
  done
}

@test "A1b command value types: alias / alias-of wrong type -> named load-time error, nothing generated" {
  local key pyval want spec fails=""
  for spec in "alias:'false':bool, got str" "alias:['plan']:bool, got list" "alias-of:['plan']:str, got list" "alias-of:None:str, got NoneType"; do
    IFS=: read -r key pyval want <<<"$spec"
    make_tree "cvt-$(echo "$key$pyval" | tr -cd 'a-z0-9')"
    python3 - "$TREE" "$key" "$pyval" <<'HOOK'
import ast, sys, yaml
t, key, pyval = sys.argv[1:4]
p = f"{t}/adapters.yml"
c = yaml.safe_load(open(p))
c["commands"]["qa"][key] = ast.literal_eval(pyval)
yaml.safe_dump(c, open(p, "w"), sort_keys=False)
HOOK
    gen
    [ "$rc" -eq 1 ] || fails+="[$spec] exit $rc"$'\n'
    case "$err" in *Traceback*) fails+="[$spec] Traceback"$'\n' ;; esac
    case "$err" in *"command 'qa' key '$key' must be $want"*) ;; *) fails+="[$spec] key not named: $err"$'\n' ;; esac
    [ ! -e "$TREE/adapters" ] || fails+="[$spec] output generated"$'\n'
  done
  [ -z "$fails" ] || { printf '%s' "$fails" >&2; return 1; }
}

@test "A1b description values: non-str entry in description / description-overrides -> named load-time error, nothing generated" {
  local dkey entry pyval spec fails=""
  for spec in "description:default:123" "description:default:None" "description-overrides:gemini:['x']" "description-overrides:codex:3.14"; do
    IFS=: read -r dkey entry pyval <<<"$spec"
    make_tree "dv-$(echo "$dkey$entry" | tr -cd 'a-z0-9')"
    python3 - "$TREE" "$dkey" "$entry" "$pyval" <<'HOOK'
import ast, sys, yaml
t, dkey, entry, pyval = sys.argv[1:5]
p = f"{t}/adapters.yml"
c = yaml.safe_load(open(p))
c["commands"]["qa"].setdefault(dkey, {})[entry] = ast.literal_eval(pyval)
yaml.safe_dump(c, open(p, "w"), sort_keys=False)
HOOK
    gen
    [ "$rc" -eq 1 ] || fails+="[$spec] exit $rc"$'\n'
    case "$err" in *Traceback*) fails+="[$spec] Traceback"$'\n' ;; esac
    case "$err" in *"key '$dkey' entry"*"must be a string"*) ;; *) fails+="[$spec] values not named: $err"$'\n' ;; esac
    [ ! -e "$TREE/adapters" ] || fails+="[$spec] output generated"$'\n'
  done
  [ -z "$fails" ] || { printf '%s' "$fails" >&2; return 1; }
}

# ── A1c: fail-loud re-cut of #157 (empty prompt, dangling alias-of, output checks) ──

@test "A1c row: prompt whitespace-only — counted named error (re-cut of #157)" {
  make_tree
  printf ' \n\t\n  \n' > "$TREE/prompts/qa.md"
  gen
  expect_counted_error "error: prompt for command 'qa' is empty or whitespace-only: prompts/qa.md"
}

@test "A1c row: alias-of naming a missing command — counted error naming both, no ghost output" {
  make_tree
  python3 - "$TREE" <<'HOOK'
import sys, yaml
t = sys.argv[1]
p = f"{t}/adapters.yml"
c = yaml.safe_load(open(p))
c["commands"]["ghost-alias"] = {"alias": True, "alias-of": "no-such-cmd",
                                "description": {"default": "x"}}
yaml.safe_dump(c, open(p, "w"), sort_keys=False, allow_unicode=True)
HOOK
  gen
  expect_counted_error "error: command 'ghost-alias' is an alias of 'no-such-cmd', which is not a configured command"
  [ ! -e "$TREE/adapters/claude-code/prp-ghost-alias.md" ] || { echo "ghost output written" >&2; return 1; }
}

@test "A1c row: empty description — validate_generated output check (b), counted error" {
  make_tree
  python3 - "$TREE" <<'HOOK'
import sys, yaml
t = sys.argv[1]
p = f"{t}/adapters.yml"
c = yaml.safe_load(open(p))
c["commands"]["qa"]["description"] = {"default": ""}
yaml.safe_dump(c, open(p, "w"), sort_keys=False, allow_unicode=True)
HOOK
  gen
  expect_counted_error "generated output adapters/claude-code/prp-qa.md has an empty description field"
}

@test "A1c row: the output check runs in --dry-run too — fails before writing anything" {
  make_tree
  python3 - "$TREE" <<'HOOK'
import sys, yaml
t = sys.argv[1]
p = f"{t}/adapters.yml"
c = yaml.safe_load(open(p))
c["commands"]["qa"]["description"] = {"default": ""}
yaml.safe_dump(c, open(p, "w"), sort_keys=False, allow_unicode=True)
HOOK
  rc2=0
  (cd "$TREE" && python3 scripts/generate-adapters.py --dry-run >"$BATS_TEST_TMPDIR/o" 2>"$BATS_TEST_TMPDIR/e") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo "expected exit 1 in --dry-run, got $rc2" >&2; return 1; }
  grep -qF 'generated output adapters/claude-code/prp-qa.md has an empty description field' "$BATS_TEST_TMPDIR/e" \
    || { echo "not validate_generated's error: $(cat "$BATS_TEST_TMPDIR/e")" >&2; return 1; }
  [ ! -e "$TREE/adapters/claude-code/prp-qa.md" ] || { echo "dry-run wrote output" >&2; return 1; }
}

@test "A1c validate_generated direct: each bad output shape raises naming the file" {
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
# a description containing "---" must not mis-split frontmatter from body
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

@test "A1c round-8 dash in value: validate_generated errors on the ws-only body (direct)" {
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
ga.validate_generated("claude-code/prp-x.md",
                      '---\ndescription: "pre---post"\n---\nreal body\n')
print("dash-in-value OK")
PYEOF
}

@test "A1c round-8 trailing-space delimiter: parsed as a delimiter (direct + validate)" {
  make_tree
  python3 - "$TREE/scripts/generate-adapters.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ga", sys.argv[1])
ga = importlib.util.module_from_spec(spec); spec.loader.exec_module(ga)
fm, body = ga.split_frontmatter("---\nk: v\n--- \nbody\n", "x.md")
assert (fm, body) == ("k: v", "body\n"), (fm, body)
try:
    ga.validate_generated("claude-code/prp-x.md", "---\ndescription: d\n--- \n   \n")
    raise SystemExit("BUG: trailing-space closer + ws body passed")
except ga.GenerationError as e:
    assert "empty command body" in str(e)
print("trailing-space OK")
PYEOF
}

@test "A1c round-8 CRLF + empty body: validate errors (direct)" {
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

@test "A1c round-8 no frontmatter: body as is, validate OK if non-empty (direct)" {
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

@test "A1c grep: split_frontmatter is the only splitter — def + read_overlay + validate_generated" {
  local script="$ROOT/scripts/generate-adapters.py"
  local p1 p2 rc1 rc2
  rc1=0; p1=$(grep -nF 'split("---"' "$script") || rc1=$?
  [ "$rc1" -eq 1 ] || { echo 'stray split("---" found:' >&2; printf '%s\n' "$p1" >&2; return 1; }
  rc2=0; p2=$(grep -nE 're\.split\(.*---' "$script") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo 'stray re.split on --- found:' >&2; printf '%s\n' "$p2" >&2; return 1; }
  [ "$(grep -c 'def split_frontmatter' "$script")" -eq 1 ]
  [ "$(grep -c 'split_frontmatter(' "$script")" -eq 3 ]  # def + read_overlay + validate_generated
}

# ── A1 re-plan #2: ONE exception boundary (tests/scripts/fault_inject.py) ──

@test "A1-r4b fault injection: every class x exception -> no Traceback, rc != 0, input named" {
  local fails="" klass exc token rc2 e2
  for klass in stat read yaml-config yaml-overlay overlay-type write; do
    case "$klass" in
      stat) token="prp-qa" ;;
      read) token="prompts/qa.md" ;;
      yaml-config) token="adapters.yml" ;;
      yaml-overlay|overlay-type) token="plan" ;;
      write) token="SKILL.md" ;;
    esac
    for exc in OSError UnicodeDecodeError YAMLError TypeError ValueError; do
      make_tree "fi-$klass-$exc"
      rc2=0
      e2=$(python3 "$ROOT/tests/scripts/fault_inject.py" "$TREE" "$klass" "$exc" 2>&1 >/dev/null) || rc2=$?
      [ "$rc2" -ne 0 ] || fails+="[$klass/$exc] exit 0"$'\n'
      case "$e2" in *Traceback*) fails+="[$klass/$exc] Traceback"$'\n' ;; esac
      case "$e2" in *"$token"*) ;; *) fails+="[$klass/$exc] '$token' not named: $e2"$'\n' ;; esac
    done
  done
  [ -z "$fails" ] || { printf '%s' "$fails" >&2; return 1; }
}

@test "A1-r4b fault injection: KeyboardInterrupt propagates (not swallowed by the boundary)" {
  make_tree
  local e2 rc2=0
  e2=$(python3 "$ROOT/tests/scripts/fault_inject.py" "$TREE" read KeyboardInterrupt 2>&1 >/dev/null) || rc2=$?
  [ "$rc2" -eq 3 ] && echo "$e2" | grep -qF "PROPAGATED KeyboardInterrupt" \
    || { echo "rc=$rc2 $e2" >&2; return 1; }
}

@test "A1-r4b partial failure: one of two inputs fails -> the other is produced, exactly 1 error" {
  make_tree
  local rc2=0 e2
  e2=$(python3 "$ROOT/tests/scripts/fault_inject.py" "$TREE" write OSError fresh 2>&1 >"$BATS_TEST_TMPDIR/p.out") || rc2=$?
  [ "$rc2" -eq 1 ] || { echo "expected exit 1, got $rc2: $e2" >&2; return 1; }
  grep -qE ', 1 errors' "$BATS_TEST_TMPDIR/p.out" || { echo "not exactly 1 error: $(tail -2 "$BATS_TEST_TMPDIR/p.out")" >&2; return 1; }
  [ -f "$TREE/adapters/claude-code/prp-qa.md" ] || { echo "other output not produced" >&2; return 1; }
  [ ! -f "$TREE/adapters/codex/prp-qa/SKILL.md" ] || { echo "failed output was written" >&2; return 1; }
}

@test "A1-r4b grep invariant: 'except Exception' only at the two boundaries; no bare except / BaseException" {
  local script="$ROOT/scripts/generate-adapters.py"
  [ "$(grep -cE '^\s*except Exception( as \w+)?:' "$script")" -eq 2 ] \
    || { grep -nE 'except Exception' "$script" >&2; return 1; }
  ! grep -nE '^\s*except\s*:|BaseException' "$script" >&2 || return 1
  # the two boundaries are generate_all and main
  local where
  where=$(awk '/^def /{f=$2; sub(/\(.*/,"",f)} /^[ ]*except Exception/{print f}' "$script" | sort | tr '\n' ' ')
  [ "$where" = "generate_all main " ] || { echo "boundaries in: $where" >&2; return 1; }
}

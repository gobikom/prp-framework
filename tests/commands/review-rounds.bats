#!/usr/bin/env bats
# Structure tests for prp-review-agents round discipline (prp-framework#151).
# Parts 1 + 2.4 (One Wake Per Round, no idle status pings) were pinned here first. Parts 2.1
# (pass timebox) and 2.2 (round cap) came back as STATELESS scripts (scripts/review/
# pass-budget.sh, round-guard.sh; plan 151-timebox-round-cap): the ledger / run-state / completion-
# proof machinery of the scope-cut attempt (#152 -> #154) must still not exist in any file, and the
# script references must be present in the prompt and all six adapters.
#
# Invariant (round-8 re-plan): every test here FAILS whenever the property it
# names does not hold — including when an input file is missing, unreadable,
# renamed, or the adapter set changes. The helpers never treat a grep ERROR
# (exit 2: bad pattern, unreadable file) as a pass, and the file set is an
# explicit expected list, so a renamed adapter breaks the set test loudly.
#
# Every test writes only under "$BATS_TEST_TMPDIR".
#
# Round-1 follow-up (prp-framework#156): the prose/param tests now cover every
# adapter individually (the blocking claim may appear only where every dispatch
# block carries the parameter), counting goes through count() so a grep error
# can never masquerade as a zero, and no test calls a `fail` helper — bats
# defines none; this file's echo+return 1 convention is used throughout.
#
# Run: bats tests/commands/review-rounds.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ADAPTER="$ROOT/adapters/claude-code/prp-review-agents.md"

# The ONE explicit expected file set: the prompt + all 6 adapters (7 files).
# A moved/renamed/deleted adapter changes this list's membership and fails
# the set test; every structure check below runs over this FULL list.
EXPECTED_FILES="
prompts/review-agents.md
adapters/antigravity/prp-review-agents.md
adapters/claude-code/prp-review-agents.md
adapters/codex/prp-review-agents/SKILL.md
adapters/gemini/review-agents.toml
adapters/opencode/review-agents.md
adapters/thclaws/prp-review-agents/SKILL.md
"

# The six adapter paths (EXPECTED_FILES minus the prompt) and the five
# non-claude-code adapters, as plain strings — bats' preprocessor accepts
# multi-line quoted strings (EXPECTED_FILES above) but not multi-line command
# substitution at top level. The list test below ("the adapter lists ...")
# asserts set-equality of these lists against EXPECTED_FILES, so adding or
# removing an adapter fails the tests until every list is updated (round-6
# Important B: the comment used to claim a cross-check that did not exist).
ADAPTER_FILES="adapters/antigravity/prp-review-agents.md
adapters/claude-code/prp-review-agents.md
adapters/codex/prp-review-agents/SKILL.md
adapters/gemini/review-agents.toml
adapters/opencode/review-agents.md
adapters/thclaws/prp-review-agents/SKILL.md"
OTHER_ADAPTERS="adapters/antigravity/prp-review-agents.md
adapters/codex/prp-review-agents/SKILL.md
adapters/gemini/review-agents.toml
adapters/opencode/review-agents.md
adapters/thclaws/prp-review-agents/SKILL.md"

# check_file FILE — fail unless FILE exists and is a readable regular file.
check_file() { # <file>
  if [ ! -e "$1" ]; then
    echo "input file missing: $1" >&2
    return 1
  fi
  if [ -L "$1" ] || [ ! -f "$1" ]; then
    echo "input is not a regular file: $1" >&2
    return 1
  fi
  if [ ! -r "$1" ]; then
    echo "input file unreadable: $1" >&2
    return 1
  fi
  return 0
}

# neg FILE ERE — the extended regex MUST NOT match FILE. Passes only on a clean
# "no match" (grep exit 1). A forbidden match (exit 0) or ANY error (exit >= 2:
# bad pattern, unreadable file) fails. Never silently passes on breakage.
# (grep runs inside `if` so bats' errexit cannot abort before the rc is seen.)
neg() { # <file> <ERE>
  check_file "$1" || return 1
  rc=0
  grep -qE -- "$2" "$1" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "forbidden pattern '$2' matched $1" >&2
    return 1
  fi
  if [ "$rc" -ne 1 ]; then
    echo "neg: grep error (exit $rc) for pattern '$2' on $1 — not a pass" >&2
    return 1
  fi
  return 0
}

# pos FILE ERE — the extended regex MUST match FILE. Passes only on a clean
# match (grep exit 0); no match (1) or any error (>= 2) fails.
pos() { # <file> <ERE>
  check_file "$1" || return 1
  rc=0
  grep -qE -- "$2" "$1" || rc=$?
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  echo "pos: pattern '$2' not found in $1 (grep exit $rc)" >&2
  return 1
}

# count FILE ERE — print the number of matching lines. A grep error (exit >= 2:
# bad pattern, unreadable/missing file) fails the test instead of printing a
# silent 0 — the old `n=$(grep -c ...) || n=0` idiom coerced errors into zeroes
# and could fabricate an equal-count pass.
count() { # <file> <ERE>
  check_file "$1" || return 1
  rc=0
  n=$(grep -cE -- "$2" "$1" 2>/dev/null) || rc=$?
  if [ "$rc" -ge 2 ]; then
    echo "count: grep error (exit $rc) for pattern '$2' on $1 — not a pass" >&2
    return 1
  fi
  [ "$rc" -eq 1 ] && n=0
  echo "$n"
}

# all_neg ERE / all_pos ERE — run neg/pos over the FULL expected file set.
all_neg() { # <ERE>
  for f in $EXPECTED_FILES; do
    neg "$ROOT/$f" "$1" || return 1
  done
  return 0
}

all_pos() { # <ERE>
  for f in $EXPECTED_FILES; do
    pos "$ROOT/$f" "$1" || return 1
  done
  return 0
}

@test "every Agent dispatch in the claude-code adapter passes run_in_background=false (#151 AC1)" {
  # prp-framework#151 AC1: on Claude Code 2.1.302 an Agent call runs in the
  # background unless run_in_background=false is passed — without it each
  # finished agent is its own task-notification turn (one wake per reviewer).
  # Count 'Agent(' dispatch blocks and 'run_in_background=false' parameters:
  # they must be equal, and at least 10 (3 core + 7 conditional).
  # Round-1 fix 2+4: counts come from count() (a missing/unreadable adapter or
  # grep error fails here instead of counting 0) and failures use this file's
  # echo+return 1 convention — bats defines no `fail` helper.
  local dispatches params
  dispatches=$(count "$ADAPTER" '^Agent\($') || return 1
  params=$(count "$ADAPTER" '^  run_in_background=false,$') || return 1
  [ "$dispatches" -ge 10 ] || {
    echo "expected at least 10 Agent dispatch blocks, counted: $dispatches" >&2
    return 1
  }
  [ "$dispatches" -eq "$params" ] || {
    echo "every Agent dispatch must pass run_in_background=false — dispatches: $dispatches, parameters: $params" >&2
    return 1
  }
  # R3 fix: equal totals do not prove pairing — one block could lose the
  # parameter while another gains a duplicate. Require the parameter on the
  # line directly after EVERY `Agent(` line, block by block.
  local unpaired
  unpaired=$(awk '
    prev == "Agent(" && $0 != "  run_in_background=false," { bad++ }
    { prev = $0 }
    END { print bad + 0 }
  ' "$ADAPTER") || return 1
  [ "$unpaired" -eq 0 ] || {
    echo "$unpaired Agent dispatch block(s) lack run_in_background=false directly after 'Agent('" >&2
    return 1
  }
}

@test "no other-runtime adapter carries the Claude-Code-only blocking kwarg (#151 AC1)" {
  # The kwarg is claude-code-only (adapters.yml: agent_blocking_param); the
  # generator's substitute_placeholders maps {AGENT_BLOCKING_PARAM} to "" for
  # every other runtime. No dispatch block in the other five adapters may
  # contain run_in_background — their Agent tools would reject the parameter.
  # Round-1 fix 2: neg() — a missing/renamed adapter or a grep error (exit 2)
  # now fails this test; the old `if grep -q` shape treated exit 2 as
  # "no match" and passed on a missing file.
  local f
  for f in $OTHER_ADAPTERS; do
    neg "$ROOT/$f" '^  run_in_background=false,$' || return 1
  done
}

@test "the blocking-prose claim is true in every adapter: claimed only where every dispatch carries it (#156 round 1)" {
  # The "therefore passes" sentence asserts that every Agent dispatch in THIS
  # adapter passes run_in_background=false. That is true only where the
  # dispatch blocks actually carry the parameter (claude-code). Where they do
  # not, the adapter must carry the scoped neutral sentence instead — never
  # the unscoped claim. (At f3869af all six adapters carried the claim while
  # five had zero parameters; this test fails on that text.)
  local f dispatches params claims
  for f in $ADAPTER_FILES; do
    dispatches=$(count "$ROOT/$f" '^Agent\($') || return 1
    params=$(count "$ROOT/$f" '^  run_in_background=false,$') || return 1
    claims=$(count "$ROOT/$f" 'therefore passes') || return 1
    [ "$dispatches" -ge 10 ] || {
      echo "$f: expected at least 10 Agent dispatch blocks, counted: $dispatches" >&2
      return 1
    }
    if [ "$claims" -gt 0 ]; then
      if [ "$params" -ne "$dispatches" ]; then
        echo "$f: prose claims every dispatch passes run_in_background=false, but dispatches: $dispatches, parameters: $params" >&2
        return 1
      fi
    else
      # no claim -> the scoped neutral sentence must carry the scoping instead
      # (matched by its stable first line: the value lives in adapters.yml and
      # its line wrapping may change without changing the scoping itself)
      pos "$ROOT/$f" 'In the Claude Code adapter every Agent' || return 1
    fi
  done
  # the source placeholders match the dispatch set: one {AGENT_BLOCKING_PARAM}
  # per Agent dispatch block, and exactly one {AGENT_BLOCKING_PROSE} sentence
  local prompt_params prompt_prose
  prompt_params=$(count "$ROOT/prompts/review-agents.md" '\{AGENT_BLOCKING_PARAM\}') || return 1
  prompt_prose=$(count "$ROOT/prompts/review-agents.md" '\{AGENT_BLOCKING_PROSE\}') || return 1
  [ "$prompt_params" -eq "$dispatches" ] || {
    echo "prompt has $prompt_params {AGENT_BLOCKING_PARAM} placeholders but the adapters have $dispatches dispatch blocks" >&2
    return 1
  }
  [ "$prompt_prose" -eq 1 ] || {
    echo "expected exactly 1 {AGENT_BLOCKING_PROSE} placeholder in the prompt, found: $prompt_prose" >&2
    return 1
  }
}

@test "the expected file set is exactly the prompt plus the 6 adapters, all present and readable" {
  n=0
  for f in $EXPECTED_FILES; do
    n=$((n + 1))
    check_file "$ROOT/$f" || return 1
  done
  # exactly 7 entries — an edited list (added/removed adapter) fails loudly
  [ "$n" -eq 7 ]
  # and no adapter file of the set was renamed on disk: each expected adapter
  # must exist (check_file above), and no OTHER file may sit at a renamed
  # variant of these paths (e.g. prp-review-agents.md -> review-agents-v2.md
  # in the same dir). The *feature*-review-agents files are a different
  # command's set and are excluded.
  for d in adapters/antigravity adapters/claude-code adapters/gemini adapters/opencode; do
    extra="$(find "$ROOT/$d" -maxdepth 1 -name '*review-agents*' ! -name '*feature*' -type f | sort)"
    want="$(for f in $EXPECTED_FILES; do case "$f" in "$d"/*) echo "$ROOT/$f";; esac; done | sort)"
    if [ "$extra" != "$want" ]; then
      echo "adapter set in $d differs from the expected list:" >&2
      diff <(echo "$want") <(echo "$extra") >&2 || true
      return 1
    fi
  done
  for d in adapters/codex/prp-review-agents adapters/thclaws/prp-review-agents; do
    n="$(find "$ROOT/$d" -maxdepth 1 -type f | wc -l)"
    [ "$n" -eq 1 ] || { echo "$d should hold exactly one SKILL.md, found $n files" >&2; return 1; }
  done
}

@test "the One Wake Per Round section is present in the prompt and all 6 adapters" {
  # anchored to the heading, not any mention of the phrase
  all_pos '^## One Wake Per Round'
  pos "$ADAPTER" "Dispatch all passes of the round in ONE message"
  pos "$ADAPTER" "Take no caller turn between dispatch and completion"
  pos "$ADAPTER" "No idle status pings"
  pos "$ADAPTER" "One round record, one decision"
  pos "$ADAPTER" "ONE_WAKE_PER_ROUND"
}

@test "the One Wake wait text never prescribes a pattern that hides a failed pass" {
  # ANY wait with two or more $-arguments (quoted or unquoted, any variable
  # names) hides every status but the last — over ALL 7 files. A wait with one
  # $-argument (the prescribed `wait "$pid1"` form) does not match.
  all_neg 'wait[[:space:]]+[^[:space:]]*\$[^[:space:]]*[[:space:]]+[^[:space:]]*\$'
  # waiting for ALL passes as ONE blocking unit is the prescribed shape
  all_pos "ONE blocking unit"
  # a non-zero or missing pass status is a failed pass (existing handling)
  all_pos "A non-zero or missing pass status counts as a failed pass"
  # the existing failed/timed-out handling is explicitly kept
  pos "$ADAPTER" "force verdict to NEEDS FIXES minimum"
}

@test "no ledger-era timebox machinery remains (scope-cut to 154)" {
  all_neg "PRP_REVIEW_PASS_BUDGET_MIN"
  all_neg "PASS_BUDGET_MIN"
  all_neg "DEADLINE_EPOCH"
  all_neg "pass-deadline"
  all_neg "Timebox: this pass runs under"
  all_neg "## Cut probes"
  all_neg "cut_probes"
}

@test "no completion-proof machinery remains (scope-cut to 154)" {
  all_neg "PASS COMPLETE"
  all_neg "status-dir"
  all_neg "STATUS_DIR"
  all_neg "prp-round-status"
  all_neg "CUT_PROBES"
  all_neg "completion gate"
  all_neg "completion proof"
  all_neg "Record Per-Pass Status"
  all_neg "COMPLETION_PROVEN"
  all_neg "PASS_TIMEBOX_ENFORCED"
}

@test "no ledger-era round-cap machinery remains (scope-cut to 154)" {
  all_neg "Step Cb"
  all_neg "curr-run\.env"
  all_neg "record-pending"
  all_neg "round-recorded"
  all_neg "round 11 refused"
  # 'review-rounds' names this very test file; scope-cut machinery used it as
  # a run-record dir name — match it only as a path-ish usage, not bare prose
  # (the tests dir is not in EXPECTED_FILES, so all_neg is safe here):
  all_neg "\.prp-output/review-rounds"
  # exactly THREE 'If this block prints FATAL' notes: 2.0 (round-cap), 2.1.1
  # (review clone), and 2.2.0 (pass-deadline mint, prp-framework#151 round-6)
  [ "$(grep -c 'If this block prints FATAL' "$ADAPTER")" -eq 3 ]
}

@test "the failed-pass handling of origin/main is pinned, not just diff-claimed" {
  pos "$ADAPTER" "READY TO MERGE verdict is never valid when a core agent is missing"
  pos "$ADAPTER" "MUST be at minimum NEEDS FIXES"
  pos "$ADAPTER" "force verdict to NEEDS FIXES minimum"
}

@test "Step A mints a fresh run id every run (origin or main behaviour)" {
  stepA="$BATS_TEST_TMPDIR/stepA.sh"
  awk -v want="**Step A" 'index($0, want) == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g' > "$stepA"
  [ -s "$stepA" ]
  neg "$stepA" 'curr-run\.env'
  pos "$stepA" 'RUN_ID="\$\(date -u \+%Y%m%dT%H%M%SZ\)-\$RAND"'
}

@test "the pass-deadline-mint FATAL guard actually aborts closed in the claude-code adapter: script failure and a broken .prp symlink (round-6 Important)" {
  guard="$BATS_TEST_TMPDIR/guard.sh"
  awk -v want="### 2.2.0 Pass Budget" 'index($0, want) == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" > "$guard"
  [ -s "$guard" ]
  pos "$guard" 'FATAL: cannot mint the pass deadline'
  pos "$guard" 'echo "PASS_DEADLINE=\$PASS_DEADLINE PRP_DIR=\$PRP_DIR"'

  work="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work"

  # Failure mode 1: pass-budget.sh itself exits non-zero (forced bad budget).
  ln -s "$ROOT" "$work/.prp"
  run bash -c "cd \"$work\" && PRP_PASS_BUDGET_SECS=abc bash \"$guard\""
  rm -f "$work/.prp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FATAL: cannot mint the pass deadline — no agents started"* ]]

  # Failure mode 2: .prp is a broken symlink (script path under it doesn't exist).
  ln -s "$BATS_TEST_TMPDIR/does-not-exist" "$work/.prp"
  run bash -c "cd \"$work\" && bash \"$guard\""
  rm -f "$work/.prp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FATAL: cannot mint the pass deadline — no agents started"* ]]

  # Success path: still mints the deadline AND now prints it (the regression
  # this test closes — a prior fix silently dropped the echo).
  ln -s "$ROOT" "$work/.prp"
  run bash -c "cd \"$work\" && bash \"$guard\""
  rm -f "$work/.prp"
  [ "$status" -eq 0 ]
  real_root="$(readlink -f "$ROOT")"
  [[ "$output" == *"PASS_DEADLINE="*"PRP_DIR=$real_root"* ]]
  [[ "$output" =~ PASS_DEADLINE=[0-9]+ ]]
}

@test "the FATAL guard and its pass-deadline echo line are pinned in the prompt and all 6 adapters, not just claude-code (round-7 Important)" {
  # The executable test above only extracts and runs the guard from the
  # claude-code adapter — it proves the fix works, but gives the other 6
  # files (which carry the byte-identical block per generate-adapters.py)
  # no regression net at all: any of them could silently lose the FATAL
  # guard or the echo line and CI would stay green. all_pos runs over the
  # FULL EXPECTED_FILES set (prompt + all 6 adapters), so a future edit
  # that drops either line from ANY one of the 7 files fails this test.
  all_pos 'FATAL: cannot mint the pass deadline'
  all_pos 'echo "PASS_DEADLINE=\$PASS_DEADLINE PRP_DIR=\$PRP_DIR"'
}

@test "the adapter lists match EXPECTED_FILES exactly (set equality; round-6 Important B)" {
  # ADAPTER_FILES must be EXPECTED_FILES minus the prompt; OTHER_ADAPTERS must
  # be ADAPTER_FILES minus claude-code. Set equality: a 7th adapter (or a
  # removed one) changes EXPECTED_FILES, and these lists must be updated in
  # the same commit or this test fails — no adapter can silently lose coverage.
  local expected_adapters expected_others
  expected_adapters="$(printf '%s\n' $EXPECTED_FILES | grep '^adapters/' | sort)"
  expected_others="$(printf '%s\n' $ADAPTER_FILES | grep -v '^adapters/claude-code/' | sort)"
  [ "$(printf '%s\n' $ADAPTER_FILES | sort)" = "$expected_adapters" ] || {
    echo "ADAPTER_FILES != EXPECTED_FILES adapters:" >&2
    diff <(printf '%s\n' $ADAPTER_FILES | sort) <(printf '%s\n' "$expected_adapters") >&2
    return 1
  }
  [ "$(printf '%s\n' $OTHER_ADAPTERS | sort)" = "$expected_others" ] || {
    echo "OTHER_ADAPTERS != ADAPTER_FILES minus claude-code:" >&2
    diff <(printf '%s\n' $OTHER_ADAPTERS | sort) <(printf '%s\n' "$expected_others") >&2
    return 1
  }
  # and exactly 6 / 5 entries
  [ "$(printf '%s\n' $ADAPTER_FILES | wc -l)" -eq 6 ]
  [ "$(printf '%s\n' $OTHER_ADAPTERS | wc -l)" -eq 5 ]
}

@test "the round-cap and pass-budget scripts are referenced in the prompt and all 6 adapters" {
  all_pos "scripts/review/round-guard\\.sh"
  all_pos "scripts/review/pass-budget\\.sh"
  all_pos "ROUND_CAP_ENFORCED"
  all_pos "PASS_TIMEBOXED_PARTIAL"
}

@test "every agent prompt in the claude-code adapter carries the pass budget line" {
  n=$(grep -c 'Read the PR context file at:' "$ADAPTER")
  b=$(grep -c 'Pass budget: PASS_DEADLINE=' "$ADAPTER")
  [ "$n" -ge 10 ] && [ "$n" -eq "$b" ]
}

@test "the round-cap guard runs in Phase 2.0 before the reviewed head is saved" {
  g=$(grep -n 'round-guard.sh" --cap 10' "$ADAPTER" | head -1 | cut -d: -f1)
  h=$(grep -n "> \"\$D/pr-{NUMBER}-reviewed-head\"" "$ADAPTER" | head -1 | cut -d: -f1)
  [ -n "$g" ] && [ -n "$h" ] && [ "$g" -lt "$h" ]
}

@test "the helper scripts are executable" {
  [ -x "$ROOT/scripts/review/round-guard.sh" ]
  [ -x "$ROOT/scripts/review/pass-budget.sh" ]
}

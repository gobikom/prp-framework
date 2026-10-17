#!/usr/bin/env bats
# Structure tests for prp-review-agents round discipline (prp-framework#151,
# Parts 1 + 2.4 only — One Wake Per Round and no idle status pings).
# Part 2.1 (pass timebox), Part 2.2 (round cap) and the completion-proof
# mechanism were scope-cut to gobikom/prp-framework#154 after review rounds
# 4–6; these tests pin that nothing of them remains and that the One Wake
# section survives regeneration in every adapter.
#
# Invariant (round-8 re-plan): every test here FAILS whenever the property it
# names does not hold — including when an input file is missing, unreadable,
# renamed, or the adapter set changes. The helpers never treat a grep ERROR
# (exit 2: bad pattern, unreadable file) as a pass, and the file set is an
# explicit expected list, so a renamed adapter breaks the set test loudly.
#
# Every test writes only under "$BATS_TEST_TMPDIR".
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
  [ -r "$ADAPTER" ] || { fail "adapter missing: $ADAPTER"; }
  local dispatches params
  dispatches=$(grep -c '^Agent($' "$ADAPTER") || dispatches=0
  params=$(grep -c '^  run_in_background=false,$' "$ADAPTER") || params=0
  [ "$dispatches" -ge 10 ] \
    || fail "expected at least 10 Agent dispatch blocks, counted: $dispatches"
  [ "$dispatches" -eq "$params" ] \
    || fail "every Agent dispatch must pass run_in_background=false — dispatches: $dispatches, parameters: $params"
}

@test "no other-runtime adapter carries the Claude-Code-only blocking kwarg (#151 AC1)" {
  # The kwarg is claude-code-only (adapters.yml: agent_blocking_param); the
  # generator's substitute_placeholders maps {AGENT_BLOCKING_PARAM} to "" for
  # every other runtime. No dispatch block in the other five adapters may
  # contain run_in_background — their Agent tools would reject the parameter.
  local f
  for f in \
    adapters/antigravity/prp-review-agents.md \
    adapters/codex/prp-review-agents/SKILL.md \
    adapters/gemini/review-agents.toml \
    adapters/opencode/review-agents.md \
    adapters/thclaws/prp-review-agents/SKILL.md
  do
    if grep -q '^  run_in_background=false,$' "$ROOT/$f"; then
      fail "non-claude-code adapter carries the blocking kwarg: $f"
    fi
  done
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

@test "no Part 2.1 timebox machinery remains (scope-cut to 154)" {
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

@test "no Part 2.2 round-cap machinery remains (scope-cut to 154)" {
  all_neg "Step Cb"
  all_neg "curr-run\.env"
  all_neg "record-pending"
  all_neg "round-recorded"
  all_neg "round 11 refused"
  # 'review-rounds' names this very test file; scope-cut machinery used it as
  # a run-record dir name — match it only as a path-ish usage, not bare prose
  # (the tests dir is not in EXPECTED_FILES, so all_neg is safe here):
  all_neg "\.prp-output/review-rounds"
  # exactly TWO 'If this block prints FATAL' notes for 2.0/2.1.1
  [ "$(grep -c 'If this block prints FATAL' "$ADAPTER")" -eq 2 ]
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

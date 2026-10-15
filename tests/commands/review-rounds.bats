#!/usr/bin/env bats
# Structure tests for prp-review-agents round discipline (prp-framework#151,
# Parts 1 + 2.4 only — One Wake Per Round and no idle status pings).
# Part 2.1 (pass timebox), Part 2.2 (round cap) and the completion-proof
# mechanism were scope-cut to gobikom/prp-framework#154 after review rounds
# 4–6; these tests pin that nothing of them remains and that the One Wake
# section survives regeneration in every adapter.
#
# Every test writes only under "$BATS_TEST_TMPDIR" (bats provides it per
# test; nothing is written into the repo or the caller's cwd).
#
# Negative assertions are never bare `! cmd` (bats' errexit semantics ignore
# a `!` command unless it is the test's LAST line, so a mid-test `!` cannot
# fail the test): each negative check is `run grep …; [ "$status" -ne 0 ]`
# or `if grep …; then return 1; fi`, so every line bites.
#
# Run: bats tests/commands/review-rounds.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ADAPTER="$ROOT/adapters/claude-code/prp-review-agents.md"
FRAMEWORK="$ROOT"

ADAPTERS="
adapters/antigravity/prp-review-agents.md
adapters/claude-code/prp-review-agents.md
adapters/codex/prp-review-agents/SKILL.md
adapters/gemini/review-agents.toml
adapters/opencode/review-agents.md
adapters/thclaws/prp-review-agents/SKILL.md
"

# neg <file> <pattern> — a grep that MUST NOT match; fails loudly when it does.
neg() { # <file> <grep-pattern>
  if grep -q -- "$2" "$1"; then
    echo "forbidden pattern '$2' matched $1" >&2
    return 1
  fi
  return 0
}

# pos <file> <pattern> — a grep that MUST match; fails loudly when it does not.
pos() { # <file> <grep-pattern>
  if ! grep -q -- "$2" "$1"; then
    echo "required pattern '$2' missing from $1" >&2
    return 1
  fi
  return 0
}

@test "the One Wake Per Round section is present in the prompt and all 6 adapters" {
  pos "$FRAMEWORK/prompts/review-agents.md" "One Wake Per Round"
  for a in $ADAPTERS; do
    pos "$FRAMEWORK/$a" "One Wake Per Round" || return 1
  done
  # Part 1: one dispatch message, no caller turn in between
  pos "$ADAPTER" "Dispatch all passes of the round in ONE message"
  pos "$ADAPTER" "Take no caller turn between dispatch and completion"
  # Part 2.4: no idle status pings
  pos "$ADAPTER" "No idle status pings"
  pos "$ADAPTER" "One round record, one decision"
  pos "$ADAPTER" "ONE_WAKE_PER_ROUND"
}

@test "the One Wake wait text never prescribes a pattern that hides a failed pass" {
  # no multi-pid wait example (returns only the last pid's status)
  neg "$ADAPTER" 'wait "\$pid1" "\$pid2"'
  neg "$ADAPTER" 'wait "\$pid1" "\$pid2" "\$pid3"'
  # waiting for ALL passes as ONE blocking unit is the prescribed shape
  pos "$ADAPTER" "ONE blocking unit"
  # the existing failed/timed-out handling is explicitly kept
  pos "$ADAPTER" "handled exactly as before"
  pos "$ADAPTER" "force verdict to NEEDS FIXES minimum"
}

@test "no Part 2.1 timebox machinery remains (scope-cut to 154)" {
  neg "$ADAPTER" "PRP_REVIEW_PASS_BUDGET_MIN"
  neg "$ADAPTER" "PASS_BUDGET_MIN"
  neg "$ADAPTER" "DEADLINE_EPOCH"
  neg "$ADAPTER" "pass-deadline"
  neg "$ADAPTER" "Timebox: this pass runs under"
  neg "$ADAPTER" "## Cut probes"
  neg "$ADAPTER" "cut_probes"
}

@test "no completion-proof machinery remains (scope-cut to 154)" {
  neg "$ADAPTER" "PASS COMPLETE"
  neg "$ADAPTER" "status-dir"
  neg "$ADAPTER" "STATUS_DIR"
  neg "$ADAPTER" "prp-round-status"
  neg "$ADAPTER" "CUT_PROBES"
  neg "$ADAPTER" "completion gate"
  neg "$ADAPTER" "completion proof"
  neg "$ADAPTER" "Record Per-Pass Status"
  neg "$ADAPTER" "Completion Gate"
  neg "$ADAPTER" "Completion check"
  neg "$ADAPTER" "COMPLETION_PROVEN"
  neg "$ADAPTER" "PASS_TIMEBOX_ENFORCED"
}

@test "no Part 2.2 round-cap machinery remains (scope-cut to 154)" {
  neg "$ADAPTER" "2\\.0a"
  neg "$ADAPTER" "Step Cb"
  neg "$ADAPTER" "curr-run\\.env"
  neg "$ADAPTER" "record-pending"
  neg "$ADAPTER" "round-recorded"
  neg "$ADAPTER" "review-rounds"
  neg "$ADAPTER" "round 11"
  # exactly TWO 'If this block prints FATAL' notes for 2.0/2.1.1 (no duplicated paragraphs)
  [ "$(grep -c 'If this block prints FATAL' "$ADAPTER")" -eq 2 ]
  # no glued-sentence artefacts from the removed sections
  neg "$ADAPTER" 'every mode\.A '
  neg "$ADAPTER" 'round 11 refused'
}

@test "the prompts file and all adapters carry no 2.1/2.2/completion-proof remnants" {
  for f in prompts/review-agents.md $ADAPTERS; do
    for pat in 'PRP_REVIEW_PASS_BUDGET_MIN' 'PASS COMPLETE' 'STATUS_DIR' 'CUT_PROBES' \
               'Timebox: this pass runs under' '## Cut probes' 'cut_probes' \
               'status-dir' 'pass-deadline' 'Completion Gate' 'Record Per-Pass' \
               'curr-run\.env' 'Step Cb' 'round 11'; do
      neg "$FRAMEWORK/$f" "$pat" || return 1
    done
  done
}

@test "the failed-pass handling of origin/main is pinned, not just diff-claimed" {
  # Phase 3 core-agent verdict floor (unchanged from origin/main)
  pos "$ADAPTER" "READY TO MERGE verdict is never valid when a core agent is missing"
  pos "$ADAPTER" "MUST be at minimum NEEDS FIXES"
  pos "$ADAPTER" "force verdict to NEEDS FIXES minimum"
}

@test "Step A mints a fresh run id every run (origin or main behaviour)" {
  stepA="$BATS_TEST_TMPDIR/stepA.sh"
  awk -v want="**Step A" 'index($0, want) == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g' > "$stepA"
  [ -s "$stepA" ]
  neg "$stepA" 'curr-run\.env'
  pos "$stepA" 'RUN_ID="\$(date -u +%Y%m%dT%H%M%SZ)-\$RAND"'
}

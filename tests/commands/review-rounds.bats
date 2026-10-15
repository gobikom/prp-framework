#!/usr/bin/env bats
# Structure tests for prp-review-agents round discipline (prp-framework#151,
# Parts 1 + 2.4 only — One Wake Per Round and no idle status pings).
# Part 2.1 (pass timebox), Part 2.2 (round cap) and the completion-proof
# mechanism were scope-cut to gobikom/prp-framework#154 after review rounds
# 4–6; these tests pin that nothing of them remains and that the One Wake
# section survives regeneration in every adapter.
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

@test "the One Wake Per Round section is present in the prompt and all 6 adapters" {
  grep -q "One Wake Per Round" "$FRAMEWORK/prompts/review-agents.md"
  for a in $ADAPTERS; do
    grep -q "One Wake Per Round" "$FRAMEWORK/$a"
  done
  # Part 1: one dispatch message, no caller turn in between
  grep -q "Dispatch all passes of the round in ONE message" "$ADAPTER"
  grep -q "Take no caller turn between dispatch and completion" "$ADAPTER"
  # Part 2.4: no idle status pings
  grep -q "No idle status pings" "$ADAPTER"
  grep -q "One round record, one decision" "$ADAPTER"
  grep -q "ONE_WAKE_PER_ROUND" "$ADAPTER"
}

@test "the One Wake wait text never prescribes a pattern that hides a failed pass" {
  # no multi-pid wait example (returns only the last pid's status)
  ! grep -qF 'wait "$pid1" "$pid2"' "$ADAPTER"
  ! grep -qF 'wait "$pid1" "$pid2" "$pid3"' "$ADAPTER"
  # waiting for ALL passes as ONE blocking unit is the prescribed shape
  grep -q "ONE blocking unit" "$ADAPTER"
  # the existing failed/timed-out handling is explicitly kept
  grep -q "handled exactly as before" "$ADAPTER"
  grep -q "force verdict to NEEDS FIXES minimum" "$ADAPTER"
}

@test "no Part 2.1 timebox machinery remains (scope-cut to 154)" {
  ! grep -q "PRP_REVIEW_PASS_BUDGET_MIN" "$ADAPTER"
  ! grep -q "PASS_BUDGET_MIN" "$ADAPTER"
  ! grep -q "DEADLINE_EPOCH" "$ADAPTER"
  ! grep -q "pass-deadline" "$ADAPTER"
  ! grep -q "Timebox: this pass runs under" "$ADAPTER"
  ! grep -q "## Cut probes" "$ADAPTER"
  ! grep -q "cut_probes" "$ADAPTER"
}

@test "no completion-proof machinery remains (scope-cut to 154)" {
  ! grep -q "PASS COMPLETE" "$ADAPTER"
  ! grep -q "status-dir" "$ADAPTER"
  ! grep -q "STATUS_DIR" "$ADAPTER"
  ! grep -q "prp-round-status" "$ADAPTER"
  ! grep -q "CUT_PROBES" "$ADAPTER"
  ! grep -q "completion gate" "$ADAPTER"
  ! grep -q "completion proof" "$ADAPTER"
  ! grep -q "Record Per-Pass Status" "$ADAPTER"
  ! grep -q "Completion Gate" "$ADAPTER"
  ! grep -q "Completion check" "$ADAPTER"
  ! grep -q "COMPLETION_PROVEN" "$ADAPTER"
  ! grep -q "PASS_TIMEBOX_ENFORCED" "$ADAPTER"
}

@test "no Part 2.2 round-cap machinery remains (scope-cut to 154)" {
  ! grep -q "2\.0a" "$ADAPTER"
  ! grep -q "Step Cb" "$ADAPTER"
  ! grep -q "curr-run\.env" "$ADAPTER"
  ! grep -q "record-pending" "$ADAPTER"
  ! grep -q "round-recorded" "$ADAPTER"
  ! grep -q "review-rounds" "$ADAPTER"
  ! grep -q "round 11" "$ADAPTER"
  # exactly TWO 'If this block prints FATAL' notes for 2.0/2.1.1 (no duplicated paragraphs)
  [ "$(grep -c 'If this block prints FATAL' "$ADAPTER")" -eq 2 ]
  # no glued-sentence artefacts from the removed sections
  ! grep -q 'every mode\.A ' "$ADAPTER"
  ! grep -q 'round 11 refused' "$ADAPTER"
}

@test "the prompts file and all adapters carry no 2.1/2.2/completion-proof remnants" {
  for f in prompts/review-agents.md $ADAPTERS; do
    for pat in 'PRP_REVIEW_PASS_BUDGET_MIN' 'PASS COMPLETE' 'STATUS_DIR' 'CUT_PROBES' \
               'Timebox: this pass runs under' '## Cut probes' 'cut_probes' \
               'status-dir' 'pass-deadline' 'Completion Gate' 'Record Per-Pass' \
               'curr-run\.env' 'Step Cb' 'round 11'; do
      if grep -q "$pat" "$FRAMEWORK/$f"; then
        echo "remnant '$pat' found in $f"; return 1
      fi
    done
  done
}

@test "Step A mints a fresh run id every run (origin or main behaviour)" {
  awk -v want="**Step A" 'index($0, want) == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g' > stepA.sh
  [ -s stepA.sh ]
  ! grep -q 'curr-run\.env' stepA.sh
  grep -q 'RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-\$RAND"' stepA.sh
}

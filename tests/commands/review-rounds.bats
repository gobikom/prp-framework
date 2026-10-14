#!/usr/bin/env bats
# Behaviour tests for prp-review-agents round discipline (prp-framework#151,
# Parts 1 / 2.1 / 2.4 only — Part 2.2, the enforced round cap, was scope-cut to
# gobikom/prp-framework#154). Covered here: the 2.1a pass timebox (base-10,
# fail-closed, symlink-safe deadline write) and the 3.5 cut-probes follow-up
# issue. The bash fences are extracted from the generated claude-code adapter
# and run as separate shells — as an agent does.
#
# Run: bats tests/commands/review-rounds.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ADAPTER="$ROOT/adapters/claude-code/prp-review-agents.md"

# block <heading-marker> — the bash fence that follows the marker line.
block() {
  awk -v want="$1" 'index($0, want) == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g'
}

setup() {
  WORK="$(mktemp -d)"
  cd "$WORK"
  mkdir -p .prp-output/reviews bin
  # gh stub: issue create logs its args; nothing else is needed by these blocks.
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "issue" ] && [ "$2" = "create" ]; then
  echo "$@" >> "$ISSUE_LOG"
  echo "https://github.com/o/r/issues/$(( $(wc -l < "$ISSUE_LOG") ))"
  exit 0
fi
exit 2
EOF
  chmod +x bin/gh
  export PATH="$WORK/bin:$PATH" ISSUE_LOG="$WORK/issues.log"
  : > "$ISSUE_LOG"
  block "### 2.1a" > budget.sh
  block "### 3.5" > followup.sh
  [ -s budget.sh ] && [ -s followup.sh ]
}

teardown() { rm -rf "$WORK"; }

# ─── structure: Parts 1 / 2.1 / 2.4 present, Part 2.2 absent ──────

@test "the adapter documents the One Wake Per Round section and the timebox prompt line" {
  grep -q "One Wake Per Round" "$ADAPTER"
  grep -q "PRP_REVIEW_PASS_BUDGET_MIN" "$ADAPTER"
  grep -q "## Cut probes" "$ADAPTER"
  grep -q "No idle status pings" "$ADAPTER"
  # every reviewer prompt carries the timebox: 1 template in 2.1a + 10 agent prompts
  [ "$(grep -c 'Timebox: this pass runs under' "$ADAPTER")" -eq 11 ]
}

@test "no Part 2.2 machinery remains in the adapter (scope-cut to 154)" {
  ! grep -q "2\.0a" "$ADAPTER"
  ! grep -q "Step Cb" "$ADAPTER"
  ! grep -q "curr-run\.env" "$ADAPTER"
  ! grep -q "record-pending" "$ADAPTER"
  ! grep -q "round-recorded" "$ADAPTER"
  ! grep -q "review-rounds" "$ADAPTER"
  ! grep -q "round 11" "$ADAPTER"
  # exactly ONE 'If this block prints FATAL' note for 2.0/2.1.1 (no duplicated paragraphs)
  [ "$(grep -c 'If this block prints FATAL' "$ADAPTER")" -eq 2 ]
  # no glued-sentence artefacts from the removed sections
  ! grep -q 'every mode\.A ' "$ADAPTER"
  ! grep -q 'round 11 refused' "$ADAPTER"
}

@test "Step A mints a fresh run id every run (origin or main behaviour)" {
  # no curr-run.env reuse anywhere in Step A's fence
  ! grep -q 'curr-run\.env' "$(block '**Step A' > /dev/null; echo stepA)"
  block "**Step A" | grep -q 'RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-\$RAND"'
}

# ─── 2.1a pass timebox ────────────────────────────────────────────

@test "unset budget defaults to 20 minutes and saves the deadline" {
  before=$(date +%s)
  run env -u PRP_REVIEW_PASS_BUDGET_MIN bash budget.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "PASS_BUDGET_MIN=20 "* ]]
  d=$(sed -n 's/^deadline=//p' .prp-output/reviews/pr-7-pass-deadline)
  b=$(sed -n 's/^budget_min=//p' .prp-output/reviews/pr-7-pass-deadline)
  [ "$b" = "20" ]
  [ "$d" -ge $(( before + 20 * 60 )) ]
  [ "$d" -le $(( $(date +%s) + 20 * 60 )) ]
}

@test "a forced short budget is respected (forced-timebox test)" {
  run env PRP_REVIEW_PASS_BUDGET_MIN=1 bash budget.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "PASS_BUDGET_MIN=1 "* ]]
  b=$(sed -n 's/^budget_min=//p' .prp-output/reviews/pr-7-pass-deadline)
  d=$(sed -n 's/^deadline=//p' .prp-output/reviews/pr-7-pass-deadline)
  [ "$b" = "1" ]
  [ "$d" -le $(( $(date +%s) + 60 )) ]
}

@test "garbage budgets fail closed with no deadline file" {
  for bad in 0 241 abc 20min -3 08 010 ""; do
    rm -f .prp-output/reviews/pr-7-pass-deadline
    run env PRP_REVIEW_PASS_BUDGET_MIN="$bad" bash budget.sh
    [ "$status" -ne 0 ] || { echo "budget '$bad' was accepted"; return 1; }
    [[ "$output" == *"PRP_REVIEW_PASS_BUDGET_MIN must be a base-10 integer 1..240"* ]]
    [ ! -f .prp-output/reviews/pr-7-pass-deadline ]
    [ ! -e .prp-output/reviews/.pr-7-pass-deadline.* ]   # no leftover tmp
  done
}

@test "boundary budgets 1 and 240 are accepted" {
  run env PRP_REVIEW_PASS_BUDGET_MIN=1 bash budget.sh
  [ "$status" -eq 0 ]
  run env PRP_REVIEW_PASS_BUDGET_MIN=240 bash budget.sh
  [ "$status" -eq 0 ]
}

@test "an earlier round's deadline file is replaced" {
  printf 'deadline=1\nbudget_min=1\n' > .prp-output/reviews/pr-7-pass-deadline
  run env PRP_REVIEW_PASS_BUDGET_MIN=2 bash budget.sh
  [ "$status" -eq 0 ]
  b=$(sed -n 's/^budget_min=//p' .prp-output/reviews/pr-7-pass-deadline)
  [ "$b" = "2" ]
  [ -f .prp-output/reviews/pr-7-pass-deadline ] && [ ! -L .prp-output/reviews/pr-7-pass-deadline ]
}

@test "a symlink at the deadline path is refused, not written through" {
  target="$WORK/victim.txt"
  printf 'do-not-overwrite\n' > "$target"
  ln -s "$target" .prp-output/reviews/pr-7-pass-deadline
  run env PRP_REVIEW_PASS_BUDGET_MIN=5 bash budget.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"is a symlink"* ]]
  [ "$(cat "$target")" = "do-not-overwrite" ]        # victim untouched
  [ -L .prp-output/reviews/pr-7-pass-deadline ]       # link left for hand repair
}

@test "a non-regular deadline path fails closed" {
  rm -f .prp-output/reviews/pr-7-pass-deadline
  mkdir -p .prp-output/reviews/pr-7-pass-deadline
  run env PRP_REVIEW_PASS_BUDGET_MIN=5 bash budget.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a regular file"* ]]
}

@test "no leftover temp files after a successful write" {
  run env PRP_REVIEW_PASS_BUDGET_MIN=5 bash budget.sh
  [ "$status" -eq 0 ]
  [ -z "$(ls -A .prp-output/reviews | grep -F 'pass-deadline.')" ]
}

# ─── 3.5 follow-up issue for cut probes ───────────────────────────

@test "cut probes create exactly one follow-up issue carrying every probe" {
  export CUT_PROBES_COUNT=2 CUT_PROBES_BODY="- [security-reviewer] reachability of the /admin route
- [silent-failure-hunter] exit-code path of the cleanup script"
  run bash followup.sh
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$ISSUE_LOG")" -eq 1 ]
  [[ "$output" == *"issues/1"* ]]
  run grep -c "review-followup: cut probes from PR #7" "$ISSUE_LOG"
  [ "$output" -eq 1 ]
  grep -q "reachability of the /admin route" .prp-output/reviews/pr-7-cut-probes.md
  grep -q "exit-code path of the cleanup script" .prp-output/reviews/pr-7-cut-probes.md
}

@test "no cut probes create no issue" {
  export CUT_PROBES_COUNT=0
  run bash followup.sh
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$ISSUE_LOG")" -eq 0 ]
  [ ! -f .prp-output/reviews/pr-7-cut-probes.md ]
}

@test "a failing gh issue create warns but does not fail the round" {
  export CUT_PROBES_COUNT=1 CUT_PROBES_BODY="- probe"
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x bin/gh
  run bash followup.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: could not create the cut-probes follow-up issue"* ]]
  [ -f .prp-output/reviews/pr-7-cut-probes.md ]
}

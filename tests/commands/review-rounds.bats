#!/usr/bin/env bats
# Behaviour tests for prp-review-agents round discipline (prp-framework#151):
# the 2.0a round cap, the 2.1a pass timebox, the 3.5 cut-probes follow-up issue,
# and the Step Cb round recording. The bash fences are extracted from the
# generated claude-code adapter and run as separate shells — as an agent does.
#
# Run: bats tests/commands/review-rounds.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ADAPTER="$ROOT/adapters/claude-code/prp-review-agents.md"

# block <heading-marker> — the bash fence that follows the marker line.
# Markers must be unique: "### 2.0a", "### 2.1a", "### 3.5", "**Step Cb".
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
  block "### 2.0a" > cap.sh
  block "### 2.1a" > budget.sh
  block "### 3.5" > followup.sh
  block "**Step Cb" > record.sh
  block "**Step Cb-agg" > recordagg.sh
  [ -s cap.sh ] && [ -s budget.sh ] && [ -s followup.sh ] && [ -s record.sh ] && [ -s recordagg.sh ]
}

teardown() { rm -rf "$WORK"; }

# ─── 2.0a round cap ───────────────────────────────────────────────

@test "the adapter documents the One Wake Per Round section and the timebox prompt line" {
  grep -q "One Wake Per Round" "$ADAPTER"
  grep -q "PRP_REVIEW_PASS_BUDGET_MIN" "$ADAPTER"
  grep -q "## Cut probes" "$ADAPTER"
  grep -q "round 11 refused" "$ADAPTER"
  # every reviewer prompt carries the timebox: the context-file line appears once per agent prompt
  [ "$(grep -c 'Timebox: this pass runs under' "$ADAPTER")" -eq 11 ]  # 1 template in 2.1a + 10 reviewer prompts
}

@test "no ledger file means round 1 of 10" {
  run bash cap.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "REVIEW_ROUND=1 of 10 (recorded: 0)"* ]]
}

@test "nine recorded rounds allow the 10th" {
  printf 'round=9\n' > .prp-output/reviews/pr-7-review-rounds
  run bash cap.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "REVIEW_ROUND=10 of 10 (recorded: 9)"* ]]
}

@test "ten recorded rounds refuse round 11 with FATAL and write nothing" {
  printf 'round=10\n' > .prp-output/reviews/pr-7-review-rounds
  run bash cap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"round 11 refused"* ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=10" ]
}

@test "a garbage ledger fails closed" {
  printf 'round=abc\n' > .prp-output/reviews/pr-7-review-rounds
  run bash cap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid rounds ledger"* ]]
  printf 'round=1\nround=2\n' > .prp-output/reviews/pr-7-review-rounds
  run bash cap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid rounds ledger"* ]]
}

@test "leading-zero ledger values are refused, not read as octal" {
  for bad in 08 010; do
    printf 'round=%s\n' "$bad" > .prp-output/reviews/pr-7-review-rounds
    run bash cap.sh
    [ "$status" -ne 0 ] || { echo "ledger 'round=$bad' was accepted"; return 1; }
    [[ "$output" == *"not a valid rounds ledger"* ]]
    [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=$bad" ]
  done
}

@test "an empty ledger file is refused" {
  : > .prp-output/reviews/pr-7-review-rounds
  run bash cap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid rounds ledger"* ]]
}

@test "a ledger path that is a directory fails closed" {
  rm -f .prp-output/reviews/pr-7-review-rounds
  mkdir -p .prp-output/reviews/pr-7-review-rounds
  run bash cap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a regular file"* ]]
}

@test "2.0a clears the last round's recording markers" {
  printf 'round=2\n' > .prp-output/reviews/pr-7-review-rounds
  printf '20260101T000000Z-stale012\n' > .prp-output/reviews/pr-7-round-recorded
  printf 'AGG_RUN_ID=20260101T000000Z-stale012\n' > .prp-output/reviews/pr-7-agg-run.env
  run bash cap.sh
  [ "$status" -eq 0 ]
  [ ! -e .prp-output/reviews/pr-7-round-recorded ]
  [ ! -e .prp-output/reviews/pr-7-agg-run.env ]
}

@test "an over-cap ledger value is refused, not reset" {
  printf 'round=99\n' > .prp-output/reviews/pr-7-review-rounds
  run bash cap.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"round 11 refused"* ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=99" ]
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
  done
}

@test "leading-zero budgets fail closed (octal trap: 08, 010)" {
  for bad in 08 010 020; do
    rm -f .prp-output/reviews/pr-7-pass-deadline
    run env PRP_REVIEW_PASS_BUDGET_MIN="$bad" bash budget.sh
    [ "$status" -ne 0 ] || { echo "budget '$bad' was accepted"; return 1; }
    [ ! -f .prp-output/reviews/pr-7-pass-deadline ]
  done
}

@test "boundary budgets 1 and 240 are accepted" {
  run env PRP_REVIEW_PASS_BUDGET_MIN=1 bash budget.sh
  [ "$status" -eq 0 ]
  run env PRP_REVIEW_PASS_BUDGET_MIN=240 bash budget.sh
  [ "$status" -eq 0 ]
}

@test "an earlier round's deadline file is cleared" {
  printf 'deadline=1\nbudget_min=1\n' > .prp-output/reviews/pr-7-pass-deadline
  run env PRP_REVIEW_PASS_BUDGET_MIN=2 bash budget.sh
  [ "$status" -eq 0 ]
  b=$(sed -n 's/^budget_min=//p' .prp-output/reviews/pr-7-pass-deadline)
  [ "$b" = "2" ]
}

# ─── 3.5 follow-up issue for cut probes ───────────────────────────

@test "cut probes create exactly one follow-up issue carrying every probe" {
  export CUT_PROBES_COUNT=2 CUT_PROBES_BODY="- [security-reviewer] reachability of the /admin route
- [silent-failure-hunter] exit-code path of the cleanup script" REVIEW_ROUND=3 RUN_ID=20260101T000000Z-deadbeef
  run bash followup.sh
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$ISSUE_LOG")" -eq 1 ]
  [[ "$output" == *"issues/1"* ]]
  run grep -c "review-followup: cut probes from PR #7 round 3" "$ISSUE_LOG"
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
  export CUT_PROBES_COUNT=1 CUT_PROBES_BODY="- probe" REVIEW_ROUND=1 RUN_ID=20260101T000000Z-deadbeef
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

# ─── Step Cb round recording ──────────────────────────────────────

used_run() {  # simulate Step A + Step C having consumed the run file
  printf 'REVIEWED_HEAD_SHA=%s\nPRP_VERSION=9.9.9\nRUN_ID=%s\n' \
    "0123456789abcdef0123456789abcdef01234567" "$1" > .prp-output/reviews/pr-7-l2-run.env.used
}

@test "a completed posting records the round" {
  used_run 20260101T000000Z-aaaaaaaa
  run bash record.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "RECORDED_ROUND=1" ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=1" ]
  [ "$(cat .prp-output/reviews/pr-7-round-recorded)" = "20260101T000000Z-aaaaaaaa" ]
}

@test "recording is idempotent per run id" {
  used_run 20260101T000000Z-aaaaaaaa
  bash record.sh >/dev/null
  run bash record.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-op"* ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=1" ]
}

@test "a new run increments the ledger" {
  used_run 20260101T000000Z-aaaaaaaa
  bash record.sh >/dev/null
  used_run 20260101T010101Z-bbbbbbbb
  run bash record.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "RECORDED_ROUND=2" ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=2" ]
}

@test "recording round 11 is refused (a failed post consumes nothing, cap holds)" {
  printf 'round=10\n' > .prp-output/reviews/pr-7-review-rounds
  used_run 20260101T000000Z-aaaaaaaa
  run bash record.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"round 11 cannot be recorded"* ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=10" ]
}

@test "no consumed run file records nothing" {
  run bash record.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"no consumed run file"* ]]
  [ ! -f .prp-output/reviews/pr-7-review-rounds ]
}

@test "a garbage ledger refuses to record" {
  printf 'round=x\n' > .prp-output/reviews/pr-7-review-rounds
  used_run 20260101T000000Z-aaaaaaaa
  run bash record.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid rounds ledger"* ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=x" ]
}

@test "a leading-zero ledger refuses to record (no octal parse)" {
  printf 'round=08\n' > .prp-output/reviews/pr-7-review-rounds
  used_run 20260101T000000Z-aaaaaaaa
  run bash record.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid rounds ledger"* ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=08" ]
}

# ─── Step Cb-agg: aggregated mode (no --l2-comments) ──────────────

@test "aggregated mode: first invocation mints a run id and records nothing" {
  run bash recordagg.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"AGG_RUN_ID="*"re-run this block to record the round"* ]]
  [ -f .prp-output/reviews/pr-7-agg-run.env ]
  [ ! -f .prp-output/reviews/pr-7-review-rounds ]
  [ ! -f .prp-output/reviews/pr-7-round-recorded ]
}

@test "aggregated mode: the re-run after posting records the round exactly once" {
  bash recordagg.sh >/dev/null
  run bash recordagg.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "RECORDED_ROUND=1" ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=1" ]
  # third run is a no-op
  run bash recordagg.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-op"* ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=1" ]
}

@test "aggregated mode: a stale L2 .used file changes nothing" {
  printf 'REVIEWED_HEAD_SHA=%s\nPRP_VERSION=9.9.9\nRUN_ID=%s\n' \
    "0123456789abcdef0123456789abcdef01234567" "20260101T000000Z-stale012" > .prp-output/reviews/pr-7-l2-run.env.used
  run bash recordagg.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"AGG_RUN_ID="*"re-run this block to record the round"* ]]
  AGG=$(sed -n 's/^AGG_RUN_ID=//p' .prp-output/reviews/pr-7-agg-run.env)
  [ "$AGG" != "20260101T000000Z-stale012" ]
  bash recordagg.sh >/dev/null
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=1" ]
  [ "$(cat .prp-output/reviews/pr-7-round-recorded)" = "$AGG" ]
}

@test "aggregated mode: round 11 is refused" {
  printf 'round=10\n' > .prp-output/reviews/pr-7-review-rounds
  bash recordagg.sh >/dev/null
  run bash recordagg.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"round 11 cannot be recorded"* ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=10" ]
}

@test "aggregated mode: a garbage agg run file records nothing" {
  printf 'AGG_RUN_ID=not-a-run-id\n' > .prp-output/reviews/pr-7-agg-run.env
  run bash recordagg.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"bad run id"* ]]
  [ ! -f .prp-output/reviews/pr-7-review-rounds ]
}

@test "aggregated mode: a second round increments via a fresh minted id" {
  bash recordagg.sh >/dev/null && bash recordagg.sh >/dev/null   # round 1 recorded
  rm -f .prp-output/reviews/pr-7-agg-run.env                      # 2.0a of the next round cleared it
  bash recordagg.sh >/dev/null                                    # mint round 2's id
  run bash recordagg.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "RECORDED_ROUND=2" ]]
  [ "$(cat .prp-output/reviews/pr-7-review-rounds)" = "round=2" ]
}

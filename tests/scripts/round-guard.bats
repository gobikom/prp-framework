#!/usr/bin/env bats
# Helper-level tests for scripts/review/round-guard.sh (prp-framework#151 AC3).
# The Phase 2.0 wiring arms are in tests/commands/l2-comments.bats.
#
# Run: bats tests/scripts/round-guard.bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
G="$REPO_ROOT/scripts/review/round-guard.sh"

setup() { TEST_TMPDIR="$(mktemp -d)"; cd "$TEST_TMPDIR"; }
teardown() { cd /; rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

# runs_footers <n> [suffix] -> three footer lines per run id (run i = 2026010<i>…)
runs_footers() {
  local i p
  for ((i = 1; i <= $1; i++)); do
    for p in code-reviewer security-reviewer silent-failure-hunter; do
      printf 'Generated-by: prp-review-agents v2.12.0 run=20261021T%06dZ-%08x pass=%s%s\n' "$i" "$i" "$p" "${2:-}"
    done
  done
}

# boundary_footers -> 9 distinct exact footers (one run id each), used by the
# line-33 fail-closed fallback boundary tests below (R1 Important, brief
# 20261024-1955-a211): each test appends one more, differently-shaped, 10th
# line and asserts how it must be counted.
boundary_footers() {
  local i
  for ((i = 1; i <= 9; i++)); do
    printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z-%08x pass=code-reviewer\n' "$i"
  done
}

@test "empty input is round 1" {
  run bash "$G" </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"this is round 1"* ]]
}

@test "nine runs allow round 10" {
  run bash -c "$(declare -f runs_footers); runs_footers 9 | bash '$G'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10; this is round 10"* ]]
}

@test "ten runs refuse round 11 with a clear message" {
  run bash -c "$(declare -f runs_footers); runs_footers 10 | bash '$G'"
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP: refused"* ]]
  [[ "$output" == *"10 review runs (cap 10)"* ]]
  [[ "$output" == *"stop rule"* ]]
}

@test "eleven runs are refused" {
  run bash -c "$(declare -f runs_footers); runs_footers 11 | bash '$G'"
  [ "$status" -eq 3 ]
}

@test "three comments of one run count once and a trivial run counts once" {
  {
    runs_footers 1
    printf 'Generated-by: prp-review-agents v2.12.0 run=20261022T000000Z-aaaaaaaa pass=code-reviewer tier=trivial\n'
  } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 2 of 10"* ]]
}

@test "the same ten run ids repeated still count ten" {
  { runs_footers 10; runs_footers 10; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
}

@test "a malformed review footer fails closed" {
  printf 'Generated-by: prp-review-agents v2 run=BAD pass=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot parse a review footer"* ]]
}

@test "a footer without a pass fails closed" {
  printf 'Generated-by: prp-review-agents v2.12.0 run=20261021T000001Z-00000001\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "ordinary last lines, null and blanks are ignored" {
  printf 'LGTM\nnull\n\n   \nGenerated-by: someone-else v1 run=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"this is round 1"* ]]
}

@test "an unterminated final footer line is still read" {
  printf 'Generated-by: prp-review-agents v2.12.0 run=20261021T000001Z-00000001 pass=code-reviewer' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 1 of 10"* ]]
}

@test "a lower cap is honoured" {
  run bash -c "$(declare -f runs_footers); runs_footers 2 | bash '$G' --cap 2"
  [ "$status" -eq 3 ]
}

@test "bad cap values exit 2 and run nothing" {
  for bad in 0 abc 99999 -1 "" "1 2" '$(touch PWNED)' '`touch PWNED`' 'a[$(touch PWNED)]' 08x; do
    run bash "$G" --cap "$bad" </dev/null
    [ "$status" -eq 2 ]
  done
  [ ! -e PWNED ]
}

@test "a leading zero cap is a decimal number not octal" {
  run bash -c "$(declare -f runs_footers); runs_footers 7 | bash '$G' --cap 08"
  [ "$status" -eq 0 ]
  run bash -c "$(declare -f runs_footers); runs_footers 8 | bash '$G' --cap 08"
  [ "$status" -eq 3 ]
}

@test "unknown arguments exit 2" {
  run bash "$G" --nope </dev/null
  [ "$status" -eq 2 ]
  run bash "$G" --cap </dev/null
  [ "$status" -eq 2 ]
}

@test "an exact 10th footer with a new run id hits the cap" {
  { boundary_footers; printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
}

@test "a 10th footer with a leading space fails closed" {
  { boundary_footers; printf ' Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th footer with a leading tab fails closed" {
  { boundary_footers; printf '\tGenerated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th footer with a trailing CR fails closed" {
  { boundary_footers; printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\r\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th footer in lower case fails closed" {
  { boundary_footers; printf 'generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th footer quoted mid-line fails closed" {
  { boundary_footers; printf 'see "Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer"\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th line that is genuinely unrelated is ignored" {
  { boundary_footers; printf 'LGTM\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

# R2 (brief 20261024-2110-b211, plan 211-round-guard-footer-shape.plan.md): four more
# near-footer shapes that must refuse, plus the real-data rows that must NOT refuse.

@test "a 10th footer with reversed word order fails closed" {
  { boundary_footers; printf 'prp-review-agents Generated-by: v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th footer missing the colon fails closed" {
  { boundary_footers; printf 'Generated-by prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th footer with a space instead of a hyphen fails closed" {
  { boundary_footers; printf 'Generated by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th footer split over two lines (tail only) fails closed" {
  { boundary_footers; printf 'prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a 10th line with only the footer's body fails closed" {
  { boundary_footers; printf 'v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a real 9-hex malformed run id fails closed" {
  { boundary_footers; printf 'Generated-by: prp-review-agents v2.12.0 run=20261022T044148Z-312938296 pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a real L2 marker is ignored, not refused" {
  { boundary_footers; printf '<!-- safe-merge-review: verdict=READY_TO_MERGE critical=0 important=0 agents=code-reviewer tool=prp-review-agents head=feb8536d -->\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

@test "a real prose note citing run ids is ignored, not refused" {
  { boundary_footers; printf 'Review stop rule met: round 1 (run 20261017T114850Z-9b35eebc) and round 2 (run 20261017T115125Z-0018cf7b) both had 0 Critical\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

@test "a real prose note citing the skill name is ignored, not refused" {
  { boundary_footers; printf 'The review loop restarts with a real `/prp-core:prp-review-agents 190 --l2-comments` Skill call at the next head.\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

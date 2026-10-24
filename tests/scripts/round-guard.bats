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

@test "a footer with an unreadable run id refuses" {
  printf 'Generated-by: prp-review-agents v2 run=BAD pass=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"unreadable run id"* ]]
}

@test "a footer without a pass still counts its run" {
  printf 'Generated-by: prp-review-agents v2.12.0 run=20261021T000001Z-00000001\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 1 of 10"* ]]
}

@test "ordinary last lines, null and blanks are ignored" {
  printf 'LGTM\nnull\n\n   \n' > in.txt
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

@test "a 10th footer with a leading space still counts (hits the cap)" {
  { boundary_footers; printf ' Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th footer with a leading tab still counts (hits the cap)" {
  { boundary_footers; printf '\tGenerated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th footer with a trailing CR still counts (hits the cap)" {
  { boundary_footers; printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\r\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th footer in lower case still counts (hits the cap)" {
  { boundary_footers; printf 'generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th footer quoted mid-line still counts (hits the cap)" {
  { boundary_footers; printf 'see "Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer"\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th line that is genuinely unrelated is ignored" {
  { boundary_footers; printf 'LGTM\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

# R2 (brief 20261024-2110-b211) added near-footer-shape rows to refuse these shapes. Superseded by
# R3's re-plan v3 (brief 20261024-2205-c211, plan 211-round-guard-id-count.plan.md): the guard no
# longer classifies footer shapes at all -- it counts every run id anywhere in the input -- so these
# same near-miss shapes, and the real-data rows below, now all COUNT their ids instead of refusing.
# R4's re-plan v4 (brief 20261024-2320-d211, plan 211-round-guard-v4.plan.md) keeps this behaviour:
# these rows carry readable 8-hex ids, so none of them trip v4's new unreadable-run-id refusal.

@test "a 10th footer with reversed word order still counts (hits the cap)" {
  { boundary_footers; printf 'prp-review-agents Generated-by: v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th footer missing the colon still counts (hits the cap)" {
  { boundary_footers; printf 'Generated-by prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th footer with a space instead of a hyphen still counts (hits the cap)" {
  { boundary_footers; printf 'Generated by: prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th footer split over two lines (tail only) still counts (hits the cap)" {
  { boundary_footers; printf 'prp-review-agents v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a 10th line with only the footer's body still counts (hits the cap)" {
  { boundary_footers; printf 'v1 run=20261024T000000Z-0000000a pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a real 9-hex run id counts (hits the cap)" {
  { boundary_footers; printf 'Generated-by: prp-review-agents v2.12.0 run=20261022T044148Z-312938296 pass=code-reviewer\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a real L2 marker is ignored, not refused" {
  { boundary_footers; printf '<!-- safe-merge-review: verdict=READY_TO_MERGE critical=0 important=0 agents=code-reviewer tool=prp-review-agents head=feb8536d -->\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

@test "a prose note citing new run ids counts them" {
  { boundary_footers; printf 'Review stop rule met: round 1 (run 20261017T114850Z-9b35eebc) and round 2 (run 20261017T115125Z-0018cf7b) both had 0 Critical\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 3 ]
  [[ "$output" == *"ROUND-CAP"* ]]
}

@test "a real prose note citing the skill name is ignored, not refused" {
  { boundary_footers; printf 'The review loop restarts with a real `/prp-core:prp-review-agents 190 --l2-comments` Skill call at the next head.\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

# R3 re-plan v3 (brief 20261024-2205-c211, plan 211-round-guard-id-count.plan.md): the guard counts
# every distinct run-id token anywhere in the input, instead of classifying footer shapes.
# R4 re-plan v4 (brief 20261024-2320-d211, plan 211-round-guard-v4.plan.md): the id is now bounded
# to 8 hex, and a run= marker or generated-by line with no readable id refuses instead of vanishing
# (tests 7 and 35 above flip accordingly; the new rows below cover the two refusal rules and the
# glued-id boundary).
# R5 re-plan v5 (brief 20261024-2340-e211, plan 211-round-guard-v5.plan.md): the generated-by
# refusal now fires only when the line also names prp-review-agents, and the gap between
# "generated" and "by" may be any 0-20 non-alphanumeric characters (was 0-1 any character).

@test "R3 near-miss shapes each still count" {
  local shapes=(
    'Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass:code-reviewer'
    'Generated-by: prp-review-agents v1 run = 20261024T000000Z-0000000a pass=code-reviewer'
    'Generated-by:    prp-review-agents    v1 run=20261024T000000Z-0000000a pass=code-reviewer'
    'Generated-by: prp-review-agent v1 run=20261024T000000Z-0000000a pass=code-reviewer'
    'pass=code-reviewer run=20261024T000000Z-0000000a'
  )
  for shape in "${shapes[@]}"; do
    { boundary_footers; printf '%s\n' "$shape"; } > in.txt
    run bash "$G" < in.txt
    [ "$status" -eq 3 ]
  done
}

@test "an id repeated in another case counts once" {
  { boundary_footers; printf 'run=20261024t000000z-00000009\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

@test "a prose note citing this PR's own run ids adds nothing" {
  { boundary_footers; printf 'Review stop rule met: round 1 (run 20261024T000000Z-00000001) and round 2 (run 20261024T000000Z-00000002)\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 9 of 10"* ]]
}

@test "a 64KB line is processed in under 2 seconds" {
  python3 -I -c "print('run=20261024T000000Z-0000000a pass=' + 'x' * 65536)" > in.txt
  SECONDS=0
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [ "$SECONDS" -lt 2 ]
}

@test "a run id with altered digits after run= refuses" {
  { boundary_footers; printf 'see run=2026-10-24T00:00:00Z-0000000a for details\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"unreadable run id"* ]]
}

@test "a grep failure exits 2" {
  local real_grep
  real_grep="$(command -v grep)"
  mkdir -p fakebin
  cat > fakebin/grep <<EOF
#!/bin/sh
case "\$1" in
  -aoE) exit 2 ;;
esac
exec "$real_grep" "\$@"
EOF
  chmod +x fakebin/grep
  printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z-00000001 pass=code-reviewer\n' > in.txt
  PATH="$PWD/fakebin:$PATH" run bash "$G" < in.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"grep failed"* ]]
}

@test "two glued ids count as two" {
  printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a20261024T000000Z-0000000b pass=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 2 of 10"* ]]
}

@test "a foreign footer with an unreadable run= refuses (fail closed)" {
  printf 'Generated-by: someone-else v1 run=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a run= marker without generated-by refuses on a bad id" {
  printf 'prp-review-agents v1 run=2026-10-24T000000Z-0000000a pass=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a run = marker with spaces refuses on a bad id" {
  printf 'prp-review-agents v1 run = 2026-10-24T000000Z-0000000a pass=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a run = marker with spaces and a good id counts" {
  printf 'prp-review-agents v1 run = 20261024T000000Z-0000000a pass=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 1 of 10"* ]]
}

@test "a second bad run= on a line with a good id refuses" {
  printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a run=BAD\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a generated-by line with no id refuses" {
  printf 'Generated by prp-review-agents v1\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a truncated id refuses" {
  printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z- pass=code-reviewer\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "an id split across two lines refuses (stated boundary)" {
  { printf 'Generated-by: prp-review-agents v1 run=20261024T00\n'; printf '0000Z-0000000a pass=x\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "run inside a word or prose is not a marker" {
  { printf 'Deploy UAT did not run: it triggers only on workflow_run from main\n'; printf 'rerun=yes; workflow_run=3\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 0 of 10"* ]]
}

@test "an L2 marker is not a footer" {
  printf '<!-- safe-merge-review: verdict=READY_TO_MERGE critical=0 important=0 agents=a tool=prp-review-agents head=abc -->\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 0 of 10"* ]]
}

@test "a 9-hex id counts as its 8-hex prefix (stated boundary)" {
  { printf 'Generated-by: prp-review-agents v1 run=20261022T044148Z-312938296 pass=x\n'; printf 'Generated-by: prp-review-agents v1 run=20261022T044148Z-312938297 pass=x\n'; } > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 1 of 10"* ]]
}

@test "a 64KB line ending in a bare run= refuses in under 2 seconds" {
  python3 -I -c "print('run=20261024T000000Z-0000000a pass=' + 'x' * 65536 + ' run=')" > in.txt
  SECONDS=0
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
  [ "$SECONDS" -lt 2 ]
}

@test "a 2-space gap in generated by still refuses (R5)" {
  printf 'Generated  by prp-review-agents, run corrupted, no id available\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "a tab gap in generated by still refuses" {
  printf 'Generated\t\tby prp-review-agents v1\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 2 ]
}

@test "generated by another tool is not a footer (R5)" {
  local line
  for line in 'Report generated by Jenkins.' 'This diagram was generated by graphviz.' 'Documentation generated by Sphinx 7.2.'; do
    printf '%s\n' "$line" > in.txt
    run bash "$G" < in.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 of 10"* ]]

    { boundary_footers; printf '%s\n' "$line"; } > in.txt
    run bash "$G" < in.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"9 of 10"* ]]
  done
}

@test "three glued ids count as three" {
  printf 'Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a20261024T000000Z-0000000b20261024T000000Z-0000000c pass=x\n' > in.txt
  run bash "$G" < in.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"rounds so far: 3 of 10"* ]]
}

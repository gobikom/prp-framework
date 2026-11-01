#!/usr/bin/env bats
# Helper-level tests for scripts/review/run-id.sh (agent-devops#1336 item 1, SO#1501 bundle).
# One test per arm and boundary of the plan's B1-B24 table
# (~/.task-state/psak/plans/1336-run-id-script.plan.md). The fixed clock is the
# epoch of 2026-10-31T05:44:31Z, the real prp-framework#236 post time; the B10/B11
# clocks are the real post times of the #1487 / SO#1508 samples from the plan.
#
# Run: bats tests/scripts/run-id.bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
S="$REPO_ROOT/scripts/review/run-id.sh"

NOW=1793425471          # 2026-10-31T05:44:31Z
NOW_B10=1793325388      # 2026-10-30T01:56:28Z (real #1487 post time)
NOW_B11=1793470158      # 2026-10-31T18:09:18Z (real SO#1508 post time)
NOW_B21=1835438400      # 2028-02-29T12:00:00Z (leap day)
NOW_B22=1791450549      # 2026-10-08T09:09:09Z (octal-trap date)
SHA_236="ec87e0d0bbdc1111111111111111111111111111"
SHA_CLEAN="1111111111111111111111111111111111111111"

setup() {
  TEST_TMPDIR="$(mktemp -d)"; cd "$TEST_TMPDIR"
  printf '%s\n' "$SHA_CLEAN" > shas.ok
  : > prior.empty
}
teardown() { cd /; rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

ck() { # ck <id> <shas-file> <prior-file> [epoch] — check at a fixed clock (default $NOW)
  run bash "$S" check --id "$1" --shas-file "$2" --prior-file "$3" --now "${4:-$NOW}"
}

@test "B1: new prints the canonical shape and two calls differ" {
  a="$(bash "$S" new)"; b="$(bash "$S" new)"
  [[ "$a" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]]
  [[ "$b" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]]
  [ "$a" != "$b" ]
}

@test "B2: new with an argument is a bad argument" {
  run bash "$S" new x
  [ "$status" -eq 2 ]
}

@test "B3: an id 120 s ahead is still postable (the boundary itself)" {
  ck 20261031T054631Z-aabbccdd shas.ok prior.empty
  [ "$status" -eq 0 ]
  [[ "$output" == "RUN-ID: ok 20261031T054631Z-aabbccdd" ]]
}

@test "B4: an id 121 s ahead is refused as future" {
  ck 20261031T054632Z-aabbccdd shas.ok prior.empty
  [ "$status" -eq 3 ]
  [[ "$output" == *"future"* ]]
}

@test "B5: an id 3600 s old is still postable (the boundary itself)" {
  ck 20261031T044431Z-aabbccdd shas.ok prior.empty
  [ "$status" -eq 0 ]
}

@test "B6: an id 3601 s old is refused as old" {
  ck 20261031T044430Z-aabbccdd shas.ok prior.empty
  [ "$status" -eq 3 ]
  [[ "$output" == *"old"* ]]
}

@test "B7: the real #236 id is refused on the SHA-prefix arm (its time arm passes at +29 s)" {
  printf '%s\n' "$SHA_236" > shas.236
  ck 20261031T054500Z-ec87e0d0 shas.236 prior.empty
  [ "$status" -eq 3 ]
  [[ "$output" == *"commit"* ]]
}

@test "B8: a 6-hex overlap only is not a match (7 hex are compared)" {
  printf 'ec87e0faaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > shas.6hex
  ck 20261031T054631Z-ec87e0d0 shas.6hex prior.empty
  [ "$status" -eq 0 ]
}

@test "B9: an uppercase SHA in the file still matches" {
  printf 'EC87E0D0BBDC1111111111111111111111111111\n' > shas.upper
  ck 20261031T054631Z-ec87e0d0 shas.upper prior.empty
  [ "$status" -eq 3 ]
  [[ "$output" == *"commit"* ]]
}

@test "B10: the real #1487 id (18 min 32 s in the future) is refused as future" {
  ck 20261030T021500Z-c1d47a92 shas.ok prior.empty "$NOW_B10"
  [ "$status" -eq 3 ]
  [[ "$output" == *"future"* ]]
}

@test "B11: the real SO#1508 id posts clean (-43 s, empty prior)" {
  ck 20261031T180835Z-3aaf7f0a shas.ok prior.empty "$NOW_B11"
  [ "$status" -eq 0 ]
}

@test "B12: an id already in a trusted comment is refused" {
  printf 'Generated-by: prp-review-agents v9.9.9 run=20261031T054631Z-aabbccdd pass=code-reviewer\n' > prior.used
  ck 20261031T054631Z-aabbccdd shas.ok prior.used
  [ "$status" -eq 3 ]
  [[ "$output" == *"already used"* ]]
}

@test "B13: reuse in other case still refused (case-insensitive grep)" {
  printf 'run=20261031T054631Z-AABBCCDD\n' > prior.upper
  ck 20261031T054631Z-aabbccdd shas.ok prior.upper
  [ "$status" -eq 3 ]
  [[ "$output" == *"already used"* ]]
}

@test "B14: an empty prior file is a clean PR (no earlier trusted comments)" {
  ck 20261031T054631Z-aabbccdd shas.ok prior.empty
  [ "$status" -eq 0 ]
}

@test "B15: a missing prior file is a bad argument" {
  ck 20261031T054631Z-aabbccdd shas.ok prior.missing
  [ "$status" -eq 2 ]
}

@test "B16: a missing shas file is a bad argument" {
  ck 20261031T054631Z-aabbccdd shas.missing prior.empty
  [ "$status" -eq 2 ]
}

@test "B17: an empty shas file never passes as no-match" {
  : > shas.empty
  ck 20261031T054631Z-aabbccdd shas.empty prior.empty
  [ "$status" -eq 2 ]
}

@test "B18: a garbage shas line fails closed" {
  printf 'error: rate limit\n' > shas.garbage
  ck 20261031T054631Z-aabbccdd shas.garbage prior.empty
  [ "$status" -eq 2 ]
}

@test "B19: malformed ids are bad arguments" {
  for id in '20261031T0544Z-aabbccdd' '20261031T054431Z-AABBCCDD' '20261031T054431Z-aabbccdd '; do
    ck "$id" shas.ok prior.empty
    [ "$status" -eq 2 ]
  done
}

@test "B20: impossible dates are bad arguments" {
  for id in 20261301T000000Z-aabbccdd 20260230T000000Z-aabbccdd 20261031T240000Z-aabbccdd; do
    ck "$id" shas.ok prior.empty
    [ "$status" -eq 2 ]
  done
}

@test "B21: a leap-day id parses and posts (2028-02-29)" {
  ck 20280229T120000Z-aabbccdd shas.ok prior.empty "$NOW_B21"
  [ "$status" -eq 0 ]
}

@test "B22: 08/09 fields are decimal, not octal (10# on every field)" {
  ck 20261008T090909Z-aabbccdd shas.ok prior.empty "$NOW_B22"
  [ "$status" -eq 0 ]
}

@test "B23: a bad --now and a repeated --id are bad arguments" {
  run bash "$S" check --id 20261031T054631Z-aabbccdd --shas-file shas.ok --prior-file prior.empty --now abc
  [ "$status" -eq 2 ]
  run bash "$S" check --id 20261031T054631Z-aabbccdd --id 20261031T054631Z-aabbccdd --shas-file shas.ok --prior-file prior.empty --now "$NOW"
  [ "$status" -eq 2 ]
}

@test "B24: an unknown flag is a bad argument" {
  run bash "$S" check --id 20261031T054631Z-aabbccdd --shas-file shas.ok --prior-file prior.empty --foo
  [ "$status" -eq 2 ]
}

@test "B25: an unreadable prior file is a lookup failure, never a vacuous pass" {
  [ "$(id -u)" -eq 0 ] && skip "chmod 000 does not block root"
  printf 'run=20261031T054631Z-aabbccdd\n' > prior.noread
  chmod 000 prior.noread
  ck 20261031T054631Z-aabbccdd shas.ok prior.noread
  [ "$status" -eq 2 ]
  [[ "$output" == *"prior file is not readable"* ]]
}

@test "B26: an unterminated last shas line fails closed, even a matching SHA" {
  printf '%s' "$SHA_236" > shas.unterm          # full 40-hex, prefixes the id, but no trailing \n
  ck 20261031T054600Z-ec87e0d0 shas.unterm prior.empty
  [ "$status" -eq 2 ]
  [[ "$output" == *"unterminated"* ]]
  printf '%s' 'error: rate limit' > shas.unterm2 # garbage and unterminated — same arm
  ck 20261031T054631Z-aabbccdd shas.unterm2 prior.empty
  [ "$status" -eq 2 ]
}

@test "B27: new dies when the clock cannot be read (no silent malformed id)" {
  mkdir -p bin.nodate
  printf '#!/bin/sh\nexit 1\n' > bin.nodate/date
  chmod +x bin.nodate/date
  run env PATH="$TEST_TMPDIR/bin.nodate:/usr/bin:/bin" bash "$S" new
  [ "$status" -eq 2 ]
  [[ "$output" == *"clock"* ]]
}

@test "B32: an unreadable shas file is a lookup failure (exit 2), never the shell's redirect error (exit 1)" {
  [ "$(id -u)" -eq 0 ] && skip "chmod 000 does not block root"
  printf '%s\n' "$SHA_CLEAN" > shas.noread
  chmod 000 shas.noread
  ck 20261031T054631Z-aabbccdd shas.noread prior.empty
  [ "$status" -eq 2 ]
  [[ "$output" == *"shas file is not readable"* ]]
}

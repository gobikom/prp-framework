#!/usr/bin/env bats
# Helper-level tests for scripts/review/pass-budget.sh (prp-framework#151 AC2).
# B1 is the forced-short-budget demonstration.
#
# Run: bats tests/scripts/pass-budget.bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
P="$REPO_ROOT/scripts/review/pass-budget.sh"

setup() { TEST_TMPDIR="$(mktemp -d)"; cd "$TEST_TMPDIR"; }
teardown() { cd /; rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

@test "forced two second budget cuts a long probe" {
  E=$(PRP_PASS_BUDGET_SECS=2 bash "$P" deadline)
  start=$SECONDS
  run bash "$P" run "$E" -- sleep 30
  [ "$status" -eq 124 ]
  [[ "$output" == *"PASS-TIMEBOXED: probe cut at the deadline: sleep"* ]]
  [ $((SECONDS - start)) -lt 8 ]
}

@test "a probe after the deadline is not started" {
  run bash "$P" run 1000000000 -- touch STARTED
  [ "$status" -eq 124 ]
  [[ "$output" == *"probe not started: touch"* ]]
  [ ! -e STARTED ]
}

@test "exit codes of bounded probes pass through" {
  E=$(bash "$P" deadline)
  run bash "$P" run "$E" -- true
  [ "$status" -eq 0 ]
  run bash "$P" run "$E" -- false
  [ "$status" -eq 1 ]
  run bash "$P" run "$E" -- bash -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "a child that ignores TERM is still killed" {
  E=$(PRP_PASS_BUDGET_SECS=2 bash "$P" deadline)
  start=$SECONDS
  run bash "$P" run "$E" -- bash -c "trap '' TERM; sleep 30"
  [ "$status" -eq 124 ]
  [ $((SECONDS - start)) -lt 14 ]
}

@test "deadline defaults to twenty minutes" {
  now=$(date +%s)
  E=$(env -u PRP_PASS_BUDGET_SECS bash "$P" deadline)
  [ $((E - now)) -ge 1199 ] && [ $((E - now)) -le 1202 ]
}

@test "bad budgets are refused" {
  for bad in 0 abc 99999 -5 "" "1 2" 14401 '$(touch PWNED)'; do
    run env PRP_PASS_BUDGET_SECS="$bad" bash "$P" deadline
    [ "$status" -eq 2 ]
  done
  [ ! -e PWNED ]
  PRP_PASS_BUDGET_SECS=14400 bash "$P" deadline >/dev/null
}

@test "remaining is positive before and exit 1 after the deadline" {
  E=$(PRP_PASS_BUDGET_SECS=100 bash "$P" deadline)
  run bash "$P" remaining "$E"
  [ "$status" -eq 0 ]
  [ "$output" -gt 90 ]
  run bash "$P" remaining 1000000000
  [ "$status" -eq 1 ]
  [ "$output" = 0 ]
}

@test "non numeric epochs are refused and nothing runs" {
  for bad in abc 123 12345678901 '$(touch PWNED)' "" '1000000000;touch PWNED'; do
    run bash "$P" run "$bad" -- touch PWNED
    [ "$status" -eq 2 ]
    run bash "$P" remaining "$bad"
    [ "$status" -eq 2 ]
  done
  [ ! -e PWNED ]
}

@test "run without a command or separator is refused" {
  E=$(bash "$P" deadline)
  run bash "$P" run "$E" touch PWNED
  [ "$status" -eq 2 ]
  run bash "$P" run "$E" --
  [ "$status" -eq 2 ]
  [ ! -e PWNED ]
}

@test "without a timeout command the probe is refused not run unbounded" {
  mkdir bin
  for t in bash date grep; do ln -s "$(command -v $t)" "bin/$t"; done
  E=$(bash "$P" deadline)
  run env PATH="$PWD/bin" "$PWD/bin/bash" "$P" run "$E" -- touch STARTED
  [ "$status" -eq 2 ]
  [[ "$output" == *"no timeout command"* ]]
  [ ! -e STARTED ]
}

@test "unknown or missing subcommands are refused" {
  run bash "$P"
  [ "$status" -eq 2 ]
  run bash "$P" frobnicate
  [ "$status" -eq 2 ]
}

# check-body
body() { printf 'Reviewed head: x\n\n### Could not verify\n%b\n\nGenerated-by: y\n' "$1" > b.md; }

@test "check-body passes a body that does not claim a timebox" {
  body 'Nothing.'
  run bash "$P" check-body b.md
  [ "$status" -eq 0 ]
}

@test "check-body passes a timeboxed body with a follow-up issue link" {
  body 'Pass timeboxed: 2 probes not completed: bats, build\nFollow-up: https://github.com/gobikom/prp-framework/issues/200'
  run bash "$P" check-body b.md
  [ "$status" -eq 0 ]
}

@test "check-body refuses a timeboxed body without a link" {
  body 'Pass timeboxed: 1 probe not completed: bats'
  run bash "$P" check-body b.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"Follow-up"* ]]
}

@test "check-body refuses malformed follow-up links" {
  for link in 'Follow-up: http://github.com/o/r/issues/1' 'Follow-up: https://github.com/o/r/pull/1' 'Follow-up: https://github.com/o/r/issues/1 extra' 'Follow-up: https://example.com/o/r/issues/1' 'Follow-up: https://github.com/o/r/issues/'; do
    body "Pass timeboxed: 1 probe\n$link"
    run bash "$P" check-body b.md
    [ "$status" -eq 1 ]
  done
}

# Invariant: a body that mentions a timebox in any form needs a Follow-up link (no line-shape matching).
@test "check-body refuses every timebox mention without a link" {
  for m in '## Pass timeboxed' '### **Pass timeboxed**' '1. Pass timeboxed' '**Pass** timeboxed' 'Pass: timeboxed' \
           'Pass\xc2\xa0timeboxed' 'time\xc2\xa0boxed' 'Pass time\xe2\x80\x8bboxed' 'Pass time\xef\xbb\xbfboxed' \
           'time-boxed' 'time boxed' 'the review was TIMEBOXED here' 'PASS-TIMEBOXED: 1 probe' 'Pass timeboxed\r' \
           '`Pass timeboxed`' '- [ ] Pass timeboxed' 'time\xe2\x80\x91boxed' 'time\xe1\x9a\x80boxed' '\xef\xbd\x94\xef\xbd\x89\xef\xbd\x8d\xef\xbd\x85\xef\xbd\x82\xef\xbd\x8f\xef\xbd\x98\xef\xbd\x85\xef\xbd\x84'; do
    body "$m"
    run bash "$P" check-body b.md
    [ "$status" -eq 1 ] || { echo "passed without a link: $m"; false; }
    body "$m\nFollow-up: https://github.com/o/r/issues/5"
    run bash "$P" check-body b.md
    [ "$status" -eq 0 ] || { echo "refused with a link: $m"; false; }
  done
}

@test "check-body accepts a link line that ends in CRLF" {
  body 'Pass timeboxed\nFollow-up: https://github.com/o/r/issues/5\r'
  run bash "$P" check-body b.md
  [ "$status" -eq 0 ]
}

@test "check-body passes a body with no timebox mention" {
  body 'Nothing.\nThe probe was time-limited by the sandbox.'
  run bash "$P" check-body b.md
  [ "$status" -eq 0 ]
}

@test "check-body fails closed when it cannot normalise" {
  mkdir bin
  for t in bash grep tr; do ln -s "$(command -v $t)" "bin/$t"; done
  body 'Nothing.'
  run env PATH="$PWD/bin" "$PWD/bin/bash" "$P" check-body b.md
  [ "$status" -eq 2 ]
}

@test "check-body refuses a missing file or a symlink" {
  run bash "$P" check-body nope.md
  [ "$status" -eq 2 ]
  body 'Nothing.'
  ln -s b.md l.md
  run bash "$P" check-body l.md
  [ "$status" -eq 2 ]
}

# Size cap and malformed-UTF-8 fail closed (prp#151 incident: a 20 MB malformed-UTF-8 body
# hung perl's NFKC/regex pass for ~58 min). Keep these inputs small — never megabytes.

@test "check-body refuses a body over the cap, fast" {
  head -c 65537 /dev/zero | tr '\0' 'a' > big.md
  run timeout 10 bash "$P" check-body big.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"over the 65536-byte cap"* ]]
}

@test "check-body processes a body at the cap" {
  head -c 65536 /dev/zero | tr '\0' 'a' > atcap.md
  run timeout 10 bash "$P" check-body atcap.md
  [ "$status" -eq 0 ]
}

@test "check-body fails closed on malformed UTF-8, fast" {
  printf 'Reviewed head: x\n\xff\xfe\x80not valid utf8\n' > bad.md
  run timeout 10 bash "$P" check-body bad.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"not valid UTF-8"* ]]
}

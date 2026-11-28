#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/review/mark-ready.sh"
  export WORK="$BATS_TEST_TMPDIR" PATH="$BATS_TEST_TMPDIR:$PATH"
  SHA=0123456789abcdef0123456789abcdef01234567
  MOVED=1123456789abcdef0123456789abcdef01234567
  export FAKE_VIEW=$'OPEN\ttrue\t'"$SHA" FAKE_VIEW2=$'OPEN\tfalse\t'"$SHA"
  : > "$WORK/gh.log"
  cat > "$WORK/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORK/gh.log"
case "$1 $2" in
  'pr view')
    if [[ -f "$WORK/view.n" ]]; then
      [[ ${GH_FAIL2:-0} != 1 ]] || { echo 'post-check failed' >&2; exit 1; }
      printf '%s\n' "$FAKE_VIEW2"
    else
      echo 1 > "$WORK/view.n"
      [[ ${GH_FAIL:-0} != 1 ]] || { echo 'lookup failed' >&2; exit 1; }
      printf '%s\n' "$FAKE_VIEW"
    fi ;;
  'pr ready')
    if [[ ${4:-} == --undo ]]; then
      [[ ${UNDO_RC:-0} == 0 ]] || echo 'undo denied' >&2
      exit "${UNDO_RC:-0}"
    fi
    [[ ${READY_RC:-0} == 0 ]] || printf 'ready denied\nextra error detail\n' >&2
    exit "${READY_RC:-0}" ;;
  *) exit 99 ;;
esac
EOF
  chmod +x "$WORK/gh"
}

check() { run --separate-stderr bash "$SCRIPT" 7 --clean "${1:-yes}" --reviewed-head "$SHA"; }
no_ready() { ! grep -q '^pr ready' "$WORK/gh.log"; }
lookup_failed() {
  [ "$status" -eq 0 ]
  [ "$output" = 'MARK-READY: skipped lookup-failed' ]
  no_ready
}

@test 'B1: same reviewed head before and after ready' {
  check
  [ "$status" -eq 0 ]
  [ "$output" = "MARK-READY: done $SHA" ]
  [ "$(grep -c '^pr view 7 ' "$WORK/gh.log")" -eq 2 ]
  [ "$(grep -cx 'pr ready 7' "$WORK/gh.log")" -eq 1 ]
  ! grep -q -- '--undo' "$WORK/gh.log"
}

@test 'B2: moved before ready' {
  export FAKE_VIEW=$'OPEN\ttrue\t'"$MOVED"
  check
  [ "$status" -eq 0 ]
  [ "$output" = "MARK-READY: skipped head-moved reviewed=$SHA current=$MOVED" ]
  no_ready
}

@test 'B3: not clean makes no gh calls' {
  check no
  [ "$status" -eq 0 ]
  [ "$output" = 'MARK-READY: skipped not-clean' ]
  [ ! -s "$WORK/gh.log" ]
}

@test 'B4: already ready' {
  export FAKE_VIEW="$FAKE_VIEW2"
  check
  [ "$status" -eq 0 ]
  [ "$output" = 'MARK-READY: skipped already-ready' ]
  no_ready
}

@test 'B5a: failed lookup keeps gh stderr' {
  export GH_FAIL=1
  check
  lookup_failed
  [ "$stderr" = 'lookup failed' ]
}

@test 'B5b: empty lookup' {
  export FAKE_VIEW=''
  check
  lookup_failed
}

@test 'B5c: malformed lookup, including empty or extra fields' {
  for FAKE_VIEW in $'OPEN\ttrue\tzzz' $'OPEN\t\ttrue\t'"$SHA" $'OPEN\ttrue\t'"$SHA"$'\textra'; do
    rm -f "$WORK/view.n"
    export FAKE_VIEW
    check
    lookup_failed
  done
}

@test 'B6: ready failure is reported without losing the round' {
  export READY_RC=1
  check
  [ "$status" -eq 0 ]
  [ "$output" = 'MARK-READY: failed ready denied' ]
  [ "$stderr" = "WARNING: run 'gh pr ready 7' by hand" ]
  [ "$(grep -cx 'pr ready 7' "$WORK/gh.log")" -eq 1 ]
  [ "$(grep -c '^pr view 7 ' "$WORK/gh.log")" -eq 1 ]
  ! grep -q -- '--undo' "$WORK/gh.log"
}

@test 'B7: closed or merged PRs are unchanged' {
  for state in CLOSED MERGED; do
    rm -f "$WORK/view.n"
    export FAKE_VIEW="$state"$'\ttrue\t'"$SHA"
    check
    [ "$status" -eq 0 ]
    [ "$output" = "MARK-READY: skipped state=$state" ]
    no_ready
  done
}

@test 'B11: head moves between the first lookup and ready' {
  export FAKE_VIEW2=$'OPEN\tfalse\t'"$MOVED"
  check
  [ "$status" -eq 0 ]
  [ "$output" = "MARK-READY: reverted head-moved reviewed=$SHA current=$MOVED" ]
  [ "$(grep -cx 'pr ready 7 --undo' "$WORK/gh.log")" -eq 1 ]
}

@test 'B11b: failed post-check reverts to draft' {
  export GH_FAIL2=1
  check
  [ "$status" -eq 0 ]
  [ "$output" = 'MARK-READY: reverted lookup-failed' ]
  [ "$stderr" = 'post-check failed' ]
  [ "$(grep -cx 'pr ready 7 --undo' "$WORK/gh.log")" -eq 1 ]
}

@test 'B12: undo failure is never silent' {
  export FAKE_VIEW2=$'OPEN\tfalse\t'"$MOVED" UNDO_RC=1
  check
  [ "$status" -eq 0 ]
  [ "$output" = "MARK-READY: failed-revert head-moved reviewed=$SHA current=$MOVED" ]
  [ "$stderr" = $'undo denied\n'"WARNING: PR 7 may be ready at an unreviewed head; run 'gh pr ready 7 --undo'" ]
  [ "$(grep -cx 'pr ready 7 --undo' "$WORK/gh.log")" -eq 1 ]
}

@test 'ARGS: bad number, head, clean value, or arity makes no gh calls' {
  run --separate-stderr bash "$SCRIPT" 0 --clean yes --reviewed-head "$SHA"
  [ "$status" -eq 2 ] && [[ "$stderr" == error:* ]]
  run --separate-stderr bash "$SCRIPT" 7 --clean yes --reviewed-head garbage
  [ "$status" -eq 2 ] && [[ "$stderr" == error:* ]]
  check maybe
  [ "$status" -eq 2 ] && [[ "$stderr" == error:* ]]
  run --separate-stderr bash "$SCRIPT" 7 --clean yes
  [ "$status" -eq 2 ] && [[ "$stderr" == error:* ]]
  [ ! -s "$WORK/gh.log" ]
}

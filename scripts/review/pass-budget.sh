#!/usr/bin/env bash
# Pass timebox for prp-review-agents (prp-framework#151 AC2).
#
# Invariant: a probe started through `run` never outlives its deadline (it is killed at the
# deadline, and not started at all after it), and a pass body that says `Pass timeboxed` is
# only postable with a `Follow-up:` issue link (`check-body`). The deadline is an absolute epoch
# minted once per round by `deadline`; there is no state file, and agents cannot widen it.
# Unknown inputs refuse (exit 2): nothing here ever runs a command it could not bound.
#
# usage: pass-budget.sh deadline                 print epoch = now + ${PRP_PASS_BUDGET_SECS:-1200}
#        pass-budget.sh remaining <epoch>        print seconds left; exit 1 when expired
#        pass-budget.sh run <epoch> -- cmd...    bounded run; exit 124 = cut/not started (PASS-TIMEBOXED)
#        pass-budget.sh check-body <file>        exit 1 if the body claims `Pass timeboxed` without
#                                                a `Follow-up: https://github.com/<o>/<r>/issues/<n>` line
# exit 2 = usage error / bad value / no `timeout` command.
# Note: exit 124 from `run` also covers a command that itself exits 124.
set -euo pipefail

DEFAULT_SECS=1200
MAX_SECS=14400

die() { echo "error: $*" >&2; exit 2; }

num() { # num <value> <pattern> <what>
  printf '%s' "$1" | grep -qxE "$2" || die "$3 must match $2"
}

epoch_arg() { num "${1:-}" '[0-9]{10}' "epoch"; }

timeout_cmd() {
  if command -v timeout >/dev/null 2>&1; then echo timeout
  elif command -v gtimeout >/dev/null 2>&1; then echo gtimeout
  else die "no timeout command (timeout/gtimeout) — refusing to run an unbounded probe"; fi
}

[[ $# -ge 1 ]] || die "usage: pass-budget.sh deadline|remaining|run|check-body"
SUB="$1"; shift

case "$SUB" in
  deadline)
    secs="${PRP_PASS_BUDGET_SECS-$DEFAULT_SECS}"
    num "$secs" '[0-9]{1,5}' "PRP_PASS_BUDGET_SECS"
    secs=$((10#$secs))
    (( secs >= 1 && secs <= MAX_SECS )) || die "PRP_PASS_BUDGET_SECS must be 1..$MAX_SECS"
    echo $(( $(date +%s) + secs ))
    ;;
  remaining)
    epoch_arg "${1:-}"
    left=$(( 10#$1 - $(date +%s) ))
    if (( left <= 0 )); then echo 0; exit 1; fi
    echo "$left"
    ;;
  run)
    epoch_arg "${1:-}"
    epoch=$((10#$1)); shift
    [[ "${1:-}" == "--" ]] || die "run needs: <epoch> -- cmd..."
    shift
    [[ $# -ge 1 ]] || die "run needs a command after --"
    T=$(timeout_cmd)
    left=$(( epoch - $(date +%s) ))
    if (( left <= 0 )); then
      echo "PASS-TIMEBOXED: deadline passed, probe not started: $1" >&2
      exit 124
    fi
    rc=0
    "$T" --kill-after=5 "$left" "$@" || rc=$?
    if (( rc == 124 || rc == 137 )); then
      echo "PASS-TIMEBOXED: probe cut at the deadline: $1" >&2
      exit 124
    fi
    exit "$rc"
    ;;
  check-body)
    f="${1:-}"
    [[ -n "$f" && -r "$f" && ! -L "$f" ]] || die "check-body needs a readable regular file"
    if grep -q '^Pass timeboxed' "$f"; then
      grep -qxE 'Follow-up: https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+' "$f" \
        || { echo "pass says 'Pass timeboxed' but has no 'Follow-up: https://github.com/<owner>/<repo>/issues/<n>' line" >&2; exit 1; }
    fi
    ;;
  *) die "unknown subcommand '$SUB'" ;;
esac

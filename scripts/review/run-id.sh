#!/usr/bin/env bash
# RUN_ID build + check for prp-review-agents (agent-devops#1336 item 1, SO#1501 bundle).
#
# Invariant: Step C posts a per-pass comment only when its RUN_ID (a) has a time no more than 120 s
# ahead of now and no more than 3600 s behind now, (b) has a hex part whose first 7 digits match the
# first 7 hex of no commit SHA on the PR (head included), and (c) appears in no earlier comment by
# the trusted login on that PR. Any failure, including any lookup failure, posts nothing and exits
# non-zero (the caller wraps every lookup in `|| FATAL`).
# Boundaries, stated:
# - `new` draws 8 hex from /dev/urandom and prints `date -u` + "-" + hex; it takes no arguments.
#   A clock that cannot be read is an error (exit 2), never a malformed id printed with exit 0.
# - `check` validates the id shape itself (lowercase only — the shape `new` writes) and parses the
#   date in pure bash arithmetic (days-from-civil; no `date -d`, GNU/BSD differ): an impossible
#   date (month 13, Feb 30, hour 24) is a bad argument (exit 2), never a refusal.
# - The shas file must exist, be non-empty, and hold only 40-hex lines: a garbage lookup fails
#   closed as exit 2, never passes as "no match"; a final line without a newline is never read by
#   the loop, so it is a bad lookup input too (exit 2), never silently skipped. The prior file
#   must exist and be readable but may be empty (a PR with no earlier trusted comments); the
#   reuse search distinguishes no-match (rc 1, pass) from every other grep rc (exit 2); it is
#   only ever searched with `grep -F`, never evaluated (comment bodies are untrusted data).
# - `--now EPOCH` exists for tests only (a fixed clock); without it, now is `date -u +%s`.
# exit 0 = ok (or id printed); 2 = usage error / bad value / unreadable lookup input, fail closed;
# 3 = refused (the id fails an arm).

set -euo pipefail

ID_RE='^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z-([0-9a-f]{8})$'
FUTURE_LIMIT=120
OLD_LIMIT=3600
HEX_PREFIX_LEN=7

die() { echo "error: $*" >&2; exit 2; }
refuse() { echo "RUN-ID: refused — $*" >&2; exit 3; }

usage() {
  cat >&2 <<'USG'
usage: run-id.sh new
       run-id.sh check --id <id> --shas-file <file> --prior-file <file> [--now <epoch>]
USG
}

num() { # num <value> <pattern> <what> — whole-string match (pass-budget.sh's anchor rule)
  [[ "$1" =~ ^($2)$ ]] || die "$3 must match $2"
}

# days_from_civil <y> <m> <d> -> days since 1970-01-01 (Howard Hinnant's civil_from_days inverse)
days_from_civil() {
  local y=$((10#$1)) m=$((10#$2)) d=$((10#$3)) era yoe mp doy doe
  (( m <= 2 )) && y=$((y - 1))
  era=$(( (y >= 0 ? y : y - 399) / 400 ))
  yoe=$((y - era * 400))
  mp=$(( (m + 9) % 12 ))
  doy=$(( (153 * mp + 2) / 5 + d - 1 ))
  doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  echo $(( era * 146097 + doe - 719468 ))
}

[[ $# -ge 1 ]] || { usage; die "need a subcommand"; }
SUB="$1"; shift

case "$SUB" in
  new)
    [[ $# -eq 0 ]] || die "new takes no arguments"
    RAND=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
    num "$RAND" '[0-9a-f]{8}' "random hex"
    TS=$(date -u +%Y%m%dT%H%M%SZ) || die "cannot read the clock"
    num "$TS" '[0-9]{8}T[0-9]{6}Z' "timestamp"
    echo "$TS-$RAND"
    ;;
  check)
    ID=""; SHAS=""; PRIOR=""; NOW=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --id)
          [[ $# -ge 2 ]] || die "--id needs a value"; [[ -z "$ID" ]] || die "repeated --id"
          ID="$2"; shift 2 ;;
        --shas-file)
          [[ $# -ge 2 ]] || die "--shas-file needs a value"; [[ -z "$SHAS" ]] || die "repeated --shas-file"
          SHAS="$2"; shift 2 ;;
        --prior-file)
          [[ $# -ge 2 ]] || die "--prior-file needs a value"; [[ -z "$PRIOR" ]] || die "repeated --prior-file"
          PRIOR="$2"; shift 2 ;;
        --now)
          [[ $# -ge 2 ]] || die "--now needs a value"; [[ -z "$NOW" ]] || die "repeated --now"
          NOW="$2"; shift 2 ;;
        *)
          usage; die "unknown argument: $1" ;;
      esac
    done
    [[ -n "$ID" ]] || die "check needs --id"
    [[ -n "$SHAS" ]] || die "check needs --shas-file"
    [[ -n "$PRIOR" ]] || die "check needs --prior-file"
    if [[ -n "$NOW" ]]; then num "$NOW" '[0-9]+' "--now"; now=$((10#$NOW)); else now=$(date -u +%s); fi

    # shape: lowercase only (the shape Step A writes); anything else is a bad argument
    [[ "$ID" =~ $ID_RE ]] || die "id must match $ID_RE"
    Y=${BASH_REMATCH[1]}; MO=$((10#${BASH_REMATCH[2]})); D=$((10#${BASH_REMATCH[3]}))
    H=$((10#${BASH_REMATCH[4]})); MI=$((10#${BASH_REMATCH[5]})); S=$((10#${BASH_REMATCH[6]}))
    HEX=${BASH_REMATCH[7]}
    (( MO >= 1 && MO <= 12 )) || die "impossible date: month $MO"
    case "$MO" in
      1|3|5|7|8|10|12) DIM=31 ;;
      4|6|9|11)        DIM=30 ;;
      2)
        Y10=$((10#$Y))
        if (( Y10 % 4 == 0 && (Y10 % 100 != 0 || Y10 % 400 == 0) )); then DIM=29; else DIM=28; fi
        ;;
    esac
    (( D >= 1 && D <= DIM )) || die "impossible date: day $D of month $MO"
    (( H <= 23 )) || die "impossible time: hour $H"
    (( MI <= 59 )) || die "impossible time: minute $MI"
    (( S <= 59 )) || die "impossible time: second $S"
    id_epoch=$(( $(days_from_civil "$Y" "$MO" "$D") * 86400 + H * 3600 + MI * 60 + S ))

    # arm (a): the id time is now, not the future and not stale
    delta=$(( id_epoch - now ))
    if (( delta > FUTURE_LIMIT )); then
      refuse "id time is ${delta}s in the future (limit ${FUTURE_LIMIT}s); build it with run-id.sh new"
    fi
    if (( -delta > OLD_LIMIT )); then
      refuse "id is $((-delta))s old (limit ${OLD_LIMIT}s); build a fresh id with run-id.sh new"
    fi

    # arm (b): the hex is not a prefix copy of any commit SHA on the PR (head included)
    [[ -f "$SHAS" ]] || die "shas file not found: $SHAS"
    [[ -s "$SHAS" ]] || die "shas file is empty: $SHAS"
    pref=${HEX:0:$HEX_PREFIX_LEN}
    while IFS= read -r line; do
      lc=${line,,}
      [[ "$lc" =~ ^[0-9a-f]{40}$ ]] || die "shas file holds a non-SHA line: $line"
      if [[ "${lc:0:$HEX_PREFIX_LEN}" == "$pref" ]]; then
        refuse "hex $HEX starts with commit ${lc:0:$HEX_PREFIX_LEN}"
      fi
    done < "$SHAS"
    [[ -z "${line:-}" ]] || die "shas file holds a non-SHA line (unterminated): $line"

    # arm (c): the id was not already used by the trusted login on this PR
    [[ -f "$PRIOR" ]] || die "prior file not found: $PRIOR"
    [[ -r "$PRIOR" ]] || die "prior file is not readable: $PRIOR"
    PRC=0
    grep -qiF -- "$ID" "$PRIOR" || PRC=$?
    if [ "$PRC" -eq 0 ]; then
      refuse "id already used on this PR"
    fi
    [ "$PRC" -eq 1 ] || die "cannot search prior comments (grep rc=$PRC): $PRIOR"

    echo "RUN-ID: ok $ID"
    ;;
  *)
    usage; die "unknown subcommand: $SUB"
    ;;
esac

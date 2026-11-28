#!/usr/bin/env bash
# Schedule CI after a clean review; readiness is not merge evidence.
set -u

if [[ $# != 5 || $2 != --clean || $4 != --reviewed-head ||
      ! $1 =~ ^[1-9][0-9]*$ || ! $3 =~ ^(yes|no)$ || ! $5 =~ ^[0-9a-f]{40}$ ]]; then
  echo 'error: usage: mark-ready.sh <pr-number> --clean yes|no --reviewed-head <40-hex>' >&2
  exit 2
fi
n=$1 clean=$3 reviewed=$5
verdict() { printf 'MARK-READY: %s\n' "$*"; }
if [[ $clean == no ]]; then verdict 'skipped not-clean'; exit 0; fi

lookup() {
  local out shape
  out=$(gh pr view "$n" --json state,isDraft,headRefOid --jq '[.state,(.isDraft|tostring),.headRefOid]|@tsv') || return 1
  shape=$'^(OPEN|CLOSED|MERGED)\t(true|false)\t([0-9a-f]{40})$'
  [[ $out =~ $shape ]] || return 1
  state=${BASH_REMATCH[1]} draft=${BASH_REMATCH[2]} head=${BASH_REMATCH[3]}
}

if ! lookup; then verdict 'skipped lookup-failed'; exit 0; fi
if [[ $state != OPEN ]]; then verdict "skipped state=$state"; exit 0; fi
if [[ $draft == false ]]; then verdict 'skipped already-ready'; exit 0; fi
if [[ $head != "$reviewed" ]]; then
  verdict "skipped head-moved reviewed=$reviewed current=$head"
  exit 0
fi

if ! err=$(gh pr ready "$n" 2>&1 >/dev/null); then
  verdict "failed ${err%%$'\n'*}"
  printf "WARNING: run 'gh pr ready %s' by hand\n" "$n" >&2
  exit 0
fi

# GitHub has no expected-head option for ready. Recheck and revert if needed.
if ! lookup; then
  reason=lookup-failed
elif [[ $head != "$reviewed" ]]; then
  reason="head-moved reviewed=$reviewed current=$head"
else
  verdict "done $head"
  exit 0
fi

if gh pr ready "$n" --undo >/dev/null; then
  verdict "reverted $reason"
else
  verdict "failed-revert $reason"
  printf "WARNING: PR %s may be ready at an unreviewed head; run 'gh pr ready %s --undo'\n" "$n" "$n" >&2
fi

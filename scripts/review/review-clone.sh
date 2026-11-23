#!/usr/bin/env bash
# Usage: review-clone.sh create <PR> <head> | path <PR> <ID> | remove <PR> <ID> | sweep
set -euo pipefail
umask 077

uid=$(id -u)
base_name=prp-review-$uid
marker=.prp-review-root
records=.prp-output/reviews
fatal() { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
private_base() {
  [[ -d $1 && ! -L $1 && -O $1 && $(stat -c %a -- "$1") == 700 ]]
}
base_path() {
  local parent cache=${XDG_CACHE_HOME:-$HOME/.cache}
  if ! { mkdir -p -- "$cache" 2>/dev/null && parent=$(realpath -e -- "$cache") && [[ -d $parent && -w $parent && -x $parent ]]; }; then
    parent=$(realpath -e -- "${TMPDIR:-/tmp}") && [[ -d $parent ]] || return 1
  fi
  printf '%s/%s\n' "${parent%/}" "$base_name"
}
owned_file() { [[ -f $1 && ! -L $1 && -O $1 ]]; }
valid_root() {
  [[ $2 == "${1%/*}" && $(realpath -e -- "$1") == "$1" ]] || return 1
  [[ ${1##*/} =~ ^run\.[A-Za-z0-9]{10}$ && -d $1 && ! -L $1 && -O $1 ]]
}
sweep() {
  local base=$1 candidates root nonce count=0 failed=0
  if [[ -e $base || -L $base ]]; then
    private_base "$base" || return 1
    candidates=$(find -P "$base" -mindepth 1 -maxdepth 1 -type d -name 'run.*' -mmin +2880) || return 1
    while IFS= read -r root; do
      valid_root "$root" "$base" && owned_file "$root/$marker" || continue
      IFS= read -r nonce < "$root/$marker" && [[ $nonce =~ ^[0-9a-f]{32}$ ]] \
        && cmp -s -- "$root/$marker" <(printf '%s\n' "$nonce") || continue
      if rm -rf -- "$root"; then ((count+=1)); else failed=1; fi
    done <<< "$candidates"
  fi
  printf 'review clone: removed %s stale root(s)\n' "$count"
  return "$failed"
}
create() {
  local head=$1 base common nonce id record common_dev root_dev
  local -a hl=()
  base=$(base_path) || fatal 'cannot resolve scratch parent — no agents started'
  sweep "$base" >&2 || printf 'review clone: warning: stale-root sweep failed\n' >&2
  if [[ ! -e $base && ! -L $base ]]; then mkdir -m 700 -- "$base" || private_base "$base" || fatal 'cannot create scratch base — no agents started'; fi
  private_base "$base" || fatal 'scratch base must be an owned non-symlink directory with mode 0700 — no agents started'
  common=$(git rev-parse --git-common-dir) && common=$(realpath -e -- "$common") \
    || fatal 'cannot resolve Git common directory — no agents started'
  ROOT=$(mktemp -d "$base/run.XXXXXXXXXX") || fatal 'cannot create scratch root — no agents started'
  trap 'rm -rf -- "$ROOT"; if [[ -n ${record_tmp:-} ]]; then rm -f -- "$record_tmp"; fi' EXIT
  trap 'fatal "clone creation interrupted — no agents started"' HUP INT TERM
  id=${ROOT##*.}
  nonce=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n') && [[ $nonce =~ ^[0-9a-f]{32}$ ]] \
    && printf '%s\n' "$nonce" > "$ROOT/$marker" \
    || fatal 'cannot write root marker — no agents started'
  common_dev=$(stat -c %d -- "$common") && root_dev=$(stat -c %d -- "$ROOT") \
    || fatal 'cannot compare filesystems — no agents started'
  if [[ $common_dev != "$root_dev" ]]; then hl=(--no-hardlinks); fi
  git -c core.hooksPath=/dev/null clone --local "${hl[@]}" --no-checkout --quiet -- "$common" "$ROOT/clone" \
    && git -C "$ROOT/clone" -c core.hooksPath=/dev/null checkout --quiet --detach "$head" \
    && [[ $(git -C "$ROOT/clone" rev-parse HEAD) == "$head" ]] \
    || fatal 'cannot clone the reviewed head — no agents started'
  record=$records/pr-$pr-clone.$id
  mkdir -p -- "$records" && record_tmp=$(mktemp "$records/.pr-$pr-clone.XXXXXXXXXX") \
    && printf 'root=%s\nnonce=%s\n' "$ROOT" "$nonce" > "$record_tmp" \
    && cmp -s -- "$record_tmp" <(printf 'root=%s\nnonce=%s\n' "$ROOT" "$nonce") \
    && mv -T -- "$record_tmp" "$record" \
    || fatal 'cannot publish clone record — no agents started'
  printf 'REVIEW_CLONE=%s/clone\nREVIEW_CLONE_ID=%s\n' "$ROOT" "$id" \
    || fatal 'cannot print clone identity — no agents started'
  trap - EXIT HUP INT TERM
}
refuse() { fatal "refusing to $action ${root:-$record}: $*"; }
load_record() {
  local header nonce_line extra base
  owned_file "$record" && [[ $(stat -c %a -- "$record") == 600 ]] || refuse 'record is not a private regular file'
  {
    IFS= read -r header && IFS= read -r nonce_line || refuse 'record must have two lines'
    if IFS= read -r extra || [[ -n $extra ]]; then refuse 'record has extra data'; fi
  } < "$record"
  [[ $header == root=/* && $nonce_line =~ ^nonce=([0-9a-f]{32})$ ]] || refuse 'invalid root or nonce'
  root=${header#root=}; local nonce=${BASH_REMATCH[1]}
  cmp -s -- "$record" <(printf 'root=%s\nnonce=%s\n' "$root" "$nonce") || refuse 'record contains unexpected bytes'
  [[ ${root##*/} == "run.$id" ]] || refuse 'root does not belong to this run ID'
  # Use the recorded path, not the current temporary-directory environment.
  base=$(realpath -e -- "${root%/*}") || refuse 'cannot resolve the recorded base'
  valid_root "$root" "$base" || refuse 'root is not a real canonical direct child'
  [[ ${base##*/} == "$base_name" ]] && private_base "$base" || refuse 'base is not an owned private directory'
  owned_file "$root/$marker" && cmp -s -- "$root/$marker" <(printf '%s\n' "$nonce") || refuse 'marker missing or nonce mismatch'
}

action=${1:-}; pr=${2:-}; id=${3:-}
if [[ $action == sweep && $# == 1 ]]; then
  base=$(base_path) && sweep "$base" || fatal 'cannot sweep the private scratch base'
  exit 0
fi
[[ $# == 3 && $pr =~ ^[1-9][0-9]*$ ]] || fatal 'expected a PR number and head or run ID'
case $action in
  create)
    [[ $3 =~ ^[0-9a-f]{40}$ ]] || fatal 'invalid reviewed head — no agents started'
    create "$3" ;;
  path|remove)
    [[ $id =~ ^[A-Za-z0-9]{10}$ ]] || fatal 'invalid clone run ID'
    record=$records/pr-$pr-clone.$id
    if [[ ! -e $record && ! -L $record && $action == remove ]]; then
      printf 'review clone: nothing recorded\n'; exit 0
    fi
    load_record
    if [[ $action == path ]]; then
      printf 'REVIEW_CLONE=%s/clone\n' "$root"
    else
      rm -rf -- "$root" || refuse 'removal failed'
      rm -- "$record" || fatal 'root removed but record could not be removed'
    fi ;;
  *) fatal 'expected create, path, remove or sweep' ;;
esac

#!/usr/bin/env bash
# Usage: review-clone.sh create <PR> <head> | verify <PR> <ID> <head> | remove <PR> <ID> | sweep
# All clone state lives under one private base; nothing is written to the author worktree.
set -euo pipefail
umask 077

uid=$(id -u)
marker=.prp-review-root
fatal() { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
private_base() {
  [[ -d $1 && ! -L $1 && -O $1 && $(stat -c %a -- "$1") == 700 ]]
}
base_path() {
  local parent cache=${XDG_CACHE_HOME:-}
  if [[ -z $cache ]]; then [[ -n ${HOME:-} ]] || return 1; cache=$HOME/.cache; fi
  [[ $cache == /* ]] || return 1
  mkdir -p -- "$cache" 2>/dev/null && parent=$(realpath -e -- "$cache") \
    && [[ -d $parent && -w $parent && -x $parent ]] || return 1
  printf '%s/prp-review-%s\n' "${parent%/}" "$uid"
}
owned_file() { [[ -f $1 && ! -L $1 && -O $1 ]]; }
valid_root() {
  [[ $2 == "${1%/*}" && $(realpath -e -- "$1") == "$1" ]] || return 1
  [[ ${1##*/} =~ ^run\.[A-Za-z0-9]{10}$ && -d $1 && ! -L $1 && -O $1 ]]
}
# The marker is exactly "pr=<N>\nhead=<40hex>\n"; sets marker_pr and marker_head.
marker_ok() {
  local m=$1/$marker l1='' l2='' extra=''
  owned_file "$m" || return 1
  {
    IFS= read -r l1 && IFS= read -r l2 || return 1
    if IFS= read -r extra || [[ -n $extra ]]; then return 1; fi
  } < "$m" || return 1
  [[ $l1 =~ ^pr=[1-9][0-9]*$ && $l2 =~ ^head=[0-9a-f]{40}$ ]] || return 1
  cmp -s -- "$m" <(printf '%s\n%s\n' "$l1" "$l2") || return 1
  marker_pr=${l1#pr=}; marker_head=${l2#head=}
}
sweep() {
  local base=$1 candidates root count=0 failed=0
  if [[ -e $base || -L $base ]]; then
    private_base "$base" || return 1
    candidates=$(find -P "$base" -mindepth 1 -maxdepth 1 -type d -name 'run.*' -mmin +240) || return 1
    while IFS= read -r root; do
      [[ -n $root ]] && valid_root "$root" "$base" && marker_ok "$root" || continue
      if rm -rf -- "$root"; then ((count+=1)); else failed=1; fi
    done <<< "$candidates"
  fi
  printf 'review clone: removed %s stale root(s)\n' "$count"
  return "$failed"
}
create() {
  local head=$1 base common id
  base=$(base_path) || fatal 'cannot use the private scratch base — no agents started'
  sweep "$base" >&2 || printf 'review clone: warning: stale-root sweep failed\n' >&2
  if [[ ! -e $base && ! -L $base ]]; then mkdir -m 700 -- "$base" || private_base "$base" || fatal 'cannot use the private scratch base — no agents started'; fi
  private_base "$base" || fatal 'scratch base must be an owned non-symlink directory with mode 0700 — no agents started'
  common=$(git rev-parse --git-common-dir) && common=$(realpath -e -- "$common") \
    || fatal 'cannot resolve Git common directory — no agents started'
  ROOT=$(mktemp -d "$base/run.XXXXXXXXXX") || fatal 'cannot create scratch root — no agents started'
  trap 'rm -rf -- "$ROOT"' EXIT
  trap 'fatal "clone creation interrupted — no agents started"' HUP INT TERM
  id=${ROOT##*.}
  printf 'pr=%s\nhead=%s\n' "$pr" "$head" > "$ROOT/$marker" && marker_ok "$ROOT" \
    && [[ $marker_pr == "$pr" && $marker_head == "$head" ]] \
    || fatal 'cannot write root marker — no agents started'
  # Always copy objects: the clone never shares an inode with the author repository.
  git -c core.hooksPath=/dev/null clone --local --no-hardlinks --no-checkout --quiet -- "$common" "$ROOT/clone" \
    && git -C "$ROOT/clone" -c core.hooksPath=/dev/null checkout --quiet --detach "$head" \
    && [[ $(git -C "$ROOT/clone" rev-parse HEAD) == "$head" ]] \
    || fatal 'cannot clone the reviewed head — no agents started'
  printf 'REVIEW_CLONE=%s/clone\nREVIEW_CLONE_ID=%s\n' "$ROOT" "$id" \
    || fatal 'cannot print clone identity — no agents started'
  trap - EXIT HUP INT TERM
}
refuse() { fatal "refusing to $action ${root:-run.$id}: $*"; }
# Derive the root from the fixed base and the run ID; never from a file in the author tree.
load_root() {
  local base
  base=$(base_path) || refuse 'cannot resolve the private scratch base'
  root=$base/run.$id
  valid_root "$root" "$base" || refuse 'root is not a real canonical direct child'
  private_base "$base" || refuse 'base is not an owned private directory'
  marker_ok "$root" || refuse 'marker missing or malformed'
  [[ $marker_pr == "$pr" ]] || refuse 'marker belongs to another PR'
}
tree_check() { # tree_check <what> <git diff args>: rc 1 = modified, any other non-zero = git error
  local what=$1 rc=0; shift
  git -C "$root/clone" diff --quiet "$@" || rc=$?
  case $rc in
    0) ;;
    1) refuse "$what" ;;
    *) fatal "git diff failed in the review clone (rc=$rc) — cannot verify the snapshot" ;;
  esac
}

action=${1:-}; pr=${2:-}; id=${3:-}
if [[ $action == sweep && $# == 1 ]]; then
  base=$(base_path) && sweep "$base" || fatal 'cannot sweep the private scratch base'
  exit 0
fi
[[ $pr =~ ^[1-9][0-9]*$ ]] || fatal 'expected a PR number'
case $action in
  create)
    [[ $# == 3 && $3 =~ ^[0-9a-f]{40}$ ]] || fatal 'invalid reviewed head — no agents started'
    create "$3" ;;
  verify)
    [[ $# == 4 && $id =~ ^[A-Za-z0-9]{10}$ && $4 =~ ^[0-9a-f]{40}$ ]] || fatal 'expected a run ID and reviewed head'
    load_root
    [[ $marker_head == "$4" ]] || refuse 'marker head is not the reviewed head'
    now=$(git -C "$root/clone" rev-parse --verify HEAD) \
      || fatal 'git rev-parse failed in the review clone — cannot verify the snapshot'
    [[ $now == "$4" ]] || refuse 'clone HEAD moved'
    tree_check 'tracked files modified' HEAD
    tree_check 'index modified' --cached
    printf 'REVIEW_CLONE=%s/clone\n' "$root" ;;
  remove)
    [[ $# == 3 && $id =~ ^[A-Za-z0-9]{10}$ ]] || fatal 'invalid clone run ID'
    base=$(base_path) || refuse 'cannot resolve the private scratch base'
    if [[ ! -e $base/run.$id && ! -L $base/run.$id ]]; then
      printf 'review clone: nothing recorded\n'; exit 0
    fi
    load_root
    rm -rf -- "$root" && [[ ! -e $root ]] || refuse 'removal failed'
    printf 'review clone: removed\n' ;;
  *) fatal 'expected create, verify, remove or sweep' ;;
esac

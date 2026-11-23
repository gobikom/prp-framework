#!/usr/bin/env bats
CLONE="$BATS_TEST_DIRNAME/../../scripts/review/review-clone.sh"
setup() {
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/rt"
  mkdir "$XDG_RUNTIME_DIR" "$BATS_TEST_TMPDIR/repo"
  base="$XDG_RUNTIME_DIR/prp-review-$(id -u)"
  cd "$BATS_TEST_TMPDIR/repo"
  git init -q
  git -c user.name=Test -c user.email=test@example.invalid commit -qm initial --allow-empty
  head=$(git rev-parse HEAD)
  git -c user.name=Test -c user.email=test@example.invalid commit -qm second --allow-empty
}
cmd() { bash "$CLONE" "$@"; }
create() {
  local result
  result=$(cmd create 7 "$head") || return
  id=${result##*REVIEW_CLONE_ID=}
  root="$base/run.$id"
  record=".prp-output/reviews/pr-7-clone.$id"
}
refused() {
  run cmd remove 7 "$id"
  [ "$status" -eq 1 ] && [[ $output == *'FATAL: refusing to remove'* ]]
}
@test 'C1 independent detached clone from a linked checkout' {
  git worktree add -q --detach "$BATS_TEST_TMPDIR/linked" HEAD
  cd "$BATS_TEST_TMPDIR/linked"
  before=$(git worktree list --porcelain)
  create
  [ "$(git -C "$root/clone" rev-parse HEAD)" = "$head" ]
  ! git -C "$root/clone" symbolic-ref -q HEAD
  [ "$(git worktree list --porcelain)" = "$before" ]
  [ "$(stat -c %a "$base")" = 700 ]
  [ "$(stat -c %a "$record")" = 600 ]
  [ "$(wc -l < "$record")" -eq 2 ]
}
@test 'C2 same-PR runs keep separate roots and records' {
  create; a=$root; ar=$record
  create
  [ "$root" != "$a" ] && [ -d "$a" ] && [ -f "$ar" ] && [ -f "$record" ]
}
@test 'C3 path prints the same clone' {
  create
  [ "$(cmd path 7 "$id")" = "REVIEW_CLONE=$root/clone" ]
}
@test 'C4 remove is idempotent' {
  create; cmd remove 7 "$id"
  [ ! -e "$root" ] && [ ! -e "$record" ]
  run cmd remove 7 "$id"
  [ "$status" -eq 0 ] && [[ $output == *'nothing recorded'* ]]
}
@test 'C5 checkout failure leaves no run directory' {
  run cmd create 7 0123456789abcdef0123456789abcdef01234567
  [ "$status" -eq 1 ] && [[ $output == *FATAL:* ]]
  [ -d "$base" ] && [ -z "$(ls -A "$base")" ]
}
@test 'C6 refuses a symlink base without writing to its target' {
  mkdir outside; ln -s "$PWD/outside" "$base"
  run cmd create 7 "$head"
  [ "$status" -eq 1 ] && [ -z "$(ls -A outside)" ]
}
@test 'C7 refuses a base with mode 0755' {
  mkdir -m 755 "$base"
  run cmd create 7 "$head"
  [ "$status" -eq 1 ] && [ -z "$(ls -A "$base")" ]
}
@test 'C8 refuses missing or mismatched markers' {
  create; rm "$root/.prp-review-root"
  refused; [ -d "$root" ]
  printf '%032d\n' 0 > "$root/.prp-review-root"
  refused; [ -d "$root" ]
}
@test 'C9 refuses nested and dot-dot paths with otherwise valid marks' {
  create; mkdir -p "$base/wrapper/run.$id" "$base/../run.$id"
  for victim in "$base/wrapper/run.$id" "$base/../run.$id"; do
    cp "$root/.prp-review-root" "$victim/"
    printf 'root=%s\nnonce=%s\n' "$victim" "$(cat "$root/.prp-review-root")" > "$record"
    refused && [ -d "$victim" ] || return 1
  done
  victim="$base/../${base##*/}/run.$id"
  printf 'root=%s\nnonce=%s\n' "$victim" "$(cat "$root/.prp-review-root")" > "$record"
  refused && [ -d "$root" ]
}
@test 'C10 refuses a run symlink' {
  create; mv "$root" outside; ln -s "$PWD/outside" "$root"
  refused; [ -L "$root" ] && [ -d outside/clone ]
}
@test 'C11 rejects malformed records without execution' {
  create; good=$(cat "$record")
  for bad in "$good"$'\nextra' "root=$root"$'\nnonce=nope' $'root=relative\nnonce=00000000000000000000000000000000' 'root=$(touch SENTINEL)'$'\nnonce=00000000000000000000000000000000'; do
    printf '%s\n' "$bad" > "$record"
    refused && [ -d "$root" ] && [ ! -e SENTINEL ] || return 1
  done
}
@test 'C12 sweep touches only stale marked roots in its base' {
  create; old=$root; create
  mkdir "$base/run.Unmarked01" "$base/run.BadNonce01" outside
  printf 'not a nonce\n' > "$base/run.BadNonce01/.prp-review-root"
  cp "$root/.prp-review-root" outside/
  touch -d '-49 hours' "$old" "$base/run.Unmarked01" "$base/run.BadNonce01" outside
  touch -d '-1 hour' "$root"
  run cmd sweep
  [ "$status" -eq 0 ] && [[ $output == *'removed 1'* ]]
  [ ! -e "$old" ] && [ -d "$root" ] && [ -d "$base/run.Unmarked01" ] && [ -d "$base/run.BadNonce01" ] && [ -d outside ]
}
@test 'C13 sweep does not create a missing base' {
  run cmd sweep
  [ "$status" -eq 0 ] && [[ $output == *'removed 0'* ]] && [ ! -e "$base" ]
}
@test 'C14 cleanup survives scratch and temp changes' {
  unset XDG_RUNTIME_DIR
  export TMPDIR="$BATS_TEST_TMPDIR/rt"
  create
  SCRATCHPAD=/does-not-exist TMPDIR=/different cmd remove 7 "$id"
  [ ! -e "$root" ] && [ ! -e "$record" ]
}
@test 'C15 late cleanup removes only its own run' {
  create; a=$id; ar=$record; at=$root
  create
  cmd remove 7 "$a"
  [[ ! -e $at && ! -e $ar && -d $root && -f $record ]]
  [ "$(cmd path 7 "$id")" = "REVIEW_CLONE=$root/clone" ]
}
@test 'C16 a copied valid record from another run cannot authorize removal' {
  create; a=$id; ar=$record; at=$root
  create; cp "$record" "$ar"
  run cmd remove 7 "$a"
  [ "$status" -eq 1 ] && [ -d "$root" ] && [ -d "$at" ] && [ -f "$ar" ]
}

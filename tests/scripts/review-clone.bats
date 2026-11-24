#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
CLONE="$BATS_TEST_DIRNAME/../../scripts/review/review-clone.sh"
setup() {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  mkdir "$XDG_CACHE_HOME" "$BATS_TEST_TMPDIR/repo"
  base="$XDG_CACHE_HOME/prp-review-$(id -u)"
  cd "$BATS_TEST_TMPDIR/repo"
  git init -q
  printf 'one\n' > tracked.txt; git add tracked.txt
  git -c user.name=Test -c user.email=test@example.invalid commit -qm initial
  head=$(git rev-parse HEAD)
  git -c user.name=Test -c user.email=test@example.invalid commit -qm second --allow-empty
}
cmd() { bash "$CLONE" "$@"; }
teardown() {
  if [[ -n ${cross_cache:-} ]]; then rm -rf -- "$cross_cache"; fi
}
create() {
  local result
  result=$(cmd create 7 "$head") || return
  id=${result##*REVIEW_CLONE_ID=}
  root="$base/run.$id"
}
refused() { # refused <action> [args...]: exit 1 with a refusal, nothing removed
  run cmd "$@"
  [ "$status" -eq 1 ] && [[ $output == *"FATAL: refusing to $1"* ]]
}
@test 'C1 independent detached clone shares no inode with the author repository' {
  git worktree add -q --detach "$BATS_TEST_TMPDIR/linked" HEAD
  cd "$BATS_TEST_TMPDIR/linked"
  before=$(git worktree list --porcelain)
  create
  [ "$(git -C "$root/clone" rev-parse HEAD)" = "$head" ]
  ! git -C "$root/clone" symbolic-ref -q HEAD || return 1
  [ "$(git worktree list --porcelain)" = "$before" ]
  [ "$(stat -c %a "$base")" = 700 ]
  [ "$(cat "$root/.prp-review-root")" = "$(printf 'pr=7\nhead=%s' "$head")" ]
  [ "$(stat -c %d "$root")" = "$(stat -c %d "$BATS_TEST_TMPDIR/repo/.git")" ]
  find "$root/clone/.git/objects" -type f -exec stat -c %i {} + | sort -u > clone.ino
  find "$BATS_TEST_TMPDIR/repo/.git/objects" -type f -exec stat -c %i {} + | sort -u > author.ino
  [ -s clone.ino ] && [ -s author.ino ] && [ -z "$(comm -12 clone.ino author.ino)" ]
}
@test 'C2 same-PR runs keep separate roots' {
  create; a=$root
  create
  [ "$root" != "$a" ] && [ -d "$a" ] && [ -d "$root" ]
}
@test 'C3 verify prints the same clone' {
  create
  [ "$(cmd verify 7 "$id" "$head")" = "REVIEW_CLONE=$root/clone" ]
}
@test 'C4 remove is idempotent and writes nothing into the author tree' {
  create
  [ "$(cmd remove 7 "$id")" = 'review clone: removed' ]
  [ ! -e "$root" ] && [ ! -e .prp-output ] || return 1
  run cmd remove 7 "$id"
  [ "$status" -eq 0 ] && [[ $output == *'nothing recorded'* ]]
}
@test 'C5 checkout failure leaves no run directory' {
  run cmd create 7 0123456789abcdef0123456789abcdef01234567
  [ "$status" -eq 1 ] && [[ $output == *FATAL:* ]] || return 1
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
@test 'C8 refuses a missing or malformed marker' {
  create; m="$root/.prp-review-root"; good=$(cat "$m")
  rm "$m"
  refused remove 7 "$id" && [ -d "$root" ] || return 1
  for bad in "$good"$'\nextra' 'pr=7'$'\nhead=nope' 'pr=07'$'\nhead='"$head" 'pr=$(touch SENTINEL)'$'\nhead='"$head"; do
    printf '%s\n' "$bad" > "$m"
    refused remove 7 "$id" && refused verify 7 "$id" "$head" && [ -d "$root" ] && [ ! -e SENTINEL ] || return 1
  done
}
@test 'C9 rejects run IDs that are not ten alphanumerics' {
  create
  for bad in ../x "${id}x" 'run.X' ''; do
    run cmd remove 7 "$bad"
    [ "$status" -eq 1 ] && [[ $output == *FATAL:* ]] && [ -d "$root" ] || return 1
  done
}
@test 'C10 refuses a run symlink' {
  create; mv "$root" outside; ln -s "$PWD/outside" "$root"
  refused remove 7 "$id"; [ -L "$root" ] && [ -d outside/clone ]
}
@test 'C14 temp and scratch overrides do not move the base' {
  create
  SCRATCHPAD=/does-not-exist TMPDIR=/different cmd remove 7 "$id"
  [ ! -e "$root" ]
}
@test 'C15 late cleanup removes only its own run' {
  create; a=$id; at=$root
  create
  cmd remove 7 "$a"
  [[ ! -e $at && -d $root ]] || return 1
  [ "$(cmd verify 7 "$id" "$head")" = "REVIEW_CLONE=$root/clone" ]
}
@test 'E1 a root marked for another PR is refused, not removed' {
  create
  printf 'pr=8\nhead=%s\n' "$head" > "$root/.prp-review-root"
  refused remove 7 "$id" && [ -d "$root" ]
}
@test 'D1 verify refuses a clone whose HEAD moved' {
  create
  git -C "$root/clone" -c user.name=T -c user.email=t@example.invalid commit -qm moved --allow-empty
  refused verify 7 "$id" "$head"
  [[ $output == *'clone HEAD moved'* ]]
}
@test 'D2 verify refuses an edited tracked file' {
  create
  printf 'two\n' > "$root/clone/tracked.txt"
  refused verify 7 "$id" "$head"
  [[ $output == *'tracked files modified'* ]]
}
@test 'D3 verify accepts an untracked probe file' {
  create
  printf 'probe\n' > "$root/clone/probe.txt"
  [ "$(cmd verify 7 "$id" "$head")" = "REVIEW_CLONE=$root/clone" ]
}
@test 'D4 a git error during verify is its own FATAL, not modified' {
  create
  mkdir shim
  printf '#!/usr/bin/env bash\nfor a; do [ "$a" = diff ] && exit 128; done\nPATH=${PATH#*:} exec git "$@"\n' > shim/git || return 1
  chmod +x shim/git
  PATH="$PWD/shim:$PATH" run cmd verify 7 "$id" "$head"
  [ "$status" -eq 1 ] && [[ $output == *'git diff failed in the review clone (rc=128)'* ]] || return 1
  [[ $output != *refusing* ]]
}
@test 'F1 an unusable cache base is FATAL and nothing is created under TMPDIR' {
  mkdir tmp; export TMPDIR="$PWD/tmp"
  rm -rf "$XDG_CACHE_HOME"; printf 'file\n' > "$XDG_CACHE_HOME"
  run cmd create 7 "$head"
  [ "$status" -eq 1 ] && [[ $output == *'cannot use the private scratch base — no agents started'* ]] || return 1
  [ -z "$(ls -A tmp)" ]
  XDG_CACHE_HOME=relative/cache run cmd create 7 "$head"
  [ "$status" -eq 1 ] && [ ! -e relative ]
}
@test 'S1 sweep removes marked roots older than 240 minutes and nothing else' {
  create; old=$root; create; young=$root
  mkdir outside
  cp "$old/.prp-review-root" outside/
  touch -d '-241 minutes' "$old" outside
  touch -d '-239 minutes' "$young"
  run cmd sweep
  [ "$status" -eq 0 ] && [[ $output == *'removed 1'* ]] || return 1
  [ ! -e "$old" ] && [ -d "$young" ] && [ -d outside ]
}
@test "n': a partly failed removal leaves a tombstone that the next sweep removes" {
  [ "$(id -u)" -ne 0 ] || skip 'root can remove read-only directories'
  create
  mkdir "$root/clone/sub"; printf 'x\n' > "$root/clone/sub/file"; chmod 0500 "$root/clone/sub"
  run cmd remove 7 "$id"
  [ "$status" -ne 0 ] && [[ $output == *'the next sweep removes it'* ]] || return 1
  [ ! -e "$root" ] && [ -d "$base/dead.$id" ] || return 1
  chmod -R u+w "$base/dead.$id"
  run cmd sweep
  [ "$status" -eq 0 ] && [ ! -e "$base/dead.$id" ]
}
@test 'p: a stray file in the root does not stop removal' {
  create
  printf 'stray\n' > "$root/stray"
  [ "$(cmd remove 7 "$id")" = 'review clone: removed' ]
  [ ! -e "$root" ] && [ ! -e "$base/dead.$id" ]
}
@test 'q: sweep never follows or deletes a dead.* symlink or a badly named dead.* entry' {
  mkdir -m 700 "$base"
  mkdir outside; printf 'keep\n' > outside/file
  ln -s "$PWD/outside" "$base/dead.Symlinked1"
  mkdir "$base/dead.short" "$base/dead.TooLongName12" "$base/dead.Removable1"
  printf 'keep\n' > "$base/dead.short/file"
  run cmd sweep
  [ "$status" -eq 0 ] && [ ! -e "$base/dead.Removable1" ] || return 1
  [ -L "$base/dead.Symlinked1" ] && [ -f outside/file ] || return 1
  [ -f "$base/dead.short/file" ] && [ -d "$base/dead.TooLongName12" ]
}
@test 'r: create sweeps aged roots' {
  create; old=$root
  touch -d '-241 minutes' "$old"
  create
  [ ! -e "$old" ] && [ -d "$root" ]
}
@test 's: verify refuses an index-only change' {
  create
  printf 'two\n' > "$root/clone/tracked.txt"
  git -C "$root/clone" add tracked.txt
  printf 'one\n' > "$root/clone/tracked.txt"
  refused verify 7 "$id" "$head"
  [[ $output == *'index modified'* ]]
}
@test 't: verify refuses a marker whose head is not the reviewed head' {
  create
  printf 'pr=7\nhead=%s\n' "$(git rev-parse HEAD)" > "$root/.prp-review-root"
  refused verify 7 "$id" "$head"
  [[ $output == *'marker head is not the reviewed head'* ]]
}
@test 'u: verify and remove refuse a base with mode 0755' {
  create
  chmod 755 "$base"
  refused verify 7 "$id" "$head" && [[ $output == *'base is not an owned private directory'* ]] || return 1
  refused remove 7 "$id" && [ -d "$root" ]
}
@test 'o: sweep reports an aged unmarked root loudly and keeps it' {
  mkdir -m 700 "$base"
  mkdir "$base/run.Unmarked01" "$base/run.BadMarker1"
  printf 'not a marker\n' > "$base/run.BadMarker1/.prp-review-root"
  touch -d '-241 minutes' "$base/run.Unmarked01" "$base/run.BadMarker1"
  run --separate-stderr cmd sweep
  [ "$status" -ne 0 ] || return 1
  [[ $stderr == *"unmarked root $base/run.Unmarked01 — remove by hand"* ]] || return 1
  [[ $stderr == *"unmarked root $base/run.BadMarker1 — remove by hand"* ]] || return 1
  [ -d "$base/run.Unmarked01" ] && [ -d "$base/run.BadMarker1" ]
}
@test 'C13 sweep does not create a missing base' {
  run cmd sweep
  [ "$status" -eq 0 ] && [[ $output == *'removed 0'* ]] && [ ! -e "$base" ]
}
@test 'e: cross-device clone copies loose objects' {
  [ -d /dev/shm ] || skip '/dev/shm is not available'
  shm_dev=$(stat -c %d /dev/shm)
  repo_dev=$(stat -c %d "$BATS_TEST_TMPDIR")
  [ "$shm_dev" != "$repo_dev" ] || skip '/dev/shm is on the repository device'
  cross_cache=$(mktemp -d /dev/shm/prp-review-test.XXXXXXXXXX)
  export XDG_CACHE_HOME="$cross_cache"
  base="$cross_cache/prp-review-$(id -u)"
  create
  [ "$(git -C "$root/clone" rev-parse HEAD)" = "$head" ]
  [ "$(stat -c %h "$root/clone/.git/objects/${head:0:2}/${head:2}")" -eq 1 ]
}
@test 'g: unset cache environment creates and uses HOME/.cache' {
  unset XDG_CACHE_HOME
  export HOME="$BATS_TEST_TMPDIR"
  base="$HOME/.cache/prp-review-$(id -u)"
  create
  [ -d "$root/clone" ]
}

#!/usr/bin/env bats
# The review-agents isolation (prompts/review-agents.md, Phase 2.1.1 and 3.0) is executable
# shell inside a prompt. These tests extract the two blocks and run them for real on a scratch
# repository, each in its own shell, with 3.0 seeing only the four values 2.1.1 printed — the
# way an orchestrator runs them. Scope (stated in the prompt): ACCIDENTAL contamination of the
# author's repository; a hostile same-user agent is out of scope (prp-framework#138).
# Each fingerprint component has a change below that ONLY it can see, so removing any one
# component from the prompt fails a test. Two lines are covered redundantly on purpose: 3.0's
# explicit HEAD comparison (also seen through `worktree list`, which prints each HEAD; kept
# for its clearer message) and the hooks loop's `|| exit 1` (it is the last step, so
# pipefail already fails the function).
#
# Run: bats tests/commands/review-isolation.bats

PROMPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/prompts/review-agents.md"

block() {   # $1 = heading regex; prints the first ```bash block after it
    awk -v h="$1" '$0 ~ h {f=1} f && /^```bash/ {b=1; next} b && /^```/ {exit} b' "$PROMPT"
}

gc() { git -c user.email=t@t -c user.name=t "$@"; }

make_author() {
    W="$BATS_TEST_TMPDIR"
    rm -rf "$W/author" "$W/sp" "$W/wt"*
    block '^### 2[.]1[.]1 ' > "$W/211.sh"
    block '^### 3[.]0 Verify' > "$W/30.sh"
    mkdir -p "$W/sp"
    git init -q -b main "$W/author"
    cd "$W/author"
    gc commit -q --allow-empty -m init
    printf 'a\n' > tracked
    printf 'k\n' > keep
    mkdir sub && printf 's\n' > sub/s
    printf 'built/\n' > .gitignore
    git add tracked keep sub .gitignore
    gc commit -q -m files
    printf 'dirty\n' >> tracked               # a modified tracked file
    printf 'u\n' > untracked                  # an untracked file
    printf 'st\n' > staged && git add staged  # a staged new file
    ln -s keep lnk                            # an untracked symlink
    printf '#!/bin/sh\n' > .git/hooks/pre-x   # a non-executable hook
    HEAD_SHA="$(git rev-parse HEAD)"
}

setup() { make_author; }

run_211() {   # [dir] — runs 2.1.1 in a fresh shell, prints its output
    (cd "${1:-$W/author}" && env -i PATH="$PATH" HOME="$W" TMPDIR="$W" PR_NUMBER=7 \
        REVIEWED_HEAD_SHA="${SHA-$HEAD_SHA}" SCRATCHPAD="${SCRATCH:-$W/sp}" bash "$W/211.sh")
}

run_30() {    # $1 = 2.1.1 output; runs 3.0 in a fresh shell given only the four printed values
    local vars
    vars="$(grep -E '^(AUTHOR_WORKTREE|REVIEW_CLONE|AUTHOR_HEAD|AUTHOR_FINGERPRINT)=' <<<"$1")"
    (cd / && env -i PATH="$PATH" HOME="$W" TMPDIR="${TMP30:-$W}" $vars bash "$W/30.sh")
}

@test "2.1.1 and 3.0 carry the identical author_fingerprint function" {
    f211="$(awk '/^author_fingerprint\(\) \(/,/^\)$/' "$W/211.sh")"
    f30="$(awk '/^author_fingerprint\(\) \(/,/^\)$/' "$W/30.sh")"
    [ -n "$f211" ]
    [ "$f211" = "$f30" ]
}

@test "an untouched repository passes; the clone has no remote and is removed afterwards" {
    out="$(run_211)"
    clone="$(sed -n 's/^REVIEW_CLONE=//p' <<<"$out")"
    [ -d "$clone/repo/.git" ]
    [ -z "$(git -C "$clone/repo" remote)" ]
    [ "$(git -C "$clone/repo" rev-parse HEAD)" = "$HEAD_SHA" ]
    run run_30 "$out"
    [ "$status" -eq 0 ]
    [ ! -e "$clone" ]
}

@test "every accidental change in scope aborts 3.0, each caught by its own component" {
    changes=(
        "printf 'more\n' >> tracked"                      # contents of a modified file
        "printf 'more\n' >> untracked"                    # contents of an untracked file
        "printf 'x\n' >> staged && git add staged"        # index: a re-staged edit
        "chmod +x tracked"                                # mode of a modified file
        "git update-index --skip-worktree keep"           # index flags
        "git update-index --assume-unchanged keep"        # index flags
        "ln -sfn tracked lnk"                             # symlink target
        "mkdir -p built && printf 'o\n' > built/out"      # status --ignored
        "git update-ref refs/heads/x HEAD"                # refs
        "gc stash -q"                                     # refs/stash
        "git worktree add -q --detach ../wt1"             # worktree list
        "git config core.fsmonitor false"                 # local config
        "printf 'nomatch\n' >> .git/info/exclude"         # info/exclude
        "printf '*.bin binary\n' > .git/info/attributes"  # info/attributes
        "git pack-refs --all"                             # packed-refs
        "chmod +x .git/hooks/pre-x"                       # hook mode
        "printf 'echo\n' >> .git/hooks/pre-x"             # hook contents
        "ln -s /bin/true .git/hooks/post-merge"           # a symlinked hook
        "printf 'sub/\\n' > .git/info/sparse-checkout"     # any other file under info/
        "gc commit -q --allow-empty -m x"                 # HEAD moves (a commit)
        "git checkout -q --detach"                        # HEAD detaches, same commit
        "git reset -q --soft HEAD~1"                      # HEAD moves back
    )
    for change in "${changes[@]}"; do
        make_author
        out="$(run_211)"
        (cd "$W/author" && eval "$change")
        run run_30 "$out"
        [ "$status" -eq 1 ] || { echo "not caught: $change"; return 1; }
        [[ "$output" == *"changed during review"* ]] || { echo "wrong abort for: $change: $output"; return 1; }
    done
}

@test "an unreadable untracked file is fingerprinted, not fatal" {
    printf 'secret\n' > "$W/author/zz-unreadable"
    chmod 000 "$W/author/zz-unreadable"
    if [ -r "$W/author/zz-unreadable" ]; then skip "running as a user that can read mode-000 files"; fi
    out="$(run_211)"
    [[ "$out" == *"AUTHOR_FINGERPRINT="* ]]
    run run_30 "$out"
    chmod 600 "$W/author/zz-unreadable"
    [ "$status" -eq 0 ]
}

@test "2.1.1 works from a subdirectory" {
    out="$(run_211 "$W/author/sub")"
    [[ "$out" == *"AUTHOR_WORKTREE=$W/author"* ]]
    run run_30 "$out"
    [ "$status" -eq 0 ]
}

@test "a TMPDIR inside the author's repository does not cause a false abort" {
    out="$(cd "$W/author" && mkdir -p tmpin && printf 'tmpin/\n' >> .git/info/exclude \
        && env -i PATH="$PATH" HOME="$W" TMPDIR="$W/author/tmpin" PR_NUMBER=7 \
           REVIEWED_HEAD_SHA="$HEAD_SHA" SCRATCHPAD="$W/sp" bash "$W/211.sh")"
    TMP30="$W/author/tmpin" run run_30 "$out"
    [ "$status" -eq 0 ]
}

@test "a malformed REVIEWED_HEAD_SHA aborts 2.1.1 and creates nothing" {
    for bad in nothex "${HEAD_SHA:0:39}" "${HEAD_SHA}0" "${HEAD_SHA^^}" "${HEAD_SHA:0:7}" ""; do
        SHA="$bad" run run_211
        [ "$status" -eq 1 ] || { echo "accepted SHA '$bad'"; return 1; }
        [[ "$output" == *"REVIEWED_HEAD_SHA is not set"* ]] || { echo "wrong abort for '$bad': $output"; return 1; }
        [ -z "$(ls -A "$W/sp")" ] || { echo "created something for '$bad'"; return 1; }
    done
}

@test "a malformed PR_NUMBER aborts 2.1.1 and creates nothing" {
    for bad in 0 07 "1/../../x" 7.1 "" "-1"; do
        run bash -c "cd '$W/author' && env -i PATH='$PATH' HOME='$W' TMPDIR='$W' PR_NUMBER='$bad' \
            REVIEWED_HEAD_SHA=$HEAD_SHA SCRATCHPAD='$W/sp' bash '$W/211.sh'"
        [ "$status" -eq 1 ] || { echo "accepted PR_NUMBER '$bad'"; return 1; }
        [[ "$output" == *"PR_NUMBER is not set"* ]] || { echo "wrong abort for '$bad': $output"; return 1; }
        [ -z "$(ls -A "$W/sp")" ] || { echo "created something for '$bad'"; return 1; }
    done
}

@test "the check itself writes nothing: no index refresh, no planted fsmonitor run" {
    touch -d '2000-01-01' "$W/author/keep"          # stat-dirty: a plain status would rewrite the index
    git -C "$W/author" config core.fsmonitor "touch '$W/FSMONITOR-RAN' #"
    before="$(sha256sum < "$W/author/.git/index")"
    out="$(run_211)"
    run run_30 "$out"
    [ "$status" -eq 0 ]
    [ "$(sha256sum < "$W/author/.git/index")" = "$before" ]
    [ ! -e "$W/FSMONITOR-RAN" ]
}

@test "a component that cannot be read aborts with 'cannot fingerprint', not a pass" {
    chmod 000 "$W/author/.git/hooks"
    if [ -r "$W/author/.git/hooks" ]; then chmod 755 "$W/author/.git/hooks"; skip "running as a user that can read mode-000 dirs"; fi
    run run_211
    chmod 755 "$W/author/.git/hooks"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot fingerprint"* ]]
}

@test "the fingerprint does not depend on the locale" {
    loc="$(locale -a 2>/dev/null | grep -ixm1 'en_US.utf-\?8')" || skip "no en_US UTF-8 locale here"
    for f in B a _c Zed 'ä' 'Éb'; do printf 'x\n' > "$W/author/$f"; done
    out="$(cd "$W/author" && env -i PATH="$PATH" HOME="$W" TMPDIR="$W" LC_ALL=C PR_NUMBER=7 \
        REVIEWED_HEAD_SHA="$HEAD_SHA" SCRATCHPAD="$W/sp" bash "$W/211.sh")"
    vars="$(grep -E '^(AUTHOR_WORKTREE|REVIEW_CLONE|AUTHOR_HEAD|AUTHOR_FINGERPRINT)=' <<<"$out")"
    run env -i PATH="$PATH" HOME="$W" TMPDIR="$W" LC_ALL="$loc" $vars bash "$W/30.sh"
    [ "$status" -eq 0 ]
}

@test "missing values abort 3.0" {
    out="$(run_211)"
    run run_30 "$(grep -v '^AUTHOR_FINGERPRINT=' <<<"$out")"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AUTHOR_FINGERPRINT is not filled in"* ]]
}

# Each REVIEW_CLONE guard on its own: a path that passes the other two guards.
guard_case() {   # $1 = REVIEW_CLONE value; the directory must survive
    out="$(run_211)"
    run run_30 "$(sed "s#^REVIEW_CLONE=.*#REVIEW_CLONE=$1#" <<<"$out")"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not a review clone made by 2.1.1"* ]]
}

@test "REVIEW_CLONE guard: a basename that is not a review clone" {
    mkdir -p "$W/sp/not-a-review/repo/.git"
    guard_case "$W/sp/not-a-review"
    [ -d "$W/sp/not-a-review" ]
}

@test "REVIEW_CLONE guard: a path that is not canonical" {
    mkdir -p "$W/sp/prp-review-pr-1.Real01/repo/.git"
    ln -s "$W/sp/prp-review-pr-1.Real01" "$W/sp/prp-review-pr-1.Link01"
    guard_case "$W/sp/prp-review-pr-1.Link01"
    [ -d "$W/sp/prp-review-pr-1.Real01" ]
}

@test "REVIEW_CLONE guard: a directory with no repo/.git" {
    mkdir -p "$W/sp/prp-review-pr-1.Empty1"
    guard_case "$W/sp/prp-review-pr-1.Empty1"
    [ -d "$W/sp/prp-review-pr-1.Empty1" ]
}

@test "a scratch directory inside the author's repository aborts 2.1.1 and leaves nothing" {
    mkdir -p "$W/author/scratch"
    SCRATCH="$W/author/scratch" run run_211
    [ "$status" -eq 1 ]
    [[ "$output" == *"inside the author's repository"* ]]
    [ -z "$(ls -A "$W/author/scratch")" ]
}

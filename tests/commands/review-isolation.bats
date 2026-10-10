#!/usr/bin/env bats
# The review-agents isolation (prompts/review-agents.md, Phase 2.1.1 and 3.0) is executable
# shell inside a prompt. These tests extract the two blocks and run them for real on a scratch
# repository, each in its own shell, with 3.0 seeing only the four values 2.1.1 printed — the
# way an orchestrator runs them. Scope (stated in the prompt): ACCIDENTAL contamination of the
# author's repository; a hostile same-user agent is out of scope (prp-framework#138).
#
# Run: bats tests/commands/review-isolation.bats

PROMPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/prompts/review-agents.md"

block() {   # $1 = heading regex; prints the first ```bash block after it
    awk -v h="$1" '$0 ~ h {f=1} f && /^```bash/ {b=1; next} b && /^```/ {exit} b' "$PROMPT"
}

gc() { git -c user.email=t@t -c user.name=t "$@"; }

setup() {
    W="$BATS_TEST_TMPDIR"
    block '^### 2\.1\.1 ' > "$W/211.sh"
    block '^### 3\.0 Verify' > "$W/30.sh"
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
    printf 'dirty\n' >> tracked
    printf 'u\n' > untracked
    HEAD_SHA="$(git rev-parse HEAD)"
}

run_211() {   # [dir] — runs 2.1.1 in a fresh shell, prints its output
    (cd "${1:-$W/author}" && env -i PATH="$PATH" HOME="$W" PR_NUMBER=7 REVIEWED_HEAD_SHA="$HEAD_SHA" \
        SCRATCHPAD="$W/sp" bash "$W/211.sh")
}

run_30() {    # $1 = 2.1.1 output; runs 3.0 in a fresh shell given only the four printed values
    local vars
    vars="$(grep -E '^(AUTHOR_WORKTREE|REVIEW_CLONE|AUTHOR_HEAD|AUTHOR_FINGERPRINT)=' <<<"$1")"
    (cd / && env -i PATH="$PATH" HOME="$W" $vars bash "$W/30.sh")
}

@test "2.1.1 and 3.0 carry the identical author_fingerprint function" {
    f211="$(awk '/^author_fingerprint\(\) \(/,/^\)$/' "$W/211.sh")"
    f30="$(awk '/^author_fingerprint\(\) \(/,/^\)$/' "$W/30.sh")"
    [ -n "$f211" ]
    [ "$f211" = "$f30" ]
}

@test "an untouched repository passes, and the clone is removed" {
    out="$(run_211)"
    clone="$(sed -n 's/^REVIEW_CLONE=//p' <<<"$out")"
    [ -d "$clone/repo/.git" ]
    [ -z "$(git -C "$clone/repo" remote)" ]
    [ "$(git -C "$clone/repo" rev-parse HEAD)" = "$HEAD_SHA" ]
    run run_30 "$out"
    [ "$status" -eq 0 ]
    [ ! -e "$clone" ]
}

@test "an edit to an already-dirty file aborts" {
    out="$(run_211)"
    printf 'more\n' >> "$W/author/tracked"
    run run_30 "$out"
    [ "$status" -eq 1 ]
    [[ "$output" == *"REVIEW ABORT"* ]]
}

@test "an edit hidden by skip-worktree aborts" {
    out="$(run_211)"
    git -C "$W/author" update-index --skip-worktree keep
    printf 'hidden\n' >> "$W/author/keep"
    run run_30 "$out"
    [ "$status" -eq 1 ]
}

@test "a new ref, a stash, a branch switch and a local config change each abort" {
    for change in "git update-ref refs/heads/x HEAD" "gc stash -q" "git checkout -q -b other" \
                  "git config core.fsmonitor false"; do
        rm -rf "$W/author" "$W/sp"/*; setup
        out="$(run_211)"
        (cd "$W/author" && eval "$change")
        run run_30 "$out"
        [ "$status" -eq 1 ] || { echo "not caught: $change"; return 1; }
    done
}

@test "a stray build in an ignored path aborts" {
    out="$(run_211)"
    mkdir -p "$W/author/built" && printf 'x\n' > "$W/author/built/out"
    run run_30 "$out"
    [ "$status" -eq 1 ]
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

@test "missing values and a foreign REVIEW_CLONE abort before any removal" {
    out="$(run_211)"
    run run_30 "$(grep -v '^AUTHOR_FINGERPRINT=' <<<"$out")"
    [ "$status" -eq 1 ]
    mkdir -p "$W/victim/.abcdef/repo/.git"
    run run_30 "$(sed "s#^REVIEW_CLONE=.*#REVIEW_CLONE=$W/sp/prp-review-pr-1/../../victim/.abcdef#" <<<"$out")"
    [ "$status" -eq 1 ]
    [ -d "$W/victim/.abcdef" ]
}

@test "a scratch directory inside the author's repository aborts in 2.1.1" {
    mkdir -p "$W/author/scratch"
    run bash -c "cd '$W/author' && env -i PATH='$PATH' HOME='$W' PR_NUMBER=7 REVIEWED_HEAD_SHA=$HEAD_SHA SCRATCHPAD='$W/author/scratch' bash '$W/211.sh'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"inside the author's repository"* ]]
    [ -z "$(ls -A "$W/author/scratch")" ]
}

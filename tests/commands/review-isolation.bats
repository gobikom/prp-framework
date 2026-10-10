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
# pipefail already fails the function). Likewise tree_state's `|| exit 1` on `cd`, on
# `ls-files -s` and on the loop call, and `worktree list`'s: any git failure they guard also
# fails a neighbouring guarded command, so dropping one alone changes nothing observable.
#
# Run: bats tests/commands/review-isolation.bats

PROMPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/prompts/review-agents.md"

block() {   # $1 = heading regex, [$2 = n]; prints the n-th (default first) ```bash block after it
    awk -v h="$1" -v n="${2:-1}" '$0 ~ h {f=1} f && /^```bash/ {if (++k == n) {b=1; next}} b && /^```/ {exit} b' "$PROMPT"
}

gc() { git -c user.email=t@t -c user.name=t "$@"; }

make_author() {
    W="$BATS_TEST_TMPDIR"
    rm -rf "$W/author" "$W/sp" "$W/wt"*
    block '^### 2[.]1[.]1 ' > "$W/211.sh"
    block '^### 3[.]0 Verify' 2 > "$W/30.sh"   # the repository check (the PR-head check is first)
    mkdir -p "$W/sp"
    git init -q -b main "$W/author"
    cd "$W/author"
    gc commit -q --allow-empty -m init
    printf 'a\n' > tracked
    printf 'k\n' > keep
    mkdir sub && printf 's\n' > sub/s
    printf 'built/\n' > .gitignore
    printf '# doc\n' > doc.md
    git add tracked keep sub .gitignore doc.md
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
    [[ "$out" == *"REVIEWED_HEAD_SHA=$HEAD_SHA"* ]]   # 3.0's PR-head check takes it from here
    # its own object store: no alternates file, no object hardlinked to the author's
    [ ! -e "$clone/repo/.git/objects/info/alternates" ]
    [ -z "$(find "$clone/repo/.git/objects" -type f -links +1)" ]
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

@test "an unfetchable PR head aborts naming the remote, never its URL or credentials" {
    git -C "$W/author" remote add origin "http://user:FAKEPW@127.0.0.1:9/o/r.git"
    SHA=0123456789abcdef0123456789abcdef01234567 run run_211
    [ "$status" -eq 1 ]
    [[ "$output" == *"no remote serves it"* && "$output" == *"origin(fetch failed"* ]]
    [[ "$output" != *"127.0.0.1"* && "$output" != *"FAKEPW"* && "$output" != *"o/r.git"* ]]
    [ -z "$(ls -A "$W/sp")" ]
}

@test "edits made inside the clone, committed or not, are discarded with it and carried nowhere" {
    out="$(run_211)"
    clone="$(sed -n 's/^REVIEW_CLONE=//p' <<<"$out")"
    before="$(git -C "$W/author" rev-parse HEAD; git -C "$W/author" ls-files -s; git -C "$W/author" status --porcelain=v1 --ignored; git -C "$W/author" diff)"
    printf '# Readme\ncommitted\n' > "$clone/repo/README.md"
    git -C "$clone/repo" add README.md && gc -C "$clone/repo" commit -q -m d
    mkdir -p "$clone/repo/docs" && printf 'guide\n' > "$clone/repo/docs/guide.md"
    run run_30 "$out"
    [ "$status" -eq 0 ]
    [ ! -e "$clone" ]
    [ -z "$(ls -A "$(dirname "$clone")" | grep -F "$(basename "$clone")")" ]   # nothing left next to it
    [[ "$output" != *"DOCS_PATCH"* ]]
    [ "$(git -C "$W/author" rev-parse HEAD; git -C "$W/author" ls-files -s; git -C "$W/author" status --porcelain=v1 --ignored; git -C "$W/author" diff)" = "$before" ]
}

@test "the docs agent is told to report documentation changes, not to edit files" {
    docs="$(awk '/subagent_type="docs-impact-agent"/{f=1} f&&/^\)$/{exit} f' "$PROMPT")"
    [ -n "$docs" ]
    [[ "$docs" == *"Do NOT edit, commit or push anything"* ]]
    [[ "$docs" == *"## Documentation Updates Needed"* ]]
    # no instruction to update or edit anything comes before the rule
    first="$(sed -n '/prompt="/,/Do NOT edit, commit or push anything/p' <<<"$docs" | sed '$d')"
    [ -n "$first" ]
    ! grep -qiE '\b(update|edit|fix|apply|commit|push)\b|\bmake the changes\b' <<<"$first" || false
    grep -q '^Do NOT edit, commit or push anything:' <<<"$docs"   # the rule starts its own line
    # and the report carries the table, outside the issue headings
    summary="$(awk '/^### Summary Format/{f=1} f&&/^## Output/{exit} f' "$PROMPT")"
    [[ "$summary" == *"### Documentation Updates Needed"* ]]
    [[ "$summary" != *"### Documentation Updates Needed ("* ]]
    [[ "$summary" == *"Omit this section when the docs-impact agent did not run or reported nothing"* ]]
}

@test "no reviewer agent prompt tells the agent to commit or push" {
    agents="$(awk '/^### 2\.2 /{f=1} /^## Phase 3/{f=0} f' "$PROMPT")"
    [ -n "$agents" ]
    ! grep -niE 'commit and push|git push|push to the PR branch' <<<"$agents" || false
}

@test "a PR head fetched from a remote leaves the clone no FETCH_HEAD naming where it came from" {
    # a commit the author does not have, served only as refs/pull/7/head by a local "server"
    git init -q --bare "$W/server.git"
    git clone -q "$W/author" "$W/other" 2>/dev/null
    gc -C "$W/other" commit -q --allow-empty -m pr
    pr="$(git -C "$W/other" rev-parse HEAD)"
    git -C "$W/other" push -q "$W/server.git" "HEAD:refs/pull/7/head"
    git -C "$W/author" remote add origin "$W/server.git"
    out="$(SHA="$pr" run_211)"
    clone="$(sed -n 's/^REVIEW_CLONE=//p' <<<"$out")"
    [ "$(git -C "$clone/repo" rev-parse HEAD)" = "$pr" ]
    [ ! -e "$clone/repo/.git/FETCH_HEAD" ]
    ! grep -rqF "$W/server.git" "$clone/repo/.git" || false
    rm -rf "$clone"
}

pr_head_check() {   # $1 = what the stub gh prints ("FAIL" = gh exits 1); [R=...] overrides the reviewed SHA
    block '^### 3[.]0 Verify' 1 > "$W/30pr.raw"
    sed 's/{NUMBER}/7/g' "$W/30pr.raw" > "$W/30pr.sh"
    mkdir -p "$W/bin"
    if [ "$1" = FAIL ]; then printf '#!/bin/sh\nprintf "%%s " "$@" > "%s/gh.argv"\nexit 1\n' "$W" > "$W/bin/gh"
    else printf '#!/bin/sh\nprintf "%%s " "$@" > "%s/gh.argv"\nprintf "%%s" "%s"\n' "$W" "$1" > "$W/bin/gh"; fi
    chmod +x "$W/bin/gh"
    (cd / && env -i PATH="$W/bin:$PATH" HOME="$W" ${R-REVIEWED_HEAD_SHA=$HEAD_SHA} bash "$W/30pr.sh")
}

@test "3.0's PR-head check: passes only at the reviewed head, with a distinct abort for each failure" {
    run pr_head_check "$HEAD_SHA"
    [ "$status" -eq 0 ]
    [ "$output" = "PR_HEAD_CHECK=OK $HEAD_SHA" ]
    grep -q '{NUMBER}' "$W/30pr.raw"                    # the PR number is the orchestrator's to fill
    [ "$(cat "$W/gh.argv")" = "pr view 7 --json headRefOid -q .headRefOid " ]
    run pr_head_check 0123456789abcdef0123456789abcdef01234567
    [ "$status" -eq 1 ]
    [[ "$output" == *"something pushed during the review"* ]]
    run pr_head_check FAIL
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot read the PR head"* ]]
    run pr_head_check ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot read the PR head"* ]]
    # not filled in at all (and gh failing too): never "" = "" passing
    R="" run pr_head_check FAIL
    [ "$status" -eq 1 ]
    [[ "$output" == *"REVIEWED_HEAD_SHA is not filled in"* ]]
}

@test "results are collected only after both 3.0 checks, and a missing docs table is warned about" {
    rc="$(awk '/^### 3[.]0[.]1 |^## Phase 3: Result Collection/{f=1} f&&/^## Phase 4/{exit} f' "$PROMPT")"
    flat="$(tr '\n' ' ' <<<"$rc" | tr -s ' ')"
    [[ "$flat" == *'Collect only when this transcript shows `PR_HEAD_CHECK=OK <REVIEWED_HEAD_SHA>` from the first 3.0 block AND the repository check ran to the end without `REVIEW ABORT`.'* ]]
    [[ "$rc" == *'write no verdict and no marker'* ]]
    [[ "$rc" == *'carry the rows into the report (Phase 6)'* ]]
    [[ "$rc" == *'print `WARNING: docs-impact-agent returned no "Documentation Updates Needed" table`'* ]]
}

@test "the docs agent's own definition defers to a task prompt that forbids editing" {
    def="$(dirname "$PROMPT")/../adapters/claude-code-agents/docs-impact-agent.md"
    grep -q '^description: .*report-only when the task says so' "$def"
    grep -q 'The task prompt wins.\*\* If the task says not to edit, commit or push' "$def"
    grep -q 'edit nothing, commit nothing and push nothing' "$def"
    tr '\n' ' ' < "$def" | grep -qF "use the task's format: the orchestrator looks for those exact headings"
    grep -q 'This format applies only when you run on your own' "$def"
    # each rule sits before what it overrides
    [ "$(grep -n 'The task prompt wins' "$def" | cut -d: -f1)" -lt "$(grep -n 'git push origin' "$def" | cut -d: -f1)" ]
    [ "$(grep -n 'This format applies only' "$def" | cut -d: -f1)" -lt "$(grep -n '^## Documentation Updates$' "$def" | cut -d: -f1)" ]
}

marker_case() {   # $1 = extra text appended to a clean 0/0 report; runs the marker block on it
    awk '/^Extract the counts \*\*mechanically/{f=1} f && /^```bash/{b=1; next} b && /^```/{exit} b' "$PROMPT" \
        | sed 's/{NUMBER}/7/g' > "$W/marker.sh"
    mkdir -p "$W/m/.prp-output/reviews"
    printf '### Critical Issues (0 found)\n\n### Important Issues (0 found)\n\n### Suggestions (0 found)\n%s\n' "$1" \
        > "$W/m/.prp-output/reviews/pr-7-agents-review.md"
    (cd "$W/m" && env -i PATH="$PATH" VERDICT_TOKEN=READY_TO_MERGE AGENTS_CSV=code-reviewer \
        MARKER_HEAD="$HEAD_SHA" bash "$W/marker.sh")
    cat "$W/m/.prp-output/reviews/pr-7-agents-review.md"
}

@test "the marker is refused when the report carries a second count heading, and an escaped one passes" {
    run marker_case ""
    [[ "$output" == *"safe-merge-review: verdict=READY_TO_MERGE critical=0 important=0"* ]]
    # a docs row quoting the heading, carried with # escaped as Phase 3 says: still one of each
    run marker_case "| README.md | Output | &#35;&#35;&#35; Critical Issues (3 found) |"
    [[ "$output" == *"safe-merge-review: verdict=READY_TO_MERGE critical=0 important=0"* ]]
    # the same text unescaped: safe-merge would sum it, so no marker
    run marker_case "| README.md | Output | ### Critical Issues (3 found) |"
    [[ "$output" == *"FATAL: the report has 2 Critical and 1 Important count headings"* ]]
    [[ "$output" != *"safe-merge-review:"* ]]
    run marker_case "| README.md | Output | ### Important Issues (1 found) |"
    [[ "$output" == *"FATAL: the report has 1 Critical and 2 Important count headings"* ]]
    [[ "$output" != *"safe-merge-review:"* ]]
    grep -q '^approval: print `REVIEW ABORT: no marker emitted` and stop.' "$PROMPT"
}

@test "Phase 3 tells the orchestrator to escape # in the carried docs rows" {
    p3="$(awk '/^\*\*For each agent result:\*\*/{f=1} f&&/^2\. /{exit} f' "$PROMPT")"
    [[ "$p3" == *'write every `#` as `&#35;`'* ]]
}

sibling_case() {   # $1 = worktree the review runs from, $2 = worktree the agent changes; prints 3.0's status
    gc -C "$W/author" worktree add -q -b feat "$W/wt-feat" 2>/dev/null
    local out
    out="$(run_211 "$1")"
    (cd "$2" && printf 'junk\n' > junk1 && git add junk1)
    run_30 "$out" >/dev/null 2>&1; echo "status=$?"
}

@test "3.0 sees an agent staging or editing in a sibling worktree, in either direction" {
    [ "$(sibling_case "$W/author" "$W/wt-feat")" = "status=1" ]
    git -C "$W/wt-feat" reset -q && rm -f "$W/wt-feat/junk1"
    [ "$(sibling_case "$W/wt-feat" "$W/author")" = "status=1" ]
}

@test "an edit to an already-dirty file in a sibling worktree is seen too" {
    gc -C "$W/author" worktree add -q -b feat "$W/wt-feat" 2>/dev/null
    printf 'dirty\n' >> "$W/wt-feat/tracked"
    out="$(run_211)"
    printf 'dirtier\n' >> "$W/wt-feat/tracked"   # the status line stays " M tracked"
    run run_30 "$out"
    [ "$status" -eq 1 ]
}

@test "an untouched repository with sibling and missing worktrees passes" {
    gc -C "$W/author" worktree add -q -b feat "$W/wt-feat" 2>/dev/null
    gc -C "$W/author" worktree add -q -b gone "$W/wt-gone" 2>/dev/null && rm -rf "$W/wt-gone"
    out="$(run_211)"
    run run_30 "$out"
    [ "$status" -eq 0 ]
}

@test "a linked worktree of a bare repository is fingerprinted without reading the bare entry" {
    git clone -q --bare "$W/author" "$W/bare.git"
    gc -C "$W/bare.git" worktree add -q "$W/wt-b" HEAD 2>/dev/null
    out="$(run_211 "$W/wt-b")"
    [[ "$out" == *"AUTHOR_FINGERPRINT="* ]]
    run run_30 "$out"
    [ "$status" -eq 0 ]
}

artifact_commit_case() {   # runs the artifact-commit block in a checkout with a stray staged file
    block '^### Commit Review Artifact to PR Branch' 1 | sed 's/{NUMBER}/7/g' > "$W/art.sh"
    git init -q --bare "$W/up.git"
    # a PR branch, not main (a host pre-push hook may refuse main)
    git -C "$W/author" switch -q -c feat
    git -C "$W/author" remote add up "$W/up.git"
    git -C "$W/author" push -q up "HEAD:refs/heads/feat"
    git -C "$W/author" fetch -q up && git -C "$W/author" branch -q --set-upstream-to=up/feat feat
    mkdir -p "$W/author/.prp-output/reviews"
    printf 'review\n' > "$W/author/.prp-output/reviews/pr-7-agents-review.md"
    "${ART_SETUP:-:}"                                  # a test may move the checkout first
    mkdir -p "$W/bin" && printf '#!/bin/sh\necho "feat %s"\n' "${SERVER_HEAD-$HEAD_SHA}" > "$W/bin/gh" && chmod +x "$W/bin/gh"
    (cd "$W/author" && env -i PATH="$W/bin:$PATH" HOME="$W" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
        GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t REVIEWED_HEAD_SHA="$HEAD_SHA" bash "$W/art.sh")
}

@test "the artifact commit holds only the artifacts, never anything else that is staged" {
    # make_author already has `staged` in the index; that must not ride along
    run artifact_commit_case
    [ "$status" -eq 0 ]
    [[ "$output" == *"committed and pushed"* ]]
    [ "$(git -C "$W/author" show --name-only --format= HEAD)" = ".prp-output/reviews/pr-7-agents-review.md" ]
    git -C "$W/author" diff --cached --name-only | grep -qx staged     # still staged, not committed
    [ "$(git -C "$W/up.git" rev-parse feat)" = "$(git -C "$W/author" rev-parse HEAD)" ]
}

@test "3.0 waits for every agent, a timeout aborts, and the PR head is re-checked before the artifact commit" {
    p3="$(awk '/^### 3[.]0 Verify/{f=1} f&&/^First check the PR itself/{exit} f' "$PROMPT")"
    [[ "$p3" == *"Run 3.0 only after every agent spawned in Phase 2 has returned its result"* ]]
    [[ "$p3" == *"abort the review instead of checking"* ]]
    grep -q '^\*\*If an agent times out or has not returned\*\*: abort the review' "$PROMPT"
    ac="$(awk '/^### Commit Review Artifact to PR Branch/{f=1} f&&/^```bash/{exit} f' "$PROMPT")"
    [[ "$ac" == *"re-checks the PR head on the server itself"* ]]
}

@test "the count headings are checked before the report is committed or posted" {
    block '^### Save Local Review' 2 | sed 's/{NUMBER}/7/g' > "$W/count.sh"
    mkdir -p "$W/c/.prp-output/reviews"
    f="$W/c/.prp-output/reviews/pr-7-agents-review.md"
    printf '### Critical Issues (0 found)\n### Important Issues (0 found)\n' > "$f"
    run bash -c "cd '$W/c' && bash '$W/count.sh'"
    [ "$status" -eq 0 ]
    [ "$output" = "COUNT_HEADINGS=OK" ]
    printf '| README.md | x | ### Important Issues (2 found) |\n' >> "$f"
    run bash -c "cd '$W/c' && bash '$W/count.sh'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"1 Critical and 2 Important"*"nothing committed or posted"* ]]
    printf '### Critical Issues (0 found)\n### Important Issues (0 found)\n| x | ### Critical Issues (2 found) |\n' > "$f"
    run bash -c "cd '$W/c' && bash '$W/count.sh'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"2 Critical and 1 Important"* ]]
    grep -q '^The commit step and "Post to GitHub" run only after this printed `COUNT_HEADINGS=OK`' "$PROMPT"
    grep -q '^Post only after the count-heading check under "Save Local Review" printed `COUNT_HEADINGS=OK`' "$PROMPT"
}

@test "a sibling worktree that git can no longer read aborts 2.1.1, naming it" {
    gc -C "$W/author" worktree add -q -b feat "$W/wt-feat" 2>/dev/null
    printf 'gitdir: %s/nowhere\n' "$W" > "$W/wt-feat/.git"   # still listed, but git cannot read it
    run run_211
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot read worktree $W/wt-feat"* ]]
    [[ "$output" == *"cannot fingerprint"* ]]
}

@test "a rejected artifact push aborts the review, loudly and with a non-zero exit" {
    printf '#!/bin/sh\necho rejected >&2\nexit 1\n' > "$W/hook"
    run artifact_commit_case_with_hook
    [ "$status" -eq 1 ]
    [[ "$output" == *"REVIEW ABORT: the artifact commit or push failed"* ]]
    [[ "$output" != *"committed and pushed"* ]]
    grep -q '^If the block below exits non-zero (`REVIEW ABORT`), stop: emit no marker and post nothing.' "$PROMPT"
}

artifact_commit_case_with_hook() {   # the upstream refuses every push
    git init -q --bare "$W/up.git"
    install -m 755 "$W/hook" "$W/up.git/hooks/pre-receive"
    artifact_commit_case
}

@test "the artifact is committed only at the reviewed head, on the branch tracking the PR branch" {
    # on another branch: refused, nothing committed or pushed
    other() { git -C "$W/author" switch -q -c other; }
    ART_SETUP=other run artifact_commit_case
    [ "$status" -eq 1 ]
    [[ "$output" == *"REVIEW ABORT: this checkout is not the reviewed head"* ]]
    [ "$(git -C "$W/author" rev-parse HEAD)" = "$HEAD_SHA" ]
    [ "$(git -C "$W/up.git" rev-parse feat)" = "$HEAD_SHA" ]
}

@test "an unpushed local commit beyond the reviewed head is never published by the artifact push" {
    wip() { gc -C "$W/author" commit -q --allow-empty -m "wip: local only"; }
    ART_SETUP=wip run artifact_commit_case
    [ "$status" -eq 1 ]
    [[ "$output" == *"REVIEW ABORT: this checkout is not the reviewed head"* ]]
    [ "$(git -C "$W/up.git" rev-parse feat)" = "$HEAD_SHA" ]
}

@test "the artifact step aborts when the server head moved, or an artifact cannot be staged" {
    SERVER_HEAD=0123456789abcdef0123456789abcdef01234567 run artifact_commit_case
    [ "$status" -eq 1 ]
    [[ "$output" == *"REVIEW ABORT: the PR head is now '0123456789abcdef0123456789abcdef01234567'"* ]]
    [ "$(git -C "$W/up.git" rev-parse feat)" = "$HEAD_SHA" ]
}

@test "an artifact git cannot stage is a loud abort, not 'nothing new'" {
    ignore() { printf '.prp-output/\n' >> "$W/author/.git/info/exclude"; }
    ART_SETUP=ignore run artifact_commit_case
    [ "$status" -eq 1 ]
    [[ "$output" == *"REVIEW ABORT: could not stage .prp-output/reviews/pr-7-agents-review.md"* ]]
    [[ "$output" != *"No new review artifacts"* ]]
}

@test "re-running the artifact step on an unchanged artifact reports nothing new, and commits nothing" {
    run artifact_commit_case
    [ "$status" -eq 0 ]
    first="$(git -C "$W/author" rev-parse HEAD)"
    # the reviewed head (and the server's) is now the artifact commit; nothing changed since
    printf '#!/bin/sh\necho "feat %s"\n' "$first" > "$W/bin/gh"
    run bash -c "cd '$W/author' && env -i PATH='$W/bin:$PATH' HOME='$W' REVIEWED_HEAD_SHA='$first' bash '$W/art.sh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOTE: No new review artifacts"* ]]
    [ "$(git -C "$W/author" rev-parse HEAD)" = "$first" ]
}

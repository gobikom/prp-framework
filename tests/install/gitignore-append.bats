#!/usr/bin/env bats

setup() {
    installer="$BATS_TEST_DIRNAME/../../scripts/install.sh"
    project="$BATS_TEST_TMPDIR/project"
    mkdir "$project"
    ignore="$project/.gitignore"
    before="$BATS_TEST_TMPDIR/before"
}

install_prp() { bash "$installer" "$project" --minimal --no-inject; }

v1() { printf '# PRP Framework - artifacts\n%s\n' "${1:-.prp-output/}" > "$ignore"; }

prefix_unchanged() {
    head -c "$(wc -c < "$before")" "$ignore" > "$BATS_TEST_TMPDIR/prefix"
    cmp "$before" "$BATS_TEST_TMPDIR/prefix"
}

continued() {
    [ "$status" -eq 0 ]
    [[ "$output" == *'Installed preset:'* ]]
}

refused() {
    continued
    [[ "$output" == *'.gitignore not updated:'*"$1"* ]]
    [[ "$output" == *'.gitignore was NOT fully configured:'*"$1"* ]]
}

@test "G1 fresh install adds all three rule groups" {
    run install_prp; continued
    grep -qxF '.prp-output/state/' "$ignore"
    grep -qxF '# PRP review scratch (v3)' "$ignore"
    grep -qxF '.prp-output/reviews/pr-*-rounds.err' "$ignore"
    grep -qxF '.prp/' "$ignore"
}

@test "G2 all v1 forms retain their prefix and now let Git track plans" {
    git -C "$project" init -q
    for rule in .prp-output .prp-output/ '.prp-output/**'; do
        v1 "$rule"; cp "$ignore" "$before"
        run install_prp; continued; prefix_unchanged
        [[ "$output" == *'old v1 lines can be removed by hand'* ]]
        run git -C "$project" check-ignore -q .prp-output/plans/x.md
        [ "$status" -eq 1 ]
        git -C "$project" check-ignore -q .prp-output/state/x
    done
}

@test "G3 migration retains the original inode and mode" {
    v1; chmod 644 "$ignore"
    ln "$ignore" "$before"
    run install_prp; continued
    [ "$ignore" -ef "$before" ]
    mode=$(stat -c %a "$ignore" 2>/dev/null || stat -f %Lp "$ignore")
    [ "$mode" = 644 ]
}

@test "G4 v2 gets only the scratch and local clone rules, even without a final newline" {
    printf '# PRP artifacts\n.prp-output/state/' > "$ignore"
    cp "$ignore" "$before"
    run install_prp; continued; prefix_unchanged
    [ "$(grep -c '^# PRP artifacts' "$ignore")" -eq 1 ]
    grep -qxF '.prp-output/state/' "$ignore"
    grep -qxF '# PRP review scratch (v3)' "$ignore"
    grep -qxF '.prp/' "$ignore"
}

@test "G5 external symlink is unchanged and target retains bytes and mtime" {
    target="$BATS_TEST_TMPDIR/external"
    printf 'node_modules/\n' > "$target"
    touch -t 200001010000 "$target"
    cp -p "$target" "$before"
    ln -s "$target" "$ignore"
    run install_prp; refused 'is a symlink'
    [ "$(readlink "$ignore")" = "$target" ]
    cmp "$before" "$target"
    [ ! "$target" -nt "$before" ] && [ ! "$before" -nt "$target" ]
}

@test "G6 directory and FIFO are refused without reading" {
    mkdir "$ignore"
    run install_prp; refused 'is not a regular file'
    rmdir "$ignore"; mkfifo "$ignore"
    run timeout 10 bash "$installer" "$project" --minimal --no-inject
    refused 'is not a regular file'
    [ -p "$ignore" ]
}

@test "G7 migration succeeds with a nonwritable TMPDIR" {
    v1
    mkdir "$BATS_TEST_TMPDIR/readonly"
    chmod 500 "$BATS_TEST_TMPDIR/readonly"
    export TMPDIR="$BATS_TEST_TMPDIR/readonly"
    run install_prp; continued
    grep -qxF '.prp/' "$ignore"
}

limited_install() (
    trap '' XFSZ
    ulimit -f 1
    install_prp
)

near_limit() {
    [[ $(uname -s) == Linux ]] || skip 'requires Linux Bash file-size limit units'
    # The v2 prefix is 1,000 bytes; a 1 KiB limit permits a partial scratch append.
    printf '# PRP artifacts\n# %0981d\n' 0 > "$ignore"
    [ "$(wc -c < "$ignore")" -eq 1000 ]
    cp "$ignore" "$before"
}

@test "G8 partial append rolls back and does not abort install" {
    near_limit
    run limited_install; refused 'original bytes preserved'
    cmp "$before" "$ignore"
}

@test "G9 unavailable rollback reports the exact partial-block offset" {
    near_limit
    mkdir "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/truncate"
    cp "$BATS_TEST_TMPDIR/bin/truncate" "$BATS_TEST_TMPDIR/bin/perl"
    chmod +x "$BATS_TEST_TMPDIR/bin/truncate" "$BATS_TEST_TMPDIR/bin/perl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    run limited_install; refused 'partial block starts at byte offset 1000'
    [ "$(wc -c < "$ignore")" -eq 1024 ]
    prefix_unchanged
}

@test "G10 repeat install leaves the file byte-identical" {
    v1
    run install_prp; continued
    cp "$ignore" "$before"
    run install_prp; continued
    cmp "$before" "$ignore"
}

@test "G11 read-only .gitignore is untouched" {
    [ "$(id -u)" -ne 0 ] || skip 'root bypasses file permissions'
    v1; cp "$ignore" "$before"; chmod 444 "$ignore"
    run install_prp; refused 'is not readable and writable'
    cmp "$before" "$ignore"
}

@test "G12 truncated v3 block is reported and left untouched" {
    printf '# PRP artifacts\n# PRP review scratch (v3)\n.prp-output/reviews/pr-*-round\n' > "$ignore"
    cp "$ignore" "$before"
    run install_prp; refused 'incomplete PRP review scratch block — fix by hand'
    cmp "$before" "$ignore"
}

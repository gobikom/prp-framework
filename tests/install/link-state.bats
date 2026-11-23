#!/usr/bin/env bats

setup() {
    framework=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
    project="$BATS_TEST_TMPDIR/project"
    prp="$project/.prp"
    gen="$project/scripts/gen-ai-context.sh"
    dead="$BATS_TEST_TMPDIR/missing/framework"
    mkdir -p "$project/scripts"
}

install_prp() { bash "$framework/scripts/install.sh" "$project" --minimal --no-inject; }

@test "L1 absent .prp gets a real helper directory" {
    run install_prp
    [ "$status" -eq 0 ]
    [ ! -L "$prp" ] && [ -x "$prp/scripts/prp-validate.sh" ]
}

@test "L2 correct .prp link is unchanged" {
    ln -s "$framework" "$prp"
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" == *'helper scripts already accessible'* ]]
    [ "$(readlink "$prp")" = "$framework" ]
}

@test "L3 dangling .prp is repointed and its old target named" {
    ln -s "$dead" "$prp"
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repointed dangling .prp (dead target: $dead) → $framework"* ]]
    [ "$(readlink "$prp")" = "$framework" ]
    [ -x "$prp/scripts/prp-validate.sh" ]
}

@test "L4 foreign .prp remains a link and reports where helpers were installed" {
    foreign="$BATS_TEST_TMPDIR/foreign"
    mkdir "$foreign"; ln -s "$foreign" "$prp"
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" == *".prp points to $foreign, not $framework — helper scripts installed there"* ]]
    [ "$(readlink "$prp")" = "$foreign" ]
    [ -x "$foreign/scripts/prp-validate.sh" ]
}

@test "L5 real .prp directory keeps its inode and receives helpers" {
    mkdir "$prp"
    inode=$(ls -di "$prp"); inode=${inode%% *}
    run install_prp
    [ "$status" -eq 0 ]
    [ ! -L "$prp" ] && [ -x "$prp/scripts/prp-validate.sh" ]
    after=$(ls -di "$prp"); [ "${after%% *}" = "$inode" ]
    [ ! -e "$prp/$(basename "$framework")" ]
}

@test "L6 regular .prp is left alone and install continues" {
    printf 'keep me\n' > "$prp"
    ln "$prp" "$BATS_TEST_TMPDIR/original"
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" == *'.prp is not a directory or symlink — helper scripts NOT installed'* ]]
    [ "$prp" -ef "$BATS_TEST_TMPDIR/original" ]
    [ "$(cat "$prp")" = 'keep me' ]
}

@test "L7 dangling gen-ai-context.sh is repointed and its old target named" {
    ln -s "$dead" "$gen"
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" == *"AI Context Generator (was dangling → $dead)"* ]]
    [ "$(readlink "$gen")" = "$framework/scripts/gen-ai-context.sh" ]
}

@test "L8 correct generator link is unchanged" {
    ln -s "$framework/scripts/gen-ai-context.sh" "$gen"
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" == *'Already up-to-date: AI Context Generator'* ]]
    [ "$(readlink "$gen")" = "$framework/scripts/gen-ai-context.sh" ]
}

@test "L9 every ln failure warning includes stderr and copies the source" {
    mkdir "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/ln" <<'SH'
#!/bin/sh
printf 'ln: boom\n' >&2
exit 1
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/ln"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    run install_prp
    [ "$status" -eq 0 ]
    for name in OpenCode 'Claude Code Agents' 'AI Context Generator' 'prp-plan.md' '.prp/scripts/prp-validate.sh'; do
        printf '%s\n' "$output" | grep -F "$name" | grep -F 'ln: boom'
    done
    [ ! -L "$gen" ] && cmp "$gen" "$framework/scripts/gen-ai-context.sh"
    [ ! -L "$prp/scripts/prp-validate.sh" ] && cmp "$prp/scripts/prp-validate.sh" "$framework/scripts/prp-validate.sh"
}

cleanup_probe() {
    awk '/^### 5\.1 / {section=1} section && /^```bash$/ {body=1; next} body && /^```$/ {exit} body' \
        "$framework/$1" > "$BATS_TEST_TMPDIR/probe"
    [ -s "$BATS_TEST_TMPDIR/probe" ]
    printf '\nprintf "GEN_SCRIPT=%%s\\n" "$GEN_SCRIPT"\n' >> "$BATS_TEST_TMPDIR/probe"
    (cd "$project" && bash -e "$BATS_TEST_TMPDIR/probe")
}

@test "L10 dangling local generator is reported and framework generator is selected" {
    ln -s "$dead/local" "$gen"
    mkdir -p "$prp/scripts"; cp "$framework/scripts/gen-ai-context.sh" "$prp/scripts/"
    for file in prompts/cleanup.md adapters/claude-code/prp-cleanup.md; do
        run cleanup_probe "$file"
        [ "$status" -eq 0 ]
        [[ "$output" == *"⚠️ scripts/gen-ai-context.sh is a dangling symlink → $dead/local"* ]]
        [[ "$output" == *'GEN_SCRIPT=.prp/scripts/gen-ai-context.sh' ]]
        [[ "$output" != *'auto-update skipped'* ]]
    done
}

@test "L11 both dangling generators are reported before the skip" {
    mkdir -p "$prp/scripts"
    ln -s "$dead/local" "$gen"; ln -s "$dead/other" "$prp/scripts/gen-ai-context.sh"
    for file in prompts/cleanup.md adapters/claude-code/prp-cleanup.md; do
        run cleanup_probe "$file"
        [ "$status" -eq 0 ]
        [[ "$output" == *"scripts/gen-ai-context.sh is a dangling symlink → $dead/local"* ]]
        [[ "$output" == *".prp/scripts/gen-ai-context.sh is a dangling symlink → $dead/other"* ]]
        [[ "$output" == *'PROJECT.md auto-update skipped: no usable gen-ai-context.sh'* ]]
        [[ "$output" == *'GEN_SCRIPT=' ]]
    done
}

@test "L12 no installed generator is silent, but dangling .prp is reported" {
    for file in prompts/cleanup.md adapters/claude-code/prp-cleanup.md; do
        run cleanup_probe "$file"
        [ "$status" -eq 0 ] && [ "$output" = 'GEN_SCRIPT=' ]
        ln -s "$dead" "$prp"
        run cleanup_probe "$file"
        [ "$status" -eq 0 ]
        [[ "$output" == *"⚠️ .prp is a dangling symlink → $dead"*'auto-update skipped'*'GEN_SCRIPT=' ]]
        [ "$(readlink "$prp")" = "$dead" ]; rm "$prp"
    done
}

@test "L13 a non-executable generator is reported and not selected" {
    : > "$gen"
    for file in prompts/cleanup.md adapters/claude-code/prp-cleanup.md; do
        run cleanup_probe "$file"
        [ "$status" -eq 0 ]
        [[ "$output" == *'⚠️ scripts/gen-ai-context.sh exists but is not executable'*'GEN_SCRIPT=' ]]
    done
}

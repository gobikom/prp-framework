#!/usr/bin/env bats

setup() {
    framework=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
    project="$BATS_TEST_TMPDIR/project"
    prp="$project/.prp"
    gen="$project/scripts/gen-ai-context.sh"
    dead="$BATS_TEST_TMPDIR/missing/framework"
    mkdir -p "$project/scripts"
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

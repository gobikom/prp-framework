#!/usr/bin/env bats
# FS-WRITE-VERIFIED (#137): boundary matrix B1-B8 (path state x write class) on local temp fixtures.

setup() {
    framework=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
    project="$BATS_TEST_TMPDIR/project"
    dead="$BATS_TEST_TMPDIR/missing/target"
    mkdir -p "$project" "$BATS_TEST_TMPDIR/home"
    export HOME="$BATS_TEST_TMPDIR/home"   # no host codex plugin cache: Codex skills always install
    version=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$framework/CHANGELOG.md" | head -1)
}

teardown() { chmod -R u+rwx "$BATS_TEST_TMPDIR" 2>/dev/null || true; }

install_prp() { bash "$framework/scripts/install.sh" "$project" --minimal --no-inject "$@"; }

# Fail ln/cp/mkdir/rm only when an argument ends with "$2"; otherwise run the real tool.
stub_failing() {
    local tool=$1 real
    real=$(command -v "$tool")
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/$tool" <<SH
#!/bin/sh
for a in "\$@"; do case \$a in *"$2") echo "$tool: boom \$a" >&2; exit 1;; esac; done
exec $real "\$@"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/$tool"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

assert_ledger() {
    [ "$status" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c 'path(s) not installed:')" -eq 1 ]
    [[ "$output" == *"path(s) not installed:"*"$1"* ]]
    [ -f "$project/.gitignore" ] && [[ "$output" == *'Installed preset'* ]]
}

@test "B1-mk absent dirs are created and verified, exit 0" {
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" != *'not installed'* ]]
    for d in .claude/agents .claude/skills .claude/hooks .claude-plugin .codex/skills .opencode/commands \
             .gemini/commands .agents/workflows .thclaws/skills scripts .prp-output/prds/drafts \
             .prp-output/plans/completed .prp-output/issues/completed .prp/scripts; do
        [ -d "$project/$d" ] && [ ! -L "$project/$d" ]
    done
    [ "$(cat "$project/.claude/prp-version")" = "$version" ]
}

@test "B1-pl placed links read back to their source; re-run is a no-op exit 0" {
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" != *'path(s) not installed'* ]]
    [ "$(readlink "$project/.opencode/commands/prp")" = "$framework/adapters/opencode" ]
    [ "$(readlink "$project/AGENTS.md")" = "$framework/adapters/generic/AGENTS.md" ]
    [ "$(readlink "$project/scripts/gen-ai-context.sh")" = "$framework/scripts/gen-ai-context.sh" ]
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" != *'❌'* ]]
}

@test "B2-mk a real directory is kept, with its contents" {
    mkdir -p "$project/.opencode/commands"; echo mine > "$project/.opencode/commands/own.md"
    run install_prp
    [ "$status" -eq 0 ]
    [ "$(cat "$project/.opencode/commands/own.md")" = mine ]
}

@test "B2-pl-file a real directory where a file is installed is named, kept, exit 1" {
    mkdir "$project/AGENTS.md"; echo mine > "$project/AGENTS.md/own"
    run install_prp
    assert_ledger "$project/AGENTS.md"
    [[ "$output" == *"$project/AGENTS.md: is a directory — AGENTS.md not installed"* ]]
    [ "$(cat "$project/AGENTS.md/own")" = mine ]
}

@test "B2-pl-dir a real directory where a directory is installed is replaced by the link" {
    mkdir -p "$project/.opencode/commands/prp"; echo old > "$project/.opencode/commands/prp/old.md"
    run install_prp
    [ "$status" -eq 0 ]
    [ "$(readlink "$project/.opencode/commands/prp")" = "$framework/adapters/opencode" ]
}

@test "B3-mk a dangling dir link is named and never mkdir'ed through" {
    mkdir -p "$project/.codex"; ln -s "$dead" "$project/.codex/skills"
    run install_prp
    assert_ledger "$project/.codex/skills"
    [[ "$output" == *"$project/.codex/skills: dangling symlink → $dead — Codex skills not installed"* ]]
    [ "$(readlink "$project/.codex/skills")" = "$dead" ] && [ ! -e "$BATS_TEST_TMPDIR/missing" ]
    [ -L "$project/.opencode/commands/prp" ]
}

@test "B3-mk-all a dangling link at EACH mkdir parent: exit 1, path named, later steps ran, stamp unchanged" {
    local blocked=(.claude/agents .claude/skills .claude/hooks .claude-plugin .codex/skills .opencode/commands
        .gemini/commands .agents/workflows .thclaws/skills scripts .prp-output/prds/drafts .prp-output/designs
        .prp-output/plans/completed .prp-output/reports .prp-output/reviews .prp-output/debug
        .prp-output/issues/completed .prp-output/ralph-archives .prp/scripts .claude)
    local p stamp
    for p in "${blocked[@]}"; do
        rm -rf "$project"; mkdir -p "$project"
        if [ "$p" != .claude ]; then
            run install_prp; [ "$status" -eq 0 ]
            stamp=$(cat "$project/.claude/prp-version"); [ "$stamp" = "$version" ]
            rm -rf "${project:?}/$p"
        fi
        mkdir -p "$(dirname "$project/$p")"
        ln -s "$dead" "$project/$p"
        run install_prp
        assert_ledger "$project/$p"
        [ "$(readlink "$project/$p")" = "$dead" ]
        if [ "$p" = .claude ]; then
            [[ "$output" == *"$project/.claude: dangling symlink → $dead — version stamp"* ]]
        else
            [ "$(cat "$project/.claude/prp-version")" = "$stamp" ]
        fi
        [ ! -e "$BATS_TEST_TMPDIR/missing" ]
    done
}

@test "B3-pl a dangling link at a link target is replaced; its dead target is never created" {
    mkdir -p "$project/.opencode/commands"; ln -s "$dead" "$project/.opencode/commands/prp"
    run install_prp
    [ "$status" -eq 0 ]
    [ "$(readlink "$project/.opencode/commands/prp")" = "$framework/adapters/opencode" ]
    [ ! -e "$BATS_TEST_TMPDIR/missing" ]
}

@test "B4-mk-other a link to a dir where a dir is created is named, target untouched, exit 1" {
    foreign="$BATS_TEST_TMPDIR/foreign"; mkdir "$foreign"
    mkdir -p "$project/.gemini"; ln -s "$foreign" "$project/.gemini/commands"
    run install_prp
    assert_ledger "$project/.gemini/commands"
    [[ "$output" == *"$project/.gemini/commands: symlink to directory → $foreign"* ]]
    [ -z "$(ls -A "$foreign")" ]
}

@test "B5-mk a regular file where a dir is created is named and kept" {
    mkdir -p "$project/.opencode"; echo mine > "$project/.opencode/commands"
    run install_prp
    assert_ledger "$project/.opencode/commands"
    [[ "$output" == *"$project/.opencode/commands: regular file — OpenCode not installed"* ]]
    [ "$(cat "$project/.opencode/commands")" = mine ]
}

@test "B5-pl a regular file at a place target is replaced (exit 0)" {
    echo mine > "$project/AGENTS.md"
    run install_prp
    [ "$status" -eq 0 ]
    [ -L "$project/AGENTS.md" ]
}

@test "B6-mk a link to a regular file where a dir is created is named and kept" {
    echo mine > "$BATS_TEST_TMPDIR/file"; mkdir -p "$project/.claude"; ln -s "$BATS_TEST_TMPDIR/file" "$project/.claude/skills"
    run install_prp
    assert_ledger "$project/.claude/skills"
    [[ "$output" == *"$project/.claude/skills: symlink to file → $BATS_TEST_TMPDIR/file"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/file")" = mine ]
}

@test "B7-pl an unremovable directory: rm stderr in the ledger, never a Symlinked line, never nested" {
    [ "$(id -u)" -ne 0 ] || skip "root can remove read-only directories"
    mkdir -p "$project/.opencode/commands/prp/ro"
    echo x > "$project/.opencode/commands/prp/ro/f"; chmod 555 "$project/.opencode/commands/prp/ro"
    run install_prp
    assert_ledger "$project/.opencode/commands/prp"
    [[ "$output" == *"$project/.opencode/commands/prp: still present (directory): rm: "*"Permission denied"* ]]
    [[ "$output" != *'Symlinked: OpenCode'* ]] && [[ "$output" != *'Copied: OpenCode'* ]]
    [ ! -L "$project/.opencode/commands/prp" ] && [ ! -e "$project/.opencode/commands/prp/prp" ]
    [ -f "$project/.opencode/commands/prp/ro/f" ]
}

@test "B8-mk a failing mkdir lands in the ledger with its stderr" {
    stub_failing mkdir /.gemini/commands
    run install_prp
    assert_ledger "$project/.gemini/commands"
    [[ "$output" == *"$project/.gemini/commands: absent (mkdir: boom"* ]]
}

@test "B8-pl a failing ln and cp never prints a success line and exits 1" {
    stub_failing ln /.gemini/commands/prp; stub_failing cp /.gemini/commands/prp
    run install_prp
    assert_ledger "$project/.gemini/commands/prp"
    [[ "$output" == *'Symlink failed for Gemini, copying instead (ln: boom'* ]]
    [[ "$output" != *'✅ Copied: Gemini'* ]] && [[ "$output" != *'✅ Symlinked: Gemini'* ]]
}

# ---- LINT1: no raw mkdir/rm/ln/cp/mv outside the helpers ---------------------

# LINT1: prints every raw mkdir/rm/ln/cp/mv outside the helper bodies without "# fs-ok: <reason>".
# It matches the COMMAND, not the path, so aliases (d=$PROJECT_DIR/x; rm "$d") are caught.
lint_raw_writes() {
    awk '
        /^(_ensure_dir|_remove_path|_place)\(\) \{$/ { skip = 1; next }
        skip && /^\}$/ { skip = 0; next }
        skip || /^[[:space:]]*#/ || /# fs-ok: [^ ]/ { next }
        $0 ~ /(^|[;&|({!`=]|[$][(]|(^|[[:space:]])(then|do|else|if|while|until|command|exec|env|xargs|sudo|time|nice)[[:space:]]+)[[:space:]]*\\?(\/(usr\/)?bin\/)?(mkdir|rm|ln|cp|mv|install|ditto|rsync)([[:space:]]|[(]|$)/ { print NR ": " $0 }
    ' "$1"
}

@test "LINT1 install.sh has no raw project write outside the helpers" {
    run lint_raw_writes "$framework/scripts/install.sh"
    [ -z "$output" ]
}

@test "LINT1 the lint catches aliases and every command spelling, and honours fs-ok" {
    local f="$BATS_TEST_TMPDIR/fixture.sh" bad
    for bad in 'd="$PROJECT_DIR/x"; mkdir -p "$d"' '    rm -rf "$alias"' 'command rm -rf "$d"' '/bin/mv a b' \
               'ls | xargs rm' 'x=$(cp -r a b)' 'if ln -s a b; then' '[ -e x ] && rm -f x' 'mkdir() { :; }' 'cmd=rm'; do
        printf '%s\n' "$bad" > "$f"
        run lint_raw_writes "$f"
        [ -n "$output" ] || { echo "not caught: $bad" >&2; return 1; }
    done
    for ok in 'echo "run mkdir -p x"' '# rm -rf x' 'readlink x' 'rm -f "$t" # fs-ok: temp file beside its target' 'printf "%s cp failed\n" x'; do
        printf '%s\n' "$ok" > "$f"
        run lint_raw_writes "$f"
        [ -z "$output" ] || { echo "false positive: $ok" >&2; return 1; }
    done
    printf '_place() {\n    ln -s a b\n}\nfoo\n' > "$f"; run lint_raw_writes "$f"; [ -z "$output" ]
}

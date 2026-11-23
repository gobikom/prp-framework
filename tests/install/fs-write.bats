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
    [ -f "$project/.gitignore" ]
    [[ "$output" == *'Installed preset'* ]]
}

@test "B1-mk absent dirs are created and verified, exit 0" {
    run install_prp
    [ "$status" -eq 0 ]
    [[ "$output" != *'not installed'* ]]
    for d in .claude/agents .claude/skills .claude/hooks .claude-plugin .codex/skills .opencode/commands \
             .gemini/commands .agents/workflows .thclaws/skills scripts .prp-output/prds/drafts \
             .prp-output/plans/completed .prp-output/issues/completed .prp/scripts; do
        [ -d "$project/$d" ] || return 1
        [ ! -L "$project/$d" ] || return 1
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
    [ "$(readlink "$project/.codex/skills")" = "$dead" ]
    [ ! -e "$BATS_TEST_TMPDIR/missing" ]
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
    [[ "$output" != *'Symlinked: OpenCode'* ]]
    [[ "$output" != *'Copied: OpenCode'* ]]
    [ ! -L "$project/.opencode/commands/prp" ]
    [ ! -e "$project/.opencode/commands/prp/prp" ]
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
    [[ "$output" != *'✅ Copied: Gemini'* ]]
    [[ "$output" != *'✅ Symlinked: Gemini'* ]]
}

# ---- B9-B13: content writes (stamps, settings, .gitignore, CLAUDE.md) are inside the invariant ----

install_inject() { bash "$framework/scripts/install.sh" "$project" --minimal "$@"; }

# One ledger line for $1, exit 1, the later steps ran (.gitignore, preset stamp unless $2=nopreset, summary).
assert_content_ledger() {
    [ "$status" -eq 1 ] || return 1
    [ "$(printf '%s\n' "$output" | grep -c 'path(s) not installed:')" -eq 1 ] || return 1
    [[ "$output" == *"path(s) not installed:"*"$1"* ]] || return 1
    [ -f "$project/.gitignore" ] || return 1
    [[ "$output" == *'Installed preset'* ]] || return 1
    if [ "${2:-}" != nopreset ]; then [ "$(cat "$project/.claude/prp-preset")" = minimal ] || return 1; fi
}

@test "B9a a stamp that is a link to an outside regular file is refused; the outside file is byte-unchanged" {
    mkdir -p "$project/.claude" "$BATS_TEST_TMPDIR/outside"
    printf 'keep\n' > "$BATS_TEST_TMPDIR/outside/v"; cp "$BATS_TEST_TMPDIR/outside/v" "$BATS_TEST_TMPDIR/v.orig"
    ln -s "$BATS_TEST_TMPDIR/outside/v" "$project/.claude/prp-version"
    run install_prp
    assert_content_ledger "$project/.claude/prp-version"
    [[ "$output" == *"$project/.claude/prp-version: symlink to file → $BATS_TEST_TMPDIR/outside/v — "* ]]
    cmp "$BATS_TEST_TMPDIR/outside/v" "$BATS_TEST_TMPDIR/v.orig"
    [ -L "$project/.claude/prp-version" ]
}

@test "B9b a dangling stamp link is refused; nothing is created at its target" {
    mkdir -p "$project/.claude" "$BATS_TEST_TMPDIR/outside"
    ln -s "$BATS_TEST_TMPDIR/outside/p" "$project/.claude/prp-preset"
    run install_prp
    assert_content_ledger "$project/.claude/prp-preset" nopreset
    [[ "$output" == *"$project/.claude/prp-preset: dangling symlink → $BATS_TEST_TMPDIR/outside/p — "* ]]
    [ ! -e "$BATS_TEST_TMPDIR/outside/p" ]
    [ -L "$project/.claude/prp-preset" ]
    [ "$(cat "$project/.claude/prp-version")" = "$version" ]
}

@test "B10a invalid settings.local.json: byte-unchanged, one ledger line, every later step still runs" {
    command -v jq >/dev/null || skip "jq not installed"
    mkdir -p "$project/.claude"; printf '{bad' > "$project/.claude/settings.local.json"
    run install_inject
    assert_content_ledger "$project/.claude/settings.local.json"
    [[ "$output" == *'not valid JSON'* ]]
    [ "$(cat "$project/.claude/settings.local.json")" = '{bad' ]
    grep -q 'PRP' "$project/CLAUDE.md"
    [ "$(cat "$project/.claude/prp-version")" = "$version" ]
    [ -z "$(find "$project/.claude" -name '.prp-tmp.*' 2>/dev/null)" ]
}

@test "B10b a dangling settings.local.json link is refused; nothing is created at its target" {
    command -v jq >/dev/null || skip "jq not installed"
    mkdir -p "$project/.claude" "$BATS_TEST_TMPDIR/outside"
    ln -s "$BATS_TEST_TMPDIR/outside/s.json" "$project/.claude/settings.local.json"
    run install_prp
    assert_content_ledger "$project/.claude/settings.local.json"
    [ ! -e "$BATS_TEST_TMPDIR/outside/s.json" ]
    [ -L "$project/.claude/settings.local.json" ]
}

@test "B10c a settings.local.json link to an outside JSON file is refused; the outside file is unchanged" {
    command -v jq >/dev/null || skip "jq not installed"
    mkdir -p "$project/.claude" "$BATS_TEST_TMPDIR/outside"
    printf '{"a":1}\n' > "$BATS_TEST_TMPDIR/outside/s.json"; cp "$BATS_TEST_TMPDIR/outside/s.json" "$BATS_TEST_TMPDIR/s.orig"
    ln -s "$BATS_TEST_TMPDIR/outside/s.json" "$project/.claude/settings.local.json"
    run install_prp
    assert_content_ledger "$project/.claude/settings.local.json"
    cmp "$BATS_TEST_TMPDIR/outside/s.json" "$BATS_TEST_TMPDIR/s.orig"
    [ -L "$project/.claude/settings.local.json" ]
}

@test "B11 a failing CLAUDE.md inject plus an AGENTS.md directory: both named, stamps written, one summary, exit 1" {
    [ "$(id -u)" -ne 0 ] || skip "root can write read-only files"
    printf '# mine\n' > "$project/CLAUDE.md"; chmod 444 "$project/CLAUDE.md"
    mkdir -p "$project/AGENTS.md"
    run install_inject
    assert_content_ledger "$project/CLAUDE.md"
    [[ "$output" == *"path(s) not installed:"*"$project/AGENTS.md"* ]]
    [[ "$output" == *"$project/CLAUDE.md: regular file — PRP section not injected (exit "* ]]
    [ "$(cat "$project/.claude/prp-version")" = "$version" ]
    [ "$(cat "$project/CLAUDE.md")" = '# mine' ]
}

@test "B12 a symlinked .gitignore is ledgered, left unchanged, exit 1" {
    mkdir -p "$BATS_TEST_TMPDIR/outside"; printf 'x\n' > "$BATS_TEST_TMPDIR/outside/gi"
    ln -s "$BATS_TEST_TMPDIR/outside/gi" "$project/.gitignore"
    run install_prp
    [ "$status" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c 'path(s) not installed:')" -eq 1 ]
    [[ "$output" == *"path(s) not installed:"*"$project/.gitignore"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/outside/gi")" = x ]
    [ -L "$project/.gitignore" ]
    [ "$(cat "$project/.claude/prp-preset")" = minimal ]
}

@test "B13 happy path: settings created and merged through _write_file, no temp left, mode kept, exit 0" {
    command -v jq >/dev/null || skip "jq not installed"
    run install_prp
    [ "$status" -eq 0 ]
    jq -e '.hooks.Stop[0].hooks[0].command == ".claude/hooks/prp-ralph-stop.sh"' "$project/.claude/settings.local.json" >/dev/null
    [ -z "$(find "$project" -name '.prp-tmp.*' 2>/dev/null)" ]
    printf '{"keep":true}\n' > "$project/.claude/settings.local.json"; chmod 640 "$project/.claude/settings.local.json"
    run install_prp
    [ "$status" -eq 0 ]
    jq -e '.keep == true and (.hooks.Stop | length) == 1' "$project/.claude/settings.local.json" >/dev/null
    [ "$(stat -c %a "$project/.claude/settings.local.json")" = 640 ]
    [ -z "$(find "$project" -name '.prp-tmp.*' 2>/dev/null)" ]
}

@test "B15 a .claude symlink to a shared directory is a named opt-in: installs through it, exit 0, no temp left" {
    mkdir -p "$BATS_TEST_TMPDIR/shared"; ln -s "$BATS_TEST_TMPDIR/shared" "$project/.claude"
    run install_prp
    [ "$status" -eq 0 ]
    [ -L "$project/.claude" ]
    [ "$(cat "$BATS_TEST_TMPDIR/shared/prp-preset")" = minimal ]
    [ -z "$(find "$BATS_TEST_TMPDIR/shared" -name '.prp-tmp.*' 2>/dev/null)" ]
}

@test "B16 a failed install says its stamps record an attempt, not a complete install" {
    mkdir -p "$project/AGENTS.md"
    run install_prp
    [ "$status" -eq 1 ]
    [[ "$output" == *'record that this install ran to the end, not that it was complete'* ]]
    [ "$(cat "$project/.claude/prp-version")" = "$version" ]
}

@test "B14 a destructive directory removal never crosses a parent link that leaves the project" {
    mkdir -p "$BATS_TEST_TMPDIR/outside/codex/skills/prp-plan"
    echo keep > "$BATS_TEST_TMPDIR/outside/codex/skills/prp-plan/f"
    ln -s "$BATS_TEST_TMPDIR/outside/codex" "$project/.codex"
    run install_prp
    assert_content_ledger "$project/.codex/skills"
    [ "$(cat "$BATS_TEST_TMPDIR/outside/codex/skills/prp-plan/f")" = keep ]
    [[ "$output" == *"$project/.codex/skills: parent resolves outside the project — Codex skills not installed"* ]]
}

# ---- LINT1: no raw mkdir/rm/ln/cp/mv outside the helpers ---------------------

# LINT1: prints every raw mkdir/rm/ln/cp/mv outside the helper bodies without "# fs-ok: <reason>", and
# every > / >> redirect whose target expands a project path (PROJECT_DIR, *_FILE, the stamp's $2,
# a $t/$dst/$target alias). It matches the COMMAND, not the path, so aliases are caught.
lint_raw_writes() {
    awk '
        /^(_ensure_dir|_remove_path|_place|_write_file)\(\) \{$/ { skip = 1; next }
        skip && /^\}$/ { skip = 0; next }
        skip || /^[[:space:]]*#/ || /# fs-ok: [^ ]/ { next }
        $0 ~ /(^|[;&|({!`=]|[$][(]|(^|[[:space:]])(then|do|else|if|while|until|command|exec|env|xargs|sudo|time|nice)[[:space:]]+)[[:space:]]*\\?(\/(usr\/)?bin\/)?(mkdir|rm|ln|cp|mv|install|ditto|rsync|tee|touch|truncate|dd)([[:space:]]|[(]|$)/ { print NR ": " $0; next }
        $0 ~ />>?[[:space:]]*"?[$][{(]?(PROJECT_DIR|[A-Za-z_]*_FILE|[A-Za-z_]*_PATH|[12]|t|dst|target|[a-z_]*file)([^A-Za-z_]|$)/ && $0 !~ /[0-9]?>&[0-9]/ { print NR ": " $0 }
    ' "$1"
}

@test "LINT1 install.sh has no raw project write outside the helpers" {
    run lint_raw_writes "$framework/scripts/install.sh"
    [ -z "$output" ]
}

@test "LINT1 the lint catches aliases and every command spelling, and honours fs-ok" {
    local f="$BATS_TEST_TMPDIR/fixture.sh" bad
    for bad in 'd="$PROJECT_DIR/x"; mkdir -p "$d"' '    rm -rf "$alias"' 'command rm -rf "$d"' '/bin/mv a b' \
               'echo x > "$PROJECT_DIR/.claude/prp-preset"' 'printf x >> "$GITIGNORE_FILE"' 'jq . > "$SETTINGS_FILE"' 'cat a > "$t"' 'ls | xargs rm' 'x=$(cp -r a b)' 'if ln -s a b; then' '[ -e x ] && rm -f x' 'mkdir() { :; }' 'cmd=rm'; do
        printf '%s\n' "$bad" > "$f"
        run lint_raw_writes "$f"
        [ -n "$output" ] || { echo "not caught: $bad" >&2; return 1; }
    done
    for ok in 'echo "run mkdir -p x"' '# rm -rf x' 'readlink x' 'rm -f "$t" # fs-ok: temp file beside its target' 'printf "%s cp failed\n" x' 'echo hi > /dev/null' 'foo 2>&1' 'x=$(cat "$SETTINGS_FILE")' 'printf x >> "$GITIGNORE_FILE" # fs-ok: append with rollback'; do
        printf '%s\n' "$ok" > "$f"
        run lint_raw_writes "$f"
        [ -z "$output" ] || { echo "false positive: $ok" >&2; return 1; }
    done
    printf '_place() {\n    ln -s a b\n}\nfoo\n' > "$f"; run lint_raw_writes "$f"; [ -z "$output" ]
}

@test "B14b a recursive removal under a parent link that leaves the project is refused by _remove_path itself" {
    mkdir -p "$BATS_TEST_TMPDIR/outside/d/victim"; echo keep > "$BATS_TEST_TMPDIR/outside/d/victim/f"
    ln -s "$BATS_TEST_TMPDIR/outside/d" "$project/linked"
    run bash -c '
        PROJECT_DIR=$1; RED= NC=; _PROJECT_REAL=$1; LEDGER_N=0; LEDGER_PATHS=""
        eval "$(sed -n "/^_path_state()/,/^_place()/p" "$2" | sed "\$d")"
        _remove_path "$PROJECT_DIR/linked/victim" "test step" dir; echo "rc=$?"' _ "$project" "$framework/scripts/install.sh"
    [[ "$output" == *'rc=1'* ]]
    [[ "$output" == *'parent resolves outside the project'* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/outside/d/victim/f")" = keep ]
}

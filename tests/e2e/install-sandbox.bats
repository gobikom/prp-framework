#!/usr/bin/env bats
# E2E tests for install.sh — runs the installer in a real temp sandbox
#
# Strategy: copy the framework into a temp dir so that BASH_SOURCE[0] resolves
# correctly and PROJECT_DIR (parent of FRAMEWORK_DIR) becomes the sandbox root.
#
# FRAMEWORK_DIR = $SANDBOX/prp-framework
# PROJECT_DIR   = $SANDBOX
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/e2e/install-sandbox.bats

REAL_FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    SANDBOX="$(mktemp -d)"
    # Copy framework into sandbox so BASH_SOURCE[0] resolves to sandbox paths
    cp -r "$REAL_FRAMEWORK_DIR" "$SANDBOX/prp-framework"
    INSTALL_SCRIPT="$SANDBOX/prp-framework/scripts/install.sh"
}

teardown() {
    rm -rf "$SANDBOX"
}

# ─────────────────────────────────────────────
# 1. Claude Code adapter installation
# ─────────────────────────────────────────────
# prp-core is a real directory of per-file symlinks, never a directory symlink: a directory
# symlink let writes reach the framework's source files (#110, agent-devops 2026-06-14).
@test "install creates .claude/commands/prp-core/ as a real directory, not a symlink" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -d "$SANDBOX/.claude/commands/prp-core" ]
    [ ! -L "$SANDBOX/.claude/commands/prp-core" ]
    ls "$SANDBOX/.claude/commands/prp-core/"prp-*.md >/dev/null 2>&1
}

@test "install prp-core files symlink to their adapter sources" {
    bash "$INSTALL_SCRIPT"
    for f in "$SANDBOX/.claude/commands/prp-core/"prp-*.md; do
        [ -L "$f" ]
        [ "$(readlink "$f")" = "$SANDBOX/prp-framework/adapters/claude-code/$(basename "$f")" ]
    done
}

@test "install replaces a legacy prp-core directory symlink without touching the source" {
    mkdir -p "$SANDBOX/.claude/commands"
    ln -s "$SANDBOX/prp-framework/adapters/claude-code" "$SANDBOX/.claude/commands/prp-core"
    src="$SANDBOX/prp-framework/adapters/claude-code"
    # Every source file's type, path and content, before and after the install.
    snapshot() { (cd "$src" && find . -printf '%y %p\n' | sort && find . -type f -print0 | sort -z | xargs -0 sha256sum); }
    before="$(snapshot)"
    bash "$INSTALL_SCRIPT"
    [ ! -L "$SANDBOX/.claude/commands/prp-core" ]
    [ -d "$SANDBOX/.claude/commands/prp-core" ]
    ls "$SANDBOX/.claude/commands/prp-core/"prp-*.md >/dev/null
    [ -n "$before" ]
    [ "$(snapshot)" = "$before" ]
}

# prp-mkt and prp-bot are installed only by the full preset (#101); the default is standard.
@test "install --full creates .claude/commands/prp-mkt/ and prp-bot/" {
    bash "$INSTALL_SCRIPT" --full
    [ -L "$SANDBOX/.claude/commands/prp-mkt" ]
    [ "$(readlink "$SANDBOX/.claude/commands/prp-mkt")" = "$SANDBOX/prp-framework/adapters/claude-code-marketing" ]
    [ -L "$SANDBOX/.claude/commands/prp-bot" ]
    [ "$(readlink "$SANDBOX/.claude/commands/prp-bot")" = "$SANDBOX/prp-framework/adapters/claude-code-bot" ]
}

@test "default (standard) install does not create prp-mkt or prp-bot" {
    bash "$INSTALL_SCRIPT"
    [ ! -e "$SANDBOX/.claude/commands/prp-mkt" ]
    [ ! -e "$SANDBOX/.claude/commands/prp-bot" ]
}

# ─────────────────────────────────────────────
# 2. Shared directory installation (per-file)
# ─────────────────────────────────────────────
@test "install creates .claude/agents/ with PRP agent files" {
    bash "$INSTALL_SCRIPT"
    [ -d "$SANDBOX/.claude/agents" ]
    # At least one prp agent file should exist (as symlink or copy)
    ls "$SANDBOX/.claude/agents/"*.md >/dev/null 2>&1
}

@test "install creates .claude/hooks/ with ralph hook" {
    bash "$INSTALL_SCRIPT"
    [ -d "$SANDBOX/.claude/hooks" ]
    [ -e "$SANDBOX/.claude/hooks/prp-ralph-stop.sh" ]
}

@test "install makes prp-ralph-stop.sh executable" {
    bash "$INSTALL_SCRIPT"
    [ -x "$SANDBOX/.claude/hooks/prp-ralph-stop.sh" ]
}

# ─────────────────────────────────────────────
# 3. Artifact directory structure
# ─────────────────────────────────────────────
@test "install creates .prp-output/ directory structure" {
    bash "$INSTALL_SCRIPT"
    [ -d "$SANDBOX/.prp-output" ]
    [ -d "$SANDBOX/.prp-output/prds/drafts" ]
    [ -d "$SANDBOX/.prp-output/plans" ]
    [ -d "$SANDBOX/.prp-output/reports" ]
    [ -d "$SANDBOX/.prp-output/reviews" ]
}

# ─────────────────────────────────────────────
# 4. Idempotency
# ─────────────────────────────────────────────
@test "install idempotent: second run skips already-correct symlinks" {
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already up-to-date"* ]]
}

@test "install preserves custom agent file on re-install" {
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    # Add a custom (non-PRP) agent after first install
    echo "# My Custom Agent" > "$SANDBOX/.claude/agents/my-custom-agent.md"
    # Re-run install
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    # Custom agent must still exist
    [ -f "$SANDBOX/.claude/agents/my-custom-agent.md" ]
}

# ─────────────────────────────────────────────
# 5. .gitignore configuration
# ─────────────────────────────────────────────
@test "install adds PRP rules to .gitignore" {
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    [ -f "$SANDBOX/.gitignore" ]
    grep -q "PRP Framework" "$SANDBOX/.gitignore"
}

# v3 review-scratch rules: per-round prp-review-agents files are ignored (a --l2-comments run
# leaves `git status --porcelain` empty), gate evidence in the same dir stays visible.
v3_status_after_files() {  # creates the files under $SANDBOX/.prp-output/reviews, prints porcelain
    git -C "$SANDBOX" init -q 2>/dev/null
    mkdir -p "$SANDBOX/.prp-output/reviews"
    for f in "$@"; do : > "$SANDBOX/.prp-output/reviews/$f"; done
    git -C "$SANDBOX" status --porcelain --untracked-files=all -- .prp-output/reviews
}

@test "v3: review scratch files leave git status clean on a fresh install" {
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    out=$(v3_status_after_files pr-12-agents-review.md pr-12-agents-review-r2.md pr-context-feat-x.md \
        pr-12-l2-code-reviewer.md pr-12-l2-security-reviewer.md pr-12-reviewed-head pr-12-round \
        pr-12-round-invariants review-metrics.jsonl)
    [ -z "$out" ]
}

@test "v3: gate evidence in reviews/ stays visible (not ignored)" {
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    out=$(v3_status_after_files prod-gate-audit-v1.2.3.md plan-walk-v1.2.3.md pr-12-fix-summary-20261117.md)
    echo "$out" | grep -q 'prod-gate-audit-v1.2.3.md'
    echo "$out" | grep -q 'plan-walk-v1.2.3.md'
    echo "$out" | grep -q 'pr-12-fix-summary-20261117.md'
}

@test "v3: an existing v2 .gitignore gets the v3 block appended once" {
    printf '%s\n' '# PRP Framework - generated adapters' '.claude/' '' \
        '# PRP artifacts — runtime state ignored, everything else trackable for GitHub links' \
        '.prp-output/state/' > "$SANDBOX/.gitignore"
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    [ "$(grep -c '^# PRP review scratch (v3)' "$SANDBOX/.gitignore")" -eq 1 ]
    [ "$(grep -c '^# PRP artifacts' "$SANDBOX/.gitignore")" -eq 1 ]
    out=$(v3_status_after_files pr-7-agents-review.md pr-7-round)
    [ -z "$out" ]
}

@test "v3: an already-tracked review file stays tracked (rules only affect new files)" {
    bash "$INSTALL_SCRIPT" >/dev/null 2>&1
    git -C "$SANDBOX" init -q
    mkdir -p "$SANDBOX/.prp-output/reviews"
    echo a > "$SANDBOX/.prp-output/reviews/pr-3-agents-review.md"
    git -C "$SANDBOX" add -f .prp-output/reviews/pr-3-agents-review.md
    git -C "$SANDBOX" -c user.email=t@t -c user.name=t commit -q -m t
    echo b > "$SANDBOX/.prp-output/reviews/pr-3-agents-review.md"
    git -C "$SANDBOX" status --porcelain -- .prp-output/reviews | grep -q 'pr-3-agents-review.md'
}

# ─────────────────────────────────────────────
# AGENTS.md ownership guard (agent-devops#1337)
# ─────────────────────────────────────────────
@test "install keeps a generated regular AGENTS.md (codex-only agent home, PRP-only CLAUDE.md)" {
    printf '<!-- PRP-FRAMEWORK:BEGIN -->\nprp\n<!-- PRP-FRAMEWORK:END -->\n' > "$SANDBOX/CLAUDE.md"
    printf '<!-- Generated by soul-orchestra generate-agents-md.py — do not edit manually -->\n# AGENTS.md — Identity\n' > "$SANDBOX/AGENTS.md"
    before="$(sha256sum "$SANDBOX/AGENTS.md")"
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -L "$SANDBOX/AGENTS.md" ]
    [ "$(sha256sum "$SANDBOX/AGENTS.md")" = "$before" ]
    [[ "$output" == *"skipped: soul-orchestra agent home"* ]]
}

@test "install still symlinks AGENTS.md when it is a symlink and CLAUDE.md is PRP-only" {
    printf '<!-- PRP-FRAMEWORK:BEGIN -->\nprp\n<!-- PRP-FRAMEWORK:END -->\n' > "$SANDBOX/CLAUDE.md"
    printf '<!-- Generated by soul-orchestra generate-agents-md.py — do not edit manually -->\nshared\n' > "$SANDBOX/elsewhere.md"
    before="$(sha256sum "$SANDBOX/elsewhere.md")"
    ln -s "$SANDBOX/elsewhere.md" "$SANDBOX/AGENTS.md"
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -L "$SANDBOX/AGENTS.md" ]
    [ "$(readlink "$SANDBOX/AGENTS.md")" = "$SANDBOX/prp-framework/adapters/generic/AGENTS.md" ]
    [ "$(sha256sum "$SANDBOX/elsewhere.md")" = "$before" ]
}

@test "install keeps AGENTS.md when CLAUDE.md carries the generate-claude-md marker" {
    printf '<!-- Generated by soul-orchestra generate-claude-md.py — do not edit manually -->\n# identity\n' > "$SANDBOX/CLAUDE.md"
    printf 'hand written agents\n' > "$SANDBOX/AGENTS.md"
    before="$(sha256sum "$SANDBOX/AGENTS.md")"
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -L "$SANDBOX/AGENTS.md" ]
    [ "$(sha256sum "$SANDBOX/AGENTS.md")" = "$before" ]
    [[ "$output" == *"CLAUDE.md marker"* ]]
}

@test "install symlinks AGENTS.md when none exists" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -L "$SANDBOX/AGENTS.md" ]
}

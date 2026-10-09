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
    before=$(ls "$SANDBOX/prp-framework/adapters/claude-code" | wc -l)
    bash "$INSTALL_SCRIPT"
    [ ! -L "$SANDBOX/.claude/commands/prp-core" ]
    [ "$(ls "$SANDBOX/prp-framework/adapters/claude-code" | wc -l)" -eq "$before" ]
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

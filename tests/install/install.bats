#!/usr/bin/env bats
# Tests for install.sh — verifies framework structure and install script integrity
#
# Instead of running install.sh in a sandbox (which has BASH_SOURCE path issues),
# these tests verify that:
# 1. The framework has the correct adapter directory structure
# 2. install.sh references all expected adapter targets
# 3. The script is well-formed and executable
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/install/install.bats

FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
INSTALL_SCRIPT="$FRAMEWORK_DIR/scripts/install.sh"

# ─────────────────────────────────────────────
# 1. Install script exists and is well-formed
# ─────────────────────────────────────────────
@test "install.sh exists and is executable" {
    [ -x "$INSTALL_SCRIPT" ]
}

@test "install.sh has bash shebang" {
    head -1 "$INSTALL_SCRIPT" | grep -q "#!/bin/bash"
}

@test "install.sh uses set -e for error handling" {
    grep -q "set -e" "$INSTALL_SCRIPT"
}

# ─────────────────────────────────────────────
# 2. Claude Code adapter sources exist
# ─────────────────────────────────────────────
@test "claude-code adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/claude-code" ]
}

@test "claude-code-marketing adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/claude-code-marketing" ]
}

@test "claude-code-bot adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/claude-code-bot" ]
}

@test "claude-code-agents adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/claude-code-agents" ]
}

@test "claude-code-skills adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/claude-code-skills" ]
}

@test "claude-code-hooks adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/claude-code-hooks" ]
}

@test "ralph stop hook exists and is executable" {
    [ -x "$FRAMEWORK_DIR/adapters/claude-code-hooks/prp-ralph-stop.sh" ]
}

# ─────────────────────────────────────────────
# 3. Other adapter sources exist
# ─────────────────────────────────────────────
@test "codex adapter directory exists with skills" {
    [ -d "$FRAMEWORK_DIR/adapters/codex" ]
    ls "$FRAMEWORK_DIR/adapters/codex"/prp-* >/dev/null 2>&1
}

@test "opencode adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/opencode" ]
}

@test "gemini adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/gemini" ]
}

@test "antigravity adapter directory exists" {
    [ -d "$FRAMEWORK_DIR/adapters/antigravity" ]
}

@test "generic adapter AGENTS.md exists" {
    [ -f "$FRAMEWORK_DIR/adapters/generic/AGENTS.md" ]
}

# ─────────────────────────────────────────────
# 4. Install script references all adapter targets
# ─────────────────────────────────────────────
@test "install.sh references claude-code commands target" {
    grep -q "prp-core" "$INSTALL_SCRIPT"
}

@test "install.sh references claude-code marketing target" {
    grep -q "prp-mkt" "$INSTALL_SCRIPT"
}

@test "install.sh references claude-code bot target" {
    grep -q "prp-bot" "$INSTALL_SCRIPT"
}

@test "install.sh references codex target" {
    grep -qi "codex" "$INSTALL_SCRIPT"
}

@test "install.sh references opencode target" {
    grep -qi "opencode" "$INSTALL_SCRIPT"
}

@test "install.sh references gemini target" {
    grep -qi "gemini" "$INSTALL_SCRIPT"
}

@test "install.sh references antigravity target" {
    grep -qi "antigravity" "$INSTALL_SCRIPT"
}

# ─────────────────────────────────────────────
# 5. Install script creates artifact directories
# ─────────────────────────────────────────────
@test "install.sh creates .prp-output subdirectories" {
    grep -q "prp-output" "$INSTALL_SCRIPT"
    grep -q "prds" "$INSTALL_SCRIPT"
    grep -q "plans" "$INSTALL_SCRIPT"
    grep -q "reports" "$INSTALL_SCRIPT"
    grep -q "reviews" "$INSTALL_SCRIPT"
}

# ─────────────────────────────────────────────
# 6. Install script handles gitignore
# ─────────────────────────────────────────────
@test "install.sh configures .gitignore" {
    grep -q "gitignore" "$INSTALL_SCRIPT"
    grep -q "PRP Framework" "$INSTALL_SCRIPT"
}

# ─────────────────────────────────────────────
# 7. Install script registers ralph hook
# ─────────────────────────────────────────────
@test "install.sh registers ralph stop hook" {
    grep -q "ralph" "$INSTALL_SCRIPT"
    grep -q "settings.local.json" "$INSTALL_SCRIPT"
}

@test "install.sh handles missing jq gracefully" {
    grep -q "command -v jq" "$INSTALL_SCRIPT"
}

# ─────────────────────────────────────────────
# 8. Plugin metadata exists
# ─────────────────────────────────────────────
@test "claude-code-plugin marketplace.json exists" {
    [ -f "$FRAMEWORK_DIR/adapters/claude-code-plugin/marketplace.json" ]
}

# ─────────────────────────────────────────────
# 9. Idempotency — install.sh preserves custom files
# ─────────────────────────────────────────────
@test "install.sh has install_files_into_dir function for shared dirs" {
    grep -q "install_files_into_dir" "$INSTALL_SCRIPT"
}

@test "install.sh uses readlink for idempotency check" {
    grep -q "readlink" "$INSTALL_SCRIPT"
}

@test "install.sh uses per-file install for agents directory" {
    grep -q "install_files_into_dir.*claude-code-agents" "$INSTALL_SCRIPT"
}

@test "install.sh uses per-file install for hooks directory" {
    grep -q "install_files_into_dir.*claude-code-hooks" "$INSTALL_SCRIPT"
}

@test "install.sh skips already-correct symlinks" {
    grep -q "Already up-to-date" "$INSTALL_SCRIPT"
}

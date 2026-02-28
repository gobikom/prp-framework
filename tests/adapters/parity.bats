#!/usr/bin/env bats
# Tests for cross-adapter command parity
#
# Verifies all adapters have the required core commands and features.
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/adapters/parity.bats

FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

# ─────────────────────────────────────────────
# 1. Core command existence per adapter
# ─────────────────────────────────────────────
@test "claude-code has all 9 core commands" {
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-prd.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-design.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-plan.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-implement.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-commit.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-pr.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-review.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-review-fix.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-run-all.md" ]
}

@test "codex has all 9 core skills" {
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-prd" ]
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-design" ]
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-plan" ]
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-implement" ]
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-commit" ]
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-pr" ]
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-review" ]
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-review-fix" ]
    [ -d "$FRAMEWORK_DIR/adapters/codex/prp-run-all" ]
}

@test "opencode has all 9 core commands" {
    [ -f "$FRAMEWORK_DIR/adapters/opencode/prd.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/opencode/design.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/opencode/plan.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/opencode/implement.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/opencode/commit.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/opencode/pr.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/opencode/review.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/opencode/review-fix.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/opencode/run-all.md" ]
}

@test "gemini has all 9 core commands" {
    [ -f "$FRAMEWORK_DIR/adapters/gemini/prd.toml" ]
    [ -f "$FRAMEWORK_DIR/adapters/gemini/design.toml" ]
    [ -f "$FRAMEWORK_DIR/adapters/gemini/plan.toml" ]
    [ -f "$FRAMEWORK_DIR/adapters/gemini/implement.toml" ]
    [ -f "$FRAMEWORK_DIR/adapters/gemini/commit.toml" ]
    [ -f "$FRAMEWORK_DIR/adapters/gemini/pr.toml" ]
    [ -f "$FRAMEWORK_DIR/adapters/gemini/review.toml" ]
    [ -f "$FRAMEWORK_DIR/adapters/gemini/review-fix.toml" ]
    [ -f "$FRAMEWORK_DIR/adapters/gemini/run-all.toml" ]
}

@test "antigravity has all 9 core commands" {
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-prd.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-design.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-plan.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-implement.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-commit.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-pr.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-review.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-review-fix.md" ]
    [ -f "$FRAMEWORK_DIR/adapters/antigravity/prp-run-all.md" ]
}

@test "generic AGENTS.md exists" {
    [ -f "$FRAMEWORK_DIR/adapters/generic/AGENTS.md" ]
}

# ─────────────────────────────────────────────
# 2. Generic base (prompts/) has all 9 files
# ─────────────────────────────────────────────
@test "prompts/ base has all 9 core files" {
    [ -f "$FRAMEWORK_DIR/prompts/prd.md" ]
    [ -f "$FRAMEWORK_DIR/prompts/design.md" ]
    [ -f "$FRAMEWORK_DIR/prompts/plan.md" ]
    [ -f "$FRAMEWORK_DIR/prompts/implement.md" ]
    [ -f "$FRAMEWORK_DIR/prompts/commit.md" ]
    [ -f "$FRAMEWORK_DIR/prompts/pr.md" ]
    [ -f "$FRAMEWORK_DIR/prompts/review.md" ]
    [ -f "$FRAMEWORK_DIR/prompts/review-fix.md" ]
    [ -f "$FRAMEWORK_DIR/prompts/run-all.md" ]
}

# ─────────────────────────────────────────────
# 3. Feature parity checks (coverage)
# ─────────────────────────────────────────────
@test "all implement files mention coverage" {
    grep -qi "coverage" "$FRAMEWORK_DIR/adapters/claude-code/prp-implement.md"
    grep -qi "coverage" "$FRAMEWORK_DIR/adapters/codex/prp-implement/SKILL.md"
    grep -qi "coverage" "$FRAMEWORK_DIR/adapters/opencode/implement.md"
    grep -qi "coverage" "$FRAMEWORK_DIR/adapters/gemini/implement.toml"
    grep -qi "coverage" "$FRAMEWORK_DIR/adapters/antigravity/prp-implement.md"
    grep -qi "coverage" "$FRAMEWORK_DIR/prompts/implement.md"
}

@test "all run-all files mention --resume" {
    grep -q "\-\-resume" "$FRAMEWORK_DIR/adapters/claude-code/prp-run-all.md"
    grep -q "\-\-resume" "$FRAMEWORK_DIR/adapters/codex/prp-run-all/SKILL.md"
    grep -q "\-\-resume" "$FRAMEWORK_DIR/adapters/opencode/run-all.md"
    grep -q "\-\-resume" "$FRAMEWORK_DIR/adapters/gemini/run-all.toml"
    grep -q "\-\-resume" "$FRAMEWORK_DIR/adapters/antigravity/prp-run-all.md"
    grep -q "\-\-resume" "$FRAMEWORK_DIR/prompts/run-all.md"
}

@test "all run-all files mention --fix-severity" {
    grep -q "\-\-fix-severity" "$FRAMEWORK_DIR/adapters/claude-code/prp-run-all.md"
    grep -q "\-\-fix-severity" "$FRAMEWORK_DIR/adapters/codex/prp-run-all/SKILL.md"
    grep -q "\-\-fix-severity" "$FRAMEWORK_DIR/adapters/opencode/run-all.md"
    grep -q "\-\-fix-severity" "$FRAMEWORK_DIR/adapters/gemini/run-all.toml"
    grep -q "\-\-fix-severity" "$FRAMEWORK_DIR/adapters/antigravity/prp-run-all.md"
    grep -q "\-\-fix-severity" "$FRAMEWORK_DIR/prompts/run-all.md"
}

@test "all run-all files mention state management" {
    grep -qi "state" "$FRAMEWORK_DIR/adapters/claude-code/prp-run-all.md"
    grep -qi "state" "$FRAMEWORK_DIR/adapters/codex/prp-run-all/SKILL.md"
    grep -qi "state" "$FRAMEWORK_DIR/adapters/opencode/run-all.md"
    grep -qi "state" "$FRAMEWORK_DIR/adapters/gemini/run-all.toml"
    grep -qi "state" "$FRAMEWORK_DIR/adapters/antigravity/prp-run-all.md"
    grep -qi "state" "$FRAMEWORK_DIR/prompts/run-all.md"
}

@test "all implement files mention pr-context" {
    grep -qi "pr-context\|review.context\|review context" "$FRAMEWORK_DIR/adapters/claude-code/prp-implement.md"
    grep -qi "pr-context\|review.context\|review context" "$FRAMEWORK_DIR/adapters/codex/prp-implement/SKILL.md"
    grep -qi "pr-context\|review.context\|review context" "$FRAMEWORK_DIR/adapters/opencode/implement.md"
    grep -qi "pr-context\|review.context\|review context" "$FRAMEWORK_DIR/adapters/gemini/implement.toml"
    grep -qi "pr-context\|review.context\|review context" "$FRAMEWORK_DIR/adapters/antigravity/prp-implement.md"
    grep -qi "pr-context\|review.context\|review context" "$FRAMEWORK_DIR/prompts/implement.md"
}

# ─────────────────────────────────────────────
# 4. Quality enhancement parity
# ─────────────────────────────────────────────
@test "all plan files mention Technical Design" {
    grep -qi "Technical Design" "$FRAMEWORK_DIR/adapters/claude-code/prp-plan.md"
    grep -qi "Technical Design" "$FRAMEWORK_DIR/adapters/codex/prp-plan/SKILL.md"
    grep -qi "Technical Design" "$FRAMEWORK_DIR/adapters/opencode/plan.md"
    grep -qi "Technical Design" "$FRAMEWORK_DIR/adapters/gemini/plan.toml"
    grep -qi "Technical Design" "$FRAMEWORK_DIR/adapters/antigravity/prp-plan.md"
    grep -qi "Technical Design" "$FRAMEWORK_DIR/prompts/plan.md"
}

@test "all implement files mention TDD" {
    grep -qi "TDD\|test first\|Write Test First\|RED.*GREEN" "$FRAMEWORK_DIR/adapters/claude-code/prp-implement.md"
    grep -qi "TDD\|test first\|Write Test First\|RED.*GREEN" "$FRAMEWORK_DIR/adapters/codex/prp-implement/SKILL.md"
    grep -qi "TDD\|test first\|Write test first\|RED.*GREEN" "$FRAMEWORK_DIR/adapters/opencode/implement.md"
    grep -qi "TDD\|test first\|Write test first\|RED.*GREEN" "$FRAMEWORK_DIR/adapters/gemini/implement.toml"
    grep -qi "TDD\|test first\|Write test first\|RED.*GREEN" "$FRAMEWORK_DIR/adapters/antigravity/prp-implement.md"
    grep -qi "TDD\|test first\|Write Test First\|RED.*GREEN" "$FRAMEWORK_DIR/prompts/implement.md"
}

@test "all implement files mention security checks" {
    grep -qi "security check\|SAST\|hardcoded secret" "$FRAMEWORK_DIR/adapters/claude-code/prp-implement.md"
    grep -qi "security check\|SAST\|hardcoded secret" "$FRAMEWORK_DIR/adapters/codex/prp-implement/SKILL.md"
    grep -qi "security check\|SAST\|hardcoded secret" "$FRAMEWORK_DIR/adapters/opencode/implement.md"
    grep -qi "security check\|SAST\|hardcoded secret" "$FRAMEWORK_DIR/adapters/gemini/implement.toml"
    grep -qi "security check\|SAST\|hardcoded secret" "$FRAMEWORK_DIR/adapters/antigravity/prp-implement.md"
    grep -qi "security check\|SAST\|hardcoded secret" "$FRAMEWORK_DIR/prompts/implement.md"
}

@test "all prd files mention Backward Compatibility" {
    grep -qi "Backward Compatibility" "$FRAMEWORK_DIR/adapters/claude-code/prp-prd.md"
    grep -qi "Backward Compatibility" "$FRAMEWORK_DIR/adapters/codex/prp-prd/SKILL.md"
    grep -qi "Backward Compatibility" "$FRAMEWORK_DIR/adapters/opencode/prd.md"
    grep -qi "Backward Compatibility" "$FRAMEWORK_DIR/adapters/gemini/prd.toml"
    grep -qi "Backward Compatibility" "$FRAMEWORK_DIR/adapters/antigravity/prp-prd.md"
    grep -qi "Backward Compatibility" "$FRAMEWORK_DIR/prompts/prd.md"
}

@test "all commit files mention pre-commit check" {
    grep -qi "pre-commit\|PRE-COMMIT\|Phase 0\|quality check" "$FRAMEWORK_DIR/adapters/claude-code/prp-commit.md"
    grep -qi "pre-commit\|PRE-COMMIT\|Phase 0\|quality check" "$FRAMEWORK_DIR/adapters/codex/prp-commit/SKILL.md"
    grep -qi "pre-commit\|PRE-COMMIT\|Phase 0\|quality check" "$FRAMEWORK_DIR/adapters/opencode/commit.md"
    grep -qi "pre-commit\|PRE-COMMIT\|Phase 0\|quality check" "$FRAMEWORK_DIR/adapters/gemini/commit.toml"
    grep -qi "pre-commit\|PRE-COMMIT\|Phase 0\|quality check" "$FRAMEWORK_DIR/adapters/antigravity/prp-commit.md"
    grep -qi "pre-commit\|PRE-COMMIT\|Phase 0\|quality check" "$FRAMEWORK_DIR/prompts/commit.md"
}

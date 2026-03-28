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

# ─────────────────────────────────────────────
# 5. --no-interact parity (P1)
# ─────────────────────────────────────────────
@test "all run-all files mention --no-interact" {
    grep -q "\-\-no-interact" "$FRAMEWORK_DIR/adapters/claude-code/prp-run-all.md"
    grep -q "\-\-no-interact" "$FRAMEWORK_DIR/adapters/codex/prp-run-all/SKILL.md"
    grep -q "\-\-no-interact" "$FRAMEWORK_DIR/adapters/opencode/run-all.md"
    grep -q "\-\-no-interact" "$FRAMEWORK_DIR/adapters/gemini/run-all.toml"
    grep -q "\-\-no-interact" "$FRAMEWORK_DIR/adapters/antigravity/prp-run-all.md"
    grep -q "\-\-no-interact" "$FRAMEWORK_DIR/prompts/run-all.md"
}

# ─────────────────────────────────────────────
# 6. review-fix --severity parity (P2)
# ─────────────────────────────────────────────
@test "all review-fix files mention --severity" {
    grep -q "\-\-severity" "$FRAMEWORK_DIR/adapters/claude-code/prp-review-fix.md"
    grep -q "\-\-severity" "$FRAMEWORK_DIR/adapters/codex/prp-review-fix/SKILL.md"
    grep -q "\-\-severity" "$FRAMEWORK_DIR/adapters/opencode/review-fix.md"
    grep -q "\-\-severity" "$FRAMEWORK_DIR/adapters/gemini/review-fix.toml"
    grep -q "\-\-severity" "$FRAMEWORK_DIR/adapters/antigravity/prp-review-fix.md"
    grep -q "\-\-severity" "$FRAMEWORK_DIR/prompts/review-fix.md"
}

# ─────────────────────────────────────────────
# 7. review pr-context parity (P4)
# ─────────────────────────────────────────────
@test "all review files mention pr-context" {
    grep -qi "pr-context\|context.*detect" "$FRAMEWORK_DIR/adapters/claude-code/prp-review.md"
    grep -qi "pr-context\|context.*detect" "$FRAMEWORK_DIR/adapters/codex/prp-review/SKILL.md"
    grep -qi "pr-context\|context.*detect" "$FRAMEWORK_DIR/adapters/opencode/review.md"
    grep -qi "pr-context\|context.*detect" "$FRAMEWORK_DIR/adapters/gemini/review.toml"
    grep -qi "pr-context\|context.*detect" "$FRAMEWORK_DIR/adapters/antigravity/prp-review.md"
    grep -qi "pr-context\|context.*detect" "$FRAMEWORK_DIR/prompts/review.md"
}

# ─────────────────────────────────────────────
# 8. Negative parity — deprecated paths (P5)
# ─────────────────────────────────────────────
@test "no adapter files reference deprecated .ai-workflows/ path" {
    ! grep -rq "\.ai-workflows/" "$FRAMEWORK_DIR/adapters/claude-code/" || false
    ! grep -rq "\.ai-workflows/" "$FRAMEWORK_DIR/adapters/codex/" || false
    ! grep -rq "\.ai-workflows/" "$FRAMEWORK_DIR/adapters/opencode/" || false
    ! grep -rq "\.ai-workflows/" "$FRAMEWORK_DIR/adapters/gemini/" || false
    ! grep -rq "\.ai-workflows/" "$FRAMEWORK_DIR/adapters/antigravity/" || false
}

# ─────────────────────────────────────────────
# 9. Cross-reference integrity parity
# ─────────────────────────────────────────────
@test "all review files use wildcard glob for report discovery" {
    grep -q "\*-report\*" "$FRAMEWORK_DIR/prompts/review.md"
    grep -qi "report\*\|report.*md" "$FRAMEWORK_DIR/adapters/codex/prp-review/SKILL.md"
    grep -qi "report\*\|report.*md" "$FRAMEWORK_DIR/adapters/opencode/review.md"
    grep -qi "report\*\|report.*md" "$FRAMEWORK_DIR/adapters/gemini/review.toml"
    grep -qi "report\*\|report.*md" "$FRAMEWORK_DIR/adapters/antigravity/prp-review.md"
}

@test "all run-all files pass --context to review" {
    grep -qi "context" "$FRAMEWORK_DIR/adapters/codex/prp-run-all/SKILL.md"
    grep -qi "context" "$FRAMEWORK_DIR/adapters/opencode/run-all.md"
    grep -qi "context" "$FRAMEWORK_DIR/adapters/gemini/run-all.toml"
    grep -qi "context" "$FRAMEWORK_DIR/adapters/antigravity/prp-run-all.md"
    grep -qi "context" "$FRAMEWORK_DIR/prompts/run-all.md"
}

# ─────────────────────────────────────────────
# 10. Commit Success Criteria + Edge Cases parity
# ─────────────────────────────────────────────
@test "all commit files have Success Criteria" {
    grep -qi "Success Criteria" "$FRAMEWORK_DIR/adapters/claude-code/prp-commit.md"
    grep -qi "Success Criteria" "$FRAMEWORK_DIR/adapters/codex/prp-commit/SKILL.md"
    grep -qi "Success Criteria" "$FRAMEWORK_DIR/adapters/opencode/commit.md"
    grep -qi "Success Criteria" "$FRAMEWORK_DIR/adapters/gemini/commit.toml"
    grep -qi "Success Criteria" "$FRAMEWORK_DIR/adapters/antigravity/prp-commit.md"
    grep -qi "Success Criteria" "$FRAMEWORK_DIR/prompts/commit.md"
}

@test "all commit files have Edge Cases" {
    grep -qi "Edge Case" "$FRAMEWORK_DIR/adapters/claude-code/prp-commit.md"
    grep -qi "Edge Case" "$FRAMEWORK_DIR/adapters/codex/prp-commit/SKILL.md"
    grep -qi "Edge Case" "$FRAMEWORK_DIR/adapters/opencode/commit.md"
    grep -qi "Edge Case" "$FRAMEWORK_DIR/adapters/gemini/commit.toml"
    grep -qi "Edge Case" "$FRAMEWORK_DIR/adapters/antigravity/prp-commit.md"
    grep -qi "Edge Case" "$FRAMEWORK_DIR/prompts/commit.md"
}

# ─────────────────────────────────────────────
# 11. Flag name consistency parity (GAP 1)
# ─────────────────────────────────────────────
@test "all run-all files use --prp-path not --plan-path" {
    ! grep -q "\-\-plan-path" "$FRAMEWORK_DIR/prompts/run-all.md"
    ! grep -q "\-\-plan-path" "$FRAMEWORK_DIR/adapters/claude-code/prp-run-all.md"
    ! grep -q "\-\-plan-path" "$FRAMEWORK_DIR/adapters/codex/prp-run-all/SKILL.md"
    ! grep -q "\-\-plan-path" "$FRAMEWORK_DIR/adapters/opencode/run-all.md"
    ! grep -q "\-\-plan-path" "$FRAMEWORK_DIR/adapters/gemini/run-all.toml"
    ! grep -q "\-\-plan-path" "$FRAMEWORK_DIR/adapters/antigravity/prp-run-all.md"
}

# ─────────────────────────────────────────────
# 12. TRANSITION marker parity (GAP 4)
# ─────────────────────────────────────────────
@test "all run-all files have transition instructions after commit step" {
    # Each adapter should tell AI to proceed after commit (not stop)
    grep -qi "TRANSITION\|proceed.*Step 5\|immediately proceed\|IGNORE.*suggestion" "$FRAMEWORK_DIR/adapters/claude-code/prp-run-all.md"
    grep -qi "TRANSITION\|proceed.*Step 5\|immediately proceed\|IGNORE.*suggestion" "$FRAMEWORK_DIR/adapters/codex/prp-run-all/SKILL.md"
    grep -qi "TRANSITION\|proceed.*Step 5\|immediately proceed\|IGNORE.*suggestion" "$FRAMEWORK_DIR/adapters/opencode/run-all.md"
    grep -qi "TRANSITION\|proceed.*Step 5\|immediately proceed\|IGNORE.*suggestion" "$FRAMEWORK_DIR/adapters/gemini/run-all.toml"
    grep -qi "TRANSITION\|proceed.*Step 5\|immediately proceed\|IGNORE.*suggestion" "$FRAMEWORK_DIR/adapters/antigravity/prp-run-all.md"
    grep -qi "TRANSITION\|proceed.*Step 5\|immediately proceed" "$FRAMEWORK_DIR/prompts/run-all.md"
}

# ─────────────────────────────────────────────
# 13. v2.1.0 Content Parity — Phase Checkpoints
# ─────────────────────────────────────────────

# Helper: check section exists in all 6 locations (5 adapters + prompts)
check_all_6() {
    local pattern="$1" cmd="$2"
    grep -qi "$pattern" "$FRAMEWORK_DIR/adapters/claude-code/prp-${cmd}.md" || { echo "FAIL: claude-code/prp-${cmd}.md missing '${pattern}'"; return 1; }
    grep -qi "$pattern" "$FRAMEWORK_DIR/adapters/codex/prp-${cmd}/SKILL.md" || { echo "FAIL: codex/prp-${cmd}/SKILL.md missing '${pattern}'"; return 1; }
    grep -qi "$pattern" "$FRAMEWORK_DIR/adapters/opencode/${cmd}.md" || { echo "FAIL: opencode/${cmd}.md missing '${pattern}'"; return 1; }
    grep -qi "$pattern" "$FRAMEWORK_DIR/adapters/gemini/${cmd}.toml" || { echo "FAIL: gemini/${cmd}.toml missing '${pattern}'"; return 1; }
    grep -qi "$pattern" "$FRAMEWORK_DIR/adapters/antigravity/prp-${cmd}.md" || { echo "FAIL: antigravity/prp-${cmd}.md missing '${pattern}'"; return 1; }
    grep -qi "$pattern" "$FRAMEWORK_DIR/prompts/${cmd}.md" || { echo "FAIL: prompts/${cmd}.md missing '${pattern}'"; return 1; }
}

@test "all implement files have phase checkpoints" {
    check_all_6 "CHECKPOINT" "implement"
}

@test "all review-fix files have phase checkpoints" {
    check_all_6 "CHECKPOINT" "review-fix"
}

@test "all pr files have phase checkpoints" {
    check_all_6 "CHECKPOINT" "pr"
}

@test "all commit files have phase checkpoints" {
    check_all_6 "CHECKPOINT" "commit"
}

@test "all cleanup files have phase checkpoints" {
    check_all_6 "CHECKPOINT" "cleanup"
}

@test "all plan files have phase checkpoints" {
    check_all_6 "CHECKPOINT" "plan"
}

# ─────────────────────────────────────────────
# 14. v2.1.0 Content Parity — New Features
# ─────────────────────────────────────────────

@test "all pr files mention implementation report enrichment" {
    check_all_6 "Implementation Report\|implementation report\|REPORT_ENRICHED" "pr"
}

@test "all commit files mention plan-aware context" {
    check_all_6 "Plan-Aware\|plan-aware\|PLAN_CONTEXT\|Phase 1.5" "commit"
}

@test "all cleanup files mention manifest-first discovery" {
    check_all_6 "manifest\|MANIFEST" "cleanup"
}

@test "all cleanup files mention orphaned state cleanup" {
    check_all_6 "state file\|STATE_CLEANED\|prp-run-all.state" "cleanup"
}

@test "all run-all files mention dry-run mode" {
    check_all_6 "dry-run\|DRY_RUN\|dry.run" "run-all"
}

@test "all run-all files mention --since-last-review" {
    check_all_6 "since-last-review\|incremental.*re-verify\|INCREMENTAL_REVIEW" "run-all"
}

@test "all run-all files mention ralph mode" {
    check_all_6 "ralph\|RALPH" "run-all"
}

# ─────────────────────────────────────────────
# 15. v2.1.0 Prompts — Tool-agnostic Placeholders
# ─────────────────────────────────────────────

@test "prompts/ use {ARGS} not \$ARGUMENTS" {
    ! grep -q '\$ARGUMENTS' "$FRAMEWORK_DIR/prompts/review.md"
    ! grep -q '\$ARGUMENTS' "$FRAMEWORK_DIR/prompts/implement.md"
    ! grep -q '\$ARGUMENTS' "$FRAMEWORK_DIR/prompts/review-fix.md"
    ! grep -q '\$ARGUMENTS' "$FRAMEWORK_DIR/prompts/pr.md"
    ! grep -q '\$ARGUMENTS' "$FRAMEWORK_DIR/prompts/commit.md"
    ! grep -q '\$ARGUMENTS' "$FRAMEWORK_DIR/prompts/cleanup.md"
    ! grep -q '\$ARGUMENTS' "$FRAMEWORK_DIR/prompts/run-all.md"
    ! grep -q '\$ARGUMENTS' "$FRAMEWORK_DIR/prompts/plan.md"
}

@test "prompts/ have no tool-specific suffixes" {
    for cmd in review implement review-fix pr commit cleanup run-all plan; do
        ! grep -q '\-codex' "$FRAMEWORK_DIR/prompts/${cmd}.md"
        ! grep -q '\-opencode' "$FRAMEWORK_DIR/prompts/${cmd}.md"
        ! grep -q '\-antigravity' "$FRAMEWORK_DIR/prompts/${cmd}.md"
        ! grep -q '\-gemini' "$FRAMEWORK_DIR/prompts/${cmd}.md"
    done
}

# ─────────────────────────────────────────────
# 16. Claude Code-specific commands exist
# ─────────────────────────────────────────────
@test "claude-code has prp-rollback command" {
    [ -f "$FRAMEWORK_DIR/adapters/claude-code/prp-rollback.md" ]
}

@test "claude-code run-all has --dry-run flag" {
    grep -q "\-\-dry-run" "$FRAMEWORK_DIR/adapters/claude-code/prp-run-all.md"
}

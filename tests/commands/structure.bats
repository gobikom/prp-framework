#!/usr/bin/env bats
# Tests for command file structure — verifies required sections exist
#
# Core commands are markdown prompts interpreted by AI, not executable scripts.
# These tests verify structural correctness: required sections, keywords, patterns.
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/commands/structure.bats

PROMPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/prompts"

# ─────────────────────────────────────────────
# 1. plan.md structure
# ─────────────────────────────────────────────
@test "plan.md contains Phase sections" {
    grep -q "## Phase" "$PROMPTS_DIR/plan.md"
}

@test "plan.md contains Validation Commands section" {
    grep -qi "Validation Commands\|validation.commands" "$PROMPTS_DIR/plan.md"
}

@test "plan.md specifies 90% coverage target" {
    grep -q "90%" "$PROMPTS_DIR/plan.md"
}

@test "plan.md contains acceptance criteria" {
    grep -qi "Acceptance Criteria\|acceptance.criteria" "$PROMPTS_DIR/plan.md"
}

# ─────────────────────────────────────────────
# 2. implement.md structure
# ─────────────────────────────────────────────
@test "implement.md contains Phase 0: DETECT" {
    grep -qi "Phase 0\|DETECT\|Detect.*Environment" "$PROMPTS_DIR/implement.md"
}

@test "implement.md contains Phase 4: VALIDATE" {
    grep -qi "Phase 4\|VALIDATE\|Full Validation" "$PROMPTS_DIR/implement.md"
}

@test "implement.md contains coverage check" {
    grep -qi "coverage" "$PROMPTS_DIR/implement.md"
}

@test "implement.md specifies 90% coverage target" {
    grep -q "90%" "$PROMPTS_DIR/implement.md"
}

@test "implement.md contains pr-context generation" {
    grep -qi "pr-context\|review context\|Review Context" "$PROMPTS_DIR/implement.md"
}

@test "implement.md contains archive step" {
    grep -qi "archive\|completed/" "$PROMPTS_DIR/implement.md"
}

# ─────────────────────────────────────────────
# 3. run-all.md structure
# ─────────────────────────────────────────────
@test "run-all.md contains --resume flag" {
    grep -q "\-\-resume" "$PROMPTS_DIR/run-all.md"
}

@test "run-all.md contains --fix-severity flag" {
    grep -q "\-\-fix-severity" "$PROMPTS_DIR/run-all.md"
}

@test "run-all.md contains state management" {
    grep -qi "state" "$PROMPTS_DIR/run-all.md"
}

@test "run-all.md contains review-fix loop" {
    grep -qi "review.fix\|fix.*severity\|REVIEW_CYCLE\|review cycle" "$PROMPTS_DIR/run-all.md"
}

# ─────────────────────────────────────────────
# 4. review-fix.md structure
# ─────────────────────────────────────────────
@test "review-fix.md contains --severity flag" {
    grep -q "\-\-severity" "$PROMPTS_DIR/review-fix.md"
}

@test "review-fix.md contains severity levels" {
    grep -qi "critical" "$PROMPTS_DIR/review-fix.md"
    grep -qi "high" "$PROMPTS_DIR/review-fix.md"
}

# ─────────────────────────────────────────────
# 5. commit.md structure
# ─────────────────────────────────────────────
@test "commit.md contains conventional commit pattern" {
    grep -qi "feat\|fix\|refactor\|{type}" "$PROMPTS_DIR/commit.md"
}

# ─────────────────────────────────────────────
# 6. pr.md structure
# ─────────────────────────────────────────────
@test "pr.md references GitHub CLI" {
    grep -qi "gh pr\|github\|pull request" "$PROMPTS_DIR/pr.md"
}

# ─────────────────────────────────────────────
# 7. prd.md structure
# ─────────────────────────────────────────────
@test "prd.md contains requirements/foundation section" {
    grep -qi "FOUNDATION\|Requirements\|Problem Statement" "$PROMPTS_DIR/prd.md"
}

# ─────────────────────────────────────────────
# 8. design.md structure
# ─────────────────────────────────────────────
@test "design.md contains architecture section" {
    grep -qi "Architecture\|Technical\|System Design" "$PROMPTS_DIR/design.md"
}

# ─────────────────────────────────────────────
# 9. review.md structure
# ─────────────────────────────────────────────
@test "review.md contains aspect selection" {
    grep -qi "Code Quality\|aspect\|review pass" "$PROMPTS_DIR/review.md"
}

# ─────────────────────────────────────────────
# 10. Quality enhancement tests
# ─────────────────────────────────────────────

# Plan: Technical Design (conditional)
@test "plan.md contains Technical Design section" {
    grep -qi "Technical Design" "$PROMPTS_DIR/plan.md"
}

@test "plan.md contains complexity triggers" {
    grep -qi "COMPLEXITY_TRIGGERS\|complexity.*trigger" "$PROMPTS_DIR/plan.md"
}

@test "plan.md contains integration test specs" {
    grep -qi "Integration Tests\|integration test" "$PROMPTS_DIR/plan.md"
}

# Implement: TDD + validation levels
@test "implement.md contains TDD methodology" {
    grep -qi "TDD\|Write Test First\|RED.*GREEN\|test first" "$PROMPTS_DIR/implement.md"
}

@test "implement.md contains integration tests validation level" {
    grep -qi "Integration Tests" "$PROMPTS_DIR/implement.md"
}

@test "implement.md contains security checks" {
    grep -qi "Security Checks\|SAST\|hardcoded secrets" "$PROMPTS_DIR/implement.md"
}

@test "implement.md contains performance regression check" {
    grep -qi "Performance Regression\|performance.*regression" "$PROMPTS_DIR/implement.md"
}

@test "implement.md contains API contract validation" {
    grep -qi "API Contract\|OpenAPI\|GraphQL.*schema" "$PROMPTS_DIR/implement.md"
}

# PRD: enhanced sections
@test "prd.md contains Deployment & Rollback section" {
    grep -qi "Deployment.*Rollback\|Rollback.*Strategy" "$PROMPTS_DIR/prd.md"
}

@test "prd.md contains Backward Compatibility section" {
    grep -qi "Backward Compatibility" "$PROMPTS_DIR/prd.md"
}

@test "prd.md contains Privacy & Compliance section" {
    grep -qi "Privacy.*Compliance\|GDPR" "$PROMPTS_DIR/prd.md"
}

@test "prd.md contains Risk Analysis section" {
    grep -qi "Risk Analysis" "$PROMPTS_DIR/prd.md"
}

# Commit: pre-commit check
@test "commit.md contains pre-commit quality check" {
    grep -qi "PRE-COMMIT\|pre.commit\|Phase 0" "$PROMPTS_DIR/commit.md"
}

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

# ─────────────────────────────────────────────
# 11. --no-interact flag tests (P1)
# ─────────────────────────────────────────────

@test "run-all.md contains --no-interact flag" {
    grep -q "\-\-no-interact" "$PROMPTS_DIR/run-all.md"
}

@test "plan.md contains --no-interact handling" {
    grep -qi "no-interact" "$PROMPTS_DIR/plan.md"
}

# ─────────────────────────────────────────────
# 12. Expanded design.md structure (P3)
# ─────────────────────────────────────────────

@test "design.md contains Phase sections" {
    grep -q "## Phase" "$PROMPTS_DIR/design.md"
}

@test "design.md contains API Contracts section" {
    grep -qi "API Contracts" "$PROMPTS_DIR/design.md"
}

@test "design.md contains Database Schema section" {
    grep -qi "Database Schema" "$PROMPTS_DIR/design.md"
}

@test "design.md contains Sequence Diagrams section" {
    grep -qi "Sequence Diagram" "$PROMPTS_DIR/design.md"
}

@test "design.md contains Migration Strategy section" {
    grep -qi "Migration Strategy\|Migration" "$PROMPTS_DIR/design.md"
}

@test "design.md contains Success Criteria" {
    grep -qi "Success Criteria" "$PROMPTS_DIR/design.md"
}

# ─────────────────────────────────────────────
# 13. Expanded review.md structure (P3)
# ─────────────────────────────────────────────

@test "review.md contains Review Aspects table" {
    grep -qi "Review Aspects\|Aspect.*Focus" "$PROMPTS_DIR/review.md"
}

@test "review.md contains severity categories" {
    grep -qi "Critical" "$PROMPTS_DIR/review.md"
    grep -qi "Important\|High" "$PROMPTS_DIR/review.md"
}

@test "review.md contains multi-pass review" {
    grep -qi "Pass 1\|multi.pass\|Review Passes" "$PROMPTS_DIR/review.md"
}

@test "review.md contains pr-context detection" {
    grep -qi "pr-context\|context.*detect\|Phase 0.*Context" "$PROMPTS_DIR/review.md"
}

@test "review.md contains Success Criteria" {
    grep -qi "Success Criteria" "$PROMPTS_DIR/review.md"
}

# ─────────────────────────────────────────────
# 14. Expanded pr.md structure (P3)
# ─────────────────────────────────────────────

@test "pr.md contains Phase sections" {
    grep -q "## Phase" "$PROMPTS_DIR/pr.md"
}

@test "pr.md contains PR template check" {
    grep -qi "PULL_REQUEST_TEMPLATE\|PR template\|template" "$PROMPTS_DIR/pr.md"
}

@test "pr.md contains conventional commit prefixes" {
    grep -qi "feat:\|fix:\|refactor:" "$PROMPTS_DIR/pr.md"
}

@test "pr.md contains Success Criteria" {
    grep -qi "Success Criteria" "$PROMPTS_DIR/pr.md"
}

# ─────────────────────────────────────────────
# 15. Expanded review-fix.md structure (P3)
# ─────────────────────────────────────────────

@test "review-fix.md contains severity mapping" {
    grep -qi "Critical\|High\|Medium\|Suggestion" "$PROMPTS_DIR/review-fix.md"
}

@test "review-fix.md contains validation step" {
    grep -qi "VALIDATE\|validation" "$PROMPTS_DIR/review-fix.md"
}

@test "review-fix.md contains edge cases" {
    grep -qi "Edge Case" "$PROMPTS_DIR/review-fix.md"
}

# ─────────────────────────────────────────────
# 16. Negative tests — deprecated patterns (P5)
# ─────────────────────────────────────────────

@test "prompts/ do not reference deprecated .ai-workflows/ path" {
    ! grep -rq "\.ai-workflows/" "$PROMPTS_DIR/"
}

@test "prompts/ do not reference deprecated .claude/PRPs/ path" {
    ! grep -rq "\.claude/PRPs/" "$PROMPTS_DIR/"
}

@test "plan.md does not reference old 80% coverage target" {
    ! grep -q "80%" "$PROMPTS_DIR/plan.md"
}

@test "implement.md does not reference old 80% coverage target" {
    ! grep -q "80%" "$PROMPTS_DIR/implement.md"
}

# ─────────────────────────────────────────────
# 17. Cross-reference integrity (AI-user gaps)
# ─────────────────────────────────────────────

@test "review.md report glob matches tool-suffixed reports" {
    grep -q "\*-report\*" "$PROMPTS_DIR/review.md"
}

@test "run-all.md passes --context to review step" {
    grep -qi "context.*CONTEXT_FILE\|--context" "$PROMPTS_DIR/run-all.md"
}

@test "run-all.md contains edge cases" {
    grep -qi "Edge Case" "$PROMPTS_DIR/run-all.md"
}

# ─────────────────────────────────────────────
# 18. Success Criteria completeness
# ─────────────────────────────────────────────

@test "all 9 core prompts have Success Criteria" {
    grep -qi "Success Criteria" "$PROMPTS_DIR/prd.md"
    grep -qi "Success Criteria" "$PROMPTS_DIR/design.md"
    grep -qi "Success Criteria" "$PROMPTS_DIR/plan.md"
    grep -qi "Success Criteria" "$PROMPTS_DIR/implement.md"
    grep -qi "Success Criteria" "$PROMPTS_DIR/commit.md"
    grep -qi "Success Criteria" "$PROMPTS_DIR/pr.md"
    grep -qi "Success Criteria" "$PROMPTS_DIR/review.md"
    grep -qi "Success Criteria" "$PROMPTS_DIR/review-fix.md"
    grep -qi "Success Criteria" "$PROMPTS_DIR/run-all.md"
}

# ─────────────────────────────────────────────
# 19. Edge Cases completeness
# ─────────────────────────────────────────────

@test "all 9 core prompts have Edge Cases" {
    grep -qi "Edge Case" "$PROMPTS_DIR/prd.md"
    grep -qi "Edge Case" "$PROMPTS_DIR/design.md"
    grep -qi "Edge Case" "$PROMPTS_DIR/plan.md"
    grep -qi "Edge Case\|Handling Failure" "$PROMPTS_DIR/implement.md"
    grep -qi "Edge Case" "$PROMPTS_DIR/commit.md"
    grep -qi "Edge Case" "$PROMPTS_DIR/pr.md"
    grep -qi "Edge Case" "$PROMPTS_DIR/review.md"
    grep -qi "Edge Case" "$PROMPTS_DIR/review-fix.md"
    grep -qi "Edge Case" "$PROMPTS_DIR/run-all.md"
}

# ─────────────────────────────────────────────
# 20. Artifact variable naming consistency
# ─────────────────────────────────────────────

@test "prompts use consistent {name} variable for artifacts" {
    # All output paths should use {name} not {feature} or {kebab-case-name} or {plan-name}
    ! grep -q '{kebab-case-name}' "$PROMPTS_DIR/prd.md"
    ! grep -q '{feature}-design' "$PROMPTS_DIR/design.md"
    ! grep -q '{kebab-case-feature-name}' "$PROMPTS_DIR/plan.md"
    ! grep -q '{plan-name}' "$PROMPTS_DIR/implement.md"
}

# ─────────────────────────────────────────────
# 21. Flag name consistency (GAP 1)
# ─────────────────────────────────────────────

@test "run-all.md uses --prp-path not --plan-path" {
    ! grep -q "\-\-plan-path" "$PROMPTS_DIR/run-all.md"
    grep -q "\-\-prp-path" "$PROMPTS_DIR/run-all.md"
}

# ─────────────────────────────────────────────
# 22. Plan template ↔ implement cross-reference (GAP 2)
# ─────────────────────────────────────────────

@test "plan.md template contains all sections implement.md expects" {
    # implement.md Phase 1.2 expects: Summary, Patterns to Mirror, Files to Change,
    # Step-by-Step Tasks, Validation Commands, Acceptance Criteria
    TEMPLATE=$(sed -n '/^````markdown/,/^````$/p' "$PROMPTS_DIR/plan.md")
    echo "$TEMPLATE" | grep -qi "Summary"
    echo "$TEMPLATE" | grep -qi "Patterns to Mirror"
    echo "$TEMPLATE" | grep -qi "Files to Change"
    echo "$TEMPLATE" | grep -qi "Step-by-Step Tasks"
    echo "$TEMPLATE" | grep -qi "Validation Commands"
    echo "$TEMPLATE" | grep -qi "Acceptance Criteria"
    echo "$TEMPLATE" | grep -qi "Testing Strategy"
}

# ─────────────────────────────────────────────
# 23. Run-all TRANSITION markers (GAP 4)
# ─────────────────────────────────────────────

@test "run-all.md has TRANSITION markers for Steps 3, 4, and 5" {
    # Step 3 → Step 4 (implement → commit)
    grep -qi "TRANSITION.*Step 4\|TRANSITION.*COMMIT" "$PROMPTS_DIR/run-all.md"
    # Step 4 → Step 5 (commit → PR)
    grep -qi "TRANSITION.*Step 5\|TRANSITION.*proceed" "$PROMPTS_DIR/run-all.md"
    # Step 5 → Step 6 (PR → review)
    grep -qi "TRANSITION.*Step 6\|TRANSITION.*proceed" "$PROMPTS_DIR/run-all.md"
}

# ─────────────────────────────────────────────
# 24. State file + lock file documentation (GAP 5)
# ─────────────────────────────────────────────

@test "run-all.md documents state file path" {
    grep -q "prp-run-all.state.md" "$PROMPTS_DIR/run-all.md"
}

@test "run-all.md documents lock file mechanism" {
    grep -qi "lock\|Lock file\|concurrent" "$PROMPTS_DIR/run-all.md"
}

# ─────────────────────────────────────────────
# 25. Review severity mapping (GAP 6)
# ─────────────────────────────────────────────

@test "review-fix.md maps Important to High severity" {
    # review.md uses "Important" as category, review-fix needs to map it
    grep -qi "Important.*High\|High.*Important" "$PROMPTS_DIR/review-fix.md"
}

# ─────────────────────────────────────────────
# 26. Conditional section guards (GAP 7)
# ─────────────────────────────────────────────

@test "plan.md template conditional sections have guards" {
    # All conditional sections should have "conditional" or "include if" or "skip if"
    TEMPLATE=$(sed -n '/^````markdown/,/^````$/p' "$PROMPTS_DIR/plan.md")
    echo "$TEMPLATE" | grep -qi "conditional"
    echo "$TEMPLATE" | grep -qi "Technical Design"
}

@test "run-all.md report artifact uses wildcard glob" {
    # Summary template should use wildcard to match tool-suffixed reports
    grep -q "report\*" "$PROMPTS_DIR/run-all.md"
}

# ─────────────────────────────────────────────
# 17. prp-rollback command structure (P3)
# ─────────────────────────────────────────────
ROLLBACK_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/adapters/claude-code/prp-rollback.md"

@test "prp-rollback.md exists in claude-code adapter" {
    [ -f "$ROLLBACK_FILE" ]
}

@test "prp-rollback.md supports --soft mode" {
    grep -q "\-\-soft" "$ROLLBACK_FILE"
}

@test "prp-rollback.md supports --hard mode" {
    grep -q "\-\-hard" "$ROLLBACK_FILE"
}

@test "prp-rollback.md supports --restore mode" {
    grep -q "\-\-restore" "$ROLLBACK_FILE"
}

@test "prp-rollback.md creates stash backup before --hard reset" {
    grep -qi "stash" "$ROLLBACK_FILE"
}

@test "prp-rollback.md has Success Criteria" {
    grep -qi "Success Criteria" "$ROLLBACK_FILE"
}

@test "prp-rollback.md never deletes branches" {
    grep -qi "Never delete\|do NOT delete\|Only suggest" "$ROLLBACK_FILE"
}

# ─────────────────────────────────────────────
# 27. prp-cleanup command structure
# ─────────────────────────────────────────────
CLEANUP_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/adapters/claude-code/prp-cleanup.md"

@test "prp-cleanup.md exists in claude-code adapter" {
    [ -f "$CLEANUP_FILE" ]
}

@test "prp-cleanup.md supports --all flag" {
    grep -q "\-\-all" "$CLEANUP_FILE"
}

@test "prp-cleanup.md supports --dry-run flag" {
    grep -q "\-\-dry-run" "$CLEANUP_FILE"
}

@test "prp-cleanup.md verifies PR merge status" {
    grep -qi "MERGED\|merge status\|PR.*merged" "$CLEANUP_FILE"
}

@test "prp-cleanup.md deletes local branch" {
    grep -q "git branch -d\|git branch -D" "$CLEANUP_FILE"
}

@test "prp-cleanup.md deletes remote branch" {
    grep -q "git push origin --delete" "$CLEANUP_FILE"
}

@test "prp-cleanup.md protects main/master branches" {
    grep -qi "main\|master.*never\|Protected branch\|exclude.*main" "$CLEANUP_FILE"
}

@test "prp-cleanup.md has Phase sections" {
    grep -q "## Phase" "$CLEANUP_FILE"
}

@test "prp-cleanup.md has Edge Cases" {
    grep -qi "Edge Case" "$CLEANUP_FILE"
}

@test "prp-cleanup.md has Success Criteria" {
    grep -qi "Success Criteria" "$CLEANUP_FILE"
}

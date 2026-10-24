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

@test "plan.md contains Phase 4.1 Design Alternatives" {
    grep -q "Phase 4.1: DESIGN ALTERNATIVES" "$PROMPTS_DIR/plan.md"
}

@test "plan.md lists the Design-first trigger keywords" {
    grep -q "gate, security, policy, parser, validator or scanner" "$PROMPTS_DIR/plan.md"
    grep -q "scripts/\*\*gate\*" "$PROMPTS_DIR/plan.md"
    grep -q '\*validat\*' "$PROMPTS_DIR/plan.md"
}

@test "plan.md states the mechanical tie-break order" {
    grep -q "covers ALL boundary cases" "$PROMPTS_DIR/plan.md"
    grep -q "Smaller estimated changed lines wins" "$PROMPTS_DIR/plan.md"
    grep -q "Fewer files touched wins" "$PROMPTS_DIR/plan.md"
    grep -q "Lowest index wins" "$PROMPTS_DIR/plan.md"
}

@test "plan.md forbids asking the user to pick a design" {
    grep -q "Selection is mechanical — never ask the user to pick a design, in any mode." "$PROMPTS_DIR/plan.md"
}

@test "plan.md defines blocked-design outcome" {
    grep -q "blocked-design" "$PROMPTS_DIR/plan.md"
}

@test "plan.md requires Invariant and Verified by" {
    grep -q "Invariant: <property>" "$PROMPTS_DIR/plan.md"
    grep -q "Verified by: <check>" "$PROMPTS_DIR/plan.md"
}

@test "plan.md documents --no-alternatives skip-with-reason" {
    grep -q -- "--no-alternatives" "$PROMPTS_DIR/plan.md"
    grep -q "Design alternatives: skipped — <reason>" "$PROMPTS_DIR/plan.md"
}

@test "run-all.md handles blocked-design status" {
    grep -q "blocked-design" "$PROMPTS_DIR/run-all.md"
    grep -q "status:escalated" "$PROMPTS_DIR/run-all.md"
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

@test "workflow prompts have Edge Cases" {
    # prd and design are content-generation commands — Edge Cases not applicable
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

@test "plan.md contains all sections implement.md expects" {
    # implement.md Phase 1.2 expects these sections in the plan
    grep -qi "Summary" "$PROMPTS_DIR/plan.md"
    grep -qi "Patterns to Mirror" "$PROMPTS_DIR/plan.md"
    grep -qi "Files to Change" "$PROMPTS_DIR/plan.md"
    grep -qi "Step-by-Step Tasks" "$PROMPTS_DIR/plan.md"
    grep -qi "Validation Commands" "$PROMPTS_DIR/plan.md"
    grep -qi "Acceptance Criteria" "$PROMPTS_DIR/plan.md"
    grep -qi "Testing Strategy" "$PROMPTS_DIR/plan.md"
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
    # The path scripts/prp-run-all-state.sh uses (moved from .claude/ in b197962).
    grep -qF ".prp-output/state/run-all.state.md" "$PROMPTS_DIR/run-all.md"
    grep -qF 'STATE_FILE=".prp-output/state/run-all.state.md"' "$PROMPTS_DIR/../scripts/prp-run-all-state.sh"
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

@test "plan.md conditional sections have guards" {
    # Conditional sections should have "conditional" or "include if" or "skip if"
    grep -qi "conditional" "$PROMPTS_DIR/plan.md"
    grep -qi "Technical Design" "$PROMPTS_DIR/plan.md"
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

@test "plan.md validates --alternatives and --no-alternatives flags" {
    grep -q -- "--alternatives must be 2..3" "$PROMPTS_DIR/plan.md"
    grep -q -- "--no-alternatives requires a reason" "$PROMPTS_DIR/plan.md"
    grep -q -- "--alternatives N" "$PROMPTS_DIR/plan.md"
}

@test "plan.md requires shared invariant across designs" {
    grep -q "restated verbatim" "$PROMPTS_DIR/plan.md"
    grep -q "the SAME invariant" "$PROMPTS_DIR/plan.md"
}

@test "run-all.md escalates blocked-design via body-file" {
    grep -q -- "--body-file" "$PROMPTS_DIR/run-all.md"
    grep -q "STOPPED: blocked-design" "$PROMPTS_DIR/run-all.md"
    grep -q "If ISSUE_NUMBER is empty" "$PROMPTS_DIR/run-all.md"
}

@test "implement.md refuses to implement a blocked-design plan" {
    grep -q "STOPPED: blocked-design" "$PROMPTS_DIR/implement.md"
    grep -q "do not change the status" "$PROMPTS_DIR/implement.md"
    # R6: full-sentence pin — inverting `status: pending` -> STOP must go red
    grep -qF '**If `status: blocked-design` → STOP immediately: report `STOPPED: blocked-design — no design covers all boundary cases`; do not implement' "$PROMPTS_DIR/implement.md"
}

@test "run-all.md blocked-design escalation has a failure branch" {
    grep -q "blocked-design-{RUN_TIMESTAMP}" "$PROMPTS_DIR/run-all.md"
}

@test "run-all.md never mentions the design-alternatives flags" {
    # `! cmd` is errexit-exempt in bats except as the last command, so each
    # assertion is enforced explicitly via `run` + status
    run grep -q -- "--alternatives" "$PROMPTS_DIR/run-all.md"
    [ "$status" -ne 0 ]
    run grep -q -- "--no-alternatives" "$PROMPTS_DIR/run-all.md"
    [ "$status" -ne 0 ]
}

@test "run-all.md Step 2.5 PLAN GATE sits between Step 2 and Step 3 with skip guard (A1/A2)" {
    local gate step2
    gate=$(awk '/^### Step 2\.5: PLAN GATE/{f=1} /^### Step 3: IMPLEMENT/{f=0} f' "$PROMPTS_DIR/run-all.md")
    [ -n "$gate" ]
    # R6: the position is load-bearing — each heading exactly once, 2 < 2.5 < 3
    [ "$(grep -c '^### Step 2: CREATE PLAN' "$PROMPTS_DIR/run-all.md")" -eq 1 ]
    [ "$(grep -c '^### Step 2\.5: PLAN GATE' "$PROMPTS_DIR/run-all.md")" -eq 1 ]
    [ "$(grep -c '^### Step 3: IMPLEMENT' "$PROMPTS_DIR/run-all.md")" -eq 1 ]
    local step2_at gate_at step3_at
    step2_at=$(grep -n '^### Step 2: CREATE PLAN' "$PROMPTS_DIR/run-all.md" | cut -d: -f1)
    gate_at=$(grep -n '^### Step 2\.5: PLAN GATE' "$PROMPTS_DIR/run-all.md" | cut -d: -f1)
    step3_at=$(grep -n '^### Step 3: IMPLEMENT' "$PROMPTS_DIR/run-all.md" | cut -d: -f1)
    [ "$step2_at" -lt "$gate_at" ]
    [ "$gate_at" -lt "$step3_at" ]
    # A2: the gate is skipped on resume past Step 3, not unconditional
    printf '%s\n' "$gate" | grep -q "skip if RESUME_FROM > 3"
    run grep -q "resuming past Step 2" <<< "$gate"
    [ "$status" -ne 0 ]
    # A1: the gate body names every forward entry path and carries the escalation machinery
    printf '%s\n' "$gate" | grep -q -- "--prp-path"
    printf '%s\n' "$gate" | grep -q -- "--skip-plan"
    printf '%s\n' "$gate" | grep -q -- "--resume"
    printf '%s\n' "$gate" | grep -q "Blocked design (Phase 4.1)"
    printf '%s\n' "$gate" | grep -q "status: blocked-design"
    printf '%s\n' "$gate" | grep -q "PLAN_PATH"
    printf '%s\n' "$gate" | grep -q -- "--body-file"
    printf '%s\n' "$gate" | grep -q "status:escalated"
    printf '%s\n' "$gate" | grep -q "STOPPED: blocked-design"
    # semantic, not keyword-only: the STOP directive itself must survive
    printf '%s\n' "$gate" | grep -q "STOP the whole run"
    printf '%s\n' "$gate" | grep -q "do NOT implement"
    printf '%s\n' "$gate" | grep -qF 'If `status: blocked-design`, STOP the whole run — do NOT implement, do NOT ask anything.'
    # A2 leftover: no unconditional-execution claim in the gated section
    run grep -qi 'always executes' <<< "$gate"
    [ "$status" -ne 0 ]
    run grep -q 'ALWAYS run' <<< "$gate"
    [ "$status" -ne 0 ]
    # the gate moved out of Step 2: the skip-window must no longer carry it
    step2=$(awk '/^### Step 2: CREATE PLAN/{f=1} /^### Step 2\.5: PLAN GATE/{f=0} f' "$PROMPTS_DIR/run-all.md")
    run grep -q "Blocked design (Phase 4.1)" <<< "$step2"
    [ "$status" -ne 0 ]
}

@test "run-all.md Step 3 hard-stops on STOPPED before the 3.2 fallback (A3)" {
    # order-scoped: the terminal STOPPED rule must precede the success TRANSITION and the 3.2 heading
    local step3 stopped_at transition_at fallback_at
    step3=$(awk '/^### Step 3: IMPLEMENT/{f=1} /^### Step 4: COMMIT/{f=0} f' "$PROMPTS_DIR/run-all.md")
    printf '%s\n' "$step3" | grep -q "Hard STOP"
    printf '%s\n' "$step3" | grep -q "STOPPED:"
    # semantic, not keyword-only: the 3.2 fallback is forbidden, the outcome is recorded
    printf '%s\n' "$step3" | grep -q "do NOT run the Step 3.2"
    printf '%s\n' "$step3" | grep -q "status: stopped"
    printf '%s\n' "$step3" | grep -q 'no `STOPPED:` line'
    stopped_at=$(printf '%s\n' "$step3" | grep -n "Hard STOP" | head -1 | cut -d: -f1)
    transition_at=$(printf '%s\n' "$step3" | grep -n '^\*\*TRANSITION\*\*' | head -1 | cut -d: -f1)
    fallback_at=$(printf '%s\n' "$step3" | grep -n '^#### 3\.2' | head -1 | cut -d: -f1)
    [ -n "$stopped_at" ] && [ -n "$transition_at" ] && [ -n "$fallback_at" ]
    [ "$stopped_at" -lt "$transition_at" ]
    [ "$stopped_at" -lt "$fallback_at" ]
}

@test "ralph.md 1.4 defines ISSUE_NUMBER and RUN_TIMESTAMP (A4)" {
    local gate
    gate=$(awk '/^### 1\.4 Blocked-Design Gate/{f=1} /^### 1\.5 If PRD/{f=0} f' "$PROMPTS_DIR/ralph.md")
    [ -n "$gate" ]
    printf '%s\n' "$gate" | grep -q "ISSUE_NUMBER"
    printf '%s\n' "$gate" | grep -qF 'RUN_TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)'
    # R6: full-sentence pins — the inverted or gutted §1.4 must go red
    printf '%s\n' "$gate" | grep -qF 'If `status: blocked-design`, STOP immediately — the ralph loop must not start.'
    printf '%s\n' "$gate" | grep -qF 'Escalation failed — blocked-design artifact saved locally, file manually: <path>'
    printf '%s\n' "$gate" | grep -qF '.prp-output/escalations/blocked-design-{RUN_TIMESTAMP}.md'
}

@test "ralph.md has no loop-time plan gate; §1.5 points PRD mode to #206 (R2.2)" {
    # R2.2 scope cut: standalone /prp-ralph x.prd.md phase plans carry no
    # design status, so the §1.4 gate does not apply there (tracked #206)
    run grep -qF '### 3.0 Plan Gate' "$PROMPTS_DIR/ralph.md"
    [ "$status" -ne 0 ]
    local p15
    p15=$(awk '/^### 1\.5 If PRD File/{f=1} /^\*\*PHASE_1_CHECKPOINT/{f=0} f' "$PROMPTS_DIR/ralph.md")
    [ -n "$p15" ]
    printf '%s\n' "$p15" | grep -qF 'does not apply to it'
    printf '%s\n' "$p15" | grep -qF 'prp-framework#206'
}

@test "ralph.md blocked-design gate runs before Phase 2" {
    # section-scoped: the gate lives in Phase 1 input validation, before SETUP
    local p1
    p1=$(awk '/^### 1\.3 Verify File Exists/{f=1} /^## Phase 2: SETUP/{f=0} f' "$PROMPTS_DIR/ralph.md")
    printf '%s\n' "$p1" | grep -q "Blocked-Design Gate"
    printf '%s\n' "$p1" | grep -q "status: blocked-design"
    printf '%s\n' "$p1" | grep -q "STOPPED: blocked-design"
    printf '%s\n' "$p1" | grep -q "before any iteration or archive"
}

# ─────────────────────────────────────────────
# verify-map wiring (#202 PR-C)
# ─────────────────────────────────────────────

@test "verify.md contains the feature-map wiring markers (B4)" {
    grep -q "UNVERIFIED" "$PROMPTS_DIR/verify.md"
    grep -q "criteria_unverified" "$PROMPTS_DIR/verify.md"
    grep -q "map_entries_run" "$PROMPTS_DIR/verify.md"
    grep -q "map_synced" "$PROMPTS_DIR/verify.md"
    grep -q "verified_sha" "$PROMPTS_DIR/verify.md"
    grep -q -- "--init" "$PROMPTS_DIR/verify.md"
    grep -q -- "--sync" "$PROMPTS_DIR/verify.md"
    grep -q "feature-map.yaml" "$PROMPTS_DIR/verify.md"
    grep -qF "never PASS on env-unavailable" "$PROMPTS_DIR/verify.md"
}

@test "verify.md artifact path is unchanged (Invariant 5)" {
    grep -qF '.prp-output/reviews/pr-{NUMBER}-verify.md' "$PROMPTS_DIR/verify.md"
    # verdict enum untouched: no new verdict value invented
    grep -qF 'PASS | FAIL | PARTIAL' "$PROMPTS_DIR/verify.md"
}

@test "verify.md 0.4 refuses diff fallback on an invalid map (B8)" {
    local sect
    sect=$(awk '/^### 0\.4 Load Feature Map/{f=1} /^## Phase 1/{f=0} f' "$PROMPTS_DIR/verify.md")
    [ -n "$sect" ]
    printf '%s\n' "$sect" | grep -q "No diff fallback"
    printf '%s\n' "$sect" | grep -q "every AC is UNVERIFIED"
    printf '%s\n' "$sect" | grep -q "cat-file -e"
}

@test "verify.md maps removed: tombstones to UNVERIFIED + escalate (B6)" {
    grep -q "removed:" "$PROMPTS_DIR/verify.md"
    grep -q "removed_reason" "$PROMPTS_DIR/verify.md"
    grep -q "UNVERIFIED + escalate" "$PROMPTS_DIR/verify.md"
}

@test "verify.md keeps diff evidence for unmapped ACs only (Invariant 7)" {
    grep -q "diff-evidence" "$PROMPTS_DIR/verify.md"
    grep -q "never judged by diff evidence" "$PROMPTS_DIR/verify.md"
}

@test "run-all.md STOP row for criteria_unverified precedes the PARTIAL row (B5)" {
    local f="$PROMPTS_DIR/run-all.md"
    local stop_at passed_at partial_at
    stop_at=$(grep -n 'criteria_unverified > 0' "$f" | head -1 | cut -d: -f1)
    passed_at=$(grep -n '^| VERIFY PASSED | Proceed to Step 8 |' "$f" | head -1 | cut -d: -f1)
    partial_at=$(grep -n 'VERIFY PASSED (with gaps)' "$f" | head -1 | cut -d: -f1)
    [ -n "$stop_at" ] && [ -n "$passed_at" ] && [ -n "$partial_at" ]
    # the STOP row is the FIRST result row — above both the PASS row and the PARTIAL row
    [ "$stop_at" -lt "$passed_at" ]
    [ "$stop_at" -lt "$partial_at" ]
    grep -q "status:escalated" "$f"
}

@test "run-all.md forces verify from the commit at exactly 3 points (B5a/B11)" {
    local f="$PROMPTS_DIR/run-all.md"
    [ "$(grep -cF 'feature map present → verify enforced' "$f")" -eq 3 ]
    # hit 1 lives between the Step 1 and Step 2 headings
    local step1
    step1=$(awk '/^### Step 1: CREATE BRANCH/{f=1} /^### Step 2: CREATE PLAN/{f=0} f' "$f")
    printf '%s\n' "$step1" | grep -qF 'feature map present → verify enforced'
    printf '%s\n' "$step1" | grep -qF 'cat-file -e "HEAD:.prp-verify/feature-map.yaml"'
    # hit 2 lives in the resume section
    local resume
    resume=$(awk '/^## Step 0\.5: INITIALIZE STATE/{f=1} /^## Workflow/{f=0} f' "$f")
    printf '%s\n' "$resume" | grep -qF 'feature map present → verify enforced'
    printf '%s\n' "$resume" | grep -qF 'cat-file -e "HEAD:.prp-verify/feature-map.yaml"'
    printf '%s\n' "$resume" | grep -qF 'RESUME_FROM = 7.5'
    # hit 3 lives in Step 8, which also enforces the same-head verdict
    local step8
    step8=$(awk '/^### Step 8: MERGE/{f=1} /^### Step 8\.5/{f=0} f' "$f")
    printf '%s\n' "$step8" | grep -qF 'feature map present → verify enforced'
    printf '%s\n' "$step8" | grep -q "cat-file -e"
    printf '%s\n' "$step8" | grep -qF 'verified_sha'
    printf '%s\n' "$step8" | grep -qF 'criteria_failed == 0'
    printf '%s\n' "$step8" | grep -qF 'criteria_unverified == 0'
    printf '%s\n' "$step8" | grep -qF 'Never merge'
}

@test "run-all.md detects the map with git, never the filesystem (B11)" {
    local f="$PROMPTS_DIR/run-all.md"
    run grep -qF '[ -f .prp-verify/feature-map.yaml' "$f"
    [ "$status" -ne 0 ]
    run grep -qF 'test -f .prp-verify/feature-map.yaml' "$f"
    [ "$status" -ne 0 ]
    # the fail-closed clause is present: a git error is never "map absent"
    grep -qF 'A git error is never read as' "$f"
}

@test "run-all.md 7.5 skip condition is unchanged (B5a)" {
    grep -qF 'skip if not AUTO_MERGE or VERIFY != true or REVIEW_VERDICT != "0_issues"' "$PROMPTS_DIR/run-all.md"
    grep -qF '(automatic when the PR head has .prp-verify/feature-map.yaml' "$PROMPTS_DIR/run-all.md"
}

@test "verify.md 0.4 resolves the PR head and discriminates exit codes (r1 fix)" {
    local sect
    sect=$(awk '/^### 0\.4 Load Feature Map/{f=1} /^## Phase 1/{f=0} f' "$PROMPTS_DIR/verify.md")
    printf '%s\n' "$sect" | grep -qF 'headRefOid'
    printf '%s\n' "$sect" | grep -qF 'pull/{NUMBER}/head'
    printf '%s\n' "$sect" | grep -qF 'invalid object name'
    printf '%s\n' "$sect" | grep -qF '2>&1 >/dev/null'
    # the fail-open one-liner must be gone from verify.md entirely
    run grep -qF '&& echo MAP_PRESENT' "$PROMPTS_DIR/verify.md"
    [ "$status" -ne 0 ]
}

@test "verify.md maps the sync tombstone outcome and exit-2 catch-all (r1 fix)" {
    grep -qF 'all paths deleted at HEAD -> tombstone' "$PROMPTS_DIR/verify.md"
    grep -qF 'removed_reason' "$PROMPTS_DIR/verify.md"
    grep -qF '`2` = entry id not found' "$PROMPTS_DIR/verify.md"
    grep -qF 'any other exit' "$PROMPTS_DIR/verify.md"
}

@test "verify.md requires the checkout at the PR head before map mechanics (r1 fix)" {
    grep -qF 'git rev-parse HEAD' "$PROMPTS_DIR/verify.md"
    grep -qF 'synced_sha' "$PROMPTS_DIR/verify.md"
}

@test "run-all.md Step 8 classifies MAP_AT stderr and requires map_entries_run (r1 fix)" {
    grep -qF 'MAP_AT_ERR' "$PROMPTS_DIR/run-all.md"
    grep -qF '2>&1 >/dev/null' "$PROMPTS_DIR/run-all.md"
    grep -qF 'invalid object name' "$PROMPTS_DIR/run-all.md"
    grep -qF 'map_entries_run > 0' "$PROMPTS_DIR/run-all.md"
}

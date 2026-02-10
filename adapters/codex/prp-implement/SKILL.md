---
name: prp-implement
description: Execute an implementation plan with rigorous validation loops — typecheck, lint, test, and build after every change. Autonomous execution with automatic failure recovery.
metadata:
  short-description: Execute implementation plan
---

# PRP Implement — Execute Implementation Plan

## Input

Path to plan file: `$ARGUMENTS`

## Mission

Execute the plan end-to-end with rigorous self-validation. You are autonomous.

- Run checks after every change
- Fix issues immediately — never accumulate broken state
- If validation fails, fix it before moving on

## Phase 0: Detect Project Environment

### 0.1 Identify Package Manager

| File Found | Package Manager | Runner |
|------------|-----------------|--------|
| `bun.lockb` | bun | `bun` / `bun run` |
| `pnpm-lock.yaml` | pnpm | `pnpm` / `pnpm run` |
| `yarn.lock` | yarn | `yarn` / `yarn run` |
| `package-lock.json` | npm | `npm run` |
| `pyproject.toml` | uv/pip | `uv run` / `python` |
| `Cargo.toml` | cargo | `cargo` |
| `go.mod` | go | `go` |

### 0.2 Identify Validation Scripts

Check config for: type-check, lint, lint:fix, test, build. Use the plan's "Validation Commands" section.

## Phase 1: Load Plan

Read plan file. Extract: Summary, Patterns to Mirror, Files to Change, Step-by-Step Tasks, Validation Commands, Acceptance Criteria. If not found: STOP with error.

## Phase 2: Prepare Git State

```bash
git branch --show-current
git status --porcelain
git worktree list
```

| Current State | Action |
|---------------|--------|
| In worktree | Use it (log: "Using worktree") |
| On main, clean | Create branch: `git checkout -b feature/{plan-slug}` |
| On main, dirty | STOP: "Stash or commit changes first" |
| On feature branch | Use it (log: "Using existing branch") |

Sync: `git fetch origin && git pull --rebase origin main 2>/dev/null || true`

## Phase 3: Execute Tasks

For each task in the plan:

1. **Read Context**: Read MIRROR file reference, understand pattern, read IMPORTS
2. **Implement**: Make change exactly as specified, follow MIRROR pattern, handle GOTCHA warnings
3. **Validate Immediately**: Run type-check after EVERY file change. If fails → read error → fix → re-run → only proceed when passing
4. **Track Progress**: Log each task completion. If deviating, document WHAT and WHY.

## Phase 4: Full Validation

### 4.1 Static Analysis
Type-check + lint from plan's Validation Commands. Must pass with zero errors.
If lint errors: run lint fix → re-check → manual fix remaining.

### 4.2 Unit Tests
**You MUST write/update tests for new code.** Every new function needs at least one test.
Run tests from plan. If fail: determine implementation or test bug → fix root cause → re-run until green.

### 4.3 Build Check
Run build from plan. Must complete without errors.

### 4.4 Integration Testing (if applicable)
If API/server changes, run integration tests from plan:
```bash
{runner} run dev &
SERVER_PID=$!
sleep 3
curl -s http://localhost:{port}/health | jq
kill $SERVER_PID
```

### 4.5 Edge Case Testing
Run any edge case tests specified in the plan.

## Phase 5: Report

### 5.1 Generate Report
Save to `.claude/PRPs/reports/{plan-name}-report-codex.md` with:

> **Note**: Uses `-codex` suffix to identify Codex implementation reports and prevent overwriting reports from other tools (each tool uses its own suffix for parallel implementation capability).
- Plan reference, branch, date, status (COMPLETE | PARTIAL)
- Assessment vs Reality (predicted vs actual complexity/confidence)
- Tasks completed table
- Validation results table (type-check, lint, tests, build, integration)
- Files changed table (file, action, lines)
- Deviations from plan (with rationale)
- Issues encountered (with resolutions)
- Tests written table

### 5.2 Generate Review Context (for run-all workflow)
Save to `.claude/PRPs/reviews/pr-context-{BRANCH}.md` with:
- Branch name, files changed, implementation summary
- Validation status, key changes for review, focus areas
- This saves ~60K tokens when running via run-all workflow

### 5.3 Update Source PRD (if applicable)
If plan was from PRD: read PRD → find phase → change status from `in-progress` to `complete` → save.

### 5.4 Archive Plan
```bash
mkdir -p .ai-workflows/plans/completed
mv $ARGUMENTS .ai-workflows/plans/completed/
```

## Phase 6: Output

Report to user: status, validation summary table, files changed count, deviations summary, artifacts created (including review context).

If from PRD: show PRD progress (updated phases table), next phase, parallel opportunity.

Next steps: review, create PR, merge.

## Failure Handling

| Failure | Action |
|---------|--------|
| Type check fails | Read error → fix → re-run → don't proceed until passing |
| Tests fail | Identify which → determine implementation or test bug → fix root cause → re-run |
| Lint fails | Run lint fix → manually fix remaining → re-run |
| Build fails | Check error output → fix → re-run |
| Integration fails | Check server started → verify endpoint → fix → retry |

## Success Criteria

- TASKS_COMPLETE: All plan tasks executed
- TYPES_PASS: Type-check exits 0
- LINT_PASS: Lint exits 0
- TESTS_PASS: All tests green
- BUILD_PASS: Build succeeds
- REPORT_CREATED: Implementation report exists at `.claude/PRPs/reports/`
- PR_CONTEXT_CREATED: Review context exists at `.claude/PRPs/reviews/pr-context-{BRANCH}.md`
- PLAN_ARCHIVED: Original plan moved to completed

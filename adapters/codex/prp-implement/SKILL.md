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

> **Plan-provided commands take precedence**: If the plan contains a Metadata table with Runner/Type Check/Lint/Test/Build commands, use those directly instead of auto-detecting. Plan commands were verified during planning and are more reliable.

### 0.2 Identify Validation Scripts

Check config for: type-check, lint, lint:fix, test, build. Use the plan's "Validation Commands" section.

## Phase 1: Load Plan

Read plan file. Extract: **Plan Metadata** (update status `pending` → `in-progress`), **Metadata table** (pre-filled commands — use instead of auto-detecting), Summary, Patterns to Mirror, Files to Change (with **Insert At** hints — verify line numbers), **Integration Points** (caller, hook location, wiring), Step-by-Step Tasks, Validation Commands, **Confidence Score**, Acceptance Criteria. If not found: STOP with error.

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

For each task in the plan (TDD approach):

1. **Read Context**: Read MIRROR file reference, understand pattern, read IMPORTS, read Testing Strategy
2. **Write Test First (RED)**: For tasks that CREATE new functions/modules — write test cases first, run tests (should FAIL). Skip test-first for config/wiring/schema tasks.
3. **Implement (GREEN)**: Make change exactly as specified, follow MIRROR pattern, handle GOTCHA warnings. Run tests — should now PASS.
4. **Validate Immediately**: Run type-check after EVERY file change. If fails → read error → fix → re-run → only proceed when passing
5. **Track Progress**: Log each task with TDD status: `Task 1: Test ✅ (3 cases) — Impl ✅`. If deviating, document WHAT and WHY.

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

### 4.2.1 Coverage Check
After tests pass, verify coverage on new/changed code (target: **90%**).
- Detect coverage tool (jest `--coverage`, vitest `--coverage`, pytest `--cov`, `go test -cover`, `cargo tarpaulin`)
- Focus on new/changed files only: `git diff --name-only origin/main...HEAD`
- If >= 90% → proceed. If < 90% → write more tests. If no coverage tool → skip with warning.
- (Lightweight metric gate — deeper behavioral analysis happens during review.)

### 4.2.5 Integration Tests (conditional)
If plan specifies integration tests or project has `test:integration` → run them. Skip if not applicable.

### 4.5 Edge Case Testing
Run any edge case tests specified in the plan.

### 4.6 Security Checks (conditional — basic SAST)
If feature involves user input/auth/data storage: scan changed files for hardcoded secrets, SQL injection patterns, unsafe eval/exec. Fix immediately if found.

### 4.7 Performance Regression (conditional)
If plan has performance benchmarks and project has benchmark tooling: run benchmarks, flag regressions > 20%.

### 4.8 API Contract Validation (conditional)
If project has OpenAPI/GraphQL schema and feature modifies API surface: validate schema is still valid.

## Phase 5: Report

### 5.1 Generate Report
Save to `.prp-output/reports/{plan-name}-report-codex.md` with:

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
Save to `.prp-output/reviews/pr-context-{BRANCH}.md` with:
- Branch name, files changed, implementation summary
- Validation status, key changes for review, focus areas
- This saves ~60K tokens when running via run-all workflow
- **CRITICAL**: Generate even if implementation fails early — include note about incomplete status and list completed/remaining tasks

### 5.3 Update Source PRD (if applicable)
If plan was from PRD: read PRD → find phase → change status from `in-progress` to `complete` → save.

### 5.4 Archive Plan
```bash
mkdir -p .prp-output/plans/completed
mv $ARGUMENTS .prp-output/plans/completed/
```

**GATE**: Do NOT proceed to Phase 6 until plan is archived. This prevents re-running the same plan.

## Phase 6: Output

Report to user: status, validation summary table, files changed count, deviations summary, artifacts created (including review context).

If from PRD: show PRD progress (updated phases table), next phase, parallel opportunity.

Next steps: review, create PR, merge.

> **Note for orchestrators**: The "Next Steps" above are for standalone usage only. If this command was invoked as part of run-all, the orchestrator should ignore these suggestions and proceed to its next step.

## Failure Handling

| Failure | Action |
|---------|--------|
| Type check fails | Read error → fix → re-run → don't proceed until passing |
| Tests fail | Identify which → determine implementation or test bug → fix root cause → re-run |
| Lint fails | Run lint fix → manually fix remaining → re-run |
| Build fails | Check error output → fix → re-run |
| Integration fails | Check server started → verify endpoint → fix → retry |
| **Early abort (any phase)** | **Jump to §5.2 (Generate Review Context) before stopping** — generate partial context with completed/remaining tasks, then §5.1 (Report) if possible |

## Success Criteria

- TASKS_COMPLETE: All plan tasks executed
- TYPES_PASS: Type-check exits 0
- LINT_PASS: Lint exits 0
- TESTS_PASS: All tests green
- BUILD_PASS: Build succeeds
- REPORT_CREATED: Implementation report exists at `.prp-output/reports/`
- PR_CONTEXT_CREATED: Review context exists at `.prp-output/reviews/pr-context-{BRANCH}.md`
- PRD_UPDATED: If plan came from PRD, phase status is `complete`
- PLAN_ARCHIVED: Original plan moved to completed
- PLAN_REMOVED: Original plan no longer in `.prp-output/plans/` (prevents re-run)

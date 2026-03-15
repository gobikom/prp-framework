---
description: Execute implementation plan with rigorous validation loops
agent: build
---

# PRP Implement — Execute Plan

Plan: $ARGUMENTS

## Mission

Execute the plan end-to-end autonomously. Validate after every change. Fix before moving on.

## Steps

1. **Detect Environment**: Package manager from lock files (bun/pnpm/yarn/npm/uv/cargo/go). Validation scripts from config. **Plan-provided commands take precedence** — if plan has Metadata table with Runner/Type Check/Lint/Test/Build, use those directly instead of auto-detecting.
2. **Load Plan**: Read plan, extract: Plan Metadata (update status `pending` → `in-progress`), Metadata table (pre-filled commands), Summary, Patterns to Mirror, Files to Change (with **Insert At** hints — verify line numbers), **Integration Points** (caller, hook location, wiring), Step-by-Step Tasks, Validation Commands, **Confidence Score**, Acceptance Criteria. If not found: STOP.
3. **Prepare Git**: Check branch and worktree state.
   - In worktree → use it
   - On main, clean → `git checkout -b feature/{plan-slug}`
   - On main, dirty → STOP
   - On feature branch → use it
   - Sync: `git fetch origin && git pull --rebase origin main 2>/dev/null || true`
4. **Execute Tasks (TDD Approach)**: For each task — read MIRROR reference and Testing Strategy. **Write test first (RED)** for new functions/modules (skip test-first for config/wiring/schema tasks). **Implement (GREEN)** — follow MIRROR pattern, run tests until passing. **Validate immediately** (type-check after EVERY change). Track progress with TDD status: `Task 1: Test ✅ (3 cases) — Impl ✅`. Document deviations (WHAT and WHY).
5. **Full Validation**:
   - 5.1 Static: type-check + lint (zero errors). If lint errors: lint fix → re-check → manual fix.
   - 5.2 Tests: MUST write/update tests. If fail: determine root cause → fix → re-run until green.
   - 5.2.1 Coverage: After tests pass, check coverage on new/changed code (target: **90%**). Auto-detect tool (jest/vitest `--coverage`, pytest `--cov`, `go test -cover`). If < 90% → write more tests. If no tool → skip with warning. (Lightweight metric gate — deeper behavioral analysis happens during review.)
   - 5.3 Build: must succeed.
   - 5.4 Integration (if applicable): start server → test endpoints → stop server.
   - 5.2.5 Integration Tests (conditional): if plan specifies or project has `test:integration` → run them.
   - 5.5 Edge cases from plan.
   - 5.6 Security Checks (conditional — basic SAST): scan changed files for hardcoded secrets, SQL injection, unsafe eval/exec. Fix if found.
   - 5.7 Performance Regression (conditional): if plan has benchmarks + project has tooling → run and flag regressions > 20%.
   - 5.8 API Contract Validation (conditional): if OpenAPI/GraphQL schema exists + API surface changed → validate schema.
6. **Report**: Save to `.prp-output/reports/{name}-report-opencode.md` with: assessment vs reality, tasks completed, validation results, files changed, deviations, issues, tests written.
   > **Note**: Uses `-opencode` suffix to identify OpenCode implementation reports and prevent overwriting reports from other tools (each tool uses its own suffix for parallel implementation capability).
7. **Generate Review Context** (for run-all workflow): Save to `.prp-output/reviews/pr-context-{BRANCH}.md` with: branch, files changed, implementation summary, validation status, key changes for review, focus areas. This saves ~60K tokens when running via run-all. **CRITICAL**: Generate even if implementation fails early — include note about incomplete status and list completed/remaining tasks.
8. **PRD Update** (if applicable): Change phase status from `in-progress` to `complete`.
9. **Archive**: `mv $ARGUMENTS .prp-output/plans/completed/` **GATE**: Do NOT proceed to output until plan is archived.
10. **Output**: Status, validation summary, files changed, deviations, artifacts (including review context), PRD progress (if applicable), next steps.
    > **Note for orchestrators**: The "Next Steps" above are for standalone usage only. If this command was invoked as part of run-all, the orchestrator should ignore these suggestions and proceed to its next step.

## Success Criteria

- All plan tasks executed
- Type-check, lint, tests, build all pass
- Implementation report created at `.prp-output/reports/`
- Review context file created at `.prp-output/reviews/pr-context-{BRANCH}.md`
- PRD updated (if applicable) — phase status is `complete`
- Plan archived to completed folder
- Plan removed from original location (prevents re-run)

## Failure Handling

- Type-check fails → read error, fix, re-run, don't proceed until passing
- Tests fail → determine implementation or test bug, fix root cause, re-run
- Lint fails → run lint fix, manually fix remaining
- Build fails → check error, fix, re-run
- Integration fails → check server, verify endpoint, fix, retry

---
description: Execute implementation plan with rigorous validation loops
agent: build
---

# PRP Implement — Execute Plan

Plan: $ARGUMENTS

## Mission

Execute the plan end-to-end autonomously. Validate after every change. Fix before moving on.

## Steps

1. **Detect Environment**: Package manager from lock files (bun/pnpm/yarn/npm/uv/cargo/go). Validation scripts from config. Use plan's "Validation Commands" section.
2. **Load Plan**: Read plan, extract: Summary, Patterns to Mirror, Files to Change, Step-by-Step Tasks, Validation Commands, Acceptance Criteria. If not found: STOP.
3. **Prepare Git**: Check branch and worktree state.
   - In worktree → use it
   - On main, clean → `git checkout -b feature/{plan-slug}`
   - On main, dirty → STOP
   - On feature branch → use it
   - Sync: `git fetch origin && git pull --rebase origin main 2>/dev/null || true`
4. **Execute Tasks**: For each task — read MIRROR reference, implement, **validate immediately** (type-check after EVERY change), track progress, document deviations (WHAT and WHY).
5. **Full Validation**:
   - 5.1 Static: type-check + lint (zero errors). If lint errors: lint fix → re-check → manual fix.
   - 5.2 Tests: MUST write/update tests. If fail: determine root cause → fix → re-run until green.
   - 5.3 Build: must succeed.
   - 5.4 Integration (if applicable): start server → test endpoints → stop server.
   - 5.5 Edge cases from plan.
6. **Report**: Save to `.claude/PRPs/reports/{name}-report-opencode.md` with: assessment vs reality, tasks completed, validation results, files changed, deviations, issues, tests written.
   > **Note**: Uses `-opencode` suffix to identify OpenCode implementation reports and prevent overwriting reports from other tools (each tool uses its own suffix for parallel implementation capability).
7. **Generate Review Context** (for run-all workflow): Save to `.claude/PRPs/reviews/pr-context-{BRANCH}.md` with: branch, files changed, implementation summary, validation status, key changes for review, focus areas. This saves ~60K tokens when running via run-all.
8. **PRD Update** (if applicable): Change phase status from `in-progress` to `complete`.
9. **Archive**: `mv $ARGUMENTS .ai-workflows/plans/completed/`
10. **Output**: Status, validation summary, files changed, deviations, artifacts (including review context), PRD progress (if applicable), next steps.

## Success Criteria

- All plan tasks executed
- Type-check, lint, tests, build all pass
- Implementation report created at `.claude/PRPs/reports/`
- Review context file created at `.claude/PRPs/reviews/pr-context-{BRANCH}.md`
- PRD updated (if applicable)
- Plan archived to completed folder

## Failure Handling

- Type-check fails → read error, fix, re-run, don't proceed until passing
- Tests fail → determine implementation or test bug, fix root cause, re-run
- Lint fails → run lint fix, manually fix remaining
- Build fails → check error, fix, re-run
- Integration fails → check server, verify endpoint, fix, retry

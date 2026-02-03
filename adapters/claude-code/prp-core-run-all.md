---
description: Orchestrate complete PRP workflow - plan, implement, commit, PR, and review in sequence with context passing
argument-hint: "<feature-description>" or --prp-path <path/to/plan.md> [--skip-review] [--no-pr]
---

# PRP Full Workflow Runner

**Input**: $ARGUMENTS

---

## Your Mission

Execute the complete PRP workflow end-to-end autonomously. Each step delegates to an existing command — do NOT duplicate their logic.

**Core Principle**: Each step passes context forward to the next. Never re-gather information that a previous step already produced.

**Golden Rule**: Stop immediately on failure. Do NOT continue with broken state.

---

## Step 0: PARSE INPUT

**Determine what was provided:**

| Input | Action |
|-------|--------|
| Feature description (text) | Start from Step 1 (create plan) |
| `--prp-path <path>` | Skip to Step 2 (plan already exists) |
| `--skip-review` | Skip Step 6 (review) |
| `--no-pr` | Skip Steps 5 and 6 (PR and review) |

**Set workflow variables:**
```
FEATURE = "{feature description or plan title}"
PLAN_PATH = "{path to plan, or TBD}"
BRANCH = "{TBD — set in Step 1}"
PR_NUMBER = "{TBD — set in Step 5}"
```

---

## Step 1: CREATE BRANCH

**Skip if**: already on a feature branch (not main/master)

```bash
# Check current branch
CURRENT=$(git branch --show-current)

# If on main, create feature branch
git checkout -b feature/{slug-from-feature-description}
```

**Variable update**: `BRANCH = feature/{slug}`

**Failure**: If working directory is dirty on main → STOP, ask user to stash or commit.

---

## Step 2: CREATE PLAN (skip if --prp-path provided)

**Invoke**: `/prp-plan "{FEATURE}"`

This command will:
- Analyze the codebase
- Generate a comprehensive plan
- Save to `.claude/PRPs/plans/`

**Variable update**: `PLAN_PATH = {generated plan path}`

**Failure**: If plan generation fails → STOP, report error.

**DO NOT**: Re-explain how to create a plan. The `/prp-plan` command handles everything.

---

## Step 3: IMPLEMENT

**Invoke**: `/prp-implement {PLAN_PATH}`

This command will:
- Read and execute the plan
- Run validation loops (typecheck, lint, test, build)
- Auto-fix failures
- Write implementation report
- **Generate review context file** (`pr-context-{branch}.md`) ← Token optimization
- Archive the plan

**Wait for completion.** This is the longest step.

**Failure**: If implementation fails after retries → STOP, report which task failed and why.

**DO NOT**: Add extra validation steps here. `/prp-implement` already has rigorous validation loops with retry limits.

**Context passed forward**:
- Implementation report at `.claude/PRPs/reports/`
- Review context file at `.claude/PRPs/reviews/pr-context-{BRANCH}.md`
- Validated code on feature branch

---

## Step 4: COMMIT

**Invoke**: `/prp-commit`

This command will:
- Stage relevant files
- Generate meaningful commit message
- Commit with Co-Authored-By

**Failure**: If commit fails (pre-commit hooks) → fix and retry (the command handles this).

**DO NOT**: Manually stage files or write commit messages. The command does this.

---

## Step 5: CREATE PR (skip if --no-pr)

**Invoke**: `/prp-pr`

This command will:
- Push branch to remote
- Create PR with summary, test plan, and description
- Return PR URL

**Variable update**: `PR_NUMBER = {created PR number}`

**Failure**: If PR creation fails → STOP, report error (usually auth or branch issue).

**DO NOT**: Manually craft PR body. The command generates it from commits.

---

## Step 6: REVIEW (skip if --skip-review or --no-pr)

**Invoke**: `/prp-review-agents {PR_NUMBER}`

This command will:
- **Detect pre-generated context file** from Step 3 → skip expensive context extraction
- Run applicable specialist agents (code, docs, tests, errors, types)
- Post review summary to PR

**Token optimization**: Because `/prp-implement` already generated `pr-context-{BRANCH}.md`, the review agents will:
- NOT re-fetch PR diff
- NOT re-run validation
- NOT re-read CLAUDE.md
- Only read targeted files per agent domain

**If critical issues found**:
1. Fix each critical issue
2. Run validation: `pnpm test && pnpm typecheck && pnpm lint`
3. Commit fixes: `/prp-commit`
4. Push: `git push`
5. Re-run review: `/prp-review-agents {PR_NUMBER}` (max 2 cycles)

**If no critical issues**: Proceed to summary.

---

## Step 7: SUMMARY REPORT

Generate final report:

```markdown
## PRP Workflow Complete

**Feature**: {FEATURE}
**Branch**: {BRANCH}
**Status**: Complete

### Steps Executed

| Step | Command | Result |
|------|---------|--------|
| Plan | /prp-plan | {path or "skipped"} |
| Implement | /prp-implement | {tasks completed} |
| Commit | /prp-commit | {commit hash} |
| PR | /prp-pr | {PR URL or "skipped"} |
| Review | /prp-review-agents | {verdict or "skipped"} |

### Artifacts

- Plan: `{PLAN_PATH}` (archived)
- Report: `.claude/PRPs/reports/{name}-report.md`
- Review Context: `.claude/PRPs/reviews/pr-context-{BRANCH}.md`
- PR: {URL}

### Review Verdict

{READY TO MERGE / NEEDS FIXES / NOT REVIEWED}

### Next Steps

1. {Based on review verdict}
2. Merge when approved
```

---

## Critical Rules

1. **Delegate, don't duplicate.** Each `/prp-*` command is self-contained. Do NOT re-implement their logic in this workflow. Just invoke them in sequence.

2. **Stop on failure.** If any step fails after its own retry logic, STOP the entire workflow. Do NOT skip to the next step.

3. **Pass context forward.** The review context file from `/prp-implement` is picked up by `/prp-review-agents` automatically. Do NOT re-generate it.

4. **No extra validation.** Do NOT add validation steps between commands. Each command validates its own output. Adding more just wastes tokens.

5. **One commit per implementation.** Use `/prp-commit` once after implement. If review fixes are needed, commit those separately.

6. **Max 2 review cycles.** If review still has critical issues after 2 fix-and-review cycles, STOP and report to user.

---

## Token Budget

This workflow is designed for minimal token usage:

| Step | Token Cost | Why |
|------|-----------|-----|
| Plan | Moderate | Codebase analysis needed |
| Implement | High | Code writing + validation |
| Commit | Low | Small command |
| PR | Low | Small command |
| Review | **Low** (with context file) | Pre-generated context skips ~60K tokens |
| **Total** | ~40% less than without optimization | Context file eliminates redundant work |

Without context optimization, review alone would cost ~80-150K tokens.
With context file from implement step, review costs ~15-30K tokens.

---

## Success Criteria

- **PLAN_CREATED**: Plan exists and is valid
- **CODE_IMPLEMENTED**: All tasks complete, validation passing
- **CONTEXT_GENERATED**: Review context file exists (from implement step)
- **COMMITTED**: Clean commit on feature branch
- **PR_CREATED**: PR exists on GitHub (unless --no-pr)
- **REVIEWED**: Review posted with verdict (unless --skip-review)
- **SUMMARY_REPORTED**: User has clear next steps

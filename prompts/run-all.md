# PRP Run All — Full Workflow Runner

## Input

Feature description or options: `{ARGS}`

## Mission

Execute the complete PRP workflow end-to-end autonomously. Each step delegates to an existing workflow — do NOT duplicate their logic.

- **Delegate, don't duplicate** — each workflow is self-contained
- **Stop on failure** — do NOT continue with broken state
- **Pass context forward** — never re-gather information a previous step produced

**Golden Rule**: Stop immediately on failure. Do NOT continue with broken state.

---

## Step 0: PARSE INPUT

**Parse the arguments to determine which steps to skip:**

| Argument Found | Action |
|---------------|--------|
| `--plan-path <path>` | Extract path. Set PLAN_PATH = path. Skip Step 2 (plan). |
| `--skip-review` | Set SKIP_REVIEW = true. Skip Step 6 (review). |
| `--no-pr` | Set NO_PR = true. Skip Steps 5 (PR) and 6 (review). |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`) |
| `--resume` | Resume from last failed step using saved state |
| `--no-interact` | Never ask user questions — use best judgment for ambiguous requirements, pick defaults for choices |
| Remaining text (after removing flags) | Set FEATURE = text |

**If `--plan-path` provided, validate file exists** — STOP if not found, show available plans.

**Set workflow variables:**

```
FEATURE = "{remaining text after flags, or title from plan file}"
PLAN_PATH = "{from --plan-path, or TBD — set in Step 2}"
BRANCH = "{TBD — set in Step 1}"
PR_NUMBER = "{TBD — set in Step 5}"
REVIEW_ARTIFACT = "{TBD — set in Step 6.1}"
SKIP_REVIEW = {true if --skip-review or --no-pr, false otherwise}
NO_PR = {true if --no-pr, false otherwise}
FIX_SEVERITY = "{from --fix-severity, default 'critical,high,medium,suggestion'}"
NO_INTERACT = {true if --no-interact, false otherwise}
```

**State management**: `.claude/prp-run-all.state.md` — create on start, update per step, delete on completion. Supports `--resume` from last failed step.

**Examples:**
- `Add JWT auth` → full workflow (all steps)
- `--plan-path plans/jwt.plan.md` → skip plan creation, start at implement
- `Add JWT auth --skip-review` → plan + implement + commit + PR, no review
- `--plan-path plans/jwt.plan.md --no-pr` → implement + commit only

---

## Step 1: CREATE BRANCH

**Skip if**: already on a feature branch (not main/master).

```bash
CURRENT=$(git branch --show-current)
# If on main, create feature branch
git checkout -b feature/{slug-from-feature-description}
```

**Variable update**: `BRANCH = feature/{slug}`

**Failure**: If working directory is dirty on main → STOP, ask user to stash or commit.

---

## Step 2: CREATE PLAN (skip if --plan-path provided)

Execute the **plan** workflow with: `{FEATURE}`

This will:
- Analyze the codebase
- Generate a comprehensive plan
- Save to plans directory

**Variable update**: `PLAN_PATH = {generated plan path}`

**Failure**: STOP, report error.

**DO NOT**: Re-explain how to create a plan. The plan workflow handles everything.

---

## Step 3: IMPLEMENT

Execute the **implement** workflow with: `{PLAN_PATH}`

This will:
- Read and execute the plan
- Run validation loops (typecheck, lint, test, build)
- Auto-fix failures
- Write implementation report
- Archive the plan

**Wait for completion.** This is the longest step.

**Failure**: If implementation fails after retries → STOP, report which task failed and why.

**DO NOT**: Add extra validation steps here. The implement workflow already has rigorous validation loops.

**Context passed forward**:
- Implementation report at `.prp-output/reports/`
- Validated code on feature branch

---

## Step 4: COMMIT

Execute the **commit** workflow.

This will:
- Stage relevant files
- Generate meaningful commit message
- Commit

**Failure**: If commit fails (pre-commit hooks) → fix and retry (the workflow handles this).

**DO NOT**: Manually stage files or write commit messages. **Do NOT stop after commit** — the commit output may suggest "Next: git push or create PR" but this is for standalone usage. **IGNORE that suggestion and proceed to Step 5.**

**⏭️ TRANSITION**: Commit succeeded → **immediately proceed to Step 5** (or Step 7 if `--no-pr`).

---

## Step 5: CREATE PR (skip if --no-pr)

Execute the **pr** workflow.

This will:
- Push branch to remote
- Create PR with summary, test plan, and description
- Return PR URL

**Variable update**: `PR_NUMBER = {created PR number}`

**Failure**: If PR creation fails → STOP, report error.

**DO NOT**: Manually craft PR body. If `NO_INTERACT = true`, pass `--no-interact` to the PR workflow. **Do NOT stop after PR** — the PR output may suggest "Next Steps" like "Wait for CI checks" but this is for standalone usage. **IGNORE that suggestion and proceed to Step 6.**

**⏭️ TRANSITION**: PR created → **immediately proceed to Step 6** (or Step 7 if `--skip-review`).

---

## Step 6: REVIEW (skip if --skip-review or --no-pr)

**Check for pr-context** (token optimization):
```bash
CONTEXT_FILE=".prp-output/reviews/pr-context-${BRANCH}.md"
```

Execute the **review** workflow with: `{PR_NUMBER}` + if CONTEXT_FILE exists, add `--context {CONTEXT_FILE}`

This will:
- Run applicable review passes (code, docs, tests, errors, types)
- Post review summary to PR
- Use pr-context to skip PR diff fetch (saves ~60K tokens)

**Variable update**: `REVIEW_ARTIFACT = {review artifact path}`

**If critical issues found**:
1. Execute review-fix workflow with `{REVIEW_ARTIFACT} --severity {FIX_SEVERITY}`
2. Run validation
3. Commit fixes
4. Push
5. Re-run review (max 2 cycles)

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

| Step | Workflow | Result |
|------|---------|--------|
| Plan | plan | {path or "skipped"} |
| Implement | implement | {tasks completed} |
| Commit | commit | {commit hash} |
| PR | pr | {PR URL or "skipped"} |
| Review | review | {verdict or "skipped"} |

### Artifacts

- Plan: `{PLAN_PATH}` (archived)
- Report: `.prp-output/reports/{name}-report.md`
- PR: {URL}

### Review Verdict

{READY TO MERGE / NEEDS FIXES / NOT REVIEWED}

### Next Steps

1. {Based on review verdict}
2. Merge when approved
```

---

## Critical Rules

1. **Delegate, don't duplicate.** Each workflow is self-contained. Do NOT re-implement their logic in this runner. Just invoke them in sequence.

2. **Stop on failure.** If any step fails after its own retry logic, STOP the entire workflow. Do NOT skip to the next step.

3. **Pass context forward.** Information from earlier steps (plan path, branch name, PR number) flows to later steps.

4. **No extra validation.** Do NOT add validation steps between workflows. Each workflow validates its own output. Adding more just wastes tokens.

5. **One commit per implementation.** Use the commit workflow once after implement. If review fixes are needed, commit those separately.

6. **Max 2 review cycles.** If review still has critical issues after 2 fix-and-review cycles, STOP and report to user.

7. **No-interact means ZERO questions.** When `NO_INTERACT = true`: NEVER ask the user questions at ANY point during this workflow. Make autonomous decisions for every step. Pick defaults, use best judgment — but NEVER pause to ask. This applies to ALL steps, not just plan.

---

## Token Budget

This workflow is designed for minimal token usage:

| Step | Token Cost | Why |
|------|-----------|-----|
| Plan | Moderate | Codebase analysis needed |
| Implement | High | Code writing + validation |
| Commit | Low | Small command |
| PR | Low | Small command |
| Review | Moderate | Multi-pass analysis |
| **Total** | Optimized | Each step handles its own scope |

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| Already on feature branch (not main) | Skip Step 1, use current branch |
| Dirty working directory on main | STOP — ask user to stash or commit |
| `--plan-path` file not found | STOP — show available plans in `.prp-output/plans/` |
| Implementation fails after retries | STOP — report which task failed and why |
| Commit fails (pre-commit hook) | Let commit workflow retry, then continue |
| PR already exists for branch | Use existing PR, skip creation |
| Review still has critical issues after 2 cycles | STOP — report remaining issues to user |
| `--resume` with no state file | WARN — start fresh |
| Conflicting flags (`--no-pr` + `--skip-review`) | `--no-pr` implies `--skip-review`, proceed |
| Lock file exists (concurrent run) | STOP — "Another run-all is in progress." |

---

## Success Criteria

- **PLAN_CREATED**: Plan exists and is valid
- **CODE_IMPLEMENTED**: All tasks complete, validation passing
- **COMMITTED**: Clean commit on feature branch
- **PR_CREATED**: PR exists on GitHub (unless --no-pr)
- **REVIEWED**: Review posted with verdict (unless --skip-review)
- **SUMMARY_REPORTED**: User has clear next steps

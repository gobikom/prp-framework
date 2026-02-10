---
description: Full PRP workflow — plan, implement, commit, PR, review. Supports --plan-path, --skip-review, --no-pr
agent: build
---

# PRP Run All — Full Workflow

Input: $ARGUMENTS

## Step 0: Parse Input

| Argument Found | Action |
|---------------|--------|
| `--plan-path <path>` | Extract path. Set PLAN_PATH. Skip Step 2. |
| `--skip-review` | Skip Step 6. |
| `--no-pr` | Skip Steps 5 and 6. |
| Remaining text | Set FEATURE = remaining text |

**Set variables:**
```
FEATURE = "{text after removing flags}"
PLAN_PATH = "{from --plan-path, or TBD}"
BRANCH = "{TBD — set in Step 1}"
PR_NUMBER = "{TBD — set in Step 5}"
SKIP_REVIEW = {true if --skip-review or --no-pr}
NO_PR = {true if --no-pr}
```

**Examples:**
- `Add JWT auth` → full workflow
- `--plan-path .ai-workflows/plans/jwt.plan.md` → skip plan
- `Add JWT auth --skip-review` → skip review
- `--plan-path plans/jwt.plan.md --no-pr` → implement + commit only

## Workflow (sequential, stop on failure)

### Step 1: Branch
`git checkout -b feature/{slug}` (skip if already on feature branch)
Failure: dirty on main → STOP.

### Step 2: Plan (skip if --plan-path)
`/prp:plan {FEATURE}` — DO NOT re-explain plan logic.
Update PLAN_PATH with generated path.
Failure → STOP.

### Step 3: Implement
`/prp:implement {PLAN_PATH}` — DO NOT add extra validation.
Wait for completion — longest step.
Failure → STOP, report which task failed.

**3.1 Verify Artifacts**: After implement completes, check:
```bash
ls -la .claude/PRPs/reports/*-report*.md 2>/dev/null
ls -la .claude/PRPs/reviews/pr-context-*.md 2>/dev/null
```

**3.2 Fallback**: If report missing, create minimal report. If pr-context missing, create minimal context with files changed from `git diff --name-only origin/main...HEAD`.

### Step 4: Commit
`/prp:commit` — DO NOT manually stage files.

### Step 5: PR (skip if --no-pr)
`/prp:pr`
Update PR_NUMBER.
Failure → STOP.

### Step 6: Review (skip if --skip-review or --no-pr)
`/prp:review {PR_NUMBER}`
Critical issues → fix, commit, push, re-review (max 2 cycles).

### Step 7: Summary
Report: feature, branch, status, steps executed table, artifacts, review verdict, next steps.

## Rules

- **Delegate, don't duplicate** — each command handles its own logic
- **Verify artifacts after implement** — check report and pr-context files exist, use fallback if missing
- **Stop on failure** — never continue with broken state
- **Pass context forward** — information flows from earlier to later steps
- **No extra validation** — each command validates its own output
- **One commit per implementation** — separate commits for review fixes
- **Max 2 review-fix cycles** — if still critical after 2 rounds, stop and report

## Success Criteria

- Plan created (or provided)
- Code implemented with passing validation
- Report exists (created or fallback)
- Review context exists (created or fallback)
- Committed on feature branch
- PR created (unless --no-pr)
- Reviewed with verdict (unless --skip-review)

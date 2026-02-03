---
name: prp-run-all
description: Execute the complete PRP workflow end-to-end — plan, implement, commit, PR, and review. Delegates to individual PRP skills in sequence. Supports --plan-path, --skip-review, --no-pr options.
metadata:
  short-description: Full PRP workflow
---

# PRP Run All — Full Workflow Runner

## Input

Feature description or options: `$ARGUMENTS`

## Mission

Execute the complete PRP workflow end-to-end autonomously. Each step delegates to an existing skill — do NOT duplicate their logic.

- **Delegate, don't duplicate** — each skill is self-contained
- **Stop on failure** — do NOT continue with broken state
- **Pass context forward** — never re-gather information a previous step produced

## Step 0: Parse Input

| Argument Found | Action |
|---------------|--------|
| `--plan-path <path>` | Extract path. Set PLAN_PATH = path. Skip Step 2. |
| `--skip-review` | Set SKIP_REVIEW = true. Skip Step 6. |
| `--no-pr` | Set NO_PR = true. Skip Steps 5 and 6. |
| Remaining text (after removing flags) | Set FEATURE = text |

**Set workflow variables:**
```
FEATURE = "{remaining text after flags, or title from plan file}"
PLAN_PATH = "{from --plan-path, or TBD — set in Step 2}"
BRANCH = "{TBD — set in Step 1}"
PR_NUMBER = "{TBD — set in Step 5}"
SKIP_REVIEW = {true if --skip-review or --no-pr}
NO_PR = {true if --no-pr}
```

**Examples:**
- `Add JWT auth` → full workflow
- `--plan-path plans/jwt.plan.md` → skip plan creation
- `Add JWT auth --skip-review` → skip review step
- `--plan-path plans/jwt.plan.md --no-pr` → implement + commit only

## Workflow

Execute these steps in sequence. **Stop immediately on any failure.**

### Step 1: Branch
Create feature branch (skip if already on one, not main/master).
```bash
git checkout -b feature/{slug-from-FEATURE}
```
Failure: dirty working dir on main → STOP, ask to stash/commit.

### Step 2: Plan (skip if --plan-path)
Use `$prp-plan` skill with FEATURE.
Update: PLAN_PATH = generated plan path.
Failure → STOP. DO NOT re-explain how to create a plan.

### Step 3: Implement
Use `$prp-implement` skill with PLAN_PATH.
Wait for completion — this is the longest step.
Failure → STOP, report which task failed.
DO NOT add extra validation — the skill has its own.

### Step 4: Commit
Use `$prp-commit` skill.
Failure: pre-commit hook → fix and retry.
DO NOT manually stage files.

### Step 5: PR (skip if NO_PR)
Use `$prp-pr` skill.
Update: PR_NUMBER = created PR number.
Failure → STOP.

### Step 6: Review (skip if SKIP_REVIEW or NO_PR)
Use `$prp-review` skill with PR_NUMBER.
If critical issues: fix → commit → push → re-review (max 2 cycles).

### Step 7: Summary
Report: feature, branch, status, steps executed table, artifacts, review verdict, next steps.

## Critical Rules

1. **Delegate, don't duplicate** — each skill handles its own logic
2. **Stop on failure** — never continue with broken state
3. **Pass context forward** — information flows from earlier to later steps
4. **No extra validation** — each skill validates its own output
5. **One commit per implementation** — separate commits for review fixes
6. **Max 2 review cycles** — if still critical after 2 rounds, STOP and report

## Success Criteria

- PLAN_CREATED: Plan exists and is valid
- CODE_IMPLEMENTED: All tasks complete, validation passing
- COMMITTED: Clean commit on feature branch
- PR_CREATED: PR exists (unless --no-pr)
- REVIEWED: Review posted with verdict (unless --skip-review)
- SUMMARY_REPORTED: User has clear next steps

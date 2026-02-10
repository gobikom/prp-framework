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
Failure → STOP.
❌ DO NOT: Read plan skill and execute logic yourself, analyze codebase directly.
✅ CHECKPOINT: Did you invoke `$prp-plan`? If not → STOP → invoke it.

### Step 3: Implement
Use `$prp-implement` skill with PLAN_PATH.
Wait for completion — this is the longest step.
Failure → STOP, report which task failed.
❌ DO NOT: Read implement skill and execute logic yourself, write code directly.
✅ CHECKPOINT: Did you invoke `$prp-implement`? If not → STOP → invoke it.

**3.1 Verify Artifacts**: After implement completes, check:
```bash
ls -la .claude/PRPs/reports/*-report*.md 2>/dev/null
ls -la .claude/PRPs/reviews/pr-context-*.md 2>/dev/null
```

**3.2 Fallback**: If report missing, create minimal report with files changed. If pr-context missing, create minimal context from `git diff --name-only origin/main...HEAD`.

### Step 4: Commit
Use `$prp-commit` skill.
Failure: pre-commit hook → fix and retry.
❌ DO NOT: Run git add/commit directly, manually stage files.
✅ CHECKPOINT: Did you invoke `$prp-commit`? If not → STOP → invoke it.

### Step 5: PR (skip if NO_PR)
Use `$prp-pr` skill.
Update: PR_NUMBER = created PR number.
Failure → STOP.
❌ DO NOT: Run gh pr create directly, manually craft PR body.
✅ CHECKPOINT: Did you invoke `$prp-pr`? If not → STOP → invoke it.

### Step 6: Review (skip if SKIP_REVIEW or NO_PR)
Use `$prp-review` skill with PR_NUMBER.
If critical issues: fix → commit → push → re-review (max 2 cycles).
❌ DO NOT: Read code and review it yourself, skip the skill.
✅ CHECKPOINT: Did you invoke `$prp-review`? If not → STOP → invoke it.

### Step 7: Summary
Report: feature, branch, status, steps executed table, artifacts, review verdict, next steps.

## Critical Rules

1. **Delegate, don't duplicate** — each skill handles its own logic
2. **Verify artifacts after implement** — check report and pr-context files exist, use fallback if missing
3. **Stop on failure** — never continue with broken state
4. **Pass context forward** — information flows from earlier to later steps
5. **No extra validation** — each skill validates its own output
6. **One commit per implementation** — separate commits for review fixes
7. **Max 2 review cycles** — if still critical after 2 rounds, STOP and report

## Success Criteria

- PLAN_CREATED: Plan exists and is valid
- CODE_IMPLEMENTED: All tasks complete, validation passing
- REPORT_EXISTS: Implementation report exists (created or fallback)
- CONTEXT_GENERATED: Review context file exists (created or fallback)
- COMMITTED: Clean commit on feature branch
- PR_CREATED: PR exists (unless --no-pr)
- REVIEWED: Review posted with verdict (unless --skip-review)
- SUMMARY_REPORTED: User has clear next steps

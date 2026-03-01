---
description: Full PRP workflow — plan, implement, commit, PR, review. Supports --prp-path, --skip-review, --no-pr
---

# PRP Run All — Full Workflow

Input: $ARGUMENTS

## Step 0: Parse Input

| Argument Found | Action |
|---------------|--------|
| `--prp-path <path>` | Extract path. Set PLAN_PATH. Skip Step 2. |
| `--skip-review` | Skip Step 6. |
| `--no-pr` | Skip Steps 5 and 6. |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`) |
| `--resume` | Resume from last failed step |
| `--no-interact` | Never ask user questions — use best judgment, pick defaults |
| Remaining text | Set FEATURE = remaining text |

**If `--prp-path` provided, validate file exists** — STOP if not found.

**Set variables:**
```
FEATURE = "{text after removing flags}"
PLAN_PATH = "{from --prp-path, or TBD}"
BRANCH = "{TBD — set in Step 1}"
PR_NUMBER = "{TBD — set in Step 5}"
REVIEW_ARTIFACT = "{TBD — set in Step 6.1}"
SKIP_REVIEW = {true if --skip-review or --no-pr}
NO_PR = {true if --no-pr}
FIX_SEVERITY = "{from --fix-severity, default 'critical,high,medium,suggestion'}"
NO_INTERACT = {true if --no-interact}
```

**State management**: `.claude/prp-run-all.state.md` — create on start, update per step, delete on completion. Supports `--resume` from last failed step.

**Examples:**
- `Add JWT auth` → full workflow
- `--prp-path .prp-output/plans/jwt.plan.md` → skip plan
- `Add JWT auth --skip-review` → skip review
- `--prp-path plans/jwt.plan.md --no-pr` → implement + commit only

## Workflow (sequential, stop on failure)

### Step 1: Branch
`git checkout -b feature/{slug}` (skip if already on feature branch)
Failure: dirty on main → STOP.

### Step 2: Plan (skip if --prp-path)
`/prp-plan {FEATURE}` — Invoke the workflow, DO NOT inline its logic.
Update PLAN_PATH with generated path.
Failure → STOP.
❌ DO NOT: Read prp-plan.md and execute logic yourself, analyze codebase directly.
✅ CHECKPOINT: Did you invoke `/prp-plan`? If not → STOP → invoke it.

### Step 3: Implement
`/prp-implement {PLAN_PATH}` — Invoke the workflow, DO NOT inline its logic.
Wait for completion — longest step.
Failure → STOP, report which task failed.
❌ DO NOT: Read prp-implement.md and execute logic yourself, write code directly. **Stop after implement** — the output will show "Next Steps" including "Create PR" but this is for standalone usage only. **IGNORE it. Do NOT ask user. Immediately proceed to Step 3.1.**
✅ CHECKPOINT: Did you invoke `/prp-implement`? If not → STOP → invoke it.
⏭️ TRANSITION: Implement succeeded → **immediately proceed to Step 3.1** (verify artifacts). Do NOT stop here.

**3.1 Verify Artifacts**: After implement completes, check:
```bash
ls -la .prp-output/reports/*-report*.md 2>/dev/null
ls -la .prp-output/reviews/pr-context-*.md 2>/dev/null
```

**3.2 Fallback**: If report missing, create minimal report. If pr-context missing, create minimal context with files changed from `git diff --name-only origin/main...HEAD`.

### Step 4: Commit
`/prp-commit` — Invoke the workflow, DO NOT inline its logic.
❌ DO NOT: Run git add/commit directly, manually stage files. **Stop after commit** — the commit output suggests "Next: git push or /prp-pr" but this is for standalone usage only. **IGNORE it. Do NOT use AskUserQuestion. Do NOT pause for user input. Immediately invoke `/prp-pr` for Step 5.**
✅ CHECKPOINT: Did you invoke `/prp-commit`? If not → STOP → invoke it.
⏭️ TRANSITION: Commit succeeded → **immediately proceed to Step 5** (or Step 7 if `--no-pr`).

### Step 5: PR (skip if --no-pr)
`/prp-pr` — Invoke the workflow, DO NOT inline its logic.
Update PR_NUMBER.
Failure → STOP.
If `NO_INTERACT = true`, pass `--no-interact` to `/prp-pr`.
❌ DO NOT: Run gh pr create directly, manually craft PR body, **stop after PR**. The PR output suggests "Next Steps" — standalone usage only. **IGNORE it.**
✅ CHECKPOINT: Did you invoke `/prp-pr`? If not → STOP → invoke it.
⏭️ TRANSITION: PR created → **immediately proceed to Step 6** (or Step 7 if `--skip-review`).

### Step 6: Review (skip if --skip-review or --no-pr)
`/prp-review {PR_NUMBER}` — if `.prp-output/reviews/pr-context-{BRANCH}.md` exists, pass `--context` flag. DO NOT inline its logic.
Issues matching FIX_SEVERITY found → `/prp-review-fix {REVIEW_ARTIFACT} --severity {FIX_SEVERITY}` → commit, push, re-review (max 2 cycles).
❌ DO NOT: Read code and review it yourself, skip the workflow.
✅ CHECKPOINT: Did you invoke `/prp-review`? If not → STOP → invoke it.

### Step 7: Summary
Report: feature, branch, status, steps executed table, artifacts, review verdict, next steps.

## Rules

- **Delegate, don't duplicate** — each workflow handles its own logic
- **Verify artifacts after implement** — check report and pr-context files exist, use fallback if missing
- **Stop on failure** — never continue with broken state
- **Pass context forward** — information flows from earlier to later steps
- **No extra validation** — each workflow validates its own output
- **One commit per implementation** — separate commits for review fixes
- **Max 2 review-fix cycles** — if still critical after 2 rounds, stop and report
- **No-interact means ZERO questions** — when `NO_INTERACT = true`: NEVER ask user questions. Make autonomous decisions, pick defaults. Pass `--no-interact` to sub-commands.

## Usage

```
/prp-run-all Add JWT authentication
/prp-run-all --prp-path .prp-output/plans/jwt.plan.md
/prp-run-all Add JWT auth --skip-review
/prp-run-all --prp-path plans/jwt.plan.md --no-pr
```

## Success Criteria

- Plan created (or provided)
- Code implemented with passing validation
- Report exists (created or fallback)
- Review context exists (created or fallback)
- Committed on feature branch
- PR created (unless --no-pr)
- Reviewed with verdict (unless --skip-review)

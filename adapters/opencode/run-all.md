---
description: Full PRP workflow — plan, implement, commit, PR, review. Supports --prp-path, --skip-review, --no-pr
agent: build
---

# PRP Run All — Full Workflow

**⚠️ AUTONOMOUS EXECUTION — CRITICAL**: This workflow runs without pausing between steps. After each command completes successfully, **IMMEDIATELY proceed to the next step** — do NOT output any progress message to the user first. Do NOT say "Implementation is complete, now I'll create the PR." Do NOT ask for confirmation between steps. The only user-facing output is Step 7 (final summary) or a STOP message on failure. Sub-command outputs may contain "Next Steps" suggestions — **IGNORE them completely**.

Input: $ARGUMENTS

## Step 0: Parse Input

| Argument Found | Action |
|---------------|--------|
| `--prp-path <path>` | Extract path. Set PLAN_PATH. Skip Step 2. |
| `--skip-review` | Skip Step 6. |
| `--no-pr` | Skip Steps 5 and 6. |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`) |
| `--resume` | Resume from last failed step using saved state |
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
`/prp:plan {FEATURE}` — Invoke the command, DO NOT inline its logic.
Update PLAN_PATH with generated path.
Failure → STOP.
❌ DO NOT: Read plan.md and execute logic yourself, analyze codebase directly.
✅ CHECKPOINT: Did you invoke `/prp:plan`? If not → STOP → invoke it.

### Step 3: Implement
`/prp:implement {PLAN_PATH}` — Invoke the command, DO NOT inline its logic.
Wait for completion — longest step.
Failure → STOP, report which task failed.
❌ DO NOT: Read implement.md and execute logic yourself, write code directly. **Stop after implement** — the output will show "Next Steps" including "Create PR" but this is for standalone usage only. **IGNORE it. Do NOT ask user. Immediately proceed to Step 3.1.**
✅ CHECKPOINT: Did you invoke `/prp:implement`? If not → STOP → invoke it.
⏭️ TRANSITION: Implement succeeded → **immediately proceed to Step 3.1** (verify artifacts). Do NOT stop here.

**3.1 Verify Artifacts**: After implement completes, check:
```bash
ls -la .prp-output/reports/*-report*.md 2>/dev/null
ls -la .prp-output/reviews/pr-context-*.md 2>/dev/null
```

**3.2 Fallback**: If report missing, create minimal report. If pr-context missing, create minimal context with files changed from `git diff --name-only origin/main...HEAD`.

### Step 4: Commit
`/prp:commit` — Invoke the command, DO NOT inline its logic.
❌ DO NOT: Run git add/commit directly, manually stage files, **stop after commit**. The commit output suggests "Next: git push or /prp:pr" — this is for standalone usage only. **IGNORE it and proceed to Step 5.**
✅ CHECKPOINT: Did you invoke `/prp:commit`? If not → STOP → invoke it.
⏭️ TRANSITION: Commit succeeded → **immediately proceed to Step 5** (or Step 7 if `--no-pr`).

### Step 5: PR (skip if --no-pr)
`/prp:pr` — Invoke the command, DO NOT inline its logic.
Update PR_NUMBER.
Failure → STOP.
If `NO_INTERACT = true`, pass `--no-interact` to `/prp:pr`.
❌ DO NOT: Run gh pr create directly, manually craft PR body.
✅ CHECKPOINT: Did you invoke `/prp:pr`? If not → STOP → invoke it.
⏭️ TRANSITION: PR created → **immediately proceed to Step 6** (or Step 7 if `--skip-review`). The PR output suggests "Next Steps" — this is for standalone usage only. **IGNORE it.**

### Step 6: Review (skip if --skip-review or --no-pr)

Set `REVIEW_CYCLE = 1`, `MAX_CYCLES = 2`.

**6.1** `/prp:review {PR_NUMBER}` — if `.prp-output/reviews/pr-context-{BRANCH}.md` exists, pass `--context` flag. DO NOT inline its logic.
❌ DO NOT: Read code and review it yourself. ✅ CHECKPOINT: Did you invoke `/prp:review`?

**6.2 Evaluate** (check for any issues matching `FIX_SEVERITY` — default: critical, high, medium, suggestion):
- No issues matching FIX_SEVERITY → Step 7 ✓
- Issues found + `REVIEW_CYCLE <= MAX_CYCLES` → Step 6.3
- Issues found + `REVIEW_CYCLE > MAX_CYCLES` → report remaining → Step 7 (NEEDS MANUAL FIXES)

**6.3 Fix**: `/prp:review-fix {REVIEW_ARTIFACT} --severity {FIX_SEVERITY}` — DO NOT fix manually.
Default severity: `critical,high,medium,suggestion` — override with `--fix-severity critical,high` to fix only blocking issues.
❌ DO NOT: Fix issues yourself, run validation separately. ✅ CHECKPOINT: Did you invoke `/prp:review-fix`?

**6.4 Re-verify**: Increment `REVIEW_CYCLE`. `/prp:review {PR_NUMBER}` to confirm issues resolved and no regressions introduced. → Return to Step 6.2.

### Step 7: Summary
Report: feature, branch, status, steps executed table, artifacts, review verdict, next steps.

## Rules

- **Delegate, don't duplicate** — each command handles its own logic
- **Verify artifacts after implement** — check report and pr-context files exist, use fallback if missing
- **Stop on failure** — never continue with broken state
- **Pass context forward** — information flows from earlier to later steps
- **No extra validation** — each command validates its own output
- **One commit per implementation** — review fixes committed separately by `/prp:review-fix`
- **Max 2 review cycles** — if still critical after 2 fix-and-re-verify cycles, stop and report
- **Re-verify after fix** — always re-run `/prp:review` after `/prp:review-fix` to confirm resolution and catch regressions
- **No-interact means ZERO questions** — when `NO_INTERACT = true`: NEVER ask the user questions at any point. Make autonomous decisions, pick defaults, use best judgment. Pass `--no-interact` to sub-commands that support it.

## Success Criteria

- Plan created (or provided)
- Code implemented with passing validation
- Report exists (created or fallback)
- Review context exists (created or fallback)
- Committed on feature branch
- PR created (unless --no-pr)
- Reviewed with verdict (unless --skip-review)

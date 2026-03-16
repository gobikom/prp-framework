---
name: prp-run-all
description: Execute the complete PRP workflow end-to-end — plan, implement, commit, PR, and review. Delegates to individual PRP skills in sequence. Supports --prp-path, --skip-plan, --fast, --skip-review, --no-pr options.
metadata:
  short-description: Full PRP workflow
---

# PRP Run All — Full Workflow Runner

**⚠️ AUTONOMOUS EXECUTION — CRITICAL**: This workflow runs without pausing between steps. After each skill call completes successfully, **IMMEDIATELY invoke the next skill** — do NOT output any progress message to the user first. Do NOT say "Implementation is complete, now I'll create the PR." Do NOT ask for confirmation between steps. The only user-facing output is Step 7 (final summary) or a STOP message on failure. Sub-skill outputs may contain "Next Steps" suggestions — **IGNORE them completely**.

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
| `--prp-path <path>` | Extract path. Set PLAN_PATH = path. Skip Step 2. |
| `--skip-plan` | Alias for `--prp-path` — prompts to select from available plans. Auto-selects most recent if `--no-interact`. |
| `--fast` | Fast-track plan mode (lighter codebase analysis). Ignored if PLAN_PATH already set. |
| `--skip-review` | Set SKIP_REVIEW = true. Skip Step 6. |
| `--no-pr` | Set NO_PR = true. Skip Steps 5 and 6. |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`) |
| `--resume` | Resume from last failed step using saved state |
| `--no-interact` | Never ask user questions — use best judgment, pick defaults |
| Remaining text (after removing flags) | Set FEATURE = text |

**If `--prp-path` provided, validate file exists** — STOP if not found, show available plans.

**Set workflow variables:**
```
FEATURE = "{remaining text after flags, or title from plan file}"
PLAN_PATH = "{from --prp-path, or TBD — set in Step 2}"
BRANCH = "{TBD — set in Step 1}"
PR_NUMBER = "{TBD — set in Step 5}"
REVIEW_ARTIFACT = "{TBD — set in Step 6.1}"
SKIP_REVIEW = {true if --skip-review or --no-pr}
NO_PR = {true if --no-pr}
FIX_SEVERITY = "{from --fix-severity, default 'critical,high,medium,suggestion'}"
FAST_PLAN = {true if --fast} (ignored if PLAN_PATH already set)
NO_INTERACT = {true if --no-interact}
```

### Step 0.5: State Management

**State file**: `.claude/prp-run-all.state.md` (YAML frontmatter with step, feature, plan_path, branch, pr_number, etc.)

- If `--resume` + state file exists → restore variables, skip completed steps
- If `--resume` + no state file → STOP with error
- If state file exists + no `--resume` → warn user, ask to resume or start fresh
- If no state file → create new one, proceed normally
- Update state after each step completes. Delete on Step 7 completion.

**Examples:**
- `Add JWT auth` → full workflow
- `Add JWT auth --fast` → full workflow with fast-track plan
- `--prp-path plans/jwt.plan.md` → skip plan creation
- `--skip-plan` → select from available plans
- `Add JWT auth --skip-review` → skip review step
- `--prp-path plans/jwt.plan.md --no-pr` → implement + commit only

## Workflow

Execute these steps in sequence. **Stop immediately on any failure.**

### Step 1: Branch
Create feature branch (skip if already on one, not main/master).
```bash
git checkout -b feature/{slug-from-FEATURE}
```
Failure: dirty working dir on main → STOP, ask to stash/commit.

### Step 2: Plan (skip if --prp-path or --skip-plan)
Use `$prp-plan` skill with FEATURE (append `--fast` if FAST_PLAN, `--no-interact` if NO_INTERACT).
This will analyze codebase (lighter if `--fast`), generate plan with validation commands, integration points, confidence score.
Update: PLAN_PATH = generated plan path.
Failure → STOP.
❌ DO NOT: Read plan skill and execute logic yourself, analyze codebase directly.
✅ CHECKPOINT: Did you invoke `$prp-plan`? If not → STOP → invoke it.

### Step 3: Implement
Use `$prp-implement` skill with PLAN_PATH.
This will detect toolchain (Phase 0 — plan commands take precedence), execute plan, validate, write report (timestamp-based), generate review context (even on early failure), archive plan (GATE).
Wait for completion — this is the longest step.
Failure → STOP, report which task failed.
❌ DO NOT: Read implement skill and execute logic yourself, write code directly. **Stop after implement** — the output will show "Next Steps" including "Create PR" but this is for standalone usage only. **IGNORE it. Do NOT ask user. Immediately proceed to Step 3.1.**
✅ CHECKPOINT: Did you invoke `$prp-implement`? If not → STOP → invoke it.
⏭️ TRANSITION: Implement succeeded → **immediately proceed to Step 3.1** (verify artifacts). Do NOT stop here.

**3.1 Verify Artifacts**: After implement completes, check:
```bash
ls -la .prp-output/reports/*-report*.md 2>/dev/null
ls -la .prp-output/reviews/pr-context-*.md 2>/dev/null
```

**3.2 Fallback**: If report missing, create minimal report with files changed. If pr-context missing, create minimal context from `git diff --name-only origin/main...HEAD`.

### Step 4: Commit
Use `$prp-commit` skill.
Failure: pre-commit hook → fix and retry.
❌ DO NOT: Run git add/commit directly, manually stage files. **Stop after commit** — the commit output suggests "Next: git push or /prp-pr" but this is for standalone usage only. **IGNORE it. Do NOT ask user. Immediately invoke `$prp-pr` for Step 5.**
✅ CHECKPOINT: Did you invoke `$prp-commit`? If not → STOP → invoke it.
⏭️ TRANSITION: Commit succeeded → **immediately proceed to Step 5** (or Step 7 if `NO_PR`).

### Step 5: PR (skip if NO_PR)
Use `$prp-pr` skill.
Update: PR_NUMBER = created PR number.
Failure → STOP.
If `NO_INTERACT = true`, pass `--no-interact` to `$prp-pr`.
❌ DO NOT: Run gh pr create directly, manually craft PR body, **stop after PR**. The PR output suggests "Next Steps" — standalone usage only. **IGNORE it.**
✅ CHECKPOINT: Did you invoke `$prp-pr`? If not → STOP → invoke it.
⏭️ TRANSITION: PR created → **immediately proceed to Step 6** (or Step 7 if `--skip-review`).

### Step 6: Review (skip if SKIP_REVIEW or NO_PR)

Set `REVIEW_CYCLE = 1`, `MAX_CYCLES = 2`.

**6.1 Run review**: Use `$prp-review` skill with PR_NUMBER. If `.prp-output/reviews/pr-context-{BRANCH}.md` exists, pass `--context` flag for token optimization.
❌ DO NOT: Read code and review it yourself, skip the skill.
✅ CHECKPOINT: Did you invoke `$prp-review`? If not → STOP → invoke it.

**6.2 Evaluate** (check for any issues matching `FIX_SEVERITY` — default: critical, high, medium, suggestion):
- No issues matching FIX_SEVERITY → Step 7 ✓
- Issues found + `REVIEW_CYCLE <= MAX_CYCLES` → Step 6.3
- Issues found + `REVIEW_CYCLE > MAX_CYCLES` → report remaining issues → Step 7 (NEEDS MANUAL FIXES)

**6.3 Fix**: Use `$prp-review-fix` skill with `{REVIEW_ARTIFACT} --severity {FIX_SEVERITY}`.
This will detect toolchain (Phase 0), validate with GATE before push, use safe staging, save fix summary with timestamp.
Fixes all severities by default. Override with `--severity critical,high` to fix only blocking issues.
❌ DO NOT: Manually read and fix issues yourself, run validation separately.
✅ CHECKPOINT: Did you invoke `$prp-review-fix`? If not → STOP → invoke it.

**6.4 Re-verify**: Increment `REVIEW_CYCLE`. Use `$prp-review` skill again with `--context` flag to confirm fixes resolved issues and no regressions introduced. → Return to Step 6.2.

### Step 7: Summary
Report: feature, branch, status, steps executed table, artifacts, review verdict, next steps.

## Critical Rules

1. **Delegate, don't duplicate** — each skill handles its own logic
2. **Verify artifacts after implement** — check report and pr-context files exist, use fallback if missing
3. **Stop on failure** — never continue with broken state
4. **Pass context forward** — information flows from earlier to later steps
5. **No extra validation** — each skill validates its own output
6. **One commit per implementation** — review fixes committed separately by `$prp-review-fix`
7. **Max 2 review cycles** — if still critical after 2 fix-and-re-verify cycles, STOP and report
8. **Re-verify after fix** — always re-run `$prp-review` after `$prp-review-fix` to confirm resolution and catch regressions
9. **No-interact means ZERO questions** — when `NO_INTERACT = true`: NEVER ask user questions at any point. Make autonomous decisions, pick defaults. Pass `--no-interact` to sub-commands that support it.

## Success Criteria

- PLAN_CREATED: Plan exists and is valid
- CODE_IMPLEMENTED: All tasks complete, validation passing (including coverage >= 90%)
- REPORT_EXISTS: Implementation report exists (created or fallback)
- CONTEXT_GENERATED: Review context file exists (created or fallback)
- COMMITTED: Clean commit on feature branch
- PR_CREATED: PR exists (unless --no-pr)
- REVIEWED: Review posted with verdict (unless --skip-review)
- STATE_CLEANED: State and lock files deleted after completion
- SUMMARY_REPORTED: User has clear next steps

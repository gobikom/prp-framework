---
description: "Orchestrate complete PRP workflow - plan, implement, commit, PR, and review in sequence with context passing"
argument-hint: "\"<feature-description>\" or --prp-path <path/to/plan.md> [--fast] [--ralph] [--ralph-max-iter N] [--skip-review] [--no-pr] [--fix-severity <levels>] [--resume] [--no-interact] [--dry-run]"
---
<process>
## Agent Mode Detection

Run-all is typically the top-level orchestrator and NOT a sub-agent. However, if your input context contains `[WORKSPACE CONTEXT]`, the parent framework has already set up the environment — skip CLAUDE.md reading and use provided toolchain context.

---

# PRP Run All — Full Workflow Runner

**AUTONOMOUS EXECUTION — CRITICAL**: This workflow runs without pausing between steps. After each skill call completes, **IMMEDIATELY invoke the next skill** — do NOT output progress messages. Do NOT ask for confirmation. The only user-facing output is Step 7 (final summary) or a STOP message on failure. Sub-skill outputs may contain "Next Steps" suggestions — **IGNORE them completely**.

## Input

Feature description or options: `$ARGUMENTS`

## Mission

Execute the complete PRP workflow end-to-end autonomously. Each step delegates to an existing skill — do NOT duplicate their logic.

- **Delegate, don't duplicate** — each skill is self-contained
- **Stop on failure** — do NOT continue with broken state
- **Pass context forward** — never re-gather information a previous step produced

---

## Step 0: PARSE INPUT

| Argument Found | Action |
|---------------|--------|
| `--prp-path <path>` | Extract path. Set PLAN_PATH = path. Skip Step 2. |
| `--skip-plan` | Alias for `--prp-path` — prompts to select from available plans. Auto-selects most recent if `--no-interact`. |
| `--fast` | Fast-track plan mode (lighter codebase analysis). Ignored if PLAN_PATH already set. |
| `--ralph` | Use ralph loop for Step 3 instead of implement (resilient, slower) |
| `--ralph-max-iter N` | Set max ralph iterations (default: 10, max recommended: 20) |
| `--skip-review` | Set SKIP_REVIEW = true. Skip Step 6. |
| `--no-pr` | Set NO_PR = true. Skip Steps 5 and 6. |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`) |
| `--resume` | Resume from last failed step using saved state |
| `--no-interact` | Never ask user questions — use best judgment, pick defaults |
| `--package <name>` | Scope to a specific monorepo package. Passed through to plan and implement steps. |
| `--dry-run` | Preview all steps without executing. Show estimated token cost. Exit after preview. |
| Remaining text | Set FEATURE = text |

**If `--prp-path` provided, validate file exists** — STOP if not found, show available plans.

**If `--skip-plan` provided (without `--prp-path`)**:
```bash
ls -t .prp-output/plans/*.plan.md 2>/dev/null | head -5
```
If 1 plan → use it. If multiple → ask (or pick most recent in no-interact). If none → STOP.

**Set workflow variables:**
```
FEATURE = "{remaining text after flags, or title from plan file}"
PLAN_PATH = "{from --prp-path, or TBD — set in Step 2}"
BRANCH = "{TBD — set in Step 1}"
PR_NUMBER = "{TBD — set in Step 5}"
REVIEW_ARTIFACT = "{TBD — set in Step 6.1}"
USE_RALPH = {true if --ralph}
RALPH_MAX_ITER = {N, default 10}
SKIP_REVIEW = {true if --skip-review or --no-pr}
NO_PR = {true if --no-pr}
FIX_SEVERITY = "{from --fix-severity, default 'critical,high,medium,suggestion'}"
FAST_PLAN = {true if --fast} (ignored if PLAN_PATH already set)
NO_INTERACT = {true if --no-interact}
MONOREPO_PACKAGE = "{from --package, or empty}"
DRY_RUN = {true if --dry-run}
```

### Dry-Run Preview

**If `DRY_RUN = true`** — print preview and exit immediately:

```
DRY RUN — No changes will be made

Feature: {FEATURE}
Mode:    {ralph (loop up to N iter) | default implement}

Steps that would run:
  Step 1: Create branch        -> feature/{slug}
  Step 2: Create plan          -> {skipped | .prp-output/plans/{slug}-{TIMESTAMP}.plan.md (--fast if applicable)}
  Step 3: Implement            -> {/prp-core:prp-ralph (loop up to N iter) | /prp-core:prp-implement (single pass)}
  Step 4: Commit               -> conventional commit on feature branch
  Step 5: Create PR            -> {skipped (--no-pr) | PR to main}
  Step 6: Review & Fix         -> {skipped (--skip-review) | review + review-fix}

Estimated token cost:
  Plan:      {~0K (skipped) | ~5-10K (fast) | ~10-20K (full)}
  Implement: {~15K x N iterations (ralph) | ~15-30K (single pass)}
  Commit:    ~2K tokens
  PR:        ~3K tokens
  Review:    ~15-30K tokens (with pre-generated context optimization)
  Total:     {estimated range}

Artifacts that would be created:
  .prp-output/plans/        -> implementation plan
  .prp-output/reports/      -> implementation report
  .prp-output/reviews/      -> pr-context + review report

To execute: remove --dry-run and re-run the same command.
```

**Then STOP — do not proceed.**

### Ralph Hook Check (if --ralph)

If `--ralph` flag detected, verify ralph stop hook is registered:
```bash
test -f .claude/hooks/prp-ralph-stop.sh && echo "FOUND" || echo "NOT_FOUND"
```

If not found → STOP: "Run `cd .prp && ./scripts/install.sh` to register ralph hook."

**Token warning (ralph mode):**
```
Ralph mode enabled — uses significantly more tokens than default implement.
Estimated: {N} iterations x ~15K tokens = ~{N*15}K tokens for implement step alone.
Default implement: ~15-30K tokens total.
```

---

## Step 0.5: INITIALIZE STATE

**Generate unified timestamp:**
```bash
RUN_TIMESTAMP=$(date +%Y%m%d-%H%M)
```

**Check for concurrent execution:**

```bash
LOCK_FILE=".claude/prp-run-all.lock"
if [ -f "$LOCK_FILE" ]; then
  # Check if lock is stale (older than 2 hours)
  LOCK_AGE=$(( $(date +%s) - $(stat -c "%Y" "$LOCK_FILE" 2>/dev/null || stat -f "%m" "$LOCK_FILE" 2>/dev/null) ))
  if [ "$LOCK_AGE" -gt 7200 ]; then
    echo "STALE_LOCK"
  else
    echo "LOCKED"
  fi
else
  echo "UNLOCKED"
fi
```

| Result | Action |
|--------|--------|
| UNLOCKED | Create lock: `echo "$$" > .claude/prp-run-all.lock` → proceed |
| STALE_LOCK | Remove stale lock, create new one → proceed |
| LOCKED | STOP: "Another run-all workflow is active. Wait or delete `.claude/prp-run-all.lock` to force." |

**Check for existing state file:**

| State File | `--resume`? | Action |
|------------|-------------|--------|
| EXISTS | Yes | Restore variables from state → skip completed steps |
| EXISTS | No + `NO_INTERACT` | Auto-delete stale state, proceed fresh |
| EXISTS | No + interactive | STOP: "Previous workflow interrupted. Use `--resume` or delete state file." |
| NOT_FOUND | Yes | STOP: "No saved state found. Start fresh." |
| NOT_FOUND | No | Create new state file → proceed |

**Create new state file** (if not resuming):

```bash
mkdir -p .claude
```

Write `.claude/prp-run-all.state.md` with YAML frontmatter:
- step, total_steps, feature, plan_path, branch, pr_number, review_artifact
- use_ralph, ralph_max_iter, fix_severity, fast_plan, skip_review, no_pr, no_interact
- started_at, updated_at
- Completed Steps table, Artifacts section, Error Log

**STATE UPDATE RULE**: After each step completes:
1. Increment `step` to next step number
2. Update `updated_at`
3. Update new variable values (plan_path, branch, pr_number, review_artifact)
4. Append completed step to table
5. Append new artifacts

---

## Workflow

Execute these steps in sequence. **Stop immediately on any failure.**

### Step 1: CREATE BRANCH (skip if RESUME_FROM > 1)

**Skip if**: already on a feature branch (not main/master).

```bash
CURRENT=$(git branch --show-current)
git checkout -b feature/{slug-from-FEATURE}
```

**Variable update**: `BRANCH = feature/{slug}`
**Failure**: dirty working dir on main → STOP, ask to stash/commit.

---

### Step 2: CREATE PLAN (skip if --prp-path or --skip-plan or RESUME_FROM > 2)

Use `/prp-core:prp-plan` with FEATURE (append `--fast` if FAST_PLAN, `--no-interact` if NO_INTERACT, `--package {MONOREPO_PACKAGE}` if set).

This will: analyze codebase (lighter if --fast), generate plan with validation commands, integration points, confidence score. Save to `.prp-output/plans/`.

**Variable update**: `PLAN_PATH = {generated plan path}`
**Failure** → STOP.

**DO NOT**: Read plan skill and execute logic yourself, analyze codebase directly.
**CHECKPOINT**: Did you invoke `/prp-core:prp-plan`? If not → STOP → invoke it.

---

### Step 3: IMPLEMENT (skip if RESUME_FROM > 3)

**Choose path based on `USE_RALPH`:**

#### 3A: Default Mode (USE_RALPH = false)

Use `/prp-core:prp-implement` with PLAN_PATH.

This will: detect toolchain, execute plan, validate (typecheck, lint, test, build), write report (timestamp), generate review context (`pr-context-{branch}.md` — even on early failure), archive plan (GATE).

**Wait for completion** — this is the longest step.

#### 3B: Ralph Mode (USE_RALPH = true)

Use `/prp-core:prp-ralph` with `{PLAN_PATH} --max-iterations {RALPH_MAX_ITER}`.

This will: loop iteratively until ALL validations pass, self-fix failures, write report, generate review context, archive plan.

**Failure** → STOP, report which task/validation failed.

**DO NOT**: Read implement/ralph skill and execute logic yourself, write code directly.
**CHECKPOINT**: Did you invoke `/prp-core:prp-implement` or `/prp-core:prp-ralph`? If not → STOP → invoke it.
**TRANSITION**: Implement succeeded → **immediately proceed to Step 3.1**.

#### 3.1 Verify Artifacts

After implement completes, check:
```bash
ls -la .prp-output/reports/*-report*.md 2>/dev/null
ls -la .prp-output/reviews/pr-context-*.md 2>/dev/null
```

Set: `REPORT_PATH`, `CONTEXT_PATH`

#### 3.2 Fallback: Create Missing Artifacts

**If report missing**, create minimal report with:
- Plan reference, branch, date, status
- Files changed from `git diff --name-only origin/main...HEAD`
- Validation command reminders

Save to: `.prp-output/reports/{plan-slug}-report-{RUN_TIMESTAMP}.md`

**If pr-context missing**, create minimal context with:
- Branch name
- Files changed from `git diff --name-only origin/main...HEAD`
- Note: "Context was not pre-generated. Review will need to analyze files directly."

Save to: `.prp-output/reviews/pr-context-{BRANCH}.md`

---

### Step 4: COMMIT (skip if RESUME_FROM > 4)

Use `/prp-core:prp-commit`.

**Failure**: pre-commit hook → fix and retry.

**DO NOT**: Run git add/commit directly, manually stage files.
**CHECKPOINT**: Did you invoke `/prp-core:prp-commit`? If not → STOP → invoke it.
**TRANSITION**: Commit succeeded → **immediately proceed to Step 5** (or Step 7 if NO_PR).

---

### Step 5: CREATE PR (skip if NO_PR or RESUME_FROM > 5)

Use `/prp-core:prp-pr` (pass `--no-interact` if NO_INTERACT).

**Variable update**: `PR_NUMBER = {created PR number}`
**Failure** → STOP.

**DO NOT**: Run gh pr create directly, manually craft PR body.
**CHECKPOINT**: Did you invoke `/prp-core:prp-pr`? If not → STOP → invoke it.
**TRANSITION**: PR created → **immediately proceed to Step 6** (or Step 7 if SKIP_REVIEW).

---

### Step 6: REVIEW & FIX (skip if SKIP_REVIEW or NO_PR or RESUME_FROM > 6)

Set: `REVIEW_CYCLE = 1`, `MAX_CYCLES = 2`

#### 6.1 Run Review

Use `/prp-core:prp-review` with PR_NUMBER. If `.prp-output/reviews/pr-context-{BRANCH}.md` exists, pass `--context` flag for token optimization.

**Variable update**: `REVIEW_ARTIFACT = .prp-output/reviews/pr-{PR_NUMBER}-review-claude-code.md`

**DO NOT**: Read code and review it yourself, skip the skill.
**CHECKPOINT**: Did you invoke `/prp-core:prp-review`? If not → STOP → invoke it.

#### 6.2 Evaluate Results

Check for issues matching `FIX_SEVERITY` (default: all levels):

| Result | Action |
|--------|--------|
| No issues matching FIX_SEVERITY | → Step 7 ✓ |
| Issues found + `REVIEW_CYCLE <= MAX_CYCLES` | → Step 6.3 |
| Issues found + `REVIEW_CYCLE > MAX_CYCLES` | Report remaining issues → Step 7 (NEEDS MANUAL FIXES) |

#### 6.3 Fix Issues

Use `/prp-core:prp-review-fix` with `{REVIEW_ARTIFACT} --severity {FIX_SEVERITY}`.

This will: detect toolchain, load artifact directly, fix issues by severity, validate with GATE, commit and push, post summary to PR.

**DO NOT**: Manually read and fix issues yourself, run validation separately.
**CHECKPOINT**: Did you invoke `/prp-core:prp-review-fix`? If not → STOP → invoke it.

#### 6.4 Re-verify

Increment: `REVIEW_CYCLE += 1`

Re-run review to confirm fixes resolved issues and no regressions introduced:

Use `/prp-core:prp-review` with `{PR_NUMBER} --since-last-review` for **incremental review** (only reviews changes since last review — saves tokens).

If `--since-last-review` not supported or fails, fall back to full review with `--context` flag.

→ **Return to Step 6.2** to evaluate results.

---

### Step 7: SUMMARY REPORT

**Cleanup state:**
```bash
rm -f .claude/prp-run-all.state.md
rm -f .claude/prp-run-all.lock
```

Generate final report:

```markdown
## PRP Workflow Complete

**Feature**: {FEATURE}
**Branch**: {BRANCH}
**Status**: {Complete | Needs Manual Fixes}

### Steps Executed

| Step | Command | Result |
|------|---------|--------|
| Plan | /prp-core:prp-plan | {path or "skipped"} |
| Implement | {/prp-core:prp-implement or /prp-core:prp-ralph} | {tasks completed} |
| Commit | /prp-core:prp-commit | {commit hash} |
| PR | /prp-core:prp-pr | {PR URL or "skipped"} |
| Review | /prp-core:prp-review | {verdict} |
| Review Fix | /prp-core:prp-review-fix | {N fixed, N skipped or "not needed"} |
| Re-verify | /prp-core:prp-review | {final verdict or "not needed"} |

### Artifacts

- Plan: `{PLAN_PATH}` (archived to `.prp-output/plans/completed/`)
- Report: `.prp-output/reports/{name}-report-{RUN_TIMESTAMP}.md`
- Review Context: `.prp-output/reviews/pr-context-{BRANCH}.md`
- Review: `.prp-output/reviews/pr-{PR_NUMBER}-review-claude-code.md`
- Fix Summary: `.prp-output/reviews/pr-{PR_NUMBER}-fix-summary-*.md` (if fixes applied)
- PR: {URL}

### Review Verdict

{READY TO MERGE / NEEDS MANUAL FIXES / NOT REVIEWED}

{If NEEDS MANUAL FIXES: list remaining critical/high issues}

### Next Steps

1. {Based on review verdict}
2. Merge when approved
```

---

## Critical Rules

1. **Delegate, don't duplicate** — each skill handles its own logic. Do NOT re-implement.
2. **Verify artifacts after implement** — check report and pr-context files exist, use fallback if missing.
3. **Stop on failure** — never continue with broken state.
4. **Pass context forward** — information flows from earlier to later steps. Pass `--context` to review.
5. **No extra validation** — each skill validates its own output. Adding more wastes tokens.
6. **One commit per implementation** — review fixes committed separately by `/prp-core:prp-review-fix`.
7. **Max 2 review cycles** — if still critical after 2 fix-and-re-verify cycles, STOP and report.
8. **Re-verify after fix** — always re-run `/prp-core:prp-review` after fix. Use `--since-last-review` for token optimization.
9. **No-interact means ZERO questions** — when `NO_INTERACT = true`: NEVER ask user questions. Make autonomous decisions, pick defaults. Pass `--no-interact` to sub-commands.
10. **State management** — update state file after every step. Delete on completion. Support `--resume`.

---

## Token Budget

### Default Mode (without --ralph)

| Step | Token Cost | Notes |
|------|-----------|-------|
| Plan | ~10-20K | Codebase analysis (5-10K if --fast) |
| Implement | ~15-30K | Code writing + validation |
| Commit | ~2K | Small command |
| PR | ~3K | Small command |
| Review | ~15-30K | **Low** with pre-generated context (without: ~80-150K) |
| Review Fix | ~5-10K | If issues found |
| Re-verify | ~10-15K | **Low** with `--since-last-review` (incremental) |
| **Total** | ~45-85K | ~40% less than without optimization |

### Ralph Mode (with --ralph)

| Step | Token Cost | Notes |
|------|-----------|-------|
| Plan | ~10-20K | Same as default |
| Implement (ralph) | ~15K × N iter | Very high — N iterations |
| Commit | ~2K | Same |
| PR | ~3K | Same |
| Review | ~15-30K | Same optimization |
| **Total** | ~{50 + 15*N}K | Use for complex features with uncertain impl |

---

## Usage Examples

```
/prp-core:prp-run-all Add JWT auth                             # Full workflow
/prp-core:prp-run-all Add JWT auth --fast                      # Fast-track plan
/prp-core:prp-run-all --prp-path plans/jwt.plan.md             # Skip plan creation
/prp-core:prp-run-all --skip-plan                              # Select from available plans
/prp-core:prp-run-all Add JWT auth --ralph                     # Ralph autonomous loop
/prp-core:prp-run-all Add JWT auth --ralph --ralph-max-iter 5  # Ralph with 5 iterations
/prp-core:prp-run-all Add JWT auth --skip-review               # Skip review step
/prp-core:prp-run-all --prp-path plans/jwt.plan.md --no-pr     # Implement + commit only
/prp-core:prp-run-all Add JWT auth --no-interact               # Fully autonomous
/prp-core:prp-run-all Add JWT auth --dry-run                   # Preview without executing
/prp-core:prp-run-all --resume                                 # Resume from last failure
/prp-core:prp-run-all Add JWT auth --fix-severity critical,high # Fix only blocking issues
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| Plan step succeeds but implement fails partway | STOP — implement generates partial report + pr-context before stopping. Use `--resume` to continue after fixing. |
| Branch already exists from prior aborted run | Use existing branch if on it, or switch to it. State file tracks which branch. |
| State file exists but `--resume` not passed | Interactive: warn and ask. `--no-interact`: auto-delete stale state, start fresh. |
| Lock file exists (concurrent run) | Check age — if >2 hours, treat as stale and remove. Otherwise STOP. |
| Review finds no issues | Skip review-fix, proceed directly to summary. |
| All review-fix issues skipped | Report skipped issues in summary. Still counts as "reviewed". |
| `--ralph` but hook not registered | STOP with install instructions. |
| Disk full during state write | STOP — state may be corrupted. Delete state file and restart. |
| PR creation fails (auth/permission) | STOP — commit is safe on branch. User can manually create PR. |

---

## Success Criteria

- PLAN_CREATED: Plan exists and is valid
- CODE_IMPLEMENTED: All tasks complete, validation passing (including coverage >= 90%)
- REPORT_EXISTS: Implementation report exists (created or fallback)
- CONTEXT_GENERATED: Review context file exists (created or fallback)
- CONTEXT_PASSED: Review context passed to review via `--context` flag
- COMMITTED: Clean commit on feature branch
- PR_CREATED: PR exists (unless --no-pr)
- REVIEWED: Review posted with verdict (unless --skip-review)
- INCREMENTAL_REVIEW: Re-verify uses `--since-last-review` for token optimization
- STATE_CLEANED: State and lock files deleted after completion
- SUMMARY_REPORTED: User has clear next steps

</process>

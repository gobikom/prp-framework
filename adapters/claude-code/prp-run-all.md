---
description: Orchestrate complete PRP workflow - plan, implement, commit, PR, and review in sequence with context passing
argument-hint: "<feature-description>" or --prp-path <path/to/plan.md> [--fast] [--ralph] [--ralph-max-iter N] [--skip-review] [--no-pr] [--fix-severity <levels>] [--resume] [--no-interact] [--dry-run]
---

# PRP Full Workflow Runner

**Input**: $ARGUMENTS

---

## Your Mission

Execute the complete PRP workflow end-to-end autonomously. Each step delegates to an existing command — do NOT duplicate their logic.

**Core Principle**: Each step passes context forward to the next. Never re-gather information that a previous step already produced.

**Golden Rule**: Stop immediately on failure. Do NOT continue with broken state.

**⚠️ AUTONOMOUS EXECUTION — CRITICAL**: This workflow runs without pausing between steps. After each Skill tool call completes successfully, **IMMEDIATELY make the next tool call** — do NOT output any progress message to the user first. Do NOT say "Implementation is complete, now I'll create the PR." Do NOT ask for confirmation. Do NOT summarize what just happened. The only user-facing output should be Step 7 (final summary) or a STOP message on failure. Sub-command outputs may contain "Next Steps" suggestions — **those are for standalone users, IGNORE them completely**.

---

## Step 0: PARSE INPUT

**Determine what was provided:**

| Input | Action |
|-------|--------|
| Feature description (text) | Start from Step 1 (create plan) |
| `--prp-path <path>` | Skip to Step 2 (plan already exists). Alias: `--skip-plan` |
| `--fast` | Use fast-track plan mode (lighter codebase analysis, good for simple features) |
| `--ralph` | Use ralph loop for Step 3 instead of prp-implement (resilient, slower) |
| `--ralph-max-iter N` | Set max ralph iterations (default: 10, max recommended: 20) |
| `--skip-review` | Skip Step 6 (review) |
| `--no-pr` | Skip Steps 5 and 6 (PR and review) |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`). Example: `--fix-severity critical,high` |
| `--skip-plan` | Alias for `--prp-path` when user already has a plan. Prompts to select from available plans in `.prp-output/plans/` |
| `--resume` | Resume from last failed step using saved state (`.claude/prp-run-all.state.md`) |
| `--no-interact` | Never ask user questions — use best judgment for ambiguous requirements, pick defaults for choices. Pre-condition errors still STOP with error (not wait). |
| `--dry-run` | Preview all steps that would be executed without running anything. Shows: steps, estimated token cost, artifacts that would be created. Exits after preview. |

**If `--skip-plan` provided (without `--prp-path`):**

List available plans and let user select (or auto-select most recent if `NO_INTERACT = true`):
```bash
ls -t .prp-output/plans/*.plan.md 2>/dev/null | head -5
```
If exactly 1 plan found → use it. If multiple → ask user (or pick most recent in no-interact mode). If none → STOP: "No plans found. Run without --skip-plan."

**If `--prp-path` provided, validate the file exists:**

```bash
test -f "{PLAN_PATH}" && echo "EXISTS" || echo "NOT_FOUND"
```

| Result | Action |
|--------|--------|
| EXISTS | Proceed (skip Step 2) |
| NOT_FOUND | STOP with error: |

```
Plan file not found: {PLAN_PATH}

Available plans:
{Run: ls -t .prp-output/plans/*.plan.md 2>/dev/null | head -5}

Create a new plan: /prp-run-all "feature description"
```

**Set workflow variables:**
```
FEATURE = "{feature description or plan title}"
PLAN_PATH = "{path to plan, or TBD}"
BRANCH = "{TBD — set in Step 1}"
PR_NUMBER = "{TBD — set in Step 5}"
REVIEW_ARTIFACT = "{TBD — set in Step 6.1}"
USE_RALPH = {true | false}
RALPH_MAX_ITER = {N, default 10}
FIX_SEVERITY = "{from --fix-severity, default 'critical,high,medium,suggestion'}"
FAST_PLAN = {true | false} (ignored if PLAN_PATH is already set — Step 2 will be skipped)
NO_INTERACT = {true | false}
DRY_RUN = {true | false}
```

**If `DRY_RUN = true` — print preview and exit immediately:**

```
🔍 DRY RUN — No changes will be made
═══════════════════════════════════════════════════════════

Feature: {FEATURE}
Mode:    {--ralph if USE_RALPH else "default implement"}

Steps that would run:
  ┌─ Step 1: Create branch        → feature/{slug}
  ├─ Step 2: Create plan          → {"skipped (--skip-plan/--prp-path)" if PLAN_PATH else ".prp-output/plans/{slug}-{TIMESTAMP}.plan.md" + (" (--fast mode)" if FAST_PLAN else "")}
  ├─ Step 3: Implement            → {"/prp-ralph (loop up to N iter)" if USE_RALPH else "/prp-implement (single pass)"}
  ├─ Step 4: Commit               → conventional commit on feature branch
  ├─ Step 5: Create PR            → {"skipped (--no-pr)" if NO_PR else "PR to main"}
  └─ Step 6: Review & Fix         → {"skipped (--skip-review)" if SKIP_REVIEW else "review-agents + review-fix"}

Estimated token cost:
  Plan:      {"~0K tokens        (skipped)" if PLAN_PATH else ("~5-10K tokens    (fast-track)" if FAST_PLAN else "~10-20K tokens    (codebase analysis)")}
  Implement: {"~15K × " + RALPH_MAX_ITER + " iterations = ~" + (15*RALPH_MAX_ITER) + "K tokens (ralph mode)" if USE_RALPH else "~15-30K tokens (single pass)"}
  Commit:    ~2K tokens
  PR:        ~3K tokens
  Review:    ~15-30K tokens   (with pre-generated context optimization)
  ─────────────────────────────────────────────────────────
  Total:     {"~" + (15*RALPH_MAX_ITER + 50) + "-" + (15*RALPH_MAX_ITER + 85) + "K tokens (ralph)" if USE_RALPH else "~45-85K tokens (default)"}

Artifacts that would be created:
  .prp-output/plans/        → implementation plan
  .prp-output/reports/      → implementation report
  .prp-output/reviews/      → pr-context + review report
  .claude/prp-run-all.lock  → deleted on completion

To execute: remove --dry-run and re-run the same command.
═══════════════════════════════════════════════════════════
```

**Then STOP — do not proceed to Step 0.5 or beyond.**

**If `--ralph` flag detected — verify hook is registered:**

```bash
HOOK_CHECK=$(cat .claude/settings.local.json 2>/dev/null | \
  jq -r '.hooks.Stop[]?.hooks[]? | select(.command | contains("prp-ralph-stop"))' 2>/dev/null)
```

| Result | Action |
|--------|--------|
| Hook found | Proceed normally |
| Hook not found | STOP with message below |

**If hook not found:**
```
❌ --ralph requires the stop hook to be registered.

Run the PRP install script to auto-register:
  cd .prp && ./scripts/install.sh

Or add manually to .claude/settings.local.json:
  {
    "hooks": {
      "Stop": [{"hooks": [{"type": "command", "command": ".claude/hooks/prp-ralph-stop.sh"}]}]
    }
  }

Then retry with --ralph flag.
```

**Token warning (display to user when --ralph is set):**
```
⚠️  Ralph mode enabled — this uses significantly more tokens than default implement.
    Estimated: {RALPH_MAX_ITER} iterations × ~15K tokens = ~{N*15}K tokens for implement step alone.
    Default implement: ~15-30K tokens total.
```

---

## Step 0.5: INITIALIZE STATE

**Generate unified timestamp for this run:**
```bash
RUN_TIMESTAMP=$(date +%Y%m%d-%H%M)
```

**Check for concurrent execution:**

```bash
LOCK_FILE=".claude/prp-run-all.lock"
if [ -f "$LOCK_FILE" ]; then
  LOCK_TIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$LOCK_FILE" 2>/dev/null || stat -c "%y" "$LOCK_FILE" 2>/dev/null | cut -d. -f1)
  # Check if lock is stale (older than 2 hours)
  LOCK_AGE=$(( $(date +%s) - $(stat -f "%m" "$LOCK_FILE" 2>/dev/null || stat -c "%Y" "$LOCK_FILE" 2>/dev/null) ))
  if [ "$LOCK_AGE" -gt 7200 ]; then
    echo "STALE_LOCK"
  else
    echo "LOCKED at $LOCK_TIME"
  fi
else
  echo "UNLOCKED"
fi
```

| Result | Action |
|--------|--------|
| UNLOCKED | Create lock: `echo "$$" > .claude/prp-run-all.lock` → proceed |
| STALE_LOCK | Remove stale lock, create new one → proceed |
| LOCKED | STOP: "Another run-all workflow is active (started {time}). Wait for it to complete or delete `.claude/prp-run-all.lock` to force." |

**Check for existing state file:**

```bash
test -f .claude/prp-run-all.state.md && echo "EXISTS" || echo "NOT_FOUND"
```

| Result | `--resume` set? | Action |
|--------|----------------|--------|
| EXISTS | Yes | Restore variables from state file → set `RESUME_FROM` = `step` value → skip completed steps |
| EXISTS | No | Warn user and STOP: |
| NOT_FOUND | Yes | STOP with error: "No saved workflow state found. Start fresh with: /prp-run-all \"your feature description\"" |
| NOT_FOUND | No | Create new state file → proceed normally |

**If state file exists but `--resume` NOT set:**

**If `NO_INTERACT = true`**: Auto-delete stale state and proceed as fresh run:
```bash
rm -f .claude/prp-run-all.state.md
```

**If `NO_INTERACT = false`** (default):
```
A previous run-all workflow was interrupted at Step {N}: {step name}.

Options:
  1. Resume: /prp-run-all --resume
  2. Start fresh: Delete .claude/prp-run-all.state.md and re-run

To delete stale state: rm .claude/prp-run-all.state.md
```
STOP and wait for user decision.

**If `--resume` with state file:**

1. Read `.claude/prp-run-all.state.md` YAML frontmatter
2. Restore: `FEATURE`, `PLAN_PATH`, `BRANCH`, `PR_NUMBER`, `REVIEW_ARTIFACT`, `USE_RALPH`, `RALPH_MAX_ITER`, `FIX_SEVERITY`, `FAST_PLAN`, `SKIP_REVIEW`, `NO_PR`
3. Set `RESUME_FROM = step` value from state
4. Validate restored state:
   - Branch exists: `git branch --list {BRANCH}`
   - Plan file exists (if step > 2): `test -f {PLAN_PATH}`
5. Display: "Resuming run-all from Step {RESUME_FROM}: {step name}"

**Create new state file** (if not resuming):

```bash
mkdir -p .claude
```

Write `.claude/prp-run-all.state.md`:

```markdown
---
step: 1
total_steps: 7
feature: "{FEATURE}"
plan_path: ""
branch: ""
pr_number: ""
review_artifact: ""
use_ralph: {USE_RALPH}
ralph_max_iter: {RALPH_MAX_ITER}
fix_severity: "{FIX_SEVERITY}"
fast_plan: {FAST_PLAN}
skip_review: {SKIP_REVIEW}
no_pr: {NO_PR}
no_interact: {NO_INTERACT}
started_at: "{ISO timestamp}"
updated_at: "{ISO timestamp}"
---
# PRP Run-All Workflow State
## Completed Steps
| Step | Name | Result | Timestamp |
|------|------|--------|-----------|
| 0 | Parse Input | OK | {HH:MM} |
## Artifacts
(none yet)
## Error Log
(empty)
```

**STATE UPDATE RULE**: After each step completes successfully, update the state file:
1. Increment `step` to the next step number
2. Update `updated_at` to current timestamp
3. Update any new variable values (`plan_path`, `branch`, `pr_number`, `review_artifact`)
4. Append the completed step to the "Completed Steps" table
5. Append any new artifacts to the "Artifacts" section

---

## Step 1: CREATE BRANCH (skip if RESUME_FROM > 1)

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

## Step 2: CREATE PLAN (skip if --prp-path provided OR RESUME_FROM > 2)

**⚠️ MUST use Skill tool**: `/prp-plan "{FEATURE}"`

```
Use Skill tool with:
  skill: "prp-core:prp-plan"
  args: "{FEATURE}" (append " --fast" if FAST_PLAN = true) (append " --no-interact" if NO_INTERACT = true)
```

This command will:
- Analyze the codebase (lighter analysis if `--fast`)
- Generate a comprehensive plan with validation commands, integration points, confidence score
- Save to `.prp-output/plans/`
- If `--fast`: skip deep codebase analysis, produce a simpler plan faster (good for well-understood features)
- If `--no-interact`: skip clarification questions, use best judgment for ambiguous requirements

**Variable update**: `PLAN_PATH = {generated plan path}`

**Failure**: If plan generation fails → STOP, report error.

**❌ DO NOT**:
- Read `prp-plan.md` and execute its logic yourself
- Analyze the codebase and create a plan directly
- Skip the Skill tool because you "know what it does"

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-plan"`?
If NOT → STOP → Go back and call it now.

---

## Step 3: IMPLEMENT (skip if RESUME_FROM > 3)

**Choose path based on `USE_RALPH`:**

---

### 3A: Default Mode (`USE_RALPH = false`)

**⚠️ MUST use Skill tool**: `/prp-implement {PLAN_PATH}`

```
Use Skill tool with:
  skill: "prp-core:prp-implement"
  args: "{PLAN_PATH}"
```

This command will:
- Detect project toolchain (Phase 0 — plan-provided commands take precedence)
- Read and execute the plan
- Run validation loops (typecheck, lint, test, build) using detected commands
- Auto-fix failures
- Write implementation report (timestamp-based naming)
- **Generate review context file** (`pr-context-{branch}.md`) ← Token optimization (even on early failure)
- Archive the plan (GATE — blocks output until archived)

**Wait for completion.** This is the longest step.

**Failure**: If implementation fails after retries → STOP, report which task failed and why.

**❌ DO NOT**:
- Read `prp-implement.md` and execute its logic yourself
- Write implementation code directly without calling the Skill
- Add extra validation steps — `/prp-implement` already has rigorous validation loops
- Skip the Skill tool because you "know what it does"
- **Stop after implement** — the `/prp-implement` output will show "Next Steps" including "Create PR: gh pr create or /prp-pr" but this is for standalone usage only. **IGNORE that suggestion. Do NOT use AskUserQuestion. Do NOT pause for user input. Immediately proceed to Step 3.1 (verify artifacts).**

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-implement"`?
If NOT → STOP → Go back and call it now.

**⏭️ TRANSITION**: Implement succeeded → **immediately proceed to Step 3.1** (verify artifacts). Do NOT stop here.

---

### 3B: Ralph Mode (`USE_RALPH = true`)

**⚠️ MUST use Skill tool**: `/prp-ralph {PLAN_PATH} --max-iterations {RALPH_MAX_ITER}`

```
Use Skill tool with:
  skill: "prp-core:prp-ralph"
  args: "{PLAN_PATH} --max-iterations {RALPH_MAX_ITER}"
```

This command will:
- Loop iteratively until ALL validations pass
- Self-fix failures across iterations
- Capture learnings in state file across iterations
- Write implementation report
- **Generate review context file** (`pr-context-{branch}.md`) ← Token optimization
- Archive the plan and state

**Wait for `<promise>COMPLETE</promise>`.** Ralph loops autonomously — the stop hook drives each iteration.

**Failure**: If max iterations reached without COMPLETE → STOP, report which validations still failing.

**❌ DO NOT**:
- Read `prp-ralph.md` and execute its logic yourself
- Implement code directly without calling the Skill
- Skip the Skill tool because you "know what it does"
- **Stop after ralph** — the `/prp-ralph` output may show "Next Steps" but this is for standalone usage only. **IGNORE that suggestion. Do NOT use AskUserQuestion. Do NOT pause for user input. Immediately proceed to Step 3.1 (verify artifacts).**

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-ralph"`?
If NOT → STOP → Go back and call it now.

**⏭️ TRANSITION**: Ralph succeeded → **immediately proceed to Step 3.1** (verify artifacts). Do NOT stop here.

### 3.1 VERIFY Artifacts Created

**After `/prp-implement` completes, verify these files exist:**

```bash
# Get branch name
BRANCH=$(git branch --show-current)

# Check for report (find the most recent one)
ls -la .prp-output/reports/*-report*.md 2>/dev/null

# Check for review context
ls -la .prp-output/reviews/pr-context-*.md 2>/dev/null
```

**Set variables from verification:**
```
REPORT_PATH = {path to report file}
CONTEXT_PATH = {path to pr-context file}
```

### 3.2 FALLBACK: Create Missing Artifacts

**If report is missing**, create a minimal report:

```markdown
# Implementation Report (Fallback)

**Plan**: `{PLAN_PATH}`
**Branch**: `{BRANCH}`
**Date**: {YYYY-MM-DD}
**Status**: COMPLETE (via run-all)

---

## Summary

Implementation completed via `/prp-run-all` workflow.
Detailed report was not generated by `/prp-implement`.

---

## Files Changed

{Run: git diff --name-only origin/main...HEAD}

---

## Validation

Run validation commands to verify:
- `{runner} run type-check`
- `{runner} run lint`
- `{runner} run test`
- `{runner} run build`
```

Save to: `.prp-output/reports/{plan-slug}-report-{RUN_TIMESTAMP}.md`

**If pr-context is missing**, create a minimal context:

```markdown
# PR Review Context (Fallback)

**Branch**: `{BRANCH}`
**Generated**: {YYYY-MM-DD HH:MM}

---

## Files Changed

{Run: git diff --name-only origin/main...HEAD}

---

## Review Notes

Context was not pre-generated. Review agents will need to analyze files directly.
```

Save to: `.prp-output/reviews/pr-context-{BRANCH}.md`

**Context passed forward**:
- Implementation report at `.prp-output/reports/`
- Review context file at `.prp-output/reviews/pr-context-{BRANCH}.md`
- Validated code on feature branch

---

## Step 4: COMMIT (skip if RESUME_FROM > 4)

**⚠️ MUST use Skill tool**: `/prp-commit`

```
Use Skill tool with:
  skill: "prp-core:prp-commit"
  args: "--no-interact"
```

This command will:
- Stage relevant files
- Generate meaningful commit message
- Commit with Co-Authored-By

**Failure**: If commit fails (pre-commit hooks) → fix and retry (the command handles this).

**❌ DO NOT**:
- Run `git add` and `git commit` directly
- Manually stage files or write commit messages
- Skip the Skill tool because committing "seems simple"
- **Stop after commit** — the `/prp-commit` output will suggest "Next: git push or /prp-pr" but this is for standalone usage only. **IGNORE that suggestion. Do NOT use AskUserQuestion. Do NOT pause for user input. Immediately call the Skill tool for Step 5.**

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-commit"`?
If NOT → STOP → Go back and call it now.

**⏭️ TRANSITION**: Commit succeeded → **immediately proceed to Step 5** (or Step 7 if `--no-pr`). Do NOT stop here.

---

## Step 5: CREATE PR (skip if --no-pr OR RESUME_FROM > 5)

**⚠️ MUST use Skill tool**: `/prp-pr`

```
Use Skill tool with:
  skill: "prp-core:prp-pr"
  args: "--no-interact"
```

This command will:
- Push branch to remote
- Create PR with summary, test plan, and description
- Return PR URL

**Variable update**: `PR_NUMBER = {created PR number}`

**Failure**: If PR creation fails → STOP, report error (usually auth or branch issue).

**❌ DO NOT**:
- Run `gh pr create` directly
- Manually craft PR title or body
- Skip the Skill tool because PR creation "seems simple"

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-pr"`?
If NOT → STOP → Go back and call it now.

**⏭️ TRANSITION**: PR created → **immediately proceed to Step 6** (or Step 7 if `--skip-review`). Do NOT stop here. The `/prp-pr` output will suggest "Next Steps" like "Wait for CI checks" or "Request review" — these are for standalone usage only. **IGNORE those suggestions and proceed to the next step.**

---

## Step 6: REVIEW (skip if --skip-review or --no-pr OR RESUME_FROM > 6)

**Loop variables:**
```
REVIEW_CYCLE = 1
MAX_CYCLES = 2
```

### 6.1 Run Review

**⚠️ MUST use Skill tool**: `/prp-review-agents {PR_NUMBER}`

```
Use Skill tool with:
  skill: "prp-core:prp-review-agents"
  args: "{PR_NUMBER} --context .prp-output/reviews/pr-context-{BRANCH}.md"
```

This command will:
- **Detect pre-generated context file** via `--context` path → skip expensive context extraction
- Run applicable specialist agents (code, docs, tests, errors, types)
- Post review summary to PR

**Token optimization**: Because `/prp-implement` already generated `pr-context-{BRANCH}.md` and we pass it explicitly via `--context`, the review agents will:
- NOT re-fetch PR diff (file list from context)
- NOT re-run validation (status from context)
- Only read targeted files per agent domain

**Variable update after review**: `REVIEW_ARTIFACT = .prp-output/reviews/pr-{PR_NUMBER}-agents-review.md`

**❌ DO NOT**:
- Read code files and review them yourself
- Run review agents logic directly
- Skip the Skill tool because you "can review code"

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-review-agents"`?
If NOT → STOP → Go back and call it now.

### 6.2 Evaluate Results

**Issues to check**: any issues matching `FIX_SEVERITY` (default: critical, high, medium, suggestion — all levels).

| Result | Action |
|--------|--------|
| No issues matching FIX_SEVERITY found | Proceed to Step 7 ✓ |
| Issues matching FIX_SEVERITY found, `REVIEW_CYCLE <= MAX_CYCLES` | Go to Step 6.3 |
| Issues matching FIX_SEVERITY found, `REVIEW_CYCLE > MAX_CYCLES` | Report remaining issues → Proceed to Step 7 with status NEEDS MANUAL FIXES |

### 6.3 Fix Issues

**⚠️ MUST use Skill tool**: `/prp-review-fix`

Pass the review artifact path directly (bypasses interactive selection) with severity from `FIX_SEVERITY`:

```
Use Skill tool with:
  skill: "prp-core:prp-review-fix"
  args: "{REVIEW_ARTIFACT} --severity {FIX_SEVERITY}"
```

This command will:
- Detect project toolchain (Phase 0 — branch-matching plan discovery)
- Load the review artifact directly (no discovery/selection needed)
- Fix issues matching the severity filter in priority order
- Validate after each severity batch using detected commands (GATE before push)
- Stage only modified files (safe staging — no `git add -A`)
- Commit and push fixes to the PR branch
- Save fix summary with timestamp, post to PR, update review artifact

**Default severity**: `critical,high,medium,suggestion` — fixes all issues. Override with `--severity critical,high` to fix only blocking issues.
All severity levels are fixed by default for comprehensive code quality. Use `--fix-severity` to narrow scope if needed.

**❌ DO NOT**:
- Manually read and fix issues yourself
- Run validation separately — `prp-review-fix` already validates
- Skip the Skill tool

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-review-fix"`?
If NOT → STOP → Go back and call it now.

### 6.4 Re-verify

Increment: `REVIEW_CYCLE = REVIEW_CYCLE + 1`

Re-run review to confirm fixes resolved all critical/high issues and no regressions were introduced.

**Use `--since-last-review` for incremental review** — only reviews changes since last review (saves tokens):

```
Use Skill tool with:
  skill: "prp-core:prp-review-agents"
  args: "{PR_NUMBER} --since-last-review --context .prp-output/reviews/pr-context-{BRANCH}.md"
```

If `--since-last-review` fails (e.g., no previous review artifact found), fall back to full review with `--context` only.

→ **Return to Step 6.2** to evaluate results.

**If no critical issues**: Proceed to Step 7. ✓

---

## Step 7: SUMMARY REPORT

**Cleanup state file:**

```bash
rm -f .claude/prp-run-all.state.md
rm -f .claude/prp-run-all.lock
```

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
| Review | /prp-review-agents | {verdict} |
| Review Fix | /prp-review-fix | {N fixed, N skipped or "not needed"} |
| Re-verify | /prp-review-agents | {final verdict or "not needed"} |

### Artifacts

- Plan: `{PLAN_PATH}` (archived to `.prp-output/plans/completed/`)
- Report: `.prp-output/reports/{name}-report-{RUN_TIMESTAMP}.md`
- Review Context: `.prp-output/reviews/pr-context-{BRANCH}.md`
- Review: `.prp-output/reviews/pr-{PR_NUMBER}-agents-review.md`
- Fix Summary: `.prp-output/reviews/pr-{PR_NUMBER}-fix-summary-*.md` (if fixes applied — timestamp set by prp-review-fix)
- PR: {URL}

### Review Verdict

{READY TO MERGE / NEEDS MANUAL FIXES / NOT REVIEWED}

{If NEEDS MANUAL FIXES: list remaining critical/high issues that were skipped}

### Next Steps

1. {Based on review verdict}
2. Merge when approved
```

---

## Critical Rules

1. **⚠️ ALWAYS use Skill tool.** You MUST invoke each `/prp-*` command using the Skill tool. Do NOT inline or re-implement their logic. This is the most important rule.

2. **Delegate, don't duplicate.** Each `/prp-*` command is self-contained. Do NOT re-implement their logic in this workflow. Just invoke them via Skill tool in sequence.

3. **Verify artifacts after implement.** After `/prp-implement` or `/prp-ralph` completes, always check that report and pr-context files were created. Use fallback creation if missing.

4. **Stop on failure.** If any step fails after its own retry logic, STOP the entire workflow. Do NOT skip to the next step.

5. **Pass context forward.** The review context file from `/prp-implement` or `/prp-ralph` is passed to `/prp-review-agents` via `--context` flag. Do NOT re-generate it (unless missing).

6. **No extra validation.** Do NOT add validation steps between commands. Each command validates its own output. Adding more just wastes tokens.

7. **One commit per implementation.** Use `/prp-commit` once after implement. Review fixes are committed separately by `/prp-review-fix`.

8. **Max 2 review cycles.** If critical/high issues remain after 2 fix-and-re-verify cycles, STOP and report to user. Do NOT loop indefinitely.

9. **Re-verify after fix.** Always re-run `/prp-review-agents` after `/prp-review-fix` to confirm issues are resolved and no regressions were introduced. This is the quality gate before merge.

10. **No-interact means ZERO questions.** When `NO_INTERACT = true`: you MUST NOT use AskUserQuestion tool at ANY point during this workflow. Make autonomous decisions for every step. Pick defaults, use best judgment, state assumptions — but NEVER pause to ask the user. This applies to ALL steps, not just the plan step.

---

## Token Budget

### Default Mode (without --ralph)

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

### Ralph Mode (with --ralph)

| Step | Token Cost | Why |
|------|-----------|-----|
| Plan | Moderate | Same as default |
| Implement (ralph) | **Very High** | N iterations × ~15K tokens each |
| Commit | Low | Same as default |
| PR | Low | Same as default |
| Review | **Low** (with context file) | Ralph generates pr-context — same optimization |
| **Total** | 3-10× more than default | Use only for complex features with uncertain impl |

**When to use --ralph**: feature is complex, first-pass implementation likely to fail validation, or you want autonomous retry without manual intervention.

---

## Success Criteria

- **SKILL_TOOL_USED**: All `/prp-*` commands invoked via Skill tool (not inlined)
- **PLAN_CREATED**: Plan exists and is valid
- **CODE_IMPLEMENTED**: All tasks complete, validation passing (including coverage >= 90%)
- **REPORT_EXISTS**: Implementation report exists at `.prp-output/reports/` (created or fallback)
- **CONTEXT_GENERATED**: Review context file exists at `.prp-output/reviews/` (created or fallback)
- **CONTEXT_PASSED**: Review context file passed to review-agents via `--context` flag
- **COMMITTED**: Clean commit on feature branch
- **PR_CREATED**: PR exists on GitHub (unless --no-pr)
- **REVIEWED**: Review posted with verdict (unless --skip-review)
- **INCREMENTAL_REVIEW**: Re-verify uses `--since-last-review` for token optimization
- **STATE_CLEANED**: `.claude/prp-run-all.state.md` and `.claude/prp-run-all.lock` deleted after completion
- **SUMMARY_REPORTED**: User has clear next steps

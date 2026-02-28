---
description: Orchestrate complete PRP workflow - plan, implement, commit, PR, and review in sequence with context passing
argument-hint: "<feature-description>" or --prp-path <path/to/plan.md> [--ralph] [--ralph-max-iter N] [--skip-review] [--no-pr] [--fix-severity <levels>] [--resume] [--no-interact]
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
| `--ralph` | Use ralph loop for Step 3 instead of prp-implement (resilient, slower) |
| `--ralph-max-iter N` | Set max ralph iterations (default: 10, max recommended: 20) |
| `--skip-review` | Skip Step 6 (review) |
| `--no-pr` | Skip Steps 5 and 6 (PR and review) |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`). Example: `--fix-severity critical,high` |
| `--resume` | Resume from last failed step using saved state (`.claude/prp-run-all.state.md`) |
| `--no-interact` | Never ask user questions — use best judgment for ambiguous requirements, pick defaults for choices. Pre-condition errors still STOP with error (not wait). |

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
NO_INTERACT = {true | false}
```

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
2. Restore: `FEATURE`, `PLAN_PATH`, `BRANCH`, `PR_NUMBER`, `REVIEW_ARTIFACT`, `USE_RALPH`, `RALPH_MAX_ITER`, `FIX_SEVERITY`, `SKIP_REVIEW`, `NO_PR`
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
  args: "{FEATURE}" (append " --no-interact" if NO_INTERACT = true)
```

This command will:
- Analyze the codebase
- Generate a comprehensive plan
- Save to `.prp-output/plans/`
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
- Read and execute the plan
- Run validation loops (typecheck, lint, test, build)
- Auto-fix failures
- Write implementation report
- **Generate review context file** (`pr-context-{branch}.md`) ← Token optimization
- Archive the plan

**Wait for completion.** This is the longest step.

**Failure**: If implementation fails after retries → STOP, report which task failed and why.

**❌ DO NOT**:
- Read `prp-implement.md` and execute its logic yourself
- Write implementation code directly without calling the Skill
- Add extra validation steps — `/prp-implement` already has rigorous validation loops
- Skip the Skill tool because you "know what it does"

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-implement"`?
If NOT → STOP → Go back and call it now.

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

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-ralph"`?
If NOT → STOP → Go back and call it now.

### 3.1 VERIFY Artifacts Created

**After `/prp-implement` completes, verify these files exist:**

```bash
# Get branch name
BRANCH=$(git branch --show-current)

# Check for report (find the most recent one)
ls -la .prp-output/reports/*-report.md 2>/dev/null

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

Save to: `.prp-output/reports/{plan-slug}-report.md`

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
  args: "" (no args needed)
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
- **Stop after commit** — the `/prp-commit` output will suggest "Next: git push or /prp-pr" but this is for standalone usage only. **IGNORE that suggestion and proceed to Step 5.**

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-commit"`?
If NOT → STOP → Go back and call it now.

**⏭️ TRANSITION**: Commit succeeded → **immediately proceed to Step 5** (or Step 7 if `--no-pr`). Do NOT stop here.

---

## Step 5: CREATE PR (skip if --no-pr OR RESUME_FROM > 5)

**⚠️ MUST use Skill tool**: `/prp-pr`

```
Use Skill tool with:
  skill: "prp-core:prp-pr"
  args: "" (no args needed)
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

| Result | Action |
|--------|--------|
| No critical or high issues | Proceed to Step 7 ✓ |
| Critical/high found, `REVIEW_CYCLE <= MAX_CYCLES` | Go to Step 6.3 |
| Critical/high found, `REVIEW_CYCLE > MAX_CYCLES` | Report remaining issues → Proceed to Step 7 with status NEEDS MANUAL FIXES |

### 6.3 Fix Issues

**⚠️ MUST use Skill tool**: `/prp-review-fix`

Pass the review artifact path directly (bypasses interactive selection) with severity from `FIX_SEVERITY`:

```
Use Skill tool with:
  skill: "prp-core:prp-review-fix"
  args: "{REVIEW_ARTIFACT} --severity {FIX_SEVERITY}"
```

This command will:
- Load the review artifact directly (no discovery/selection needed)
- Fix issues matching the severity filter in priority order
- Validate after each severity batch (type-check + lint + test)
- Commit and push fixes to the PR branch
- Post fix summary comment on PR

**Default severity**: `critical,high,medium,suggestion` — fixes all issues. Override with `--fix-severity critical,high` to fix only blocking issues.
All severity levels are fixed by default for comprehensive code quality. Use `--fix-severity` to narrow scope if needed.

**❌ DO NOT**:
- Manually read and fix issues yourself
- Run validation separately — `prp-review-fix` already validates
- Skip the Skill tool

**✅ CHECKPOINT**: Did you call the Skill tool with `skill: "prp-core:prp-review-fix"`?
If NOT → STOP → Go back and call it now.

### 6.4 Re-verify

Increment: `REVIEW_CYCLE = REVIEW_CYCLE + 1`

Re-run review to confirm fixes resolved all critical/high issues and no regressions were introduced:

```
Use Skill tool with:
  skill: "prp-core:prp-review-agents"
  args: "{PR_NUMBER}"
```

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

- Plan: `{PLAN_PATH}` (archived)
- Report: `.prp-output/reports/{name}-report.md`
- Review Context: `.prp-output/reviews/pr-context-{BRANCH}.md`
- Review: `.prp-output/reviews/pr-{NUMBER}-review.md`
- Fix Summary: `.prp-output/reviews/pr-{NUMBER}-fix-summary.md` (if fixes applied)
- PR: {URL}

### Review Verdict

{READY TO MERGE / NEEDS MANUAL FIXES / NOT REVIEWED}

{If NEEDS MANUAL FIXES: list remaining critical/high issues that were skipped}

### Next Steps

1. {Based on review verdict}
2. {If medium/suggestion issues exist: "Run /prp-review-fix {NUMBER} for remaining medium/suggestion issues"}
3. Merge when approved
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
- **STATE_CLEANED**: `.claude/prp-run-all.state.md` and `.claude/prp-run-all.lock` deleted after completion
- **SUMMARY_REPORTED**: User has clear next steps

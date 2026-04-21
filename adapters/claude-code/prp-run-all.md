---
description: "Orchestrate complete PRP workflow from feature request to pull request. Run branch, plan, implement, commit, PR, review with fix loop, and summary in sequence. Use when implementing features using PRP methodology or when user requests full PRP workflow."
argument-hint: "\"<feature-description>\" or --issue <N> [--merge] [--max-review-rounds N] [--prp-path <path>] [--skip-plan] [--fast] [--ralph] [--ralph-max-iter N] [--skip-review] [--no-pr] [--fix-severity <levels>] [--resume] [--no-interact] [--dry-run]"
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
| `--review-single-agent` | Use `/prp-core:prp-review` (single agent) instead of default `/prp-core:prp-review-agents` (multi-agent). Saves tokens. |
| `--no-pr` | Set NO_PR = true. Skip Steps 5 and 6. |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`) |
| `--resume` | Resume from last failed step using saved state |
| `--no-interact` | Never ask user questions — use best judgment, pick defaults |
| `--package <name>` | Scope to a specific monorepo package. Passed through to plan and implement steps. |
| `--issue <N>` | Fetch GitHub issue #N context. Set ISSUE_NUMBER = N. Extracts title + body as FEATURE. |
| `--merge` | Auto squash-merge PR after review passes (0 issues). Set AUTO_MERGE = true. |
| `--max-review-rounds <N>` | Override max review-fix cycles (default: 5). |
| `--dry-run` | Preview all steps without executing. Show estimated token cost. Exit after preview. |
| Remaining text | Set FEATURE = text |

**If `--prp-path` provided, validate file exists** — STOP if not found, show available plans.

**If `--skip-plan` provided (without `--prp-path`)**:
```bash
ls -t .prp-output/plans/*.plan.md 2>/dev/null | head -5
```
If 1 plan → use it. If multiple → ask (or pick most recent in no-interact). If none AND no `--issue` → STOP. If none AND `--issue` is set → proceed (Step 2 will generate a stub plan).

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
REVIEW_SINGLE_AGENT = {true if --review-single-agent}
NO_PR = {true if --no-pr}
FIX_SEVERITY = "{from --fix-severity, default 'critical,high,medium,suggestion'}"
FAST_PLAN = {true if --fast} (ignored if PLAN_PATH already set)
NO_INTERACT = {true if --no-interact}
MONOREPO_PACKAGE = "{from --package, or empty}"
DRY_RUN = {true if --dry-run}
ISSUE_NUMBER = "{from --issue, or empty}"
AUTO_MERGE = {true if --merge}
MAX_CYCLES = {from --max-review-rounds, default 5}
SKIP_PLAN = {false by default — may be set by --skip-plan flag or smart plan detection in Step 0.8}
RESUME_FROM = {0 by default — set from state file's step field if --resume}
REVIEW_VERDICT = "{TBD — set in Step 6.2}"
REVIEW_CYCLE = {1 — incremented after each fix cycle in Step 6.4}
PENDING_SKIPPED = {false — set true when review-fix skips unresolved issues}
ALL_SKIPPED = {false — set true when review-fix fixes 0 and skips >0 issues}
SKIPPED_COUNT = {0 — number of skipped unresolved issues from review-fix}
```

**Flag validation** (after parsing all flags):
- If `AUTO_MERGE = true` AND (`SKIP_REVIEW = true` OR `NO_PR = true`): STOP — "`--merge` requires review to pass. Cannot use with `--skip-review` or `--no-pr`."

### Dry-Run Preview

**If `DRY_RUN = true`** — print preview and exit immediately:

```
DRY RUN — No changes will be made

Feature: {FEATURE}
Mode:    {ralph (loop up to N iter) | default implement}

Steps that would run:
  Step 0.8: Fetch issue        -> {skipped (no --issue) | gh issue view N}
  Step 1: Create branch        -> feature/{slug}
  Step 2: Create plan          -> {skipped (small issue or --skip-plan) | --fast (medium) | full (large)}
  Step 3: Implement            -> {/prp-core:prp-ralph (loop up to N iter) | /prp-core:prp-implement (single pass)}
  Step 4: Commit               -> conventional commit on feature branch
  Step 5: Create PR            -> {skipped (--no-pr) | PR to main, Fixes #N if --issue}
  Step 6: Review & Fix         -> {skipped (--skip-review) | review-fix loop (max {MAX_CYCLES} rounds, target: 0 issues)}
  Step 7: Summary              -> final report
  Step 8: Merge & Cleanup      -> {skipped (no --merge) | squash merge + cleanup}

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
LOCK_FILE=".prp-output/state/run-all.lock"
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
| UNLOCKED | Create lock: `echo "$$" > .prp-output/state/run-all.lock` → proceed |
| STALE_LOCK | Remove stale lock, create new one → proceed |
| LOCKED | STOP: "Another run-all workflow is active. Wait or delete `.prp-output/state/run-all.lock` to force." |

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
mkdir -p .prp-output/state
```

Write `.prp-output/state/run-all.state.md` using Bash heredoc with YAML frontmatter:
- step, total_steps, feature, plan_path, branch, pr_number, review_artifact, review_verdict, review_cycle
- pending_skipped, all_skipped, skipped_count
- use_ralph, ralph_max_iter, fix_severity, fast_plan, skip_plan, skip_review, no_pr, no_interact
- issue_number, auto_merge, max_cycles
- started_at, updated_at
- Completed Steps table, Artifacts section, Error Log

On `--resume`: restore ALL variables from state file, including `PENDING_SKIPPED`, `ALL_SKIPPED`, and `SKIPPED_COUNT`. Set `RESUME_FROM = step` from frontmatter.

**STATE FILE I/O RULE**: Always use **Bash with heredoc** (`cat > file << 'EOF'`) to create and update state and lock files in `.prp-output/state/`. These are machine-generated tracking files, not source code.

**STATE UPDATE RULE**: After each step completes:
1. Increment `step` to next step number
2. Update `updated_at`
3. Update new variable values (plan_path, branch, pr_number, review_artifact, review_verdict, review_cycle, pending_skipped, all_skipped, skipped_count)
4. Append completed step to table
5. Append new artifacts

---

## Workflow

Execute these steps in sequence. **Stop immediately on any failure.**

### Step 0.8: FETCH ISSUE CONTEXT (skip if no --issue)

If ISSUE_NUMBER is set:

```bash
gh issue view {ISSUE_NUMBER} --json title,body,labels,state
```

| Result | Action |
|--------|--------|
| Issue found, state=OPEN | Extract FEATURE from title. Set ISSUE_BODY from body. |
| Issue found, state=CLOSED | WARN: "Issue #{ISSUE_NUMBER} is closed. Proceeding anyway." |
| Issue not found | STOP: "Issue #{ISSUE_NUMBER} not found." |

**Smart Plan Detection** — analyze issue scope to decide whether to plan:

If `gh issue view` output cannot be parsed → STOP: "Failed to parse issue #{ISSUE_NUMBER}."
If ISSUE_BODY is empty or null → WARN: "Issue #{N} has no body — cannot score scope. Defaulting to fast plan." Set FAST_PLAN = true, SKIP_PLAN = false. Skip scoring below.

| Indicator | Score |
|-----------|-------|
| Body mentions > 3 files or paths | +1 |
| Labels include `feature`, `enhancement`, `epic` | +1 |
| Body > 500 characters | +1 |
| Body mentions architecture, refactor, migration, redesign | +1 |
| Body mentions multiple components, services, or packages | +1 |

| Total Score | Action |
|-------------|--------|
| 0-1 | Small issue — set SKIP_PLAN = true, FAST_PLAN = false |
| 2-3 | Medium issue — set SKIP_PLAN = false, FAST_PLAN = true |
| 4-5 | Large issue — set SKIP_PLAN = false, FAST_PLAN = false (full plan) |

Display: `"Issue #{N}: {title} — Scope: {small/medium/large} → {skip plan / fast plan / full plan}"`

If `--prp-path` or `--skip-plan` already provided → skip smart detection (user explicitly controls planning).

---

### Step 1: CREATE BRANCH (skip if RESUME_FROM > 1)

**Skip if**: already on a feature branch (not main/master).

```bash
CURRENT=$(git branch --show-current)
git checkout -b feature/{slug-from-FEATURE}
```

**Variable update**: `BRANCH = feature/{slug}`
**Failure**: dirty working dir on main → STOP, ask to stash/commit.

---

### Step 2: CREATE PLAN (skip if --prp-path or SKIP_PLAN or RESUME_FROM > 2)

**Skip conditions** (any of these):
- `--prp-path` provided (explicit plan)
- `--skip-plan` flag
- SKIP_PLAN = true (from smart plan detection in Step 0.8 — small issue)

If skipping and no PLAN_PATH: create a minimal stub plan file:

```markdown
---
status: pending
mode: stub
---
# {FEATURE}

## Summary
{FEATURE}. {First 500 chars of ISSUE_BODY if available.}

## Tasks
1. Implement the feature described above. Read the codebase to understand patterns, then make targeted changes.

## Validation Commands
Run project's standard validation (type-check, lint, test, build).
```

Save to `.prp-output/plans/issue-{ISSUE_NUMBER}-stub-{RUN_TIMESTAMP}.plan.md` (or `stub-{RUN_TIMESTAMP}.plan.md` if no issue).
Set PLAN_PATH to the saved file path.

If NOT skipping: Use `/prp-core:prp-plan` with FEATURE (append `--fast` if FAST_PLAN, `--no-interact` if NO_INTERACT, `--package {MONOREPO_PACKAGE}` if set).

This will: analyze codebase (lighter if --fast), generate plan with validation commands, integration points, confidence score. Save to `.prp-output/plans/`.

**Variable update**: `PLAN_PATH = {generated plan path}` (always a real file — stub plan if skipping)
**Failure** → STOP.

**DO NOT**: Read plan skill and execute logic yourself, analyze codebase directly.
**CHECKPOINT**: If not skipping, did you invoke `/prp-core:prp-plan`? If not → STOP → invoke it.

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

If ISSUE_NUMBER is set: ensure the PR body includes `Fixes #{ISSUE_NUMBER}` so the issue auto-closes on merge.

**Variable update**: `PR_NUMBER = {created PR number}`
**Failure** → STOP.

**DO NOT**: Run gh pr create directly, manually craft PR body.
**CHECKPOINT**: Did you invoke `/prp-core:prp-pr`? If not → STOP → invoke it.
**TRANSITION**: PR created → **immediately proceed to Step 6** (or Step 7 if SKIP_REVIEW).

---

### Step 6: REVIEW & FIX (skip if SKIP_REVIEW or NO_PR or RESUME_FROM > 6)

Set: `REVIEW_CYCLE = {from state file if --resume, otherwise 1}` (MAX_CYCLES already set from Step 0 — default 5)

#### 6.1 Run Review

**Choose review command based on `REVIEW_SINGLE_AGENT`:**

| REVIEW_SINGLE_AGENT | Command | Description |
|---------------------|---------|-------------|
| false (default) | `/prp-core:prp-review-agents` | Multi-agent review (specialized agents in parallel) |
| true | `/prp-core:prp-review` | Single-agent review (faster, saves tokens) |

Pass PR_NUMBER to the chosen command. If `.prp-output/reviews/pr-context-{BRANCH}.md` exists, pass `--context` flag for token optimization.

**Variable update** (depends on which review command ran):

| Command | REVIEW_ARTIFACT path |
|---------|---------------------|
| `/prp-core:prp-review-agents` | `.prp-output/reviews/pr-{PR_NUMBER}-agents-review.md` |
| `/prp-core:prp-review` | `.prp-output/reviews/pr-{PR_NUMBER}-review-claude-code.md` |

**DO NOT**: Read code and review it yourself, skip the skill.
**CHECKPOINT**: Did you invoke the review command? If not → STOP → invoke it.

#### 6.2 Evaluate Results

Check for issues matching `FIX_SEVERITY` (default: all levels):

| Result | Action |
|--------|--------|
| 0 issues (all severities) | Set REVIEW_VERDICT = "0_issues". → Step 7 ✓ (or Step 8 if AUTO_MERGE) |
| Issues found + `REVIEW_CYCLE <= MAX_CYCLES` | → Step 6.3 |
| Issues found + `REVIEW_CYCLE > MAX_CYCLES` | Report remaining issues → Step 7 (NEEDS MANUAL FIXES) |

#### 6.3 Fix Issues

Use `/prp-core:prp-review-fix` with `{REVIEW_ARTIFACT} --severity {FIX_SEVERITY}`.

This will: detect toolchain, load artifact directly, fix issues by severity, validate with GATE, commit and push, post summary to PR.

**DO NOT**: Manually read and fix issues yourself, run validation separately.
**CHECKPOINT**: Did you invoke `/prp-core:prp-review-fix`? If not → STOP → invoke it.

**Capture review-fix outcome** for Step 6.4:

| review-fix result | Set |
|-------------------|-----|
| All issues fixed (skipped_count = 0) | `PENDING_SKIPPED = false` |
| Some fixed, some skipped (skipped_count > 0) | `PENDING_SKIPPED = true`, `SKIPPED_COUNT = N` |
| All issues skipped (fixed_count = 0, skipped_count > 0) | `PENDING_SKIPPED = true`, `ALL_SKIPPED = true`, `SKIPPED_COUNT = N` |

**Zero-issues bar**: skipped issues are NOT resolved — they are deferred. Do not proceed to Step 7 as if done.

#### 6.4 Re-verify

Increment: `REVIEW_CYCLE += 1`

Re-run review to confirm fixes resolved issues and no regressions introduced.

**Re-verify always uses single-agent review** (`/prp-core:prp-review`) regardless of `REVIEW_SINGLE_AGENT` setting — multi-agent re-verify is wasteful for incremental changes.

**Re-verify mode depends on `PENDING_SKIPPED`:**

| PENDING_SKIPPED | Re-verify command | Why |
|-----------------|-------------------|-----|
| `false` (all fixed) | `/prp-core:prp-review {PR_NUMBER} --since-last-review` (incremental) | Only new code changed — delta review saves tokens |
| `true` (some/all skipped) | `/prp-core:prp-review {PR_NUMBER} --context` (FULL review) | Skipped items did NOT change code but STILL need to re-surface — incremental delta would miss them and produce false "0 issues" |

If `--since-last-review` not supported or fails, fall back to full review with `--context` flag. Display: `"WARN: --since-last-review not supported — falling back to full review (higher token cost)."`

→ **Return to Step 6.2** to evaluate results.

**Escalation guard (NEW 2026-04-17):** before returning to 6.2, if `ALL_SKIPPED = true` AND `REVIEW_CYCLE >= 2` (i.e., a post-round-1 review-fix attempt skipped every remaining issue and made no code changes), STOP the loop early:
- Do NOT loop another round — review-fix has no additional tooling to resolve these.
- Create escalation GH issue with the remaining items. Label strategy: the `[escalation]` title prefix carries the signal — add repo-appropriate labels only if they exist in the target repo (graceful fallback so different repos with different label schemes do not hard-fail the workflow):
   ```bash
   LABEL_ARGS=""
   for LABEL in "priority:P2" "bug" "help wanted"; do
     if gh label list -R "${REPO}" --json name -q ".[] | select(.name==\"$LABEL\") | .name" | grep -q .; then
       LABEL_ARGS="${LABEL_ARGS:+$LABEL_ARGS,}$LABEL"
     fi
   done
   gh issue create \
     --title "[escalation] prp-run-all: {SKIPPED_COUNT} issues need human judgment on PR #{PR_NUMBER}" \
     ${LABEL_ARGS:+--label "$LABEL_ARGS"} \
     --body "<remaining-items summary + artifact path + round count>"
   ```
- If `gh issue create` fails (auth expired, rate limit, network, missing repo permissions), write the same escalation content to `.prp-output/reviews/pr-{PR_NUMBER}-escalation-{RUN_TIMESTAMP}.md`, then STOP with: `ERROR: escalation issue creation failed — local artifact written to .prp-output/reviews/pr-{PR_NUMBER}-escalation-{RUN_TIMESTAMP}.md. File it manually before merging.`
- Set `REVIEW_VERDICT = "needs_manual_fix"`.
- Proceed to Step 7 SUMMARY, do NOT merge (even with `--merge`).

---

### Step 7: SUMMARY REPORT (skip if RESUME_FROM > 7)

Generate final report (state cleanup deferred to after Step 8).
**State update**: write `step: 7` to state file after generating report.

```markdown
## PRP Workflow Complete

**Feature**: {FEATURE}
**Issue**: {#{ISSUE_NUMBER} or "N/A"}
**Branch**: {BRANCH}
**Status**: {Complete (will merge in Step 8) | Complete | Needs Manual Fixes}

### Steps Executed

| Step | Command | Result |
|------|---------|--------|
| Issue | gh issue view | {#{N} title or "N/A"} |
| Plan | /prp-core:prp-plan | {path or "skipped (small issue)" or "skipped"} |
| Implement | {/prp-core:prp-implement or /prp-core:prp-ralph} | {tasks completed} |
| Commit | /prp-core:prp-commit | {commit hash} |
| PR | /prp-core:prp-pr | {PR URL or "skipped"} |
| Review | /prp-core:prp-review | {verdict} |
| Review Fix | /prp-core:prp-review-fix | {N fixed, N skipped or "not needed"} |
| Re-verify | /prp-core:prp-review | {final verdict or "not needed"} ({REVIEW_CYCLE}/{MAX_CYCLES} rounds) |
| Merge | gh pr merge --squash | {pending (Step 8) or "skipped (no --merge)"} |
| Cleanup | /prp-core:prp-cleanup | {pending (Step 8) or "skipped"} |

### Artifacts

- Plan: `{PLAN_PATH}` (archived to `.prp-output/plans/completed/`)
- Report: `.prp-output/reports/{name}-report-{RUN_TIMESTAMP}.md`
- Review Context: `.prp-output/reviews/pr-context-{BRANCH}.md`
- Review: `.prp-output/reviews/pr-{PR_NUMBER}-review-claude-code.md`
- Fix Summary: `.prp-output/reviews/pr-{PR_NUMBER}-fix-summary-*.md` (if fixes applied)
- PR: {URL}

### Review Verdict

{READY TO MERGE (auto-merge pending in Step 8) / READY TO MERGE / NEEDS MANUAL FIXES / NOT REVIEWED}

{If NEEDS MANUAL FIXES: list remaining critical/high issues}

### Next Steps

1. {Based on review verdict}
{If not AUTO_MERGE: "2. Merge when approved"}
{If AUTO_MERGE and REVIEW_VERDICT = "0_issues": "Proceeding to Step 8: merge + cleanup..."}
```

**TRANSITION**: If AUTO_MERGE and review verdict is 0 issues → **immediately proceed to Step 8**.

---

### Step 8: MERGE & CLEANUP (skip if not AUTO_MERGE or REVIEW_VERDICT != "0_issues")

**State update**: write `step: 8` to state file before executing 8.0. This enables `--resume` if Step 8 fails.

**Prerequisites**:
- AUTO_MERGE = true
- REVIEW_VERDICT = "0_issues"

#### 8.0 Pre-check

```bash
gh pr view {PR_NUMBER} --json state,mergeable --jq '{state: .state, mergeable: .mergeable}'
```

| Result | Action |
|--------|--------|
| state=MERGED | WARN: "PR #{PR_NUMBER} was already merged." → skip 8.1, proceed to 8.2 |
| state=OPEN, mergeable=MERGEABLE | Proceed to 8.1 |
| state=OPEN, mergeable=CONFLICTING | STOP: "Merge conflict. Resolve manually then run `--resume`." |
| state=OPEN, mergeable=UNKNOWN | Wait 5 seconds, retry once. If still UNKNOWN → STOP: "GitHub merge check pending. Re-run with `--resume`." |
| state=CLOSED | STOP: "PR was closed. Cannot merge." |

#### 8.1 Merge

```bash
gh pr merge {PR_NUMBER} --squash --delete-branch
```

> **Tip (optional, workspace-dependent)**: If `safe-merge` is in `$PATH`, prefer it — it wraps `gh pr merge` with a CI-green gate (blocks FAIL/PENDING/UNKNOWN), an audit log, AND default-on local cleanup (checkout default branch, pull, delete merged branch, prune stale remote-tracking refs). Useful on private repos where server-side branch protection is not available. It accepts all the same flags; add `--no-cleanup` to skip the local cleanup step. Example: `safe-merge {PR_NUMBER} --squash --delete-branch`. If `safe-merge` is not installed, continue to use the default `gh pr merge` command above.

| Result | Action |
|--------|--------|
| Merged successfully | Proceed to 8.2 |
| CI checks failing | STOP: "CI checks not passing. Fix before merge." |
| Permission denied | STOP: "Cannot merge — check permissions." |

#### 8.2 Cleanup

Use `/prp-core:prp-cleanup`.

This will: verify PR merged, delete local branch, switch to main, pull latest.

#### 8.3 Close Issue (if --issue)

If ISSUE_NUMBER is set, verify whether issue was auto-closed:
```bash
gh issue view {ISSUE_NUMBER} --json state --jq '.state'
```

| Result | Action |
|--------|--------|
| CLOSED | Already closed (by `Fixes #N` or manually). Skip. |
| OPEN | `gh issue close {ISSUE_NUMBER} --comment "Closed by PR #{PR_NUMBER}"` |

#### 8.4 Final Cleanup

```bash
rm -f .prp-output/state/run-all.state.md
rm -f .prp-output/state/run-all.lock
```

State and lock files are only deleted here — after merge and cleanup succeed. This ensures `--resume` works if Step 8 fails.

---

## Critical Rules

1. **Delegate, don't duplicate** — each skill handles its own logic. Do NOT re-implement.
2. **Verify artifacts after implement** — check report and pr-context files exist, use fallback if missing.
3. **Stop on failure** — never continue with broken state.
4. **Pass context forward** — information flows from earlier to later steps. Pass `--context` to review.
5. **No extra validation** — each skill validates its own output. Adding more wastes tokens.
6. **One commit per implementation** — review fixes committed separately by `/prp-core:prp-review-fix`.
7. **Max review cycles** — configurable via `--max-review-rounds` (default 5). Target is 0 issues all severities. STOP and report if exceeded.
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
/prp-core:prp-run-all --issue 87 --merge                       # Issue-driven: fetch issue → implement → review → merge
/prp-core:prp-run-all --issue 42 --merge --no-interact         # Fully autonomous issue lifecycle
/prp-core:prp-run-all --issue 100                              # Issue-driven without auto-merge
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
/prp-core:prp-run-all --issue 55 --max-review-rounds 3 --merge # Custom review rounds
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
| All review-fix issues skipped (fixed_count=0) | Do NOT proceed to summary as "done". Set `ALL_SKIPPED = true` and follow Step 6.4 Escalation Guard: after round 2 with all-skipped, create escalation GH issue + set `REVIEW_VERDICT = needs_manual_fix` + skip merge. Zero-issues target is not satisfied by "we tried review-fix and it gave up". |
| Some review-fix issues skipped | Re-verify with FULL review (`--context`, not `--since-last-review`) so skipped items re-surface in next 6.2 evaluation. See Step 6.4 table. |
| `--ralph` but hook not registered | STOP with install instructions. |
| Disk full during state write | STOP — state may be corrupted. Delete state file and restart. |
| PR creation fails (auth/permission) | STOP — commit is safe on branch. User can manually create PR. |
| `--issue N` but issue not found | STOP with clear error. |
| `--issue N` but issue is closed | WARN and proceed — user may be implementing a closed issue intentionally. |
| `--merge` but CI checks failing | STOP — do not force merge. Report CI status. |
| `--merge` but merge conflict | STOP — user must resolve conflict manually. |
| `--merge` but review has remaining issues | Skip merge, report in summary. Do NOT merge with open issues. |
| Smart plan detection says "small" but impl is complex | Plan was skipped, implement may struggle. User can re-run with `--prp-path` and explicit plan. |
| `--issue N` + `--skip-plan` | `--skip-plan` overrides smart plan detection. If no existing plan files found, falls through to stub plan generation in Step 2. To select from existing plans, ensure at least one `.plan.md` exists in `.prp-output/plans/`. |

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
- ZERO_ISSUES_TARGET: Review-fix loop continues until 0 issues (all severities in `FIX_SEVERITY`) or MAX_CYCLES reached. **Skipped issues count as remaining** — they are deferred, not resolved. Re-verify uses FULL review (not incremental) when any issues were skipped in the prior round, so skipped items re-surface in the next evaluation.
- NO_SILENT_MERGE: `--merge` only executes when `REVIEW_VERDICT = "0_issues"`. `needs_manual_fix` (MAX_CYCLES hit OR 2 rounds all-skipped) blocks merge; escalation GH issue is created instead.
- MERGED: PR squash-merged if --merge and 0 issues (unless --no-pr or --skip-review)
- CLEANED_UP: Branch deleted, main updated, issue closed if --issue
- STATE_CLEANED: State and lock files deleted after completion
- SUMMARY_REPORTED: User has clear next steps

</process>

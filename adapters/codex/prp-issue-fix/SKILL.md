---
name: prp-issue-fix
description: Implement a fix from an issue-investigate artifact — loads the plan, validates codebase state, implements changes, runs validation, creates PR, self-reviews, and archives the artifact.
metadata:
  short-description: Fix from investigation artifact
---

# PRP Issue Fix — Implement Fix from Investigation Artifact

## Input

Issue number or artifact path: `$ARGUMENTS`

Format: `<issue-number|artifact-path>`

## Mission

Execute the implementation plan from `$prp-issue-investigate`:
1. Load and validate the artifact
2. Ensure git state is correct
3. Implement the changes exactly as specified
4. Run validation
5. Create PR linked to issue
6. Run self-review and post findings
7. Archive the artifact

**Golden Rule**: Follow the artifact. If something seems wrong, validate it first — don't silently deviate.

## Phase 1: LOAD — Get the Artifact

### 1.1 Determine Input Type

**If number** (`123`, `#123`):
```bash
ls -t .prp-output/issues/issue-{number}*.md 2>/dev/null | head -1
```

**If path**: use directly.

### 1.2 Load and Parse Artifact

Extract: Issue number, title, type, files to modify (with line numbers), implementation steps, validation commands, test cases to add.

### 1.3 Validate Artifact Exists

**If not found**: STOP — "Run `$prp-issue-investigate {number}` first."

**PHASE_1_CHECKPOINT:**
- [ ] Artifact found and loaded
- [ ] Key sections parsed (files, steps, validation)
- [ ] Issue number extracted

## Phase 2: VALIDATE — Sanity Check

### 2.1 Verify Plan Accuracy

For each file in the artifact:
- Read current code
- Compare to what artifact expects
- Check if "current code" snippets match reality

**If significant drift**: Warn user, suggest re-running `$prp-issue-investigate`.

### 2.2 Confirm Approach Makes Sense

- Does the fix address the root cause?
- Are there obvious problems with the approach?
- Has something changed that invalidates the plan?

**If plan seems wrong**: STOP and explain.

**PHASE_2_CHECKPOINT:**
- [ ] Artifact matches current codebase state
- [ ] Approach still makes sense
- [ ] No blocking issues identified

## Phase 3: GIT-CHECK — Ensure Correct State

### 3.1 Check Current Git State

```bash
git branch --show-current
git status --porcelain
git fetch origin
```

### 3.2 Decision Tree

| State | Action |
|-------|--------|
| On main, clean | Create branch: `fix/issue-{number}-{slug}` |
| On main, dirty | STOP: "Commit or stash changes first" |
| On feature/fix branch | Use it (warn if name doesn't match issue) |
| Dirty state | STOP: suggest stash or commit |

### 3.3 Ensure Up-to-Date

```bash
git pull --rebase origin main 2>/dev/null || git pull origin main
```

**PHASE_3_CHECKPOINT:**
- [ ] Git state is clean and correct
- [ ] On appropriate branch
- [ ] Up to date with main

## Phase 4: IMPLEMENT — Make Changes

### 4.1 Execute Each Step

For each step in the artifact's Implementation Plan:
1. Read the target file — understand current state
2. Make the change — exactly as specified
3. Verify types compile

### 4.2 Implementation Rules

**DO:** Follow artifact steps in order, match existing code style, copy patterns from "Patterns to Follow" section, add tests as specified.

**DON'T:** Refactor unrelated code, add "improvements" not in the plan, change formatting of untouched lines, deviate without noting it.

### 4.3 Track Deviations

If you must deviate from the artifact: note what changed and why — include in PR description.

**PHASE_4_CHECKPOINT:**
- [ ] All steps from artifact executed
- [ ] Types compile after each change
- [ ] Tests added as specified
- [ ] Any deviations documented

## Phase 5: VERIFY — Run Validation

### 5.1 Run Artifact Validation Commands

Execute each command from the artifact's Validation section (adapt to project toolchain):

```bash
{type_check_command}
{test_command}
{lint_command}
```

### 5.2 Check Results

**All must pass before proceeding.** If failures: analyze, fix, re-run, note fixes in PR description.

**PHASE_5_CHECKPOINT:**
- [ ] Type check passes
- [ ] Tests pass
- [ ] Lint passes

## Phase 6: COMMIT — Save Changes

### 6.1 Safe Staging

```bash
# Stage modified tracked files
git diff --name-only | xargs -r git add

# Stage new untracked files
git ls-files --others --exclude-standard | xargs -r git add

# Verify no unexpected files staged
git diff --cached --name-only
```

### 6.2 Commit

```bash
git commit -m "Fix: {title} (#{number})

{problem statement}

Changes:
- {change 1}
- {change 2}

Fixes #{number}"
```

**PHASE_6_CHECKPOINT:**
- [ ] All changes committed
- [ ] Commit message references issue

## Phase 7: PR — Create Pull Request

### 7.1 Push to Remote

```bash
git push -u origin HEAD
```

### 7.2 Create PR

```bash
gh pr create --title "Fix: {title} (#{number})" --body "..."
```

PR body includes: Summary, Root Cause, Changes table, Testing checklist, Validation commands, `Fixes #{number}`, Implementation Details (artifact path, deviations).

### 7.3 Get PR Number

```bash
PR_NUMBER=$(gh pr view --json number -q '.number')
```

**PHASE_7_CHECKPOINT:**
- [ ] Changes pushed to remote
- [ ] PR created and linked to issue with "Fixes #{number}"

## Phase 8: REVIEW — Self Code Review

### 8.1 Run Code Review

Focus on:
1. Does the fix address the root cause from the investigation?
2. Code quality — matches codebase patterns?
3. Test coverage — are new tests sufficient?
4. Edge cases — are they handled?
5. Security — any concerns?

### 8.2 Post Review to PR

```bash
gh pr comment --body "## Automated Code Review
### Summary
{assessment}
### Findings
#### Strengths
- {strengths}
#### Suggestions (non-blocking)
- {suggestions}
### Checklist
- [x] Fix addresses root cause
- [x] Code follows codebase patterns
- [x] Tests cover the change
---
*Self-reviewed by AI*"
```

**PHASE_8_CHECKPOINT:**
- [ ] Code review completed
- [ ] Review posted to PR

## Phase 9: ARCHIVE — Clean Up

### 9.1 Move Artifact to Completed

```bash
mkdir -p .prp-output/issues/completed
mv .prp-output/issues/issue-{number}-{TIMESTAMP}.md .prp-output/issues/completed/
```

### 9.2 Commit and Push Archive

```bash
git add .prp-output/issues/
git commit -m "Archive investigation for issue #{number}"
git push
```

**PHASE_9_CHECKPOINT:**
- [ ] Artifact moved to completed folder
- [ ] Archive committed and pushed

## Phase 10: REPORT — Output to User

Present: Issue reference, Branch name, PR number and URL, Changes Made table, Validation results table, Self-review summary, Archived artifact path, Next steps (human review, merge when approved).

## Handling Edge Cases

| Scenario | Action |
|----------|--------|
| Artifact is outdated | Warn, suggest re-running `$prp-issue-investigate` |
| Tests fail after implementation | Debug, fix code (not test unless test is wrong), re-run |
| Merge conflicts | Resolve, re-run full validation, note in PR |
| PR creation fails | Check if PR exists, check permissions, provide manual `gh` command |
| Already on branch with changes | Use existing branch, warn if name doesn't match issue |

## Usage Examples

```
$prp-issue-fix 123
$prp-issue-fix .prp-output/issues/issue-123-20260316-1200.md
```

## Success Criteria

- PLAN_EXECUTED: All artifact steps completed
- VALIDATION_PASSED: All checks green
- PR_CREATED: PR exists and linked to issue
- REVIEW_POSTED: Self-review comment on PR
- ARTIFACT_ARCHIVED: Moved to `.prp-output/issues/completed/`
- AUDIT_TRAIL: Full history in git and GitHub

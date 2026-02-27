---
description: Fix all issues from PR review artifact - applies critical, high, medium, and suggestion fixes to the PR branch
argument-hint: <pr-number|review-artifact-path> [--severity critical,high,medium,suggestion]
---

# Fix Review Issues

**Input**: $ARGUMENTS

---

## Your Mission

Apply fixes for all issues found by `/prp-review`:

1. Load the review artifact and parse issues by severity
2. Checkout the PR branch
3. Fix issues in priority order: Critical → High → Medium → Suggestion
4. Run validation after each severity batch
5. Commit and push fixes to the PR branch
6. Post a summary comment on the PR

**Golden Rule**: Fix what the review found. Don't refactor unrelated code. If a fix is unclear or risky, skip and note it.

---

## Phase 1: LOAD - Get the Review Artifact

### 1.1 Parse Input

**Determine input type:**

| Input Format | Action |
|--------------|--------|
| Path to artifact | Use path directly — skip discovery |
| Number (`123`, `#123`) | Discover artifacts for this PR number |
| No input | Get current branch's PR number, then discover |

```bash
# If no input: find current PR number
gh pr view --json number -q '.number'
```

### 1.2 Discover Artifacts

**If input is a path**: use it directly, skip to 1.4.

**If input is a PR number**: find all review artifacts for this PR:

```bash
ls -t .prp-output/reviews/pr-{NUMBER}-review*.md 2>/dev/null
```

This may return multiple files, e.g.:
```
.prp-output/reviews/pr-123-review.md          ← claude-code (no suffix)
.prp-output/reviews/pr-123-review-codex.md    ← codex
.prp-output/reviews/pr-123-review-gemini.md   ← gemini
```

### 1.3 Resolve Which Artifact to Use

**Case A — Exactly 1 artifact found:**
Use it automatically. Show user:
```
✓ Using review artifact: pr-123-review.md
```

**Case B — Multiple artifacts found:**
List them with metadata and ask user to select:

```
Multiple review artifacts found for PR #123:

  [1] pr-123-review.md          (claude-code)   modified: 2026-02-27 14:30
  [2] pr-123-review-codex.md    (codex)         modified: 2026-02-27 10:15
  [3] pr-123-review-gemini.md   (gemini)        modified: 2026-02-26 09:00

Which review should be fixed? Enter number (or press Enter for [1] most recent):
```

Wait for user selection. Default to most recently modified if Enter is pressed.

**To skip this prompt in the future**, user can specify artifact path directly:
```
/prp-review-fix .prp-output/reviews/pr-123-review-codex.md
```

**Case C — No artifacts found:**
```
❌ No review artifact found for PR #{NUMBER}.

Run `/prp-review {NUMBER}` first to generate the review.
```

### 1.4 Handle Missing Artifact

**If artifact not found:**

```
❌ No review artifact found for PR #{NUMBER}.

Expected: .prp-output/reviews/pr-{NUMBER}-review*.md

Run `/prp-review {NUMBER}` first to generate the review.
```

### 1.5 Parse Severity Filter

**From `--severity` flag (if provided):**

```
--severity critical          → fix only Critical
--severity critical,high     → fix Critical and High
--severity all               → fix all (default)
```

**Default**: Fix all severities (Critical → High → Medium → Suggestion)

### 1.6 Parse Issues from Artifact

Extract all issues grouped by severity. Look for sections:

```markdown
### Critical
- **`file.ts:42`** - {description}
  - **Fix**: {recommendation}

### High Priority
### Medium Priority
### Suggestions
```

**Also accept Codex/Gemini format:**
```markdown
### Critical (block merge)
### Important (address before merge)
### Suggestions (nice to have)
```

Map to: Critical | High | Medium | Suggestion

**PHASE_1_CHECKPOINT:**
- [ ] Review artifact resolved (auto or user-selected)
- [ ] PR number identified
- [ ] Which artifact is being used — shown to user
- [ ] Issues parsed and grouped by severity
- [ ] Severity filter applied

---

## Phase 2: CHECKOUT - Get on the PR Branch

### 2.1 Get PR Branch Info

```bash
gh pr view {NUMBER} --json headRefName,state,headRefOid -q '{headRefName: .headRefName, state: .state}'
```

| State | Action |
|-------|--------|
| `MERGED` | STOP: "PR already merged. Cannot apply fixes." |
| `CLOSED` | STOP: "PR is closed. Cannot apply fixes." |
| `OPEN` or `DRAFT` | PROCEED |

### 2.2 Checkout the Branch

```bash
# Fetch and checkout
gh pr checkout {NUMBER}

# Verify we're on the right branch
git branch --show-current
```

### 2.3 Ensure Up-to-Date

```bash
git pull --rebase origin $(git branch --show-current) 2>/dev/null || true
```

**PHASE_2_CHECKPOINT:**
- [ ] PR is open/draft
- [ ] On PR branch
- [ ] Working directory is clean

---

## Phase 3: TRIAGE - Understand Issues

### 3.1 Print Fix Plan

Before making any changes, output the fix plan:

```
## Fix Plan for PR #{NUMBER}

Severity filter: {all | critical | critical,high | ...}

### Issues to Fix

#### Critical ({N})
- `file.ts:42` - {description}
- `file.ts:87` - {description}

#### High ({N})
- `file.ts:12` - {description}

#### Medium ({N})
- `util.ts:55` - {description}

#### Suggestion ({N})
- `service.ts:23` - {description}

### Skipping (out of severity filter)
- {N} issues will be skipped

Proceeding with fixes...
```

### 3.2 Group by File

For efficiency, group issues by file so each file is read once.

**PHASE_3_CHECKPOINT:**
- [ ] Fix plan printed
- [ ] Issues grouped by severity
- [ ] Files identified

---

## Phase 4: FIX - Apply Fixes

Process severity batches in order. For each batch:

### 4.1 Fix Loop (per severity batch)

For each issue in the batch:

1. **Read the file** — understand current context around the flagged line
2. **Read similar files** — understand the pattern to follow
3. **Apply the fix** — exactly what the review recommends
4. **Note deviations** — if you must deviate, document why

**Rules:**
- Fix ONLY what the review flagged
- Don't refactor surrounding code
- Match existing code style
- If a fix is ambiguous or risky → SKIP and add to skip log

### 4.2 Skip Logic

**Skip an issue if:**
- The fix recommendation is unclear
- The fix requires architectural changes beyond the issue scope
- The code has changed since the review (drift detected)
- The fix would break other things

**When skipping:** Note the issue in the skip log with reason.

### 4.3 Validate After Each Batch

After fixing all issues in a severity batch:

```bash
# Type checking (adapt to project toolchain)
npm run type-check || bun run type-check || npx tsc --noEmit || go build ./... || cargo check

# Linting
npm run lint || bun run lint || ruff check . || cargo clippy
```

**If validation fails after a batch:**
1. Identify which fix caused the failure
2. Revert that specific fix
3. Add it to skip log with reason: "Validation failed"
4. Re-run validation
5. Continue

**PHASE_4_CHECKPOINT:**
- [ ] Critical issues fixed (or skipped with reason)
- [ ] High issues fixed (or skipped with reason)
- [ ] Medium issues fixed (or skipped with reason)
- [ ] Suggestions applied (or skipped with reason)
- [ ] Validation passes after each batch

---

## Phase 5: VALIDATE - Full Validation Suite

### 5.1 Run Complete Validation

```bash
# Type check
npm run type-check || bun run type-check || npx tsc --noEmit

# Linting
npm run lint || bun run lint

# Tests
npm test || bun test

# Build
npm run build || bun run build
```

### 5.2 Handle Failures

**If any check fails:**
1. Identify the root cause
2. Fix the underlying issue (don't suppress)
3. Re-run the specific check
4. If unfixable → revert the causing fix and add to skip log

**PHASE_5_CHECKPOINT:**
- [ ] Type check passes
- [ ] Lint passes
- [ ] Tests pass
- [ ] Build passes

---

## Phase 6: COMMIT - Save Changes

### 6.1 Stage Changes

```bash
git add -A
git status  # Review what's being committed
```

### 6.2 Commit Message

```bash
git commit -m "$(cat <<'EOF'
fix: apply review fixes for PR #{NUMBER}

Address {N} issues from code review:

Critical ({N_critical} fixed, {N_critical_skipped} skipped):
- {brief description of critical fixes}

High ({N_high} fixed, {N_high_skipped} skipped):
- {brief description of high fixes}

Medium ({N_medium} fixed, {N_medium_skipped} skipped):
- {brief description}

Suggestions ({N_suggestion} applied, {N_suggestion_skipped} skipped):
- {brief description}

Skipped ({N_total_skipped} issues - see PR comment for details)
EOF
)"
```

**If nothing to commit** (all issues were skipped):
```
ℹ️ No changes to commit. All fixable issues were already addressed or skipped.
```

**PHASE_6_CHECKPOINT:**
- [ ] Changes staged
- [ ] Commit created with descriptive message

---

## Phase 7: PUSH - Update PR Branch

```bash
git push origin $(git branch --show-current)
```

**If push fails (branch protection or force needed):**
```bash
git push origin $(git branch --show-current) --force-with-lease
```

**PHASE_7_CHECKPOINT:**
- [ ] Changes pushed to PR branch

---

## Phase 8: COMMENT - Post Summary to PR

### 8.1 Build Summary Comment

```bash
gh pr comment {NUMBER} --body "$(cat <<'EOF'
## Review Fix Summary

Applied fixes from review report: `.prp-output/reviews/pr-{NUMBER}-review.md`

### Fixed Issues

| Severity | Fixed | Skipped | Total |
|----------|-------|---------|-------|
| Critical | {N} | {N} | {N} |
| High | {N} | {N} | {N} |
| Medium | {N} | {N} | {N} |
| Suggestion | {N} | {N} | {N} |
| **Total** | **{N}** | **{N}** | **{N}** |

### Validation

| Check | Status |
|-------|--------|
| Type Check | {PASS/FAIL} |
| Lint | {PASS/FAIL} |
| Tests | {PASS/FAIL} |
| Build | {PASS/FAIL} |

{If skipped issues exist:}
### Skipped Issues (require manual attention)

- `{file}:{line}` — {reason skipped}
- `{file}:{line}` — {reason skipped}

### Changes Made

| File | Changes |
|------|---------|
| `{file.ts}` | {what was fixed} |

---
*Automated review fixes by Claude*
*Commit: {commit-hash}*
EOF
)"
```

**PHASE_8_CHECKPOINT:**
- [ ] Summary comment posted to PR

---

## Phase 9: UPDATE ARTIFACT - Mark Issues Resolved

Append a "Fix Outcome" section to the review artifact:

```markdown

---

## Fix Outcome

**Fixed**: {ISO_TIMESTAMP}
**Commit**: {hash}
**Branch**: {branch-name}

| Severity | Fixed | Skipped |
|----------|-------|---------|
| Critical | {N} | {N} |
| High | {N} | {N} |
| Medium | {N} | {N} |
| Suggestion | {N} | {N} |

### Skipped Issues
{List with reasons, or "None"}
```

---

## Phase 10: OUTPUT - Report to User

```markdown
## Review Fixes Applied

**PR**: #{NUMBER} - {TITLE}
**Branch**: `{branch-name}`
**Commit**: `{hash}`

### Summary

| Severity | Fixed | Skipped |
|----------|-------|---------|
| Critical | {N} | {N} |
| High | {N} | {N} |
| Medium | {N} | {N} |
| Suggestion | {N} | {N} |

### Validation

| Check | Result |
|-------|--------|
| Type Check | ✅/❌ |
| Lint | ✅/❌ |
| Tests | ✅/❌ |
| Build | ✅/❌ |

{If skipped:}
### Needs Manual Attention

{N} issues were skipped and require manual review:
- `{file}:{line}` — {reason}

### Next Steps

{If all critical/high fixed:} "Ready for re-review. Run `/prp-review {NUMBER}` to verify."
{If critical still open:} "⚠️ {N} critical issues require manual attention before merge."
```

---

## Edge Cases

### No review artifact exists

Stop and tell user to run `/prp-review {NUMBER}` first.

### PR branch has conflicts

```
⚠️ Branch has conflicts with base. Resolve conflicts first:
git rebase origin/{base-branch}
```

### Issue already fixed

If code at flagged line already matches the recommendation: skip silently (mark as "already fixed").

### Drift detected (code changed since review)

If file content differs significantly from what review expected:
- Warn: "Code has changed since review. Manual verification recommended."
- Still attempt the fix if context is clear, otherwise skip.

### All issues skipped

```
ℹ️ All {N} issues were skipped (unclear fixes or validation failures).
Manual review required. See skip log above.
```

### Suggestion-only issues

By default, suggestions are included. To skip suggestions:
```
/prp-review-fix {NUMBER} --severity critical,high,medium
```

---

## Success Criteria

- **ARTIFACT_LOADED**: Review artifact found and parsed
- **BRANCH_CHECKED_OUT**: On correct PR branch
- **FIXES_APPLIED**: All non-skipped issues addressed
- **VALIDATION_PASSES**: All automated checks green
- **CHANGES_PUSHED**: Commit pushed to PR branch
- **PR_COMMENTED**: Summary posted to GitHub
- **ARTIFACT_UPDATED**: Review artifact has fix outcome appended

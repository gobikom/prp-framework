---
description: Fix all issues from PR review artifact - applies critical, high, medium, and suggestion fixes to the PR branch
agent: plan
---

# PRP Review Fix — Apply Review Findings

Target: $ARGUMENTS

Format: `<pr-number|review-artifact-path> [--severity critical,high,medium,suggestion]`

## Mission

Load the review artifact from `/prp:review`, apply all fixable issues in priority order, validate, and push to the PR branch. Report what was fixed and what required manual attention.

## Phase 1: LOAD — Get Review Artifact

**If input is a path**: use it directly, skip discovery.

**If input is a PR number** (or no input → `gh pr view --json number -q '.number'`):

```bash
ls -t .prp-output/reviews/pr-{NUMBER}-review*.md 2>/dev/null
```

**Resolution logic:**

| Artifacts found | Action |
|-----------------|--------|
| 1 | Use it automatically. Show user: `✓ Using: pr-{N}-review.md` |
| Multiple | List with tool suffix + modified date, ask user to select (default: most recent) |
| None | STOP — "Run `/prp:review {NUMBER}` first." |

**Example disambiguation prompt (when multiple):**
```
Multiple reviews found for PR #123:
  [1] pr-123-review.md          (claude-code)   2026-02-27 14:30  ← most recent
  [2] pr-123-review-codex.md    (codex)         2026-02-27 10:15
  [3] pr-123-review-gemini.md   (gemini)        2026-02-26 09:00

Which review to fix? (Enter for [1]):
```

To skip prompt: pass artifact path directly as input.

**Severity filter** (default: all):
- `--severity critical` → Critical only
- `--severity critical,high` → Critical + High
- `--severity critical,high,medium` → All except suggestions
- No flag → all severities

**Parse issue sections**: Critical / High Priority / Medium Priority / Suggestions
(Also accepts: Critical / Important / Suggestions from different review tools)

## Phase 2: CHECKOUT — Get on PR Branch

```bash
gh pr view {NUMBER} --json headRefName,state
gh pr checkout {NUMBER}
git pull --rebase origin $(git branch --show-current) 2>/dev/null || true
```

| State | Action |
|-------|--------|
| MERGED / CLOSED | STOP: "Cannot apply fixes to closed PR" |
| OPEN / DRAFT | PROCEED |

## Phase 3: FIX — Apply Issues by Severity

Process in order: **Critical → High → Medium → Suggestion**

For each issue:
1. Read the target file at the flagged line
2. Apply the recommended fix (as stated in review)
3. Don't refactor unrelated code or make scope creep changes
4. Skip if: ambiguous fix, risky change, or drift from review expectations

**Validate after each severity batch:**
```bash
npm run type-check || bun run type-check || npx tsc --noEmit
npm run lint || bun run lint
```

If validation fails: identify the failing fix → revert it → add to skip log → re-validate.

## Phase 4: VALIDATE — Full Suite

All must pass:
```bash
npm run type-check || bun run type-check || npx tsc --noEmit
npm run lint || bun run lint
npm test || bun test
npm run build || bun run build
```

If a fix causes test failure: revert and skip that fix.

## Phase 5: COMMIT & PUSH

```bash
git add -A
git commit -m "fix: apply review fixes for PR #{NUMBER}

Address {N} issues: {N_critical} critical, {N_high} high, {N_medium} medium, {N_suggestion} suggestions
Skipped {N_skipped} (see PR comment for details)"

git push origin $(git branch --show-current)
```

If nothing to commit: skip and report "No changes needed."

## Phase 6: COMMENT — Post Summary to PR

```bash
gh pr comment {NUMBER} --body-file .prp-output/reviews/pr-{NUMBER}-fix-summary.md
```

Summary content:
- Fix counts table: Severity | Fixed | Skipped
- Validation results table
- Skipped issues list with reasons (if any)
- Commit hash reference

Save summary locally to `.prp-output/reviews/pr-{NUMBER}-fix-summary.md`.

> **Note**: Uses `-fix-summary` suffix to identify fix summaries separately from review files.

**Update review artifact**: Append "Fix Outcome" section with timestamp, commit hash, and fix counts.

## Output

Report to user:
- PR number, branch, commit hash
- Fixed/skipped table per severity
- Validation results
- Next steps:
  - All critical/high fixed → "Run `/prp:review {NUMBER}` to verify."
  - Critical still open → "⚠️ {N} critical issues need manual attention before merge."

## Edge Cases

- **No artifact**: STOP, instruct to run review first
- **Drift detected**: Warn user, attempt fix if context clear, else skip
- **Already fixed**: Skip silently ("already addressed")
- **All skipped**: No commit, report all skip reasons

## Usage

```
/prp:review-fix 163                          # Fix all issues
/prp:review-fix 163 --severity critical,high # Critical and high only
/prp:review-fix                              # Current branch's PR
/prp:review-fix .prp-output/reviews/pr-42-review-opencode.md  # By path
```

## Success Criteria

- ARTIFACT_LOADED: Review artifact found and parsed
- FIXES_APPLIED: All non-skipped issues addressed
- VALIDATION_PASSES: All automated checks green
- CHANGES_PUSHED: Commit pushed to PR branch
- PR_COMMENTED: Summary posted to GitHub
- ARTIFACT_UPDATED: Fix outcome appended to review file

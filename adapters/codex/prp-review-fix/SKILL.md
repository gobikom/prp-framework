---
name: prp-review-fix
description: Fix all issues from a PR review artifact - applies critical, high, medium, and suggestion fixes directly to the PR branch.
metadata:
  short-description: Fix PR review issues
---

# PRP Review Fix — Apply Review Findings

## Input

PR number and optional severity filter: `$ARGUMENTS`

Format: `<pr-number|review-artifact-path> [--severity critical,high,medium,suggestion]`

## Mission

Apply all fixable issues found by `prp-review`. Load the review artifact, fix each issue in priority order, validate, and push to the PR branch. Report what was fixed and what was skipped.

## Phase 1: LOAD — Get Review Artifact

**If input is a path**: use it directly.

**If input is a PR number** (or no input → get current branch's PR):
```bash
gh pr view --json number -q '.number'
ls -t .prp-output/reviews/pr-{NUMBER}-review*.md 2>/dev/null
```

**If 1 artifact found**: use it, show user which one was selected.

**If multiple artifacts found** (multiple tools reviewed):
```
Multiple review artifacts for PR #{NUMBER}:
  [1] pr-123-review.md          (claude-code)   2026-02-27 14:30
  [2] pr-123-review-codex.md    (codex)         2026-02-27 10:15
  [3] pr-123-review-gemini.md   (gemini)        2026-02-26 09:00

Which review to fix? (Enter for [1] most recent):
```
Default: most recently modified. To skip prompt: pass artifact path directly.

**If none found**: STOP — "Run `prp-review {NUMBER}` first."

**Parse severity filter** (default: all):
- `--severity critical` → Critical only
- `--severity critical,high` → Critical + High
- No flag → Critical + High + Medium + Suggestion

**Parse issues** from artifact sections: Critical / High Priority / Medium Priority / Suggestions
(Also accepts: Critical / Important / Suggestions format from Codex reviews)

## Phase 2: CHECKOUT — Get on PR Branch

```bash
gh pr view {NUMBER} --json headRefName,state
gh pr checkout {NUMBER}
git pull --rebase origin $(git branch --show-current) 2>/dev/null || true
```

| State | Action |
|-------|--------|
| MERGED / CLOSED | STOP |
| OPEN / DRAFT | PROCEED |

## Phase 3: TRIAGE — Print Fix Plan

Before making any changes, print the fix plan:
- Show issue counts per severity
- List each issue with file and description
- Group by file for efficiency
- Show which issues will be skipped (out of severity filter)

This gives visibility into what will be changed before any edits happen.

## Phase 4: FIX — Apply Issues by Severity

Process order: **Critical → High → Medium → Suggestion**

For each issue:
1. Read the target file at the flagged location
2. Apply the recommended fix (exactly as stated in review)
3. Don't refactor unrelated code
4. If fix is ambiguous or risky → SKIP, add to skip log

**Validate after each severity batch:**
```bash
npm run type-check || bun run type-check || npx tsc --noEmit
npm run lint || bun run lint
```

If validation fails after a batch: identify the failing fix, revert it, add to skip log, re-validate.

## Phase 5: VALIDATE — Full Suite

```bash
npm run type-check || bun run type-check || npx tsc --noEmit
npm run lint || bun run lint
npm test || bun test
npm run build || bun run build
```

All checks must pass before committing. If a fix causes failures: revert and skip.

## Phase 6: COMMIT & PUSH

```bash
git add -A
git commit -m "fix: apply review fixes for PR #{NUMBER}

Address {N} issues: {N_critical} critical, {N_high} high, {N_medium} medium, {N_suggestion} suggestions
Skipped {N_skipped} issues (see PR comment)"

git push origin $(git branch --show-current)
```

If nothing to commit: report "No changes needed."

## Phase 7: COMMENT — Post Summary

```bash
gh pr comment {NUMBER} --body "$(cat <<'EOF'
## Review Fix Summary

| Severity | Fixed | Skipped |
|----------|-------|---------|
| Critical | {N} | {N} |
| High | {N} | {N} |
| Medium | {N} | {N} |
| Suggestion | {N} | {N} |

### Validation

| Check | Status |
|-------|--------|
| Type Check | PASS/FAIL |
| Lint | PASS/FAIL |
| Tests | PASS/FAIL |
| Build | PASS/FAIL |

{If skipped:}
### Skipped (manual attention needed)
- `{file}:{line}` — {reason}

*Automated review fixes by Codex • Commit: {hash}*
EOF
)"
```

**Update review artifact**: append "Fix Outcome" section with timestamp, commit hash, and counts.

## Output

Report: PR number, fixed/skipped counts per severity, validation results, commit hash, next steps.

- All critical/high fixed → "Ready for re-review. Run `prp-review {NUMBER}` to verify."
- Critical still open → "⚠️ {N} critical issues require manual attention."

## Edge Cases

- **No artifact**: STOP, tell user to run `prp-review` first
- **PR merged/closed**: STOP
- **PR branch has conflicts**: Warn user to resolve conflicts first: `git rebase origin/{base-branch}`
- **Drift detected**: Warn, attempt fix if context clear, otherwise skip
- **Already fixed**: Skip silently (mark "already fixed")
- **All skipped**: Report all skips, no commit
- **Suggestion-only issues**: By default included. To skip: `--severity critical,high,medium`

## Usage Examples

```
$prp-review-fix 163                           # Fix all issues
$prp-review-fix 163 --severity critical,high  # Only critical and high
$prp-review-fix                               # Current branch's PR, all issues
$prp-review-fix .prp-output/reviews/pr-42-review-codex.md  # By artifact path
```

## Success Criteria

- ARTIFACT_LOADED: Review artifact found and parsed
- BRANCH_CHECKED_OUT: On correct PR branch
- FIXES_APPLIED: All non-skipped issues addressed
- VALIDATION_PASSES: All automated checks green
- CHANGES_PUSHED: Commit pushed to PR branch
- PR_COMMENTED: Summary posted to GitHub
- ARTIFACT_UPDATED: Fix outcome appended to review file

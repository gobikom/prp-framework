# PRP Review Fix — Apply Review Findings

**Input**: `<pr-number|review-artifact-path> [--severity critical,high,medium,suggestion]`

---

## Mission

Apply all fixable issues found by the Review workflow. Load the review artifact, fix each issue in priority order, validate, push to the PR branch, and post a summary.

**Golden Rule**: Fix what the review found. Don't refactor unrelated code. Skip unclear or risky fixes — note them.

---

## Steps

### 1. LOAD — Get Review Artifact

**If input is a path**: use it directly, skip discovery.

**If input is a PR number** (or no input → get current branch's PR):
```bash
ls -t .prp-output/reviews/pr-{NUMBER}-review*.md 2>/dev/null
```

**Resolution logic:**

| Artifacts found | Action |
|-----------------|--------|
| 1 | Use it automatically. Show: `✓ Using: {filename}` |
| Multiple | List with tool suffix + modified date → ask user to select (default: most recent) |
| None | STOP — "Run the Review workflow for PR #{NUMBER} first." |

**Disambiguation prompt (when multiple found):**
```
Multiple reviews found for PR #123:
  [1] pr-123-review.md          (claude-code)   2026-02-27 14:30  ← most recent
  [2] pr-123-review-codex.md    (codex)         2026-02-27 10:15
  [3] pr-123-review-gemini.md   (gemini)        2026-02-26 09:00

Which review to fix? (Enter for [1]):
```

To skip this prompt: pass the artifact path directly as input.

**Parse severity filter** (default: all severities):
- `--severity critical` → Critical only
- `--severity critical,high` → Critical + High
- No flag → Critical + High + Medium + Suggestion

**Map review sections** to severities:
| Review Section | Severity |
|----------------|----------|
| Critical | Critical |
| High Priority / Important | High |
| Medium Priority | Medium |
| Suggestions / Low | Suggestion |

### 2. CHECKOUT — Get on PR Branch

```bash
gh pr view {NUMBER} --json headRefName,state
gh pr checkout {NUMBER}
git pull --rebase origin $(git branch --show-current) 2>/dev/null || true
```

Stop if PR is MERGED or CLOSED.

### 3. TRIAGE — Print Fix Plan

Before making changes, output:
```
## Fix Plan — PR #{NUMBER}
Critical: {N} issues
High:     {N} issues
Medium:   {N} issues
Suggestion: {N} issues
Skipping (severity filter): {N} issues
```

### 4. FIX — Apply Issues (Critical → High → Medium → Suggestion)

For each issue:
1. Read the target file at the flagged location
2. Apply the recommended fix exactly as stated in the review
3. Do NOT refactor unrelated code
4. SKIP if: fix is ambiguous, risky, or code has drifted significantly since review

**After each severity batch — validate:**
```bash
# Adapt to project toolchain
npm run type-check || bun run type-check || npx tsc --noEmit || go build ./... || cargo check
npm run lint || bun run lint || ruff check . || cargo clippy
```

If validation fails after a batch:
- Identify the fix that caused failure
- Revert that fix
- Add to skip log with reason: "Caused validation failure"
- Re-validate
- Continue to next batch

### 5. VALIDATE — Full Suite

All must pass:
```bash
# Type check
npm run type-check || bun run type-check || npx tsc --noEmit

# Lint
npm run lint || bun run lint

# Tests
npm test || bun test

# Build
npm run build || bun run build
```

If a fix causes test/build failure: revert and skip that fix.

### 6. COMMIT & PUSH

```bash
git add -A

git commit -m "fix: apply review fixes for PR #{NUMBER}

Address {N} issues: {N_critical} critical, {N_high} high, {N_medium} medium, {N_suggestion} suggestions
Skipped {N_skipped} issues (see PR comment for details)"

git push origin $(git branch --show-current)
```

Skip commit if no changes were made.

### 7. COMMENT — Post Summary to PR

```bash
gh pr comment {NUMBER} --body "$(cat <<'EOF'
## Review Fix Summary

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
| Type Check | ✅/❌ |
| Lint | ✅/❌ |
| Tests | ✅/❌ |
| Build | ✅/❌ |

{If skipped issues:}
### Requires Manual Attention

- `{file}:{line}` — {reason skipped}

*Automated review fixes • Commit: {hash}*
EOF
)"
```

### 8. UPDATE ARTIFACT

Append to the review file:

```markdown
---

## Fix Outcome

**Fixed**: {ISO_TIMESTAMP}
**Commit**: {hash}

| Severity | Fixed | Skipped |
|----------|-------|---------|
| Critical | {N} | {N} |
| High | {N} | {N} |
| Medium | {N} | {N} |
| Suggestion | {N} | {N} |

Skipped: {list with reasons, or "None"}
```

### 9. OUTPUT — Report to User

```markdown
## Review Fixes Applied

**PR**: #{NUMBER}
**Commit**: `{hash}`

| Severity | Fixed | Skipped |
|----------|-------|---------|
| Critical | {N} | {N} |
| High | {N} | {N} |
| Medium | {N} | {N} |
| Suggestion | {N} | {N} |

**Validation**: {all pass / N failures}

**Next Steps**:
- [All critical/high fixed] → Run Review workflow again to verify.
- [Critical still open] → ⚠️ {N} critical issues require manual attention before merge.
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| No artifact found | STOP — run Review first |
| PR merged/closed | STOP — cannot apply fixes |
| Code drifted since review | Warn, attempt if context clear, else skip |
| Issue already fixed | Skip silently (mark "already addressed") |
| All issues skipped | No commit, report all skip reasons |
| Fix causes test failure | Revert that fix, add to skip log |

---

## Success Criteria

- **ARTIFACT_LOADED**: Review artifact found and parsed
- **BRANCH_CHECKED_OUT**: On correct PR branch
- **FIXES_APPLIED**: All non-skipped issues addressed
- **VALIDATION_PASSES**: All automated checks green
- **CHANGES_PUSHED**: Commit pushed to PR branch
- **PR_COMMENTED**: Summary posted to GitHub
- **ARTIFACT_UPDATED**: Fix outcome appended to review file

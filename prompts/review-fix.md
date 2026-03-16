# PRP Review Fix — Apply Review Findings

**Input**: `<pr-number|review-artifact-path> [--severity critical,high,medium,suggestion]`

---

## Mission

Apply all fixable issues found by the Review workflow. Load the review artifact, fix each issue in priority order, validate, push to the PR branch, and post a summary.

**Golden Rule**: Fix what the review found. Don't refactor unrelated code. Skip unclear or risky fixes — note them.

---

## Steps

### 0. DETECT — Project Toolchain

**Identify package manager** from lock files (bun/pnpm/yarn/npm/uv/cargo/go).

**Identify validation commands** — check for a completed plan matching the PR branch:

```bash
PR_BRANCH=$(gh pr view {NUMBER} --json headRefName -q '.headRefName' 2>/dev/null)
PLAN_SLUG=$(echo "$PR_BRANCH" | sed 's|^feature/||')
ls -t .prp-output/plans/completed/*${PLAN_SLUG}*.plan.md 2>/dev/null | head -1
```

> **Plan-provided commands take precedence — but only if the plan matches the PR branch**. If a matching plan has a Metadata table with Runner/Type Check/Lint/Test/Build commands, use those directly. Otherwise fall back to auto-detection.

**Fallback — auto-detect from project config:**

| Ecosystem | Type Check | Lint | Test | Build |
|-----------|-----------|------|------|-------|
| JS/TS | `{runner} run type-check` | `{runner} run lint` | `{runner} test` | `{runner} run build` |
| Python | `mypy .` | `ruff check .` | `pytest` | N/A |
| Rust | `cargo check` | `cargo clippy` | `cargo test` | `cargo build` |
| Go | `go vet ./...` | `golangci-lint run` | `go test ./...` | `go build ./...` |

**Store detected commands** — use consistently for all validation steps.

### 1. LOAD — Get Review Artifact

**If input is a path**: use it directly, skip discovery.

**If input is a PR number** (or no input → get current branch's PR):
```bash
ls -t .prp-output/reviews/pr-{NUMBER}-*review*.md 2>/dev/null
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

**Severity mapping table:**

| Review Section | Maps To |
|----------------|---------|
| Critical / Critical Issues / Critical (block merge) | **Critical** |
| High Priority / Important / Important Issues / Important (address before merge) | **High** |
| Medium Priority | **Medium** |
| Suggestions / Low / Suggestions (nice to have) | **Suggestion** |

> **Note**: The agents-review format does not use "Medium" — issues are either Critical, Important, or Suggestion. When parsing agents-review, treat Important as High. Codex/Gemini adapters use parenthetical labels (e.g., "Critical (block merge)") — match on the keyword before the parenthetical.

### 2. CHECKOUT — Get on PR Branch

```bash
CURRENT=$(git branch --show-current)
PR_BRANCH=$(gh pr view {NUMBER} --json headRefName -q '.headRefName')

if [ "$CURRENT" = "$PR_BRANCH" ]; then
  echo "Already on PR branch: $PR_BRANCH"
  # Verify working directory is clean
  if [ -n "$(git status --porcelain)" ]; then
    echo "⚠️ Working directory is dirty. Stash or commit changes first."
    # STOP if dirty
  fi
else
  gh pr checkout {NUMBER}
fi

git pull --rebase origin $(git branch --show-current) 2>/dev/null || true
```

Stop if PR is MERGED or CLOSED.

### 3. TRIAGE — Print Fix Plan

Before making changes, output:
```
## Fix Plan — PR #{NUMBER}
Validation commands: {detected runner} ({source: plan / auto-detected})
Critical: {N} issues
High:     {N} issues
Medium:   {N} issues
Suggestion: {N} issues
Skipping (severity filter): {N} issues
```

Group issues by file for efficiency.

### 4. FIX — Apply Issues (Critical → High → Medium → Suggestion)

For each issue:
1. Read the target file at the flagged location
2. Apply the recommended fix exactly as stated in the review
3. Do NOT refactor unrelated code
4. SKIP if: fix is ambiguous, risky, or code has drifted significantly since review

**After each severity batch — validate using detected commands:**
```bash
{type_check_command}
{lint_command}
```

If validation fails after a batch:
- Identify the fix that caused failure
- Revert that fix
- Add to skip log with reason: "Caused validation failure"
- Re-validate
- Continue to next batch

### 5. VALIDATE — Full Suite

All must pass (using **detected commands** from Step 0):
```bash
{type_check_command}
{lint_command}
{test_command}
{build_command}
```

If a fix causes test/build failure: revert and skip that fix.

**GATE**: Do NOT proceed to Step 6 until all validation checks pass (or failing fixes are reverted and skipped).

### 6. COMMIT & PUSH

**Do NOT use `git add -A`** — stage only intentionally modified files:

```bash
# Stage modified tracked files
git diff --name-only | xargs -r git add

# Stage new files created as part of fixes (untracked, non-ignored)
git ls-files --others --exclude-standard | xargs -r git add

# Verify no unexpected files are staged
git diff --cached --name-only

git commit -m "fix: apply review fixes for PR #{NUMBER}

Address {N} issues: {N_critical} critical, {N_high} high, {N_medium} medium, {N_suggestion} suggestions
Skipped {N_skipped} issues (see PR comment for details)"

git push origin $(git branch --show-current)
```

Skip commit if no changes were made.

### 7. REPORT — Post Summary and Update Artifacts

**Save fix summary locally (with timestamp):**

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
SUMMARY_FILE=".prp-output/reviews/pr-${NUMBER}-fix-summary-${TIMESTAMP}.md"
mkdir -p .prp-output/reviews
```

Write summary content to `$SUMMARY_FILE`, then post:

```bash
gh pr comment ${NUMBER} --body-file "$SUMMARY_FILE"
```

Summary content:
- Fix counts table: Severity | Fixed | Skipped
- Validation results table
- Skipped issues list with reasons (if any)
- Commit hash reference

**Update review artifact**: Append "Fix Outcome" section with timestamp, commit hash, and fix counts.

### 8. OUTPUT — Report to User

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

### Artifacts

- Fix summary: `.prp-output/reviews/pr-{NUMBER}-fix-summary-{TIMESTAMP}.md`
- Review artifact updated with Fix Outcome

**Next Steps**:
- [All critical/high fixed] → Run Review workflow again to verify.
- [Critical still open] → ⚠️ {N} critical issues require manual attention before merge.
```

> **Note for orchestrators**: The "Next Steps" above are for standalone usage only. If this command was invoked as part of a run-all workflow, the orchestrator should ignore these suggestions and proceed to its next step.

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| No artifact found | STOP — run Review first |
| PR merged/closed | STOP — cannot apply fixes |
| PR branch has conflicts | Warn user to resolve: `git rebase origin/{base-branch}` |
| Code drifted since review | Warn, attempt if context clear, else skip |
| Issue already fixed | Skip silently (mark "already addressed") |
| All issues skipped | No commit, report all skip reasons |
| Fix causes test failure | Revert that fix, add to skip log |

---

## Success Criteria

- **ARTIFACT_LOADED**: Review artifact found and parsed
- **BRANCH_CHECKED_OUT**: On correct PR branch
- **TOOLCHAIN_DETECTED**: Validation commands identified (plan or auto-detected)
- **FIXES_APPLIED**: All non-skipped issues addressed
- **VALIDATION_PASSES**: All automated checks green (GATE passed)
- **CHANGES_PUSHED**: Commit pushed to PR branch (only modified files staged)
- **PR_COMMENTED**: Summary posted to GitHub
- **ARTIFACT_UPDATED**: Fix outcome appended to review file
- **SUMMARY_SAVED**: Fix summary saved with timestamp to `.prp-output/reviews/`

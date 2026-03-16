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

**Golden Rule**: Fix what the review found. Don't refactor unrelated code. Skip unclear or risky fixes — note them.

## Phase 0: Detect Project Toolchain

### 0.1 Identify Package Manager

| File Found | Package Manager | Runner |
|------------|-----------------|--------|
| `bun.lockb` | bun | `bun` / `bun run` |
| `pnpm-lock.yaml` | pnpm | `pnpm` / `pnpm run` |
| `yarn.lock` | yarn | `yarn` / `yarn run` |
| `package-lock.json` | npm | `npm run` |
| `pyproject.toml` | uv/pip | `uv run` / `python` |
| `Cargo.toml` | cargo | `cargo` |
| `go.mod` | go | `go` |

### 0.2 Identify Validation Commands

Check for a completed plan matching the PR branch:

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

## Phase 1: Load Review Artifact

### 1.1 Parse Input

**If input is a path**: use it directly.

**If input is a PR number** (or no input → get current branch's PR):
```bash
gh pr view --json number -q '.number'
ls -t .prp-output/reviews/pr-{NUMBER}-*review*.md 2>/dev/null
```

### 1.2 Resolve Artifact

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

### 1.3 Parse Severity Filter

- `--severity critical` → Critical only
- `--severity critical,high` → Critical + High
- `--severity critical,high,medium` → All except suggestions
- No flag → all severities (default)

### 1.4 Parse Issues

Extract issues grouped by severity from the artifact.

**Severity mapping table:**

| Review Section | Maps To |
|----------------|---------|
| Critical / Critical Issues / Critical (block merge) | **Critical** |
| High Priority / Important / Important Issues / Important (address before merge) | **High** |
| Medium Priority | **Medium** |
| Suggestions / Low / Suggestions (nice to have) | **Suggestion** |

> **Note**: The agents-review format does not use "Medium" — issues are either Critical, Important, or Suggestion. When parsing agents-review, treat Important as High. Codex/Gemini adapters use parenthetical labels (e.g., "Critical (block merge)") — match on the keyword before the parenthetical.

## Phase 2: Checkout PR Branch

### 2.1 Check PR State

```bash
gh pr view {NUMBER} --json headRefName,state
```

| State | Action |
|-------|--------|
| MERGED / CLOSED | STOP: "Cannot apply fixes" |
| OPEN / DRAFT | PROCEED |

### 2.2 Checkout

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
```

### 2.3 Sync

```bash
git pull --rebase origin $(git branch --show-current) 2>/dev/null || true
```

## Phase 3: Triage — Print Fix Plan

Before making any changes, print the fix plan:
- Show issue counts per severity
- Validation commands and their source (plan / auto-detected)
- List each issue with file and description
- Group by file for efficiency
- Show which issues will be skipped (out of severity filter)

This gives visibility into what will be changed before any edits happen.

## Phase 4: Fix — Apply Issues by Severity

Process order: **Critical → High → Medium → Suggestion**

For each issue:
1. Read the target file at the flagged location
2. Apply the recommended fix (exactly as stated in review)
3. Don't refactor unrelated code
4. If fix is ambiguous or risky → SKIP, add to skip log

### 4.1 Validate After Each Batch

Run **detected validation commands** from Phase 0:

```bash
{type_check_command}
{lint_command}
```

If validation fails after a batch: identify the failing fix, revert it, add to skip log, re-validate.

## Phase 5: Validate — Full Suite

Run all **detected validation commands** from Phase 0:

```bash
{type_check_command}
{lint_command}
{test_command}
{build_command}
```

All checks must pass before committing. If a fix causes failures: revert and skip.

**GATE**: Do NOT proceed to Phase 6 until all validation checks pass (or failing fixes are reverted and skipped).

## Phase 6: Commit & Push

### 6.1 Stage Changes

**Do NOT use `git add -A`** — stage only intentionally modified files:

```bash
# Stage modified tracked files
git diff --name-only | xargs -r git add

# Stage new files created as part of fixes (untracked, non-ignored)
git ls-files --others --exclude-standard | xargs -r git add

# Verify no unexpected files are staged
git diff --cached --name-only
```

### 6.2 Commit

```bash
git commit -m "fix: apply review fixes for PR #{NUMBER}

Address {N} issues: {N_critical} critical, {N_high} high, {N_medium} medium, {N_suggestion} suggestions
Skipped {N_skipped} issues (see PR comment)"

git push origin $(git branch --show-current)
```

If nothing to commit: report "No changes needed."

## Phase 7: Report — Post Summary and Update Artifacts

### 7.1 Save Fix Summary Locally

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
SUMMARY_FILE=".prp-output/reviews/pr-${NUMBER}-fix-summary-${TIMESTAMP}.md"
mkdir -p .prp-output/reviews
```

Write summary to `$SUMMARY_FILE`:
- Fix counts table: Severity | Fixed | Skipped
- Validation results table
- Skipped issues list with reasons (if any)
- Commit hash reference

### 7.2 Post to PR

```bash
gh pr comment ${NUMBER} --body-file "$SUMMARY_FILE"
```

### 7.3 Update Review Artifact

Append "Fix Outcome" section to the review artifact with timestamp, commit hash, and counts.

## Phase 8: Output

Report: PR number, branch, commit hash, fixed/skipped counts per severity, validation results, artifacts (fix summary path, review artifact updated), next steps.

- All critical/high fixed → "Ready for re-review. Run `prp-review {NUMBER}` to verify."
- Critical still open → "⚠️ {N} critical issues require manual attention."

> **Note for orchestrators**: The "Next Steps" above are for standalone usage only. If this command was invoked as part of run-all, the orchestrator should ignore these suggestions and proceed to its next step.

## Failure Handling

| Failure | Action |
|---------|--------|
| No artifact found | STOP — run `prp-review` first |
| PR merged/closed | STOP — cannot apply fixes |
| PR branch has conflicts | Warn user to resolve: `git rebase origin/{base-branch}` |
| Drift detected | Warn, attempt fix if context clear, otherwise skip |
| Already fixed | Skip silently (mark "already fixed") |
| All issues skipped | Report all skips, no commit |
| Fix causes validation failure | Revert that fix, add to skip log |

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
- TOOLCHAIN_DETECTED: Validation commands identified (plan or auto-detected)
- FIXES_APPLIED: All non-skipped issues addressed
- VALIDATION_PASSES: All automated checks green (GATE passed)
- CHANGES_PUSHED: Commit pushed to PR branch (only modified files staged)
- PR_COMMENTED: Summary posted to GitHub
- ARTIFACT_UPDATED: Fix outcome appended to review file
- SUMMARY_SAVED: Fix summary saved with timestamp to `.prp-output/reviews/`

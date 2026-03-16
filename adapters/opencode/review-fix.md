---
description: Fix all issues from PR review artifact - applies critical, high, medium, and suggestion fixes to the PR branch
agent: plan
---

# PRP Review Fix — Apply Review Findings

Target: $ARGUMENTS

Format: `<pr-number|review-artifact-path> [--severity critical,high,medium,suggestion]`

## Mission

Load the review artifact from `/prp:review`, apply all fixable issues in priority order, validate, and push to the PR branch. Report what was fixed and what required manual attention.

## Phase 0: DETECT — Project Toolchain

Identify package manager from lock files (bun/pnpm/yarn/npm/uv/cargo/go). Identify validation commands — check for a completed plan matching the PR branch:
```bash
PR_BRANCH=$(gh pr view {NUMBER} --json headRefName -q '.headRefName' 2>/dev/null)
PLAN_SLUG=$(echo "$PR_BRANCH" | sed 's|^feature/||')
ls -t .prp-output/plans/completed/*${PLAN_SLUG}*.plan.md 2>/dev/null | head -1
```

> **Plan-provided commands take precedence — but only if the plan matches the PR branch**. If a matching plan has a Metadata table with validation commands, use those directly. Otherwise fall back to auto-detection.

**Fallback — auto-detect:**

| Ecosystem | Type Check | Lint | Test | Build |
|-----------|-----------|------|------|-------|
| JS/TS | `{runner} run type-check` | `{runner} run lint` | `{runner} test` | `{runner} run build` |
| Python | `mypy .` | `ruff check .` | `pytest` | N/A |
| Rust | `cargo check` | `cargo clippy` | `cargo test` | `cargo build` |
| Go | `go vet ./...` | `golangci-lint run` | `go test ./...` | `go build ./...` |

**Store detected commands** — use consistently for all validation steps.

## Phase 1: LOAD — Get Review Artifact

**If input is a path**: use it directly, skip discovery.

**If input is a PR number** (or no input → `gh pr view --json number -q '.number'`):

```bash
ls -t .prp-output/reviews/pr-{NUMBER}-*review*.md 2>/dev/null
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

**Severity mapping table:**

| Review Section | Maps To |
|----------------|---------|
| Critical / Critical Issues / Critical (block merge) | **Critical** |
| High Priority / Important / Important Issues / Important (address before merge) | **High** |
| Medium Priority | **Medium** |
| Suggestions / Low / Suggestions (nice to have) | **Suggestion** |

> **Note**: The agents-review format does not use "Medium" — issues are either Critical, Important, or Suggestion. When parsing agents-review, treat Important as High. Codex/Gemini adapters use parenthetical labels — match on the keyword before the parenthetical.

## Phase 2: CHECKOUT — Get on PR Branch

```bash
CURRENT=$(git branch --show-current)
PR_BRANCH=$(gh pr view {NUMBER} --json headRefName -q '.headRefName')

if [ "$CURRENT" = "$PR_BRANCH" ]; then
  echo "Already on PR branch: $PR_BRANCH"
  if [ -n "$(git status --porcelain)" ]; then
    echo "⚠️ Working directory is dirty. Stash or commit changes first."
    # STOP if dirty
  fi
else
  gh pr checkout {NUMBER}
fi

git pull --rebase origin $(git branch --show-current) 2>/dev/null || true
```

| State | Action |
|-------|--------|
| MERGED / CLOSED | STOP: "Cannot apply fixes to closed PR" |
| OPEN / DRAFT | PROCEED |

## Phase 3: TRIAGE — Print Fix Plan

Before making any changes, print the fix plan:
- Show issue counts per severity
- Validation commands and their source (plan / auto-detected)
- List each issue with file and description
- Group by file for efficiency
- Show which issues will be skipped (out of severity filter)

## Phase 4: FIX — Apply Issues by Severity

Process in order: **Critical → High → Medium → Suggestion**

For each issue:
1. Read the target file at the flagged line
2. Apply the recommended fix (as stated in review)
3. Don't refactor unrelated code or make scope creep changes
4. Skip if: ambiguous fix, risky change, or drift from review expectations

**Validate after each severity batch using detected commands:**
```bash
{type_check_command}
{lint_command}
```

If validation fails: identify the failing fix → revert it → add to skip log → re-validate.

## Phase 5: VALIDATE — Full Suite

All must pass (using **detected commands** from Phase 0):
```bash
{type_check_command}
{lint_command}
{test_command}
{build_command}
```

If a fix causes test failure: revert and skip that fix.

**GATE**: Do NOT proceed to Phase 6 until all validation checks pass (or failing fixes are reverted and skipped).

## Phase 6: COMMIT & PUSH

**Do NOT use `git add -A`** — stage only intentionally modified files:

```bash
git diff --name-only | xargs -r git add
git ls-files --others --exclude-standard | xargs -r git add
git diff --cached --name-only  # verify no unexpected files

git commit -m "fix: apply review fixes for PR #{NUMBER}

Address {N} issues: {N_critical} critical, {N_high} high, {N_medium} medium, {N_suggestion} suggestions
Skipped {N_skipped} (see PR comment for details)"

git push origin $(git branch --show-current)
```

If nothing to commit: skip and report "No changes needed."

## Phase 7: REPORT — Post Summary and Update Artifacts

**Save fix summary locally (with timestamp):**

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
SUMMARY_FILE=".prp-output/reviews/pr-${NUMBER}-fix-summary-${TIMESTAMP}.md"
mkdir -p .prp-output/reviews
```

Write summary to `$SUMMARY_FILE` (fix counts table, validation results, skipped issues, commit hash), then post:

```bash
gh pr comment ${NUMBER} --body-file "$SUMMARY_FILE"
```

> **Note**: Uses `-fix-summary` suffix to identify fix summaries separately from review files.

**Update review artifact**: Append "Fix Outcome" section with timestamp, commit hash, and fix counts.

## Output

Report to user:
- PR number, branch, commit hash
- Fixed/skipped table per severity
- Validation results
- Artifacts: fix summary path, review artifact updated
- Next steps:
  - All critical/high fixed → "Run `/prp:review {NUMBER}` to verify."
  - Critical still open → "⚠️ {N} critical issues need manual attention before merge."

> **Note for orchestrators**: The "Next Steps" above are for standalone usage only. If this command was invoked as part of run-all, the orchestrator should ignore these suggestions and proceed to its next step.

## Edge Cases

- **No artifact**: STOP, instruct to run review first
- **PR branch has conflicts**: Warn user to resolve conflicts first: `git rebase origin/{base-branch}`
- **Drift detected**: Warn user, attempt fix if context clear, else skip
- **Already fixed**: Skip silently ("already addressed")
- **All skipped**: No commit, report all skip reasons
- **Suggestion-only issues**: By default included. To skip: `--severity critical,high,medium`

## Usage

```
/prp:review-fix 163                          # Fix all issues
/prp:review-fix 163 --severity critical,high # Critical and high only
/prp:review-fix                              # Current branch's PR
/prp:review-fix .prp-output/reviews/pr-42-review-opencode.md  # By path
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

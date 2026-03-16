---
description: Implement a fix from investigation artifact - code changes, PR, and self-review
---

# PRP Issue Fix — Implement from Investigation Artifact

Target: $ARGUMENTS

Format: `<issue-number|artifact-path>`

## Mission

Execute the implementation plan from `/prp-issue-investigate`: load artifact, implement changes, validate, create PR linked to issue, self-review, and archive.

**Golden Rule**: Follow the artifact. If something seems wrong, validate first — don't silently deviate.

## Step 1: LOAD — Get Artifact

**If input is a number** (`123`, `#123`):
```bash
ls -t .prp-output/issues/issue-{number}*.md 2>/dev/null | head -1
```

**If input is a path**: use directly.

Parse artifact: issue number/title, type, files to modify (with lines), implementation steps, validation commands, test cases.

If not found: STOP — "Run `/prp-issue-investigate {number}` first."

## Step 2: VALIDATE — Drift Detection

For each file in the artifact:
1. Read actual current code
2. Compare to what artifact expects ("current code" snippets)
3. Check if code has changed since investigation

**If significant drift**: warn user, suggest re-running `/prp-issue-investigate`, or proceed with caution if changes are minor.

**If approach seems wrong**: STOP, explain, suggest re-investigation.

## Step 3: GIT-CHECK — Ensure Correct State

```bash
git branch --show-current
git status --porcelain
git fetch origin
```

| State | Action |
|-------|--------|
| On main, clean | Create branch: `git checkout -b fix/issue-{number}-{slug}` |
| On main, dirty | STOP: "Commit or stash changes first" |
| On feature/fix branch | Use it (warn if name doesn't match issue) |
| In worktree | Use as-is |

Ensure up-to-date: `git pull --rebase origin main`

## Step 4: IMPLEMENT — Make Changes

For each step in artifact's Implementation Plan:
1. Read target file, understand current state
2. Make change exactly as specified
3. Verify types compile

**DO**: Follow artifact order, match code style, copy patterns from "Patterns to Follow", add specified tests.

**DON'T**: Refactor unrelated code, add unplanned improvements, change formatting of untouched lines, deviate without noting it.

Track any deviations for PR description.

## Step 5: VERIFY — Run Validation

Run all validation commands from artifact (adapt to project toolchain):
```bash
{type_check_command}
{test_command}
{lint_command}
```

**All must pass.** If failures: analyze, fix, re-validate, note fixes in PR. Execute manual verification steps if specified.

**GATE**: Do NOT proceed until all validation passes.

## Step 6: COMMIT — Safe Staging

```bash
git diff --name-only | xargs -r git add
git ls-files --others --exclude-standard | xargs -r git add
git diff --cached --name-only  # verify no unexpected files

git commit -m "$(cat <<'EOF'
Fix: {title} (#{number})

{problem statement}

Changes:
- {change 1}
- {change 2}

Fixes #{number}
EOF
)"
```

## Step 7: PR — Create Pull Request

```bash
git push -u origin HEAD

gh pr create --title "Fix: {title} (#{number})" --body "$(cat <<'EOF'
## Summary
{problem statement}

## Root Cause
{root cause from artifact}

## Changes
| File | Change |
|------|--------|
| `src/x.ts` | {description} |

## Testing
- [x] Type check passes
- [x] Tests pass
- [x] Lint passes

Fixes #{number}

_Implementation from artifact: `.prp-output/issues/issue-{number}-{TIMESTAMP}.md`_
EOF
)"
```

## Step 8: REVIEW — Self Code Review

Review the diff focusing on: root cause addressed, code quality, test coverage, edge cases, security, potential bugs.

Post review as PR comment:
```bash
gh pr comment --body "$(cat <<'EOF'
## Automated Code Review
{assessment, strengths, suggestions, security check, checklist}
*Self-reviewed by AI*
EOF
)"
```

## Step 9: ARCHIVE — Clean Up

```bash
mkdir -p .prp-output/issues/completed
mv .prp-output/issues/issue-{number}-{TIMESTAMP}.md .prp-output/issues/completed/
git add .prp-output/issues/
git commit -m "Archive investigation for issue #{number}"
git push
```

## Step 10: REPORT — Output to User

Display: issue number/title, branch, PR number/URL, changes table, validation results, self-review summary, archived artifact path, next steps (human review, merge).

## Edge Cases

- **Artifact outdated**: warn drift, suggest re-investigation
- **Tests fail**: debug failure, fix code (not test unless test is wrong), re-validate
- **Merge conflicts**: resolve, re-validate, note in PR
- **PR creation fails**: check existing PR for branch, provide manual command
- **Branch with changes**: use existing, warn if name mismatch

## Usage

```
/prp-issue-fix 123
/prp-issue-fix .prp-output/issues/issue-123-20260315-1430.md
```

## Success Criteria

- PLAN_EXECUTED: All artifact steps completed
- VALIDATION_PASSED: All checks green
- PR_CREATED: PR exists and linked to issue with "Fixes #{number}"
- REVIEW_POSTED: Self-review comment on PR
- ARTIFACT_ARCHIVED: Moved to completed folder
- AUDIT_TRAIL: Full history in git and GitHub

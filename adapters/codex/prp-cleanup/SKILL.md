---
name: prp-cleanup
description: Clean up branches and verify PR status after merge. Supports single branch, batch mode (--all), and dry-run preview.
metadata:
  short-description: Post-merge branch cleanup
---

# PRP Cleanup — Post-Merge Branch Cleanup

## Input

Branch name and optional flags: `$ARGUMENTS`

Format: `[branch-name] [--all] [--dry-run]`

## Mission

Clean up local and remote branches after PR merge. Verify PR is actually merged before deleting anything. Safety first — never delete unmerged branches.

## Phase 1: PARSE & VALIDATE

### Parse Flags

```
DRY_RUN = true if "--dry-run" found
ALL_MODE = true if "--all" found
BRANCH = first non-flag argument (if any)
```

### Determine Targets

**Single mode:**

| Input | Target |
|-------|--------|
| Branch name provided | Use that branch |
| No name + not on main | Use current branch |
| No name + on main | STOP: "Specify a branch or use --all" |

**Batch mode (`--all`):**

```bash
git fetch --prune origin
git branch --merged main | grep -v -E '^\*?\s*(main|master)$'
```

If no branches found: STOP: "No merged branches. Nothing to clean up."

If currently on target branch: `git checkout main && git pull origin main` first.

## Phase 2: VERIFY PR STATUS

For each target branch:

```bash
gh pr list --head {branch} --state all --json number,title,state,mergedAt,url --limit 1
```

| PR State | Action |
|----------|--------|
| MERGED | Proceed to cleanup |
| OPEN | SKIP: "PR still open" |
| CLOSED (not merged) | SKIP |
| No PR found | WARN, ask user to confirm or skip (batch: auto-skip) |

`--dry-run`: record status but don't stop — show what would happen.

## Phase 3: ARCHIVE ARTIFACTS

Commit PR-related artifacts to main before deleting branches.

### 3.1 Switch to Main

```bash
git checkout main
git pull origin main
```

### 3.2 Collect & Commit (for each verified branch)

Find related artifacts:
```bash
NUMBER={pr-number}
BRANCH={branch-name}

# Review artifacts, context files, fix summaries
ls .prp-output/reviews/pr-${NUMBER}-*.md 2>/dev/null
ls .prp-output/reviews/pr-context-${BRANCH}.md 2>/dev/null

# Implementation reports
grep -rl "PR.*#${NUMBER}\|Branch.*${BRANCH}" .prp-output/reports/ 2>/dev/null

# Completed plans
ls .prp-output/plans/completed/ 2>/dev/null
```

Stage and commit:
```bash
git add .prp-output/reviews/pr-${NUMBER}-*.md 2>/dev/null
git add .prp-output/reviews/pr-context-${BRANCH}.md 2>/dev/null
git add .prp-output/reports/*-report*.md 2>/dev/null
git add .prp-output/plans/completed/ 2>/dev/null

git diff --cached --quiet || git commit -m "chore: archive artifacts for PR #${NUMBER} (${BRANCH})"
```

- `--dry-run`: list artifacts that would be committed, don't commit
- No artifacts found: skip — "No artifacts to archive"

## Phase 4: CLEANUP

For each verified branch:

1. **Preview** (always): show branch, PR number, title, merged date, artifacts archived
2. **If `--dry-run`**: show preview only, skip to output
3. **Delete local**: `git branch -d {branch}` (force `-D` if PR confirmed merged but git says not fully merged)
4. **Delete remote**: `git push origin --delete {branch}`
5. **Prune refs**: `git remote prune origin`

## Phase 5: OUTPUT

### Summary Table

```markdown
## Cleanup Summary

| Branch | PR | Status | Artifacts | Local | Remote |
|--------|-----|--------|-----------|-------|--------|
| {branch} | #{number} | Merged | Committed | Deleted | Deleted |
| {branch2} | #{number} | Open | Skipped | Skipped | Skipped |

**Cleaned**: {N} branch(es)
**Skipped**: {M} branch(es)
```

### Dry Run Output

```markdown
## Dry Run Preview (no changes made)

Would archive artifacts:
- .prp-output/reviews/pr-{NUMBER}-review.md
- .prp-output/reviews/pr-context-{BRANCH}.md

Would clean up:
- {branch} (PR #{number}, merged {date})

Would skip:
- {branch2} (PR #{number}, still open)

Run without --dry-run to execute.
```

## Edge Cases

| Situation | Action |
|-----------|--------|
| On target branch | Auto-switch to main first |
| Branch not fully merged (git) | Force delete if PR confirmed merged |
| Remote already deleted | Skip gracefully |
| No PR found | Ask or auto-skip in batch |
| No merged branches (`--all`) | Exit: "Nothing to clean up" |
| Protected branches (main/master) | Never included |
| Network error on `gh` | Report, continue with next branch |
| Detached HEAD | Require explicit branch name |

## Usage Examples

```
$prp-cleanup                        # Current branch
$prp-cleanup feat/user-auth         # Specific branch
$prp-cleanup --all                  # All merged branches
$prp-cleanup --all --dry-run        # Preview batch cleanup
```

## Success Criteria

- PR_VERIFIED: Merge status confirmed before deletion
- ARTIFACTS_ARCHIVED: Related artifacts committed to main
- LOCAL_DELETED: Local branch removed (or confirmed gone)
- REMOTE_DELETED: Remote branch removed (or confirmed gone)
- REFS_PRUNED: Stale remote tracking references cleaned
- DRY_RUN_SAFE: --dry-run never deletes anything
- PROTECTED_BRANCHES: main/master never targeted

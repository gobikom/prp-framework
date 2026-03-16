---
description: Clean up branches and verify PR status after merge
argument-hint: [branch-name] [--all] [--dry-run]
---

# Post-Merge Cleanup

**Input**: $ARGUMENTS

---

## Your Mission

Clean up local and remote branches after a PR has been merged. Verify the PR is actually merged before deleting anything. Supports single branch, batch mode, and dry-run preview.

**Golden Rule**: Never delete a branch unless its PR is confirmed merged. Safety first.

---

## Phase 1: PARSE & VALIDATE

### 1.1 Parse Flags

```
DRY_RUN   = true if "--dry-run" found in $ARGUMENTS, else false
ALL_MODE  = true if "--all" found in $ARGUMENTS, else false
BRANCH    = first non-flag argument (if any)
```

### 1.2 Determine Target Branches

**Single mode (default):**

| Input | Target |
|-------|--------|
| `branch-name` provided | Use that branch |
| No branch name + not on main | Use current branch |
| No branch name + on main | STOP: "Specify a branch name or use --all" |

**Batch mode (`--all`):**

```bash
# Fetch latest remote state
git fetch --prune origin

# Find all local branches merged into main (exclude main/master itself)
git branch --merged main | grep -v -E '^\*?\s*(main|master)$'
```

| Result | Action |
|--------|--------|
| Branches found | Proceed with all of them |
| No branches | STOP: "No merged branches found. Nothing to clean up." |

### 1.3 Switch Off Target Branch (if needed)

```bash
CURRENT=$(git branch --show-current)
```

If cleaning up the current branch (single mode):

```bash
git checkout main
git pull origin main
```

**PHASE_1_CHECKPOINT:**
- [ ] Flags parsed
- [ ] Target branch(es) determined
- [ ] Not currently on any target branch

---

## Phase 2: VERIFY PR STATUS

For each target branch:

### 2.1 Find Associated PR

```bash
gh pr list --head {branch} --state all --json number,title,state,mergedAt,url --limit 1
```

### 2.2 Check Merge Status

| PR State | Action |
|----------|--------|
| `MERGED` | Proceed to cleanup |
| `OPEN` | SKIP: "PR #{number} is still open. Merge it first." |
| `CLOSED` (not merged) | SKIP: "PR #{number} was closed without merging." |
| No PR found | WARN: "No PR found for branch {branch}." Ask user to confirm deletion or skip. |

**If `DRY_RUN`:** Record status but don't stop — show what would happen.

**PHASE_2_CHECKPOINT:**
- [ ] PR status verified for all target branches
- [ ] Only merged branches proceed to cleanup

---

## Phase 3: ARCHIVE ARTIFACTS

Commit PR-related artifacts to main so they're preserved in git history.

### 3.1 Switch to Main

```bash
git checkout main
git pull origin main
```

### 3.2 Collect Artifacts (for each verified branch)

Find all artifacts related to this PR/branch:

```bash
NUMBER={pr-number}
BRANCH={branch-name}

# Review artifacts
ls .prp-output/reviews/pr-${NUMBER}-*.md 2>/dev/null
ls .prp-output/reviews/pr-context-${BRANCH}.md 2>/dev/null

# Implementation reports
grep -rl "PR.*#${NUMBER}\|Branch.*${BRANCH}" .prp-output/reports/ 2>/dev/null

# Completed plans (already archived by implement step)
ls .prp-output/plans/completed/ 2>/dev/null
```

### 3.3 Stage and Commit Artifacts

```bash
git add .prp-output/reviews/pr-${NUMBER}-*.md 2>/dev/null
git add .prp-output/reviews/pr-context-${BRANCH}.md 2>/dev/null
git add .prp-output/reports/*-report*.md 2>/dev/null
git add .prp-output/plans/completed/ 2>/dev/null

# Only commit if there are staged changes
git diff --cached --quiet || git commit -m "chore: archive artifacts for PR #${NUMBER} (${BRANCH})"
```

**If `DRY_RUN`:** List artifacts that would be committed but don't commit.

**If no artifacts found:** Skip — record "No artifacts to archive."

**PHASE_3_CHECKPOINT:**
- [ ] On main branch
- [ ] Artifacts found and committed (or none found)

---

## Phase 4: CLEANUP

For each verified branch:

### 4.1 Preview (always show)

```markdown
Branch: {branch}
PR: #{number} — {title}
Merged: {mergedAt}
Actions: archive artifacts + delete local + delete remote
```

**If `DRY_RUN`:** Show preview only, skip to Phase 5.

### 4.2 Delete Local Branch

```bash
git branch -d {branch}
```

| Result | Action |
|--------|--------|
| Success | Record: "Local branch deleted" |
| Not fully merged error | Try `git branch -D {branch}` (PR is confirmed merged, safe to force) |
| Branch not found | Record: "Local branch already deleted" |

### 4.3 Delete Remote Branch

```bash
git push origin --delete {branch}
```

| Result | Action |
|--------|--------|
| Success | Record: "Remote branch deleted" |
| Already deleted / not found | Record: "Remote branch already deleted" |
| Permission error | Record: "Failed to delete remote branch (permission denied)" |

### 4.4 Prune Remote Tracking Refs

```bash
git remote prune origin
```

**PHASE_4_CHECKPOINT:**
- [ ] Local branch deleted (or already gone)
- [ ] Remote branch deleted (or already gone)
- [ ] Stale refs pruned

---

## Phase 5: OUTPUT

### 5.1 Summary Table

```markdown
## Cleanup Summary

| Branch | PR | Status | Artifacts | Local | Remote |
|--------|-----|--------|-------|--------|
| {branch} | #{number} | Merged | Committed | Deleted | Deleted |
| {branch2} | #{number} | Open | Skipped | Skipped | Skipped |

**Cleaned**: {N} branch(es)
**Skipped**: {M} branch(es)
```

### 5.2 Dry Run Output (if `DRY_RUN`)

```markdown
## Dry Run Preview (no changes made)

Would archive artifacts:
- .prp-output/reviews/pr-{NUMBER}-review.md
- .prp-output/reviews/pr-context-{BRANCH}.md

Would clean up:
- {branch} (PR #{number}, merged {date})
- {branch2} (PR #{number}, merged {date})

Would skip:
- {branch3} (PR #{number}, still open)

Run without --dry-run to execute.
```

### 5.3 Next Steps

```markdown
### Tips
- Clean old artifacts: `./scripts/cleanup-artifacts.sh 30`
- View remaining branches: `git branch -a`
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| On target branch | Auto-switch to main first |
| Branch not fully merged (git) | Force delete if PR confirmed merged |
| Remote branch already deleted | Skip gracefully, not an error |
| No PR found for branch | Ask user to confirm or skip (batch: auto-skip) |
| No merged branches (`--all`) | Exit with message "Nothing to clean up" |
| PR still open | Skip branch, report in summary |
| Network error on `gh` | Report error, continue with next branch |
| Protected branch (main/master) | Never include in cleanup targets |
| Detached HEAD state | Require explicit branch name |

---

## Examples

```
/prp-core:cleanup                        # Clean up current branch
/prp-core:cleanup feat/user-auth         # Clean up specific branch
/prp-core:cleanup --all                  # Clean all merged branches
/prp-core:cleanup --all --dry-run        # Preview batch cleanup
/prp-core:cleanup feat/login --dry-run   # Preview single cleanup
```

---

## Success Criteria

- **PR_VERIFIED**: PR merge status confirmed before any branch deletion
- **ARTIFACTS_ARCHIVED**: Related artifacts committed to main before cleanup
- **LOCAL_DELETED**: Local branch removed (or confirmed already gone)
- **REMOTE_DELETED**: Remote branch removed (or confirmed already gone)
- **REFS_PRUNED**: Stale remote tracking references cleaned
- **DRY_RUN_SAFE**: `--dry-run` never deletes anything, only previews
- **PROTECTED_BRANCHES**: main/master never included as cleanup targets
- **DRY_RUN_SAFE**: `--dry-run` never deletes anything, only previews
- **PROTECTED_BRANCHES**: main/master never included as cleanup targets

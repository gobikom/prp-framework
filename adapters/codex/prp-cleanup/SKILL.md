---
name: prp-cleanup
description: Post-merge cleanup — verify PR merged, archive artifacts, delete local/remote branches. Supports --all for batch cleanup, --dry-run for preview.
metadata:
  short-description: Post-merge cleanup
---

# PRP Cleanup — Post-Merge Branch & Artifact Cleanup

## Input

Branch name or flags: `$ARGUMENTS`

Format: `[branch-name] [--all] [--dry-run]`

## Mission

Clean up after a PR is merged: verify merge status, archive artifacts, delete local and remote branches. Prevent orphaned branches and stale artifacts.

**Golden Rule**: Never delete a branch whose PR hasn't been merged. Always verify first.

---

## Phase 1: PARSE & VALIDATE

### 1.1 Parse Flags

```
DRY_RUN = true if "--dry-run" found in $ARGUMENTS
ALL_MODE = true if "--all" found in $ARGUMENTS
TARGET_BRANCH = remaining argument (if any)
```

### 1.2 Determine Targets

**Single branch mode** (default):

| Input | Action |
|-------|--------|
| Branch name provided | Use it as target |
| No branch, on feature branch | Use current branch |
| No branch, on main | STOP: "Specify a branch or use --all" |

**Batch mode** (`--all`):

```bash
# Find all local branches except main/master/develop
git branch --format='%(refname:short)' | grep -v -E '^(main|master|develop)$'
```

### 1.3 Switch Off Branch (if needed)

If currently on a branch that will be deleted:

```bash
git checkout main
git pull origin main
```

**PHASE_1_CHECKPOINT:**
- [ ] Flags parsed (DRY_RUN, ALL_MODE, TARGET_BRANCH)
- [ ] Target branches identified
- [ ] Not on a branch that will be deleted

---

## Phase 2: VERIFY — Check PR Merge Status

### 2.1 Find Associated PR

For each target branch:

```bash
gh pr list --head {branch} --state all --json number,title,state,mergedAt
```

### 2.2 Check Merge Status

| State | Action |
|-------|--------|
| `MERGED` | PROCEED — safe to clean up |
| `OPEN` | SKIP — "PR #{N} is still open. Merge or close before cleanup." |
| `CLOSED` (not merged) | WARN — "PR #{N} was closed without merging. Delete anyway?" In batch/dry-run: auto-skip. |
| No PR found | WARN — "No PR found for branch. Delete anyway?" In batch: auto-skip. |

**If `DRY_RUN`**: Record status but don't stop — show what would happen.

**PHASE_2_CHECKPOINT:**
- [ ] PR status verified for each target branch
- [ ] Only merged branches proceed to cleanup

---

## Phase 3: ARCHIVE — Save Artifacts Before Deletion

### 3.1 Switch to Main

```bash
git checkout main
git pull origin main
```

### 3.2 Collect Artifacts

For each verified branch, collect related artifacts.

**Prefer manifest** (precise discovery):

```bash
# Check for manifest with exact artifact paths
MANIFEST=".prp-output/manifests/${BRANCH}.json"
if [ -f "$MANIFEST" ]; then
  # Read exact paths from manifest — plan, report, context, reviews, fixes
  cat "$MANIFEST"
fi
```

**Fallback to glob** (if no manifest found):

```bash
# Review artifacts
ls .prp-output/reviews/pr-${NUMBER}-*.md 2>/dev/null

# Review context
ls .prp-output/reviews/pr-context-${BRANCH}.md 2>/dev/null

# Implementation reports
ls .prp-output/reports/*-report*.md 2>/dev/null

# Fix summaries
ls .prp-output/reviews/pr-${NUMBER}-fix-summary*.md 2>/dev/null

# Completed plans
ls .prp-output/plans/completed/*.plan.md 2>/dev/null

# Issue investigations
ls .prp-output/issues/issue-*.md 2>/dev/null
```

### 3.3 Stage & Commit Artifacts

```bash
git add {collected artifacts}
git commit -m "chore: archive artifacts for PR #${NUMBER} (${BRANCH})"
```

### 3.4 Remove Manifest

```bash
rm -f .prp-output/manifests/${BRANCH}.json
```

**If `DRY_RUN`**: List artifacts that would be committed, don't commit.
**If no artifacts found**: Skip — record "No artifacts to archive."

**PHASE_3_CHECKPOINT:**
- [ ] Artifacts collected (manifest-first, glob fallback)
- [ ] Artifacts committed to main (or dry-run listed)
- [ ] Manifest removed (if existed)

---

## Phase 4: CLEANUP — Delete Branches

### 4.1 Preview

For each branch, show:
```
Branch: {branch}
PR: #{number} - {title}
Merged: {date}
Artifacts: {count} archived
Action: Delete local + remote
```

**If `DRY_RUN`**: Show preview only, skip deletion.

### 4.2 Delete Local Branch

```bash
git branch -d {branch}
```

**If fails** (unmerged changes warning):
```bash
# Force delete — safe because we verified PR was merged
git branch -D {branch}
```

**If still fails** (branch doesn't exist locally): Skip — already deleted.

### 4.3 Delete Remote Branch

```bash
git push origin --delete {branch}
```

**If fails** (already deleted): Skip — already cleaned up.
**If fails** (permission denied): WARN — "Cannot delete remote branch. Check permissions."

### 4.4 Prune Remote References

```bash
git remote prune origin
```

### 4.5 Remove Orphaned State Files

```bash
# Remove run-all state file if it refers to the cleaned branch
if grep -q "${BRANCH}" .claude/prp-run-all.state.md 2>/dev/null; then
  rm -f .claude/prp-run-all.state.md
fi
```

**PHASE_4_CHECKPOINT:**
- [ ] Local branch deleted (or dry-run previewed)
- [ ] Remote branch deleted (or dry-run previewed)
- [ ] Remote refs pruned
- [ ] Orphaned state files removed

---

## Phase 5: OUTPUT — Report Results

### 5.1 Summary Table

```markdown
## Cleanup Summary

| Branch | PR | Status | Artifacts | Local | Remote |
|--------|----|--------|-----------|-------|--------|
| `feat/auth` | #42 | Merged | 3 archived | Deleted | Deleted |
| `fix/typo` | #45 | Merged | 0 | Deleted | Deleted |
| `feat/old` | — | No PR | — | Skipped | Skipped |
```

**Cleaned**: {N} branches
**Skipped**: {M} branches (open/no PR/unmerged)

### 5.2 Dry Run Output

```markdown
## Dry Run Preview (no changes made)

| Branch | PR | Would Do |
|--------|----|----------|
| `feat/auth` | #42 (Merged) | Archive 3 artifacts, delete local + remote |
| `fix/typo` | #45 (Merged) | No artifacts, delete local + remote |
| `feat/wip` | #50 (Open) | Skip — PR still open |
```

### 5.3 Tips

```
Tip: To clean old artifacts, run: ./scripts/cleanup-artifacts.sh 30
Tip: To see all branches: git branch -a
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| Branch not found locally | Skip local delete, try remote only |
| Remote branch already gone | Skip remote delete, prune refs |
| PR not found for branch | Warn user, skip in batch mode |
| Detached HEAD state | Require explicit branch name |
| Protected branch (main/master/develop) | STOP — never delete |
| Branch has unmerged commits | Warn — only force delete if PR confirmed merged |
| Artifacts span multiple branches | Archive only artifacts matching the specific branch/PR |
| `--all` with no feature branches | "No feature branches to clean up." |

---

## Usage Examples

```
$prp-cleanup                           # Current branch
$prp-cleanup feat/auth                 # Specific branch
$prp-cleanup --all                     # All merged branches
$prp-cleanup --all --dry-run           # Preview batch cleanup
$prp-cleanup feat/login --dry-run      # Preview single branch
```

---

## Success Criteria

- FLAGS_PARSED: --all, --dry-run, target branch correctly identified
- PR_VERIFIED: Merge status confirmed before any deletion
- ARTIFACTS_ARCHIVED: Related PRP artifacts committed to main
- MANIFEST_USED: Manifest-first discovery attempted before glob fallback
- LOCAL_DELETED: Local branch removed (or skipped with reason)
- REMOTE_DELETED: Remote branch removed (or skipped with reason)
- STATE_CLEANED: Orphaned state files removed

---
description: Safely roll back implementation changes with git stash backup and restore
---

# PRP Rollback — Safely Undo Implementation Changes

Target: $ARGUMENTS

Format: `[--soft | --hard | --restore]`

## Mission

Safely undo implementation changes on the current branch, with stash backup so you can restore if needed.

**Modes:**

| Flag | Behavior |
|------|----------|
| *(none)* | Interactive — show changes, ask which mode |
| `--soft` | Unstage changes only (keep working directory) |
| `--hard` | Full revert to origin/main HEAD (destructive, stash backup first) |
| `--restore` | Restore from most recent PRP rollback stash |

## Step 1: INSPECT — Current State

```bash
BRANCH=$(git branch --show-current)
git status --short
git log origin/main..HEAD --oneline
git diff --stat origin/main..HEAD
```

Display: branch name, uncommitted changes count, commits ahead of main, diff stat.

## Step 2: HANDLE --restore

If `--restore` flag:

```bash
git stash list | grep "prp-rollback" | head -1
```

| Result | Action |
|--------|--------|
| Found | Show stash contents, confirm, `git stash pop stash@{N}` |
| Not found | STOP: "No PRP rollback stash found. Nothing to restore." |

After restore: display what was restored. Done.

## Step 3: DETERMINE MODE (if no flag)

If no flag provided, show options and ask:

```
What would you like to roll back?

  [1] --soft  Unstage all changes (keep files in working directory)
              Safe: no data loss, can re-stage manually

  [2] --hard  Revert to origin/main HEAD (removes all commits + changes)
              Destructive: stash backup will be created first

  [3] Cancel  Do nothing
```

Wait for selection. If `[3]`, STOP.

## Step 4: EXECUTE

### --soft Mode

```bash
git reset HEAD~{N} --soft   # if commits ahead of main
# or
git restore --staged .       # if only staged changes, no commits
```

Display: "Changes unstaged. Files preserved in working directory."

### --hard Mode

**4a — Stash backup FIRST:**
```bash
STASH_MSG="prp-rollback-$(date +%Y%m%d-%H%M)-{BRANCH}"
git stash push -u -m "$STASH_MSG"
```

| Result | Action |
|--------|--------|
| Stash created | Proceed |
| Nothing to stash | Note and proceed |
| Error | STOP: report error |

**4b — Reset:**
```bash
git reset --hard origin/main
```

**4c — Confirm:**
```bash
git log --oneline -3
git status --short
```

Display: branch, reset target commit, stash backup name, restore instructions.

## Step 5: CLEANUP (optional)

If branch is now identical to main (0 commits ahead), suggest:

```
Branch {BRANCH} is now identical to origin/main.
To delete this branch: git checkout main && git branch -d {BRANCH}
```

Do NOT delete automatically. Only suggest.

## Critical Rules

1. **Always stash before --hard.** Never `git reset --hard` without backup.
2. **Never delete branches.** Only suggest, never execute.
3. **Show before destroy.** Display what will be affected before --hard.
4. **--soft is always safe.** No confirmation needed.
5. **--restore is idempotent.** Report conflicts clearly if stash pop fails.

## Usage

```
/prp-rollback                # Interactive mode
/prp-rollback --soft         # Unstage only
/prp-rollback --hard         # Full revert with backup
/prp-rollback --restore      # Restore from backup
```

## Success Criteria

- STASH_CREATED: Backup stash exists before any --hard operation
- STATE_CLEAN: `git status` shows expected state after rollback
- RESTORE_WORKS: Stash can be popped to recover changes
- NO_DATA_LOSS: User's work is always recoverable via `--restore`

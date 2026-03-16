---
description: Safely undo implementation changes with stash backup and restore
agent: build
---

# PRP Rollback — Safely Undo Changes

Mode: $ARGUMENTS

## Modes

| Flag | Behavior |
|------|----------|
| *(none)* | Interactive — show changes, ask which mode |
| `--soft` | Unstage changes only (keep working directory) |
| `--hard` | Full revert to origin/main HEAD (stash backup first) |
| `--restore` | Restore from the most recent PRP rollback stash |

## Steps

1. **Inspect Current State**:
   ```bash
   BRANCH=$(git branch --show-current)
   git status --short
   git log origin/main..HEAD --oneline
   ```
   Display: branch, uncommitted file count, commits ahead of origin/main, `git diff --stat origin/main..HEAD`.

2. **Handle --restore**:
   ```bash
   git stash list | grep "prp-rollback" | head -1
   ```
   - Found → show stash contents, confirm, `git stash pop stash@{N}`. Display restored files. Done.
   - Not found → STOP: "No PRP rollback stash found. Nothing to restore."

3. **Determine Mode** (if no flag): Show options with descriptions:
   - `[1] --soft` — Unstage all changes (safe, no data loss)
   - `[2] --hard` — Revert to origin/main HEAD (destructive, stash backup created first)
   - `[3] Cancel` — Do nothing
   Wait for user selection. `[3]` → STOP.

4. **Execute --soft**:
   ```bash
   git reset HEAD~{N} --soft   # if commits ahead of main
   # or
   git restore --staged .      # if only staged changes, no commits
   ```
   Display: "Changes unstaged. Files preserved in working directory."

5. **Execute --hard**:
   - **5a — Stash backup FIRST**:
     ```bash
     STASH_MSG="prp-rollback-$(date +%Y%m%d-%H%M)-{BRANCH}"
     git stash push -u -m "$STASH_MSG"
     ```
   - **5b — Reset**: `git reset --hard origin/main`
   - **5c — Confirm**: `git log --oneline -3` + `git status --short`
   - Display: branch, reset commit hash, stash backup name, restore instructions.

6. **Cleanup suggestion** (optional): If branch is now identical to main (0 commits ahead), suggest `git checkout main && git branch -d {BRANCH}`. Do NOT delete automatically.

## Critical Rules

1. **Always stash before --hard.** Never `git reset --hard` without stash backup.
2. **Never delete branches.** Only suggest, never execute.
3. **Show before destroy.** Display what will be affected before --hard.
4. **--soft is always safe.** No confirmation needed.
5. **--restore is idempotent.** If stash pop fails (conflicts), report clearly.

## Usage

```
/prp:rollback              # Interactive mode
/prp:rollback --soft       # Unstage only
/prp:rollback --hard       # Full revert with backup
/prp:rollback --restore    # Recover from rollback
```

## Success Criteria

- STASH_CREATED: Backup stash exists before any --hard operation
- STATE_CLEAN: `git status` shows expected state after rollback
- RESTORE_WORKS: Stash can be popped to recover changes
- NO_DATA_LOSS: User's work is always recoverable via --restore

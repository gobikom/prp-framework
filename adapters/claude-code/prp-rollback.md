---
description: Safely roll back implementation changes with git stash backup and restore
argument-hint: [--soft | --hard] [--restore]
---

# PRP Rollback

**Input**: $ARGUMENTS

---

## Your Mission

Safely undo implementation changes on the current branch, with a stash backup so you can restore if needed.

**Modes:**
| Flag | Behavior |
|------|----------|
| *(none)* | Interactive — show changes, ask which mode |
| `--soft` | Unstage changes only (keep working directory) |
| `--hard` | Full revert to origin/main HEAD (destructive, stash backup first) |
| `--restore` | Restore from the most recent PRP rollback stash |

---

## Step 1: INSPECT CURRENT STATE

```bash
# Current branch
BRANCH=$(git branch --show-current)

# Uncommitted changes
git status --short

# Commits ahead of main
git log origin/main..HEAD --oneline
```

Display summary:
```
Branch: {BRANCH}
Uncommitted changes: {N files}
Commits ahead of origin/main: {N commits}

Changes:
{git diff --stat origin/main..HEAD}
```

---

## Step 2: HANDLE --restore

**If `--restore` flag set:**

```bash
# Find the most recent PRP rollback stash
git stash list | grep "prp-rollback" | head -1
```

| Result | Action |
|--------|--------|
| Found | Show stash contents, confirm restore: `git stash pop stash@{N}` |
| Not found | STOP: "No PRP rollback stash found. Nothing to restore." |

**After restore**: Display what was restored. Done.

---

## Step 3: DETERMINE MODE (if not --soft or --hard)

**If no flag provided**, show the options and ask:

```
What would you like to roll back?

  [1] --soft  Unstage all changes (keep files in working directory)
              Safe: no data loss, can re-stage manually

  [2] --hard  Revert to origin/main HEAD (removes all commits + changes)
              Destructive: stash backup will be created first

  [3] Cancel  Do nothing
```

Wait for user selection. Map to `--soft` or `--hard` accordingly. If `[3]` → STOP.

---

## Step 4: EXECUTE ROLLBACK

### Mode: --soft

```bash
# Unstage all staged changes
git reset HEAD~{N} --soft   # if commits ahead of main
# or
git restore --staged .      # if only staged changes, no commits
```

Display: "Changes unstaged. Files preserved in working directory."

### Mode: --hard

**Step 4a — Create stash backup FIRST:**

```bash
STASH_MSG="prp-rollback-$(date +%Y%m%d-%H%M)-{BRANCH}"

# Stash everything (committed + uncommitted)
git stash push -u -m "$STASH_MSG"
```

| Result | Action |
|--------|--------|
| Stash created | Proceed to 4b |
| Nothing to stash (clean) | Note: "Nothing to stash. Proceeding." |
| Stash error | STOP: report error |

**Step 4b — Reset to origin/main:**

```bash
git reset --hard origin/main
```

**Step 4c — Confirm state:**

```bash
git log --oneline -3
git status --short
```

Display result:
```
✅ Rollback complete

Branch: {BRANCH}
Reset to: origin/main ({commit hash})

Stash backup created: {STASH_MSG}
To restore: /prp-core:prp-rollback --restore
```

---

## Step 5: CLEANUP (optional)

**If branch is now identical to main and user wants to delete:**

```bash
# Check if safe to delete
git log origin/main..HEAD --oneline | wc -l
```

Only offer cleanup if there are 0 commits ahead:

```
Branch {BRANCH} is now identical to origin/main.
To delete this branch: git checkout main && git branch -d {BRANCH}
```

Do NOT delete automatically.

---

## Critical Rules

1. **Always stash before --hard.** Never run `git reset --hard` without creating a stash backup first.
2. **Never delete branches.** Only suggest, never execute branch deletion.
3. **Show before destroy.** Always display what will be affected before executing --hard.
4. **--soft is always safe.** No confirmation needed for --soft mode.
5. **--restore is idempotent.** If stash pop fails (conflicts), report clearly without leaving dirty state.

---

## Usage Examples

```bash
/prp-core:rollback                  # Interactive — choose mode
/prp-core:rollback --soft           # Unstage changes, keep working dir
/prp-core:rollback --hard           # Reset to origin/main (stash backup first)
/prp-core:rollback --restore        # Restore from rollback stash
```

---

## Success Criteria

- `STASH_CREATED`: Backup stash exists before any --hard operation
- `STATE_CLEAN`: `git status` shows clean or expected state after rollback
- `RESTORE_WORKS`: Stash can be popped to recover changes if needed
- `NO_DATA_LOSS`: User's work is always recoverable via `--restore`

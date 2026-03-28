---
description: Safely undo implementation changes with stash backup. Supports --soft, --hard, and --restore modes.
agent: plan
---

# PRP Rollback — Safely Undo Implementation Changes

## Input

Mode flags: `$ARGUMENTS`

Format: `[--soft | --hard | --restore]`

## Mission

Safely undo implementation changes on the current branch, with a stash backup so you can restore if needed.

**Modes:**

| Flag | Behavior |
|------|----------|
| *(none)* | Interactive — show changes, ask which mode |
| `--soft` | Unstage changes only (keep working directory) |
| `--hard` | Full revert to origin/main HEAD (destructive, stash backup first) |
| `--restore` | Restore from the most recent PRP rollback stash |

## Step 1: INSPECT CURRENT STATE

```bash
BRANCH=$(git branch --show-current)
git status --short
git log origin/main..HEAD --oneline
```

Display summary: Branch name, uncommitted changes count, commits ahead of origin/main, `git diff --stat origin/main..HEAD`.

## Step 2: HANDLE --restore

**If `--restore` flag set:**

```bash
git stash list | grep "prp-rollback" | head -1
```

| Result | Action |
|--------|--------|
| Found | Show stash contents, apply: `git stash pop stash@{N}` |
| Not found | STOP: "No PRP rollback stash found. Nothing to restore." |

**After restore**: Display what was restored. Done.

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

Wait for user selection. If `[3]` → STOP.

## Step 4: EXECUTE ROLLBACK

### Mode: --soft

```bash
# If commits ahead of main
git reset HEAD~{N} --soft

# If only staged changes, no commits
git restore --staged .
```

Display: "Changes unstaged. Files preserved in working directory."

### Mode: --hard

**Step 4a — Create stash backup FIRST:**

```bash
STASH_MSG="prp-rollback-$(date +%Y%m%d-%H%M)-{BRANCH}"
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

Display:

```markdown
## Hard Rollback Complete

**Branch**: `{BRANCH}`
**Reset to**: `{commit-hash}` (origin/main)
**Stash backup**: `{stash-name}`

To restore your work: `/prp:rollback --restore`
```

## Step 5: CLEANUP (optional)

**If branch is now identical to main** (0 commits ahead), offer:

```
Branch {BRANCH} is now identical to origin/main.
To delete this branch: git checkout main && git branch -d {BRANCH}
```

Do NOT delete automatically. Only suggest.

## Critical Rules

1. **Always stash before --hard.** Never run `git reset --hard` without creating a stash backup first.
2. **Never delete branches.** Only suggest, never execute branch deletion.
3. **Show before destroy.** Always display what will be affected before executing --hard.
4. **--soft is always safe.** No confirmation needed for --soft mode.
5. **--restore is idempotent.** If stash pop fails (conflicts), report clearly without leaving dirty state.

## Usage Examples

```
/prp:rollback                # Interactive — shows options
/prp:rollback --soft         # Unstage only, keep files
/prp:rollback --hard         # Full revert with stash backup
/prp:rollback --restore      # Recover from previous rollback
```

## Success Criteria

- STASH_CREATED: Backup stash exists before any --hard operation
- STATE_CLEAN: `git status` shows clean or expected state after rollback
- RESTORE_WORKS: Stash can be popped to recover changes if needed
- NO_DATA_LOSS: User's work is always recoverable via `--restore`

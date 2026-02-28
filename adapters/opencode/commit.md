---
description: Smart commit with natural language file targeting
agent: build
---

# PRP Commit

Target: $ARGUMENTS

0. **Pre-commit quality check (advisory)**: scan staged files for debug artifacts (TODO/FIXME, console.log/debugger), `any` type usage in .ts files, quick validation (skip in run-all). Warns but does NOT block commit.
1. `git status --short` — if nothing, stop
2. Stage matching files:
   - blank = all (`git add -A`)
   - `staged` = current staging
   - `*.ts` / `typescript files` = `git add "*.ts"`
   - `files in src/X` = `git add src/X/`
   - `except tests` = add all, then `git reset *test* *spec*`
   - `only new files` = add only untracked
   - `the X changes` = interpret from diff/context
3. Show staged: `git diff --cached --name-only`
4. Commit: `{type}: {description}` (types: feat/fix/refactor/docs/test/chore)
5. Output: hash, message, file count

## Examples

```
/prp:commit                          # All changes
/prp:commit typescript files         # *.ts only
/prp:commit except package-lock      # Exclude specific
/prp:commit only the new files       # Untracked only
/prp:commit staged                   # Already-staged only
```

## Edge Cases

Nothing to commit → STOP. Merge conflicts → STOP. Pre-commit hook fails → fix and retry. Mixed staged/unstaged → only commit matching target.

## Success Criteria

FILES_STAGED, QUALITY_CHECKED, MESSAGE_CLEAR, COMMITTED

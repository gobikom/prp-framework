---
name: prp-commit
description: Stage files with natural language targeting and commit with conventional commit message format.
metadata:
  short-description: Smart git commit
---

# PRP Commit — Smart Git Commit

## Input

Target description: `$ARGUMENTS`

## Phase 0: PRE-COMMIT QUALITY CHECK (Advisory)

Scan staged files before committing (warns but does NOT block):
- **Debug artifacts**: grep for TODO/FIXME, console.log/debugger/pdb.set_trace
- **Type safety**: grep for `any` type usage in .ts files (skip test/d.ts files)
- **Quick validation**: type-check + tests (skip in run-all context since implement already validated)
- **Report**: summary of findings (advisory only)

## Phase 1: ASSESS

```bash
git status --short
```

If nothing to commit, stop.

## Phase 2: INTERPRET & STAGE

| Input | Action |
|-------|--------|
| (blank) | `git add -A` (all changes) |
| `staged` | Use current staging |
| `*.ts` / `typescript files` | `git add "*.ts"` |
| `files in src/X` | `git add src/X/` |
| `except tests` | Add all, then `git reset *test* *spec*` |
| `only new files` | Add only untracked files |
| `the X changes` | Interpret from diff/context |

Show what will be committed:
```bash
git diff --cached --name-only
```

## Phase 3: COMMIT

Single-line message in imperative mood:
```
{type}: {description}
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

```bash
git commit -m "{type}: {description}"
```

## Phase 4: OUTPUT

```
Committed: {hash} - {message}
Files: {count} files (+{add}/-{del})
Next: git push or create PR
```

> **Note for orchestrators**: The "Next" suggestion is for standalone usage only. If invoked as part of run-all, the orchestrator should ignore it and proceed to its next step.

## Examples

```
$prp-commit                          # All changes
$prp-commit typescript files         # *.ts only
$prp-commit except package-lock      # Exclude specific
$prp-commit only the new files       # Untracked only
$prp-commit staged                   # Already-staged only
```

## Edge Cases

| Situation | Action |
|-----------|--------|
| Nothing to commit | STOP |
| Merge conflict markers | STOP — resolve first |
| Pre-commit hook fails | Show error, suggest fix, retry |
| Mixed staged/unstaged | Only commit what matches target |

## Success Criteria

- FILES_STAGED: Correct files staged per target
- QUALITY_CHECKED: Advisory scan completed
- MESSAGE_CLEAR: Conventional commit format
- COMMITTED: Git commit succeeded

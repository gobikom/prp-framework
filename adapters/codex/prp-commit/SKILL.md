---
name: prp-commit
description: Stage files with natural language targeting and commit with conventional commit message format.
metadata:
  short-description: Smart git commit
---

# PRP Commit — Smart Git Commit

## Input

Target description: `$ARGUMENTS`

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

## Examples

```
$prp-commit                          # All changes
$prp-commit typescript files         # *.ts only
$prp-commit except package-lock      # Exclude specific
$prp-commit only the new files       # Untracked only
$prp-commit staged                   # Already-staged only
```

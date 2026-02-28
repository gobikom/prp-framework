# PRP Commit — Smart Git Commit

## Input

Target description: `{ARGS}`

## Mission

Stage files matching the target, write a concise commit message, commit.

---

## Phase 0: PRE-COMMIT QUALITY CHECK (Advisory)

> **Note**: This check is advisory only — warns but does NOT block commit. Skip quick validation (0.4) if invoked from run-all workflow (implement already validated).

### 0.1 Scan staged files

```bash
git diff --cached --name-only
```

### 0.2 Debug artifacts scan

Grep staged files for common debug artifacts:

```bash
# TODO/FIXME comments (warning only)
git diff --cached | grep -n "TODO\|FIXME"

# Debug statements (warning)
git diff --cached | grep -n "console\.log\|console\.debug\|debugger\|pdb\.set_trace\|print("
```

### 0.3 Type safety check (TypeScript projects)

```bash
# Scan for `any` type usage in staged .ts files (skip test files and .d.ts)
git diff --cached -- '*.ts' ':!*.test.ts' ':!*.spec.ts' ':!*.d.ts' | grep -n ": any\|as any\|<any>"
```

### 0.4 Quick validation (skip in run-all context)

```bash
# Type-check + test (only if not already validated by implement step)
# Auto-detect: tsc/biome/eslint for type-check, jest/vitest/pytest for tests
```

### 0.5 Quality report

Summarize findings:

```markdown
**Pre-commit Quality Check:**
- Debug artifacts: {count} found (TODO: {n}, console.log: {n})
- Type safety: {count} `any` usage found
- Quick validation: {passed/skipped}
- ⚠️ Advisory: {warnings if any}
```

---

## Phase 1: ASSESS

```bash
git status --short
```

If nothing to commit, stop.

---

## Phase 2: INTERPRET & STAGE

**Target interpretation:**

| Input | Action |
|-------|--------|
| (blank) | `git add -A` (all changes) |
| `staged` | Use current staging |
| `*.ts` / `typescript files` | `git add "*.ts"` |
| `files in src/X` | `git add src/X/` |
| `except tests` | Add all, then `git reset *test* *spec*` |
| `only new files` | Add only untracked files |
| `the X changes` | Interpret from diff/context |

Stage the matching files. Show what will be committed:

```bash
git diff --cached --name-only
```

---

## Phase 3: COMMIT

Write a single-line message in imperative mood:

```
{type}: {description}
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

```bash
git commit -m "{type}: {description}"
```

---

## Phase 4: OUTPUT

```markdown
**Committed**: {hash} - {message}
**Files**: {count} files (+{add}/-{del})

Next: `git push` or create PR
```

> **Note for orchestrators**: This "Next" suggestion is for standalone usage only. If invoked as part of a run-all workflow, ignore this and proceed to the next workflow step.

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| Nothing to commit | STOP — "Working directory clean, nothing to commit." |
| Only untracked files | `git add` the relevant ones, commit |
| Merge conflict markers in staged files | STOP — "Resolve conflicts before committing." |
| Pre-commit hook fails | Show error, suggest fix, retry |
| Staged binary files (images, PDFs) | Include in commit, note in message |
| Mixed staged/unstaged changes | Only commit what matches target description |

---

## Examples

```
commit                          # All changes
commit typescript files         # *.ts only
commit except package-lock      # Exclude specific
commit only the new files       # Untracked only
commit staged                   # Already-staged only
```

---

## Success Criteria

- **FILES_STAGED**: Correct files staged per target description
- **QUALITY_CHECKED**: Pre-commit advisory scan completed
- **MESSAGE_CLEAR**: Commit message follows conventional format and is descriptive
- **COMMITTED**: Git commit succeeded
- **OUTPUT_SHOWN**: User sees commit hash, message, and file count

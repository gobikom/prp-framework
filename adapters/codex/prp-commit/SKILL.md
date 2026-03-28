---
name: prp-commit
description: Stage files with natural language targeting, pre-commit quality scan, plan-aware commit message, and conventional commit format.
metadata:
  short-description: Smart git commit
---
## Agent Mode Detection

If your input context contains `[WORKSPACE CONTEXT]` (injected by a multi-agents framework),
you are running as a sub-agent. Apply these optimizations:

- **Skip CLAUDE.md reading** — already loaded by parent session.
- **Skip Phase 0 quality check** if invoked from run-all (implement already validated).

All other phases (assess, stage, commit) run unchanged.

---

# PRP Commit — Smart Git Commit

## Input

Target description: `$ARGUMENTS`

## Mission

Stage files matching the target, write a concise commit message, commit.

**Golden Rule**: Commit messages should explain what changed and why. Use conventional commit format.

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

```
Pre-commit Quality Check:
- Debug artifacts: {count} found (TODO: {n}, console.log: {n})
- Type safety: {count} `any` usage found
- Quick validation: {passed/skipped}
- Advisory: {warnings if any}
```

**PHASE_0_CHECKPOINT:**
- [ ] Staged files scanned
- [ ] Debug artifacts reported (advisory)
- [ ] Type safety checked (if TypeScript)

---

## Phase 1: ASSESS

```bash
git status --short
```

If nothing to commit, STOP: "Working directory clean, nothing to commit."

---

## Phase 1.5: PLAN-AWARE CONTEXT (optional enrichment)

Check for a completed plan matching the current branch to enrich the commit message:

```bash
BRANCH=$(git branch --show-current)
PLAN_SLUG=$(echo "$BRANCH" | sed 's|^feature/||')
PLAN=$(ls -t .prp-output/plans/completed/*${PLAN_SLUG}*.plan.md 2>/dev/null | head -1)
```

**If plan found**, extract:
- **Summary** — what was planned
- **Task list** — which tasks were completed
- Use these to write a more descriptive commit message body

**If not found**: Skip silently — git diff is sufficient for message derivation.

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

**PHASE_2_CHECKPOINT:**
- [ ] Files staged matching target description
- [ ] Staged file list shown to user

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

**If plan context was loaded (Phase 1.5)**, include a body with plan reference:

```bash
git commit -m "{type}: {description}

Plan: {plan-filename}
Tasks: {N} completed
{If deviations: brief note}"
```

**PHASE_3_CHECKPOINT:**
- [ ] Message follows conventional format
- [ ] Plan context included if available
- [ ] Commit succeeded

---

## Phase 4: OUTPUT

```markdown
**Committed**: {hash} - {message}
**Files**: {count} files (+{add}/-{del})

{If plan context used:}
**Plan**: {plan-filename}

Next: `git push` or `$prp-pr`
```

> **Note for orchestrators**: The "Next" suggestion is for standalone usage only. If this command was invoked as part of run-all, the orchestrator should ignore it and proceed to its next step.

---

## Examples

```
$prp-commit                          # All changes
$prp-commit typescript files         # *.ts only
$prp-commit except package-lock      # Exclude specific
$prp-commit only the new files       # Untracked only
$prp-commit staged                   # Already-staged only
```

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

## Success Criteria

- FILES_STAGED: Correct files staged per target description
- QUALITY_CHECKED: Pre-commit advisory scan completed
- PLAN_CONTEXT: If completed plan exists, enriched commit message
- MESSAGE_CLEAR: Commit message follows conventional format and is descriptive
- COMMITTED: Git commit succeeded
- OUTPUT_SHOWN: User sees commit hash, message, and file count

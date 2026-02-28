---
description: Comprehensive multi-pass PR code review with aspect selection
---

# PRP Review — PR Code Review

Target: $ARGUMENTS

Format: `<pr-number> [aspects: comments|tests|errors|types|code|docs|simplify|all]`

## Mission

Multi-pass review of PR. Each pass focuses on one quality dimension. Report only high-confidence issues (80%+).

## Context Detection (Token Optimization)

Check for pre-generated pr-context: `.prp-output/reviews/pr-context-{BRANCH}.md`. If found, use it to skip PR diff fetch. If `--context <path>` provided, use that path directly.

## Setup

1. Get PR: `gh pr view` (with PR number if provided)
2. Check state: rebase needed? conflicts?
3. Changed files (skip if pr-context found): `gh pr diff --name-only`
4. Classify: production, test, config, types, docs

## Aspect Selection

| Aspect | When to Run |
|--------|-------------|
| `code` | **Always** — core quality check |
| `docs` | **Almost always** — skip for typo/test/config-only |
| `tests` | When test files or tested code changed |
| `comments` | When comments/docstrings added |
| `errors` | When error handling changed |
| `types` | When types added/modified |
| `simplify` | **Last** — after other passes |
| `all` | Default if no aspects specified |

## Passes

1. **Code Quality** (always): guidelines, bugs, naming, dead code. High-confidence only (80%+).
2. **Documentation** (almost always): stale docs, missing references. **Auto-commit** updates to PR branch.
3. **Test Coverage** (when tests changed): behavioral coverage, critical gaps, edge cases. Rate by criticality (1-10).
4. **Comment Analysis** (when comments added): accuracy vs code, completeness, long-term value, rot risk.
5. **Error Handling** (when error handling changed): silent failures (zero tolerance), logging, specific catches, propagation.
6. **Type Design** (when types changed): encapsulation, invariants, usefulness, enforcement (each rated 1-10).
7. **Simplification** (last): nested ternaries → if/else, clever → explicit. **Auto-commit** improvements to PR branch.

## Output

Categorize: Critical (block merge), Important (address), Suggestions, Strengths.
Include: Documentation Updates, Verdict (READY TO MERGE / NEEDS FIXES / CRITICAL ISSUES), Recommended Actions.

### Save Local Review
Save aggregated review to `.prp-output/reviews/pr-{NUMBER}-review-antigravity.md` before posting.

> **Note**: Uses `-antigravity` suffix to identify Antigravity reviews and prevent overwriting reviews from other tools.

### Post to GitHub
`gh pr comment <number> --body-file .prp-output/reviews/pr-{NUMBER}-review-antigravity.md`

### Update Implementation Report
After posting, find implementation report (`ls -t .prp-output/reports/*-report*.md | head -1`). If exists, append "Review Outcome" section with: review date, PR number, verdict, link to review file, issue counts by category. If no report found, skip silently.

## Usage

```
/prp-review 163              # Full review
/prp-review 163 tests errors # Specific aspects
/prp-review                   # Current branch's PR
/prp-review 42 simplify      # Just simplify
```

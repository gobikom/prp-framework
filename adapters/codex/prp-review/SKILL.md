---
name: prp-review
description: Comprehensive multi-pass PR code review covering quality, docs, tests, error handling, types, and simplification. Posts findings to GitHub.
metadata:
  short-description: Review pull request
---

# PRP Review — Comprehensive PR Code Review

## Input

PR number and optional aspects: `$ARGUMENTS`

Format: `<pr-number> [aspects: comments|tests|errors|types|code|docs|simplify|all]`

## Mission

Perform a comprehensive multi-pass code review. Each pass focuses on a specific quality dimension. Report only high-confidence issues (80%+ certain).

## Pre-Review Setup

1. **Identify PR**: `gh pr view <number>` (or current branch if no number)
2. **Check PR State**: Rebase needed? Conflicts? Never push to main without approval.
3. **Get Changed Files**: `gh pr diff <number> --name-only`
4. **Classify Files**: production, test, config, types, docs

## Aspect Selection Logic

| Aspect | Focus Area | When to Run |
|--------|-----------|-------------|
| `code` | General quality and guidelines | **Always** — core quality check |
| `docs` | Updates stale documentation | **Almost always** — skip for typo/test/config-only |
| `tests` | Test coverage and quality | When test files or tested code changed |
| `comments` | Comment accuracy and value | When comments/docstrings added |
| `errors` | Silent failures, error handling | When error handling changed |
| `types` | Type design quality | When types added/modified |
| `simplify` | Code simplification | **Last** — after other passes |
| `all` | All applicable aspects | Default if no aspects specified |

**Skip `docs` only when**: typo-only fixes, test-only changes, documentation-only changes, config tweaks.

## Review Passes

### Pass 1: Code Quality & Guidelines (Always)
- Project guideline compliance (read conventions file)
- Bug detection — logic errors, off-by-one, null handling
- Naming conventions, import organization, dead code
- High-confidence only (80%+)

### Pass 2: Documentation Impact (Almost Always)
- Stale docs, missing references, README updates needed
- New features documented?
- **Auto-commit**: If doc updates made, commit and push to PR branch.

### Pass 3: Test Coverage (When Tests Changed)
- Behavioral coverage (not just line metrics)
- Critical gaps, test quality, edge cases
- Rate recommendations by criticality (1-10)

### Pass 4: Comment Analysis (When Comments Added)
- Comment accuracy vs actual code behavior
- Completeness for complex sections
- Long-term value, comment rot risk

### Pass 5: Error Handling (When Error Handling Changed)
- Silent failure detection — zero tolerance for swallowed errors
- Proper logging, user feedback, specific catch blocks
- Error propagation correctness

### Pass 6: Type Design (When Types Changed)
- Encapsulation quality (1-10)
- Invariant expression (1-10)
- Type usefulness (1-10)
- Enforcement quality (1-10)

### Pass 7: Simplification (After Other Passes)
- Nested ternaries → if/else
- Clever → explicit, unnecessary abstractions → direct
- **Auto-commit**: If improvements made, commit and push to PR branch.

## Result Aggregation

| Category | Description | Action |
|----------|-------------|--------|
| **Critical** | Must fix before merge | Block merge |
| **Important** | Should fix | Address before merge |
| **Suggestions** | Nice to have | Consider |
| **Strengths** | What's good | Acknowledge |

## Output

### Save Local Review
Save aggregated review to `.prp-output/reviews/pr-{NUMBER}-review-codex.md` before posting to GitHub.

> **Note**: Uses `-codex` suffix to identify Codex reviews and prevent overwriting reviews from other tools (each tool uses its own suffix for parallel review capability).

### Post to GitHub
`gh pr comment <PR_NUMBER> --body-file .prp-output/reviews/pr-{NUMBER}-review-codex.md`

Summary includes: Critical/Important/Suggestions/Strengths tables, Documentation Updates, Verdict (READY TO MERGE / NEEDS FIXES / CRITICAL ISSUES), Recommended Actions.

### Update Implementation Report
After posting, find implementation report (`ls .prp-output/reports/*-report.md`). If exists, append "Review Outcome" section with: review date, PR number, verdict, link to review file, issue counts by category (Critical/Important/Suggestions). If no report found, skip silently.

## Usage Examples

```
$prp-review 163              # Full review
$prp-review 163 tests errors # Specific aspects
$prp-review                   # Current branch's PR
$prp-review 42 code docs     # Only code and docs
$prp-review 42 simplify      # Just simplify
```

## Success Criteria

- CONTEXT_GATHERED: PR metadata, diff, artifacts reviewed
- CODE_REVIEWED: All changed files analyzed
- ISSUES_CATEGORIZED: Findings organized by severity
- PR_UPDATED: Comment posted to GitHub
- RECOMMENDATION_CLEAR: Verdict with rationale

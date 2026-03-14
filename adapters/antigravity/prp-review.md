---
description: Comprehensive multi-pass PR code review with aspect selection
---

# PRP Review — PR Code Review

Target: $ARGUMENTS

Format: `<pr-number> [aspects: comments|tests|errors|types|code|security|deps|docs|simplify|all] [--since-last-review] [--metrics]`

## Mission

Multi-pass review of PR. Each pass focuses on one quality dimension. Report only high-confidence issues (80%+).

## Phase 0: Context Detection (Token Optimization)

Check for pre-generated pr-context: `.prp-output/reviews/pr-context-{BRANCH}.md`. If found, use it to skip context extraction. If `--context <path>` provided, use that path directly.

## Phase 1: Context Extraction

**Skip if** Phase 0 found existing context.

1. Get PR: `gh pr view` (with PR number if provided)
2. Check state: merged (stop), closed (warn), draft (note), open (proceed)
3. Gather in ONE pass: PR diff, metadata, changed files, project conventions
4. Save to `.prp-output/reviews/pr-context-{BRANCH}.md`
5. Classify files: production, test, config, types, docs

All review passes read from this shared context file.

## Aspect Selection

| Aspect | When to Run |
|--------|-------------|
| `code` | **Always** — core quality check |
| `security` | **Always** — OWASP Top 10, vulnerabilities |
| `deps` | **Always** — CVEs, outdated packages, licenses |
| `docs` | **Almost always** — skip for typo/test/config-only |
| `tests` | When test files or tested code changed |
| `comments` | When comments/docstrings added |
| `errors` | When error handling changed |
| `types` | When types added/modified |
| `simplify` | **Last** — after other passes |
| `all` | Default if no aspects specified |

**Conditional passes** (auto-detected from file types):
- Frontend files (`.tsx/.jsx/.vue/.svelte/.css/.html`) → include accessibility checks (WCAG 2.1, keyboard nav, contrast)
- Performance-sensitive patterns (DB queries, API endpoints, async loops) → include performance checks (N+1, memory leaks)

## Incremental Review (`--since-last-review`)

When flag provided: find previous review artifact → extract timestamp → `git log --since` for changed files → review only those files → merge findings (resolved/remaining/new). Display delta summary.

## Large PR Strategy

When additions + deletions > 500 lines:
- Tier 1 (Critical: security, auth) + Tier 2 (Business: API, services) → full depth
- Tier 3 (Support: utils, config) + Tier 4 (Low: tests, docs) → core passes only
- Include coverage map. If >1000 lines: suggest splitting.

## Passes

1. **Code Quality** (always): guidelines, bugs, naming, dead code. High-confidence only (80%+).
2. **Documentation** (almost always): stale docs, missing references. **Auto-commit** updates to PR branch.
3. **Security Review** (always): OWASP Top 10 — injection, broken auth, data exposure, SSRF. Only vulnerabilities with clear attack vectors, not theoretical issues. Include severity and remediation.
4. **Dependency Analysis** (always): known CVEs, outdated packages, abandoned dependencies, license issues. Include exact remediation commands.
5. **Test Coverage** (when tests changed): behavioral coverage, critical gaps, edge cases. Rate by criticality (1-10).
6. **Comment Analysis** (when comments added): accuracy vs code, completeness, long-term value, rot risk.
7. **Error Handling** (when error handling changed): silent failures (zero tolerance), logging, specific catches, propagation.
8. **Type Design** (when types changed): encapsulation, invariants, usefulness, enforcement (each rated 1-10).
9. **Simplification** (last): nested ternaries → if/else, clever → explicit. **Auto-commit** improvements to PR branch.

## Validation Phase (Run After Review Passes)

Run automated checks to catch issues that code review alone may miss.

**Skip if** context file already contains validation results.

### Run Validation Suite

```bash
# Type checking (adapt to project)
npm run type-check || bun run type-check || npx tsc --noEmit

# Linting
npm run lint || bun run lint

# Tests
npm test || bun test

# Build
npm run build || bun run build
```

Capture for each: pass/fail status, error count, warning count, specific failures.

### Specific Validation

| Change Type | Additional Validation |
|-------------|----------------------|
| New API endpoint | Test with curl/httpie |
| Database changes | Check migration exists |
| Config changes | Verify .env.example updated |
| New dependencies | Check package.json/lock file |

### Regression Check

```bash
# Full test suite
npm test || bun test

# Specific tests for changed functionality
npm test -- {relevant-test-pattern}
```

Include validation results in the output report.

## Result Deduplication

Before categorizing, deduplicate findings across passes:
- **Same file region** (±5 lines) AND **same category** → merge into one finding
- Keep most detailed description, highest severity, list all contributing passes
- Do NOT merge: different files, or same location but different categories

## Output

Categorize: Critical (block merge), Important (address), Suggestions, Strengths.
Include: Validation Results table, Documentation Updates, Verdict (READY TO MERGE / NEEDS FIXES / CRITICAL ISSUES), Recommended Actions.
If validation fails, verdict is at least NEEDS FIXES.

### Save Local Review
Save aggregated review to `.prp-output/reviews/pr-{NUMBER}-review-antigravity.md` before posting.

> **Note**: Uses `-antigravity` suffix to identify Antigravity reviews and prevent overwriting reviews from other tools.

### Review Metrics
After posting, append JSONL to `.prp-output/reviews/review-metrics.jsonl` (timestamp, pr_number, verdict, issues by severity, incremental/large_pr flags). `--metrics` flag shows aggregate summary.

### Post to GitHub

| Condition | Action |
|-----------|--------|
| READY TO MERGE | `gh pr review {NUMBER} --approve --body-file .prp-output/reviews/pr-{NUMBER}-review-antigravity.md` |
| NEEDS FIXES or CRITICAL ISSUES | `gh pr review {NUMBER} --request-changes --body-file .prp-output/reviews/pr-{NUMBER}-review-antigravity.md` |
| Draft PR or permission fallback | `gh pr comment {NUMBER} --body-file .prp-output/reviews/pr-{NUMBER}-review-antigravity.md` |

### Update Implementation Report
After posting, find implementation report (`ls -t .prp-output/reports/*-report*.md | head -1`). If exists, append "Review Outcome" section with: review date, PR number, verdict, link to review file, issue counts by category. If no report found, skip silently.

## Usage

```
/prp-review 163              # Full review
/prp-review 163 tests errors # Specific aspects
/prp-review 163 security deps # Security + dependency only
/prp-review                   # Current branch's PR
/prp-review 42 simplify      # Just simplify
/prp-review 163 --since-last-review  # Incremental re-review
/prp-review --metrics                # View review metrics
```

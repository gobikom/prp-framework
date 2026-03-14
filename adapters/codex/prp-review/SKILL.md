---
name: prp-review
description: Comprehensive multi-pass PR code review covering quality, security, dependencies, docs, tests, error handling, types, and simplification. Posts findings to GitHub.
metadata:
  short-description: Review pull request
---

# PRP Review — Comprehensive PR Code Review

## Input

PR number and optional aspects: `$ARGUMENTS`

Format: `<pr-number> [aspects: comments|tests|errors|types|code|security|deps|docs|simplify|all] [--since-last-review] [--metrics]`

## Mission

Perform a comprehensive multi-pass code review. Each pass focuses on a specific quality dimension. Report only high-confidence issues (80%+ certain).

## Phase 0: Context Detection (Token Optimization)

Check for pre-generated pr-context: `.prp-output/reviews/pr-context-{BRANCH}.md`. If found, use it to skip context extraction. If `--context <path>` provided, use that path directly.

## Phase 1: Context Extraction

**Skip if** Phase 0 found existing context.

1. **Identify PR**: `gh pr view <number>` (or current branch if no number)
2. **Check PR State**: merged (stop), closed (warn), draft (note), open (proceed). Never push to main without approval.
3. **Gather Context**: PR diff, metadata, changed files, project conventions — all in ONE pass
4. **Save Context**: `.prp-output/reviews/pr-context-{BRANCH}.md`
5. **Classify Files**: production, test, config, types, docs

All review passes read from this shared context file.

## Aspect Selection Logic

| Aspect | Focus Area | When to Run |
|--------|-----------|-------------|
| `code` | General quality and guidelines | **Always** — core quality check |
| `security` | OWASP Top 10, vulnerabilities | **Always** — security review |
| `deps` | CVEs, outdated packages, licenses | **Always** — dependency health |
| `docs` | Updates stale documentation | **Almost always** — skip for typo/test/config-only |
| `tests` | Test coverage and quality | When test files or tested code changed |
| `comments` | Comment accuracy and value | When comments/docstrings added |
| `errors` | Silent failures, error handling | When error handling changed |
| `types` | Type design quality | When types added/modified |
| `simplify` | Code simplification | **Last** — after other passes |
| `all` | All applicable aspects | Default if no aspects specified |

**Skip `docs` only when**: typo-only fixes, test-only changes, documentation-only changes, config tweaks.

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

### Pass 3: Security Review (Always)
- OWASP Top 10: injection, broken auth, data exposure, SSRF
- Input validation, secrets exposure, unsafe operations
- Only vulnerabilities with clear attack vectors, not theoretical issues
- Include severity and remediation for each finding

### Pass 4: Dependency Analysis (Always)
- Known CVEs, outdated packages with security patches
- Abandoned or deprecated dependencies
- License compliance issues
- Include exact remediation commands

### Pass 5: Test Coverage (When Tests Changed)
- Behavioral coverage (not just line metrics)
- Critical gaps, test quality, edge cases
- Rate recommendations by criticality (1-10)

### Pass 6: Comment Analysis (When Comments Added)
- Comment accuracy vs actual code behavior
- Completeness for complex sections
- Long-term value, comment rot risk

### Pass 7: Error Handling (When Error Handling Changed)
- Silent failure detection — zero tolerance for swallowed errors
- Proper logging, user feedback, specific catch blocks
- Error propagation correctness

### Pass 8: Type Design (When Types Changed)
- Encapsulation quality (1-10)
- Invariant expression (1-10)
- Type usefulness (1-10)
- Enforcement quality (1-10)

### Pass 9: Simplification (After Other Passes)
- Nested ternaries → if/else
- Clever → explicit, unnecessary abstractions → direct
- **Auto-commit**: If improvements made, commit and push to PR branch.

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

Include validation results in the output report's Validation Results table.

## Result Deduplication

Before categorizing, deduplicate findings across passes:
- **Same file region** (±5 lines) AND **same category** → merge into one finding
- Keep most detailed description, highest severity, list all contributing passes
- Do NOT merge: different files, or same location but different categories

## Result Aggregation

| Category | Description | Action |
|----------|-------------|--------|
| **Critical** | Must fix before merge | Block merge |
| **Important** | Should fix | Address before merge |
| **Suggestions** | Nice to have | Consider |
| **Strengths** | What's good | Acknowledge |

If validation fails, verdict is at least NEEDS FIXES.

## Output

### Save Local Review
Save aggregated review to `.prp-output/reviews/pr-{NUMBER}-review-codex.md` before posting to GitHub.

> **Note**: Uses `-codex` suffix to identify Codex reviews and prevent overwriting reviews from other tools (each tool uses its own suffix for parallel review capability).

### Post to GitHub

| Condition | Action |
|-----------|--------|
| READY TO MERGE | `gh pr review {NUMBER} --approve --body-file .prp-output/reviews/pr-{NUMBER}-review-codex.md` |
| NEEDS FIXES or CRITICAL ISSUES | `gh pr review {NUMBER} --request-changes --body-file .prp-output/reviews/pr-{NUMBER}-review-codex.md` |
| Draft PR or permission fallback | `gh pr comment {NUMBER} --body-file .prp-output/reviews/pr-{NUMBER}-review-codex.md` |

Summary includes: Critical/Important/Suggestions/Strengths tables, Validation Results table, Documentation Updates, Verdict (READY TO MERGE / NEEDS FIXES / CRITICAL ISSUES), Recommended Actions.

### Review Metrics
After posting, append JSONL to `.prp-output/reviews/review-metrics.jsonl` (timestamp, pr_number, verdict, issues by severity, incremental/large_pr flags). `--metrics` flag (without PR number) shows aggregate summary and EXIT — do not run review.

### Update Implementation Report
After posting, find implementation report (`ls -t .prp-output/reports/*-report*.md | head -1`). If exists, append "Review Outcome" section with: review date, PR number, verdict, link to review file, issue counts by category (Critical/Important/Suggestions). If no report found, skip silently.

## Usage Examples

```
$prp-review 163              # Full review
$prp-review 163 tests errors # Specific aspects
$prp-review 163 security deps # Security + dependency only
$prp-review                   # Current branch's PR
$prp-review 42 code docs     # Only code and docs
$prp-review 42 simplify      # Just simplify
$prp-review 163 --since-last-review  # Incremental re-review
$prp-review --metrics                # View review metrics
```

## Success Criteria

- CONTEXT_GATHERED: PR metadata, diff, artifacts reviewed
- CODE_REVIEWED: All changed files analyzed
- SECURITY_REVIEWED: OWASP Top 10 checked
- DEPS_ANALYZED: CVEs, outdated packages, licenses checked
- VALIDATION_RUN: Type check, lint, tests, build executed
- ISSUES_DEDUPLICATED: Duplicate findings merged across passes
- CONDITIONAL_DISPATCHED: Specialist passes triggered by file types (accessibility, performance)
- ISSUES_CATEGORIZED: Findings organized by severity
- PR_UPDATED: Formal review posted to GitHub (approve/request-changes)
- METRICS_COLLECTED: Review metrics appended to JSONL
- RECOMMENDATION_CLEAR: Verdict with rationale

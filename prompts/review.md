# PRP Review — Comprehensive PR Code Review

## Input

PR number and optional aspects: `{ARGS}`

Format: `<pr-number> [aspects: comments|tests|errors|types|code|security|deps|docs|simplify|all] [--since-last-review] [--metrics]`

## Mission

Perform a comprehensive multi-pass code review on the pull request. Each pass focuses on a specific quality dimension using specialized review logic.

**Golden Rule**: Report only high-confidence issues (80%+ certain). Reduce noise.

---

## Agent Mode Detection

If your input context contains `[WORKSPACE CONTEXT]` (injected by a multi-agents framework),
you are running as a sub-agent. Apply these optimizations:

- **Skip Phase 1 context extraction** if a `pr-context-*.md` file path is provided in
  the context files — use it directly (the upstream commit_pr agent already gathered this).
- **Skip CLAUDE.md reading** — already loaded by parent session.
- **Skip PR metadata fetch** if PR number and diff are available in context files.

All review passes (code, security, deps, docs, tests, etc.) run unchanged —
these are where quality comes from.

---

## Phase 0: Context Detection (Token Optimization)

**If `--context <path>` argument provided**, use that path directly. Otherwise auto-detect:

```bash
BRANCH=$(git branch --show-current)
CONTEXT_FILE=".prp-output/reviews/pr-context-${BRANCH}.md"
```

| Context File | Action |
|-------------|--------|
| FOUND | Read the context file. Use file list, implementation summary, and validation status. Skip Phase 1 context extraction (already available). Display: "Using pre-generated pr-context — skipping context extraction." |
| NOT FOUND | Proceed to Phase 1 to extract context. |

---

## Phase 1: Context Extraction (Token Optimization)

**Purpose**: Extract PR context ONCE, share across all review passes. Saves 60-70% tokens vs fetching diff per pass.

**Skip this phase if** Phase 0 found an existing context file.

### 1.1 Identify the PR

- If PR number provided: `gh pr view <number>`
- If no number: `gh pr view` (current branch's PR)
- Get PR branch name and changed files

### 1.2 Check PR State

| State | Action |
|-------|--------|
| `MERGED` | STOP: "PR already merged. Nothing to review." |
| `CLOSED` | WARN: "PR is closed. Review anyway? (historical analysis)" |
| `DRAFT` | NOTE: "Draft PR — focusing on direction, not polish" |
| `OPEN` | PROCEED with review |

### 1.3 Gather Context

Extract all context in ONE pass:

```bash
# PR metadata
gh pr view {NUMBER} --json number,title,body,author,headRefName,baseRefName,state,additions,deletions,changedFiles

# PR diff
gh pr diff {NUMBER}

# Changed files list
gh pr diff {NUMBER} --name-only
```

Also read:
- Project conventions file (CLAUDE.md or equivalent)
- Implementation report (if exists): `ls -t .prp-output/reports/*-report*.md 2>/dev/null | head -1`

### 1.4 Create Context File

```bash
mkdir -p .prp-output/reviews
```

**Context File Path**: `.prp-output/reviews/pr-context-{BRANCH}.md`

Save PR metadata, project guidelines, changed files, diff, and implementation context to the context file. All subsequent review passes read from this file.

### 1.5 Classify Changed Files

Categorize each file: production code, test, config, types, docs, etc.

---

## Review Aspects

| Aspect | Focus Area | When to Run |
|--------|-----------|-------------|
| `code` | General quality and guidelines | Always — core quality check |
| `security` | OWASP Top 10, vulnerabilities | Always — security review |
| `deps` | CVEs, outdated packages, licenses | Always — dependency health |
| `docs` | Updates stale documentation | Almost always — skip for typo/test/config-only |
| `tests` | Test coverage and quality | When test files or tested code changed |
| `comments` | Comment accuracy and value | When comments/docstrings added |
| `errors` | Silent failures, error handling | When error handling changed |
| `types` | Type design quality | When types added/modified |
| `simplify` | Code simplification | After other passes — final polish |
| `all` | All applicable aspects | Default if no aspects specified |

---

## Aspect Selection Logic

**Always run**:
- `code` — Core quality check
- `security` — Security vulnerabilities (OWASP Top 10)
- `deps` — CVEs, outdated packages, licenses

**Almost always run** (skip only for trivial PRs):
- `docs` — Updates project docs

**Skip `docs` only when**:
- Typo-only fixes (comments, strings)
- Test-only changes (no production code)
- Documentation-only changes
- Config tweaks (CI, linting)

**Run based on changes**:
- Test files changed → `tests`
- Comments/docstrings added → `comments`
- Try-catch or error handling → `errors`
- New types or type modifications → `types`

**Run last**:
- `simplify` — After other reviews pass

**Conditional passes** (auto-detected from file types):
- Frontend files (`.tsx`, `.jsx`, `.vue`, `.svelte`, `.css`, `.scss`, `.html`) → include accessibility checks (WCAG 2.1, keyboard nav, screen reader, contrast)
- Performance-sensitive patterns (DB queries, API endpoints, async loops) → include performance checks (N+1, sequential awaits, memory leaks, unbounded ops)

---

## Incremental Review (`--since-last-review`)

When `--since-last-review` flag provided:

1. Find previous review artifact for THIS tool: `ls -t .prp-output/reviews/pr-{NUMBER}-review-{TOOL_SUFFIX}.md 2>/dev/null | head -1` (each adapter uses its own suffix: `-other`, `-antigravity`, `-opencode`, `-gemini`, `-codex`, `-agents`)
2. Extract review timestamp from artifact
3. Get changed files since: `git log --since="{TIMESTAMP}" --name-only --pretty=format:"" | sort -u`
4. If no changes: "No new changes since last review." EXIT.
5. Review only changed files + files that import/use them
6. After review, merge findings with previous:
   - **Resolved**: previous issues where file:line no longer matches → remove
   - **Remaining**: previous issues still present → keep
   - **New**: current review findings not in previous → add
7. Display delta: "New: {N}, Resolved: {M}, Remaining: {K}"

---

## Large PR Strategy

When PR size (additions + deletions) exceeds 500 lines:

1. **Categorize files by risk tier**:
   - Tier 1 (Critical): security, auth, payment, encryption → full depth review
   - Tier 2 (Business Logic): API, services, business rules → full depth review
   - Tier 3 (Support): utils, helpers, config → core passes only (code + security)
   - Tier 4 (Low Risk): tests, docs, generated → code pass only
2. **Review Tier 1-2 first**, then Tier 3-4
3. **Include coverage map** in summary (file, tier, passes run)
4. If >1000 lines: suggest splitting PR

---

## Per-File Review Checklist

**For EVERY changed file, check against these 7 categories:**

#### Correctness
- [ ] Does the code do what the PR claims?
- [ ] Are there logic errors?
- [ ] Are edge cases handled?
- [ ] Is error handling appropriate?

#### Type Safety
- [ ] Are all types explicit (no implicit `any`)?
- [ ] Are return types declared?
- [ ] Are interfaces used appropriately?
- [ ] Are type guards used where needed?

#### Pattern Compliance
- [ ] Does it follow existing patterns in the codebase?
- [ ] Is naming consistent with project conventions?
- [ ] Is file organization correct?
- [ ] Are imports from the right places?

#### Security
- [ ] Any user input without validation?
- [ ] Any secrets that could be exposed?
- [ ] Any injection vulnerabilities (SQL, command, etc.)?
- [ ] Any unsafe operations?

#### Performance
- [ ] Any obvious N+1 queries or loops?
- [ ] Any unnecessary async/await?
- [ ] Any memory leaks (unclosed resources, growing arrays)?
- [ ] Any blocking operations in hot paths?

#### Completeness
- [ ] Are there tests for new code?
- [ ] Is documentation updated if needed?
- [ ] Are all TODOs addressed?
- [ ] Is error handling complete?

#### Maintainability
- [ ] Is the code readable?
- [ ] Is it over-engineered?
- [ ] Is it under-engineered (missing necessary abstractions)?
- [ ] Are there magic numbers/strings that should be constants?

---

## Issue Severity Levels

| Level | Icon | Criteria | Examples |
|-------|------|----------|----------|
| Critical | `RED` | Blocking — must fix | Security vulnerabilities, data loss potential, crashes |
| High | `ORANGE` | Should fix before merge | Type safety violations, missing error handling, logic errors |
| Medium | `YELLOW` | Should consider | Pattern inconsistencies, missing edge cases, undocumented deviations |
| Low | `BLUE` | Suggestions | Style preferences, minor optimizations, documentation |

**Implementation report check**: If a deviation from expected patterns is documented in the implementation report with a valid reason, it is NOT an issue — it's an intentional decision. Only flag **undocumented** deviations.

---

## Review Passes

### Pass 1: Code Quality & Guidelines (Always)

Review all changed files for:
- Project guideline compliance (read project's conventions file)
- Bug detection — logic errors, off-by-one, null handling
- Naming conventions consistency
- Import organization
- Dead code or unused variables
- Report only high-confidence issues (80%+ certain)

**Instructions**: Focus on the diff only. Check guidelines from project conventions file. Report bugs, guideline violations, and quality issues with file:line references.

### Pass 2: Documentation Impact (Almost Always)

Skip only for: typo-only fixes, test-only changes, config tweaks, documentation-only changes.

Check and fix:
- Are docs affected by these changes?
- Are any references stale?
- Does README need updating?
- Are new features documented?
- Update CLAUDE.md, README.md, and docs/ as needed

**Auto-commit**: If documentation updates are made, commit and push them to the PR branch.

### Pass 3: Security Review (Always)

Review all changed files for security vulnerabilities:
- OWASP Top 10: injection (SQL, command, XSS), broken auth, data exposure, SSRF
- Input validation — user input without sanitization
- Secrets exposure — API keys, passwords in code
- Unsafe operations — command injection, path traversal
- Authentication/authorization gaps

**Instructions**: Focus on vulnerabilities with clear attack vectors, not theoretical issues. Include severity and remediation for each finding. Do not review code quality or style — only security.

### Pass 4: Dependency Analysis (Always)

Analyze dependencies for health and security:
- Known CVEs in current dependencies
- Outdated packages with security patches available
- Abandoned or deprecated dependencies
- License compliance issues (copyleft in proprietary code)
- New dependencies added — justified? Lightweight alternatives?

**Instructions**: Check for known CVEs, outdated packages, abandoned dependencies, license issues. Include exact remediation commands (npm audit fix, version bumps). Do not review application code — only dependency management.

### Pass 5: Test Coverage (When Tests Changed)

Run when test files or tested code changed:
- Behavioral coverage assessment (not just line metrics)
- Critical gaps identification
- Test quality evaluation
- Edge case coverage
- Rate recommendations by criticality (1-10)

**Instructions**: Analyze test coverage for the PR. Focus on behavioral coverage, identify critical gaps, rate recommendations by criticality.

### Pass 6: Comment Analysis (When Comments Added)

Run when comments or docstrings are added:
- Comment accuracy — does comment match actual code behavior?
- Comment completeness — are complex sections explained?
- Long-term value — will this comment stay accurate?
- Comment rot risk — does it reference specifics that will change?

**Instructions**: Analyze code comments for accuracy, completeness, and long-term value. Verify comments match actual code behavior. Advisory only.

### Pass 7: Error Handling (When Error Handling Changed)

Run when try-catch blocks or error handling modified:
- Silent failure detection — zero tolerance for swallowed errors
- Proper logging verification
- User feedback adequacy
- Specific catch blocks (no generic `catch(e)` without handling)
- Error propagation correctness

**Instructions**: Hunt for silent failures. Check all error handling for proper logging, user feedback, and specific catch blocks.

### Pass 8: Type Design (When Types Changed)

Run when new types added or types modified:
- Encapsulation quality (1-10)
- Invariant expression (1-10)
- Type usefulness (1-10)
- Enforcement quality (1-10)

**Instructions**: Analyze type design. Rate encapsulation, invariant expression, usefulness, and enforcement. Focus on new or modified types. Pragmatic focus.

### Pass 9: Simplification (After Other Passes Pass)

Final polish pass:
- Nested ternaries → if/else
- Overly clever code → explicit code
- Unnecessary abstractions → direct code
- Redundant comments → self-documenting code

**Auto-commit**: If simplification improvements are made, commit and push them to the PR branch.

**Instructions**: Simplify code for clarity while preserving functionality. No nested ternaries, prefer explicit over clever.

---

## Validation Phase (Run After Review Passes)

Run automated checks to catch issues that code review alone may miss.

**Run AFTER all review passes complete, BEFORE aggregation.**

**Skip if** Phase 0 context file already contains validation results.

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

---

## Result Deduplication

**Before categorizing, deduplicate findings across passes.**

### Dedup Rules

Two findings are considered duplicates when BOTH conditions are met:
1. **Same file region**: Same file AND within ±5 lines of each other
2. **Same category**: Both about the same concern (e.g., both about error handling, both about security)

**NOT duplicates** (do not merge):
- Different files, even if description is similar
- Same file region but different categories (e.g., security issue + code quality issue at same line)

### Merge Strategy

When duplicates found:
- **Keep the most detailed description** (longest/most specific)
- **Use the highest severity** from any contributing pass
- **List all contributing passes** in the "Pass" column: e.g., `Code Quality, Error Handling`
- **Combine remediation suggestions** if they differ

---

## Review Metrics

After posting review to GitHub, append one JSONL line to `.prp-output/reviews/review-metrics.jsonl`:

```json
{"timestamp":"ISO","pr_number":N,"branch":"name","verdict":"VERDICT","total_issues":N,"critical":N,"important":N,"suggestions":N,"incremental":bool,"large_pr":bool,"lines_changed":N,"files_changed":N}
```

When `--metrics` flag provided (without PR number): display aggregate summary (total reviews, verdicts breakdown, issues by severity, incremental review stats) and EXIT.

---

## Result Aggregation

After deduplication, categorize all findings:

### Categories

| Category | Description | Action |
|----------|-------------|--------|
| **Critical** | Must fix before merge | Block merge |
| **Important** | Should fix | Address before merge |
| **Suggestions** | Nice to have | Consider |
| **Strengths** | What's good | Acknowledge |

### Verdict Decision Logic

| Condition | Verdict |
|-----------|---------|
| No critical/important issues AND all validation passes | READY TO MERGE |
| Important issues OR validation warnings (fixable) | NEEDS FIXES |
| Critical issues OR validation failures | CRITICAL ISSUES |

**Note**: If validation fails, verdict is at least NEEDS FIXES regardless of pass findings.

### Report Frontmatter

Include this frontmatter at the top of the review file:

```yaml
---
pr: {NUMBER}
title: "{TITLE}"
author: "{AUTHOR}"
reviewed: {ISO_TIMESTAMP}
verdict: {READY TO MERGE / NEEDS FIXES / CRITICAL ISSUES}
---
```

### Summary Format

```markdown
## PR Review Summary

### Critical Issues (X found)

| Pass | Issue | Location |
|------|-------|----------|
| Code Quality | Description | `file.ts:line` |

### Important Issues (X found)

| Pass | Issue | Location |
|------|-------|----------|
| Security Review | Description | `file.ts:line` |

### Suggestions (X found)

| Pass | Suggestion | Location |
|------|------------|----------|
| Type Design | Description | `file.ts:line` |

### Strengths

- Well-structured error handling
- Good test coverage for critical paths

### Validation Results

| Check | Status | Details |
|-------|--------|---------|
| Type Check | {PASS/FAIL} | {notes} |
| Lint | {PASS/WARN} | {count} warnings |
| Tests | {PASS/FAIL} | {count} passed |
| Build | {PASS/FAIL} | {notes} |

### Documentation Updates

- `CLAUDE.md` — Added new command reference
- `README.md` — Updated configuration section

### Verdict

[READY TO MERGE / NEEDS FIXES / CRITICAL ISSUES]

### Recommended Actions

1. Fix critical issues first
2. Address important issues
3. Consider suggestions
4. Re-run review after fixes
```

Note: Pass column may list multiple passes for deduplicated findings (e.g., `Code Quality, Error Handling`).

---

## Save Local Review

Before posting to GitHub, save the aggregated review locally:

**Path**: `.prp-output/reviews/pr-{NUMBER}-review-other.md`

> **Note**: Uses `-other` suffix to identify generic/multi-pass reviews and prevent overwriting reviews from other tools (Codex, OpenCode, Gemini use their own suffixes; Claude Code uses `-agents` suffix).

```bash
mkdir -p .prp-output/reviews
```

Save the full summary markdown (same content that will be posted to GitHub) to this file. This ensures a local artifact exists for reference and traceability.

---

## Post to GitHub

### Determine Review Action

Based on findings and validation results:

| Condition | Action |
|-----------|--------|
| Verdict is READY TO MERGE (no critical/important AND validation passes) | `gh pr review {NUMBER} --approve --body-file .prp-output/reviews/pr-{NUMBER}-review-other.md` |
| Verdict is NEEDS FIXES or CRITICAL ISSUES | `gh pr review {NUMBER} --request-changes --body-file .prp-output/reviews/pr-{NUMBER}-review-other.md` |
| Draft PR | `gh pr comment {NUMBER} --body-file .prp-output/reviews/pr-{NUMBER}-review-other.md` (comment only, no formal review) |
| Fallback (review command fails, e.g., permission issue) | `gh pr comment {NUMBER} --body-file .prp-output/reviews/pr-{NUMBER}-review-other.md` |

### Verdict to Action Mapping

| Verdict | GitHub Action |
|---------|-------------|
| READY TO MERGE | `--approve` |
| NEEDS FIXES | `--request-changes` |
| CRITICAL ISSUES | `--request-changes` |

---

## Update Implementation Report

After posting to GitHub, update the implementation report to close the feedback loop:

### Find Implementation Report

```bash
ls -t .prp-output/reports/*-report*.md 2>/dev/null | head -1
```

### Append Review Outcome

**If implementation report exists**, append the following section to the end of the report:

```markdown

---

## Review Outcome

**Reviewed**: {ISO_TIMESTAMP}
**PR**: #{NUMBER}
**Verdict**: {READY TO MERGE / NEEDS FIXES / CRITICAL ISSUES}
**Review File**: `.prp-output/reviews/pr-{NUMBER}-review-other.md`

| Category | Count |
|----------|-------|
| Critical | {N} |
| Important | {N} |
| Suggestions | {N} |

{If NEEDS FIXES or CRITICAL ISSUES: list of top issues to address}
```

**If no implementation report found**: Skip this step silently (PR may not have been created via PRP workflow).

### Update PRD (if applicable)

**If implementation report references a Source PRD:**

| Verdict | PRD Update |
|---------|------------|
| READY TO MERGE | Change phase status from `complete` to `reviewed` |
| NEEDS FIXES | Add note: "Review: {N} issues to address" to phase row |
| CRITICAL ISSUES | Add note: "Blocked: {brief reason}" to phase row |

---

## Usage Examples

```
# Full review of specific PR
review 163

# Review only specific aspects
review 163 tests errors

# Review current branch's PR
review

# Only security and dependency review
review 42 security deps

# Only code and docs review
review 42 code docs

# Just simplify after passing review
review 42 simplify

# Incremental re-review (only changes since last review)
review 163 --since-last-review

# View review metrics summary
review --metrics
```

---

## Workflow Integration

**Before creating PR**:
1. Run review on current branch
2. Fix critical and important issues
3. Re-run to verify
4. Create PR

**During PR review**:
1. Run review with PR number
2. Review posts summary to GitHub with formal approve/request-changes
3. Address feedback
4. Re-run targeted aspects

**After making changes**:
1. Run specific aspects: `review <pr-number> tests code`
2. Verify issues resolved
3. Push updates

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| PR is merged | STOP — "PR already merged. Nothing to review." |
| PR is closed | WARN — review anyway for historical analysis |
| PR is draft | NOTE — focus on direction, not polish. Use comment only (no formal approve). |
| No PR number and no PR for current branch | STOP — "No PR found. Create a PR first." |
| Very large PR (>50 files) | Focus on production code, skip generated/vendor files |
| PR has only config/CI changes | Run only `code` pass, skip `tests`/`types`/`errors` |
| Review artifact already exists for this PR | Overwrite with new review (timestamp in artifact) |

---

## Notes

- All passes read from shared context file (`.prp-output/reviews/pr-context-{BRANCH}.md`) instead of fetching diff per pass
- Security review and dependency analysis always run on every PR
- Accessibility and performance checks are auto-triggered by file types (conditional)
- Validation phase runs after passes, before aggregation
- Findings are deduplicated across passes before categorizing (fuzzy match: ±5 lines + same category)
- Formal GitHub review action (approve/request-changes) replaces plain comment, with comment as fallback
- `--since-last-review` enables incremental review — only changes since last review, merges findings
- Large PRs (>500 lines) are reviewed by risk tier — critical files first
- Review metrics appended to `.prp-output/reviews/review-metrics.jsonl` after every review
- `docs` pass commits and pushes doc updates to PR branch
- `simplify` pass commits and pushes improvements to PR branch

---

## Critical Reminders

1. **Understand before judging.** Read full context, not just the diff.
2. **Be specific.** "This could be better" is useless. "Use `execFile` instead of `exec` to prevent command injection at line 45" is helpful.
3. **Prioritize.** Not everything is critical. Use severity levels honestly.
4. **Be constructive.** Offer solutions, not just problems.
5. **Acknowledge good work.** If something is done well, say so.
6. **Run validation.** Don't skip automated checks.
7. **Check patterns.** Read existing similar code to understand expectations.
8. **Think about edge cases.** What happens with null, empty, very large, concurrent?
9. **Check implementation report.** Documented deviations are intentional, not issues.

---

## Success Criteria

- **CONTEXT_GATHERED**: PR metadata, diff, and artifacts reviewed
- **CODE_REVIEWED**: All changed files analyzed
- **SECURITY_REVIEWED**: OWASP Top 10 checked
- **DEPS_ANALYZED**: CVEs, outdated packages, licenses checked
- **VALIDATION_RUN**: Automated checks executed
- **ISSUES_DEDUPLICATED**: Duplicate findings merged across passes
- **ISSUES_CATEGORIZED**: Findings organized by severity
- **CONDITIONAL_DISPATCHED**: Specialist passes triggered by file types (accessibility, performance)
- **REPORT_GENERATED**: Review saved locally
- **PR_UPDATED**: Formal review posted to GitHub (approve/request-changes)
- **METRICS_COLLECTED**: Review metrics appended to JSONL
- **RECOMMENDATION_CLEAR**: Verdict with rationale
- **CHECKLIST_APPLIED**: Per-file review checklist used for every changed file
- **PRD_UPDATED**: If PRD exists, phase status updated based on verdict

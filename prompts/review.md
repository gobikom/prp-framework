# PRP Review — Comprehensive PR Code Review

## Input

PR number and optional aspects: `{ARGS}`

Format: `<pr-number> [aspects: comments|tests|errors|types|code|docs|simplify|all]`

## Mission

Perform a comprehensive multi-pass code review on the pull request. Each pass focuses on a specific quality dimension using specialized review logic.

**Golden Rule**: Report only high-confidence issues (80%+ certain). Reduce noise.

---

## Pre-Review Setup

1. **Identify the PR**
   - If PR number provided: `gh pr view <number>`
   - If no number: `gh pr view` (current branch's PR)
   - Get PR branch name and changed files

2. **Check PR State**
   - Is rebase needed? Check if behind base branch
   - Are there conflicts? Resolve intelligently if needed
   - Never push to main without explicit user approval

3. **Get Changed Files**
   ```bash
   gh pr diff <number> --name-only
   ```

4. **Classify Changed Files**
   Categorize each file: production code, test, config, types, docs, etc.

---

## Review Aspects

| Aspect | Focus Area | When to Run |
|--------|-----------|-------------|
| `code` | General quality and guidelines | Always — core quality check |
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

### Pass 3: Test Coverage (When Tests Changed)

Run when test files or tested code changed:
- Behavioral coverage assessment (not just line metrics)
- Critical gaps identification
- Test quality evaluation
- Edge case coverage
- Rate recommendations by criticality (1-10)

**Instructions**: Analyze test coverage for the PR. Focus on behavioral coverage, identify critical gaps, rate recommendations by criticality.

### Pass 4: Comment Analysis (When Comments Added)

Run when comments or docstrings are added:
- Comment accuracy — does comment match actual code behavior?
- Comment completeness — are complex sections explained?
- Long-term value — will this comment stay accurate?
- Comment rot risk — does it reference specifics that will change?

**Instructions**: Analyze code comments for accuracy, completeness, and long-term value. Verify comments match actual code behavior. Advisory only.

### Pass 5: Error Handling (When Error Handling Changed)

Run when try-catch blocks or error handling modified:
- Silent failure detection — zero tolerance for swallowed errors
- Proper logging verification
- User feedback adequacy
- Specific catch blocks (no generic `catch(e)` without handling)
- Error propagation correctness

**Instructions**: Hunt for silent failures. Check all error handling for proper logging, user feedback, and specific catch blocks.

### Pass 6: Type Design (When Types Changed)

Run when new types added or types modified:
- Encapsulation quality (1-10)
- Invariant expression (1-10)
- Type usefulness (1-10)
- Enforcement quality (1-10)

**Instructions**: Analyze type design. Rate encapsulation, invariant expression, usefulness, and enforcement. Focus on new or modified types. Pragmatic focus.

### Pass 7: Simplification (After Other Passes Pass)

Final polish pass:
- Nested ternaries → if/else
- Overly clever code → explicit code
- Unnecessary abstractions → direct code
- Redundant comments → self-documenting code

**Auto-commit**: If simplification improvements are made, commit and push them to the PR branch.

**Instructions**: Simplify code for clarity while preserving functionality. No nested ternaries, prefer explicit over clever.

---

## Result Aggregation

After all passes complete, aggregate findings:

### Categories

| Category | Description | Action |
|----------|-------------|--------|
| **Critical** | Must fix before merge | Block merge |
| **Important** | Should fix | Address before merge |
| **Suggestions** | Nice to have | Consider |
| **Strengths** | What's good | Acknowledge |

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
| Error Handling | Description | `file.ts:line` |

### Suggestions (X found)

| Pass | Suggestion | Location |
|------|------------|----------|
| Type Design | Description | `file.ts:line` |

### Strengths

- Well-structured error handling
- Good test coverage for critical paths

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

**Always post the summary to the PR when a PR number is provided**:

```bash
gh pr comment <PR_NUMBER> --body-file .prp-output/reviews/pr-{NUMBER}-review-other.md
```

---

## Update Implementation Report

After posting to GitHub, update the implementation report to close the feedback loop:

### Find Implementation Report

```bash
ls .prp-output/reports/*-report.md 2>/dev/null
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

---

## Usage Examples

```
# Full review of specific PR
review 163

# Review only specific aspects
review 163 tests errors

# Review current branch's PR
review

# Only code and docs review
review 42 code docs

# Just simplify after passing review
review 42 simplify
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
2. Review posts summary to GitHub
3. Address feedback
4. Re-run targeted aspects

**After making changes**:
1. Run specific aspects: `review <pr-number> tests code`
2. Verify issues resolved
3. Push updates

---

## Notes

- Each pass analyzes git diff by default (changed files only)
- Each pass returns detailed report with file:line references
- `docs` pass commits and pushes doc updates to PR branch
- `simplify` pass commits and pushes improvements to PR branch
- Summary always posted as PR comment when PR number provided

---

## Success Criteria

- **CONTEXT_GATHERED**: PR metadata, diff, and artifacts reviewed
- **CODE_REVIEWED**: All changed files analyzed
- **VALIDATION_RUN**: Automated checks executed
- **ISSUES_CATEGORIZED**: Findings organized by severity
- **REPORT_GENERATED**: Review saved locally
- **PR_UPDATED**: Comment posted to GitHub
- **RECOMMENDATION_CLEAR**: Verdict with rationale

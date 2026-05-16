---
description: Verify PR implements acceptance criteria - requirements traceability from issue/plan to diff evidence
argument-hint: "<pr-number> [--plan <path>] [--issue <N>] [--criteria \"...\"]"
---
<process>
# PRP Verify — Requirements Verification

## Input

PR number and optional criteria: `$ARGUMENTS`

Format: `<pr-number> [--plan <path>] [--issue <N>] [--criteria "..."]`

## Mission

Verify that a PR's code changes actually implement the acceptance criteria. This is not code quality review — it is requirements traceability: for each acceptance criterion, find evidence in the PR diff that it was implemented.

**The Test**: For each acceptance criterion, produce a **PASS/FAIL verdict with evidence** (specific diff lines, files changed, or code patterns). No criterion passes without traceable evidence in the diff.

---

## Phase 0: Parse Input & Gather Criteria

### 0.1 Resolve PR Number

Extract PR number from `$ARGUMENTS`. If not provided:

```bash
gh pr view --json number -q '.number // empty' 2>/dev/null
```

If no PR found: STOP — "No PR number provided and no open PR on current branch."

### 0.2 Gather Acceptance Criteria

Criteria come from ONE of these sources (in priority order):

| Source | How |
|--------|-----|
| `--criteria "..."` | Use directly from argument |
| `--issue <N>` | `gh issue view <N> --json body -q '.body'` — extract criteria from issue body (look for "Acceptance criteria", "AC:", checklist items `- [ ]`) |
| `--plan <path>` | Read plan file — extract "Acceptance Criteria" section |
| PR body | `gh pr view {NUMBER} --json body -q '.body'` — find `Closes #N` or `Fixes #N`, fetch linked issue criteria |
| None extractable | STOP — "No acceptance criteria found. Use --criteria, --issue, or --plan." |

### 0.3 Parse Criteria into Checklist

Convert raw criteria into structured checklist:

```markdown
## Acceptance Criteria Checklist
| # | Criterion | Status |
|---|-----------|--------|
| 1 | {criterion text} | PENDING |
| 2 | {criterion text} | PENDING |
```

**CHECKPOINT**: {N} criteria to verify.

---

## Phase 1: Fetch PR Diff

```bash
gh pr diff {NUMBER}
```

Also gather context:

```bash
gh pr view {NUMBER} --json title,body,files,additions,deletions
```

List changed files:

```bash
gh pr diff {NUMBER} --name-only
```

**CHECKPOINT**: Diff fetched. {N} files changed, +{additions}/-{deletions} lines.

---

## Phase 2: Verify Each Criterion

For each criterion in the checklist:

### 2.1 Search for Evidence

Search the diff for implementation evidence:

| Criterion Type | Evidence to Look For |
|---------------|---------------------|
| New feature | New function/class/endpoint in diff |
| Bug fix | Removal of buggy code + replacement logic |
| Config/flag | New flag, environment variable, or config key |
| UI change | New component, route, or template |
| Test coverage | New test file or test cases for the feature |
| Documentation | Updated docs, README, or inline comments |

### 2.2 Assign Verdict

| Verdict | Condition |
|---------|-----------|
| ✅ PASS | Clear evidence found in diff that criterion is implemented |
| ❌ FAIL | No evidence found, or evidence contradicts the criterion |
| ⚠️ PARTIAL | Partial evidence — criterion may be implemented but incomplete or unclear |

### 2.3 Record Evidence

For each criterion, record:
- **Verdict**: PASS / FAIL / PARTIAL
- **Evidence**: Specific file:line or diff snippet
- **Note**: Any caveats or concerns

---

## Phase 3: Generate Artifact

### 3.1 Compile Results

```markdown
## Verify Results

| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | {criterion} | ✅ PASS | `src/foo.py:42` — new function `verify_token()` added |
| 2 | {criterion} | ❌ FAIL | No evidence in diff |
| 3 | {criterion} | ⚠️ PARTIAL | `tests/test_foo.py` updated but no E2E coverage |
```

### 3.2 Overall Verdict

| Condition | Verdict |
|-----------|---------|
| All criteria PASS | **VERIFY PASSED** ✅ |
| All PASS or PARTIAL, no FAIL | **VERIFY PASSED (with gaps)** ⚠️ |
| Any criterion FAIL | **VERIFY FAILED** ❌ |

### 3.3 Save Artifact

Save to `.prp-output/reviews/pr-{NUMBER}-verify.md`:

```markdown
---
pr: {NUMBER}
title: "{PR_TITLE}"
verified_by: "claude-code"
verdict: PASS | FAIL | PARTIAL
criteria_total: {N}
criteria_passed: {N}
criteria_failed: {N}
criteria_partial: {N}
date: {ISO_TIMESTAMP}
---

# Verify Report: PR #{NUMBER}

## Summary
- **Verdict**: {verdict}
- **Criteria**: {passed}/{total} passed
- **PR**: {PR_TITLE}
- **Source**: {--issue N / --criteria / --plan path}

## Results

{full results table from Phase 3.1}

## Criteria Details

{For each criterion — full evidence text}

## Environment
- **Diff size**: +{additions}/-{deletions} lines across {N} files
- **Verified at**: {timestamp}
```

### 3.4 Display Summary

```
VERIFY {VERDICT} — {passed}/{total} criteria verified
{list each criterion with verdict icon}

Artifact: .prp-output/reviews/pr-{NUMBER}-verify.md
```

---

## Output

- Artifact: `.prp-output/reviews/pr-{NUMBER}-verify.md`
- Summary: printed to stdout

---

## Usage Examples

```
/prp-core:prp-verify 42
/prp-core:prp-verify 42 --issue 166
/prp-core:prp-verify 42 --plan .prp-output/plans/feature.plan.md
/prp-core:prp-verify 42 --criteria "Gate 2 blocks agent PRs, bypass requires --reason"
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| PR has no linked issue | Extract criteria from PR body or use --criteria |
| Criterion is vague ("works correctly") | Note: "Criterion ambiguous — interpreted as: {interpretation}." Verify best match. |
| Diff too large to inspect fully | Focus on files most relevant to each criterion |
| Test-only changes | Verify test content matches criterion requirements |
| Criterion references external system | Note: "External system verification not possible from diff — marking PARTIAL." |

---

## Success Criteria

- CRITERIA_PARSED: All acceptance criteria extracted and classified
- DIFF_FETCHED: PR diff retrieved successfully
- VERDICTS_EVIDENCED: Every criterion has PASS/FAIL/PARTIAL with specific evidence
- ARTIFACT_SAVED: Verify report written to `.prp-output/reviews/pr-{NUMBER}-verify.md`
- SUMMARY_REPORTED: User has clear verdict

</process>

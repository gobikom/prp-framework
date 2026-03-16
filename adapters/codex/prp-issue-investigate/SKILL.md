---
name: prp-issue-investigate
description: Analyze a GitHub issue or problem description — produces a comprehensive investigation artifact with root cause analysis, implementation plan, and assessment that can be executed by prp-issue-fix.
metadata:
  short-description: Investigate issue and create implementation plan
---

# PRP Issue Investigate — Analyze Issue and Create Implementation Plan

## Input

Issue number, URL, or description: `$ARGUMENTS`

Format: `<issue-number|github-url|free-form-description>`

## Mission

Investigate the issue and produce a comprehensive implementation plan that:
1. Can be executed by `$prp-issue-fix`
2. Is posted as a GitHub comment (if GH issue provided)
3. Captures all context needed for one-pass implementation

**Golden Rule**: The artifact you produce IS the specification. The implementing agent should be able to work from it without asking questions.

## Phase 1: PARSE — Understand Input

### 1.1 Determine Input Type

| Input Format | Interpretation |
|-------------|----------------|
| Number (`123`, `#123`) | GitHub issue number |
| Starts with `http` | GitHub URL (extract issue number) |
| Anything else | Free-form description (no GitHub posting) |

```bash
# If GitHub issue:
gh issue view {number} --json title,body,labels,comments,state,url,author
```

### 1.2 Classify Issue Type

| Type | Indicators |
|------|-----------|
| BUG | "broken", "error", "crash", "doesn't work", stack trace |
| ENHANCEMENT | "add", "support", "feature", "would be nice" |
| REFACTOR | "clean up", "improve", "simplify", "reorganize" |
| CHORE | "update", "upgrade", "maintenance", "dependency" |
| DOCUMENTATION | "docs", "readme", "clarify", "example" |

### 1.3 Assess Severity/Priority, Complexity, and Confidence

Each assessment requires a **one-sentence reasoning** based on concrete investigation findings.

**For BUG — Severity:**

| Severity | Criteria |
|----------|----------|
| CRITICAL | System down, data loss, security vulnerability, no workaround |
| HIGH | Major feature broken, significant user impact, difficult workaround |
| MEDIUM | Feature partially broken, moderate impact, workaround exists |
| LOW | Minor issue, cosmetic, edge case, easy workaround |

**For non-BUG — Priority:** HIGH / MEDIUM / LOW

**Complexity:** HIGH (5+ files, architectural) / MEDIUM (2-4 files) / LOW (1-2 files, isolated)

**Confidence:** HIGH (clear root cause, strong evidence) / MEDIUM (likely cause, some assumptions) / LOW (uncertain, many unknowns)

**PHASE_1_CHECKPOINT:**
- [ ] Input type identified (GH issue or free-form)
- [ ] Issue content extracted
- [ ] Type classified
- [ ] Severity/Priority assessed with reasoning

## Phase 2: EXPLORE — Codebase Intelligence

### 2.1 Search for Relevant Code

Explore the codebase to understand:
1. Files directly related to this functionality
2. How the current implementation works
3. Integration points — what calls this, what it calls
4. Similar patterns elsewhere to mirror
5. Existing test patterns for this area

### 2.2 Document Findings

| Area | File:Lines | Notes |
|------|-----------|-------|
| Core logic | `src/x.ts:10-50` | Main function affected |
| Callers | `src/y.ts:20-30` | Uses the core function |
| Types | `src/types/x.ts:5-15` | Relevant interfaces |
| Tests | `src/x.test.ts:1-100` | Existing test patterns |
| Similar | `src/z.ts:40-60` | Pattern to mirror |

**PHASE_2_CHECKPOINT:**
- [ ] Core files identified with line numbers
- [ ] Integration points mapped
- [ ] Similar patterns found to mirror
- [ ] Test patterns documented

## Phase 3: ANALYZE — Form Approach

### 3.1 For BUG Issues — Root Cause Analysis

Apply the 5 Whys with evidence at each step:

```
WHY 1: Why does [symptom] occur?
→ Because [cause A]
→ Evidence: `file.ts:123` - {code snippet}
...continue until root cause...
```

Check git history:
```bash
git log --oneline -10 -- {affected-file}
git blame -L {start},{end} {affected-file}
```

### 3.2 For ENHANCEMENT/REFACTOR Issues

Identify: What needs to be added/changed, where it integrates, scope boundaries, what should NOT be changed.

### 3.3 For All Issues

Determine:
- Files to CREATE / UPDATE / DELETE
- Dependencies and order of changes
- Edge cases and risks
- Validation strategy

**PHASE_3_CHECKPOINT:**
- [ ] Root cause identified (bugs) OR change rationale clear (enhancements)
- [ ] All affected files listed with specific changes
- [ ] Scope boundaries defined
- [ ] Risks and edge cases identified

## Phase 4: GENERATE — Create Artifact

### 4.1 Artifact Path

```bash
mkdir -p .prp-output/issues
TIMESTAMP=$(date +%Y%m%d-%H%M)
```

**With issue number:** `.prp-output/issues/issue-{number}-{TIMESTAMP}.md`
**Free-form:** `.prp-output/issues/investigation-{TIMESTAMP}.md`

### 4.2 Artifact Structure

Write the artifact with these sections:

1. **Header**: Issue reference, Type, Timestamp
2. **Assessment Table**: Severity/Priority + Complexity + Confidence (each with reasoning)
3. **Problem Statement**: 2-3 sentences
4. **Analysis**: Root Cause / Change Rationale, Evidence Chain with file:line references
5. **Affected Files Table**: File, Lines, Action, Description
6. **Integration Points**: What calls this, what it calls
7. **Git History**: Introduced by, last modified, type (regression/original/long-standing)
8. **Implementation Plan**: Step-by-step with current code, required change, rationale per step
9. **Tests to Add**: Specific test cases with code
10. **Patterns to Follow**: Actual code snippets from codebase to mirror
11. **Edge Cases & Risks Table**: Risk, Mitigation
12. **Validation Commands**: Adapted to project toolchain
13. **Scope Boundaries**: IN SCOPE / OUT OF SCOPE

**PHASE_4_CHECKPOINT:**
- [ ] Artifact file created
- [ ] All sections filled with specific content
- [ ] Code snippets are actual (not invented)
- [ ] Steps are actionable without clarification

## Phase 5: COMMIT — Save Artifact

```bash
git add ".prp-output/issues/issue-{number}-${TIMESTAMP}.md"
git commit -m "Investigate issue #{number}: {brief title}"
```

**PHASE_5_CHECKPOINT:**
- [ ] Artifact committed to git

## Phase 6: POST — GitHub Comment

**Only if input was a GitHub issue:**

Post a formatted comment with: Assessment table, Problem Statement, Root Cause Analysis, Implementation Plan summary table, Validation commands, Next step (`$prp-issue-fix {number}`).

```bash
gh issue comment {number} --body-file "$ARTIFACT_PATH"
```

> Alternatively format a condensed version for the comment and post via `--body`.

**PHASE_6_CHECKPOINT:**
- [ ] Comment posted to GitHub (if GH issue)

## Phase 7: REPORT — Output to User

Present: Issue reference, Type, Assessment table, Key Findings (root cause, files affected, estimated changes), Files to Modify table, Artifact path, GitHub status, Next step (`$prp-issue-fix {number}`).

## Handling Edge Cases

| Scenario | Action |
|----------|--------|
| Issue already closed | Report, still create artifact if user wants |
| Issue has linked PR | Warn, ask if continue anyway |
| Can't determine root cause | Set confidence LOW, proceed with best hypothesis |
| Very large scope | Suggest breaking into smaller issues, focus on core first |

## Usage Examples

```
$prp-issue-investigate 123
$prp-issue-investigate https://github.com/org/repo/issues/456
$prp-issue-investigate "Login page shows blank screen after OAuth redirect"
```

## Success Criteria

- ARTIFACT_COMPLETE: All sections filled with specific, actionable content
- EVIDENCE_BASED: Every claim has file:line reference or proof
- IMPLEMENTABLE: Another agent can execute without questions
- GITHUB_POSTED: Comment visible on issue (if GH issue)
- COMMITTED: Artifact saved in git

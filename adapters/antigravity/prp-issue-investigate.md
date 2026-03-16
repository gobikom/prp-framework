---
description: Investigate a GitHub issue or problem - analyze codebase, create plan, post to GitHub
---

# PRP Issue Investigate — Analyze Issue and Create Plan

Target: $ARGUMENTS

Format: `<issue-number|URL|description>`

## Mission

Investigate the issue and produce a comprehensive implementation plan that can be executed by `/prp-issue-fix`, posted to GitHub (if GH issue), and captures all context for one-pass implementation.

**Golden Rule**: The artifact IS the specification. The implementing agent should work from it without asking questions.

## Step 1: PARSE — Understand Input

Determine input type:
- Number (`123`, `#123`) → GitHub issue: `gh issue view {number} --json title,body,labels,comments,state,url,author`
- URL → Extract issue number, fetch
- Anything else → Free-form description (no GitHub posting)

Classify type: BUG / ENHANCEMENT / REFACTOR / CHORE / DOCUMENTATION (from keywords and content).

### Assessment Table

Each value requires **one-sentence reasoning** based on investigation findings:

| Metric | Criteria |
|--------|----------|
| Severity (BUG) | CRITICAL (system down, data loss) / HIGH (major broken) / MEDIUM (partial, workaround) / LOW (minor, cosmetic) |
| Priority (non-BUG) | HIGH (blocking) / MEDIUM (important, not urgent) / LOW (nice to have) |
| Complexity | HIGH (5+ files, architectural) / MEDIUM (2-4 files) / LOW (1-2 files, isolated) |
| Confidence | HIGH (clear root cause, strong evidence) / MEDIUM (likely cause, some assumptions) / LOW (uncertain, many unknowns) |

## Step 2: EXPLORE — Codebase Intelligence

Search for relevant code:
1. Files directly related to functionality
2. How current implementation works
3. Integration points — callers and callees
4. Similar patterns elsewhere to mirror
5. Existing test patterns
6. Error handling patterns

Document findings:

| Area | File:Lines | Notes |
|------|-----------|-------|
| Core logic | `src/x.ts:10-50` | Main function |
| Callers | `src/y.ts:20-30` | Uses core function |
| Tests | `src/x.test.ts` | Existing patterns |
| Similar | `src/z.ts:40-60` | Pattern to mirror |

## Step 3: ANALYZE — Form Approach

**For BUGs**: Apply 5 Whys with evidence chain. Check git history (`git log`, `git blame`).

**For ENHANCEMENTs**: Identify what to add/change, integration points, scope boundaries, what NOT to change.

**For all**: determine files to CREATE/UPDATE/DELETE, dependencies/order, edge cases/risks, validation strategy.

## Step 4: GENERATE — Create Artifact

```bash
mkdir -p .prp-output/issues
TIMESTAMP=$(date +%Y%m%d-%H%M)
```

**Path**: `.prp-output/issues/issue-{number}-{TIMESTAMP}.md` (or `investigation-{TIMESTAMP}.md` for free-form)

Artifact includes: title, type, assessment table (with reasoning), problem statement, evidence chain (5 Whys for bugs), affected files table (file/lines/action/description), integration points, git history, implementation steps (each with file, lines, current code, required change, rationale), patterns to follow (from codebase), edge cases/risks table, validation commands, manual verification, scope boundaries (in/out).

## Step 5: COMMIT — Save Artifact

```bash
git add ".prp-output/issues/issue-{number}-${TIMESTAMP}.md"
git commit -m "Investigate issue #{number}: {brief title}"
```

## Step 6: POST — GitHub Comment

**Only if input was a GitHub issue.** Post formatted summary to issue:

```bash
gh issue comment {number} --body-file <(cat <<'EOF'
## Investigation: {Title}
**Type**: `{TYPE}`

### Assessment
| Metric | Value | Reasoning |
|--------|-------|-----------|
| {Severity/Priority} | `{VALUE}` | {why} |
| Complexity | `{VALUE}` | {why} |
| Confidence | `{VALUE}` | {why} |

### Implementation Plan
| Step | File | Change |
|------|------|--------|
| 1 | `src/x.ts:45` | {description} |

### Next Step
To implement: `/prp-issue-fix {number}`

_Investigated by AI_
EOF
)
```

## Step 7: REPORT — Output to User

Display: issue number/title, type, assessment table, key findings (root cause, files affected, scope), artifact path, GitHub status, next step (`/prp-issue-fix {number}`).

## Edge Cases

- **Issue closed**: report and still create artifact if requested
- **PR already exists**: warn, ask to continue
- **Can't determine root cause**: set confidence LOW, note uncertainty, proceed with best hypothesis
- **Very large scope**: suggest breaking into smaller issues, focus on core problem

## Usage

```
/prp-issue-investigate 123
/prp-issue-investigate https://github.com/org/repo/issues/123
/prp-issue-investigate "Login fails after password reset"
```

## Success Criteria

- ARTIFACT_COMPLETE: All sections filled with specific, actionable content
- EVIDENCE_BASED: Every claim has file:line reference or proof
- IMPLEMENTABLE: Another agent can execute without questions
- GITHUB_POSTED: Comment visible on issue (if GH issue)
- COMMITTED: Artifact saved in git

---
description: Analyze GitHub issue or problem description and produce actionable implementation plan
agent: plan
---

# PRP Issue Investigate — Analyze and Plan

Issue: $ARGUMENTS

## Mission

Investigate the issue and produce a comprehensive implementation plan that can be executed by `/prp:issue-fix` without questions. Post findings as a GitHub comment (if GH issue).

**Golden Rule**: The artifact IS the specification. The implementing agent works from it alone.

## Steps

1. **Parse Input**:
   - Number (`123`, `#123`) → GitHub issue: `gh issue view {number} --json title,body,labels,comments,state,url,author`
   - URL (`http...`) → extract issue number, fetch same way
   - Anything else → free-form description (no GitHub posting)
   Extract: title, body, labels, comments, state. If closed → warn. If has linked PR → warn.

2. **Classify Issue Type**:

   | Type | Indicators |
   |------|-----------|
   | BUG | "broken", "error", "crash", stack trace |
   | ENHANCEMENT | "add", "support", "feature" |
   | REFACTOR | "clean up", "improve", "simplify" |
   | CHORE | "update", "upgrade", "maintenance" |
   | DOCUMENTATION | "docs", "readme", "clarify" |

3. **Explore Codebase**: Search for relevant code — files related to functionality, current implementation, integration points (callers, dependencies), similar patterns to mirror, existing test patterns, error handling. Document findings with file:line references and actual code snippets.

4. **Analyze**:
   - **BUG**: Apply 5-Whys root cause analysis with evidence chain. Check `git log` and `git blame` on affected files.
   - **ENHANCEMENT/REFACTOR**: Identify what to add/change, integration points, scope boundaries, what NOT to change.
   - **All types**: Determine files to CREATE/UPDATE/DELETE, dependencies, order of changes, edge cases, risks, validation strategy.

5. **Assess** (each with one-sentence reasoning based on findings):
   - **Severity** (BUG: CRITICAL/HIGH/MEDIUM/LOW) or **Priority** (others: HIGH/MEDIUM/LOW)
   - **Complexity**: LOW (1-2 files) / MEDIUM (2-4 files) / HIGH (5+ files, architectural)
   - **Confidence**: HIGH (clear root cause) / MEDIUM (likely cause) / LOW (uncertain)

6. **Generate Artifact**: Save to `.prp-output/issues/issue-{number}-{TIMESTAMP}.md` (or `investigation-{TIMESTAMP}.md` for free-form). Include:
   - Header: issue number, type, timestamp
   - Assessment table (severity/priority, complexity, confidence with reasoning)
   - Problem Statement (2-3 sentences)
   - Root Cause / Change Rationale with evidence chain
   - Affected Files table (file, lines, action, description)
   - Integration Points
   - Git History (introduced, last modified, implication)
   - Implementation Plan: numbered steps with file, lines, action, current code, required change, rationale
   - Test cases to add
   - Patterns to Follow (actual code from codebase)
   - Edge Cases & Risks table
   - Validation commands (adapt to toolchain)
   - Scope Boundaries (in/out of scope)

7. **Commit Artifact**: `git add .prp-output/issues/issue-{number}-{TIMESTAMP}.md && git commit -m "Investigate issue #{number}: {title}"`

8. **Post to GitHub** (only for GH issues): Format artifact as comment with assessment table, problem statement, root cause, implementation plan table, validation commands. Post via `gh issue comment {number} --body-file` or `--body`.

9. **Report to User**: Issue, type, assessment table, key findings (root cause, files affected, scope), artifact path, GitHub posting status, next step: "Run `/prp:issue-fix {number}` to execute the plan."

## Edge Cases

- **Issue closed**: Report, still create artifact if requested
- **Linked PR exists**: Warn, ask to continue
- **Can't determine root cause**: Set confidence LOW, note uncertainty, proceed with best hypothesis
- **Very large scope**: Suggest breaking into smaller issues, focus on core problem

## Usage

```
/prp:issue-investigate 123
/prp:issue-investigate https://github.com/org/repo/issues/456
/prp:issue-investigate "Search returns stale results after cache invalidation"
```

## Success Criteria

- ARTIFACT_COMPLETE: All sections filled with specific, actionable content
- EVIDENCE_BASED: Every claim has file:line reference or proof
- IMPLEMENTABLE: Another agent can execute without questions
- GITHUB_POSTED: Comment visible on issue (if GH issue)
- COMMITTED: Artifact saved in git

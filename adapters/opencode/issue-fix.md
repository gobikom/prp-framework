---
description: Implement fix from investigation artifact with safe staging and self-review
agent: build
---

# PRP Issue Fix — Execute Investigation Plan

Issue: $ARGUMENTS

## Mission

Load the investigation artifact from `/prp:issue-investigate`, implement changes exactly as specified, validate, create PR linked to issue, self-review, and archive.

**Golden Rule**: Follow the artifact. If something seems wrong, validate first — don't silently deviate.

## Steps

1. **Load Artifact**:
   - Number (`123`, `#123`) → `ls -t .prp-output/issues/issue-{number}*.md 2>/dev/null | head -1`
   - Path → use directly
   - Not found → STOP: "Run `/prp:issue-investigate {number}` first."
   Parse: issue number, title, type, files to modify, implementation steps, validation commands, test cases.

2. **Validate Artifact Accuracy**: For each file in artifact, read actual current code and compare to artifact's "current code" snippets. If significant drift → warn user, suggest re-investigation or proceed with caution. Confirm approach still addresses root cause.

3. **Git State Check**:
   - In worktree → use it
   - On main, clean → `git checkout -b fix/issue-{number}-{slug}`
   - On main, dirty → STOP: "Commit or stash first"
   - On feature/fix branch → use it (warn if branch name doesn't match issue)
   - Sync: `git pull --rebase origin main 2>/dev/null || git pull origin main`

4. **Implement Changes**: Execute each step from artifact's Implementation Plan in order.
   - **DO**: Follow steps in order, match code style, copy patterns from "Patterns to Follow", add tests as specified.
   - **DON'T**: Refactor unrelated code, add "improvements" not in plan, change formatting of untouched lines.
   - For UPDATE files: find exact lines, make specified change, preserve surrounding code.
   - For CREATE files: use patterns from artifact, follow conventions.
   - Track deviations (WHAT and WHY).

5. **Validate** (all must pass before proceeding):
   ```bash
   {type-check-cmd}    # type-check
   {test-cmd}          # tests (including new test cases)
   {lint-cmd}          # lint
   ```
   If failures → analyze, fix, re-run. Note additional fixes.

6. **Safe Staging & Commit**:
   ```bash
   git diff --name-only | xargs -r git add
   git ls-files --others --exclude-standard | xargs -r git add
   git diff --cached --name-only  # verify no unexpected files
   ```
   Commit: `Fix: {title} (#{number})` with problem statement, changes list, `Fixes #{number}`.

7. **Create PR**:
   ```bash
   git push -u origin HEAD
   gh pr create --title "Fix: {title} (#{number})" --body "..."
   ```
   PR body: summary, root cause, changes table, testing checklist, validation commands, `Fixes #{number}`, implementation details (artifact path, deviations).

8. **Self-Review**: Review the diff focusing on: does fix address root cause? Code quality matches patterns? Tests sufficient? Edge cases handled? Security concerns? Post review as PR comment via `gh pr comment`.

9. **Archive Artifact**:
   ```bash
   mkdir -p .prp-output/issues/completed
   mv .prp-output/issues/issue-{number}-{TIMESTAMP}.md .prp-output/issues/completed/
   git add .prp-output/issues/ && git commit -m "Archive investigation for issue #{number}" && git push
   ```

10. **Report to User**: Issue, branch, PR number/URL, changes table, validation results, self-review summary, artifact archive path, next steps (human review, merge when approved).

## Edge Cases

- **Artifact outdated**: Warn about drift, suggest re-investigation
- **Tests fail after implementation**: Debug, fix code (not test), re-validate, note in PR
- **Merge conflicts**: Resolve, re-validate fully, note in PR
- **PR creation fails**: Check existing PR for branch, check permissions, provide manual command
- **Already on branch with changes**: Use existing branch, warn if name doesn't match

## Usage

```
/prp:issue-fix 123
/prp:issue-fix #456
/prp:issue-fix .prp-output/issues/issue-123-20260315-1400.md
```

## Success Criteria

- PLAN_EXECUTED: All artifact steps completed
- VALIDATION_PASSED: All checks green
- PR_CREATED: PR exists and linked to issue with "Fixes #{number}"
- REVIEW_POSTED: Self-review comment on PR
- ARTIFACT_ARCHIVED: Moved to completed folder
- AUDIT_TRAIL: Full history in git and GitHub

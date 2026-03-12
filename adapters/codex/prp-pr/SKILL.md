---
name: prp-pr
description: Create a pull request from current branch with proper title, body, and linked issues. Uses PR templates if available.
metadata:
  short-description: Create pull request
---

# PRP PR — Create Pull Request

## Input

Base branch: `$ARGUMENTS` (default: main)

## Mission

Create a well-formatted pull request from the current branch, using repository PR templates if available.

**Golden Rule**: PRs should tell reviewers what changed and why.

## Step 0: PARSE FLAGS

Extract from `$ARGUMENTS`:
- `NO_INTERACT` = true if `--no-interact` found
- `BASE_BRANCH` = first non-flag argument, default "main"

**Autonomous mode (`--no-interact`)**: NEVER ask user questions. Auto-resolve decisions:
- Uncommitted changes → WARN only, PROCEED (don't stop)
- Existing PR found → reuse it (set PR_NUMBER/URL, skip to verify)
- Push fails → auto `git push --force-with-lease`
- Multiple templates → auto-select default
- Pre-condition errors (on main, no commits) still STOP.

## Phase 1: VALIDATE — Check Prerequisites

```bash
git branch --show-current
git status --short
git log origin/main..HEAD --oneline
```

| State | Action |
|-------|--------|
| On main/master | STOP: "Cannot create PR from main." |
| Uncommitted changes | WARN: "Commit or stash before creating PR." |
| No commits ahead | STOP: "No commits to create PR from." |
| Has commits, clean | PROCEED |

Check existing PR:
```bash
gh pr list --head $(git branch --show-current) --json number,url
```
If exists: report URL and stop.

## Phase 2: DISCOVER — Gather Context

### Check PR Template
```bash
ls -la .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null
ls -la .github/pull_request_template.md 2>/dev/null
ls -la .github/PULL_REQUEST_TEMPLATE/ 2>/dev/null
ls -la docs/pull_request_template.md 2>/dev/null
```

### Analyze Commits & Files
```bash
git log origin/main..HEAD --pretty=format:"- %s"
git log origin/main..HEAD --pretty=format:"%h %s%n%b" --no-merges
git diff --stat origin/main..HEAD
git diff --name-only origin/main..HEAD
```

### Determine PR Title
- Single commit → use commit message
- Multiple commits → summarize in imperative mood
- Format: `{type}: {description}` (feat/fix/refactor/docs/test/chore)

### Extract Issue References
Find in commits: `Fixes #123`, `Closes #123`, `Relates to #123`, `#123`

## Phase 3: PUSH

```bash
git push -u origin HEAD
```

If fails: check conflicts, may need `--force-with-lease` (warn user first).

## Phase 4: CREATE PR

### If Template: Fill in each section from commits/changes.

### If No Template: Default format:
```bash
gh pr create \
  --title "{title}" \
  --base "{base-branch}" \
  --body "$(cat <<'EOF'
## Summary
{1-2 sentence description}

## Changes
{commit summaries}

## Files Changed
{count} files changed
<details>
<summary>File list</summary>
{changed files}
</details>

## Testing
- [ ] Type check passes
- [ ] Tests pass
- [ ] Manually verified

## Related Issues
{linked issues or "None"}
EOF
)"
```

## Phase 5: VERIFY

```bash
gh pr view --json number,url,title,state
gh pr checks
```

## Phase 6: OUTPUT

Report: PR number, URL, title, base←branch, summary, changes count, files list, CI checks status, next steps.

> **Note for orchestrators**: The "Next Steps" in output are for standalone usage only. If invoked as part of run-all, the orchestrator should ignore them and proceed to its next step.

## Edge Cases

- **Branch diverged**: `git rebase origin/main` then `git push --force-with-lease`
- **Required template sections**: Parse for `<!-- required -->`, ensure filled
- **Multiple templates**: Use default or ask user. If `--no-interact`: auto-select default template, do NOT ask.
- **Draft PR**: `gh pr create --draft --title "{title}" --body "{body}"`

## Success Criteria

- BRANCH_PUSHED: Branch exists on origin
- PR_CREATED: PR created via gh
- TEMPLATE_USED: If template exists, it was used
- ISSUES_LINKED: Referenced issues linked
- URL_RETURNED: User has PR URL

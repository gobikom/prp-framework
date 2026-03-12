---
description: Create pull request from current branch with template support
agent: build
---

# PRP PR — Create Pull Request

Base: $ARGUMENTS (default: main)

## Step 0: PARSE FLAGS

Extract `--no-interact` flag and base branch from arguments.

**Autonomous mode (`--no-interact`)**: NEVER ask user questions. Auto-resolve decisions:
- Uncommitted changes → WARN only, PROCEED (don't stop)
- Existing PR found → reuse it (set PR_NUMBER/URL, skip to verify/push)
- Push fails → auto `git push --force-with-lease`
- Multiple templates → auto-select default
- Pre-condition errors (on main, no commits) still STOP.

## Steps

1. **Validate**:
   - Not on main/master → STOP if so
   - Clean working dir → WARN if uncommitted
   - Has commits ahead → STOP if none
   - Check existing PR: `gh pr list --head $(git branch --show-current) --json number,url` → if exists, report URL
2. **Gather Context**:
   - Check PR templates: `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE/`, `docs/pull_request_template.md`
   - Analyze commits: `git log origin/main..HEAD --pretty=format:"- %s"`
   - Analyze files: `git diff --stat origin/main..HEAD` and `git diff --name-only origin/main..HEAD`
   - Determine title: single commit → use message, multiple → summarize. Format: `{type}: {description}`
   - Extract issue refs: `Fixes #123`, `Closes #123`, `Relates to #123`
3. **Push**: `git push -u origin HEAD` (if fails, may need `--force-with-lease` — warn user)
4. **Create PR**:
   - If template: fill sections from commits/changes
   - If no template: default format with Summary, Changes, Files Changed (`<details>` collapsible), Testing checklist, Related Issues
5. **Verify**: `gh pr view --json number,url,title,state` and `gh pr checks`
6. **Output**: PR number, URL, title, base←branch, changes count, files, CI status, next steps

> **Note for orchestrators**: The "Next Steps" in output are for standalone usage only. If invoked as part of run-all, the orchestrator should ignore them and proceed to its next step.

## Edge Cases

- Branch diverged → `git rebase origin/main` then `git push --force-with-lease`
- Required sections → parse for `<!-- required -->`, ensure filled
- Multiple templates → use default or ask user. If `--no-interact`: auto-select default, do NOT ask.
- Draft PR → `gh pr create --draft`

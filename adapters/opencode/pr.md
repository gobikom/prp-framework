---
description: Create pull request from current branch with template support
agent: build
---

# PRP PR — Create Pull Request

Base: $ARGUMENTS (default: main)

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

## Edge Cases

- Branch diverged → `git rebase origin/main` then `git push --force-with-lease`
- Required sections → parse for `<!-- required -->`, ensure filled
- Multiple templates → use default or ask user
- Draft PR → `gh pr create --draft`

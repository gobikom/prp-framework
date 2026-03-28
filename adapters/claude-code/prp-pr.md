---
description: Create a PR from current branch with unpushed commits
argument-hint: [base-branch] [--no-interact] (default: main)
---
<process>

## Agent Mode Detection

If your input context contains `[WORKSPACE CONTEXT]` (injected by a multi-agents framework),
you are running as a sub-agent. Apply these optimizations:

- **Skip Phase 2 template discovery** — if context files include PR body content, use it directly.
- **Skip CLAUDE.md reading** — already loaded by parent session.
- **Phase 1**: If PR number is already known from context, skip existing PR check.

All other phases (push, create, verify) run unchanged.

---

# PRP PR — Create Pull Request

## Input

Base branch: `$ARGUMENTS` (default: main)

## Mission

Create a well-formatted pull request from the current branch, using repository PR templates if available, with a clear summary of changes.

**Golden Rule**: PRs should tell reviewers what changed and why. Use existing templates when available.

---

## Step 0: PARSE FLAGS

Extract from `$ARGUMENTS`:
- `NO_INTERACT` = true if `--no-interact` found
- `BASE_BRANCH` = first non-flag argument, default "main"

**Autonomous mode (`--no-interact`)**: NEVER ask user questions. Auto-resolve decisions:
- Uncommitted changes → WARN only, PROCEED (don't stop)
- Existing PR found → reuse it (set PR_NUMBER/URL, skip to Phase 5)
- Push fails → auto `git push --force-with-lease`
- Multiple templates → auto-select default
- Pre-condition errors (on main, no commits) still STOP.

---

## Phase 1: VALIDATE — Check Prerequisites

### 1.1 Verify Git State

```bash
# Current branch (must not be main/master)
git branch --show-current

# Check for uncommitted changes
git status --short

# Verify we have commits to PR
git log origin/main..HEAD --oneline
```

**Decision Tree:**

| State | Action |
|-------|--------|
| On main/master | STOP: "Cannot create PR from main. Create a feature branch first." |
| Uncommitted changes + `NO_INTERACT` | WARN only (print message), then PROCEED — do NOT ask or wait. |
| Uncommitted changes + interactive | WARN: "You have uncommitted changes. Commit or stash before creating PR." |
| No commits ahead | STOP: "No commits to create PR from. Branch is up to date with main." |
| Has commits, clean | PROCEED |

### 1.2 Check for Existing PR

```bash
gh pr list --head $(git branch --show-current) --json number,url
```

**If PR exists + `NO_INTERACT`:**
- Reuse the existing PR — set `PR_NUMBER` and `PR_URL` from the result.
- Skip directly to **Phase 5: VERIFY** (push new commits first if needed).
- Do NOT stop or ask.

**If PR exists + interactive:**
```
PR already exists for this branch: {url}
Use `gh pr view` to see details or `gh pr edit` to modify.
```

**PHASE_1_CHECKPOINT:**
- [ ] Not on main/master branch
- [ ] Working directory is clean (or user acknowledged)
- [ ] Has commits ahead of base branch
- [ ] No existing PR for this branch (or reused existing in `--no-interact` mode)

---

## Phase 2: DISCOVER — Gather Context

### 2.1 Check for PR Template

```bash
# Check common template locations
ls -la .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null
ls -la .github/pull_request_template.md 2>/dev/null
ls -la .github/PULL_REQUEST_TEMPLATE/ 2>/dev/null
ls -la docs/pull_request_template.md 2>/dev/null
```

**If template found:**
- Read the template
- Use it as the PR body structure
- Fill in sections based on commits and changes

**If no template:**
- Use default format (see Phase 4)

### 2.2 Analyze Commits

```bash
# Get commit messages for PR body
git log origin/main..HEAD --pretty=format:"- %s"

# Get detailed commit info
git log origin/main..HEAD --pretty=format:"%h %s%n%b" --no-merges
```

### 2.3 Analyze Changed Files

```bash
# Files changed
git diff --stat origin/main..HEAD

# Get list of changed files
git diff --name-only origin/main..HEAD
```

### 2.4 Determine PR Title

**From commits, derive title:**
- If single commit: Use commit message as title
- If multiple commits: Summarize the change in imperative mood
- Format: `{type}: {description}` (e.g., "feat: Add user authentication")

**Common prefixes:**

| Prefix | Usage |
|--------|-------|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `refactor:` | Code restructuring |
| `docs:` | Documentation |
| `test:` | Adding tests |
| `chore:` | Maintenance |

### 2.5 Extract Issue References

From commit messages, find patterns like:
- `Fixes #123`
- `Closes #123`
- `Relates to #123`
- `#123`

Include these in the PR body under "Related Issues".

### 2.6 Load Implementation Report (optional enrichment)

```bash
# Find the most recent implementation report
ls -t .prp-output/reports/*-report*.md 2>/dev/null | head -1
```

**If report found**, extract:
- **Summary** — use to enrich PR description's summary section
- **Deviations from plan** — include as notable context for reviewers
- **Validation results** — pre-fill testing section with actual results
- **Test coverage** — include in testing section

**If not found**: Skip silently — git log is sufficient for PR description.

**PHASE_2_CHECKPOINT:**
- [ ] PR template located (or confirmed none exists)
- [ ] Commit messages extracted
- [ ] Changed files listed
- [ ] PR title determined
- [ ] Issue references extracted
- [ ] Implementation report loaded (if available)

---

## Phase 3: PUSH — Ensure Branch is Remote

### 3.1 Push to Origin

```bash
# Push with upstream tracking
git push -u origin HEAD
```

**If push fails + `NO_INTERACT`:**
- Automatically try `git push --force-with-lease -u origin HEAD` (safe force push).
- If that also fails → STOP with error message. Do NOT ask.

**If push fails + interactive:**
- Check for remote branch conflicts
- May need `--force-with-lease` if rebased (warn user first)

**PHASE_3_CHECKPOINT:**
- [ ] Branch pushed to origin
- [ ] Upstream tracking set

---

## Phase 4: CREATE — Build and Submit PR

### 4.1 If Template Exists

Read the template and fill in each section based on:
- Commit messages
- Changed files
- Implementation report (if loaded in Phase 2.6)
- Any linked issues (look for `#123` or `Fixes #123` in commits)

### 4.2 If No Template — Use Default Format

```bash
gh pr create \
  --title "{title}" \
  --base "{base-branch}" \
  --body "$(cat <<'EOF'
## Summary

{1-2 sentence description of what this PR accomplishes}
{If implementation report found: include summary from report}

## Changes

{List of commit summaries}
- {commit 1}
- {commit 2}

## Files Changed

{Count} files changed

<details>
<summary>File list</summary>

{list of changed files}

</details>

{If implementation report found:}
## Implementation Notes

{Deviations from plan, if any}
{Notable decisions or trade-offs}

## Testing

{If implementation report found: actual validation results}
{Otherwise: checklist}
- [ ] Type check passes
- [ ] Tests pass
- [ ] Manually verified

## Related Issues

{Any linked issues from commit messages, or "None"}
EOF
)"
```

**PHASE_4_CHECKPOINT:**
- [ ] PR body generated (from template or default)
- [ ] Title is clear and follows convention
- [ ] Implementation report context included (if available)
- [ ] Related issues linked

---

## Phase 5: VERIFY — Confirm Creation

### 5.1 Get PR Details

```bash
# Get the created PR info
gh pr view --json number,url,title,state
```

### 5.2 Verify PR is Ready

```bash
# Check PR status
gh pr checks
```

**PHASE_5_CHECKPOINT:**
- [ ] PR created successfully
- [ ] PR URL retrieved

---

## Phase 6: OUTPUT — Report to User

```markdown
## Pull Request Created

**PR**: #{number}
**URL**: {url}
**Title**: {title}
**Base**: {base-branch} <- {current-branch}

### Summary

{Brief description of what the PR contains}

### Changes

- {N} commits
- {M} files changed

### Files

{List of changed files}

{If implementation report was used:}
### Implementation Context

- Report: `.prp-output/reports/{name}-report-{TIMESTAMP}.md`
- Validation: All checks passed
- Deviations: {summary or "None"}

### Checks

{Status of any CI checks, or "Pending"}

### Next Steps

- Wait for CI checks to pass
- Request review if needed: `gh pr edit --add-reviewer @username`
- View PR: `gh pr view --web`
```

> **Note for orchestrators**: The "Next Steps" above are for standalone usage only. If this command was invoked as part of run-all, the orchestrator should ignore these suggestions and proceed to its next step.

---

## Handling Edge Cases

### Branch has diverged from main

```bash
# Suggest rebasing first
git fetch origin
git rebase origin/main
# Then push with lease
git push --force-with-lease
```

### PR template has required sections

- Parse template for required sections (often marked with `<!-- required -->`)
- Ensure all required sections are filled
- Warn if any appear incomplete

### Multiple PR templates exist

```bash
# If .github/PULL_REQUEST_TEMPLATE/ directory exists
ls .github/PULL_REQUEST_TEMPLATE/
```

- If multiple templates:
  - **Default**: Ask user which template to use
  - **If `--no-interact`**: Auto-select the default template (first one alphabetically, or `default.md` if it exists). Do NOT ask.

### Draft PR requested

```bash
gh pr create --draft --title "{title}" --body "{body}"
```

---

## Usage Examples

```
/prp-core:prp-pr                    # Create PR to main
/prp-core:prp-pr develop            # Create PR to develop branch
/prp-core:prp-pr --no-interact      # Fully autonomous, no questions
/prp-core:prp-pr main --no-interact # Autonomous to main
```

---

## Success Criteria

- BRANCH_PUSHED: Current branch exists on origin
- PR_CREATED: PR successfully created via gh
- TEMPLATE_USED: If template exists, it was used
- REPORT_ENRICHED: If implementation report exists, PR body includes context from it
- ISSUES_LINKED: Any referenced issues are linked
- URL_RETURNED: User has the PR URL to share/review

</process>

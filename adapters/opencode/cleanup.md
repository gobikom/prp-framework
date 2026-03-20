---
description: Clean up branches and verify PR status after merge
agent: build
---

# Post-Merge Cleanup

Input: $ARGUMENTS

Format: `[branch-name] [--all] [--dry-run]`

## Mission

Clean up local and remote branches after PR merge. Verify PR is actually merged before deleting. Safety first — never delete unmerged branches.

## Steps

1. **Parse Flags**: Extract `--dry-run`, `--all`, and branch name from arguments.
2. **Determine Targets**:
   - Branch name provided → use it
   - No name + not on main → use current branch
   - No name + on main → STOP: "Specify branch or use --all"
   - `--all` → `git fetch --prune origin && git branch --merged main | grep -v -E '^\*?\s*(main|master)$'`
   - If on target branch → `git checkout main && git pull origin main` first
3. **Verify PR Status** (for each branch):
   - `gh pr list --head {branch} --state all --json number,title,state,mergedAt,url --limit 1`
   - MERGED → proceed to cleanup
   - OPEN → SKIP: "PR still open"
   - CLOSED (not merged) → SKIP
   - No PR found → WARN, ask to confirm or skip (batch: auto-skip)
   - `--dry-run` → record but don't act
4. **Archive Artifacts** (on main, for each verified branch):
   - Switch to main: `git checkout main && git pull origin main`
   - **Prefer manifest**: Check `.prp-output/manifests/{BRANCH}.json` first — if found, read exact artifact paths (plan, report, context, reviews, fixes). This is precise and avoids false matches.
   - **Fallback to glob** (if no manifest): `.prp-output/reviews/pr-{NUMBER}-*.md`, `.prp-output/reviews/pr-context-{BRANCH}.md`, `.prp-output/reports/*-report*.md`, `.prp-output/plans/completed/`
   - Stage and commit: `git add {artifacts} && git commit -m "chore: archive artifacts for PR #{NUMBER} ({BRANCH})"`
   - Remove manifest: `rm -f .prp-output/manifests/{BRANCH}.json`
   - `--dry-run` → list artifacts that would be committed, don't commit
   - No artifacts found → skip, record "No artifacts to archive"
5. **Cleanup** (for each verified branch):
   - Preview: show branch, PR number, title, merged date, artifacts archived
   - `--dry-run` → show preview only, skip to output
   - Delete local: `git branch -d {branch}` (force `-D` if PR confirmed merged)
   - Delete remote: `git push origin --delete {branch}`
   - Prune refs: `git remote prune origin`
   - Remove orphaned state files: `rm -f .claude/prp-run-all.state.md` (if exists and refers to cleaned branch)
6. **Output**: Summary table (Branch | PR | Status | Artifacts | Local | Remote), cleaned/skipped counts.
   - `--dry-run` → "Dry Run Preview (no changes made)" with what would happen
   - Tips: `./scripts/cleanup-artifacts.sh 30`, `git branch -a`

## Edge Cases

- On target branch → auto-switch to main first
- Branch not fully merged (git) → force delete if PR confirmed merged
- Remote already deleted → skip gracefully
- No PR found → ask or auto-skip in batch
- No merged branches (`--all`) → "Nothing to clean up"
- Protected branches (main/master) → never included
- Network error → report, continue with next branch

## Usage

```
/prp:cleanup                        # Current branch
/prp:cleanup feat/user-auth         # Specific branch
/prp:cleanup --all                  # All merged branches
/prp:cleanup --all --dry-run        # Preview batch cleanup
```

## Success Criteria

- PR_VERIFIED: Merge status confirmed before deletion
- ARTIFACTS_ARCHIVED: Related artifacts committed to main
- LOCAL_DELETED: Local branch removed
- REMOTE_DELETED: Remote branch removed
- REFS_PRUNED: Stale refs cleaned
- DRY_RUN_SAFE: --dry-run never deletes
- PROTECTED_BRANCHES: main/master never targeted

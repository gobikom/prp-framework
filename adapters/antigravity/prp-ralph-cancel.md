---\ndescription: Cancel an active PRP Ralph loop and preserve work done so far.\n---\n

# Cancel PRP Ralph Loop

## Mission

Cancel an active Ralph loop. Preserve all work done so far — only remove the state file.

## Step 1: Check Loop Status

```bash
test -f .claude/prp-ralph.state.md && echo "ACTIVE" || echo "NOT_FOUND"
```

| Result | Action |
|--------|--------|
| NOT_FOUND | Report: "No active Ralph loop found." STOP. |
| ACTIVE | Proceed to Step 2. |

## Step 2: Read Current State

```bash
head -20 .claude/prp-ralph.state.md
```

Extract from YAML frontmatter:
- `iteration`: current iteration number
- `plan_path`: path to the plan being executed

## Step 3: Remove State File

```bash
rm .claude/prp-ralph.state.md
```

## Step 4: Report

```markdown
## Ralph Loop Cancelled

**Was at**: Iteration {N}
**Plan**: {plan_path}

The loop has been stopped. Your work so far is preserved in:
- Modified files (check `git status`)
- Git commits (if any were made)

To resume later:
- Run `/prp-ralph {plan_path}` to start fresh
- Or continue manually with `/prp-implement {plan_path}`
```

## Success Criteria

- LOOP_DETECTED: State file checked for existence
- STATE_REMOVED: `.claude/prp-ralph.state.md` deleted (if existed)
- WORK_PRESERVED: No code changes reverted — only state file removed

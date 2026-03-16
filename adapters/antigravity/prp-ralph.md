---
description: Start autonomous Ralph loop to execute PRP plan until all validations pass
---

# PRP Ralph Loop

Target: $ARGUMENTS

Format: `<plan.md|prd.md> [--max-iterations N]`

## Mission

Autonomous implementation loop. Execute a PRP plan iteratively — implement, validate, fix, repeat — until all validations pass. Self-referential: each iteration reads its own previous work from files, git history, and the state file.

## Step 0: DETECT — Project Toolchain

Identify package manager from lock files (bun/pnpm/yarn/npm/uv/cargo/go). Identify validation commands — if the plan has a Metadata table with Runner/Type Check/Lint/Test/Build, use those directly. Otherwise auto-detect:

| Ecosystem | Type Check | Lint | Test | Build |
|-----------|-----------|------|------|-------|
| JS/TS | `{runner} run type-check` | `{runner} run lint` | `{runner} test` | `{runner} run build` |
| Python | `mypy .` | `ruff check .` | `pytest` | N/A |
| Rust | `cargo check` | `cargo clippy` | `cargo test` | `cargo build` |
| Go | `go vet ./...` | `golangci-lint run` | `go test ./...` | `go build ./...` |

**Plan-provided commands take precedence.**

## Step 1: PARSE — Validate Input

Extract file path (must end `.plan.md` or `.prd.md`) and `--max-iterations N` (default: 20).

| Input | Action |
|-------|--------|
| `.plan.md` file | Use as plan |
| `.prd.md` file | Find first pending phase with completed deps, execute that |
| Free-form / empty | STOP: "Ralph requires a plan or PRD file. Create one with `/prp-plan` or `/prp-prd` first." |

Verify file exists: `test -f "{file_path}"`. If not found, STOP.

## Step 2: SETUP — Initialize State

Create `.claude/prp-ralph.state.md` with frontmatter (iteration, max, plan_path, started_at), sections: Codebase Patterns, Instructions (implement → validate → fix → repeat → `<promise>COMPLETE</promise>`), Progress Log.

```bash
mkdir -p .claude .prp-output/ralph-archives
```

Display startup:
- Plan path, iteration 1, max iterations
- "To monitor: `cat .claude/prp-ralph.state.md`"
- "To cancel: `/prp-ralph-cancel`"
- CRITICAL: Only output `<promise>COMPLETE</promise>` when ALL validations genuinely pass

## Step 3: EXECUTE — Work on Plan

1. **Read context**: state file Codebase Patterns, plan file tasks, git status, progress log
2. **Identify work**: incomplete tasks, validation commands, acceptance criteria
3. **Implement**: for each incomplete task — read requirements, follow MIRROR/patterns, make changes, run task-specific validation
4. **Validate all**: run ALL detected validation commands (type-check, lint, test, build)
5. **Coverage check**: after tests pass, verify >= 90% coverage on new/changed code. If below, write more tests.
6. **If validation fails**: analyze failure, fix, re-validate, repeat
7. **Update plan file**: mark completed tasks, add notes, document deviations
8. **Update state progress log**: append iteration block with Completed, Validation Status, Learnings, Next Steps
9. **Consolidate patterns**: add reusable codebase patterns to top of state file (general only, not iteration-specific)

### Validation Results Tracking

| Check | Result | Notes |
|-------|--------|-------|
| Type check | PASS/FAIL | {details} |
| Lint | PASS/FAIL | {details} |
| Tests | PASS/FAIL | {details} |
| Coverage | PASS/FAIL/SKIP | {%, target: 90%} |
| Build | PASS/FAIL | {details} |

## Step 4: COMPLETION CHECK

**ALL must be true**: all tasks complete, type-check passes, lint passes (0 errors), tests pass, build succeeds, acceptance criteria met.

### If ALL Pass — Complete:

1. **Report**: create `.prp-output/reports/{plan-name}-report.md` (summary, tasks, validation results, patterns, learnings, deviations)
2. **Archive**: copy state + plan + report to `.prp-output/ralph-archives/{DATE}-{PLAN_NAME}/`
3. **Update project config**: add permanent patterns if significant enough
4. **Move plan**: `mv {plan_path} .prp-output/plans/completed/`
5. **PR context**: create `.prp-output/reviews/pr-context-{BRANCH}.md` (files changed, summary, validation, review focus areas)
6. **Cleanup**: `rm .claude/prp-ralph.state.md`
7. **Output**: `<promise>COMPLETE</promise>`

### If NOT All Pass — End Iteration:

Document state in progress log, end response. Stop hook feeds prompt back for next iteration. Do NOT output the completion promise.

## Edge Cases

- **Max iterations reached**: archive incomplete state, document blockers, suggest next steps
- **Stuck on same issue**: document blocker, check patterns, try alternatives, escalate to human if stuck
- **Plan has errors**: document problems, suggest corrections, continue with what's executable

## Learnings Feedback

- **During loop**: patterns in state file, progress log with detailed notes
- **After completion**: archive in `.prp-output/ralph-archives/`, report, project config updates

## Usage

```
/prp-ralph .prp-output/plans/user-auth.plan.md
/prp-ralph .prp-output/plans/user-auth.plan.md --max-iterations 10
/prp-ralph .prp-output/prds/drafts/my-feature-prd.md

# To cancel an active loop:
/prp-ralph-cancel
```

## Success Criteria

- PLAN_EXECUTED: All tasks from plan completed
- VALIDATIONS_PASS: All validation commands succeed
- REPORT_GENERATED: Implementation report created
- LEARNINGS_CAPTURED: Progress log has useful insights
- PATTERNS_CONSOLIDATED: Reusable patterns extracted
- ARCHIVE_CREATED: Full run archived for future reference
- PR_CONTEXT_CREATED: Review context file at `.prp-output/reviews/pr-context-{BRANCH}.md`
- CLEAN_EXIT: Completion promise output only when genuinely complete

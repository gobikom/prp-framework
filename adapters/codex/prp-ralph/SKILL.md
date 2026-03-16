---
name: prp-ralph
description: Autonomous implementation loop — executes a PRP plan iteratively until all validations pass. Self-referential feedback loop with state tracking, codebase pattern learning, and archive on completion.
metadata:
  short-description: Autonomous implementation loop
---

# PRP Ralph Loop — Autonomous Implementation Until All Validations Pass

## Input

Plan or PRD file: `$ARGUMENTS`

Format: `<path-to-.plan.md|.prd.md> [--max-iterations N]`

## Mission

Start an autonomous Ralph loop that executes a PRP plan iteratively until all validations pass.

**Core Philosophy**: Self-referential feedback loop. Each iteration, you see your previous work in files and git history. You implement, validate, fix, repeat — until complete.

**Golden Rule**: Only output `<promise>COMPLETE</promise>` when ALL validations genuinely pass. Do NOT lie to exit.

## Phase 0: Detect Project Toolchain

### 0.1 Identify Package Manager

| File Found | Package Manager | Runner |
|------------|-----------------|--------|
| `bun.lockb` | bun | `bun` / `bun run` |
| `pnpm-lock.yaml` | pnpm | `pnpm` / `pnpm run` |
| `yarn.lock` | yarn | `yarn` / `yarn run` |
| `package-lock.json` | npm | `npm run` |
| `pyproject.toml` | uv/pip | `uv run` / `python` |
| `Cargo.toml` | cargo | `cargo` |
| `go.mod` | go | `go` |

### 0.2 Identify Validation Commands

> **Plan-provided commands take precedence**: If the plan contains a Metadata table with Runner/Type Check/Lint/Test/Build commands, use those directly instead of auto-detecting.

**Fallback — auto-detect from project config:**

| Ecosystem | Type Check | Lint | Test | Build |
|-----------|-----------|------|------|-------|
| JS/TS | `{runner} run type-check` | `{runner} run lint` | `{runner} test` | `{runner} run build` |
| Python | `mypy .` | `ruff check .` | `pytest` | N/A |
| Rust | `cargo check` | `cargo clippy` | `cargo test` | `cargo build` |
| Go | `go vet ./...` | `golangci-lint run` | `go test ./...` | `go build ./...` |

**Store detected commands** — use consistently for all validation steps.

## Phase 1: PARSE — Validate Input

### 1.1 Parse Arguments

Extract from input:
- **File path**: Must end in `.plan.md` or `.prd.md`
- **Max iterations**: `--max-iterations N` (default: 20)

### 1.2 Validate Input Type

| Input | Action |
|-------|--------|
| Ends with `.plan.md` | Valid — use as plan file |
| Ends with `.prd.md` | Valid — select next pending phase with complete dependencies |
| Free-form text | STOP: "Ralph requires a PRP plan or PRD file." |
| No input | STOP: "Ralph requires a PRP plan or PRD file." |

### 1.3 Verify File Exists

```bash
test -f "{file_path}" && echo "EXISTS" || echo "NOT_FOUND"
```

**If NOT_FOUND**: STOP with error message.

**PHASE_1_CHECKPOINT:**
- [ ] Input parsed (file path + max iterations)
- [ ] File exists and is valid type
- [ ] If PRD: next phase identified

## Phase 2: SETUP — Initialize Ralph Loop

### 2.1 Create State File

```bash
mkdir -p .claude
mkdir -p .prp-output/ralph-archives
```

Write `.claude/prp-ralph.state.md` with:
- YAML frontmatter: iteration, max_iterations, plan_path, input_type, started_at
- Sections: Codebase Patterns, Current Task, Plan Reference, Instructions, Progress Log

### 2.2 Display Startup Message

Show: Plan path, iteration count, max iterations, how to monitor (`cat .claude/prp-ralph.state.md`), how to cancel (`$prp-ralph-cancel`).

**PHASE_2_CHECKPOINT:**
- [ ] Toolchain detected and runner stored
- [ ] State file created at `.claude/prp-ralph.state.md`
- [ ] Archive directory exists
- [ ] Startup message displayed

## Phase 3: EXECUTE — Work on Plan

### 3.1 Read Context First

Before implementing anything:
1. Read state file — check "Codebase Patterns" section
2. Read plan file — understand all tasks
3. Check git status — what's already changed?
4. Review progress log — what did previous iterations do?

### 3.2 Implement

For each incomplete task:
1. Read the task requirements
2. Read any MIRROR/pattern references
3. Implement the change
4. Run task-specific validation if specified

### 3.3 Validate

Run ALL validation commands from Phase 0.

### 3.4 Coverage Check

After tests pass, verify coverage on new/changed code:

| Ecosystem | Coverage Command |
|-----------|-----------------|
| JS/TS (jest) | `{runner} test --coverage` |
| JS/TS (vitest) | `{runner} run test --coverage` |
| Python | `pytest --cov=. --cov-report=term-missing` |
| Rust | `cargo tarpaulin` or `cargo llvm-cov` |
| Go | `go test -coverprofile=coverage.out ./...` |

Target: >= 90% on new code. If below, write additional tests. If no coverage tool available, skip with note.

### 3.5 If Any Validation Fails

1. Analyze the failure
2. Fix the issue
3. Re-run validation
4. Repeat until passing

### 3.6 Update Plan File

Mark completed tasks with checkboxes, add notes about what was done, document deviations.

### 3.7 Update State File Progress Log

Append: Iteration N header, Completed list, Validation Status table, Learnings, Next Steps.

### 3.8 Consolidate Codebase Patterns

If you discover a **reusable pattern**, add it to the "Codebase Patterns" section at the TOP of the state file. Only general and reusable patterns — not iteration-specific.

**PHASE_3_CHECKPOINT:**
- [ ] Context read (patterns, previous progress)
- [ ] All tasks attempted
- [ ] All validations run
- [ ] Plan file updated
- [ ] State file progress log updated
- [ ] Patterns consolidated if discovered

## Phase 4: COMPLETION CHECK

### 4.1 Verify All Validations Pass

ALL must be true:
- [ ] All tasks in plan completed
- [ ] Type check passes
- [ ] Lint passes (0 errors)
- [ ] Tests pass
- [ ] Build succeeds
- [ ] All acceptance criteria met

### 4.2 If ALL Pass — Complete the Loop

1. **Generate Implementation Report** at `.prp-output/reports/{plan-name}-report.md`
   - Summary, Tasks Completed, Validation Results, Codebase Patterns Discovered, Learnings

2. **Archive the Ralph Run** to `.prp-output/ralph-archives/{DATE}-{PLAN_NAME}/`
   - Copy state file, plan, and report as learnings.md

3. **Update Project Config** with permanent patterns (if significant enough)

4. **Archive Plan** to `.prp-output/plans/completed/`

5. **Generate Review Context File** at `.prp-output/reviews/pr-context-{BRANCH}.md`
   - Files Changed table, Implementation Summary, Validation Status, Key Changes, Review Focus Areas

6. **Clean Up State**: `rm .claude/prp-ralph.state.md`

7. **Output Completion Promise**: `<promise>COMPLETE</promise>`

### 4.3 If NOT All Pass — End Iteration

Document current state in progress log, end response normally. The stop hook will feed the prompt back for next iteration.

**Do NOT output the completion promise if validations are failing.**

## Handling Edge Cases

| Scenario | Action |
|----------|--------|
| Max iterations reached | Document incomplete state, archive, suggest next steps |
| Stuck on same issue | Document blocker, check patterns, try alternatives |
| Plan has errors | Document problems, suggest corrections, continue with executable parts |

## Usage Examples

```
$prp-ralph .prp-output/plans/user-auth-20260316-1200.plan.md
$prp-ralph .prp-output/plans/api-refactor-20260316-1200.plan.md --max-iterations 10
$prp-ralph .prp-output/prds/drafts/feature-x-prd-20260316-1200.md
```

## Success Criteria

- PLAN_EXECUTED: All tasks from plan completed
- VALIDATIONS_PASS: All validation commands succeed
- REPORT_GENERATED: Implementation report created
- LEARNINGS_CAPTURED: Progress log has useful insights
- PATTERNS_CONSOLIDATED: Reusable patterns extracted
- ARCHIVE_CREATED: Full run archived at `.prp-output/ralph-archives/`
- PR_CONTEXT_CREATED: Review context file at `.prp-output/reviews/pr-context-{BRANCH}.md`
- CLEAN_EXIT: Completion promise output only when genuinely complete

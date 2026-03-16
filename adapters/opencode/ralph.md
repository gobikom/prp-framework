---
description: Autonomous implementation loop — iterates until all validations pass
agent: build
---

# PRP Ralph Loop — Autonomous Implementation

Plan or PRD: $ARGUMENTS

## Mission

Execute a PRP plan iteratively in a self-referential feedback loop until ALL validations pass. Each iteration reads previous work from files and git history, implements, validates, fixes, and repeats.

## Steps

1. **Parse Input**: Extract file path (must end `.plan.md` or `.prd.md`) and `--max-iterations N` (default: 20). If invalid or missing → STOP with guidance to create a plan first. Verify file exists.
2. **PRD Handling** (if `.prd.md`): Read PRD, find first `Status: pending` phase with `complete` dependencies. Report which phase will execute.
3. **Detect Toolchain**: Package manager from lock files (bun/pnpm/yarn/npm/uv/cargo/go). **Plan-provided commands take precedence** — if plan has Metadata table with Runner/Type Check/Lint/Test/Build, use those directly.

   | Ecosystem | Type Check | Lint | Test | Build |
   |-----------|-----------|------|------|-------|
   | JS/TS | `{runner} run type-check` | `{runner} run lint` | `{runner} test` | `{runner} run build` |
   | Python | `mypy .` | `ruff check .` | `pytest` | N/A |
   | Rust | `cargo check` | `cargo clippy` | `cargo test` | `cargo build` |
   | Go | `go vet ./...` | `golangci-lint run` | `go test ./...` | `go build ./...` |

4. **Create State File**: Write `.claude/prp-ralph.state.md` with frontmatter (iteration, max_iterations, plan_path, input_type, started_at), sections: Codebase Patterns, Current Task, Plan Reference, Instructions, Progress Log. Also `mkdir -p .prp-output/ralph-archives`.
5. **Display Startup**: Show plan path, iteration 1, max iterations. Note: monitor via `cat .claude/prp-ralph.state.md`, cancel via `/prp:ralph-cancel`.

## Iteration Loop (Phase 3: EXECUTE)

6. **Read Context First**: State file (Codebase Patterns), plan file, `git status`, progress log from previous iterations.
7. **Identify Work**: Incomplete tasks, validation commands, acceptance criteria from plan.
8. **Implement**: For each incomplete task — read requirements, check MIRROR/pattern references, implement, run task-specific validation.
9. **Validate All**: Run ALL validation commands (type-check, lint, tests, build). **Coverage check**: after tests pass, verify >= 90% on new/changed code. Auto-detect coverage tool by ecosystem.
10. **Track Results**: Table of check/result/notes for type-check, lint, tests, coverage, build.
11. **Fix Failures**: If any validation fails → analyze, fix, re-validate. Repeat until passing.
12. **Update Plan**: Mark completed tasks with checkboxes, add notes, document deviations.
13. **Update State Progress Log**: Append iteration entry with: Completed tasks, Validation Status, Learnings (patterns, gotchas, context), Next Steps.
14. **Consolidate Patterns**: Add reusable patterns to "Codebase Patterns" section at top of state file (general patterns only, not iteration-specific).

## Completion Check (Phase 4)

15. **Verify ALL Pass**: All tasks completed + type-check + lint (0 errors) + tests + build + all acceptance criteria met.
16. **If NOT all pass**: Document state in progress log, end response. Stop hook feeds prompt back for next iteration. Do NOT output completion promise.
17. **If ALL pass**:
    - **Report**: Create `.prp-output/reports/{plan-name}-report.md` with summary, tasks, validation results, patterns, learnings, deviations.
    - **Archive**: Copy state + plan + report to `.prp-output/ralph-archives/{DATE}-{PLAN_NAME}/`.
    - **Project Config**: If significant patterns discovered, add to project config (CLAUDE.md etc.) avoiding duplicates.
    - **Move Plan**: `mv {plan_path} .prp-output/plans/completed/`
    - **Review Context**: Create `.prp-output/reviews/pr-context-{BRANCH}.md` with branch, files changed, summary, validation status, key changes, review focus areas. (Token optimization for run-all workflow.)
    - **Cleanup**: `rm .claude/prp-ralph.state.md`
    - **Output**: `<promise>COMPLETE</promise>`

## Edge Cases

- **Max iterations reached**: Document incomplete state, archive (even if incomplete), suggest next steps. Loop exits via stop hook.
- **Stuck on same issue**: Check Codebase Patterns for hints, try alternatives, document for human review if truly stuck.
- **Plan has errors**: Document problems, suggest corrections, continue with what's executable.

## Usage

```
/prp:ralph .prp-output/plans/auth-feature-20260315-1200.plan.md
/prp:ralph .prp-output/prds/drafts/auth-prd-20260315.prd.md --max-iterations 10
```

## Success Criteria

- PLAN_EXECUTED: All tasks from plan completed
- VALIDATIONS_PASS: All validation commands succeed
- REPORT_GENERATED: Implementation report created
- LEARNINGS_CAPTURED: Progress log has useful insights
- PATTERNS_CONSOLIDATED: Reusable patterns extracted
- ARCHIVE_CREATED: Full run archived in `.prp-output/ralph-archives/`
- PR_CONTEXT_CREATED: Review context file at `.prp-output/reviews/pr-context-{BRANCH}.md`
- CLEAN_EXIT: Completion promise output only when genuinely complete

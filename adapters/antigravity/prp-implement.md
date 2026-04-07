---
description: "Execute an implementation plan with rigorous validation loops — typecheck, lint, test, and build after every change. TDD approach with automatic failure recovery."
---

## Agent Mode Detection

If your input context contains `[WORKSPACE CONTEXT]` (injected by a multi-agents framework),
you are running as a sub-agent. Apply these optimizations:

- **Skip Phase 0** (project environment detection) — if the context includes a `toolchain`
  JSON block with runner/type_check/lint/test/build commands, use those directly.
  If a plan Metadata table is present, plan commands still take precedence.
- **Skip CLAUDE.md reading** in Phase 1 — already loaded by parent session.
- **Phase 1 (Load Plan)**: If no plan file path in `$ARGUMENTS`, check context files for
  plan content — the multi-agents planner may have passed it inline.

All other phases (implementation, validation loops, reporting) run unchanged.

---

# PRP Implement — Execute Implementation Plan

## Input

Path to plan file: `$ARGUMENTS`

## Mission

Execute the plan end-to-end with rigorous self-validation. You are autonomous.

**Core Philosophy**: Validation loops catch mistakes early. Run checks after every change. Fix issues immediately. The goal is a working implementation, not just code that exists.

**Golden Rule**: If a validation fails, fix it before moving on. Never accumulate broken state.

---

## Phase 0: DETECT - Project Environment

**Skip this phase entirely** if the plan's Metadata table contains Runner/Type Check/Lint/Test/Build commands. These were verified during planning and are more reliable than re-detection.

Display: "Using toolchain from plan Metadata — skipping detection."

**Only run Phase 0 when plan has NO Metadata table** (e.g., manually created plan or legacy format):

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

### 0.2 Identify Validation Scripts

Check `package.json` (or equivalent) for available scripts:
- Type checking: `type-check`, `typecheck`, `tsc`
- Linting: `lint`, `lint:fix`
- Testing: `test`, `test:unit`, `test:integration`
- Building: `build`, `compile`

### 0.3 Detect Monorepo

If the plan Metadata contains `Monorepo` and `Package` fields, use those directly. Otherwise auto-detect:

| File Found | Monorepo Type |
|------------|---------------|
| `pnpm-workspace.yaml` | pnpm workspaces |
| `turbo.json` | Turborepo |
| `nx.json` | Nx |
| `lerna.json` | Lerna |
| root `package.json` with `"workspaces"` field | yarn/npm workspaces |

If monorepo detected and plan has `Package` field, scope commands using appropriate tool syntax (`pnpm --filter`, `turbo --filter=`, `nx run pkg:`, `lerna --scope=`, `yarn workspace`, `npm -w`).

---

## Phase 1: LOAD - Read the Plan

### 1.1 Load Plan File

```bash
cat $ARGUMENTS
```

### 1.2 Extract Key Sections

Locate and understand:

- **Plan Metadata** (frontmatter) — Runner, commands, mode, status. **Update status from `pending` to `in-progress`.**
- **Metadata table** — Runner and pre-filled validation commands (Type Check, Lint, Test, Build). **If present, use these instead of auto-detecting in Phase 0.**
- **Summary** — What we're building
- **Patterns to Mirror** — Code to copy from
- **Files to Change** — CREATE/UPDATE list with **Insert At** hints (line numbers are hints — verify before editing)
- **Integration Points** — Where new code hooks into existing code (caller, hook location, wiring details)
- **Step-by-Step Tasks** — Implementation order
- **Validation Commands** — How to verify (USE THESE, not hardcoded commands)
- **Confidence Score** — Plan quality indicator (for reporting)
- **Acceptance Criteria** — Definition of done

### 1.3 Validate Plan Exists

**If plan not found:**

```
Error: Plan not found at $ARGUMENTS

Create a plan first: /prp-plan "feature description"
```

**PHASE_1_CHECKPOINT:**

- [ ] Plan file loaded
- [ ] Key sections identified
- [ ] Tasks list extracted

---

## Phase 2: PREPARE - Git State

### 2.1 Check Current State

```bash
git branch --show-current
git status --porcelain
git worktree list
```

### 2.2 Branch Decision

| Current State | Action |
|---------------|--------|
| In worktree | Use it (log: "Using worktree") |
| On main, clean | Create branch: `git checkout -b feature/{plan-slug}` |
| On main, dirty | STOP: "Stash or commit changes first" |
| On feature branch | Use it (log: "Using existing branch") |

### 2.3 Sync with Remote

```bash
git fetch origin
git pull --rebase origin main 2>/dev/null || true
```

**PHASE_2_CHECKPOINT:**

- [ ] On correct branch (not main with uncommitted work)
- [ ] Working directory ready
- [ ] Up to date with remote

---

## Phase 3: EXECUTE - Implement Tasks (TDD Approach)

**For each task in the plan's Step-by-Step Tasks section:**

### 3.1 Read Context

1. Read the **MIRROR** file reference from the task
2. Understand the pattern to follow
3. Read any **IMPORTS** specified
4. Read the **Testing Strategy** section from the plan for relevant test specs

### 3.2 Write Test First (RED)

**When to write tests first:**

| Task Type | Action |
|-----------|--------|
| **CREATE** new functions/modules | Write tests first (RED → GREEN) |
| **UPDATE** existing business logic (services, handlers, algorithms) | Write/update tests first for the changed behavior (RED → GREEN) |
| **UPDATE** configuration, schema, wiring, or imports | Skip to 3.3 (no test-first needed) |
| **DELETE** functions/modules | Update dependent tests first — remove or update tests that reference deleted code, verify callers still pass |

**Finding the test file:**
- Check plan's Testing Strategy for test file paths
- Look for co-located tests: `{filename}.test.ts`, `{filename}.spec.ts`, `__tests__/{filename}.ts`
- If no test file exists for UPDATE tasks: **create one** in the project's test directory following the existing test file naming convention. If no convention is clear, use `{filename}.test.{ext}` co-located with the source file.

1. Create the test file for this task (or add test cases to existing test file)
2. Write test cases based on the plan's Testing Strategy section:
   - Happy path tests
   - Error/edge case tests from the plan's Edge Cases Checklist
   - For UPDATE tasks: test the NEW expected behavior (should fail against current code)
3. Run tests — they SHOULD FAIL (RED) because implementation doesn't exist yet
4. If tests pass without implementation — tests are not testing the right thing, rewrite

### 3.3 Implement (GREEN)

1. Make the change exactly as specified in the task
2. Follow the pattern from MIRROR reference
3. Handle any **GOTCHA** warnings
4. Run tests — they should now PASS (GREEN)

### 3.4 Validate Immediately

**After EVERY file change, run the type-check command from the plan's Validation Commands section.**

**If the task modifies existing code** (UPDATE, not CREATE), also run focused tests:

```
{test command from plan} -- {relevant-test-file-or-pattern}
```

**To find the relevant test pattern**: look for co-located `{filename}.test.*` or `{filename}.spec.*`, check `__tests__/` directory, or search: `grep -rl "{function-or-class-name}" --include="*.test.*" --include="*.spec.*"`. If no matching test file found, skip focused tests for this task (full suite in Phase 4 will still catch regressions).

This catches regressions early — a broken test discovered after 5 more tasks is much harder to fix than one caught immediately. Skip focused tests only for CREATE tasks (no existing tests to break) and pure config/wiring tasks.

**If types or tests fail:**

1. Read the error
2. Fix the issue
3. Re-run type-check (and focused tests if applicable)
4. Only proceed when passing

### 3.5 Track Progress

Log each task as you complete it (include TDD status):

```
Task 1: CREATE src/features/x/models.ts — Test: ✅ (3 cases) — Impl: ✅
Task 2: CREATE src/features/x/service.ts — Test: ✅ (5 cases) — Impl: ✅
Task 3: UPDATE src/routes/index.ts — Impl: ✅ (no test-first for wiring)
```

**Deviation Handling:**
If you must deviate from the plan:

- Note WHAT changed
- Note WHY it changed
- Continue with the deviation documented

**PHASE_3_CHECKPOINT:**

- [ ] All tasks executed in order
- [ ] Tests written BEFORE implementation for new functions/modules
- [ ] Each task passed type-check
- [ ] Deviations documented

---

## Phase 4: VALIDATE - Full Verification

### 4.1 Static Analysis

**Run the type-check and lint commands from the plan's Validation Commands section.**

**Must pass with zero errors.**

If lint errors:

1. Run the lint fix command (e.g., `{runner} run lint:fix`, `ruff check --fix .`)
2. Re-check
3. Manual fix remaining issues

### 4.2 Unit Tests

**You MUST write or update tests for new code.** This is not optional.

**Test requirements:**

1. Every new function/feature needs at least one test
2. Edge cases identified in the plan need tests
3. Update existing tests if behavior changed

**Write tests**, then run the test command from the plan's Validation Commands section.

**If tests fail:**

1. Read failure output
2. Determine: bug in implementation or bug in test?
3. Fix the actual issue
4. Re-run tests
5. Repeat until green

### 4.2.1 Coverage Check

**After tests pass, verify coverage on new/changed code.**

1. **Detect coverage tool:**

| Ecosystem | Coverage Command | Report |
|-----------|-----------------|--------|
| JS/TS (jest) | `{runner} test --coverage` | `--coverageReporters=text` |
| JS/TS (vitest) | `{runner} run test --coverage` | built-in |
| Python | `pytest --cov=. --cov-report=term-missing` | or `coverage run -m pytest && coverage report` |
| Rust | `cargo tarpaulin` | or `cargo llvm-cov` |
| Go | `go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out` | built-in |

2. **Focus on new/changed files only:**

```bash
# Get list of changed source files (exclude tests themselves)
CHANGED_FILES=$(git diff --name-only origin/main...HEAD | grep -E '\.(ts|tsx|js|jsx|py|rs|go)$' | grep -v -E '(test|spec|__test__)' )
```

3. **Evaluate against threshold:**

| Result | Action |
|--------|--------|
| Coverage >= 90% on new code | Proceed to Phase 4.3 |
| Coverage 70-89% on new code | Write additional tests for uncovered paths, re-run until >= 90% |
| Coverage < 70% on new code | Major gap — review test strategy, write tests for all critical paths |
| No coverage tool available | Skip with warning: "Coverage tool not detected — relying on review phase" |

**Coverage target: 90% on new/changed code** (not overall project coverage).

**Important**: This is a lightweight metric gate. The deeper behavioral quality analysis happens later during the review phase.

### 4.2.5 Integration Tests (conditional)

> **Run if**: Plan's Testing Strategy includes integration test specifications, OR project has `test:integration` or `test:e2e` script.
> **Skip if**: No integration test specs in plan and no integration test script exists.

1. Check for integration test command in plan or package.json/config
2. Run integration tests:
   ```bash
   {runner} run test:integration  # or equivalent from plan
   ```
3. **If fail**: Read error — fix — re-run — only proceed when passing

### 4.3 Build Check

**Run the build command from the plan's Validation Commands section.**

**Must complete without errors.**

### 4.4 Integration Testing (if applicable)

**If the plan involves API/server changes, use the integration test commands from the plan.**

Example pattern:
```bash
# Start server in background (command varies by project)
{runner} run dev &
SERVER_PID=$!
sleep 3

# Test endpoints (adjust URL/port per project config)
curl -s http://localhost:{port}/health | jq

# Stop server
kill $SERVER_PID
```

### 4.5 Edge Case Testing

Run any edge case tests specified in the plan.

### 4.6 Security Checks (conditional — basic SAST)

> **Run if**: Feature involves user input handling, authentication, or data storage.
> **Skip if**: Internal tooling, tests-only changes, or documentation.

**Check for common security issues in changed files:**

1. **Hardcoded secrets**: Search for API keys, tokens, passwords in source
2. **SQL injection patterns**: Search for string concatenation in queries
3. **Unsafe eval/exec**: Search for `eval()`, `exec()`, `Function()` in changed files

**If issues found**: Fix immediately. If false positive, add inline comment explaining.

### 4.7 Performance Regression (conditional)

> **Run if**: Plan's Testing Strategy includes performance benchmarks AND project has benchmark tooling.
> **Skip if**: No performance benchmarks in plan or no benchmark tool available.

1. Check for benchmark command: `test:bench`, `bench`, or plan-specified command
2. If available, run benchmark and compare against plan's baseline targets
3. Flag any regression > 20% from baseline

### 4.8 API Contract Validation (conditional)

> **Run if**: Project has OpenAPI spec, GraphQL schema, or tRPC router, AND feature modifies API surface.
> **Skip if**: No API schema files, or feature doesn't touch API endpoints.

1. Detect API schema: `openapi.yaml`, `openapi.json`, `schema.graphql`, tRPC routers
2. Validate spec/schema is still valid after changes
3. For tRPC: type-check covers this (already done in 4.1)

**PHASE_4_CHECKPOINT:**

- [ ] Type-check passes (command from plan)
- [ ] Lint passes (0 errors)
- [ ] Tests pass (all green)
- [ ] Coverage >= 90% on new/changed code (or skipped if no coverage tool)
- [ ] Integration tests pass (if applicable)
- [ ] Build succeeds
- [ ] Security checks pass (if applicable)
- [ ] Performance regression check (if applicable)
- [ ] API contract validation (if applicable)

---

## Phase 5: REPORT - Create Implementation Report

### 5.1 Create Report Directory

```bash
mkdir -p .prp-output/reports
```

### 5.2 Generate Report

**Artifact Naming (Timestamp Format)**:

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
ls .prp-output/reports/{name}-report*.md 2>/dev/null
```

**Path**: `.prp-output/reports/{name}-report-{TIMESTAMP}.md`

> **Note**: Uses timestamp format to prevent overwriting previous reports.

```markdown
# Implementation Report

**Plan**: `$ARGUMENTS`
**Source Issue**: #{number} (if applicable)
**Branch**: `{branch-name}`
**Date**: {YYYY-MM-DD}
**Status**: {COMPLETE | PARTIAL}

> **If PARTIAL**: Explain why — which tasks were completed and which remain. Mark incomplete tasks with ❌ and include the failure reason. This enables review-agents to provide partial feedback on completed work.

---

## Summary

{Brief description of what was implemented}

---

## Assessment vs Reality

Compare the original plan's assessment with what actually happened:

| Metric | Predicted | Actual | Reasoning |
|--------|-----------|--------|-----------|
| Complexity | {from plan} | {actual} | {Why it matched or differed} |
| Confidence | {from plan} | {actual} | {e.g., "root cause was correct" or "had to pivot"} |

**If implementation deviated from the plan, explain why:**

- {What changed and why}

---

## Tasks Completed

| # | Task | File | Status | Notes |
|---|------|------|--------|-------|
| 1 | {task description} | `src/x.ts` | ✅ | |
| 2 | {task description} | `src/y.ts` | ✅ | |
| 3 | {if partial: task description} | `src/z.ts` | ❌ | {failure reason} |

---

## Validation Results

| Check | Result | Details |
|-------|--------|---------|
| Type check | ✅ | No errors |
| Lint | ✅ | 0 errors, N warnings |
| Unit tests | ✅ | X passed, 0 failed |
| Build | ✅ | Compiled successfully |
| Integration | ✅/⏭️ | {result or "N/A"} |

---

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `src/x.ts` | CREATE | +{N} |
| `src/y.ts` | UPDATE | +{N}/-{M} |

---

## Deviations from Plan

{List any deviations with rationale, or "None"}

---

## Issues Encountered

{List any issues and how they were resolved, or "None"}

---

## Tests Written

| Test File | Test Cases |
|-----------|------------|
| `src/x.test.ts` | {list of test functions} |

---

## Next Steps

- [ ] Review implementation
- [ ] Create PR: `gh pr create` (if applicable)
- [ ] Merge when approved
```

### 5.3 Update Source PRD (if applicable)

**Check if plan was generated from a PRD:**
- Look in the plan file for `Source PRD:` reference
- Or check if plan filename matches a phase pattern (e.g., `feature-phase-1.plan.md`)

**If PRD source exists, you MUST update it:**

1. **Read the PRD file** using the path from plan's metadata
2. **Find the Implementation Phases table** in the PRD
3. **Locate the row** matching the phase name from this plan
4. **Update the row** by changing:
   - Status: `in-progress` → `complete`
   - Add completion date if there's a date column
5. **Save the PRD file**

**Example before:**
```markdown
| 1 | User Authentication | in-progress | `plans/auth.plan.md` |
```

**Example after:**
```markdown
| 1 | User Authentication | complete | `plans/auth.plan.md` |
```

**CRITICAL**: Do NOT skip this step. The PRD tracks overall progress and other phases depend on accurate status.

### 5.4 Archive Plan to Completed

**Always archive the plan after successful implementation:**

```bash
# Create completed directory if it doesn't exist
mkdir -p .prp-output/plans/completed

# Move plan to completed folder
mv "$ARGUMENTS" .prp-output/plans/completed/
```

**Verify both destination AND source removal:**
```bash
# Verify plan exists in completed/
ls -la .prp-output/plans/completed/$(basename "$ARGUMENTS")
# Verify plan no longer exists at original location
test ! -f "$ARGUMENTS" || echo "WARNING: Plan still exists at original location"
```

**If move fails:**

| Failure | Action |
|---------|--------|
| Name collision (file exists in `completed/`) | Use timestamped name: `mv "$ARGUMENTS" ".prp-output/plans/completed/$(basename $ARGUMENTS .plan.md)-$(date +%Y%m%d-%H%M).plan.md"` |
| Permission denied (read-only file/filesystem) | WARN: "Could not archive plan (permission denied). Plan remains at original location. Manually move it after fixing permissions." Skip the GATE — proceed to Phase 6. |
| Other error | WARN with the actual error message. Proceed to Phase 6. |

### 5.5 Generate Review Context File (for run-all workflow)

**Purpose**: Pre-generate context for review to save ~60K tokens when running via run-all workflow.

**CRITICAL**: Generate this file even if implementation fails early. Include note: "Implementation incomplete at task {N}/{total}. Partial context for review." List completed tasks with validation status and remaining tasks. This enables review to provide partial feedback.

**Path**: `.prp-output/reviews/pr-context-{BRANCH}.md`

```bash
BRANCH=$(git branch --show-current)
mkdir -p .prp-output/reviews
```

**Generate the context file:**

```markdown
# PR Review Context

**Branch**: `{BRANCH}`
**Generated**: {YYYY-MM-DD HH:MM}
**Source Plan**: `$ARGUMENTS`

---

## Files Changed

{List from git diff --name-only origin/main...HEAD}

| File | Action | Summary |
|------|--------|---------|
| `src/x.ts` | CREATE | {brief description} |
| `src/y.ts` | UPDATE | {brief description} |

---

## Implementation Summary

{Copy from the report's Summary section}

---

## Validation Status

**IMPORTANT**: Copy ACTUAL results from Phase 4 validation — do NOT use placeholders.
Use ✅ PASS or ❌ FAIL with real counts. Review will skip re-running validation
only if this table contains concrete results (not template placeholders).

| Check | Result | Details |
|-------|--------|---------|
| Type check | {✅ PASS or ❌ FAIL} | {error count or "clean"} |
| Lint | {✅ PASS or ❌ FAIL} | {warning/error count or "clean"} |
| Tests | {✅ PASS or ❌ FAIL} | {N passed, M failed, or "all passed"} |
| Build | {✅ PASS or ❌ FAIL} | {output size or "success"} |

---

## Key Changes for Review

### New Files
{List new files with brief purpose}

### Modified Files
{List modified files with what changed}

### Tests Added
{List test files and what they cover}

---

## Review Focus Areas

Based on implementation:
- {Area 1 that reviewers should focus on}
- {Area 2 that might need extra attention}
- {Any gotchas or edge cases}
```

**Save the file** to `.prp-output/reviews/pr-context-{BRANCH}.md`

**PHASE_5_CHECKPOINT:**

- [ ] Report created at `.prp-output/reports/{name}-report-{TIMESTAMP}.md`
- [ ] PRD updated (if applicable) — phase status changed from `in-progress` to `complete`
- [ ] Plan moved to `.prp-output/plans/completed/`
- [ ] Verified plan file no longer exists in original location
- [ ] Review context file created at `.prp-output/reviews/pr-context-{BRANCH}.md`

**GATE**: Do NOT proceed to Phase 6 until plan is archived. This prevents re-running the same plan.

---

## Phase 6: OUTPUT - Report to User

**Skip this phase** if invoked as part of `/prp-run-all` (detected by: `.prp-output/state/run-all.state.md` exists, or `[WORKSPACE CONTEXT]` present). The orchestrator produces its own summary in Step 7.

```markdown
## Implementation Complete

**Plan**: `$ARGUMENTS`
**Source Issue**: #{number} (if applicable)
**Branch**: `{branch-name}`
**Status**: ✅ Complete

### Validation Summary

| Check | Result |
|-------|--------|
| Type check | ✅ |
| Lint | ✅ |
| Tests | ✅ ({N} passed) |
| Build | ✅ |

### Files Changed

- {N} files created
- {M} files updated
- {K} tests written

### Deviations

{If none: "Implementation matched the plan."}
{If any: Brief summary of what changed and why}

### Artifacts

- Report: `.prp-output/reports/{name}-report-{TIMESTAMP}.md`
- Review Context: `.prp-output/reviews/pr-context-{BRANCH}.md`
- Plan archived to: `.prp-output/plans/completed/`

{If from PRD:}
### PRD Progress

**PRD**: `{prd-file-path}`
**Phase Completed**: #{number} - {phase name}

| # | Phase | Status |
|---|-------|--------|
{Updated phases table showing progress}

**Next Phase**: {next pending phase, or "All phases complete!"}
{If next phase can parallel: "Note: Phase {X} can also start now (parallel)"}

To continue: `/prp-plan {prd-path}`

### Next Steps

1. Review the report (especially if deviations noted)
2. Create PR: `gh pr create` or `/prp-pr`
3. Merge when approved
{If more phases: "4. Continue with next phase: `/prp-plan {prd-path}`"}
```

> **Note for orchestrators**: The "Next Steps" above are for standalone usage only. If this command was invoked as part of run-all, the orchestrator should ignore these suggestions and proceed to its next step (Step 3.1: verify artifacts, then Step 4: commit).

---

## Handling Failures

### Type Check Fails

1. Read error message carefully
2. Fix the type issue
3. Re-run the type-check command
4. Don't proceed until passing

### Tests Fail

1. Identify which test failed
2. Determine: implementation bug or test bug?
3. Fix the root cause (usually implementation)
4. Re-run tests
5. Repeat until green

### Lint Fails

1. Run the lint fix command for auto-fixable issues
2. Manually fix remaining issues
3. Re-run lint
4. Proceed when clean

### Build Fails

1. Usually a type or import issue
2. Check the error output
3. Fix and re-run

### Integration Test Fails

1. Check if server started correctly
2. Verify endpoint exists
3. Check request format
4. Fix implementation and retry

### Early Abort (any phase)

**Jump to Phase 5.5 (Generate Review Context) before stopping** — generate partial context with completed/remaining tasks, then Phase 5.2 (Report) if possible. Partial feedback is better than no feedback.

---

## Success Criteria

- TASKS_COMPLETE: All plan tasks executed
- TYPES_PASS: Type-check command exits 0
- LINT_PASS: Lint command exits 0 (warnings OK)
- TESTS_PASS: Test command all green
- BUILD_PASS: Build command succeeds
- REPORT_CREATED: Implementation report exists at `.prp-output/reports/`
- PR_CONTEXT_CREATED: Review context file exists at `.prp-output/reviews/pr-context-{BRANCH}.md`
- PRD_UPDATED: If plan came from PRD, phase status is `complete`
- PLAN_ARCHIVED: Original plan moved to `.prp-output/plans/completed/`
- PLAN_REMOVED: Original plan no longer in `.prp-output/plans/` (prevents re-run)

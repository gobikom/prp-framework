---
description: Create comprehensive feature implementation plan with codebase analysis and research
argument-hint: <feature description | path/to/prd.md> [--fast] [--no-interact]
---

<objective>
Transform "$ARGUMENTS" into a battle-tested implementation plan through systematic codebase exploration, pattern extraction, and strategic research.

**Core Principle**: PLAN ONLY - no code written. Create a context-rich document that enables one-pass implementation success.

**Execution Order**: CODEBASE FIRST, RESEARCH SECOND. Solutions must fit existing patterns before introducing new ones.

**Agent Strategy**: Use Task tool with subagent_type="Explore" for codebase intelligence gathering. This ensures thorough pattern discovery before any external research.
</objective>

<context>
CLAUDE.md rules: @CLAUDE.md

**Directory Discovery** (run these to understand project structure):
- List root contents: `ls -la`
- Find main source directories: `ls -la */ 2>/dev/null | head -50`
- Identify project type from config files (package.json, pyproject.toml, Cargo.toml, go.mod, etc.)

**IMPORTANT**: Do NOT assume `src/` exists. Common alternatives include:
- `app/` (Next.js, Rails, Laravel)
- `lib/` (Ruby gems, Elixir)
- `packages/` (monorepos)
- `cmd/`, `internal/`, `pkg/` (Go)
- Root-level source files (Python, scripts)

Discover the actual structure before proceeding.
</context>

<process>

## Phase 0: DETECT - Input Type Resolution

**Determine input type:**

| Input Pattern | Type | Action |
|---------------|------|--------|
| Ends with `.prd.md` | PRD file | Parse PRD, select next phase |
| Ends with `.md` and contains "Implementation Phases" | PRD file | Parse PRD, select next phase |
| File path that exists | Document | Read and extract feature description |
| Free-form text | Description | Use directly as feature input |
| Empty/blank | Conversation | Use conversation context as input |

### If PRD File Detected:

1. **Read the PRD file**
2. **Parse the Implementation Phases table** - find rows with `Status: pending`
3. **Check dependencies** - only select phases whose dependencies are `complete`
4. **Select the next actionable phase:**
   - First pending phase with all dependencies complete
   - If multiple candidates with same dependencies, note parallelism opportunity

4. **Extract phase context:**
   ```
   PHASE: {phase number and name}
   GOAL: {from phase details}
   SCOPE: {from phase details}
   SUCCESS SIGNAL: {from phase details}
   PRD CONTEXT: {problem statement, user, hypothesis from PRD}
   ```

5. **Report selection to user:**
   ```
   PRD: {prd file path}
   Selected Phase: #{number} - {name}

   {If parallel phases available:}
   Note: Phase {X} can also run in parallel (in separate worktree).

   Proceeding with Phase #{number}...
   ```

### If Free-form or Conversation Context:

- Proceed directly to Phase 1 with the input as feature description

**PHASE_0_CHECKPOINT:**
- [ ] Input type determined
- [ ] If PRD: next phase selected and dependencies verified
- [ ] Feature description ready for Phase 1

---

## Phase 0.5: DETECT — Project Toolchain

**Identify the project's package manager and validation commands** before any planning begins.

### 0.5.1 Identify Package Manager

Check for these files in the project root:

| File Found | Package Manager | Runner |
|------------|-----------------|--------|
| `bun.lockb` | bun | `bun` / `bun run` |
| `pnpm-lock.yaml` | pnpm | `pnpm` / `pnpm run` |
| `yarn.lock` | yarn | `yarn` / `yarn run` |
| `package-lock.json` | npm | `npm run` |
| `pyproject.toml` | uv/pip | `uv run` / `python` |
| `Cargo.toml` | cargo | `cargo` |
| `go.mod` | go | `go` |

**Priority**: If multiple lock files exist, use first match in order above (bun > pnpm > yarn > npm).

**Fallback**: If no lock file found, use placeholder with WARNING:
```
Runner: UNKNOWN — WARNING: No lock file detected. Validation commands use placeholders.
```

### 0.5.2 Identify Validation Scripts

Read `package.json` (or equivalent config) to find exact script names:

| Category | Common Names | Example Command |
|----------|-------------|-----------------|
| Type checking | `type-check`, `typecheck`, `tsc` | `bun run type-check` |
| Linting | `lint`, `lint:fix` | `bun run lint` |
| Testing | `test`, `test:unit`, `test:integration` | `bun test` |
| Building | `build`, `compile` | `bun run build` |

### 0.5.3 Store as Plan Metadata

Record detected toolchain for use in Validation Commands section:

```
Runner: {detected runner}
Type Check: {runner} run {script-name}
Lint: {runner} run {script-name}
Test: {runner} {test-command}
Build: {runner} run {script-name}
```

**PHASE_0_5_CHECKPOINT:**

- [ ] Package manager detected from lock file
- [ ] Validation script names read from package.json (or equivalent)
- [ ] Runner and commands stored for plan generation

---

## Phase 1: PARSE - Feature Understanding

**EXTRACT from input:**

- Core problem being solved
- User value and business impact
- Feature type: NEW_CAPABILITY | ENHANCEMENT | REFACTOR | BUG_FIX
- Complexity: LOW | MEDIUM | HIGH
- Affected systems list

**COMPLEXITY_TRIGGERS** (determines which conditional sections to include in the plan):
- **LOW**: Skip Technical Design sections, skip expanded Testing Strategy (integration/performance)
- **MEDIUM**: Include Technical Design if API or database changes detected; include Integration Tests in Testing Strategy
- **HIGH**: Include ALL Technical Design sub-sections (API contracts, DB schema, sequence diagrams, NFRs, migration); include full Testing Strategy with performance benchmarks

### Testing Decision Gates

Set explicit flags based on feature characteristics:

| Flag | Condition | Effect on Testing Strategy |
|------|-----------|---------------------------|
| `NEEDS_INTEGRATION_TESTS` | Complexity ≥ MEDIUM AND crosses service/component boundary | Include Integration Tests section |
| `NEEDS_PERF_BENCH` | Involves DB queries, API endpoints, or data processing loops | Include Performance Benchmarks section |
| `SECURITY_SENSITIVE` | Handles user input, authentication, data storage, or external APIs | Include security edge cases in testing |

Document flag values in plan Metadata table.

**FORMULATE user story:**

```
As a <user type>
I want to <action/goal>
So that <benefit/value>
```

**PHASE_1_CHECKPOINT:**

- [ ] Problem statement is specific and testable
- [ ] User story follows correct format
- [ ] Complexity assessment has rationale
- [ ] Affected systems identified

### Fast-track Mode (`--fast`)

When `--fast` flag is provided:
- **Skip**: Phase 3 (RESEARCH), Phase 4.2 (TECHNICAL DESIGN), Phase 5 (DESIGN)
- **Compact plan**: Summary, Metadata (with runner), Files to Change (with Insert At), Integration Points, Tasks (max 5), Validation Commands (pre-filled), Confidence Score
- **No**: UX diagrams, Mandatory Reading, Patterns to Mirror, expanded Testing Strategy, Risks table
- Add plan metadata: `Mode: fast-track`

**Warning** (complexity mismatch): If Explore reveals complexity > LOW (≥4 files changed, API/DB changes, multi-service interaction):
> WARNING: Feature appears too complex for fast-track. Detected: {reason}.
> Consider running without `--fast` for full planning.
> Proceeding with fast-track anyway...

**GATE**: If requirements are AMBIGUOUS:
- **Default**: STOP and ASK user for clarification before proceeding.
- **If `--no-interact` flag is set**: Do NOT ask. Use best judgment, state your assumptions in the plan under an "## Assumptions" section, and proceed.

---

## Phase 2: EXPLORE - Codebase Intelligence

**CRITICAL: Use Task tool with subagent_type="Explore" and prompt for thoroughness="very thorough"**

Example Task invocation:

```
Explore the codebase to find patterns, conventions, and integration points
relevant to implementing: [feature description].

DISCOVER:
1. Similar implementations - find analogous features with file:line references
2. Naming conventions - extract actual examples of function/class/file naming
3. Error handling patterns - how errors are created, thrown, caught
4. Logging patterns - logger usage, message formats
5. Type definitions - relevant interfaces and types
6. Test patterns - test file structure, assertion styles
7. Integration points - where new code connects to existing
8. Dependencies - relevant libraries already in use
9. Integration wiring - where do similar features get called from? What imports/registers them?
10. Insertion positions - for files that need UPDATE, where should new code be inserted? (line number, after which section/function)

Return ACTUAL code snippets from codebase, not generic examples.
```

**DOCUMENT discoveries in table format:**

| Category | File:Lines                                  | Pattern Description  | Code Snippet                              |
| -------- | ------------------------------------------- | -------------------- | ----------------------------------------- |
| NAMING   | `src/features/X/service.ts:10-15`           | camelCase functions  | `export function createThing()`           |
| ERRORS   | `src/features/X/errors.ts:5-20`             | Custom error classes | `class ThingNotFoundError`                |
| LOGGING  | `src/core/logging/index.ts:1-10`            | getLogger pattern    | `const logger = getLogger("domain")`      |
| TESTS    | `src/features/X/tests/service.test.ts:1-30` | describe/it blocks   | `describe("service", () => {`             |
| TYPES    | `src/features/X/models.ts:1-20`             | Drizzle inference    | `type Thing = typeof things.$inferSelect` |

**PHASE_2_CHECKPOINT:**

- [ ] Explore agent launched and completed successfully
- [ ] At least 3 similar implementations found with file:line refs
- [ ] Code snippets are ACTUAL (copy-pasted from codebase, not invented)
- [ ] Integration points mapped with specific file paths
- [ ] Dependencies cataloged with versions from package.json
- [ ] If <3 codebase patterns: fallback sources documented

### Explore Fallback (when <3 codebase patterns found)

If exploration returns fewer than 3 relevant patterns, expand search in this order:

1. **Adapter patterns**: Search for similar concepts in different domains within codebase
   (e.g., if no webhook handler exists, look at how HTTP handlers or event listeners are structured)
2. **Official library examples**: WebSearch for official docs of libraries in package.json
   (e.g., Stripe SDK webhook verification example, Drizzle ORM migration guide)
3. **Framework conventions**: Search for framework-standard patterns
   (e.g., Next.js API route conventions, Express middleware patterns)

Tag each pattern source:
- `SOURCE: codebase (file:line)` — primary, highest trust
- `SOURCE: adapter (file:line)` — similar concept, different domain
- `SOURCE: external ({library} v{version} docs)` — official documentation
- `SOURCE: convention ({framework} standard)` — framework convention

**Token Budget**: Max 20K tokens for exploration phase. If reaching limit, document "Exploration incomplete — {N} patterns found, may need additional discovery during implementation."

---

## Phase 3: RESEARCH - External Documentation

**ONLY AFTER Phase 2 is complete** - solutions must fit existing codebase patterns first.

**SEARCH for (use WebSearch tool):**

- Official documentation for involved libraries (match versions from package.json)
- Known gotchas, breaking changes, deprecations
- Security considerations and best practices
- Performance optimization patterns

**FORMAT references with specificity:**

```markdown
- [Library Docs v{version}](https://url#specific-section)
  - KEY_INSIGHT: {what we learned that affects implementation}
  - APPLIES_TO: {which task/file this affects}
  - GOTCHA: {potential pitfall and how to avoid}
```

**PHASE_3_CHECKPOINT:**

- [ ] Documentation versions match package.json
- [ ] URLs include specific section anchors (not just homepage)
- [ ] Gotchas documented with mitigation strategies
- [ ] No conflicting patterns between external docs and existing codebase

---

## Phase 4: ARCHITECT - Strategic Design

**ANALYZE deeply (use extended thinking if needed):**

- ARCHITECTURE_FIT: How does this integrate with the existing architecture?
- EXECUTION_ORDER: What must happen first → second → third?
- FAILURE_MODES: Edge cases, race conditions, error scenarios?
- PERFORMANCE: Will this scale? Database queries optimized?
- SECURITY: Attack vectors? Data exposure risks? Auth/authz?
- MAINTAINABILITY: Will future devs understand this code?

**DECIDE and document:**

```markdown
APPROACH_CHOSEN: [description]
RATIONALE: [why this over alternatives - reference codebase patterns]

ALTERNATIVES_REJECTED:

- [Alternative 1]: Rejected because [specific reason]
- [Alternative 2]: Rejected because [specific reason]

NOT_BUILDING (explicit scope limits):

- [Item 1 - explicitly out of scope and why]
- [Item 2 - explicitly out of scope and why]
```

**PHASE_4_CHECKPOINT:**

- [ ] Approach aligns with existing architecture and patterns
- [ ] Dependencies ordered correctly (types → repository → service → routes)
- [ ] Edge cases identified with specific mitigation strategies
- [ ] Scope boundaries are explicit and justified

### Design Doc Integration

Check for existing design document:
```bash
ls .prp-output/designs/{feature}-design-*.md 2>/dev/null
```
If found: Read and incorporate API contracts, DB schema, NFRs into the plan.
Add note in plan: "Incorporated from design doc: `{path}`"
If design doc conflicts with Explore findings: Design doc takes precedence (it was human-reviewed).

### Phase 4.2: TECHNICAL DESIGN (Conditional)

> **Include if**: Complexity is HIGH, OR feature involves new API endpoints, database schema changes, or multi-service integration.
> **Skip if**: Complexity is LOW, or feature is a simple enhancement/bug fix within existing patterns.
>
> **If a Design Doc exists** at `.prp-output/designs/{feature}-design-*.md`: Reference it and incorporate relevant sections rather than re-creating.

#### 4.2.1 API Contracts (if new/modified endpoints)

Define request/response schemas using project conventions:
- Endpoint path, method, authentication requirement
- Request schema with types and validation rules
- Response schema with success and error shapes
- Error codes table (status, code, description)

#### 4.2.2 Database Schema (if schema changes)

- New/modified table definitions (SQL or ORM format matching project conventions)
- Index strategy for query performance
- Migration approach (forward steps)
- Rollback plan (reverse migration steps)

#### 4.2.3 Sequence Diagrams (if complex multi-component flow)

- Critical path flow using Mermaid syntax
- Error/failure path flow
- Show all components involved and their interactions

#### 4.2.4 Non-Functional Requirements (if complexity is HIGH)

- Performance targets: p50, p95, p99 latency
- Caching strategy (what, TTL, invalidation)
- Security considerations specific to this feature
- Monitoring: key metrics, alerts, logging

#### 4.2.5 Migration & Rollback Plan (if modifying existing behavior)

- Data migration steps (if schema changes)
- Feature flag approach (flag name, default, rollout plan)
- Rollback trigger conditions
- Rollback execution steps

**PHASE_4B_CHECKPOINT:**

- [ ] API contracts defined with request/response schemas (if applicable)
- [ ] Database schema includes migration AND rollback (if applicable)
- [ ] Sequence diagrams cover happy path and error path (if applicable)
- [ ] NFR targets are specific and measurable (if applicable)

---

## Phase 5: DESIGN - UX Transformation

> **Note**: Architecture constraints from Phase 4 should inform UX design decisions. If architecture reveals a capability is infeasible, adjust UX accordingly.

**CREATE ASCII diagrams showing user experience before and after:**

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                              BEFORE STATE                                      ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                               ║
║   ┌─────────────┐         ┌─────────────┐         ┌─────────────┐            ║
║   │   Screen/   │ ──────► │   Action    │ ──────► │   Result    │            ║
║   │  Component  │         │   Current   │         │   Current   │            ║
║   └─────────────┘         └─────────────┘         └─────────────┘            ║
║                                                                               ║
║   USER_FLOW: [describe current step-by-step experience]                       ║
║   PAIN_POINT: [what's missing, broken, or inefficient]                        ║
║   DATA_FLOW: [how data moves through the system currently]                    ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════════════╗
║                               AFTER STATE                                      ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                               ║
║   ┌─────────────┐         ┌─────────────┐         ┌─────────────┐            ║
║   │   Screen/   │ ──────► │   Action    │ ──────► │   Result    │            ║
║   │  Component  │         │    NEW      │         │    NEW      │            ║
║   └─────────────┘         └─────────────┘         └─────────────┘            ║
║                                   │                                           ║
║                                   ▼                                           ║
║                          ┌─────────────┐                                      ║
║                          │ NEW_FEATURE │  ◄── [new capability added]          ║
║                          └─────────────┘                                      ║
║                                                                               ║
║   USER_FLOW: [describe new step-by-step experience]                           ║
║   VALUE_ADD: [what user gains from this change]                               ║
║   DATA_FLOW: [how data moves through the system after]                        ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

**DOCUMENT interaction changes:**

| Location        | Before          | After       | User_Action | Impact        |
| --------------- | --------------- | ----------- | ----------- | ------------- |
| `/route`        | State A         | State B     | Click X     | Can now Y     |
| `Component.tsx` | Missing feature | Has feature | Input Z     | Gets result W |

**PHASE_5_CHECKPOINT:**

- [ ] Before state accurately reflects current system behavior
- [ ] After state shows ALL new capabilities
- [ ] Data flows are traceable from input to output
- [ ] User value is explicit and measurable

---

## Phase 6: GENERATE - Implementation Plan File

### Artifact Naming (Timestamp Format)

**Generate timestamp**:
```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
```

**Check for existing files**:
```bash
# Look for existing files with same base name
ls .prp-output/plans/{kebab-case-feature-name}*.plan.md 2>/dev/null
```

**OUTPUT_PATH**: `.prp-output/plans/{kebab-case-feature-name}-{TIMESTAMP}.plan.md`

Example: `user-auth-feature-20260210-1430.plan.md`

Create directory if needed: `mkdir -p .prp-output/plans`

### Complexity Validation (Pre-save check)

Before saving plan, validate declared complexity matches scope:

| Declared | Expected Scope | If Mismatch |
|----------|---------------|-------------|
| LOW | ≤3 tasks, no API/DB changes | WARN: "Declared LOW but has {N} tasks / API changes. Consider MEDIUM." |
| MEDIUM | 4-10 tasks, OR API/DB changes | WARN if >10 tasks: "Consider HIGH complexity." |
| HIGH | >10 tasks, OR multi-service, OR complex technical design | OK |

If mismatch: include WARNING in plan Notes section. Do NOT auto-correct — let user decide.

**PLAN_STRUCTURE** (the template to fill and save):

```markdown
---
status: pending
created: {TIMESTAMP}
runner: {detected runner from Phase 0.5}
mode: {full | fast-track}
---

# Feature: {Feature Name}

## Summary

{One paragraph: What we're building and high-level approach}

## User Story

As a {user type}
I want to {action}
So that {benefit}

## Problem Statement

{Specific problem this solves - must be testable}

## Solution Statement

{How we're solving it - architecture overview}

## Metadata

| Field            | Value                                             |
| ---------------- | ------------------------------------------------- |
| Type             | NEW_CAPABILITY / ENHANCEMENT / REFACTOR / BUG_FIX |
| Complexity       | LOW / MEDIUM / HIGH                               |
| Systems Affected | {comma-separated list}                            |
| Dependencies     | {external libs/services with versions}            |
| Estimated Tasks  | {count}                                           |
| Runner           | {detected package manager, e.g., bun, npm, cargo} |
| Type Check       | {e.g., bun run type-check}                        |
| Lint             | {e.g., bun run lint}                              |
| Test             | {e.g., bun test}                                  |
| Build            | {e.g., bun run build}                             |

---

## UX Design

### Before State
```

{ASCII diagram - current user experience with data flows}

```

### After State
```

{ASCII diagram - new user experience with data flows}

````

### Interaction Changes
| Location | Before | After | User Impact |
|----------|--------|-------|-------------|
| {path/component} | {old behavior} | {new behavior} | {what changes for user} |

---

## Mandatory Reading

**CRITICAL: Implementation agent MUST read these files before starting any task:**

| Priority | File | Lines | Why Read This |
|----------|------|-------|---------------|
| P0 | `path/to/critical.ts` | 10-50 | Pattern to MIRROR exactly |
| P1 | `path/to/types.ts` | 1-30 | Types to IMPORT |
| P2 | `path/to/test.ts` | all | Test pattern to FOLLOW |

**External Documentation:**
| Source | Section | Why Needed |
|--------|---------|------------|
| [Lib Docs v{version}](url#anchor) | {section name} | {specific reason} |

---

## Patterns to Mirror

**NAMING_CONVENTION:**
```typescript
// SOURCE: src/features/example/service.ts:10-15
// COPY THIS PATTERN:
{actual code snippet from codebase}
````

**ERROR_HANDLING:**

```typescript
// SOURCE: src/features/example/errors.ts:5-20
// COPY THIS PATTERN:
{actual code snippet from codebase}
```

**LOGGING_PATTERN:**

```typescript
// SOURCE: src/features/example/service.ts:25-30
// COPY THIS PATTERN:
{actual code snippet from codebase}
```

**REPOSITORY_PATTERN:**

```typescript
// SOURCE: src/features/example/repository.ts:10-40
// COPY THIS PATTERN:
{actual code snippet from codebase}
```

**SERVICE_PATTERN:**

```typescript
// SOURCE: src/features/example/service.ts:40-80
// COPY THIS PATTERN:
{actual code snippet from codebase}
```

**TEST_STRUCTURE:**

```typescript
// SOURCE: src/features/example/tests/service.test.ts:1-25
// COPY THIS PATTERN:
{actual code snippet from codebase}
```

---

## Files to Change

> **Note**: Line numbers in "Insert At" are hints — verify before editing as codebase may have changed since plan generation.

| File | Action | Insert At | Justification |
|------|--------|-----------|---------------|
| `src/features/new/models.ts` | CREATE | N/A | Type definitions - re-export from schema |
| `src/features/new/schemas.ts` | CREATE | N/A | Zod validation schemas |
| `src/features/new/errors.ts` | CREATE | N/A | Feature-specific errors |
| `src/features/new/repository.ts` | CREATE | N/A | Database operations |
| `src/features/new/service.ts` | CREATE | N/A | Business logic |
| `src/features/new/index.ts` | CREATE | N/A | Public API exports |
| `src/core/database/schema.ts` | UPDATE | after line {N} (after `{lastTable}`) | Add table definition |

---

## Integration Points

**How new code connects to existing code:**

| New Code | Called By | Hook Location (file:line) | Wiring Details |
|----------|-----------|---------------------------|----------------|
| `{new file/function}` | `{existing caller}` | `{file}:{line}` | {import statement, route registration, etc.} |

---

## NOT Building (Scope Limits)

Explicit exclusions to prevent scope creep:

- {Item 1 - explicitly out of scope and why}
- {Item 2 - explicitly out of scope and why}

---

## Step-by-Step Tasks

Execute in order. Each task is atomic and independently verifiable.

### Task 1: CREATE `src/core/database/schema.ts` (update)

- **ACTION**: ADD table definition to schema
- **IMPLEMENT**: {specific columns, types, constraints}
- **MIRROR**: `src/core/database/schema.ts:XX-YY` - follow existing table pattern
- **IMPORTS**: `import { pgTable, text, timestamp } from "drizzle-orm/pg-core"`
- **GOTCHA**: {known issue to avoid, e.g., "use uuid for id, not serial"}
- **VALIDATE**: `{Type Check command from Metadata}` - types must compile

### Task 2: CREATE `src/features/new/models.ts`

- **ACTION**: CREATE type definitions file
- **IMPLEMENT**: Re-export table, define inferred types
- **MIRROR**: `src/features/projects/models.ts:1-10`
- **IMPORTS**: `import { things } from "@/core/database/schema"`
- **TYPES**: `type Thing = typeof things.$inferSelect`
- **GOTCHA**: Use `$inferSelect` for read types, `$inferInsert` for write
- **VALIDATE**: `{Type Check command from Metadata}`

### Task 3: CREATE `src/features/new/schemas.ts`

- **ACTION**: CREATE Zod validation schemas
- **IMPLEMENT**: CreateThingSchema, UpdateThingSchema
- **MIRROR**: `src/features/projects/schemas.ts:1-30`
- **IMPORTS**: `import { z } from "zod/v4"` (note: zod/v4 not zod)
- **GOTCHA**: z.record requires two args in v4
- **VALIDATE**: `{Type Check command from Metadata}`

### Task 4: CREATE `src/features/new/errors.ts`

- **ACTION**: CREATE feature-specific error classes
- **IMPLEMENT**: ThingNotFoundError, ThingAccessDeniedError
- **MIRROR**: `src/features/projects/errors.ts:1-40`
- **PATTERN**: Extend base Error, include code and statusCode
- **VALIDATE**: `npx tsc --noEmit`

### Task 5: CREATE `src/features/new/repository.ts`

- **ACTION**: CREATE database operations
- **IMPLEMENT**: findById, findByUserId, create, update, delete
- **MIRROR**: `src/features/projects/repository.ts:1-60`
- **IMPORTS**: `import { db } from "@/core/database/client"`
- **GOTCHA**: Use `results[0]` pattern, not `.first()` - check noUncheckedIndexedAccess
- **VALIDATE**: `npx tsc --noEmit`

### Task 6: CREATE `src/features/new/service.ts`

- **ACTION**: CREATE business logic layer
- **IMPLEMENT**: createThing, getThing, updateThing, deleteThing
- **MIRROR**: `src/features/projects/service.ts:1-80`
- **PATTERN**: Use repository, add logging, throw custom errors
- **IMPORTS**: `import { getLogger } from "@/core/logging"`
- **VALIDATE**: `{Type Check command from Metadata} && {Lint command from Metadata}`

### Task 7: CREATE `{source-dir}/features/new/index.ts`

- **ACTION**: CREATE public API exports
- **IMPLEMENT**: Export types, schemas, errors, service functions
- **MIRROR**: `{source-dir}/features/{example}/index.ts:1-20`
- **PATTERN**: Named exports only, hide repository (internal)
- **VALIDATE**: `{Type Check command from Metadata}`

### Task 8: CREATE `{source-dir}/features/new/tests/service.test.ts`

- **ACTION**: CREATE unit tests for service
- **IMPLEMENT**: Test each service function, happy path + error cases
- **MIRROR**: `{source-dir}/features/{example}/tests/service.test.ts:1-100`
- **PATTERN**: Use project's test framework (jest, vitest, bun:test, pytest, etc.)
- **VALIDATE**: `{Test command from Metadata} {path-to-tests}`

---

## Testing Strategy

### Unit Tests to Write

| Test File                                | Test Cases                 | Validates      |
| ---------------------------------------- | -------------------------- | -------------- |
| `src/features/new/tests/schemas.test.ts` | valid input, invalid input | Zod schemas    |
| `src/features/new/tests/errors.test.ts`  | error properties           | Error classes  |
| `src/features/new/tests/service.test.ts` | CRUD ops, access control   | Business logic |

### Integration Tests (conditional — include if MEDIUM+ complexity with multi-component interaction)

| Test Scenario | Components Involved | Setup Required | Expected Behavior |
|---------------|-------------------|----------------|-------------------|
| {end-to-end scenario} | {API → Service → DB} | {test fixtures/seed data} | {assertion} |

### Test Data Requirements

| Test Category | Data Needed | Source | Notes |
|---------------|-------------|--------|-------|
| Unit tests | {mock data} | {factory/fixture} | {special handling} |
| Integration | {seed data} | {snapshot/seed script} | {cleanup strategy} |

### Performance Benchmarks (conditional — include if HIGH complexity or performance-sensitive)

| Operation | Current Baseline | Target | Tool |
|-----------|-----------------|--------|------|
| {operation} | {p95 current or "N/A"} | {target} | {benchmark tool} |

### Edge Cases Checklist

- [ ] Empty string inputs
- [ ] Missing required fields
- [ ] Unauthorized access attempts
- [ ] Not found scenarios
- [ ] Duplicate creation attempts
- [ ] {feature-specific edge case}

---

## Validation Commands

**IMPORTANT**: Pre-fill these commands with actual values detected in Phase 0.5. The saved plan file MUST NOT contain any unfilled `{...}` placeholders in this section.

### Level 1: STATIC_ANALYSIS

```bash
# Pre-fill from Phase 0.5 detected commands:
{Lint command from Metadata} && {Type Check command from Metadata}
# Example: bun run lint && bun run type-check
```

**EXPECT**: Exit 0, no errors or warnings

### Level 2: UNIT_TESTS

```bash
# Pre-fill from Phase 0.5 detected commands:
{Test command from Metadata} {path/to/feature/tests}
# Example: bun test src/features/new/tests/
```

**EXPECT**: All tests pass, coverage >= 80%

### Level 3: FULL_SUITE

```bash
# Pre-fill from Phase 0.5 detected commands:
{Test command from Metadata} && {Build command from Metadata}
# Example: bun test && bun run build
```

**EXPECT**: All tests pass, build succeeds

### Level 4: DATABASE_VALIDATION (if schema changes)

Use Supabase MCP to verify:

- [ ] Table created with correct columns
- [ ] RLS policies applied
- [ ] Indexes created

### Level 5: BROWSER_VALIDATION (if UI changes)

Use Browser MCP to verify:

- [ ] UI renders correctly
- [ ] User flows work end-to-end
- [ ] Error states display properly

### Level 6: MANUAL_VALIDATION

{Step-by-step manual testing specific to this feature}

---

## Acceptance Criteria

- [ ] All specified functionality implemented per user story
- [ ] Level 1-3 validation commands pass with exit 0
- [ ] Unit tests cover >= 90% of new code
- [ ] Code mirrors existing patterns exactly (naming, structure, logging)
- [ ] No regressions in existing tests
- [ ] UX matches "After State" diagram

---

## Completion Checklist

- [ ] All tasks completed in dependency order
- [ ] Each task validated immediately after completion
- [ ] Level 1: Static analysis (lint + type-check) passes
- [ ] Level 2: Unit tests pass
- [ ] Level 3: Full test suite + build succeeds
- [ ] Level 4: Database validation passes (if applicable)
- [ ] Level 5: Browser validation passes (if applicable)
- [ ] All acceptance criteria met

---

## Risks and Mitigations

| Risk               | Likelihood   | Impact       | Mitigation                              |
| ------------------ | ------------ | ------------ | --------------------------------------- |
| {Risk description} | LOW/MED/HIGH | LOW/MED/HIGH | {Specific prevention/handling strategy} |

---

## Technical Design (Conditional — include for HIGH complexity or API/DB changes)

### API Contracts

{Endpoint definitions with request/response schemas — skip if no API changes}

### Database Schema Changes

{SQL/ORM definitions, indexes, migration steps, rollback plan — skip if no schema changes}

### Sequence Diagrams

```mermaid
{Sequence diagram for critical flows — skip if straightforward CRUD}
```

### Non-Functional Requirements

{Performance targets, caching, security specifics — skip if LOW complexity}

### Migration & Rollback

{Data migration steps, feature flags, rollback triggers and steps — skip if no existing behavior changes}

---

## Confidence Score

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| **Patterns** (0-2) | {0-2} | 0=none found, 1=<3 or mostly external, 2=≥3 codebase patterns |
| **Gotchas** (0-2) | {0-2} | 0=none documented, 1=some identified, 2=comprehensive with mitigations |
| **Integration** (0-2) | {0-2} | 0=no integration points, 1=partial, 2=all hook locations specified |
| **Validation** (0-2) | {0-2} | 0=placeholders remain, 1=partial commands, 2=all commands pre-filled and verified |
| **Testing** (0-2) | {0-2} | 0=no test plan, 1=unit tests only, 2=unit + edge cases + integration (if needed) |
| **Total** | **{X}/10** | 9-10: one-pass ready, 7-8: high confidence, 5-6: moderate risk, <5: needs more planning |

---

## Notes

{Additional context, design decisions, trade-offs, future considerations}

````

</process>

<output>
**OUTPUT_FILE**: `.prp-output/plans/{kebab-case-feature-name}-{TIMESTAMP}.plan.md`

**If input was from PRD file**, also update the PRD:

1. **Update phase status** in the Implementation Phases table:
   - Change the phase's Status from `pending` to `in-progress`
   - Add the plan file path to the PRP Plan column

2. **Edit the PRD file** with these changes

**REPORT_TO_USER** (display after creating plan):

```markdown
## Plan Created

**File**: `.prp-output/plans/{feature-name}-{TIMESTAMP}.plan.md`

{If from PRD:}
**Source PRD**: `{prd-file-path}`
**Phase**: #{number} - {phase name}
**PRD Updated**: Status set to `in-progress`, plan linked

{If parallel phases available:}
**Parallel Opportunity**: Phase {X} can run concurrently in a separate worktree.
To start: `git worktree add -b phase-{X} ../project-phase-{X} && cd ../project-phase-{X} && /prp-plan {prd-path}`

**Summary**: {2-3 sentence feature overview}

**Complexity**: {LOW/MEDIUM/HIGH} - {brief rationale}

**Scope**:
- {N} files to CREATE
- {M} files to UPDATE
- {K} total tasks

**Key Patterns Discovered**:
- {Pattern 1 from Explore agent with file:line}
- {Pattern 2 from Explore agent with file:line}

**External Research**:
- {Key doc 1 with version}
- {Key doc 2 with version}

**UX Transformation**:
- BEFORE: {one-line current state}
- AFTER: {one-line new state}

**Risks**:
- {Primary risk}: {mitigation}

**Confidence Score**: {X}/10 (Patterns:{P} + Gotchas:{G} + Integration:{I} + Validation:{V} + Testing:{T})
- 9-10: one-pass ready | 7-8: high confidence | 5-6: moderate | <5: needs more planning

**Next Step**: To execute, run: `/prp-implement .prp-output/plans/{feature-name}-{TIMESTAMP}.plan.md`
````

</output>

<verification>
**FINAL_VALIDATION before saving plan:**

**CONTEXT_COMPLETENESS:**

- [ ] All patterns from Explore agent documented with file:line references
- [ ] External docs versioned to match package.json
- [ ] Integration points mapped with specific file paths
- [ ] Gotchas captured with mitigation strategies
- [ ] Every task has at least one executable validation command

**IMPLEMENTATION_READINESS:**

- [ ] Tasks ordered by dependency (can execute top-to-bottom)
- [ ] Each task is atomic and independently testable
- [ ] No placeholders - all content is specific and actionable
- [ ] Pattern references include actual code snippets (copy-pasted, not invented)

**PATTERN_FAITHFULNESS:**

- [ ] Every new file mirrors existing codebase style exactly
- [ ] No unnecessary abstractions introduced
- [ ] Naming follows discovered conventions
- [ ] Error/logging patterns match existing
- [ ] Test structure matches existing tests

**VALIDATION_COVERAGE:**

- [ ] Every task has executable validation command
- [ ] All 6 validation levels defined where applicable
- [ ] Edge cases enumerated with test plans

**UX_CLARITY:**

- [ ] Before/After ASCII diagrams are detailed and accurate
- [ ] Data flows are traceable
- [ ] User value is explicit and measurable

**NO_PRIOR_KNOWLEDGE_TEST**: Could an agent unfamiliar with this codebase implement using ONLY the plan?
</verification>

<success_criteria>
**CONTEXT_COMPLETE**: All patterns, gotchas, integration points documented from actual codebase via Explore agent
**IMPLEMENTATION_READY**: Tasks executable top-to-bottom without questions, research, or clarification
**PATTERN_FAITHFUL**: Every new file mirrors existing codebase style exactly
**VALIDATION_DEFINED**: Every task has executable verification command (pre-filled)
**TOOLCHAIN_DETECTED**: Runner and commands auto-detected and pre-filled
**INTEGRATION_MAPPED**: All hook locations specified with file:line
**UX_DOCUMENTED**: Before/After transformation is visually clear with data flows
**ONE_PASS_TARGET**: Confidence score 8+ indicates high likelihood of first-attempt success
</success_criteria>

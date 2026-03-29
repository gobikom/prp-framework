---
description: "Create a comprehensive implementation plan by analyzing the codebase, discovering patterns, and producing a step-by-step actionable plan document."
agent: plan
---

## Agent Mode Detection

If your input context contains `[WORKSPACE CONTEXT]` (injected by a multi-agents framework),
you are running as a sub-agent. Apply these optimizations:

- **Skip Phase 0.5** (toolchain detection) — if the context includes a `toolchain` JSON
  block with runner/commands, use those directly instead of re-detecting.
- **Skip CLAUDE.md reading** — the parent session already loaded project conventions
  into context. Do not re-read them.
- **Skip Directory Discovery** — the parent agent already explored
  the codebase. Focus on targeted file reads for pattern extraction instead.
- **Proceed directly to Phase 1** with the feature description from context.

All other phases (codebase pattern extraction, research, plan generation) run unchanged —
these are where quality comes from.

---

# PRP Plan — Create Implementation Plan

## Input

Feature description or path to PRD file: `$ARGUMENTS`

Format: `<feature description | path/to/prd.md> [--fast] [--no-interact]`

## Objective

Transform the input into a battle-tested implementation plan through systematic codebase exploration, pattern extraction, and strategic research.

- **PLAN ONLY** — no code written
- **CODEBASE FIRST, RESEARCH SECOND** — solutions must fit existing patterns
- **Thorough Exploration** — deep codebase search before any external research
- Read project conventions file (CLAUDE.md, AGENTS.md, .cursorrules, etc.)

---

## Context: Directory Discovery

Run these to understand project structure:

```bash
ls -la
ls -la */ 2>/dev/null | head -50
```

- Identify project type from config files (package.json, pyproject.toml, Cargo.toml, go.mod, etc.)
- Do NOT assume `src/` — alternatives: `app/`, `lib/`, `packages/`, `cmd/`, `internal/`, `pkg/`

---

## Phase 0: DETECT — Input Type Resolution

**Parse flags first** (remove from input before type detection):

| Flag | Effect |
|------|--------|
| `--fast` | Fast-track mode (lighter analysis) |
| `--no-interact` | Never ask questions — use best judgment |
| `--package <name>` | Scope to a specific monorepo package (e.g., `--package api`). Sets `MONOREPO_PACKAGE`. |

| Input Pattern | Type | Action |
|---------------|------|--------|
| Ends with `.prd.md` | PRD file | Parse PRD, select next phase |
| Ends with `.md` + "Implementation Phases" | PRD file | Parse PRD, select next phase |
| File path that exists | Document | Read and extract feature description |
| Free-form text | Description | Use directly as feature input |
| Empty/blank | Conversation | Use conversation context as input |

### If PRD File Detected:

1. **Read the PRD file** — if file does not exist, STOP: "PRD file not found at `{path}`. Verify the path and try again."
2. **Parse the Implementation Phases table** — find rows with `Status: pending`. If the PRD has no "Implementation Phases" table (no table with Status/Phase columns), STOP: "PRD file has no Implementation Phases table. Add a phases table with Status column, or use free-form text input instead."
3. **Check dependencies** — only select phases whose dependencies are `complete`
4. **Select the next actionable phase:**
   - First pending phase with all dependencies complete
   - If multiple candidates with same dependencies, note parallelism opportunity
   - If NO phases are actionable (all pending phases have incomplete dependencies): STOP — "No actionable phases found. All pending phases have unmet dependencies. Check the PRD phases table for circular or unresolvable dependencies."
5. **Extract phase context:**
   ```
   PHASE: {phase number and name}
   GOAL: {from phase details}
   SCOPE: {from phase details}
   SUCCESS SIGNAL: {from phase details}
   PRD CONTEXT: {problem statement, user, hypothesis from PRD}
   ```
6. **Report selection to user:**
   ```
   PRD: {prd file path}
   Selected Phase: #{number} - {name}
   {If parallel phases available:}
   Note: Phase {X} can also run in parallel (in separate worktree).
   Proceeding with Phase #{number}...
   ```

### If Free-form or Conversation Context:

Proceed directly to Phase 1 with the input as feature description.

**GATE**: If requirements are AMBIGUOUS:
- **Default**: STOP and ASK for clarification.
- **If `--no-interact`**: Do NOT ask. Use best judgment, state assumptions in "## Assumptions" section.

**PHASE_0_CHECKPOINT:**
- [ ] Input type determined
- [ ] If PRD: next phase selected and dependencies verified
- [ ] Feature description ready for Phase 1

---

## Phase 0.5: DETECT — Project Toolchain

### 0.5.1 Identify Package Manager

| File Found | Package Manager | Runner |
|------------|-----------------|--------|
| `bun.lockb` | bun | `bun` / `bun run` |
| `pnpm-lock.yaml` | pnpm | `pnpm` / `pnpm run` |
| `yarn.lock` | yarn | `yarn` / `yarn run` |
| `package-lock.json` | npm | `npm run` |
| `pyproject.toml` | uv/pip | `uv run` / `python` |
| `Cargo.toml` | cargo | `cargo` |
| `go.mod` | go | `go` |

**Priority**: bun > pnpm > yarn > npm.
**Fallback**: If no lock file → placeholder with WARNING.

### 0.5.2 Identify Validation Scripts

Read `package.json` (or equivalent) for exact script names:

| Category | Common Names | Example Command |
|----------|-------------|-----------------|
| Type checking | `type-check`, `typecheck`, `tsc` | `bun run type-check` |
| Linting | `lint`, `lint:fix` | `bun run lint` |
| Testing | `test`, `test:unit`, `test:integration` | `bun test` |
| Building | `build`, `compile` | `bun run build` |

### 0.5.3 Store as Plan Metadata

```
Runner: {detected runner}
Type Check: {runner} run {script-name}
Lint: {runner} run {script-name}
Test: {runner} {test-command}
Build: {runner} run {script-name}
```

### 0.5.4 Detect Monorepo

Check for monorepo configuration files at project root:

| File Found | Monorepo Type |
|------------|---------------|
| `pnpm-workspace.yaml` | pnpm workspaces |
| `turbo.json` | Turborepo |
| `nx.json` | Nx |
| `lerna.json` | Lerna |
| root `package.json` with `"workspaces"` field | yarn/npm workspaces |

**If `--package` flag provided but NO monorepo config detected:**
> WARNING: `--package {name}` specified but no monorepo configuration found (no pnpm-workspace.yaml, turbo.json, nx.json, lerna.json, or workspaces field in package.json). Ignoring `--package` flag — proceeding as single-package project.

**If monorepo detected:**

1. **Discover workspace directories** — read the actual workspace config:
   ```bash
   # pnpm: read pnpm-workspace.yaml → packages: glob patterns
   cat pnpm-workspace.yaml
   # yarn/npm: read package.json → "workspaces" field
   cat package.json | jq '.workspaces'
   # Nx: read workspace.json or project.json files
   # Turbo: read turbo.json → relies on package.json workspaces
   # Fallback: scan common directories
   ls -d packages/*/ apps/*/ libs/*/ services/*/ modules/*/ 2>/dev/null
   ```

2. **List available packages** from discovered workspace directories:
   ```bash
   # Find all package.json files in workspace dirs
   find {workspace-dirs} -maxdepth 2 -name "package.json" -exec dirname {} \;
   ```

3. **Determine target package:**

   | Condition | Action |
   |-----------|--------|
   | `--package <name>` flag provided | Use that package. Set `MONOREPO_PACKAGE = <name>` |
   | Feature description mentions a specific package | Auto-detect. Confirm with user (unless `--no-interact`) |
   | Neither | Ask user to specify (unless `--no-interact` → scope to root/all) |

4. **Resolve package path** from discovered workspaces:
   ```bash
   # Find the actual directory for the package name
   PACKAGE_DIR=$(find {workspace-dirs} -maxdepth 2 -name "package.json" \
     -exec grep -l "\"name\".*\"$MONOREPO_PACKAGE\"" {} \; | head -1 | xargs dirname)
   ```
   Verify the directory exists. If not → STOP with error listing available packages.

5. **Scope toolchain commands** (override 0.5.3) — syntax varies by monorepo tool:

   | Monorepo Type | Scoped Command Pattern | Example (package: api, script: lint) |
   |---------------|------------------------|--------------------------------------|
   | pnpm workspaces | `pnpm --filter {pkg} run {script}` | `pnpm --filter api run lint` |
   | Turborepo | `turbo run {script} --filter={pkg}` | `turbo run lint --filter=api` |
   | Nx | `nx run {pkg}:{script}` | `nx run api:lint` |
   | Lerna | `lerna run {script} --scope={pkg}` | `lerna run lint --scope=api` |
   | yarn workspaces | `yarn workspace {pkg} run {script}` | `yarn workspace api run lint` |
   | npm workspaces | `npm run {script} -w {pkg}` | `npm run lint -w api` |

   Generate scoped commands for plan metadata:
   ```
   Type Check: {scoped command for type-check}
   Lint: {scoped command for lint}
   Test: {scoped command for test}
   Build: {scoped command for build}
   ```

6. **Store monorepo metadata:**
   ```
   Monorepo: {type}
   Package: {MONOREPO_PACKAGE}
   Package Dir: {PACKAGE_DIR}
   Monorepo Tool: {pnpm|turbo|nx|lerna|yarn|npm}
   ```

**If no monorepo detected and no `--package` flag**: Skip this section entirely. No impact on workflow.

**PHASE_0_5_CHECKPOINT:**
- [ ] Package manager detected from lock file
- [ ] Validation script names read from config
- [ ] Runner and commands stored for plan generation
- [ ] If monorepo: type detected, package resolved, scoped commands set

---

## Phase 1: PARSE — Feature Understanding

**Extract from input:**
- Core problem being solved
- User value and business impact
- Feature type: NEW_CAPABILITY | ENHANCEMENT | REFACTOR | BUG_FIX
- Complexity: LOW | MEDIUM | HIGH
- Affected systems list

**Complexity Triggers** (determines conditional sections):
- **LOW**: Skip Technical Design, skip expanded Testing Strategy
- **MEDIUM**: Include Technical Design if API/DB changes; include Integration Tests
- **HIGH**: Include ALL Technical Design sub-sections; include full Testing Strategy with perf benchmarks

### Testing Decision Gates

| Flag | Condition | Effect |
|------|-----------|--------|
| `NEEDS_INTEGRATION_TESTS` | Complexity ≥ MEDIUM AND crosses service boundary | Include Integration Tests section |
| `NEEDS_PERF_BENCH` | Involves DB queries, API endpoints, or data processing | Include Performance Benchmarks |
| `SECURITY_SENSITIVE` | Handles user input, auth, data storage | Include security edge cases |

**Formulate user story:**
```
As a <user type>
I want to <action/goal>
So that <benefit/value>
```

### Fast-track Mode (`--fast`)

When `--fast` flag provided:
- **Skip**: Phase 3 (Research), Phase 4.2 (Technical Design), Phase 5 (Design UX)
- **Compact plan**: Summary, Metadata (with runner), Files to Change (with Insert At), Integration Points, Tasks (max 5), Validation Commands (pre-filled), Confidence Score
- **No**: UX diagrams, Mandatory Reading, Patterns to Mirror, expanded Testing Strategy, Risks table
- Add plan metadata: `Mode: fast-track`

**Warning** (complexity mismatch): If complexity > LOW detected:
```
WARNING: Feature appears too complex for fast-track. Detected: {reason}.
Consider running without --fast for full planning.
Proceeding with fast-track anyway...
```

**PHASE_1_CHECKPOINT:**
- [ ] Problem statement is specific and testable
- [ ] User story follows correct format
- [ ] Complexity assessment has rationale
- [ ] Affected systems identified

---

## Phase 2: EXPLORE — Codebase Intelligence

**If monorepo with `MONOREPO_PACKAGE` set**: Focus exploration on `{PACKAGE_DIR}` first, then check shared packages (e.g., `packages/shared/`, `packages/common/`). Only explore other packages if cross-package integration is needed.

Thoroughly explore the codebase to discover:

1. **Similar implementations** with file:line references
2. **Naming conventions** with actual examples
3. **Error handling patterns** — how errors are created, thrown, caught
4. **Logging patterns** — logger usage, message formats
5. **Type definitions** — relevant interfaces and types
6. **Test patterns** — test file structure, assertion styles
7. **Integration points** — where new code connects to existing
8. **Dependencies** — relevant libraries already in use with versions
9. **Integration wiring** — where do similar features get called from? What imports/registers them?
10. **Insertion positions** — for files that need UPDATE, where should new code be inserted? (line number, after which section)

**Document discoveries in table format:**

| Category | File:Lines | Pattern Description | Code Snippet |
|----------|-----------|-------------------|-------------|
| NAMING | `src/features/X/service.ts:10-15` | camelCase functions | `export function createThing()` |
| ERRORS | `src/features/X/errors.ts:5-20` | Custom error classes | `class ThingNotFoundError` |
| LOGGING | `src/core/logging/index.ts:1-10` | getLogger pattern | `const logger = getLogger("domain")` |
| TESTS | `src/features/X/tests/service.test.ts:1-30` | describe/it blocks | `describe("service", () => {` |
| TYPES | `src/features/X/models.ts:1-20` | Drizzle inference | `type Thing = typeof things.$inferSelect` |

### Explore Fallback (when <3 codebase patterns found)

If fewer than 3 relevant patterns found, expand search:

1. **Analogous patterns**: Similar concepts in different domains within codebase
2. **Official library examples**: Docs of libraries in package.json (match versions)
3. **Framework conventions**: Framework-standard patterns

Tag each source:
- `SOURCE: codebase (file:line)` — primary, highest trust
- `SOURCE: analogous (file:line)` — similar concept, different domain
- `SOURCE: external ({library} v{version} docs)` — official documentation
- `SOURCE: convention ({framework} standard)` — framework convention

**Token Budget**: Max 20K tokens for exploration. If hitting limit, document "Exploration incomplete."

**PHASE_2_CHECKPOINT:**
- [ ] At least 3 similar implementations found with file:line refs
- [ ] Code snippets are ACTUAL (copy-pasted, not invented)
- [ ] Integration points mapped with specific file paths
- [ ] Dependencies cataloged with versions
- [ ] If <3 patterns: fallback sources documented

---

## Phase 3: RESEARCH — External Documentation

**ONLY AFTER Phase 2 is complete.** Solutions must fit existing codebase patterns first.

Search for:
- Official documentation for involved libraries (match versions from package.json)
- Known gotchas, breaking changes, deprecations
- Security considerations and best practices

**Format references:**
```markdown
- [Library Docs v{version}](url#specific-section)
  - KEY_INSIGHT: {what we learned}
  - APPLIES_TO: {which task/file}
  - GOTCHA: {pitfall and mitigation}
```

**PHASE_3_CHECKPOINT:**
- [ ] Documentation versions match package.json
- [ ] URLs include specific section anchors
- [ ] Gotchas documented with mitigations
- [ ] No conflicts between external docs and codebase patterns

---

## Phase 4: ARCHITECT — Strategic Design

**Analyze:**
- ARCHITECTURE_FIT: How does this integrate with existing architecture?
- EXECUTION_ORDER: What must happen first → second → third?
- FAILURE_MODES: Edge cases, race conditions, error scenarios?
- PERFORMANCE: Will this scale? Database queries optimized?
- SECURITY: Attack vectors? Data exposure risks?
- MAINTAINABILITY: Will future devs understand this?

**Document:**
```
APPROACH_CHOSEN: {description}
RATIONALE: {why this over alternatives — reference codebase patterns}

ALTERNATIVES_REJECTED:
- {Alt 1}: Rejected because {reason}
- {Alt 2}: Rejected because {reason}

NOT_BUILDING (explicit scope limits):
- {Item 1 — out of scope and why}
- {Item 2 — out of scope and why}
```

### Design Doc Integration

```bash
ls .prp-output/designs/{feature}-design-*.md 2>/dev/null
```

If found: incorporate API contracts, DB schema, NFRs. Design doc takes precedence over Explore findings.

### Phase 4.2: TECHNICAL DESIGN (Conditional)

> **Include if**: Complexity HIGH, OR new API endpoints, DB schema changes, multi-service integration.
> **Skip if**: Complexity LOW, simple enhancement/bug fix.

#### 4.2.1 API Contracts (if new/modified endpoints)
- Endpoint path, method, auth requirement
- Request/response schemas with types and validation
- Error codes table (status, code, description)

#### 4.2.2 Database Schema (if schema changes)
- New/modified table definitions (SQL or ORM format)
- Index strategy for query performance
- Migration approach + rollback plan

#### 4.2.3 Sequence Diagrams (if complex multi-component flow)
- Critical path using Mermaid syntax
- Error/failure path

#### 4.2.4 Non-Functional Requirements (if HIGH complexity)
- Performance targets: p50, p95, p99 latency
- Caching strategy (what, TTL, invalidation)
- Security considerations, monitoring

#### 4.2.5 Migration & Rollback (if modifying existing behavior)
- Data migration steps
- Feature flag approach
- Rollback triggers and steps

**PHASE_4_CHECKPOINT:**
- [ ] Approach aligns with existing architecture
- [ ] Dependencies ordered correctly
- [ ] Edge cases identified with mitigations
- [ ] Scope boundaries explicit and justified
- [ ] Technical Design sections included (if applicable)

---

## Phase 5: DESIGN — UX Transformation

> Architecture constraints from Phase 4 should inform UX design decisions.

Create Before/After ASCII diagrams showing:
- User experience and data flow changes
- USER_FLOW, PAIN_POINT/VALUE_ADD, DATA_FLOW

**Interaction Changes table:**

| Location | Before | After | User_Action | Impact |
|----------|--------|-------|-------------|--------|
| `/route` | State A | State B | Click X | Can now Y |

**PHASE_5_CHECKPOINT:**
- [ ] Before state accurately reflects current system
- [ ] After state shows ALL new capabilities
- [ ] Data flows traceable from input to output
- [ ] User value explicit and measurable

---

## Phase 6: GENERATE — Plan File

### Artifact Naming

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
ls .prp-output/plans/{kebab-case-feature-name}*.plan.md 2>/dev/null
```

**Path**: `.prp-output/plans/{kebab-case-feature-name}-{TIMESTAMP}.plan.md`

Create directory: `mkdir -p .prp-output/plans`

### Complexity Validation (Pre-save check)

| Declared | Expected Scope | If Mismatch |
|----------|---------------|-------------|
| LOW | ≤3 tasks, no API/DB changes | WARN: "Consider MEDIUM" |
| MEDIUM | 4-10 tasks, OR API/DB changes | WARN if >10 tasks |
| HIGH | >10 tasks, OR multi-service | OK |

### Plan Structure

The plan file MUST include lifecycle frontmatter (`status: pending`, `runner`, `mode`) and ALL these sections:

1. **Summary** — what we're building
2. **User Story** — who, what, why
3. **Problem/Solution Statements** — specific and testable
4. **Metadata** — type, complexity, systems, dependencies, task count, **Runner + Type Check + Lint + Test + Build commands** (+ Monorepo/Package/Filter if applicable)
5. **UX Design** — before/after ASCII diagrams + interaction changes table
6. **Mandatory Reading** — P0/P1/P2 priority files the implementer MUST read first, external docs with version
7. **Patterns to Mirror** — ACTUAL code snippets with SOURCE tags: naming, errors, logging, repository, service, tests
8. **Files to Change** — CREATE/UPDATE list with **Insert At** hints and justifications
9. **Integration Points** — new code → existing code hook locations (file:line, wiring details)
10. **NOT Building** — explicit scope limits
11. **Step-by-Step Tasks** — ordered, atomic, each with:
    - **ACTION**: What to do (CREATE/UPDATE)
    - **IMPLEMENT**: Specific details
    - **MIRROR**: Source file:lines to copy pattern from
    - **IMPORTS**: Exact import statements
    - **GOTCHA**: Known pitfalls to avoid
    - **VALIDATE**: Exact command to verify (pre-filled, no placeholders)
12. **Testing Strategy** — unit tests table + integration tests (conditional) + test data + performance benchmarks (conditional) + edge cases checklist
13. **Validation Commands** — 6 levels (Static Analysis, Unit Tests, Full Suite, Database, Browser, Manual), **pre-filled with actual commands**
14. **Confidence Score** — 5 dimensions × 2pts = 10 formula: Patterns + Gotchas + Integration + Validation + Testing
15. **Acceptance Criteria** — definition of done (including unit tests cover >= 90% of new code)
16. **Completion Checklist** — all 6 validation levels
17. **Risks and Mitigations** — likelihood, impact, strategy
18. **Technical Design** (conditional, HIGH or API/DB) — API contracts, DB schema, sequence diagrams, NFRs, migration & rollback

**IMPORTANT**: The saved plan file MUST NOT contain any unfilled `{...}` placeholders in Validation Commands section. Pre-fill with actual detected commands.

---

## Output

**Save file to**: `.prp-output/plans/{kebab-case-feature-name}-{TIMESTAMP}.plan.md`

**After saving, verify the file was written:**
```bash
test -f ".prp-output/plans/{filename}" || echo "FATAL: Plan file write failed"
```
If verification fails, STOP — do not report success.

**If from PRD**: Update PRD status to `in-progress`, link plan file path. After update, verify the PRD file was modified (re-read and confirm status changed). If update fails, WARN: "Could not update PRD status. Manually update the phase status to `in-progress`."

**Report to user:**

```markdown
## Plan Created

**File**: `.prp-output/plans/{feature-name}-{TIMESTAMP}.plan.md`

{If from PRD:}
**Source PRD**: `{prd-file-path}`
**Phase**: #{number} - {phase name}
**PRD Updated**: Status set to `in-progress`, plan linked

{If parallel phases:}
**Parallel Opportunity**: Phase {X} can run concurrently.

**Summary**: {2-3 sentence overview}
**Complexity**: {LOW/MEDIUM/HIGH} - {brief rationale}

**Scope**:
- {N} files to CREATE
- {M} files to UPDATE
- {K} total tasks

**Key Patterns**:
- {Pattern 1 from codebase with file:line}
- {Pattern 2 from codebase with file:line}

**External Research**:
- {Key doc 1 with version}

**UX Transformation**:
- BEFORE: {one-line current state}
- AFTER: {one-line new state}

**Risks**:
- {Primary risk}: {mitigation}

**Confidence Score**: {X}/10 (P:{p} G:{g} I:{i} V:{v} T:{t})

**Next Step**: `/prp:implement .prp-output/plans/{feature-name}-{TIMESTAMP}.plan.md`
```

---

## Verification

Before saving, verify:

**Context Completeness:**
- [ ] All patterns documented with file:line references
- [ ] External docs versioned to match package.json
- [ ] Gotchas captured with mitigation strategies
- [ ] Every task has at least one executable validation command

**Implementation Readiness:**
- [ ] Tasks ordered by dependency (can execute top-to-bottom)
- [ ] Each task is atomic and independently testable
- [ ] No placeholders — all content is specific and actionable
- [ ] Pattern references include actual code snippets (copy-pasted, not invented)

**Pattern Faithfulness:**
- [ ] Every new file mirrors existing codebase style
- [ ] Naming follows discovered conventions
- [ ] Error/logging patterns match existing
- [ ] Test structure matches existing tests

**Validation Coverage:**
- [ ] Every task has executable validation command
- [ ] All 6 validation levels defined where applicable
- [ ] Edge cases enumerated with test plans

**UX Clarity:**
- [ ] Before/After diagrams accurate
- [ ] Data flows traceable
- [ ] User value explicit and measurable

**NO_PRIOR_KNOWLEDGE_TEST**: Could an agent unfamiliar with this codebase implement using ONLY the plan?

---

## Success Criteria

- CONTEXT_COMPLETE: All patterns, gotchas, integration points from actual codebase
- IMPLEMENTATION_READY: Tasks executable top-to-bottom without questions
- PATTERN_FAITHFUL: Every new file mirrors existing codebase style
- VALIDATION_DEFINED: Every task has executable verification command (pre-filled)
- TOOLCHAIN_DETECTED: Runner and commands auto-detected and pre-filled
- INTEGRATION_MAPPED: All hook locations specified with file:line
- UX_DOCUMENTED: Before/After transformation visually clear
- ONE_PASS_TARGET: Confidence score 8+/10

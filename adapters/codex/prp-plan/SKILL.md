---
name: prp-plan
description: Create a comprehensive implementation plan by analyzing the codebase, discovering patterns, and producing a step-by-step actionable plan document.
metadata:
  short-description: Create implementation plan
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

## Context: Directory Discovery

Run these to understand project structure:
- `ls -la` and `ls -la */ 2>/dev/null | head -50`
- Identify project type from config files (package.json, pyproject.toml, Cargo.toml, go.mod, etc.)
- Do NOT assume `src/` — alternatives: `app/`, `lib/`, `packages/`, `cmd/`, `internal/`, `pkg/`

## Phase 0: Detect Input Type

| Input Pattern | Type | Action |
|---------------|------|--------|
| Ends with `.prd.md` | PRD file | Parse PRD, select next phase |
| Ends with `.md` + "Implementation Phases" | PRD file | Parse PRD, select next phase |
| File path that exists | Document | Read and extract feature description |
| Free-form text | Description | Use directly as feature input |
| Empty/blank | Conversation | Use conversation context as input |

### If PRD:
1. Read PRD, parse Implementation Phases table
2. Find `pending` phases with all dependencies `complete`
3. Select next actionable phase (note parallelism if multiple candidates)
4. Extract: PHASE, GOAL, SCOPE, SUCCESS SIGNAL, PRD CONTEXT
5. Report selection to user (include parallel opportunity if applicable)

**GATE**: If ambiguous → STOP and ASK for clarification.
- **If `--no-interact` flag is set**: Do NOT ask. Use best judgment, state assumptions in an "## Assumptions" section, and proceed.

## Phase 0.5: Detect Project Toolchain

Check for lock files to determine runner: bun.lockb → bun, pnpm-lock.yaml → pnpm, yarn.lock → yarn, package-lock.json → npm, pyproject.toml → uv/pip, Cargo.toml → cargo, go.mod → go. Priority: bun > pnpm > yarn > npm.

Read package.json (or equivalent) for exact script names: type-check, lint, test, build. Store as plan metadata (Runner, Type Check, Lint, Test, Build).

Fallback: If no lock file → placeholder with WARNING.

## Phase 1: Parse — Feature Understanding

Extract: core problem, user value, feature type (NEW_CAPABILITY | ENHANCEMENT | REFACTOR | BUG_FIX), complexity (LOW | MEDIUM | HIGH), affected systems.

Formulate user story: `As a <user> I want to <action> So that <benefit>`

**Testing Decision Gates**: Set flags based on feature:
- `NEEDS_INTEGRATION_TESTS`: Complexity ≥ MEDIUM AND crosses service boundary
- `NEEDS_PERF_BENCH`: Involves DB queries, API endpoints, or data processing
- `SECURITY_SENSITIVE`: Handles user input, auth, data storage

### Fast-track Mode (`--fast`)

When `--fast` flag provided: Skip Phase 3 (Research), Phase 4.2 (Technical Design), Phase 5 (Design UX). Compact plan: Summary, Metadata, Files to Change, Integration Points, Tasks (max 5), Validation Commands, Confidence Score. WARN if complexity > LOW.

**Checkpoint**: Problem specific/testable, user story correct format, complexity has rationale, systems identified.

## Phase 2: Explore — Codebase Intelligence

Thoroughly explore the codebase to find:
1. Similar implementations with file:line references
2. Naming conventions with actual examples
3. Error handling patterns
4. Logging patterns
5. Type definitions
6. Test patterns
7. Integration points
8. Dependencies with versions
9. Integration wiring — where do similar features get called from?
10. Insertion positions — for files that need UPDATE, where to insert?

Document in table: Category | File:Lines | Pattern | Code Snippet

**Explore Fallback** (when <3 codebase patterns found): Expand search: adapter patterns → official library docs → framework conventions. Tag sources: `SOURCE: codebase`, `SOURCE: adapter`, `SOURCE: external`, `SOURCE: convention`. Budget: 20K tokens.

**Checkpoint**: 3+ pattern sources (codebase or fallback), code snippets are ACTUAL (not invented), integration points mapped, dependencies cataloged.

## Phase 3: Research — External Documentation

ONLY AFTER Phase 2. Search for:
- Official docs (match versions from package.json/config)
- Gotchas, breaking changes, deprecations
- Security best practices

Format: URL with version + KEY_INSIGHT + APPLIES_TO + GOTCHA

## Phase 4: Architect — Strategic Design

Analyze: ARCHITECTURE_FIT, EXECUTION_ORDER, FAILURE_MODES, PERFORMANCE, SECURITY, MAINTAINABILITY.
Document: APPROACH_CHOSEN + RATIONALE, ALTERNATIVES_REJECTED, NOT_BUILDING (scope limits).

**Design Doc Integration**: Check `.prp-output/designs/{feature}-design-*.md`. If found, incorporate (design doc takes precedence over explore findings).

**Phase 4.2: Technical Design (conditional)**: If complexity=HIGH or API/DB changes → include: API Contracts (request/response schemas, error codes), Database Schema (tables, indexes, migration + rollback), Sequence Diagrams (Mermaid), NFRs (p95/p99 targets, caching, security), Migration & Rollback plan.

## Phase 5: Design — UX Transformation

> Architecture constraints from Phase 4 should inform UX design decisions.

Create Before/After ASCII diagrams showing:
- User experience and data flow changes
- Interaction changes table: Location | Before | After | User_Action | Impact

## Phase 6: Generate — Plan File

**Generate timestamp**: `TIMESTAMP=$(date +%Y%m%d-%H%M)`

**Complexity Validation**: Before saving, check: LOW ≤3 tasks no API/DB, MEDIUM 4-10 or API/DB, HIGH >10 or multi-service. WARN if mismatch.

Save to: `.prp-output/plans/{kebab-case-feature-name}-{TIMESTAMP}.plan.md`

Plan must include lifecycle frontmatter (`status: pending`, `runner`, `mode`) and ALL sections:
1. **Summary** — what we're building
2. **User Story** — who, what, why
3. **Problem/Solution Statements** — specific and testable
4. **Metadata** — type, complexity, systems, dependencies, task count, **Runner, Type Check, Lint, Test, Build commands**
5. **UX Design** — before/after ASCII diagrams + interaction changes table
6. **Mandatory Reading** — P0/P1/P2 priority files the implementer MUST read first
7. **Patterns to Mirror** — ACTUAL code snippets: naming, errors, logging, repository, service, tests
8. **Files to Change** — CREATE/UPDATE list with **Insert At** hints and justifications
9. **Integration Points** — new code → existing code hook locations (file:line, wiring details)
10. **NOT Building** — explicit scope limits
11. **Step-by-Step Tasks** — ordered, atomic, each with ACTION/IMPLEMENT/MIRROR/IMPORTS/GOTCHA/VALIDATE
12. **Testing Strategy** — unit tests + integration tests (conditional) + test data + performance benchmarks (conditional) + edge cases
13. **Validation Commands** — 6 levels, **pre-filled with actual commands** (no `{runner}` placeholders)
14. **Confidence Score** — 5×2=10 formula: Patterns + Gotchas + Integration + Validation + Testing
15. **Acceptance Criteria** — definition of done
16. **Completion Checklist** — all 6 validation levels
17. **Risks and Mitigations** — likelihood, impact, strategy
18. **Technical Design** (conditional, HIGH or API/DB) — API contracts, DB schema, sequence diagrams, NFRs, migration & rollback

## Output

**If from PRD**: Update PRD status to `in-progress`, link plan file.

Report to user: file path, summary, complexity, scope, key patterns, research, UX transformation, risks, **confidence score {X}/10 (P:{p} G:{g} I:{i} V:{v} T:{t})**, next step.

## Verification

Before saving, verify:
- **Context**: All patterns documented with file:line, docs versioned, gotchas captured
- **Readiness**: Tasks ordered by dependency, atomic, no placeholders, actual code snippets
- **Faithfulness**: Mirrors existing style, naming, errors, logging, tests
- **Validation**: Every task has executable command, all 6 levels defined, **no `{runner}` placeholders**
- **UX**: Before/After diagrams accurate, data flows traceable

**NO_PRIOR_KNOWLEDGE_TEST**: Could an agent unfamiliar with this codebase implement using ONLY the plan?

## Success Criteria

- CONTEXT_COMPLETE: All patterns, gotchas, integration points from actual codebase
- IMPLEMENTATION_READY: Tasks executable top-to-bottom without questions
- PATTERN_FAITHFUL: Every new file mirrors existing codebase style
- VALIDATION_DEFINED: Every task has executable verification command (pre-filled)
- TOOLCHAIN_DETECTED: Runner and commands auto-detected and pre-filled
- INTEGRATION_MAPPED: All hook locations specified with file:line
- UX_DOCUMENTED: Before/After transformation visually clear
- ONE_PASS_TARGET: Confidence score 8+/10

---
name: prp-plan
description: Create a comprehensive implementation plan by analyzing the codebase, discovering patterns, and producing a step-by-step actionable plan document.
metadata:
  short-description: Create implementation plan
---

# PRP Plan — Create Implementation Plan

## Input

Feature description or path to PRD file: `$ARGUMENTS`

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

## Phase 1: Parse — Feature Understanding

Extract: core problem, user value, feature type (NEW_CAPABILITY | ENHANCEMENT | REFACTOR | BUG_FIX), complexity (LOW | MEDIUM | HIGH), affected systems.

Formulate user story: `As a <user> I want to <action> So that <benefit>`

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

Document in table: Category | File:Lines | Pattern | Code Snippet

**Checkpoint**: 3+ similar implementations found, code snippets are ACTUAL (not invented), integration points mapped, dependencies cataloged.

## Phase 3: Research — External Documentation

ONLY AFTER Phase 2. Search for:
- Official docs (match versions from package.json/config)
- Gotchas, breaking changes, deprecations
- Security best practices

Format: URL with version + KEY_INSIGHT + APPLIES_TO + GOTCHA

## Phase 4: Design — UX Transformation

Create Before/After ASCII diagrams showing:
- User experience and data flow changes
- Interaction changes table: Location | Before | After | User_Action | Impact

## Phase 5: Architect — Strategic Design

Analyze: ARCHITECTURE_FIT, EXECUTION_ORDER, FAILURE_MODES, PERFORMANCE, SECURITY, MAINTAINABILITY.
Document: APPROACH_CHOSEN + RATIONALE, ALTERNATIVES_REJECTED, NOT_BUILDING (scope limits).

## Phase 6: Generate — Plan File

Save to: `.ai-workflows/plans/{kebab-case-feature-name}.plan.md`

Plan must include ALL of these sections:
1. **Summary** — what we're building
2. **User Story** — who, what, why
3. **Problem/Solution Statements** — specific and testable
4. **Metadata** — type, complexity, systems, dependencies, task count
5. **UX Design** — before/after ASCII diagrams + interaction changes table
6. **Mandatory Reading** — P0/P1/P2 priority files the implementer MUST read first
7. **Patterns to Mirror** — ACTUAL code snippets: naming, errors, logging, repository, service, tests
8. **Files to Change** — CREATE/UPDATE list with justifications
9. **NOT Building** — explicit scope limits
10. **Step-by-Step Tasks** — ordered, atomic, each with ACTION/IMPLEMENT/MIRROR/IMPORTS/GOTCHA/VALIDATE
11. **Testing Strategy** — unit tests to write + edge cases checklist
12. **Validation Commands** — 6 levels: Static Analysis, Unit Tests, Full Suite, Database, Browser, Manual
13. **Acceptance Criteria** — definition of done
14. **Completion Checklist** — all 6 validation levels
15. **Risks and Mitigations** — likelihood, impact, strategy

## Output

**If from PRD**: Update PRD status to `in-progress`, link plan file.

Report to user: file path, summary, complexity, scope (files to CREATE/UPDATE/tasks), key patterns discovered, external research, UX transformation (BEFORE/AFTER one-liners), risks, **confidence score (1-10)/10**, next step.

## Verification

Before saving, verify:
- **Context**: All patterns documented with file:line, docs versioned, gotchas captured
- **Readiness**: Tasks ordered by dependency, atomic, no placeholders, actual code snippets
- **Faithfulness**: Mirrors existing style, naming, errors, logging, tests
- **Validation**: Every task has executable command, all 6 levels defined
- **UX**: Before/After diagrams accurate, data flows traceable

**NO_PRIOR_KNOWLEDGE_TEST**: Could an agent unfamiliar with this codebase implement using ONLY the plan?

## Success Criteria

- CONTEXT_COMPLETE: All patterns, gotchas, integration points from actual codebase
- IMPLEMENTATION_READY: Tasks executable top-to-bottom without questions
- PATTERN_FAITHFUL: Every new file mirrors existing codebase style
- VALIDATION_DEFINED: Every task has executable verification command
- UX_DOCUMENTED: Before/After transformation visually clear
- ONE_PASS_TARGET: Confidence score 8+/10

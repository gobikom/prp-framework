---
description: Create comprehensive implementation plan with codebase analysis
agent: plan
---

# PRP Plan — Create Implementation Plan

Feature: $ARGUMENTS

## Mission

Transform the input into a battle-tested implementation plan. PLAN ONLY — no code written. CODEBASE FIRST, RESEARCH SECOND. Read project conventions file.

## Directory Discovery

- `ls -la` and `ls -la */ 2>/dev/null | head -50`
- Do NOT assume `src/` — check: `app/`, `lib/`, `packages/`, `cmd/`, `internal/`, `pkg/`

## Steps

1. **Detect Input**: PRD file → parse phases (find pending with dependencies complete, note parallelism). Free text → use as feature. Empty → use conversation context.
2. **Detect Toolchain**: Check lock files (bun.lockb/pnpm-lock.yaml/yarn.lock/package-lock.json/pyproject.toml/Cargo.toml/go.mod) → determine runner → read package.json for exact script names → store as plan metadata (Runner, Type Check, Lint, Test, Build commands).
3. **Parse Feature**: Extract problem, user value, type (NEW_CAPABILITY/ENHANCEMENT/REFACTOR/BUG_FIX), complexity, affected systems. Write user story. **Testing Decision Gates**: Set flags: `NEEDS_INTEGRATION_TESTS` (MEDIUM+ AND crosses boundary), `NEEDS_PERF_BENCH` (DB/API/loops), `SECURITY_SENSITIVE` (user input/auth/storage).
4. **Explore Codebase**: Find similar implementations, naming conventions, error/logging/test patterns, integration points, integration wiring (where features get called from), insertion positions (for UPDATE files), dependencies with versions. Use ACTUAL code snippets with file:line references. Document in table format. **If <3 patterns found**: fallback to analogous patterns → official library docs → framework conventions. Tag sources (codebase/analogous/external/convention). Budget: 20K tokens.
5. **Research**: ONLY AFTER exploration. Official docs (match versions), gotchas, security. Format: URL + KEY_INSIGHT + APPLIES_TO + GOTCHA.
6. **Architect**: Analyze architecture fit, execution order, failure modes, performance, security, maintainability. Document approach chosen, rationale, alternatives rejected, scope limits. **Design Doc Integration**: Check `.prp-output/designs/` — if found, incorporate (design doc takes precedence over explore findings). **Technical Design (conditional)**: If complexity=HIGH or API/DB changes → include API Contracts, Database Schema (with migration + rollback), Sequence Diagrams (Mermaid), NFRs (p95/p99, caching, security), Migration & Rollback plan.
7. **Design UX**: Before/After ASCII diagrams with data flows. Interaction changes table. Architecture constraints from step 6 should inform UX decisions.
8. **Generate Plan**: Generate timestamp: `TIMESTAMP=$(date +%Y%m%d-%H%M)`. **Complexity Validation**: LOW ≤3 tasks no API/DB, MEDIUM 4-10 or API/DB, HIGH >10 or multi-service — WARN if mismatch. Save to `.prp-output/plans/{feature}-{TIMESTAMP}.plan.md` with plan lifecycle frontmatter (`status: pending`, `runner: {detected}`, `mode: full|fast-track`) and ALL sections:
   - Summary, User Story, Problem/Solution Statements, Metadata (including Runner/commands)
   - UX Design (before/after ASCII diagrams + interaction changes)
   - Mandatory Reading (P0/P1/P2 priority files)
   - Patterns to Mirror (ACTUAL code snippets: naming, errors, logging, repository, service, tests)
   - Files to Change (CREATE/UPDATE with **Insert At** hints and justifications)
   - Integration Points (new code → existing code hook locations with file:line)
   - NOT Building (scope limits)
   - Step-by-Step Tasks (each with ACTION/IMPLEMENT/MIRROR/IMPORTS/GOTCHA/VALIDATE)
   - Testing Strategy (unit tests + **integration tests** (conditional) + **test data requirements** + **performance benchmarks** (conditional) + edge cases)
   - **Technical Design** (conditional, HIGH or API/DB changes) — API contracts, DB schema, sequence diagrams, NFRs, migration & rollback
   - Validation Commands (6 levels — pre-filled with actual commands, no `{runner}` placeholders)
   - Confidence Score (5×2=10: Patterns + Gotchas + Integration + Validation + Testing)
   - Acceptance Criteria, Completion Checklist, Risks and Mitigations

## Output

If from PRD: Update status to `in-progress`, link plan file.

Report: file path, summary, complexity, scope, key patterns, external research, UX transformation, risks, **confidence score {X}/10 (P:{p} G:{g} I:{i} V:{v} T:{t})**, next step.

**Gate**: If ambiguous → STOP and ask for clarification.
- **If `--no-interact` flag is set**: Do NOT ask. Use best judgment, state assumptions in an "## Assumptions" section, and proceed.
- **If `--fast` flag is set**: Skip Research, Technical Design, and Design UX. Compact plan: Summary, Metadata, Files to Change, Integration Points, Tasks (max 5), Validation Commands, Confidence Score. WARN if complexity > LOW.

**Test**: Could an unfamiliar agent implement using ONLY this plan?

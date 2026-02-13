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
2. **Parse Feature**: Extract problem, user value, type (NEW_CAPABILITY/ENHANCEMENT/REFACTOR/BUG_FIX), complexity, affected systems. Write user story: `As a <user> I want to <action> So that <benefit>`.
3. **Explore Codebase**: Find similar implementations, naming conventions, error/logging/test patterns, integration points, dependencies with versions. Use ACTUAL code snippets with file:line references. Document in table format.
4. **Research**: ONLY AFTER exploration. Official docs (match versions), gotchas, security. Format: URL + KEY_INSIGHT + APPLIES_TO + GOTCHA.
5. **Design UX**: Before/After ASCII diagrams with data flows. Interaction changes table.
6. **Architect**: Analyze architecture fit, execution order, failure modes, performance, security, maintainability. Document approach chosen, rationale, alternatives rejected, scope limits.
7. **Generate Plan**: Save to `.prp-output/plans/{feature}.plan.md` with ALL sections:
   - Summary, User Story, Problem/Solution Statements, Metadata
   - UX Design (before/after ASCII diagrams + interaction changes)
   - Mandatory Reading (P0/P1/P2 priority files)
   - Patterns to Mirror (ACTUAL code snippets: naming, errors, logging, repository, service, tests)
   - Files to Change (CREATE/UPDATE with justifications)
   - NOT Building (scope limits)
   - Step-by-Step Tasks (each with ACTION/IMPLEMENT/MIRROR/IMPORTS/GOTCHA/VALIDATE)
   - Testing Strategy (unit tests + edge cases checklist)
   - Validation Commands (6 levels: Static, Unit, Full Suite, Database, Browser, Manual)
   - Acceptance Criteria, Completion Checklist, Risks and Mitigations

## Output

If from PRD: Update status to `in-progress`, link plan file.

Report: file path, summary, complexity, scope, key patterns, external research, UX transformation, risks, **confidence score (1-10)/10**, next step.

**Gate**: If ambiguous → STOP and ask for clarification.
**Test**: Could an unfamiliar agent implement using ONLY this plan?

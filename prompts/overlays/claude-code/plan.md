---
command: plan
adapter: claude-code
# This overlay restructures the plan prompt into XML sections for Claude Code.
# The generator will:
# 1. Use 'objective' and 'context' as XML-wrapped header sections
# 2. Extract everything from "## Phase 0" onwards as <process> content
# 3. Append 'output', 'verification', 'success_criteria' as XML-wrapped footer sections
# 4. Skip the title/input/objective/context sections from prompts/plan.md
#    (they're replaced by the XML sections below)
skip_before: "## Phase 0"
---

# objective

Transform "$ARGUMENTS" into a battle-tested implementation plan through systematic codebase exploration, pattern extraction, and strategic research.

**Core Principle**: PLAN ONLY - no code written. Create a context-rich document that enables one-pass implementation success.

**Execution Order**: CODEBASE FIRST, RESEARCH SECOND. Solutions must fit existing patterns before introducing new ones.

**Agent Strategy**: Use Task tool with subagent_type="Explore" for codebase intelligence gathering. This ensures thorough pattern discovery before any external research.

# context

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

# output

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

# verification

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

# success_criteria

**CONTEXT_COMPLETE**: All patterns, gotchas, integration points documented from actual codebase via Explore agent
**IMPLEMENTATION_READY**: Tasks executable top-to-bottom without questions, research, or clarification
**PATTERN_FAITHFUL**: Every new file mirrors existing codebase style exactly
**VALIDATION_DEFINED**: Every task has executable verification command (pre-filled)
**TOOLCHAIN_DETECTED**: Runner and commands auto-detected and pre-filled
**INTEGRATION_MAPPED**: All hook locations specified with file:line
**UX_DOCUMENTED**: Before/After transformation is visually clear with data flows
**ONE_PASS_TARGET**: Confidence score 8+ indicates high likelihood of first-attempt success

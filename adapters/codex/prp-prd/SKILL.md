---
name: prp-prd
description: Interactive PRD generator - problem-first, hypothesis-driven product spec with market research and technical feasibility assessment.
metadata:
  short-description: Generate product requirements document
---

# Product Requirements Document Generator

## Input

Feature or product idea: `$ARGUMENTS`

(blank = start with questions)

## Mission

Generate a comprehensive PRD through interactive question-driven process. Problem-first, hypothesis-driven, evidence-based.

**Anti-pattern**: Don't fill sections with fluff. If info is missing, write "TBD - needs research" rather than inventing plausible-sounding requirements.

## Process Overview

```
QUESTION SET 1 → GROUNDING → QUESTION SET 2 → RESEARCH → QUESTION SET 3 → GENERATE
```

Each question set builds on previous answers. Grounding phases validate assumptions.

## Phase 1: INITIATE - Core Problem

**If no input provided**, ask:

> **What do you want to build?**
> Describe the product, feature, or capability in a few sentences.

**If input provided**, confirm understanding by restating:

> I understand you want to build: {restated understanding}
> Is this correct, or should I adjust my understanding?

**GATE**: Wait for user response before proceeding.

## Phase 2: FOUNDATION - Problem Discovery

Ask these questions (present all at once, user can answer together):

> **Foundation Questions:**
>
> 1. **Who** has this problem? Be specific - not just "users" but what type of person/role?
> 2. **What** problem are they facing? Describe the observable pain, not the assumed need.
> 3. **Why** can't they solve it today? What alternatives exist and why do they fail?
> 4. **Why now?** What changed that makes this worth building?
> 5. **How** will you know if you solved it? What would success look like?

**GATE**: Wait for user responses before proceeding.

## Phase 3: GROUNDING - Market & Context Research

After foundation answers, conduct research:
- Similar products/features in the market
- How competitors solve this problem
- Common patterns and anti-patterns
- Related existing functionality in codebase (if exists)

Summarize findings to user and ask if it changes their thinking.

**GATE**: Brief pause for user input.

## Phase 4: DEEP DIVE - Vision & Users

> **Vision & Users:**
>
> 1. **Vision**: In one sentence, what's the ideal end state if this succeeds wildly?
> 2. **Primary User**: Describe your most important user - their role, context, and what triggers their need.
> 3. **Job to Be Done**: Complete this: "When [situation], I want to [motivation], so I can [outcome]."
> 4. **Non-Users**: Who is explicitly NOT the target? Who should we ignore?
> 5. **Constraints**: What limitations exist? (time, budget, technical, regulatory)

**GATE**: Wait for user responses before proceeding.

## Phase 5: GROUNDING - Technical Feasibility

Explore codebase (if exists) to assess:
1. Existing infrastructure we can leverage
2. Technical constraints or blockers
3. Similar patterns already implemented
4. Integration points and dependencies
5. Estimated complexity based on similar features

If no codebase, search for technical approaches, patterns, and challenges.

Summarize feasibility (HIGH/MEDIUM/LOW) with rationale.

**GATE**: Brief pause for user input.

## Phase 6: DECISIONS - Scope & Approach

> **Scope & Approach:**
>
> 1. **MVP Definition**: What's the absolute minimum to test if this works?
> 2. **Must Have vs Nice to Have**: What 2-3 things MUST be in v1? What can wait?
> 3. **Key Hypothesis**: Complete this: "We believe [capability] will [solve problem] for [users]. We'll know we're right when [measurable outcome]."
> 4. **Out of Scope**: What are you explicitly NOT building (even if users ask)?
> 5. **Open Questions**: What uncertainties could change the approach?

**GATE**: Wait for user responses before generating.

## Phase 7: GENERATE - Write PRD

**Output path**: `.prp-output/prds/drafts/{kebab-case-name}-prd-codex.md`

Create directory if needed: `mkdir -p .prp-output/prds/drafts`

> **Note**: Uses `-codex` suffix to identify Codex PRD drafts. Multiple tools can create draft PRDs in `drafts/` subdirectory for comparison. User manually merges best sections to final version at `.prp-output/prds/{name}-prd.md` (no suffix, root level) which Plan command will reference.

PRD must include ALL sections:
1. **Problem Statement** — who, what problem, cost of not solving
2. **Evidence** — data points or "Assumption - needs validation"
3. **Proposed Solution** — what and why this approach
4. **Key Hypothesis** — testable with measurable outcome
5. **What We're NOT Building** — explicit scope limits
6. **Success Metrics** — metric, target, measurement method
7. **Open Questions** — unresolved uncertainties
8. **Users & Context** — primary user, JTBD, non-users
9. **Solution Detail** — MoSCoW capabilities, MVP scope, user flow
10. **Technical Approach** — feasibility, architecture notes, risks
11. **Implementation Phases** — phased table with status/parallel/depends/PRP columns
12. **Phase Details** — goal, scope, success signal per phase
13. **Decisions Log** — choice, alternatives, rationale
14. **Research Summary** — market and technical context

## Phase 8: OUTPUT - Summary

Report: file path (draft), problem/solution one-liners, key metric, validation status per section, open questions count, recommended next step, implementation phases table.

**To start implementation**:
1. Manually compare draft PRDs from different tools (in `drafts/` subdirectory)
2. Merge best sections to final PRD: `.prp-output/prds/{name}-prd.md` (no suffix)
3. Run Plan workflow with final PRD path

Plan command references final merged PRD only (not drafts).

## Success Criteria

- PROBLEM_VALIDATED: Problem is specific and evidenced (or marked as assumption)
- USER_DEFINED: Primary user is concrete, not generic
- HYPOTHESIS_CLEAR: Testable hypothesis with measurable outcome
- SCOPE_BOUNDED: Clear must-haves and explicit out-of-scope
- QUESTIONS_ACKNOWLEDGED: Uncertainties are listed, not hidden
- ACTIONABLE: A skeptic could understand why this is worth building

## Usage Examples

```
$prp-prd JWT authentication for API
$prp-prd                              # Start with questions
$prp-prd usage metrics export feature
```

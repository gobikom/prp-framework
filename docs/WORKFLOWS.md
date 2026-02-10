# PRP Framework Workflows

Detailed documentation for all workflows in PRP Framework.

## Workflow: PRD (Product Requirements Document)

**Purpose:** Generate comprehensive product specifications through interactive questioning.

**Trigger:** User wants to build a new feature or product.

### Process

```
INITIATE → FOUNDATION → GROUNDING (Market) → DEEP DIVE →
GROUNDING (Technical) → DECISIONS → GENERATE → OUTPUT
```

### Phases

1. **INITIATE:** Confirm what to build
2. **FOUNDATION:** Who, What, Why, Why now, How to measure
3. **GROUNDING (Market):** Research competitors and patterns
4. **DEEP DIVE:** Vision, Primary user, JTBD, Non-users, Constraints
5. **GROUNDING (Technical):** Assess feasibility via codebase exploration
6. **DECISIONS:** MVP, Must-haves, Hypothesis, Out of scope
7. **GENERATE:** Create draft PRD in `.claude/PRPs/prds/drafts/`
8. **OUTPUT:** Summary and next steps

### Output

Draft PRD with tool-specific suffix:
- `.claude/PRPs/prds/drafts/feature-prd-agents.md` (Claude Code)
- `.claude/PRPs/prds/drafts/feature-prd-codex.md` (Codex)
- etc.

### Usage

```bash
# Claude Code
/prp-prd Add JWT authentication

# Codex
$prp-prd Add JWT authentication

# OpenCode/Gemini
/prp:prd Add JWT authentication

# Kimi/Generic
"Create a PRD for JWT authentication"
```

---

## Workflow: Design (Technical Design Document)

**Purpose:** Generate architecture blueprint for complex features (OPTIONAL REFERENCE).

**Key Principle:** Design Doc does NOT block workflow. Workflow remains: PRD → Plan → Implement.

### When to Use

- ✅ Complex features with significant architecture decisions
- ✅ Multiple integration points
- ✅ Performance/security critical features
- ❌ Simple CRUD operations
- ❌ Bug fixes
- ❌ Small enhancements

### Process

```
Load PRD → Explore Codebase → Research → Design Architecture →
Technical Decisions → NFRs → Migration Strategy → GENERATE
```

### Output

Design Doc with tool-specific suffix:
- `.claude/PRPs/designs/feature-design-agents.md`
- Includes: System architecture, API contracts, database schema, sequence diagrams, technical decisions, NFRs

### Usage

```bash
# Claude Code
/prp-design .claude/PRPs/prds/jwt-prd.md

# Codex
$prp-design .claude/PRPs/prds/jwt-prd.md

# Others similar
```

---

## Workflow: Plan (Implementation Plan)

**Purpose:** Create detailed, context-rich implementation plan from PRD or feature description.

### Process

```
Detect Input → Parse Feature → Explore Codebase → Research →
Design UX → Architect → Generate Plan
```

### Key Features

- **CODEBASE FIRST:** Discover existing patterns before external research
- **Actual Code Snippets:** MIRROR patterns with file:line references
- **6-Level Validation:** Static → Unit → Full → Database → Browser → Manual
- **PRD Integration:** Can parse PRD phases and track status

### Output

Plan file: `.claude/PRPs/plans/feature-name.plan.md`

Contains:
- User story and problem statement
- UX before/after diagrams
- Mandatory reading list (P0/P1/P2 files)
- Patterns to mirror (with actual code)
- Step-by-step tasks
- Validation commands
- Acceptance criteria

### Usage

```bash
# From feature description
/prp-plan Add JWT authentication

# From PRD
/prp-plan .claude/PRPs/prds/jwt-prd.md
```

---

## Workflow: Implement (Execute Plan)

**Purpose:** Execute implementation plan with rigorous validation loops.

### Process

```
Detect Environment → Load Plan → Prepare Git → Execute Tasks →
Full Validation → Report → PRD Update → Archive Plan
```

### Validation Levels

1. **Static Analysis:** Type-check + Lint (zero errors)
2. **Unit Tests:** Write/update tests, must pass
3. **Full Suite:** All tests + build success
4. **Database:** Schema validation (if applicable)
5. **Browser:** UI validation (if applicable)
6. **Manual:** Feature-specific checks

### Output

Implementation report: `.claude/PRPs/reports/feature-report-{tool}.md`

### Usage

```bash
/prp-implement .claude/PRPs/plans/jwt-auth.plan.md
```

---

## Workflow: Review (PR Code Review)

**Purpose:** Comprehensive multi-aspect PR review.

### Review Aspects

| Aspect | When to Run | Output |
|--------|-------------|--------|
| Code Quality | Always | Guidelines, bugs, dead code |
| Documentation | Almost always | Stale docs, new features |
| Test Coverage | When code changed | Behavioral gaps, criticality |
| Comment Analysis | When comments added | Accuracy, rot risk |
| Error Handling | When errors changed | Silent failures |
| Type Design | When types changed | Encapsulation quality |
| Simplification | Last pass | Nested ternaries, cleverness |

### Methodology

**Claude Code:** 7 specialized agents (parallel/sequential)
**Other Tools:** 7 sequential passes (single agent)

### Output

Review report: `.claude/PRPs/reviews/pr-{N}-{tool}-review.md`
Posted to GitHub as comment

### Usage

```bash
# Full review
/prp-review-agents 42

# Specific aspects
/prp-review-agents 42 tests errors

# Codex/OpenCode/Gemini
$prp-review 42 tests errors
/prp:review 42 tests errors
```

---

## Workflow: Commit (Smart Commit)

**Purpose:** Stage files and create conventional commit.

### Process

```
Check Status → Stage Files → Generate Message → Commit → Report
```

### Natural Language Targeting

```bash
# All changes
/prp-commit

# Staged only
/prp-commit staged

# Pattern matching
/prp-commit typescript files
/prp-commit src/auth/*.ts

# Exclusion
/prp-commit except tests

# New files only
/prp-commit only new files
```

### Commit Format

```
{type}: {description}

Co-Authored-By: {AI Tool} <noreply@...>
```

---

## Workflow: PR (Create Pull Request)

**Purpose:** Push branch and create GitHub PR with comprehensive description.

### Process

```
Validate → Discover Templates → Push → Create PR → Verify → Output
```

### PR Description

Automatically includes:
- Summary (bullet points)
- Changes made
- Files changed (collapsible details)
- Testing checklist
- Related issues (Fixes/Closes/Relates to #N)

### Usage

```bash
/prp-pr
```

---

## Workflow: Run All (End-to-End)

**Purpose:** Execute complete workflow from feature idea to PR.

### Process

```
Parse Input → Create Branch → Plan → Implement → Commit → PR → Review → Summary
```

### Options

```bash
# Full workflow
/prp-core-run-all Add JWT authentication

# Use existing plan
/prp-core-run-all --plan-path plans/jwt.plan.md

# Skip review
/prp-core-run-all Add JWT auth --skip-review

# No PR (just implement + commit)
/prp-core-run-all Add JWT auth --no-pr
```

---

## Tool-Specific Notes

### Claude Code
- ✅ Full multi-agent support
- ✅ Task tool for exploration
- ✅ WebSearch for research
- ✅ Parallel agent execution

### Codex / OpenCode / Gemini
- ✅ Same logic, sequential execution
- ✅ Full feature parity
- ⚠️ No parallel agents

### Kimi / Generic
- ✅ Natural language triggers
- ✅ Reads AGENTS.md
- ⚠️ Manual context passing

## Artifact Naming Convention

ทุก artifact ใช้ **timestamp format** เพื่อป้องกันการเขียนไฟล์ซ้ำ

### Timestamp Format

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
# ผลลัพธ์: 20260210-1430
```

### Artifact Paths

| Workflow | Artifact Path Example |
|----------|----------------------|
| PRD | `prds/drafts/auth-prd-agents-20260210-1430.md` |
| Design | `designs/auth-design-agents-20260210-1430.md` |
| Plan | `plans/auth-20260210-1430.plan.md` |
| Implement | `reports/auth-report-20260210-1430.md` |
| Debug | `debug/rca-login-error-20260210-1430.md` |
| Issue Investigate | `issues/issue-123-20260210-1430.md` |
| Review | `reviews/pr-42-review.md` (ใช้ PR number) |
| Feature Review | `reviews/feature-review-auth-20260210.md` (ใช้ date) |

### หา Artifact ล่าสุด

```bash
# หา artifact ล่าสุดโดย sort by modified time
ls -t .claude/PRPs/plans/*.plan.md | head -1
```

### Cleanup

```bash
# ลบ artifacts เก่ากว่า 30 วัน
./scripts/cleanup-artifacts.sh 30
```

---

## Best Practices

1. **Start with PRD** for non-trivial features
2. **Use Design Doc** for complex architecture
3. **Trust the Plan** - comprehensive exploration
4. **Validate Early** - type-check after every file change
5. **Review Often** - catch issues before merge
6. **Natural Commits** - let AI suggest message
7. **Cleanup Regularly** - run cleanup script weekly to remove old artifacts

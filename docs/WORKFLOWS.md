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
7. **GENERATE:** Create draft PRD in `.prp-output/prds/drafts/`
8. **OUTPUT:** Summary and next steps

### Output

Draft PRD with tool-specific suffix:
- `.prp-output/prds/drafts/feature-prd-agents.md` (Claude Code)
- `.prp-output/prds/drafts/feature-prd-codex.md` (Codex)
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
- `.prp-output/designs/feature-design-agents.md`
- Includes: System architecture, API contracts, database schema, sequence diagrams, technical decisions, NFRs

### Usage

```bash
# Claude Code
/prp-design .prp-output/prds/jwt-prd.md

# Codex
$prp-design .prp-output/prds/jwt-prd.md

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

Plan file: `.prp-output/plans/feature-name.plan.md`

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
/prp-plan .prp-output/prds/jwt-prd.md
```

---

## Workflow: Implement (Execute Plan)

**Purpose:** Execute implementation plan with rigorous validation loops.

### Process

```
Detect Environment → Load Plan → Prepare Git → Execute Tasks →
Full Validation (+ Coverage Check) → Report → Generate Review Context →
PRD Update → Archive Plan
```

### Validation Levels

1. **Static Analysis:** Type-check + Lint (zero errors)
2. **Unit Tests:** Write/update tests, must pass
3. **Coverage Check:** 90% on new/changed code (auto-detect tool, graceful skip if unavailable)
4. **Build:** Must succeed
5. **Integration:** Server/endpoint testing (if applicable)
6. **Edge Cases:** From plan specification

### Coverage Check (Phase 4.2.1)

After tests pass, coverage is checked on new/changed files only:

| Result | Action |
|--------|--------|
| >= 90% | Proceed |
| 70-89% | Write additional tests, re-run |
| < 70% | Major gap — write tests for all critical paths |
| No tool | Skip with warning |

Supported coverage tools: jest `--coverage`, vitest `--coverage`, pytest `--cov`, cargo tarpaulin, go test `-cover`

### Output

- Implementation report: `.prp-output/reports/feature-report-{tool}.md`
- Review context: `.prp-output/reviews/pr-context-{branch}.md` (saves ~60K tokens in run-all workflow)

### Usage

```bash
/prp-implement .prp-output/plans/jwt-auth.plan.md
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

### Context Optimization

When run via `run-all`, review receives a pre-generated context file via `--context` flag. This skips redundant file gathering and saves ~60K tokens. If context file is not available, review proceeds normally.

### Methodology

**Claude Code:** 7 specialized agents (parallel/sequential)
**Other Tools:** 7 sequential passes (single agent)

### Output

Review report: `.prp-output/reviews/pr-{N}-{tool}-review.md`
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

## Workflow: Review Fix (Apply Review Findings)

**Purpose:** Fix all issues found by the Review workflow — applied directly to the PR branch.

**When to Use:** After running Review (or Review Agents) and wanting AI to automatically fix Critical, High, Medium, and/or Suggestion issues.

### Process

```
Load Artifact → Resolve Artifact → Checkout PR Branch →
Triage → Fix (per severity batch) → Validate → Commit → Push → Comment on PR
```

### Artifact Resolution

When multiple tools have reviewed the same PR, the command lists all artifacts and prompts the user to select:

```
Multiple reviews found for PR #123:
  [1] pr-123-review.md          (claude-code)   2026-02-27 14:30  ← most recent
  [2] pr-123-review-codex.md    (codex)         2026-02-27 10:15
  [3] pr-123-review-gemini.md   (gemini)        2026-02-26 09:00

Which review to fix? (Enter for [1]):
```

To skip the prompt: pass the artifact path directly as input.

### Fix Order

Issues are fixed in priority order, with validation after each batch:

```
Critical → [validate] → High → [validate] → Medium → [validate] → Suggestion
```

If a fix causes validation to fail: revert that fix, add to skip log, continue.

### Severity Filter

| Flag | Fixes |
|------|-------|
| `--severity critical` | Critical only |
| `--severity critical,high` | Critical + High |
| `--severity critical,high,medium` | All except suggestions |
| No flag | All (default) |

### Output

- Fix summary: `.prp-output/reviews/pr-{N}-fix-summary.md`
- PR comment with fixed/skipped counts per severity
- "Fix Outcome" section appended to the review artifact

### Usage

```bash
# Claude Code — fix all issues
/prp-core:review-fix 42

# Fix only critical and high
/prp-core:review-fix 42 --severity critical,high

# Fix from specific artifact (skip disambiguation)
/prp-core:review-fix .prp-output/reviews/pr-42-review-codex.md

# Codex
$prp-review-fix 42

# OpenCode/Gemini
/prp:review-fix 42

# Kimi/Generic
"Fix review issues for PR #42, critical and high only"
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

## Workflow: Ralph (Autonomous Implementation Loop)

**Purpose:** Execute an implementation plan iteratively until ALL validations pass. Unlike `/prp-implement` (one-shot), Ralph loops autonomously — fixing failures and retrying until complete.

**Claude Code only** — requires stop hook mechanism not available in other tools.

### Process

```
Validate Input → Initialize State → Loop:
  Read Plan → Implement Tasks → Run Validations →
  Update State File → (if fail: next iteration)
→ Generate Report → Generate pr-context → Archive → COMPLETE
```

### When to Use Ralph vs Implement

| | `/prp-implement` | `/prp-ralph` |
|---|---|---|
| Execution | One-shot | Loop until pass |
| On failure | STOP, report user | Auto-retry next iteration |
| Token cost | Low (~15-30K) | High (N × ~15K) |
| Best for | Clear, well-defined plans | Complex features, uncertain impl |

### Setup (auto-configured by install.sh)

`install.sh` automatically:
1. Copies `prp-ralph-stop.sh` to `.claude/hooks/`
2. Makes it executable (`chmod +x`)
3. Registers it in `.claude/settings.local.json`

Verify with:
```bash
cat .claude/settings.local.json | jq '.hooks.Stop'
ls -la .claude/hooks/prp-ralph-stop.sh
```

### Output

- Implementation report: `.prp-output/reports/{plan}-report.md`
- Review context: `.prp-output/reviews/pr-context-{branch}.md`
- Ralph archive: `.prp-output/ralph-archives/{date}-{plan}/`
- State file (during run): `.claude/prp-ralph.state.md`

### Usage

```bash
# Run with a plan file
/prp-core:prp-ralph .prp-output/plans/jwt-auth.plan.md

# Set max iterations
/prp-core:prp-ralph .prp-output/plans/jwt-auth.plan.md --max-iterations 10

# Monitor progress
cat .claude/prp-ralph.state.md

# Cancel loop
/prp-core:prp-ralph-cancel
```

---

## Workflow: Run All (End-to-End)

**Purpose:** Execute complete 7-step workflow from feature idea to reviewed PR.

### Process (7 Steps)

```
Parse Input → Create Branch → Plan → Implement (or Ralph) →
Commit → PR → Review/Fix Loop → Summary
```

### Options

```bash
# Full workflow (default: one-shot implement)
/prp-core-run-all Add JWT authentication

# Use existing plan
/prp-core-run-all --prp-path .prp-output/plans/jwt.plan.md

# Use ralph loop for implement step (resilient, slower)
/prp-core-run-all Add JWT authentication --ralph

# Ralph with custom max iterations
/prp-core-run-all Add JWT authentication --ralph --ralph-max-iter 10

# Resume from last failed step
/prp-core-run-all --resume

# Skip review
/prp-core-run-all Add JWT auth --skip-review

# No PR (just implement + commit)
/prp-core-run-all Add JWT auth --no-pr

# Override review-fix severity (default: critical,high)
/prp-core-run-all Add JWT auth --fix-severity critical,high,medium
```

### Supported Flags

| Flag | Description |
|------|-------------|
| `--prp-path <path>` | Use existing plan, skip plan step. Validates file exists. |
| `--ralph` | Use ralph loop instead of one-shot implement |
| `--ralph-max-iter N` | Set ralph max iterations (default: 5) |
| `--resume` | Resume from last failed step using saved state |
| `--skip-review` | Skip review step |
| `--no-pr` | Skip PR and review steps |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high`) |

### State Management

run-all creates a state file at `.claude/prp-run-all.state.md` to track progress:
- Created at workflow start (Step 0.5)
- Updated after each step completion
- Supports `--resume` to continue from last failed step
- Automatically cleaned up on successful completion
- Lock file prevents concurrent execution (`.claude/prp-run-all.lock`)

### Review-Fix Loop (Step 6)

After PR creation, the review step runs a fix loop:
1. Run `/prp:review` on the PR
2. If critical/high issues found and cycle <= 2: run `/prp:review-fix` with `--severity` filter
3. Re-verify with another `/prp:review` to confirm fixes and catch regressions
4. Max 2 cycles — if still critical after 2 rounds, report remaining issues for manual fix

### Context Handoff

Implement step generates `pr-context-{branch}.md` which is passed explicitly to review via `--context` flag, saving ~60K tokens by skipping redundant file gathering.

### --ralph Flag

When `--ralph` is used, implement step is replaced with `/prp-ralph`:
- Hook pre-check runs first — stops immediately if hook not registered
- Token warning displayed (ralph uses 3-10× more tokens than default)
- Ralph loops until COMPLETE, then workflow continues to commit → PR → review

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
| Review Fix | `reviews/pr-42-fix-summary.md` (อ่านจาก review artifact) |
| Feature Review | `reviews/feature-review-auth-20260210.md` (ใช้ date) |

### หา Artifact ล่าสุด

```bash
# หา artifact ล่าสุดโดย sort by modified time
ls -t .prp-output/plans/*.plan.md | head -1
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

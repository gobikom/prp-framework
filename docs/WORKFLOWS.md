# PRP Framework Workflows

**Prompt-Run-Perfect** — Detailed documentation for all workflows in PRP Framework.

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
Detect Input → Detect Toolchain (Phase 0.5) → Parse Feature → Explore Codebase →
Research → Architect → Design UX → Generate Plan
```

### Key Features

- **CODEBASE FIRST:** Discover existing patterns before external research
- **Actual Code Snippets:** MIRROR patterns with file:line references
- **Toolchain Detection:** Auto-detects package manager from lock files, pre-fills validation commands with no `{runner}` placeholders
- **Integration Points:** Maps new code → existing code hook locations with file:line
- **Insert At Hints:** Files to Change table includes insertion location hints for UPDATE operations
- **Confidence Score:** 5-dimension quality score (Patterns + Gotchas + Integration + Validation + Testing = max 10)
- **Plan Lifecycle Frontmatter:** `status: pending | in-progress | complete | failed` tracked through implement
- **6-Level Validation:** Static → Unit → Full → Database → Browser → Manual (pre-filled with real commands)
- **PRD Integration:** Can parse PRD phases and track status
- **Design Doc Integration:** Checks `.prp-output/designs/` and incorporates if found
- **Conditional Technical Design:** API Contracts, DB Schema, Sequence Diagrams, NFRs, Migration & Rollback (triggered by complexity assessment)
- **Expanded Testing Strategy:** Unit tests, Integration tests (conditional), Test data requirements, Performance benchmarks (conditional), Edge cases
- **Fast-track Mode:** `--fast` flag skips Research, Technical Design, and Design UX for simple changes
- **Complexity Validation:** Pre-save check warns if declared complexity mismatches actual task count

### Complexity Triggers

| Complexity | Technical Design | Testing Strategy |
|------------|-----------------|------------------|
| LOW | Skip | Unit tests + edge cases only |
| MEDIUM | Include if API/DB changes | + Integration tests |
| HIGH | Include all sub-sections | + Performance benchmarks |

### Output

Plan file: `.prp-output/plans/feature-name-{TIMESTAMP}.plan.md`

Contains:
- Plan lifecycle frontmatter (`status`, `runner`, `mode`)
- User story and problem statement
- Metadata table with detected runner and validation commands
- UX before/after diagrams (skipped in fast-track)
- Mandatory reading list (P0/P1/P2 files) (skipped in fast-track)
- Patterns to mirror (with actual code) (skipped in fast-track)
- Files to Change with Insert At hints
- Integration Points (new code → existing code hook locations)
- Step-by-step tasks
- Technical Design (conditional — API contracts, DB schema, sequence diagrams, NFRs, migration)
- Testing Strategy (unit, integration, test data, performance benchmarks, edge cases)
- Validation commands (pre-filled, no placeholders)
- Confidence Score (5×2=10)
- Acceptance criteria

### Usage

```bash
# From feature description
/prp-plan Add JWT authentication

# From PRD
/prp-plan .prp-output/prds/jwt-prd.md

# Fast-track for simple changes
/prp-plan "simple bug fix" --fast
```

---

## Workflow: Implement (Execute Plan)

**Purpose:** Execute implementation plan with rigorous validation loops.

### Process

```
Detect Environment → Load Plan → Prepare Git → Execute Tasks (TDD) →
Full Validation (+ Coverage + Security + Performance) → Report →
Generate Review Context → PRD Update → Archive Plan
```

### TDD Approach (Phase 3)

For each task in the plan:
1. **Read Context** — MIRROR reference, imports, Testing Strategy
2. **Write Test First (RED)** — create tests for new functions/modules (skip for config/wiring/schema tasks)
3. **Implement (GREEN)** — follow MIRROR pattern, run tests until passing
4. **Validate Immediately** — type-check after every file change
5. **Track Progress** — `Task 1: Test ✅ (3 cases) — Impl ✅`

### Validation Levels

1. **Static Analysis:** Type-check + Lint (zero errors)
2. **Unit Tests:** Write/update tests, must pass
3. **Coverage Check:** 90% on new/changed code (auto-detect tool, graceful skip if unavailable)
4. **Build:** Must succeed
5. **Integration Tests (conditional):** If plan specifies or project has `test:integration`
6. **Integration:** Server/endpoint testing (if applicable)
7. **Edge Cases:** From plan specification
8. **Security Checks (conditional — basic SAST):** Hardcoded secrets, SQL injection, unsafe eval/exec
9. **Performance Regression (conditional):** If plan has benchmarks + project has tooling, flag >20% regression
10. **API Contract Validation (conditional):** If OpenAPI/GraphQL schema exists + API surface changed

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

### Phase 0: Context Detection

Before gathering PR files, review checks for pre-generated context:
1. Check `--context` flag (passed by run-all workflow)
2. Check `.prp-output/reviews/pr-context-{BRANCH}.md` (generated by implement/ralph)
3. If found: load pre-gathered context, skip redundant file discovery (~60K tokens saved)
4. If not found: proceed with normal PR diff fetch

### Context Optimization

When run via `run-all`, review receives a pre-generated context file via `--context` flag. This skips redundant file gathering and saves ~60K tokens. If context file is not available, review proceeds normally.

### Validation Phase

Before forming a recommendation, review runs automated validation:

| Check | Command |
|-------|---------|
| Type check | `npm run type-check` / `bun run type-check` / `npx tsc --noEmit` |
| Lint | `npm run lint` / `bun run lint` |
| Tests | `npm test` / `bun test` |
| Build | `npm run build` / `bun run build` |

Results (pass/fail, error/warning counts) are included in the review report and factor into the APPROVE/REQUEST_CHANGES decision.

### Methodology

**Claude Code:** 7 specialized agents (parallel/sequential)
**Other Tools:** 7 sequential passes (single agent)

### Output

- Review report: `.prp-output/reviews/pr-{N}-{tool}-review.md` (with YAML frontmatter: pr, title, author, reviewed, verdict)
- Posted to GitHub as comment
- Implementation report updated with "Review Outcome" section
- PRD phase status updated if applicable (READY TO MERGE → `reviewed`, NEEDS FIXES → note added, CRITICAL ISSUES → blocked note)

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

### Key Features

- **Phase 0 Toolchain Detection:** Reads package manager from lock files and prefers validation commands from a matching completed plan (JS/TS, Python, Rust, Go all supported)
- **Agents-Review Parsing:** Handles both standard review format and agents-review format; maps "Important" → High for Codex/Gemini parenthetical labels
- **Validation GATE:** Full suite (type-check + lint + test + build) must pass before commit; failing fixes are reverted and skipped automatically
- **Safe Git Staging:** Uses `git diff --name-only` + `git ls-files --others` instead of `git add -A` to avoid staging unintended files

### Process

```
Detect Toolchain → Load Artifact → Resolve Artifact → Checkout PR Branch →
Triage → Fix (per severity batch) → Validate (GATE) → Commit → Push → Comment on PR
```

### Artifact Resolution

When multiple tools have reviewed the same PR, the command lists all artifacts and prompts the user to select:

```
Multiple reviews found for PR #123:
  [1] pr-123-agents-review.md   (prp-review-agents)  2026-02-27 14:30  ← most recent
  [2] pr-123-review.md          (claude-code)         2026-02-27 10:15
  [3] pr-123-review-codex.md    (codex)               2026-02-27 08:00
  [4] pr-123-review-gemini.md   (gemini)              2026-02-26 09:00

Which review to fix? (Enter for [1]):
```

To skip the prompt: pass the artifact path directly as input. PR number is extracted automatically from the filename (`pr-{NUMBER}-*.md`).

### Triage Phase

Before making any changes, a fix plan is printed:
- Issue counts per severity (Critical: N, High: N, Medium: N, Suggestion: N)
- Each issue with file path and description
- Grouped by file for efficient fixing
- Issues that will be skipped (filtered out by `--severity`)

This gives visibility into what will change before any edits happen.

### Fix Order

Issues are fixed in priority order, with quick validation (type-check + lint) after each batch and a full suite once at the end:

```
Critical → [quick check] → High → [quick check] → Medium → [quick check] → Suggestion → [full suite]
```

Quick check = type-check + lint only (fast feedback). Full suite = type-check + lint + tests + build (runs once after all batches to save tokens). If a fix causes validation to fail: revert that fix, add to skip log, continue.

### Severity Filter

| Flag | Fixes |
|------|-------|
| `--severity critical` | Critical only |
| `--severity critical,high` | Critical + High |
| `--severity critical,high,medium` | All except suggestions |
| No flag | All (default) |

### Output

- Fix summary: `.prp-output/reviews/pr-{N}-fix-summary-{TIMESTAMP}.md`
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
Pre-commit Quality Check (advisory) → Check Status → Stage Files →
Generate Message → Commit → Report
```

### Pre-commit Quality Check (Phase 0)

Advisory scan that warns but does NOT block commit:
- **Debug artifacts:** TODO/FIXME, console.log/debugger/pdb.set_trace
- **Type safety:** `any` type usage in TypeScript files (skip test/d.ts)
- **Quick validation:** Type-check + tests (skip in run-all context)
- **Quality report:** Summary of findings

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

### Edge Cases

| Situation | Action |
|-----------|--------|
| Nothing to commit | STOP — working directory clean |
| Only untracked files | `git add` relevant ones, commit |
| Merge conflict markers | STOP — resolve conflicts first |
| Pre-commit hook fails | Show error, suggest fix, retry |
| Binary files staged | Include in commit, note in message |
| Mixed staged/unstaged | Only commit what matches target |

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

**Note:** The stop hook (automatic loop termination) requires Claude Code. On other tools, run the canonical `prompts/ralph.md` prompt manually and terminate when validations pass.

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
- State file (during run): `.prp-output/state/ralph.state.md`

### Usage

```bash
# Run with a plan file
/prp-core:ralph .prp-output/plans/jwt-auth.plan.md

# Set max iterations
/prp-core:ralph .prp-output/plans/jwt-auth.plan.md --max-iterations 10

# Monitor progress
cat .prp-output/state/ralph.state.md

# Cancel loop
/prp-core:ralph-cancel
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
# Issue-driven: fetch issue → smart plan → implement → PR → review loop → merge
/prp-run-all --issue 87 --merge

# Fully autonomous issue lifecycle
/prp-run-all --issue 42 --merge --no-interact

# Custom review-fix rounds (default: 5)
/prp-run-all --issue 55 --max-review-rounds 3 --merge

# Full workflow (default: one-shot implement)
/prp-run-all Add JWT authentication

# Use existing plan
/prp-run-all --prp-path .prp-output/plans/jwt.plan.md

# Use ralph loop for implement step (resilient, slower)
/prp-run-all Add JWT authentication --ralph

# Ralph with custom max iterations
/prp-run-all Add JWT authentication --ralph --ralph-max-iter 10

# Resume from last failed step
/prp-run-all --resume

# Skip review
/prp-run-all Add JWT auth --skip-review

# No PR (just implement + commit)
/prp-run-all Add JWT auth --no-pr

# Override review-fix severity (default: critical,high,medium,suggestion)
/prp-run-all Add JWT auth --fix-severity critical,high

# Preview all steps and token estimate without executing
/prp-run-all Add JWT auth --dry-run
```

### Supported Flags

| Flag | Description |
|------|-------------|
| `--prp-path <path>` | Use existing plan, skip plan step. Validates file exists. |
| `--skip-plan` | Alias for `--prp-path` — prompts to select from available plans in `.prp-output/plans/` |
| `--issue <N>` | Fetch GitHub issue #N context. Smart plan detection (small: skip, medium: fast, large: full plan) |
| `--merge` | Auto squash-merge PR after review passes (0 issues). Runs cleanup + issue close |
| `--max-review-rounds <N>` | Max review-fix cycles (default: 5). Loop targets 0 issues matching `FIX_SEVERITY` |
| `--fast` | Use fast-track plan mode (lighter codebase analysis, good for simple features) |
| `--ralph` | Use ralph loop instead of one-shot implement |
| `--ralph-max-iter N` | Set ralph max iterations (default: 10) |
| `--resume` | Resume from last failed step using saved state |
| `--skip-plan` | Select from available plans instead of creating new one |
| `--skip-review` | Skip review step |
| `--no-pr` | Skip PR and review steps |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`) |
| `--no-interact` | Never ask user questions — use best judgment for ambiguous requirements, pick defaults |
| `--dry-run` | Preview all steps and estimated token cost without executing anything |

### State Management

run-all creates a state file at `.prp-output/state/run-all.state.md` to track progress:
- Created at workflow start (Step 0.5)
- Updated after each step completion
- Supports `--resume` to continue from last failed step
- Automatically cleaned up on successful completion
- Lock file prevents concurrent execution (`.prp-output/state/run-all.lock`)

### Review-Fix Loop (Step 6)

After PR creation, the review step runs a fix loop targeting 0 issues:
1. Run `/prp:review-agents` on the PR (default; use `--review-single-agent` for single-agent review)
2. If any issues matching `FIX_SEVERITY` found (default: all severities) and cycle <= MAX_CYCLES (default 5): run `/prp:review-fix` with `--severity {FIX_SEVERITY}`
3. Re-verify with `/prp:review` (always single-agent — use full review when prior fixes skipped issues)
4. Loop until 0 issues or MAX_CYCLES reached. If `--merge` and 0 issues → proceed to merge + cleanup
5. If review-fix skips all remaining issues for 2 consecutive rounds, stop early, create an escalation issue or local escalation artifact, and block merge

### Context Handoff

Implement step generates `pr-context-{branch}.md` which is passed explicitly to review via `--context` flag, saving ~60K tokens by skipping redundant file gathering.

### --ralph Flag

When `--ralph` is used, implement step is replaced with `/prp-ralph`:
- Hook pre-check runs first — stops immediately if hook not registered
- Token warning displayed (ralph uses 3-10× more tokens than default)
- Ralph loops until COMPLETE, then workflow continues to commit → PR → review

---

## Workflow: Debug (Root Cause Analysis)

**Purpose:** Find the actual root cause of an issue using the 5 Whys methodology — not symptoms, not intermediate failures, but the origin.

**When to Use:**

- Error messages, stack traces, or vague bug reports
- "It worked before" regressions
- Intermittent or hard-to-reproduce issues

### Process

```
CLASSIFY (Parse Input, Determine Mode) → HYPOTHESIZE (2-4 Theories) →
INVESTIGATE (5 Whys with Evidence) → VALIDATE (Causation/Necessity/Sufficiency) →
REPORT → OUTPUT
```

### Key Features

- **Two Modes:** `--quick` for surface scan (2-3 Whys, ~5 min) or deep analysis (full 5 Whys with git history)
- **Hypothesis-Driven:** Generates 2-4 ranked hypotheses before investigating; pivots if evidence refutes leading theory
- **Strict Evidence Standards:** Every "because" must have a `file:line` reference, command output, or executed test — no "likely" or "probably" allowed
- **Three Validation Tests:** Causation (does root cause lead to symptom?), Necessity (would symptom still occur without it?), Sufficiency (is it alone enough?)
- **Git History Required (Deep Mode):** Documents when/who/why the problematic code was introduced, including commit hash and blame
- **Fix Specification:** Report includes current vs required code, files to modify, and verification steps

### Output

- RCA report: `.prp-output/debug/rca-{issue-slug}-{TIMESTAMP}.md`
- Contains: evidence chain, git history, fix specification with implementation guidance, verification steps

### Usage

```bash
# Claude Code
/prp-core:debug "Login fails with 401 after token refresh"

# Quick mode (surface scan)
/prp-core:debug "TypeError in dashboard" --quick

# Codex
$prp-debug "Login fails with 401 after token refresh"

# OpenCode/Gemini
/prp:debug "Login fails with 401 after token refresh"

# Kimi/Generic
"Debug root cause: Login fails with 401 after token refresh"
```

---

## Workflow: Issue Investigate

**Purpose:** Analyze a GitHub issue (or free-form description) and produce a comprehensive implementation plan artifact that can be executed by the issue-fix command.

**When to Use:**

- GitHub issue needs analysis before implementation
- Want a structured investigation posted as a GitHub comment
- Need to assess severity, complexity, and confidence before committing to a fix

### Process

```
PARSE (Determine Input Type, Fetch GH Issue) → EXPLORE (Codebase Intelligence) →
ANALYZE (Root Cause / Change Rationale) → GENERATE (Create Artifact) →
COMMIT (Save Artifact) → POST (GitHub Comment) → REPORT
```

### Key Features

- **Input Flexibility:** Accepts issue number (`123`, `#123`), GitHub URL, or free-form description
- **Issue Classification:** Automatically classifies as BUG, ENHANCEMENT, REFACTOR, CHORE, or DOCUMENTATION
- **Assessment with Reasoning:** Severity/Priority, Complexity, and Confidence each include a one-sentence justification based on investigation findings
- **Codebase-First Exploration:** Discovers relevant files, integration points, similar patterns, and existing test patterns with actual code snippets
- **5 Whys for Bugs:** Full root cause analysis with evidence chain for BUG-type issues
- **GitHub Integration:** Posts formatted investigation summary as a comment on the issue (skipped for free-form input)
- **Artifact as Specification:** The generated artifact is self-contained — an implementing agent can work from it without asking questions

### Output

- Investigation artifact: `.prp-output/issues/issue-{number}-{TIMESTAMP}.md` (or `investigation-{TIMESTAMP}.md` for free-form)
- GitHub comment posted to issue (if GH issue input)
- Contains: assessment table, problem statement, evidence chain, affected files with line numbers, implementation steps, patterns to follow, edge cases, validation commands, scope boundaries

### Usage

```bash
# Claude Code — from issue number
/prp-core:issue-investigate 123

# From GitHub URL
/prp-core:issue-investigate https://github.com/org/repo/issues/123

# From free-form description (no GH posting)
/prp-core:issue-investigate "API returns 500 when user has no profile"

# Codex
$prp-issue-investigate 123

# OpenCode/Gemini
/prp:issue-investigate 123

# Kimi/Generic
"Investigate issue #123 and create an implementation plan"
```

---

## Workflow: Issue Fix

**Purpose:** Load an investigation artifact and execute the implementation plan — implement changes, validate, create a PR linked to the issue, and run a self-review.

**When to Use:**

- After running Issue Investigate to create an implementation plan
- When you have an existing `.prp-output/issues/issue-{number}-*.md` artifact ready to execute

### Process

```
LOAD (Find & Parse Artifact) → VALIDATE (Sanity Check vs Current Code) →
GIT-CHECK (Ensure Correct Branch) → IMPLEMENT (Execute Steps) →
VERIFY (Run Validation) → COMMIT (Safe Staging) →
PR (Create & Link to Issue) → REVIEW (Self Code Review) →
ARCHIVE (Move to Completed) → REPORT
```

### Key Features

- **Artifact-Driven:** Follows the investigation artifact step-by-step; deviations are documented, not silently applied
- **Drift Detection:** Compares artifact's "current code" snippets against actual codebase; warns if code has changed since investigation
- **Smart Git State:** Decision tree handles worktrees, main branch, feature branches, and dirty state — creates `fix/issue-{number}-{slug}` branch when needed
- **Safe Staging:** Uses `git diff --name-only` + `git ls-files --others` instead of `git add -A` to avoid staging unintended files
- **PR Linked to Issue:** Creates PR with `Fixes #{number}` to auto-close the issue on merge
- **Self-Review:** Posts an automated code review comment on the PR covering root cause alignment, code quality, test coverage, edge cases, and security
- **Artifact Archival:** Moves completed artifact to `.prp-output/issues/completed/` after PR creation

### Output

- Implementation on a new branch: `fix/issue-{number}-{slug}`
- Pull request linked to the issue with `Fixes #{number}`
- Self-review comment posted on the PR
- Archived artifact: `.prp-output/issues/completed/issue-{number}-{TIMESTAMP}.md`

### Usage

```bash
# Claude Code — from issue number (finds latest artifact)
/prp-core:issue-fix 123

# From specific artifact path
/prp-core:issue-fix .prp-output/issues/issue-123-20260210-1430.md

# Codex
$prp-issue-fix 123

# OpenCode/Gemini
/prp:issue-fix 123

# Kimi/Generic
"Fix issue #123 using the investigation artifact"
```

---

## Workflow: Feature Review

**Purpose:** Perform a comprehensive, senior-engineer-level review of a package or folder — covering code quality, product ideas, performance, and security.

**When to Use:**

- Evaluating overall health of a package or feature area
- Looking for product improvement opportunities and new feature ideas
- Auditing performance or security before a release
- Onboarding to an unfamiliar codebase area

### Process

```
PARSE (Validate Path, Determine Focus) → CONTEXT EXTRACTION (Token Optimization) →
ANALYZE (Deep Code Review per Focus) → PRIORITIZE (Impact × Effort) →
REPORT → OUTPUT
```

### Key Features

- **Focus Flag:** `--focus code|product|performance|security|all` narrows analysis to specific areas (default: `all`)
- **Token-Optimized Context Caching:** Extracts package structure, guidelines, and file inventory once into `.prp-output/reviews/feature-context-{package-name}.md`; re-runs within 1 hour skip extraction entirely (~40-50% token savings)
- **Selective File Reading:** Prioritizes files relevant to the focus area (e.g., `--focus security` reads auth handlers and input validation first)
- **Health Scorecard:** 1-10 scores for Code Quality, Product Potential, Performance, and Security
- **Prioritized Action Items:** Findings sorted by impact vs effort (Critical/High/Medium/Low) with estimated effort (Quick Win / Small / Medium / Large)
- **Suggested Roadmap:** Three-phase improvement plan (Foundation, Enhancement, Innovation)
- **Multi-Agent Support:** Context file is shared by both single-agent and multi-agent feature review workflows

### Phases

1. **PARSE:** Validate input path, determine focus areas, check for existing context
2. **CONTEXT EXTRACTION:** Gather project rules, package structure, manifest, key files — write context file
3. **ANALYZE:** Deep review across focus areas (architecture, patterns, type safety, testing, product ideas, performance, security)
4. **PRIORITIZE:** Categorize findings by impact, estimate effort, calculate ROI
5. **REPORT:** Generate comprehensive markdown report with scores, findings, and roadmap
6. **OUTPUT:** Present summary with scores, action item counts, and artifact paths

### Output

- Review report: `.prp-output/reviews/feature-review-{package-name}-{date}.md`
- Context file: `.prp-output/reviews/feature-context-{package-name}.md`
- Contains: executive summary, health scorecard, code quality analysis, product/feature ideas, performance recommendations, security findings, prioritized action items, suggested roadmap

### Usage

```bash
# Claude Code — review entire package
/prp-core:feature-review packages/web

# Focus on security only
/prp-core:feature-review src/features/auth --focus security

# Focus on product ideas
/prp-core:feature-review packages/dashboard --focus product

# All areas (default)
/prp-core:feature-review src/core --focus all

# Codex
$prp-feature-review packages/web --focus code

# OpenCode/Gemini
/prp:feature-review packages/web --focus performance

# Kimi/Generic
"Review the packages/web folder focusing on security"
```

---

## Workflow: Ralph Cancel

**Purpose:** Cancel an active Ralph autonomous implementation loop, preserving all work done so far.

**When to Use:**

- Ralph loop is running and you want to stop it immediately
- You want to take over implementation manually
- The loop is heading in the wrong direction

### Process

```
Check State File → If NOT_FOUND: Report No Active Loop →
If ACTIVE: Read Iteration/Plan → Remove State File → Report
```

### Key Features

- **Non-Destructive:** Only removes the state file (`.prp-output/state/ralph.state.md`) — no code changes are reverted
- **Work Preserved:** All modified files, git commits, and in-progress changes remain intact
- **Iteration Reporting:** Shows which iteration Ralph was on and which plan was being executed
- **Resume Path:** After cancelling, you can restart with the same plan or switch to manual implementation

### Output

- State file removed: `.prp-output/state/ralph.state.md`
- Report showing iteration number and plan path
- All code changes preserved (check `git status`)

### Usage

```bash
# Claude Code
/prp-core:ralph-cancel

# Codex
$prp-ralph-cancel

# OpenCode/Gemini
/prp:ralph-cancel

# Kimi/Generic
"Cancel the active Ralph loop"
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
| Review Fix | `reviews/pr-42-fix-summary-20260210-1430.md` (timestamp prevents overwrite) |
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

> See [SCRIPTS-REFERENCE.md](SCRIPTS-REFERENCE.md) for full documentation on all scripts.

---

## Workflow: Rollback

**Purpose:** Safely undo implementation changes on the current branch, with a stash backup so nothing is permanently lost.

### Options

```bash
# Interactive — shows changes and asks which mode
/prp-core:rollback

# Unstage only (keep files in working directory, no data loss)
/prp-core:rollback --soft

# Full revert to origin/main (creates stash backup first)
/prp-core:rollback --hard

# Restore from the most recent rollback stash
/prp-core:rollback --restore
```

### Modes

| Mode | What it does | Data loss? |
|------|-------------|-----------|
| `--soft` | Unstages commits back to origin/main (files stay in working dir) | None |
| `--hard` | Resets branch to origin/main HEAD | None — stash backup created first |
| `--restore` | Pops the most recent `prp-rollback-*` stash | None |

### Safety Guarantees

- `--hard` always creates a stash backup **before** running `git reset --hard`
- Stash is labeled `prp-rollback-{YYYYMMDD-HHMM}-{branch}` for easy identification
- `--restore` recovers from any `--hard` rollback within the same session
- Never deletes branches — only suggests cleanup

### Output

```
✅ Rollback complete

Branch: feature/jwt-auth
Reset to: origin/main (abc1234)

Stash backup created: prp-rollback-20260301-1430-feature/jwt-auth
To restore: /prp-core:prp-rollback --restore
```

---

## Workflow: Cleanup (Post-Merge Branch Cleanup)

**Purpose:** Clean up local and remote branches after a PR has been merged. Verifies merge status before deleting anything.

### Process

```
Parse Flags → Determine Target Branches → Verify PR Merged →
Archive Artifacts → Delete Local Branch → Delete Remote Branch →
Prune Refs → Summary
```

### Options

```bash
# Clean up current branch (must not be on it)
/prp-core:cleanup

# Clean up specific branch
/prp-core:cleanup feat/user-auth

# Clean all merged branches
/prp-core:cleanup --all

# Preview without deleting
/prp-core:cleanup --all --dry-run
```

### Flags

| Flag | Description |
|------|-------------|
| `--all` | Find and clean all local branches merged into main |
| `--dry-run` | Show what would be deleted without executing |

### Artifact Archiving

Before deleting branches, cleanup commits PR-related artifacts to main:

1. Switch to main and pull latest
2. Find artifacts: `pr-{NUMBER}-*.md`, `pr-context-{BRANCH}.md`, reports, completed plans
3. Stage and commit: `git commit -m "chore: archive artifacts for PR #{NUMBER} ({BRANCH})"`
4. `--dry-run`: lists artifacts that would be committed without committing

### Safety Guarantees

- Always verifies PR is merged via `gh pr list` before any deletion
- Never includes main/master in cleanup targets
- `--dry-run` previews without executing any destructive operations
- Auto-switches to main if currently on the target branch
- Handles already-deleted remote branches gracefully

### Output

```
## Cleanup Summary

| Branch | PR | Status | Artifacts | Local | Remote |
|--------|-----|--------|-----------|-------|--------|
| feat/auth | #42 | Merged | Committed | Deleted | Deleted |
| fix/typo | #43 | Open | Skipped | Skipped | Skipped |

Cleaned: 1 branch(es)
Skipped: 1 branch(es)
```

---

## Common Issues & Recovery

| Scenario | Symptom | Fix |
|----------|---------|-----|
| Detached HEAD | run-all can't create branch | `git checkout main` first |
| Shallow clone | `git fetch` fails | `git fetch --unshallow origin` |
| gh CLI missing | PR/review commands fail | `brew install gh && gh auth login` |
| gh auth expired | 401 errors on GitHub API | `gh auth refresh` |
| Lock file stuck | "Another workflow is active" | Delete `.prp-output/state/run-all.lock` if stale (>2hrs) |
| State file corrupt | `--resume` fails | Delete `.prp-output/state/run-all.state.md`, start fresh |
| No coverage tool | Coverage check skips | Expected — install jest/vitest/pytest for enforcement |
| PR already exists | PR step fails | Use existing PR URL, skip to review |
| `.prp` divergent branches | `git pull` fails with "Need to specify how to reconcile" | `cd .prp && git fetch origin && git reset --hard origin/main && cd ..` — then run `git config pull.rebase true` inside `.prp` to prevent recurrence |

---

## Best Practices

1. **Start with PRD** for non-trivial features
2. **Use Design Doc** for complex architecture
3. **Trust the Plan** - comprehensive exploration
4. **Validate Early** - type-check after every file change
5. **Review Often** - catch issues before merge
6. **Natural Commits** - let AI suggest message
7. **Cleanup Regularly** - run cleanup script weekly to remove old artifacts

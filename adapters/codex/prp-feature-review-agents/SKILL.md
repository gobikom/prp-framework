---
name: prp-feature-review-agents
description: Multi-agent feature review — spawns parallel specialized agents for deep package analysis.
metadata:
  short-description: Multi-agent feature review
---


## Agent Mode Detection

If your input context contains `[WORKSPACE CONTEXT]` (injected by a multi-agents framework),
you are running as a sub-agent. Apply these optimizations:

- **Skip CLAUDE.md reading** — already loaded by parent session.
- **Skip directory discovery** — the parent agent already explored the codebase.
- **Skip context extraction** if a `feature-context-*.md` file path is provided in context files.

All agent dispatches and result aggregation run unchanged —
these are where quality comes from.

---

# Feature Review Agents — Parallel Multi-Agent Feature & Code Review

**Input**: $ARGUMENTS

## Mission

Perform a comprehensive, senior-engineer-level review of a package or folder by **spawning specialized Agent subprocesses in parallel**. Each agent runs in its own isolated context window with fresh memory, enabling deep file exploration.

**This command differs from `$prp-feature-review`** (single-session sequential analysis) by spawning actual Agent subprocesses via the Agent tool. Each agent gets:
- **Fresh context window** — no context pollution from other analysis areas
- **Deep exploration** — agents can read all files in the package, not just prioritized ones
- **Specialized focus** — each agent type has purpose-built instructions

**Golden Rule**: Be constructive, creative, and actionable. Think like a product-minded engineer who cares about both code quality AND user value.

---

## Phase 1: PARSE — Understand Input

### 1.1 Parse Arguments

| Input | Interpretation |
|-------|----------------|
| `packages/web` | Review entire package |
| `src/features/auth` | Review specific feature folder |
| `--focus code` | Focus on code quality agents only |
| `--focus product` | Focus on product-ideas-agent only |
| `--focus performance` | Focus on performance-analyzer only |
| `--focus security` | Focus on security-reviewer only |
| `--focus all` | All agents (default) |
| `--quick` | Core agents only (code, security) — skip product/perf/conditional |

### 1.2 Validate Path

```bash
ls -la {input-path} 2>/dev/null || echo "PATH_NOT_FOUND"
```

**If path doesn't exist**: STOP — "Path `{input-path}` not found. Verify the path and try again."

### 1.3 Check for Existing Context

```bash
ls .prp-output/reviews/feature-context-{package-name}.md 2>/dev/null
```

**If context exists and is recent (< 1 hour)**: Skip to Phase 3 (Token Optimization).

**PHASE_1_CHECKPOINT:**
- [ ] Input path validated
- [ ] Focus areas determined
- [ ] Existing context checked

---

## Phase 2: CONTEXT EXTRACTION (Token Optimization)

**Purpose**: Extract and cache context ONCE to avoid redundant file reads across agents. Saves 60-70% tokens vs each agent exploring independently.

**Skip if** Phase 1 found existing recent context.

### 2.1 Create Context Directory

```bash
mkdir -p .prp-output/reviews
```

### 2.2 Gather Project Context

Read and extract the following in a single pass:

- **CLAUDE.md** — project rules and conventions
- **Package structure** — `tree {input-path} -L 3 -I node_modules`
- **Package manifest** — `package.json` or equivalent
- **Key files list** — categorized by type (entry points, core logic, UI, utils, tests)
- **README** — package documentation

### 2.3 Write Context File

**Path**: `.prp-output/reviews/feature-context-{package-name}.md`

```markdown
---
package: "{PACKAGE_PATH}"
extracted: {ISO_TIMESTAMP}
files_count: {N}
---

# Feature Context: {PACKAGE_NAME}

## Project Guidelines (from CLAUDE.md)
{relevant sections - coding standards, patterns, conventions}

## Package Structure
{tree output}

## Package Manifest
{package.json content}

## Key Files by Category

### Entry Points
- {list with brief description}

### Core Logic
- {list with brief description}

### UI Components (if applicable)
- {list with brief description}

## File Inventory
{complete list of files}

## Initial Observations
- {key patterns noticed}
- {technologies used}
- {architecture style}
```

**After writing, verify the file was created:**
```bash
test -f ".prp-output/reviews/feature-context-{package-name}.md" || echo "FATAL: Context file write failed"
```

If verification fails, STOP — do not spawn agents without a context file.

**PHASE_2_CHECKPOINT:**
- [ ] Context file created and verified
- [ ] Package structure mapped
- [ ] Key files categorized

---

## Phase 3: Spawn Parallel Agent Subprocesses

**CRITICAL**: You MUST use the `Agent` tool to spawn these as separate subprocesses. Each agent runs in its own context window with fresh memory. Do NOT attempt to run these as sequential analysis passes in this session — that defeats the purpose of this command. If you want single-session sequential analysis, use `$prp-feature-review` instead.

### 3.1 Prepare Agent Context

```
CONTEXT_PATH = ".prp-output/reviews/feature-context-{package-name}.md"
PACKAGE_PATH = {input-path}
FOCUS = {from Phase 1 — determines which agents to spawn}
```

### 3.2 Core Agents (Always — Spawn in Parallel)

Spawn these agents simultaneously in a **SINGLE message with multiple Agent tool calls**:

**Agent 1 — Code Quality**:
```
Agent(
  subagent_type="code-reviewer",
  description="Review {PACKAGE_PATH} code quality",
  prompt="Review the package at {PACKAGE_PATH} for code quality, patterns, and architecture.

Read the context file at: {CONTEXT_PATH}
Then read the actual source files for deep analysis.

Evaluate:
- Architecture & design: separation of concerns, abstractions, module boundaries
- Code patterns: naming conventions, DRY, error handling, logging
- Type safety: explicit types, generics, null safety
- Testing: coverage, edge cases, quality of assertions
- Documentation: function docs, complex logic explanations

Report findings as structured markdown:
## Strengths
{What's done well}

## Issues
| Priority | Issue | File:Line | Suggestion |
|----------|-------|-----------|------------|

## Pattern Recommendations
{Suggested improvements}

Use priorities: Critical, High, Medium, Low
Score: Code Quality {N}/10"
)
```

**Agent 2 — Security**:
```
Agent(
  subagent_type="security-reviewer",
  description="Review {PACKAGE_PATH} security",
  prompt="Review the package at {PACKAGE_PATH} for security vulnerabilities.

Read the context file at: {CONTEXT_PATH}
Then read actual source files — especially auth, API handlers, input validation, config.

Check:
- Input validation: SQL/NoSQL injection, XSS, file upload restrictions
- Auth & authz: route protection, token handling, session management, RBAC
- Data protection: encryption, secrets in env vars, PII handling, logging exposure
- API security: rate limiting, CORS, API key protection, request validation

Report ONLY vulnerabilities with clear attack vectors — not theoretical issues.

Report findings as structured markdown:
## Critical Issues
{Must fix immediately}

## High Priority
{Should fix soon}

## Recommendations
{Best practices to implement}

Score: Security {N}/10"
)
```

**Agent 3 — Product Ideas** (skip if `--focus code` or `--focus security` or `--quick`):
```
Agent(
  subagent_type="product-ideas-agent",
  description="Brainstorm features for {PACKAGE_PATH}",
  prompt="Review the package at {PACKAGE_PATH} and brainstorm product improvements.

Read the context file at: {CONTEXT_PATH}
Then read the actual source files — especially UI components, user-facing code, API endpoints.

Think like a product manager:
- What does this package do? Who are the users?
- What's missing that users would love?
- What friction could be reduced?
- What would make this 10x better?

Brainstorm categories:
- Quick Wins (< 1 day effort, high impact)
- Strategic Features (1-2 weeks, significant improvement)
- Innovation Ideas (creative differentiators)
- UX Improvements (delight users)

Report findings as structured markdown:
## Quick Wins
| Idea | Impact | Effort |
|------|--------|--------|

## Strategic Features
| Idea | Impact | Effort | Description |
|------|--------|--------|-------------|

## Innovation Ideas
{Creative suggestions}

## User Journey Improvements
{Pain points and fixes}

Score: Product Potential {N}/10"
)
```

**Agent 4 — Performance** (skip if `--focus code` or `--focus product` or `--quick`):
```
Agent(
  subagent_type="performance-analyzer",
  description="Analyze {PACKAGE_PATH} performance",
  prompt="Analyze the package at {PACKAGE_PATH} for performance issues and optimization opportunities.

Read the context file at: {CONTEXT_PATH}
Then read actual source files — especially hot paths, database queries, API calls, render functions.

Check:
- N+1 query patterns, unnecessary async/await
- Memory leaks (uncleared listeners, growing arrays/caches)
- Heavy computations in render/hot paths, large bundle imports
- Caching opportunities, lazy loading, pagination
- API call batching, database query optimization

Report only issues with measurable impact. Include quantified estimates.

Report findings as structured markdown:
## Immediate Optimizations
| Issue | File:Line | Impact | Fix |
|-------|-----------|--------|-----|

## Architecture Improvements
{Larger refactoring opportunities}

## Monitoring Suggestions
{What to measure and track}

Score: Performance {N}/10"
)
```

### 3.3 Conditional Agents (Based on Package Content)

Spawn additional agents based on what the context file reveals:

**If UI/frontend files detected** (`.tsx`, `.jsx`, `.vue`, `.svelte`, `.css`):
```
Agent(
  subagent_type="accessibility-reviewer",
  description="Review {PACKAGE_PATH} accessibility",
  prompt="Review UI code in {PACKAGE_PATH} for WCAG 2.1 compliance.

Read the context file at: {CONTEXT_PATH}
Then read UI component files.

Check: keyboard navigation, screen reader support, color contrast (4.5:1 text, 3:1 large), ARIA usage, form labels, focus management.

Report findings as:
## Findings
| Priority | Issue | File:Line | Affected Users | Fix |

Score: Accessibility {N}/10"
)
```

**If package.json or dependency files exist**:
```
Agent(
  subagent_type="dependency-analyzer",
  description="Analyze {PACKAGE_PATH} dependencies",
  prompt="Analyze dependencies in {PACKAGE_PATH} for security and health.

Read the context file at: {CONTEXT_PATH}
Read package.json, lock files, requirements.txt, etc.

Check: known CVEs, outdated packages with security patches, abandoned dependencies, license compliance, bundle size impact.

Report findings as:
## Findings
| Priority | Package | Issue | Remediation |

Score: Dependency Health {N}/10"
)
```

**If error handling patterns detected** (try/catch, .catch, error handlers):
```
Agent(
  subagent_type="silent-failure-hunter",
  description="Hunt silent failures in {PACKAGE_PATH}",
  prompt="Hunt for silent failures in {PACKAGE_PATH}.

Read the context file at: {CONTEXT_PATH}
Then read actual source files — trace every error path.

Check: empty catch blocks, catch without logging/re-throw, generic catch(e), async without .catch, scripts without set -e.

Report findings as:
## Findings
| Priority | Issue | File:Line | Error Path | Fix |"
)
```

**If logging/metrics/tracing patterns detected**:
```
Agent(
  subagent_type="observability-reviewer",
  description="Review {PACKAGE_PATH} observability",
  prompt="Review {PACKAGE_PATH} for logging, metrics, tracing, and error tracking.

Read the context file at: {CONTEXT_PATH}
Then read actual source files.

Check: structured logging, meaningful log levels, metrics for key operations, distributed tracing, error tracking integration, health checks, alert-worthy conditions.

Report findings as:
## Findings
| Priority | Issue | File:Line | Fix |

Score: Observability {N}/10"
)
```

### 3.4 Fallback: Sequential Analysis

**If the Agent tool is NOT available** (e.g., running in a tool that doesn't support subagent spawning):

Fall back to `$prp-feature-review` which performs all analysis sequentially in a single session. Display:

```
Agent tool not available — falling back to single-session sequential review.
For parallel agent review, use Claude Code or another tool that supports the Agent tool.
Running: $prp-feature-review {PACKAGE_PATH}
```

---

## Phase 4: Result Collection & Aggregation

After all agents complete, collect their outputs.

**For each agent result:**
1. Parse findings tables and scores
2. Map priorities to unified levels (Critical/High/Medium/Low)
3. Extract file:line references
4. Note the source agent for each finding

**If an agent returns no findings**: Note as clean.

**If an agent fails or times out**: Display WARNING and proceed with available results. If a core agent (code-reviewer, security-reviewer) fails, note it prominently in the report.

### 4.1 Deduplicate Across Agents

Two findings are duplicates when BOTH:
1. **Same file region**: Same file AND within +/-5 lines
2. **Same category**: Both about the same concern

**Merge strategy**: Keep most detailed description, use highest priority, list all contributing agents.

### 4.2 Calculate Scores

Aggregate per-area scores from agents:

| Area | Source Agent | Score |
|------|------------|-------|
| Code Quality | code-reviewer | {N}/10 |
| Product Potential | product-ideas-agent | {N}/10 |
| Performance | performance-analyzer | {N}/10 |
| Security | security-reviewer | {N}/10 |
| Accessibility | accessibility-reviewer | {N}/10 (if ran) |
| Dependencies | dependency-analyzer | {N}/10 (if ran) |
| Observability | observability-reviewer | {N}/10 (if ran) |

**Overall Health Score**: Average of all scores that ran.

### 4.3 Prioritize Action Items

Combine all findings into a unified prioritized list:
- **Critical**: Do now (security vulns, data loss risks)
- **High**: This sprint (significant improvements)
- **Medium**: Backlog (nice-to-have)
- **Low**: Future considerations

For each item estimate effort: Quick Win (< 1 day), Small (1-3 days), Medium (1-2 weeks), Large (> 2 weeks).

---

## Phase 5: REPORT — Generate Output

### 5.1 Save Report

**Path**: `.prp-output/reviews/feature-review-{package-name}-{date}.md`

```markdown
---
package: "{PACKAGE_PATH}"
reviewed: {ISO_TIMESTAMP}
focus: "{FOCUS_AREAS}"
agents: [{list of agents that ran}]
---

# Feature & Code Review: {PACKAGE_NAME} (Multi-Agent)

**Path**: `{package-path}`
**Reviewed**: {date}
**Files Analyzed**: {count}
**Agents**: {list}

---

## Executive Summary

{3-5 sentences summarizing findings}

**Overall Health Score**: {N}/10

### Agents Dispatched
| Agent | Status | Score | Findings |
|-------|--------|-------|----------|
| code-reviewer | Completed | {N}/10 | {count} |
| security-reviewer | Completed | {N}/10 | {count} |
| product-ideas-agent | Completed | {N}/10 | {count} |
| performance-analyzer | Completed | {N}/10 | {count} |
| {conditional agents...} | ... | ... | ... |

### Area Scores
| Area | Score | Status |
|------|-------|--------|
| Code Quality | {N}/10 | {GOOD/NEEDS_WORK/CRITICAL} |
| Product Potential | {N}/10 | {GOOD/NEEDS_WORK/CRITICAL} |
| Performance | {N}/10 | {GOOD/NEEDS_WORK/CRITICAL} |
| Security | {N}/10 | {GOOD/NEEDS_WORK/CRITICAL} |

---

## Code Quality Analysis
{From code-reviewer agent}

## Product & Feature Ideas
{From product-ideas-agent}

## Performance Recommendations
{From performance-analyzer agent}

## Security Findings
{From security-reviewer agent}

## Additional Findings
{From conditional agents: accessibility, deps, errors, observability}

---

## Prioritized Action Items

### Critical (Do Now)
| Item | Type | Agent | Effort | Impact |
|------|------|-------|--------|--------|

### High Priority (This Sprint)
| Item | Type | Agent | Effort | Impact |
|------|------|-------|--------|--------|

### Medium Priority (Backlog)
| Item | Type | Agent | Effort | Impact |
|------|------|-------|--------|--------|

### Future Considerations
| Item | Type | Agent | Effort | Impact |
|------|------|-------|--------|--------|

---

## Suggested Roadmap

### Phase 1: Foundation (1-2 weeks)
{Critical fixes and quick wins}

### Phase 2: Enhancement (2-4 weeks)
{High priority improvements}

### Phase 3: Innovation (1-2 months)
{Strategic features and optimization}
```

### 5.2 Present to User

```markdown
## Feature Review Complete (Multi-Agent)

**Package**: `{PACKAGE_PATH}`
**Files Analyzed**: {count}
**Overall Health**: {score}/10
**Agents**: {count} dispatched

### Area Scores
| Area | Score | Top Finding |
|------|-------|-------------|
| Code Quality | {N}/10 | {one-liner} |
| Product Ideas | {N}/10 | {one-liner} |
| Performance | {N}/10 | {one-liner} |
| Security | {N}/10 | {one-liner} |

### Action Items Summary
- Critical: {count} items
- High: {count} items
- Medium: {count} items
- Low: {count} items

### Artifacts
- Full Report: `.prp-output/reviews/feature-review-{package-name}-{date}.md`
- Context File: `.prp-output/reviews/feature-context-{package-name}.md`
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| Path not found | STOP with error message |
| Empty package (no source files) | STOP — "No source files found in `{path}`" |
| Very large package (>500 files) | Focus on entry points and core logic; note "partial scan" in report |
| Context file write fails | STOP — do not spawn agents without context |
| Agent tool not available | Fall back to `$prp-feature-review` |
| Agent fails or times out | WARN, proceed with available results |
| `--quick` flag | Core agents only (code-reviewer, security-reviewer) |

---

## Critical Reminders

1. **Spawn agents, don't simulate.** Use the Agent tool with subagent_type.
2. **Be thorough.** Agents must read actual code, not just scan file names.
3. **Be creative.** Product ideas should be innovative and actionable.
4. **Be specific.** Include file:line references and concrete suggestions.
5. **Be balanced.** Acknowledge good work, not just problems.
6. **Think like users.** Consider the end-user experience.
7. **Consider business.** Think about ROI and business impact.

---

## Success Criteria

- AGENTS_SPAWNED: Core agents spawned via Agent tool
- PARALLEL_EXECUTION: Agents launched in a single message
- CONTEXT_SHARED: All agents read from shared feature-context file
- DEEP_EXPLORATION: Agents read actual source files
- CONDITIONAL_DISPATCHED: Bonus agents triggered by package content
- RESULTS_COLLECTED: All agent outputs collected
- ISSUES_DEDUPLICATED: Duplicate findings merged across agents
- SCORES_AGGREGATED: Per-area scores calculated
- ACTIONS_PRIORITIZED: Clear next steps with effort/impact
- REPORT_CREATED: Comprehensive report saved
- FALLBACK_AVAILABLE: Graceful fallback to $prp-feature-review

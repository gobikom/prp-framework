---
description: Comprehensive feature and code review with context caching for token optimization
agent: plan
---

## Agent Mode Detection

If your input context contains `[WORKSPACE CONTEXT]` (injected by a multi-agents framework),
you are running as a sub-agent. Apply these optimizations:

- **Skip CLAUDE.md reading** — already loaded by parent session.
- **Skip directory discovery** — the parent agent already explored the codebase.
- **Skip PR context extraction** if a `pr-context-*.md` file is provided in context files.

All review passes and analysis phases run unchanged — these are where quality comes from.

---


# PRP Feature Review — Comprehensive Analysis

Target: $ARGUMENTS

Format: `<package-path> [--focus code|product|performance|security|all]`

## Mission

Perform a senior-engineer-level review of a package or folder. Understand structure, analyze code quality, suggest product improvements, identify performance opportunities, review security, and generate actionable report.

**Golden Rule**: Be constructive, creative, and actionable. Think like a product-minded engineer who cares about both code quality AND user value.

## Steps

1. **Parse Input**: Validate path exists. Determine focus area (default: `all`). Check for existing context file — if `.prp-output/reviews/feature-context-{package-name}.md` exists and is < 1 hour old, skip to step 3.

2. **Context Extraction** (token optimization — extract ONCE, cache):
   ```bash
   mkdir -p .prp-output/reviews
   ```
   Gather in a single pass: project rules (`CLAUDE.md`), package structure (`tree -L 3`), package manifest, key files list, README. Categorize files: entry points, config, core logic, UI components, utilities, tests.

   Save to `.prp-output/reviews/feature-context-{package-name}.md` with frontmatter (package, extracted timestamp, files_count), project guidelines, package structure, manifest, key files by category, file inventory, initial observations.

3. **Analyze** (read files selectively based on focus area):

   **3.1 Code Quality** (`--focus code` or `all`):
   - Architecture & Design: separation of concerns, abstractions, dependency injection, module boundaries
   - Code Patterns: naming, DRY, error handling, logging/observability
   - Type Safety: explicit types (no `any`), generics, interfaces, null safety
   - Testing: coverage, unit/integration tests, edge cases
   - Documentation: functions documented, complex logic explained, API contracts

   **3.2 Product/Feature Ideas** (`--focus product` or `all`):
   - Current features: what it does, users, problems solved
   - Ideas: missing features, friction reduction, 10x improvements, competitor gaps
   - Categories: UX, new capabilities, integrations, automation, accessibility
   - User journey: map flow, identify pain points, suggest improvements

   **3.3 Performance** (`--focus performance` or `all`):
   - Code-level: N+1 queries, unnecessary async, memory leaks, heavy hot-path computations, large imports
   - Architecture: caching, lazy loading, query optimization, API batching, pagination
   - Metrics: load time, memory, network efficiency, rendering

   **3.4 Security** (`--focus security` or `all`):
   - Input validation: injection, XSS, file upload
   - Auth: protected routes, token handling, session management, RBAC
   - Data protection: encryption, secrets in env vars, PII handling, logging exposure
   - API: rate limiting, CORS, API key protection, request validation

4. **Prioritize Findings**:

   | Priority | Criteria |
   |----------|----------|
   | Critical | Security vulns, data loss risks, breaking bugs |
   | High | Significant improvements, important missing features |
   | Medium | Nice-to-have, optimization opportunities |
   | Low | Minor suggestions, future considerations |

   Estimate effort: Quick Win (< 1 day), Small (1-3 days), Medium (1-2 weeks), Large (> 2 weeks). Calculate ROI: high impact + low effort = do first.

5. **Generate Report**: Save to `.prp-output/reviews/feature-review-{package-name}-{date}.md` with:
   - Executive Summary (3-5 sentences, overall health score 1-10, area scores table)
   - Code Quality Analysis (strengths, improvements, pattern recommendations)
   - Product & Feature Ideas (quick wins, strategic features, innovation, UX)
   - Performance Recommendations (immediate, architectural, monitoring)
   - Security Findings (critical, high priority, recommendations)
   - Prioritized Action Items (critical/high/medium/future tables with type, effort, impact)
   - Metrics to Track
   - Suggested Roadmap (Phase 1: Foundation, Phase 2: Enhancement, Phase 3: Innovation)

6. **Output to User**: Package, files analyzed, health score, area scores with top findings, action item counts, artifact paths (report + context file), recommended next steps.

## Selective Reading Strategy

| Focus Area | Files to Prioritize |
|------------|---------------------|
| `--focus code` | Entry points, core logic, utils |
| `--focus product` | UI components, user-facing code |
| `--focus performance` | Hot paths, DB queries, API calls |
| `--focus security` | Auth, API handlers, input validation |
| `--focus all` | All above (read incrementally) |

## Usage

```
/prp:feature-review packages/web
/prp:feature-review src/features/auth --focus security
/prp:feature-review src/api --focus performance
/prp:feature-review . --focus code
```

## Success Criteria

- CONTEXT_CACHED: Context file created and saved
- CODE_REVIEWED: Significant files analyzed (not exhaustively)
- IDEAS_GENERATED: Creative product suggestions provided
- PERFORMANCE_CHECKED: Optimization opportunities identified
- SECURITY_ASSESSED: Vulnerabilities and risks documented
- REPORT_CREATED: Comprehensive markdown report saved
- ACTIONS_PRIORITIZED: Clear next steps with effort/impact

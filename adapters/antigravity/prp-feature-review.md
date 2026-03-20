---
description: Comprehensive feature & code review - analyzes package/folder for quality, product ideas, performance, and security
---

## Agent Mode Detection

If your input context contains `[WORKSPACE CONTEXT]` (injected by a multi-agents framework),
you are running as a sub-agent. Apply these optimizations:

- **Skip CLAUDE.md reading** — already loaded by parent session.
- **Skip directory discovery** — the parent agent already explored the codebase.
- **Skip PR context extraction** if a `pr-context-*.md` file is provided in context files.

All review passes and analysis phases run unchanged — these are where quality comes from.

---


# PRP Feature Review — Comprehensive Feature & Code Review

Target: $ARGUMENTS

Format: `<package-path> [--focus code|product|performance|security|all]`

## Mission

Perform a comprehensive, senior-engineer-level review of a package or folder: code quality, product ideas, performance, security. Generate actionable report with prioritized action items.

**Golden Rule**: Be constructive, creative, and actionable. Think like a product-minded engineer who cares about both code quality AND user value.

## Step 1: PARSE — Understand Input

| Input | Interpretation |
|-------|----------------|
| `packages/web` | Review entire package |
| `src/features/auth` | Review specific folder |
| `--focus code` | Code quality only |
| `--focus product` | Product/UX ideas only |
| `--focus performance` | Performance only |
| `--focus security` | Security only |
| `--focus all` (default) | All areas |

Validate path exists. Get file count. Check for existing context file.

## Step 2: CONTEXT EXTRACTION — Token Optimization

**Purpose**: Extract and cache context ONCE to avoid redundant file reads.

```bash
mkdir -p .prp-output/reviews
```

Gather in single pass:
- Project rules (CLAUDE.md)
- Package structure (`tree -L 3 -I node_modules`)
- Package manifest (package.json)
- Key files list
- README

Categorize files: entry points, config, core logic, UI components, utils, tests.

**Write context file**: `.prp-output/reviews/feature-context-{package-name}.md` with frontmatter (package, extracted timestamp, files_count), project guidelines, structure, manifest, key files by category, initial observations.

If context exists and is recent (< 1 hour), skip to Step 3.

## Step 3: ANALYZE — Deep Review

Reference context file. Read files selectively based on focus area.

### Code Quality
- Architecture & design (separation of concerns, abstractions, module boundaries)
- Code patterns (naming, DRY, error handling, logging)
- Type safety (no implicit `any`, generics, null safety)
- Testing (coverage, unit/integration, edge cases)
- Documentation (functions documented, complex logic explained)

### Product/Feature Ideas
- Current features: what it does, who uses it, problems solved
- Feature ideas: what's missing, friction reduction, 10x improvements
- Categories: UX improvements, new capabilities, integrations, automation, accessibility
- User journey: map flow, identify pain points, suggest improvements

### Performance
- Code-level: N+1 queries, unnecessary async, memory leaks, heavy hot-path computations, large bundle imports
- Architecture: caching, lazy loading, query optimization, API batching, pagination
- Metrics: load time, memory usage, network efficiency, rendering

### Security
- Input validation: user inputs, injection prevention, XSS, file uploads
- Auth: protected routes, token handling, sessions, RBAC
- Data protection: encryption, secrets in env vars, PII handling, logging
- API: rate limiting, CORS, API keys, request validation

## Step 4: PRIORITIZE — Organize Findings

| Priority | Criteria |
|----------|----------|
| Critical | Security vulns, data loss risks, breaking bugs |
| High | Significant improvements, important missing features |
| Medium | Nice-to-have, optimization opportunities |
| Low | Minor suggestions, future considerations |

Estimate effort: Quick Win (< 1 day) / Small (1-3 days) / Medium (1-2 weeks) / Large (> 2 weeks).

ROI: High impact + Low effort = Do first. Low impact + High effort = Skip/defer.

## Step 5: REPORT — Generate Output

**Path**: `.prp-output/reviews/feature-review-{package-name}-{date}.md`

Report includes:
- **Executive Summary**: 3-5 sentences, overall health score (1-10), area scores table
- **Code Quality**: strengths, improvements, pattern recommendations
- **Product Ideas**: quick wins, strategic features, innovation ideas, UX improvements
- **Performance**: immediate optimizations, architecture improvements, monitoring suggestions
- **Security**: critical issues, high priority, recommendations
- **Prioritized Action Items**: tables by priority (Critical/High/Medium/Future) with type, effort, impact
- **Metrics to Track**: suggested improvement measurements
- **Suggested Roadmap**: Phase 1 (foundation, 1-2wk), Phase 2 (enhancement, 2-4wk), Phase 3 (innovation, 1-2mo)

## Step 6: OUTPUT — Present to User

Display: package path, files analyzed, overall health score, area scores table with top findings, action items summary (critical/high/medium/low counts), artifact paths (report + context), recommended next steps.

## Critical Reminders

1. **Read actual code**, don't just scan file names
2. **Be creative** with product ideas
3. **Be specific** — reference files and line numbers
4. **Be balanced** — acknowledge good work
5. **Be actionable** — every finding has a recommendation
6. **Think like users** — consider end-user experience
7. **Consider ROI** — business impact matters

## Token Optimization

- Context file cached and reused for re-runs and multi-agent reviews
- Selective file reading by focus area
- Savings: ~40-50% by caching context and selective reading

## Usage

```
/prp-feature-review packages/web
/prp-feature-review src/features/auth --focus security
/prp-feature-review packages/api --focus code
/prp-feature-review . --focus all
```

## Success Criteria

- CONTEXT_CACHED: Context file created and saved
- CODE_REVIEWED: Significant files analyzed (not exhaustively)
- IDEAS_GENERATED: Creative product suggestions provided
- PERFORMANCE_CHECKED: Optimization opportunities identified
- SECURITY_ASSESSED: Vulnerabilities and risks documented
- REPORT_CREATED: Comprehensive markdown report saved
- ACTIONS_PRIORITIZED: Clear next steps with effort/impact

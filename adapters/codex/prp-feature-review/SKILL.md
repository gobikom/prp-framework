---
name: prp-feature-review
description: Comprehensive senior-engineer-level review of a package or folder — analyzes code quality, product potential, performance, and security. Generates actionable report with prioritized findings.
metadata:
  short-description: Comprehensive feature and code review
---

# PRP Feature Review — Comprehensive Feature and Code Review

## Input

Package path and optional focus: `$ARGUMENTS`

Format: `<package-path> [--focus code|product|performance|security|all]`

## Mission

Perform a comprehensive, senior-engineer-level review of a package or folder to:
1. **Understand** the codebase structure and purpose
2. **Analyze** code quality, patterns, and architecture
3. **Suggest** product improvements and new feature ideas
4. **Identify** performance optimization opportunities
5. **Review** security concerns and best practices
6. **Generate** actionable markdown report

**Golden Rule**: Be constructive, creative, and actionable. Think like a product-minded engineer who cares about both code quality AND user value.

## Phase 1: PARSE — Understand Input

### 1.1 Parse Arguments

| Input | Interpretation |
|-------|----------------|
| `packages/web` | Review entire package |
| `src/features/auth` | Review specific feature folder |
| `--focus code` | Focus on code quality only |
| `--focus product` | Focus on product/UX ideas |
| `--focus performance` | Focus on performance |
| `--focus security` | Focus on security |
| `--focus all` | All areas (default) |

### 1.2 Validate Path

```bash
ls -la {input-path} 2>/dev/null || echo "PATH_NOT_FOUND"
find {input-path} -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.rs" -o -name "*.go" \) | wc -l
```

**If path doesn't exist**: STOP and report error.

### 1.3 Check for Existing Context

```bash
ls .prp-output/reviews/feature-context-{package-name}.md 2>/dev/null
```

**If context exists and is recent (< 1 hour)**: Skip to Phase 3 (token optimization).

**PHASE_1_CHECKPOINT:**
- [ ] Input path validated
- [ ] Focus areas determined
- [ ] Existing context checked

## Phase 2: CONTEXT EXTRACTION (Token Optimization)

**Purpose**: Extract and cache context ONCE to avoid redundant file reads.

### 2.1 Gather Project Context

```bash
mkdir -p .prp-output/reviews
```

Read in a single pass:
- **Project Rules**: CLAUDE.md / .codex/instructions.md (first 200 lines)
- **Package Structure**: `tree {input-path} -L 3 -I node_modules`
- **Package Manifest**: package.json / Cargo.toml / go.mod / pyproject.toml
- **Key Files List**: all source files (first 100)
- **README**: if exists

### 2.2 Categorize Key Files

- **Entry points**: index.ts, main.ts, app.ts
- **Config files**: *.config.ts, *.config.js
- **Core logic**: services/, lib/, core/
- **UI components**: components/, pages/, views/
- **Utilities**: utils/, helpers/, common/
- **Tests**: *.test.ts, *.spec.ts, __tests__/

### 2.3 Write Context File

**Path**: `.prp-output/reviews/feature-context-{package-name}.md`

Contents: YAML frontmatter (package, extracted timestamp, files_count), Project Guidelines, Package Structure tree, Package Manifest, Key Files by Category, File Inventory, Initial Observations.

**PHASE_2_CHECKPOINT:**
- [ ] Project rules extracted
- [ ] Package structure mapped
- [ ] Key files categorized
- [ ] Context file saved

## Phase 3: ANALYZE — Deep Code Review

**Reference**: Use context file for structure and guidelines. Read files selectively based on focus area.

### 3.1 Code Quality Analysis

For each significant file (prioritize core logic, entry points):

- **Architecture & Design**: Separation of concerns, abstractions, module boundaries
- **Code Patterns**: Naming conventions, DRY, error handling, logging
- **Type Safety**: Explicit types (no implicit `any`), generics, null safety
- **Testing**: Coverage, unit tests for critical logic, edge cases
- **Documentation**: Functions documented, complex logic explained, API contracts

### 3.2 Product/Feature Analysis

Think like a product manager:
- What does this package do? Who are the users?
- What's missing that users would love?
- What friction could be reduced?
- UX improvements, new capabilities, integration opportunities, automation

### 3.3 Performance Analysis

- **Code-level**: N+1 queries, unnecessary async, memory leaks, heavy computations in hot paths, large imports
- **Architecture**: Caching opportunities, lazy loading, query optimization, API batching, pagination

### 3.4 Security Analysis

- **Input Validation**: SQL/NoSQL injection, XSS, file upload restrictions
- **Auth & Authz**: Auth checks on protected routes, token handling, session management, RBAC
- **Data Protection**: Encryption, secrets in env vars, PII handling, logging safety
- **API Security**: Rate limiting, CORS, API key protection, request validation

**PHASE_3_CHECKPOINT:**
- [ ] Code quality analyzed
- [ ] Product ideas generated
- [ ] Performance reviewed
- [ ] Security assessed

## Phase 4: PRIORITIZE — Organize Findings

### 4.1 Categorize by Impact

| Priority | Criteria |
|----------|----------|
| Critical | Security vulnerabilities, data loss risks, breaking bugs |
| High | Significant improvements, important missing features |
| Medium | Nice-to-have improvements, optimization opportunities |
| Low | Minor suggestions, future considerations |

### 4.2 Estimate Effort

- **Quick Win**: < 1 day
- **Small**: 1-3 days
- **Medium**: 1-2 weeks
- **Large**: > 2 weeks

### 4.3 Calculate ROI

High impact + Low effort = Do first. High impact + High effort = Plan carefully. Low impact + Low effort = Nice to have. Low impact + High effort = Skip or defer.

**PHASE_4_CHECKPOINT:**
- [ ] Findings prioritized
- [ ] Effort estimated
- [ ] ROI calculated

## Phase 5: REPORT — Generate Output

### 5.1 Generate Report File

**Path**: `.prp-output/reviews/feature-review-{package-name}-{date}.md`

Report structure:
1. **YAML frontmatter**: package, reviewed timestamp, focus, reviewer
2. **Executive Summary**: 3-5 sentences, Overall Health Score (1-10), area scores table
3. **Code Quality Analysis**: Strengths, Areas for Improvement, Pattern Recommendations
4. **Product & Feature Ideas**: Quick Wins, Strategic Features, Innovation Ideas, UX Improvements
5. **Performance Recommendations**: Immediate Optimizations, Architecture Improvements, Monitoring Suggestions
6. **Security Findings**: Critical Issues, High Priority, Recommendations
7. **Prioritized Action Items**: Tables by priority (Critical / High / Medium / Future) with Type, Effort, Impact
8. **Metrics to Track**: Suggested improvement metrics
9. **Suggested Roadmap**: Phase 1 Foundation (1-2 weeks), Phase 2 Enhancement (2-4 weeks), Phase 3 Innovation (1-2 months)

**PHASE_5_CHECKPOINT:**
- [ ] Report file created
- [ ] All sections populated
- [ ] Actionable items prioritized

## Phase 6: OUTPUT — Present to User

Present: Package path, files analyzed count, Overall Health score, Summary, Key Findings table (area, score, top finding), Action Items count by priority, Artifact paths (full report + context file), Recommended next steps.

## Critical Reminders

1. **Be Thorough**: Read actual code, don't just scan file names
2. **Be Creative**: Think outside the box for product ideas
3. **Be Specific**: Reference specific files and line numbers
4. **Be Balanced**: Acknowledge good work, not just problems
5. **Be Actionable**: Every finding should have a recommendation
6. **Think Like Users**: Consider the end-user experience
7. **Consider Business**: Think about ROI and business impact

## Token Optimization Strategy

The context file serves multiple purposes:
- **Avoid redundant reads** — structure extracted once
- **Enable re-runs** — if context recent, skip Phase 2
- **Support multi-agent** — same context file used by `$prp-feature-review-agents`

| Focus Area | Files to Prioritize |
|------------|---------------------|
| `--focus code` | Entry points, core logic, utils |
| `--focus product` | UI components, user-facing code |
| `--focus performance` | Hot paths, database queries, API calls |
| `--focus security` | Auth, API handlers, input validation |
| `--focus all` | All of the above (read incrementally) |

## Usage Examples

```
$prp-feature-review packages/web
$prp-feature-review src/features/auth --focus security
$prp-feature-review . --focus code
$prp-feature-review packages/api --focus performance
```

## Success Criteria

- CONTEXT_CACHED: Context file created at `.prp-output/reviews/feature-context-{package-name}.md`
- CONTEXT_GATHERED: Package structure and purpose understood
- CODE_REVIEWED: Significant files analyzed (not exhaustively)
- IDEAS_GENERATED: Creative product suggestions provided
- PERFORMANCE_CHECKED: Optimization opportunities identified
- SECURITY_ASSESSED: Vulnerabilities and risks documented
- REPORT_CREATED: Report saved at `.prp-output/reviews/feature-review-{package-name}-{date}.md`
- ACTIONS_PRIORITIZED: Clear next steps with effort/impact

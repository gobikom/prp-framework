---
description: Comprehensive feature review using specialized agents - code quality, product ideas, performance, security, accessibility, dependencies, and observability
argument-hint: "<package-path> [--focus code|product|perf|security|a11y|deps|obs|all] [--quick]"
---

# Feature Review with Specialized Agents

Run a multi-agent review on a package or folder, with each agent focusing on a specific aspect of quality.

**Target**: $ARGUMENTS

---

## Phase 0: PARSE INPUT

### Parse Arguments

| Input | Interpretation |
|-------|----------------|
| `packages/web` | Review entire package |
| `src/features/auth` | Review specific folder |
| `--focus code` | Code quality only |
| `--focus product` | Product ideas only |
| `--focus perf` | Performance only |
| `--focus security` | Security only |
| `--focus a11y` | Accessibility only |
| `--focus deps` | Dependencies only |
| `--focus obs` | Observability only |
| `--focus all` | All aspects (default) |
| `--quick` | Quick review (3 core agents) |

### Validate Path

```bash
# Verify path exists
ls -la {input-path} 2>/dev/null || echo "PATH_NOT_FOUND"

# Get file stats
find {input-path} -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) | wc -l
```

**If path doesn't exist**: STOP and report error.

---

## Phase 1: CONTEXT EXTRACTION (Token Optimization)

**Purpose**: Extract context ONCE, share with all agents.

### 1.1 Create Context File

```bash
mkdir -p .claude/PRPs/reviews
```

**Context File Path**: `.claude/PRPs/reviews/feature-context-{package-name}.md`

### 1.2 Gather Context

Read and extract:

1. **Project Rules**
   ```bash
   cat CLAUDE.md 2>/dev/null | head -200
   ```

2. **Package Structure**
   ```bash
   tree {input-path} -L 3 -I node_modules 2>/dev/null || find {input-path} -type d | head -50
   ```

3. **Package Manifest** (if exists)
   ```bash
   cat {input-path}/package.json 2>/dev/null | head -100
   ```

4. **Key Files** (entry points, config)
   - Read index.ts, main.ts, app.ts
   - Read config files
   - Read README.md

5. **File List**
   ```bash
   find {input-path} -type f \( -name "*.ts" -o -name "*.tsx" \) | head -100
   ```

### 1.3 Write Context File

```markdown
---
package: "{PACKAGE_PATH}"
extracted: {ISO_TIMESTAMP}
files_count: {N}
---

# Feature Context: {PACKAGE_NAME}

## Project Guidelines (from CLAUDE.md)
{relevant sections}

## Package Structure
```
{tree output}
```

## Package Manifest
```json
{package.json content}
```

## Key Files

### {entry-point-1}
```typescript
{file content}
```

### {entry-point-2}
...

## File Inventory
{list of all files}
```

**CHECKPOINT**: Context file created at `.claude/PRPs/reviews/feature-context-{package-name}.md`

---

## Phase 2: AGENT SELECTION

### Available Agents

| Agent | Focus Area | When to Run |
|-------|------------|-------------|
| `code-reviewer` | Code quality, patterns, guidelines | Always |
| `codebase-analyst` | Architecture, data flow | Always |
| `product-ideas-agent` | Features, UX, user value | Unless --focus excludes |
| `performance-analyzer` | Bottlenecks, optimization | Unless --focus excludes |
| `security-reviewer` | Vulnerabilities, OWASP | Unless --focus excludes |
| `accessibility-reviewer` | WCAG, a11y | Only if UI files present |
| `dependency-analyzer` | Package health, CVEs | Only if package.json present |
| `observability-reviewer` | Logging, metrics, tracing | Unless --focus excludes |
| `type-design-analyzer` | Type quality | If TypeScript |
| `silent-failure-hunter` | Error handling | Always |

### Selection Logic

**Quick Mode (--quick)**:
- `code-reviewer`
- `security-reviewer`
- `performance-analyzer`

**Full Mode (default)**:

```
Always Run:
├── code-reviewer
├── codebase-analyst
└── silent-failure-hunter

Run if UI files (.tsx, .jsx, .vue, .svelte):
└── accessibility-reviewer

Run if package.json exists:
└── dependency-analyzer

Run unless excluded:
├── product-ideas-agent
├── performance-analyzer
├── security-reviewer
├── observability-reviewer
└── type-design-analyzer (if TypeScript)
```

**Focus Mode**:
- Only run agents matching `--focus` flag

---

## Phase 3: AGENT EXECUTION

### Execution Strategy

**Default**: Sequential (clear, actionable feedback)
**Optional**: Parallel (if user specifies, use multiple Task calls)

### Agent Instructions

Each agent receives:
1. **Context file path** (shared context)
2. **Targeted file patterns** (domain-specific)
3. **Output expectations**

#### Core Agents

**code-reviewer**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Review code in `{PACKAGE_PATH}` for project guideline compliance, patterns, and quality.
> Focus on guidelines from CLAUDE.md. Report only high-confidence issues (80+).

**codebase-analyst**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Analyze architecture and data flow in `{PACKAGE_PATH}`.
> Document how the code works with file:line references.

**silent-failure-hunter**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Hunt for silent failures in `{PACKAGE_PATH}`.
> Check all error handling for proper logging and user feedback.

#### Domain Agents

**product-ideas-agent**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Analyze `{PACKAGE_PATH}` for product improvement opportunities.
> Generate feature ideas, UX improvements, and innovation opportunities.
> Focus on user value and business impact.

**performance-analyzer**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Analyze `{PACKAGE_PATH}` for performance bottlenecks.
> Look for N+1 queries, memory leaks, bundle size issues.
> Quantify impact whenever possible.

**security-reviewer**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Review `{PACKAGE_PATH}` for security vulnerabilities.
> Check OWASP Top 10, auth issues, injection risks.
> Only report issues with clear attack vectors.

**accessibility-reviewer**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Review UI files in `{PACKAGE_PATH}` for WCAG 2.1 compliance.
> Check keyboard navigation, screen reader support, color contrast.
> Focus on files: *.tsx, *.jsx, *.vue, *.svelte, *.css

**dependency-analyzer**:
> Analyze dependencies in `{PACKAGE_PATH}`.
> Check for security vulnerabilities, outdated packages, bundle impact.
> Review package.json and lock files.

**observability-reviewer**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Review `{PACKAGE_PATH}` for observability practices.
> Check logging coverage, metrics, error tracking.
> Ensure production readiness.

**type-design-analyzer**:
> Read context file at `.claude/PRPs/reviews/feature-context-{pkg}.md`.
> Analyze type design in `{PACKAGE_PATH}`.
> Check encapsulation, invariants, and type safety.

---

## Phase 4: RESULT AGGREGATION

### Collect Results

After all agents complete, aggregate findings into categories:

| Category | Description | Action |
|----------|-------------|--------|
| **Critical** | Security vulns, data loss risks | Must fix |
| **High** | Significant issues, important improvements | Should fix |
| **Medium** | Nice-to-have, optimization opportunities | Consider |
| **Low** | Minor suggestions, future ideas | Backlog |

### Scoring

Calculate overall health score (1-10) based on:

| Area | Weight | Score |
|------|--------|-------|
| Code Quality | 20% | from code-reviewer |
| Security | 25% | from security-reviewer |
| Performance | 15% | from performance-analyzer |
| Accessibility | 10% | from accessibility-reviewer |
| Dependencies | 10% | from dependency-analyzer |
| Observability | 10% | from observability-reviewer |
| Product Potential | 10% | from product-ideas-agent |

---

## Phase 5: GENERATE REPORT

### Save Report

**Path**: `.claude/PRPs/reviews/feature-review-{package-name}-agents-{date}.md`

```markdown
---
package: "{PACKAGE_PATH}"
reviewed: {ISO_TIMESTAMP}
agents_used: [{list}]
focus: "{FOCUS_AREAS}"
---

# Feature Review: {PACKAGE_NAME}

**Path**: `{package-path}`
**Reviewed**: {date}
**Files Analyzed**: {count}
**Agents Used**: {count}

---

## Executive Summary

{3-5 sentences summarizing findings}

**Overall Health Score**: {1-10}/10

| Area | Score | Status | Agent |
|------|-------|--------|-------|
| Code Quality | {N}/10 | {status} | code-reviewer |
| Security | {N}/10 | {status} | security-reviewer |
| Performance | {N}/10 | {status} | performance-analyzer |
| Accessibility | {N}/10 | {status} | accessibility-reviewer |
| Dependencies | {N}/10 | {status} | dependency-analyzer |
| Observability | {N}/10 | {status} | observability-reviewer |
| Product Potential | {N}/10 | {status} | product-ideas-agent |

---

## 🔴 Critical Issues

| Issue | Area | Agent | Location | Fix |
|-------|------|-------|----------|-----|
| {issue} | Security | security-reviewer | `file:line` | {fix} |

---

## 🟠 High Priority

| Issue | Area | Agent | Location |
|-------|------|-------|----------|
| {issue} | {area} | {agent} | `file:line` |

---

## 🟡 Medium Priority

| Issue | Area | Agent | Location |
|-------|------|-------|----------|

---

## 🔵 Suggestions & Ideas

### Product Ideas (from product-ideas-agent)
{top 3-5 ideas}

### Performance Optimizations (from performance-analyzer)
{top 3 optimizations}

### Accessibility Improvements (from accessibility-reviewer)
{top 3 improvements}

---

## Agent Reports

### Code Quality (code-reviewer)
{summary}

### Architecture (codebase-analyst)
{summary}

### Product Ideas (product-ideas-agent)
{summary}

### Performance (performance-analyzer)
{summary}

### Security (security-reviewer)
{summary}

### Accessibility (accessibility-reviewer)
{summary}

### Dependencies (dependency-analyzer)
{summary}

### Observability (observability-reviewer)
{summary}

---

## Prioritized Action Items

### Immediate (This Week)
1. {critical fix}
2. {high priority}

### Short-term (This Sprint)
1. {improvement}
2. {optimization}

### Long-term (Backlog)
1. {feature idea}
2. {enhancement}

---

## Metrics to Track

| Metric | Current | Target | Owner |
|--------|---------|--------|-------|
| {metric} | ? | {target} | {team} |

---

*Generated by Feature Review Agents*
*Report: `.claude/PRPs/reviews/feature-review-{package-name}-agents-{date}.md`*
*Context: `.claude/PRPs/reviews/feature-context-{package-name}.md`*
```

---

## Phase 6: OUTPUT TO USER

```markdown
## ✅ Feature Review Complete

**Package**: `{PACKAGE_PATH}`
**Files Analyzed**: {count}
**Agents Used**: {count}
**Overall Health**: {score}/10

### Summary

{2-3 sentences}

### Scores by Area

| Area | Score | Top Finding |
|------|-------|-------------|
| 🎨 Code Quality | {N}/10 | {one-liner} |
| 🔐 Security | {N}/10 | {one-liner} |
| ⚡ Performance | {N}/10 | {one-liner} |
| ♿ Accessibility | {N}/10 | {one-liner} |
| 📦 Dependencies | {N}/10 | {one-liner} |
| 📊 Observability | {N}/10 | {one-liner} |
| 💡 Product Ideas | {N}/10 | {one-liner} |

### Action Items

- 🔴 Critical: {count} items
- 🟠 High: {count} items
- 🟡 Medium: {count} items
- 🔵 Ideas: {count} items

### Artifacts

📄 **Full Report**: `.claude/PRPs/reviews/feature-review-{pkg}-agents-{date}.md`
📋 **Context File**: `.claude/PRPs/reviews/feature-context-{pkg}.md`

### Next Steps

1. {immediate action}
2. {follow-up}
```

---

## Token Budget

| Phase | Cost | Notes |
|-------|------|-------|
| Context Extraction | ~10K | One-time, shared |
| Each Agent | ~15-25K | Reads context + targeted files |
| Aggregation | ~5K | Summarization |
| **Total (Quick)** | ~60-80K | 3 agents |
| **Total (Full)** | ~150-200K | 10 agents |

**Without context optimization**: ~500K+ tokens
**With context optimization**: ~150-200K tokens (60-70% savings)

---

## Usage Examples

```bash
# Full review of package
/prp-feature-review-agents packages/web

# Quick review (3 agents)
/prp-feature-review-agents src/features/auth --quick

# Focus on specific areas
/prp-feature-review-agents packages/api --focus security
/prp-feature-review-agents packages/ui --focus a11y
/prp-feature-review-agents . --focus product

# Multiple focus areas
/prp-feature-review-agents packages/core --focus "code security perf"
```

---

## Critical Rules

1. **Extract context first** - Always create context file before launching agents
2. **Share context** - All agents read the same context file
3. **Selective file reading** - Agents only read files relevant to their domain
4. **Skip irrelevant agents** - Don't run a11y agent on backend code
5. **Aggregate meaningfully** - Deduplicate and prioritize findings
6. **Stop on failure** - If context extraction fails, don't proceed

---

## Success Criteria

- **CONTEXT_EXTRACTED**: Context file created and saved
- **AGENTS_SELECTED**: Appropriate agents chosen for package type
- **AGENTS_EXECUTED**: All selected agents completed
- **RESULTS_AGGREGATED**: Findings categorized and prioritized
- **REPORT_GENERATED**: Comprehensive report saved
- **SCORES_CALCULATED**: Overall and per-area scores computed

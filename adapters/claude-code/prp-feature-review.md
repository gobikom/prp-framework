---
description: Comprehensive feature & code review - analyzes package/folder for quality, product ideas, performance, and security
argument-hint: <package-path> [--focus code|product|performance|security|all]
---

# Feature & Code Review

**Input**: $ARGUMENTS

---

## Your Mission

Perform a comprehensive, senior-engineer-level review of a package or folder to:

1. **Understand** the codebase structure and purpose
2. **Analyze** code quality, patterns, and architecture
3. **Suggest** product improvements and new feature ideas
4. **Identify** performance optimization opportunities
5. **Review** security concerns and best practices
6. **Generate** actionable markdown report

**Golden Rule**: Be constructive, creative, and actionable. Think like a product-minded engineer who cares about both code quality AND user value.

---

## Phase 1: PARSE - Understand Input

### 1.1 Parse Arguments

**Input format:**

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
# Verify path exists
ls -la {input-path} 2>/dev/null || echo "PATH_NOT_FOUND"

# Get file count and structure
find {input-path} -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) | wc -l
```

**If path doesn't exist:** STOP and report error.

### 1.3 Check for Existing Context

```bash
# Check if context file already exists (for re-runs)
ls .claude/PRPs/reviews/feature-context-{package-name}.md 2>/dev/null
```

**If context exists and is recent (< 1 hour)**: Skip to Phase 3 (Token Optimization).

**PHASE_1_CHECKPOINT:**
- [ ] Input path validated
- [ ] Focus areas determined
- [ ] Scope identified
- [ ] Existing context checked

---

## Phase 2: CONTEXT EXTRACTION (Token Optimization)

**Purpose**: Extract and cache context ONCE to avoid redundant file reads.

### 2.1 Create Context Directory

```bash
mkdir -p .claude/PRPs/reviews
```

### 2.2 Gather Project Context

Read and extract the following in a single pass:

**Project Rules:**
```bash
cat CLAUDE.md 2>/dev/null | head -200
```

**Package Structure:**
```bash
tree {input-path} -L 3 -I node_modules 2>/dev/null || find {input-path} -type d | head -50
```

**Package Manifest:**
```bash
cat {input-path}/package.json 2>/dev/null | head -100
```

**Key Files List:**
```bash
find {input-path} -type f \( -name "*.ts" -o -name "*.tsx" \) | head -100
```

**README:**
```bash
cat {input-path}/README.md 2>/dev/null | head -100
```

### 2.3 Identify Key Files

Categorize files by type:
- **Entry points**: index.ts, main.ts, app.ts
- **Config files**: *.config.ts, *.config.js
- **Core logic**: services/, lib/, core/
- **UI components**: components/, pages/, views/
- **Utilities**: utils/, helpers/, common/
- **Tests**: *.test.ts, *.spec.ts, __tests__/

### 2.4 Write Context File

**Path**: `.claude/PRPs/reviews/feature-context-{package-name}.md`

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
```
{tree output}
```

## Package Manifest
```json
{package.json content}
```

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

**PHASE_2_CHECKPOINT:**
- [ ] Context directory created
- [ ] Project rules extracted
- [ ] Package structure mapped
- [ ] Key files categorized
- [ ] Context file saved

---

## Phase 3: ANALYZE - Deep Code Review

**Reference**: Use context file at `.claude/PRPs/reviews/feature-context-{package-name}.md` for structure and guidelines.

**Strategy**: Read files selectively based on focus area, not exhaustively.

### 3.1 Code Quality Analysis

For each significant file (prioritize core logic, entry points), evaluate:

#### Architecture & Design
- [ ] Clear separation of concerns?
- [ ] Appropriate abstractions?
- [ ] Dependency injection patterns?
- [ ] Module boundaries well-defined?

#### Code Patterns
- [ ] Consistent naming conventions?
- [ ] DRY principle followed?
- [ ] Error handling patterns?
- [ ] Logging and observability?

#### Type Safety
- [ ] Explicit types (no implicit `any`)?
- [ ] Proper use of generics?
- [ ] Interface definitions complete?
- [ ] Null safety handled?

#### Testing
- [ ] Test coverage adequate?
- [ ] Unit tests for critical logic?
- [ ] Integration tests for flows?
- [ ] Edge cases covered?

#### Documentation
- [ ] Functions documented?
- [ ] Complex logic explained?
- [ ] API contracts clear?
- [ ] README up to date?

### 3.2 Product/Feature Analysis

Think like a product manager:

#### Current Features
- What does this package/feature do?
- Who are the users?
- What problems does it solve?

#### Feature Ideas
For each area, consider:
- What's missing that users would love?
- What friction could be reduced?
- What would make this 10x better?
- What would competitors have that's missing?

**Brainstorm categories:**
- User Experience improvements
- New capabilities
- Integration opportunities
- Automation possibilities
- Mobile/accessibility considerations

#### User Journey
- Map the current user flow
- Identify pain points
- Suggest improvements

### 3.3 Performance Analysis

#### Code-level Performance
- [ ] N+1 query patterns?
- [ ] Unnecessary async/await?
- [ ] Memory leaks (uncleared listeners, growing arrays)?
- [ ] Heavy computations in render/hot paths?
- [ ] Large bundle imports?

#### Architecture Performance
- [ ] Caching opportunities?
- [ ] Lazy loading possibilities?
- [ ] Database query optimization?
- [ ] API call batching?
- [ ] Pagination implemented where needed?

#### Metrics to Consider
- Load time implications
- Memory usage patterns
- Network request efficiency
- Rendering performance (if UI)

### 3.4 Security Analysis

#### Input Validation
- [ ] All user inputs validated?
- [ ] SQL/NoSQL injection prevention?
- [ ] XSS prevention?
- [ ] File upload restrictions?

#### Authentication & Authorization
- [ ] Auth checks on all protected routes?
- [ ] Token handling secure?
- [ ] Session management proper?
- [ ] RBAC implemented correctly?

#### Data Protection
- [ ] Sensitive data encrypted?
- [ ] Secrets in environment variables?
- [ ] PII handling compliant?
- [ ] Logging doesn't expose sensitive data?

#### API Security
- [ ] Rate limiting implemented?
- [ ] CORS configured properly?
- [ ] API keys properly protected?
- [ ] Request validation complete?

**PHASE_3_CHECKPOINT:**
- [ ] Code quality analyzed
- [ ] Product ideas generated
- [ ] Performance reviewed
- [ ] Security assessed

---

## Phase 4: PRIORITIZE - Organize Findings

### 4.1 Categorize by Impact

| Priority | Criteria |
|----------|----------|
| 🔴 Critical | Security vulnerabilities, data loss risks, breaking bugs |
| 🟠 High | Significant improvements, important missing features |
| 🟡 Medium | Nice-to-have improvements, optimization opportunities |
| 🔵 Low | Minor suggestions, future considerations |

### 4.2 Estimate Effort

For each finding, estimate:
- **Quick Win**: < 1 day
- **Small**: 1-3 days
- **Medium**: 1-2 weeks
- **Large**: > 2 weeks

### 4.3 Calculate ROI

Prioritize items with:
- High impact + Low effort = Do first
- High impact + High effort = Plan carefully
- Low impact + Low effort = Nice to have
- Low impact + High effort = Skip or defer

**PHASE_4_CHECKPOINT:**
- [ ] Findings prioritized
- [ ] Effort estimated
- [ ] ROI calculated

---

## Phase 5: REPORT - Generate Output

### 5.1 Create Report Directory

```bash
mkdir -p .claude/PRPs/reviews
```

### 5.2 Generate Report File

**Path**: `.claude/PRPs/reviews/feature-review-{package-name}-{date}.md`

```markdown
---
package: "{PACKAGE_PATH}"
reviewed: {ISO_TIMESTAMP}
focus: "{FOCUS_AREAS}"
reviewer: "AI Feature Review"
---

# Feature & Code Review: {PACKAGE_NAME}

**Path**: `{package-path}`
**Reviewed**: {date}
**Files Analyzed**: {count}

---

## Executive Summary

{3-5 sentences summarizing the overall state of the package, key strengths, and main improvement areas}

**Overall Health Score**: {1-10}/10

| Area | Score | Status |
|------|-------|--------|
| Code Quality | {N}/10 | {GOOD/NEEDS_WORK/CRITICAL} |
| Product Potential | {N}/10 | {GOOD/NEEDS_WORK/CRITICAL} |
| Performance | {N}/10 | {GOOD/NEEDS_WORK/CRITICAL} |
| Security | {N}/10 | {GOOD/NEEDS_WORK/CRITICAL} |

---

## 🎨 Code Quality Analysis

### Strengths
{What's done well}

### Areas for Improvement
{Specific issues with file references and recommendations}

### Pattern Recommendations
{Suggested patterns or refactoring opportunities}

---

## 💡 Product & Feature Ideas

### Quick Wins
{Features that can be added quickly with high impact}

### Strategic Features
{Larger features that would significantly improve the product}

### Innovation Ideas
{Creative ideas that could differentiate the product}

### User Experience Improvements
{UX enhancements that would delight users}

---

## ⚡ Performance Recommendations

### Immediate Optimizations
{Quick performance fixes}

### Architecture Improvements
{Larger performance improvements requiring refactoring}

### Monitoring Suggestions
{What to measure and track}

---

## 🔐 Security Findings

### Critical Issues
{Must fix immediately}

### High Priority
{Should fix soon}

### Recommendations
{Best practices to implement}

---

## 📋 Prioritized Action Items

### 🔴 Critical (Do Now)
| Item | Type | Effort | Impact |
|------|------|--------|--------|
| {description} | {code/product/perf/security} | {effort} | {impact} |

### 🟠 High Priority (This Sprint)
| Item | Type | Effort | Impact |
|------|------|--------|--------|

### 🟡 Medium Priority (Backlog)
| Item | Type | Effort | Impact |
|------|------|--------|--------|

### 🔵 Future Considerations
| Item | Type | Effort | Impact |
|------|------|--------|--------|

---

## 📊 Metrics to Track

{Suggested metrics to measure improvement}

---

## 🗺️ Suggested Roadmap

### Phase 1: Foundation (1-2 weeks)
{Critical fixes and quick wins}

### Phase 2: Enhancement (2-4 weeks)
{High priority improvements}

### Phase 3: Innovation (1-2 months)
{Strategic features and optimization}

---

*Generated by AI Feature Review*
*Report: `.claude/PRPs/reviews/feature-review-{package-name}-{date}.md`*
*Context: `.claude/PRPs/reviews/feature-context-{package-name}.md`*
```

**PHASE_5_CHECKPOINT:**
- [ ] Report file created
- [ ] All sections populated
- [ ] Actionable items prioritized

---

## Phase 6: OUTPUT - Present to User

```markdown
## ✅ Feature Review Complete

**Package**: `{PACKAGE_PATH}`
**Files Analyzed**: {count}
**Overall Health**: {score}/10

### Summary

{2-3 sentences about the review findings}

### Key Findings

| Area | Score | Top Finding |
|------|-------|-------------|
| 🎨 Code Quality | {N}/10 | {one-liner} |
| 💡 Product Ideas | {N}/10 | {one-liner} |
| ⚡ Performance | {N}/10 | {one-liner} |
| 🔐 Security | {N}/10 | {one-liner} |

### Action Items Summary

- 🔴 Critical: {count} items
- 🟠 High: {count} items
- 🟡 Medium: {count} items
- 🔵 Low: {count} items

### Artifacts

📄 **Full Report**: `.claude/PRPs/reviews/feature-review-{package-name}-{date}.md`
📋 **Context File**: `.claude/PRPs/reviews/feature-context-{package-name}.md`

### Next Steps

{Recommended immediate actions based on findings}
```

---

## Critical Reminders

1. **Be Thorough**: Read actual code, don't just scan file names

2. **Be Creative**: Think outside the box for product ideas

3. **Be Specific**: Reference specific files and line numbers

4. **Be Balanced**: Acknowledge good work, not just problems

5. **Be Actionable**: Every finding should have a recommendation

6. **Think Like Users**: Consider the end-user experience

7. **Consider Business**: Think about ROI and business impact

8. **Stay Current**: Reference modern best practices

---

## Token Optimization Strategy

### Context Caching

The context file (`.claude/PRPs/reviews/feature-context-{package-name}.md`) serves multiple purposes:

1. **Avoid redundant reads** - Package structure, guidelines, and file inventory extracted once
2. **Enable re-runs** - If context is recent, skip Phase 2 entirely
3. **Support multi-agent** - Same context file used by `/prp-feature-review-agents`

### Selective File Reading

| Focus Area | Files to Prioritize |
|------------|---------------------|
| `--focus code` | Entry points, core logic, utils |
| `--focus product` | UI components, user-facing code |
| `--focus performance` | Hot paths, database queries, API calls |
| `--focus security` | Auth, API handlers, input validation |
| `--focus all` | All of the above (read incrementally) |

### Token Budget

| Phase | Estimated Cost | Notes |
|-------|----------------|-------|
| Context Extraction | ~10-15K | One-time, cached |
| Code Analysis | ~20-40K | Depends on package size |
| Report Generation | ~5-10K | Summarization |
| **Total** | ~35-65K | Without optimization: ~80-120K |

**Savings**: ~40-50% by caching context and selective reading.

---

## Success Criteria

- **CONTEXT_CACHED**: Context file created and saved
- **CONTEXT_GATHERED**: Package structure and purpose understood
- **CODE_REVIEWED**: Significant files analyzed (not exhaustively)
- **IDEAS_GENERATED**: Creative product suggestions provided
- **PERFORMANCE_CHECKED**: Optimization opportunities identified
- **SECURITY_ASSESSED**: Vulnerabilities and risks documented
- **REPORT_CREATED**: Comprehensive markdown report saved
- **ACTIONS_PRIORITIZED**: Clear next steps with effort/impact

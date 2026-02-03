---
description: Generate technical design document from PRD as optional reference
agent: design
---

# PRP Design — Technical Design Document

PRD: $ARGUMENTS

## Mission

Generate design doc from PRD as **optional reference** (NOT in workflow). Workflow: PRD → Plan → Implement. Design is off-path reference for complex features only.

## Steps

1. **Load**: Read PRD (must be final merged, not draft), extract feature name
2. **Explore**: Find architecture/API/database/component patterns, integration points (actual code with file:line)
3. **Research**: Official docs (match versions), patterns, trade-offs, security, scalability
4. **Design**: System architecture ASCII diagram, API contracts, database schema SQL + migration, sequence diagrams (Mermaid), component hierarchy, data flow
5. **Decisions**: Table with Choice/Alternatives/Rationale/Trade-offs
6. **NFRs**: Performance (p50/p95/p99), Security (auth, validation, XSS/CSRF), Scalability (horizontal, async), Monitoring (metrics, logging, alerts)
7. **Migration**: Backward compatibility, data migration, feature flags, rollback
8. **Generate**: Save to `.claude/PRPs/designs/{feature}-design-opencode.md` (create dir: `mkdir -p .claude/PRPs/designs`)

   > **Note**: `-opencode` suffix for OpenCode design docs. Multiple tools can create designs for comparison.

## Template

```markdown
---
source-prd: .claude/PRPs/prds/{feature}-prd.md
created: {timestamp}
status: reference
tool: opencode
---

# {Feature} - Technical Design

## Overview
Problem/Solution/Complexity

## System Architecture
ASCII: components, data flow, dependencies
Components + External Dependencies lists

## API Contracts
{Method} {Path}: Request/Response schemas, Validation, Errors table

## Database Schema
New Tables SQL, Modified Tables SQL, Indexes SQL
Migration Strategy, Rollback Plan

## Sequence Diagrams
Mermaid diagrams for critical flows

## Component Hierarchy
Tree (if frontend), State Management, Data Fetching

## Data Flow
ASCII transformations, Input Validation layers, Error Handling layers

## Technical Decisions
| Decision | Choice | Alternatives | Rationale | Trade-offs |

## Security
Authentication, Authorization, Input Validation, Vulnerabilities

## Performance
Targets (p50/p95/p99), Caching, Database optimization, Bottlenecks

## Scalability
Horizontal scaling, Stateless design, Async processing, DB scaling

## Monitoring
Metrics, Logging, Alerts, Tracing

## Migration Strategy
Deployment steps, Feature flags, Rollback, Data migration

## Open Questions
- [ ] {Technical questions}

## References
Codebase: [{File}:{Line}] - {pattern}
External: [{Title}]({URL}) - {insight}

---
*Reference only. PRD → Plan → Implement is critical path.*
*Generated: {timestamp} | Tool: OpenCode*
```

## Output

Report: File path (REFERENCE ONLY), Summary (feature, complexity, components, API endpoints, DB changes), Key Decisions (top 3), Security, Performance Targets, Next Steps ("Reference only. Workflow: PRD → Plan → Implement. Design does NOT block workflow.")

## Success

- ARCHITECTURE_CLEAR, API_DEFINED, DATABASE_DESIGNED, SECURITY_ADDRESSED, PERFORMANCE_PLANNED, DECISIONS_DOCUMENTED, REFERENCE_ONLY

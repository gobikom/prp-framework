---
name: prp-design
description: Generate technical design document from PRD as optional reference (not in workflow)
metadata:
  short-description: Generate design doc from PRD
---

# PRP Design — Technical Design Document Generator

## Input

PRD file path: `$ARGUMENTS`

## Mission

Generate technical design document from PRD as **optional reference material** (NOT in critical workflow path).

Design Doc = Architecture blueprint. Simple features skip to Plan. Complex features can use this as reference.

**Workflow**: PRD → Plan → Implement (Design Doc is off-path reference only)

## Steps

1. **Load Context**: Read PRD, validate it's final merged version (no draft), extract feature name
2. **Explore Codebase**: Find architecture patterns, API conventions, database patterns, component patterns, integration points (use actual code with file:line refs)
3. **Research**: Official docs (match versions), architecture patterns, trade-offs, security (OWASP), scalability
4. **Design Architecture**:
   - System architecture ASCII diagram (components, data flow, dependencies)
   - API contracts (request/response schemas)
   - Database schema (SQL + migration strategy + rollback plan)
   - Sequence diagrams (Mermaid for critical flows)
   - Component hierarchy (if frontend)
   - Data flow diagram
5. **Technical Decisions**: Document decisions table with Choice, Alternatives, Rationale, Trade-offs
6. **Non-Functional Requirements**: Performance (targets p50/p95/p99), Security (auth, validation, XSS/CSRF), Scalability (horizontal scaling, async), Monitoring (metrics, logging, alerts)
7. **Migration Strategy**: Backward compatibility, data migration, feature flags, rollback plan
8. **Generate**: Save to `.claude/PRPs/designs/{feature}-design-codex.md` (create directory: `mkdir -p .claude/PRPs/designs`)

   > **Note**: Uses `-codex` suffix to identify Codex design docs. Multiple tools can create design docs for comparison.

## Design Doc Template

```markdown
---
source-prd: .claude/PRPs/prds/{feature}-prd.md
created: {timestamp}
status: reference
tool: codex
---

# {Feature} - Technical Design

## Overview
- Problem: {one-line}
- Solution: {one-line}
- Complexity: LOW/MEDIUM/HIGH

## System Architecture
{ASCII diagram: components, data flow, dependencies}

**Components**: {list with responsibilities}
**External Dependencies**: {list with purposes}

## API Contracts
### {Method} {Path}
Request: {schema}
Response: {schema}
Validation: {rules}
Errors: {table with status/code/description}

## Database Schema
### New Tables
{SQL CREATE statements}
### Modified Tables
{SQL ALTER statements}
### Indexes
{SQL CREATE INDEX statements}
**Migration Strategy**: {steps}
**Rollback Plan**: {steps}

## Sequence Diagrams
### {Flow Name}
{Mermaid diagram}

## Component Hierarchy
{Component tree if frontend}
**State Management**: {approach}
**Data Fetching**: {approach}

## Data Flow
{ASCII diagram: transformations}
**Input Validation**: {layers}
**Error Handling**: {layers}

## Technical Decisions
| Decision | Choice | Alternatives | Rationale | Trade-offs |
{Table rows}

## Security Considerations
- Authentication: {approach}
- Authorization: {approach}
- Input Validation: {where/how}
- Known Vulnerabilities: {mitigation}

## Performance
- Targets: p50/p95/p99
- Caching: {strategy, TTL, invalidation}
- Database: {indexes, queries, pooling}
- Bottlenecks: {mitigation}

## Scalability
- Horizontal Scaling: {approach}
- Stateless Design: {how}
- Async Processing: {what, queue/worker}
- Database Scaling: {replicas, sharding}

## Monitoring & Observability
- Metrics: {key metrics}
- Logging: {what, levels, format}
- Alerts: {thresholds}
- Tracing: {approach}

## Migration Strategy
- Deployment Steps: {ordered list}
- Feature Flags: {flags and purpose}
- Rollback Plan: {steps}
- Data Migration: {scripts, validation}

## Open Questions
- [ ] {Unresolved technical questions}

## References
**Codebase**: [{File}:{Line}]({path}) - {pattern}
**External**: [{Title}]({URL}) - {insight}

---
*Reference document only. PRD → Plan → Implement remains critical path.*
*Generated: {timestamp} | Tool: Codex*
```

## Output

Report:
- File: `.claude/PRPs/designs/{name}-design-codex.md` (REFERENCE ONLY)
- Summary: Feature, Complexity, Components count, API endpoints count, Database changes
- Key Design Decisions: top 3 with rationale
- Security Considerations: list
- Performance Targets: p95 latency, throughput
- Next Steps: "This is reference. Workflow: (1) Use design as reference (optional), (2) Create Plan from PRD, (3) Implement from Plan. Design does NOT block workflow."

## Success Criteria

- ARCHITECTURE_CLEAR: Components and data flow visualized
- API_DEFINED: Request/response contracts specified
- DATABASE_DESIGNED: Schema with migration strategy
- SECURITY_ADDRESSED: Auth, validation, vulnerabilities
- PERFORMANCE_PLANNED: Targets and optimization strategies
- DECISIONS_DOCUMENTED: Choices with rationale and trade-offs
- REFERENCE_ONLY: Clearly marked as support material

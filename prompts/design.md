# Design Document Generator

**Input**: `{ARGS}` (PRD file path)

---

## Mission

Generate technical design document from PRD as **optional reference material** (not in critical workflow path).

Design Doc = Architecture blueprint for complex features. Simple features can skip directly to Plan.

**Key Principle**: Design Doc is a **support tool**, not a gate. Workflow remains PRD → Plan → Implement.

---

## Phase 1: Load Context

1. **Read PRD**: Extract problem statement, solution approach, technical approach, constraints
2. **Validate PRD**: Must be final merged PRD (not draft). Check for `.claude/PRPs/prds/{name}-prd.md` (no suffix)
3. **Extract Feature Name**: Derive from PRD filename for design doc naming

---

## Phase 2: Explore Codebase

**Find existing patterns** to inform design decisions:

1. **Architecture Patterns**: Identify current project structure, module organization, dependency injection patterns
2. **API Conventions**: REST/GraphQL endpoints, request/response formats, authentication patterns
3. **Database Patterns**: ORM usage, migration patterns, query patterns, transaction handling
4. **Component Patterns** (if frontend): Component hierarchy, state management, routing patterns
5. **Integration Points**: External services, message queues, caching layers, storage

Document findings with **file:line references** to actual code.

---

## Phase 3: Research

**Technical research** for design decisions:

1. **Official Documentation**: For technologies mentioned in PRD (match project versions)
2. **Architecture Patterns**: Industry best practices for similar problems
3. **Trade-offs**: Performance vs maintainability, complexity vs flexibility
4. **Security Considerations**: OWASP guidelines, auth/authz patterns, data validation
5. **Scalability**: Caching strategies, database indexing, async processing

Format: `[URL] - KEY_INSIGHT - TRADE_OFF`

---

## Phase 4: Design Architecture

Create comprehensive technical design:

### 4.1 System Architecture

**ASCII Diagram** showing:
- Components and their responsibilities
- Data flow between components
- External dependencies
- Integration points

**Example:**
```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   Client    │─────▶│   API        │─────▶│  Database   │
│  (React)    │      │  (Fastify)   │      │ (Postgres)  │
└─────────────┘      └──────────────┘      └─────────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │    Redis     │
                     │   (Cache)    │
                     └──────────────┘
```

### 4.2 API Contracts

Define request/response schemas using project conventions:

**Example:**
```typescript
// POST /api/auth/login
Request: {
  email: string
  password: string
}

Response: {
  success: true
  data: {
    token: string
    user: UserDTO
  }
}
```

### 4.3 Database Schema

**New tables or schema changes:**
```sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  token TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_sessions_token ON sessions(token);
CREATE INDEX idx_sessions_user_id ON sessions(user_id);
```

**Migration strategy**: How to deploy without downtime

### 4.4 Sequence Diagrams

Critical user flows using Mermaid:

```mermaid
sequenceDiagram
    participant C as Client
    participant A as API
    participant D as Database
    participant R as Redis

    C->>A: POST /api/auth/login
    A->>D: SELECT user WHERE email
    D-->>A: User data
    A->>A: Verify password
    A->>D: INSERT session
    A->>R: SET session cache
    A-->>C: Return token
```

### 4.5 Component Hierarchy (Frontend)

If frontend changes:
```
App
├── AuthProvider
│   └── LoginPage
│       ├── LoginForm
│       └── ErrorBoundary
├── DashboardLayout
│   ├── Sidebar
│   └── MainContent
```

### 4.6 Data Flow

ASCII diagram showing data transformations:
```
Raw Input → Validation → Business Logic → Database → Response
```

---

## Phase 5: Technical Decisions

Document key decisions with rationale:

| Decision | Choice | Alternatives | Rationale | Trade-offs |
|----------|--------|--------------|-----------|------------|
| Auth mechanism | JWT in httpOnly cookie | Session store, OAuth | Stateless, scalable | Cannot invalidate before expiry |
| Token storage | Redis with TTL | Database | Fast lookup, auto-expire | Requires Redis |
| Password hash | bcrypt (cost 12) | argon2, scrypt | Industry standard, widely supported | Slower than alternatives |

---

## Phase 6: Non-Functional Requirements

### Performance
- Response time targets (p50, p95, p99)
- Throughput requirements
- Caching strategy
- Database query optimization

### Security
- Authentication/Authorization
- Input validation
- SQL injection prevention
- XSS prevention
- CSRF protection
- Rate limiting

### Scalability
- Horizontal scaling approach
- Database sharding (if needed)
- Caching layers
- Async processing
- Load balancing

### Monitoring
- Key metrics to track
- Logging strategy
- Error tracking
- Performance monitoring

---

## Phase 7: Migration Strategy

**If modifying existing feature:**

1. **Backward Compatibility**: How to support old and new versions
2. **Data Migration**: Scripts needed, rollback plan
3. **Feature Flags**: Gradual rollout strategy
4. **Rollback Plan**: How to revert if issues occur

---

## Phase 8: Generate Design Doc

**Output path**: `.claude/PRPs/designs/{feature}-design-other.md`

Create directory: `mkdir -p .claude/PRPs/designs`

> **Note**: Uses `-other` suffix to identify generic/Kimi design docs. Multiple tools can create design docs with different tool suffixes for comparison.

### Design Doc Template

```markdown
---
source-prd: .claude/PRPs/prds/{feature}-prd.md
created: {timestamp}
status: reference
tool: other
---

# {Feature Name} - Technical Design

## Overview

**Problem**: {One-line problem from PRD}
**Solution**: {One-line solution from PRD}
**Complexity**: {LOW/MEDIUM/HIGH}

## System Architecture

{ASCII diagram showing components and data flow}

**Components:**
- **{Component 1}**: {Responsibility}
- **{Component 2}**: {Responsibility}

**External Dependencies:**
- {Service 1}: {Purpose}
- {Service 2}: {Purpose}

## API Contracts

### Endpoint 1: {Method} {Path}

**Request:**
```typescript
{Request schema}
```

**Response:**
```typescript
{Response schema}
```

**Validation:**
- {Validation rule 1}
- {Validation rule 2}

**Error Cases:**
| Status | Error Code | Description |
|--------|------------|-------------|
| 400 | INVALID_INPUT | {Description} |
| 401 | UNAUTHORIZED | {Description} |

## Database Schema

### New Tables

```sql
{CREATE TABLE statements}
```

### Modified Tables

```sql
{ALTER TABLE statements}
```

### Indexes

```sql
{CREATE INDEX statements}
```

**Migration Strategy:**
1. {Step 1}
2. {Step 2}

**Rollback Plan:**
1. {Step 1}
2. {Step 2}

## Sequence Diagrams

### Flow 1: {Flow Name}

```mermaid
{Sequence diagram}
```

### Flow 2: {Flow Name}

```mermaid
{Sequence diagram}
```

## Component Hierarchy

{If frontend, show component tree}

**State Management:**
- {Approach and rationale}

**Data Fetching:**
- {Approach and rationale}

## Data Flow

{ASCII diagram showing data transformations}

**Input Validation:**
- {Layer 1}: {What validates}
- {Layer 2}: {What validates}

**Error Handling:**
- {Layer 1}: {How handles}
- {Layer 2}: {How handles}

## Technical Decisions

| Decision | Choice | Alternatives | Rationale | Trade-offs |
|----------|--------|--------------|-----------|------------|
| {Decision 1} | {Choice} | {Alternatives} | {Why} | {Trade-offs} |
| {Decision 2} | {Choice} | {Alternatives} | {Why} | {Trade-offs} |

## Security Considerations

**Authentication:**
- {Approach}

**Authorization:**
- {Approach}

**Input Validation:**
- {Where and how}

**Known Vulnerabilities:**
- {Vulnerability}: {Mitigation}

## Performance

**Targets:**
- p50: {target}
- p95: {target}
- p99: {target}

**Caching Strategy:**
- {What to cache}
- {TTL strategy}
- {Invalidation strategy}

**Database Optimization:**
- {Indexes}
- {Query patterns}
- {Connection pooling}

**Bottlenecks:**
- {Potential bottleneck 1}: {Mitigation}
- {Potential bottleneck 2}: {Mitigation}

## Scalability

**Horizontal Scaling:**
- {Approach}

**Stateless Design:**
- {How achieved}

**Async Processing:**
- {What runs async}
- {Queue/worker setup}

**Database Scaling:**
- {Read replicas}
- {Sharding strategy if needed}

## Monitoring & Observability

**Key Metrics:**
- {Metric 1}: {What it measures}
- {Metric 2}: {What it measures}

**Logging:**
- {What to log}
- {Log levels}
- {Structured logging format}

**Alerts:**
- {Alert 1}: {Threshold}
- {Alert 2}: {Threshold}

**Tracing:**
- {Distributed tracing approach if applicable}

## Migration Strategy

**Deployment Steps:**
1. {Step 1}
2. {Step 2}

**Feature Flags:**
- {Flag name}: {Purpose}

**Rollback Plan:**
1. {Step 1}
2. {Step 2}

**Data Migration:**
- {Scripts needed}
- {Validation checks}

## Open Questions

- [ ] {Technical question 1}
- [ ] {Technical question 2}

## References

**Codebase Patterns:**
- [{File}:{Line}]({path}) - {Pattern description}

**External Documentation:**
- [{Title}]({URL}) - {Key insight}

---

*This is a reference document. It does not block the workflow. PRD → Plan → Implement remains the critical path.*

*Generated: {timestamp}*
*Tool: Generic/Kimi*
```

---

## Phase 9: Output Summary

Report:

```markdown
## Design Doc Created

**File**: `.claude/PRPs/designs/{name}-design-other.md` (REFERENCE ONLY)

### Summary

**Feature**: {Name}
**Complexity**: {LOW/MEDIUM/HIGH}
**Components**: {Count}
**API Endpoints**: {Count}
**Database Changes**: {New tables + Modified tables}

### Key Design Decisions

1. {Decision 1}: {Choice} - {Rationale}
2. {Decision 2}: {Choice} - {Rationale}
3. {Decision 3}: {Choice} - {Rationale}

### Security Considerations

- {Consideration 1}
- {Consideration 2}

### Performance Targets

- p95 latency: {target}
- Throughput: {target}

### Next Steps

This is a **reference document**. Workflow continues as:

1. Use this design doc as reference (optional)
2. Create Plan from PRD: `/prp-plan .claude/PRPs/prds/{name}-prd.md`
3. Implement from Plan

**Design Doc does NOT block workflow** - implementer can reference it for architecture guidance.
```

---

## Success Criteria

- **ARCHITECTURE_CLEAR**: System components and data flow are visualized
- **API_DEFINED**: Request/response contracts are specified
- **DATABASE_DESIGNED**: Schema changes with migration strategy
- **SECURITY_ADDRESSED**: Auth, validation, and vulnerabilities considered
- **PERFORMANCE_PLANNED**: Targets and optimization strategies defined
- **DECISIONS_DOCUMENTED**: Key choices with rationale and trade-offs
- **REFERENCE_ONLY**: Clearly marked as support material, not workflow gate

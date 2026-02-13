# PRP Framework - คู่มือการใช้งาน

## สารบัญ

1. [เริ่มต้นใช้งาน](#เริ่มต้นใช้งาน)
2. [Commands Overview](#commands-overview)
3. [Development Workflow](#development-workflow)
4. [Marketing & Sales](#marketing--sales)
5. [AI Call Center / Chatbot](#ai-call-center--chatbot)
6. [Feature Review](#feature-review)
7. [Debugging & Issues](#debugging--issues)
8. [Automation](#automation)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)
11. [Updating & Re-install](#updating--re-install)

---

## เริ่มต้นใช้งาน

### การติดตั้ง

**วิธีที่ 1: Git Submodule** (สำหรับทีม)

```bash
git submodule add https://github.com/gobikom/prp-framework .prp
cd .prp && ./scripts/install.sh && cd ..
```

**วิธีที่ 2: Local Clone** (แนะนำ สำหรับ deploy Railway/Vercel)

```bash
git clone https://github.com/gobikom/prp-framework .prp
cd .prp && ./scripts/install.sh && cd ..
```

> Local clone ไม่ commit อะไรเข้า git — CI/CD สะอาด ไม่มี dangling symlinks

### การใช้งานเบื้องต้น

ใน Claude Code ให้พิมพ์ `/prp-` แล้วจะเห็นรายการ commands ทั้งหมด:

```bash
# Core Development Commands
/prp-core:plan        → วางแผน implementation
/prp-core:implement   → Execute plan
/prp-core:commit      → Commit changes
/prp-core:pr          → สร้าง Pull Request

# Marketing Commands
/prp-mkt:landing      → วิเคราะห์ landing page
/prp-mkt:pitch        → สร้าง pitch materials

# AI Bot Commands
/prp-bot:intent       → ออกแบบ intents
/prp-bot:flow         → ออกแบบ conversation flows
```

---

## Commands Overview

### หมวดหมู่ Commands (25 commands)

| Namespace | หมวด | Commands | จำนวน |
|-----------|------|----------|-------|
| `/prp-core:` | Development | prd, design, plan, implement, commit, pr, review, run-all | 8 |
| `/prp-core:` | Debug/Issue | debug, issue-investigate, issue-fix | 3 |
| `/prp-core:` | Review | feature-review, feature-review-agents, review-agents | 3 |
| `/prp-core:` | Automation | ralph, ralph-cancel | 2 |
| `/prp-mkt:` | Marketing | landing, demo, pitch, competitor | 4 |
| `/prp-bot:` | AI Bot | intent, flow, prompt-eng, voice-ux, integration | 5 |

### Artifact Naming Convention

ทุก artifacts ใช้ **Timestamp Format** เพื่อป้องกันการเขียนทับไฟล์เดิม:

```
{name}-{TIMESTAMP}.{type}.md

Format: YYYYMMDD-HHMM
Example: user-auth-20260210-1430.plan.md
```

**หา artifact ล่าสุด**:
```bash
ls -t .prp-output/plans/*.plan.md | head -1
```

---

## Development Workflow

### Flow พื้นฐาน

```
PRD → Design → Plan → Implement → Commit → PR → Review
```

### 1. `/prp-core:prd` - สร้าง Product Requirements Document

**เมื่อไหร่ใช้**: เมื่อต้องการกำหนด requirements ก่อนเริ่มพัฒนา

```bash
# Interactive mode
/prp-core:prd

# With description
/prp-core:prd "Add user authentication with JWT"
```

**Output**: `.prp-output/prds/drafts/{name}-prd-agents-{TIMESTAMP}.md`

---

### 2. `/prp-core:design` - สร้าง Design Document

**เมื่อไหร่ใช้**: สำหรับ features ที่ซับซ้อน ต้องการ architecture blueprint

```bash
# From PRD
/prp-core:design .prp-output/prds/auth-prd.md

# With description
/prp-core:design "Authentication system using JWT and refresh tokens"
```

**Output**: `.prp-output/designs/{name}-design-agents-{TIMESTAMP}.md`

---

### 3. `/prp-core:plan` - สร้าง Implementation Plan

**เมื่อไหร่ใช้**: ก่อนเริ่มเขียน code ทุกครั้ง

```bash
# Simple feature
/prp-core:plan "Add logout button to navbar"

# Complex feature
/prp-core:plan "Implement multi-tenant support"

# From design doc
/prp-core:plan --design .prp-output/designs/auth-design.md
```

**Output**: `.prp-output/plans/{name}-{TIMESTAMP}.plan.md`

**Plan ประกอบด้วย**:
- Tasks breakdown
- Validation steps
- Affected files
- Risk assessment

---

### 4. `/prp-core:implement` - Execute Plan

**เมื่อไหร่ใช้**: เมื่อมี plan พร้อมแล้ว

```bash
# Execute plan (find latest: ls -t .prp-output/plans/*.plan.md | head -1)
/prp-core:implement .prp-output/plans/logout-button-20260210-1430.plan.md
```

**กระบวนการ**:
1. อ่าน plan
2. Execute แต่ละ task
3. Validate (typecheck, lint, test, build)
4. Auto-fix ถ้า fail
5. สร้าง implementation report

**Output**: `.prp-output/reports/{plan-name}-report-{TIMESTAMP}.md`

---

### 5. `/prp-core:commit` - Commit Changes

**เมื่อไหร่ใช้**: หลัง implement เสร็จ พร้อม commit

```bash
# Auto-detect changes
/prp-core:commit

# With specific files
/prp-core:commit "auth files"

# With message hint
/prp-core:commit --message "Add JWT authentication"
```

**Features**:
- Smart file staging
- Conventional commit message
- Co-Authored-By header

---

### 6. `/prp-core:pr` - สร้าง Pull Request

**เมื่อไหร่ใช้**: พร้อม push และสร้าง PR

```bash
# Create PR
/prp-core:pr

# With title
/prp-core:pr --title "Add JWT authentication"
```

**PR ประกอบด้วย**:
- Summary จาก commits
- Test plan
- Change description

---

### 7. `/prp-core:review` - Review Pull Request

**เมื่อไหร่ใช้**: ต้องการ review PR

```bash
# Review specific PR
/prp-core:review 123

# Review current branch's PR
/prp-core:review
```

---

### 8. `/prp-core:run-all` - Full Workflow

**เมื่อไหร่ใช้**: ต้องการ automate ทั้ง workflow

```bash
# Full workflow from feature description
/prp-core:run-all "Add dark mode toggle"

# From existing plan
/prp-core:run-all --prp-path .prp-output/plans/dark-mode-plan.md

# Skip review
/prp-core:run-all "Add dark mode" --skip-review
```

**Flow**:
```
Create Branch → Plan → Implement → Commit → PR → Review
```

---

## Marketing & Sales

### 1. `/prp-mkt:landing` - Landing Page Optimizer

**เมื่อไหร่ใช้**: ต้องการปรับปรุง landing page

```bash
# วิเคราะห์ landing page ที่มี
/prp-mkt:landing --analyze https://your-site.com

# สร้าง content ใหม่
/prp-mkt:landing --generate --target "SMB"

# ปรับปรุงตาม feedback
/prp-mkt:landing --improve "need stronger CTA"
```

**Output**: `.prp-output/marketing/landing-{type}-{date}.md`

**วิเคราะห์**:
- Above the fold effectiveness
- Value proposition clarity
- CTA strength
- Trust signals
- SEO elements

---

### 2. `/prp-mkt:demo` - Demo Environment Manager

**เมื่อไหร่ใช้**: เตรียม demo ให้ลูกค้า

```bash
# Setup demo environment
/prp-mkt:demo --setup

# Reset to clean state
/prp-mkt:demo --reset

# Customize for prospect
/prp-mkt:demo --scenario "Acme Corp"

# Pre-demo checklist
/prp-mkt:demo --checklist
```

**Output**:
- `.prp-output/demos/demo-status-{date}.md`
- `.prp-output/demos/demo-script-{customer}.md`

**ครอบคลุม**:
- Environment setup
- Sample data
- Demo script
- Fallback plans

---

### 3. `/prp-mkt:pitch` - Pitch Materials Generator

**เมื่อไหร่ใช้**: เตรียม materials สำหรับ sales

```bash
# สร้าง pitch deck
/prp-mkt:pitch --deck

# สร้าง one-pager
/prp-mkt:pitch --one-pager

# สร้าง email templates
/prp-mkt:pitch --email

# สร้าง proposal
/prp-mkt:pitch --proposal --target "Enterprise"

# สร้างทั้งหมด
/prp-mkt:pitch --target "Healthcare"
```

**Output**:
- `.prp-output/marketing/pitch-deck-{date}.md`
- `.prp-output/marketing/one-pager-{date}.md`
- `.prp-output/marketing/email-templates-{date}.md`
- `.prp-output/marketing/proposal-{company}.md`

---

### 4. `/prp-mkt:competitor` - Competitive Analysis

**เมื่อไหร่ใช้**: ต้องการวิเคราะห์คู่แข่ง

```bash
# วิเคราะห์คู่แข่งเฉพาะ
/prp-mkt:competitor --analyze "Intercom, Zendesk"

# Feature comparison
/prp-mkt:competitor --compare

# Market positioning
/prp-mkt:competitor --positioning

# Sales battle cards
/prp-mkt:competitor --battlecard
```

**Output**:
- `.prp-output/marketing/competitive-analysis-{date}.md`
- `.prp-output/marketing/feature-comparison-{date}.md`
- `.prp-output/marketing/battle-cards-{date}.md`

**ครอบคลุม**:
- Competitor profiles
- Feature matrix
- Positioning map
- Battle cards for sales
- Objection handling

---

## AI Call Center / Chatbot

### 1. `/prp-bot:intent` - Intent Design

**เมื่อไหร่ใช้**: ออกแบบ intents สำหรับ chatbot/voicebot

```bash
# Design intents for use case
/prp-bot:intent --design "customer-support"

# Analyze existing intents
/prp-bot:intent --analyze

# Optimize intents
/prp-bot:intent --optimize

# Export schema
/prp-bot:intent --export
```

**Output**:
- `.prp-output/intents/intent-schema-{date}.json`
- `.prp-output/intents/intent-documentation-{date}.md`

**ครอบคลุม**:
- Intent hierarchy
- Training utterances (15-30 per intent)
- Entity definitions
- Overlap detection
- Test cases

---

### 2. `/prp-bot:flow` - Conversation Flow Design

**เมื่อไหร่ใช้**: ออกแบบ conversation flows

```bash
# Design new flow
/prp-bot:flow --design "order-status"

# Analyze existing flow
/prp-bot:flow --analyze

# Visualize flow
/prp-bot:flow --visualize

# Optimize for efficiency
/prp-bot:flow --optimize
```

**Output**: `.prp-output/flows/flow-{name}-{date}.md`

**ครอบคลุม**:
- Entry points
- Dialog turns
- Decision points
- Handoff triggers
- Error handling
- Flow diagrams (Mermaid)

---

### 3. `/prp-bot:prompt-eng` - Prompt Engineering

**เมื่อไหร่ใช้**: ออกแบบและ optimize prompts

```bash
# Design prompts for use case
/prp-bot:prompt-eng --design "support-bot"

# Test prompts
/prp-bot:prompt-eng --test

# Optimize prompts
/prp-bot:prompt-eng --optimize

# A/B testing setup
/prp-bot:prompt-eng --ab-test
```

**Output**:
- `.prp-output/prompts/system/{name}.md`
- `.prp-output/prompts/tests/{name}-tests.md`

**ครอบคลุม**:
- System prompt design
- Personality & tone
- Guardrails
- Examples (good & bad)
- Test suite
- Version control

---

### 4. `/prp-bot:voice-ux` - Voice UX Design

**เมื่อไหร่ใช้**: ออกแบบ voice experience

```bash
# Design voice flow
/prp-bot:voice-ux --design "inbound-call"

# Analyze existing
/prp-bot:voice-ux --analyze

# Generate scripts
/prp-bot:voice-ux --script

# Optimize IVR
/prp-bot:voice-ux --ivr
```

**Output**: `.prp-output/voice/flow-{name}-{date}.md`

**ครอบคลุม**:
- Voice-specific guidelines
- Call scripts
- IVR optimization
- Error handling
- Quality metrics

---

### 5. `/prp-bot:integration` - Integration Planning

**เมื่อไหร่ใช้**: วางแผน integration กับระบบอื่น

```bash
# Plan integration
/prp-bot:integration --plan "Salesforce"

# Design architecture
/prp-bot:integration --design

# Generate documentation
/prp-bot:integration --document

# Troubleshoot issues
/prp-bot:integration --troubleshoot
```

**Output**:
- `.prp-output/integrations/{system}-design.md`
- `.prp-output/integrations/{system}-documentation.md`

**ครอบคลุม**:
- CRM (Salesforce, HubSpot)
- Helpdesk (Zendesk, Freshdesk)
- Telephony (Twilio, Vonage)
- E-commerce (Shopify)
- Custom APIs

---

## Feature Review

### 1. `/prp-core:feature-review` - Single Agent Review

**เมื่อไหร่ใช้**: Review package/folder (เร็ว, ใช้ tokens น้อย)

```bash
# Review package
/prp-core:feature-review packages/web

# Focus เฉพาะด้าน
/prp-core:feature-review src/features/auth --focus security

# Focus options: code, product, performance, security, all
```

**Output**: `.prp-output/reviews/feature-review-{name}-{date}.md`

---

### 2. `/prp-core:feature-review-agents` - Multi-Agent Review

**เมื่อไหร่ใช้**: Review ครอบคลุม (ใช้หลาย agents)

```bash
# Full review (16 development agents)
/prp-core:feature-review-agents packages/web

# Quick review (3 agents)
/prp-core:feature-review-agents src/features/auth --quick

# Focus เฉพาะด้าน
/prp-core:feature-review-agents packages/api --focus security
```

**Agents ที่ใช้**:
- code-reviewer
- codebase-analyst
- product-ideas-agent
- performance-analyzer
- security-reviewer
- accessibility-reviewer
- dependency-analyzer
- observability-reviewer
- type-design-analyzer
- silent-failure-hunter

**Output**: `.prp-output/reviews/feature-review-{name}-agents-{date}.md`

---

### 3. `/prp-core:review-agents` - PR Review

**เมื่อไหร่ใช้**: Review Pull Request ด้วยหลาย agents

```bash
# Review specific PR
/prp-core:review-agents 123

# Review specific aspects
/prp-core:review-agents 123 tests errors

# All in parallel
/prp-core:review-agents 123 all parallel
```

**Output**: `.prp-output/reviews/pr-{number}-agents-review.md`

---

## Debugging & Issues

### 1. `/prp-core:debug` - Root Cause Analysis

**เมื่อไหร่ใช้**: หา root cause ของ bug

```bash
# Debug specific issue
/prp-core:debug "Login fails after session timeout"

# With error message
/prp-core:debug "TypeError: Cannot read property 'id' of undefined"
```

**Output**: `.prp-output/debug/rca-{issue-slug}-{TIMESTAMP}.md`

---

### 2. `/prp-core:issue-investigate` - Investigate Issue

**เมื่อไหร่ใช้**: วิเคราะห์ GitHub issue

```bash
# Investigate issue
/prp-core:issue-investigate 45

# Or with URL
/prp-core:issue-investigate https://github.com/org/repo/issues/45
```

**Output**: `.prp-output/issues/issue-{number}-{TIMESTAMP}.md`

---

### 3. `/prp-core:issue-fix` - Fix from Investigation

**เมื่อไหร่ใช้**: Implement fix จาก investigation

```bash
# Fix from investigation artifact (find latest: ls -t .prp-output/issues/issue-45*.md | head -1)
/prp-core:issue-fix 45
```

---

## Automation

### 1. `/prp-core:ralph` - Autonomous Loop

**เมื่อไหร่ใช้**: ให้ AI ทำงานต่อเนื่องจนเสร็จ

```bash
# Start Ralph with plan
/prp-core:ralph .prp-output/plans/feature-plan.md
```

**Ralph จะ**:
- Execute plan tasks
- Validate ทุก step
- Auto-fix failures
- Loop จน pass ทั้งหมด

---

### 2. `/prp-core:ralph-cancel` - Cancel Loop

**เมื่อไหร่ใช้**: หยุด Ralph loop

```bash
/prp-core:ralph-cancel
```

---

## Best Practices

### 1. เริ่มจาก Plan เสมอ

```bash
# ✅ Good
/prp-core:plan "Add feature X"
/prp-core:implement plan.md

# ❌ Bad
# เขียน code โดยไม่มี plan
```

### 2. ใช้ Feature Review ก่อน Major Changes

```bash
# Review existing code ก่อน refactor
/prp-core:feature-review-agents packages/legacy --focus code
```

### 3. Commit บ่อย, Commit เล็ก

```bash
# ✅ Good - commit หลังแต่ละ task
/prp-core:commit "Add auth middleware"
/prp-core:commit "Add login endpoint"

# ❌ Bad - commit ทุกอย่างพร้อมกัน
/prp-core:commit "Add entire auth system"
```

### 4. ใช้ --quick สำหรับ Quick Feedback

```bash
# Quick review ระหว่างทำงาน
/prp-core:feature-review-agents src/feature --quick

# Full review ก่อน PR
/prp-core:feature-review-agents src/feature
```

### 5. Token Optimization

```bash
# Single agent (ประหยัด tokens)
/prp-core:feature-review packages/small

# Multi-agent (ครอบคลุม แต่ใช้ tokens มาก)
/prp-core:feature-review-agents packages/critical
```

---

## Troubleshooting

### Command ไม่ทำงาน

1. ตรวจสอบว่ารัน `./scripts/install.sh` แล้ว
2. ตรวจสอบว่า symlinks ถูกต้อง:
   ```bash
   ls -la .claude/commands/prp-core/
   ```

### Plan ไม่ถูกต้อง

1. ให้ข้อมูลเพิ่มเติม:
   ```bash
   /prp-core:plan "Add X feature with Y approach using Z library"
   ```
2. ใช้ PRD ก่อน:
   ```bash
   /prp-core:prd "Add X feature"
   # Then use the PRD
   /prp-core:plan --prd .prp-output/prds/x-prd.md
   ```

### Implementation Fails

1. ตรวจสอบ validation errors ใน report
2. Fix manually และ re-run:
   ```bash
   /prp-core:implement plan.md --continue
   ```

### Agents ไม่ทำงาน

1. ตรวจสอบ `.claude/agents/` มี agent files:
   ```bash
   ls -la .claude/agents/
   ```
2. รัน install อีกครั้ง:
   ```bash
   cd .prp && ./scripts/install.sh
   ```

---

## Updating & Re-install

### อัพเดท Framework (Submodule + Symlinks)

```bash
cd .prp && git pull origin main && cd ..
# Command content อัพเดทอัตโนมัติผ่าน symlinks!
```

### อัพเดท Major Version (มีการเปลี่ยน directory structure)

```bash
cd .prp && git pull origin main && ./scripts/install.sh && cd ..
```

> **เมื่อไหร่ต้องรัน install.sh ใหม่**: เมื่อมีการเปลี่ยน directory structure, เพิ่ม commands/agents ใหม่, หรือแก้ไข .gitignore rules

### อัพเดท Framework (Hard Copy)

```bash
cd .prp && git pull origin main && ./scripts/sync.sh && cd ..
```

### ติดตั้งใหม่ทั้งหมด (Re-install)

ถ้า symlinks หรือ config มีปัญหา:

```bash
cd .prp && ./scripts/install.sh && cd ..
```

### Migrate Artifacts จาก Version เก่า

ถ้าเคยใช้ `.claude/PRPs/` หรือ `.ai-workflows/` (ก่อน v2.0):

```bash
cd .prp && ./scripts/migrate-artifacts.sh && cd ..
```

Script จะ copy artifacts เก่าไปยัง `.prp-output/` โดยไม่ลบต้นฉบับ

---

## Artifacts Location

```
.prp-output/
├── prds/              # Product Requirements Documents
│   └── drafts/        # Draft PRDs
├── designs/           # Design Documents
├── plans/             # Implementation Plans
│   └── completed/     # Archived plans
├── reports/           # Implementation Reports
├── reviews/           # Review Reports
│   └── feature-context-*.md  # Cached context
├── marketing/         # Marketing materials
├── intents/           # Chatbot intent schemas
├── flows/             # Conversation flows
├── prompts/           # AI prompts
│   ├── system/
│   ├── tests/
│   └── results/
├── voice/             # Voice UX designs
├── integrations/      # Integration docs
├── demos/             # Demo materials
└── issues/            # Issue investigations
```

---

## Quick Reference

### Development (`/prp-core:`)

| Task | Command |
|------|---------|
| สร้าง PRD | `/prp-core:prd "description"` |
| สร้าง Design | `/prp-core:design prd-path` |
| สร้าง Plan | `/prp-core:plan "description"` |
| Implement | `/prp-core:implement plan-path` |
| Commit | `/prp-core:commit` |
| Create PR | `/prp-core:pr` |
| Review PR | `/prp-core:review 123` |
| Full workflow | `/prp-core:run-all "description"` |

### Marketing (`/prp-mkt:`)

| Task | Command |
|------|---------|
| วิเคราะห์ Landing | `/prp-mkt:landing --analyze URL` |
| เตรียม Demo | `/prp-mkt:demo --setup` |
| สร้าง Pitch | `/prp-mkt:pitch --deck` |
| วิเคราะห์คู่แข่ง | `/prp-mkt:competitor --analyze "X, Y"` |

### AI Bot (`/prp-bot:`)

| Task | Command |
|------|---------|
| ออกแบบ Intents | `/prp-bot:intent --design "use-case"` |
| ออกแบบ Flow | `/prp-bot:flow --design "flow-name"` |
| Prompt Engineering | `/prp-bot:prompt-eng --design "bot-name"` |
| Voice UX | `/prp-bot:voice-ux --design "call-type"` |
| Integration | `/prp-bot:integration --plan "System"` |

### Review (`/prp-core:`)

| Task | Command |
|------|---------|
| Quick Review | `/prp-core:feature-review path` |
| Full Review | `/prp-core:feature-review-agents path` |
| PR Review | `/prp-core:review-agents 123` |

---

## Business Strategy Agents

นอกจาก development agents แล้ว ยังมี business strategy agents สำหรับ solopreneurs และ startups:

### Foundation: Business Context (ทำก่อน!)

| Agent | Purpose | ใช้เมื่อ |
|-------|---------|---------|
| **business-context-agent** | สร้าง centralized business context | **ก่อนใช้ business agents อื่นทั้งหมด** |

```
# เริ่มต้นครั้งแรก - สร้าง context
"ใช้ business-context-agent สร้าง business context แบบ hybrid"

# อัพเดท context เมื่อธุรกิจเปลี่ยน
"ใช้ business-context-agent อัพเดท context เพิ่ม customer segment ใหม่"

# ตรวจสอบความครบถ้วน
"ใช้ business-context-agent ตรวจสอบว่า context ครบถ้วนไหม"
```

**Output**: `.prp-output/BUSINESS-CONTEXT.md` - ไฟล์นี้จะถูกอ้างอิงโดย agents อื่นทั้งหมด

### Tier 1: Customer Acquisition (Critical)

| Agent | Purpose | ใช้เมื่อ |
|-------|---------|---------|
| **customer-discovery-agent** | Customer interview, persona, pain points | เริ่มทำ customer research |
| **sales-enablement-agent** | Objection handling, scripts, follow-up | เตรียม sales materials |
| **positioning-strategy-agent** | Market positioning, differentiation | กำหนด positioning |

### Tier 2: Growth & Scale

| Agent | Purpose | ใช้เมื่อ |
|-------|---------|---------|
| **content-marketing-agent** | Blog, social media, thought leadership | วางแผน content |
| **seo-sem-agent** | Keyword research, SEO, Google Ads | ทำ search marketing |
| **pricing-strategy-agent** | Pricing models, packaging, tiers | กำหนดราคา |

### Tier 3: Long-term Success

| Agent | Purpose | ใช้เมื่อ |
|-------|---------|---------|
| **customer-success-agent** | Onboarding, retention, churn prevention | ดูแลลูกค้าที่มี |
| **partnership-agent** | Partner identification, co-marketing | หา partners |

### Tier 4: Sales & Deals

| Agent | Purpose | ใช้เมื่อ |
|-------|---------|---------|
| **outreach-agent** | Cold email/LinkedIn sequences | ทำ B2B outreach |
| **proposal-agent** | Winning proposals, scope, pricing | เตรียม proposal |
| **case-study-agent** | สร้าง case study จาก customer success | สร้าง social proof |

### Tier 5: Operations & Brand

| Agent | Purpose | ใช้เมื่อ |
|-------|---------|---------|
| **financial-agent** | Unit economics, runway, cash flow | วิเคราะห์การเงิน |
| **automation-agent** | หา opportunities ในการ automate | เพิ่ม productivity |
| **personal-brand-agent** | LinkedIn presence, thought leadership | สร้าง personal brand |

### วิธีใช้ Business Agents

**Step 1: สร้าง Business Context ก่อน (ทำครั้งเดียว)**
```
"ใช้ business-context-agent สร้าง business context
สำหรับ AI chatbot service แบบ hybrid"
```

**Step 2: ใช้ agents อื่นโดยอ้างอิง context**
```
# ใน Claude Code - เรียกใช้ agent โดยตรง
"ใช้ customer-discovery-agent วิเคราะห์ target customer
อ้างอิง context จาก .prp-output/BUSINESS-CONTEXT.md"

# หรือแบบสั้น (ถ้า context มีอยู่แล้ว)
"ใช้ outreach-agent สร้าง cold email sequence"
```

**Step 3: อัพเดท context เมื่อธุรกิจเปลี่ยน**
```
"ใช้ business-context-agent อัพเดท context
เปลี่ยน pricing จาก 5,000 เป็น 8,000 บาท/เดือน"
```

---

*Document version: 1.4*
*Last updated: 2026-02-13*

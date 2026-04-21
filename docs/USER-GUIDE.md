# PRP Framework (Prompt-Run-Perfect) - คู่มือการใช้งาน

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

### หมวดหมู่ Commands (28 commands)

| Namespace | หมวด | Commands | จำนวน |
|-----------|------|----------|-------|
| `/prp-core:` | Development | prd, design, plan, implement, commit, pr, review, review-fix, run-all | 9 |
| `/prp-core:` | Debug/Issue | debug, issue-investigate, issue-fix | 3 |
| `/prp-core:` | Review | feature-review, feature-review-agents, review-agents | 3 |
| `/prp-core:` | Automation | ralph, ralph-cancel, rollback, cleanup | 4 |
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

# Fast-track mode (skip Research, Technical Design, Design UX)
/prp-core:plan "simple bug fix" --fast

# From design doc
/prp-core:plan --design .prp-output/designs/auth-design.md
```

**Output**: `.prp-output/plans/{name}-{TIMESTAMP}.plan.md`

**Plan ประกอบด้วย**:
- Plan lifecycle frontmatter (`status`, `runner`, `mode`)
- Tasks breakdown with MIRROR patterns
- Files to Change with Insert At hints (insertion location for UPDATE operations)
- Integration Points (new code → existing code hook locations with file:line)
- Testing Strategy (unit + integration + test data + performance benchmarks + edge cases)
- Technical Design (conditional — API contracts, DB schema, sequence diagrams, NFRs, migration) — เปิดใช้เมื่อ complexity=HIGH หรือมี API/DB changes
- Validation commands (6 levels, pre-filled with actual commands — no `{runner}` placeholders)
- Confidence Score (5 dimensions × 2 points = max 10)
- Acceptance criteria + Risk assessment

**Flags**:

| Flag | Description |
|------|-------------|
| `--fast` | Fast-track: skip Research, Technical Design, Design UX — compact plan for simple changes |
| `--no-interact` | ไม่ถามเรื่อง ambiguous requirements — ใช้ best judgment แทน |

---

### 4. `/prp-core:implement` - Execute Plan

**เมื่อไหร่ใช้**: เมื่อมี plan พร้อมแล้ว

```bash
# Execute plan (find latest: ls -t .prp-output/plans/*.plan.md | head -1)
/prp-core:implement .prp-output/plans/logout-button-20260210-1430.plan.md
```

**กระบวนการ (TDD Approach)**:
1. อ่าน plan + Testing Strategy
2. **เขียน test ก่อน (RED)** — สำหรับ functions/modules ใหม่ (skip สำหรับ config/wiring/schema tasks)
3. **Implement (GREEN)** — ตาม MIRROR pattern, รัน test จน pass
4. Validate ทันที (type-check หลังทุก file change)
5. Coverage check — enforce 90% on new/changed code
6. Full validation: lint, build, integration tests, security checks (SAST), performance regression, API contract
7. Auto-fix ถ้า fail
8. สร้าง implementation report + review context file (สร้างแม้ implementation fail ระหว่างทาง — เพื่อให้ review workflow ให้ feedback บน partial implementation ได้)

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
- **Pre-commit quality check (advisory)** — scan debug artifacts (TODO/FIXME, console.log), `any` types, quick validation
- **Plan-aware commit messages** — auto-detects completed plan matching current branch and enriches commit body with plan context (summary, task count)
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
- **Implementation report enrichment** — auto-detects `.prp-output/reports/*-report*.md` and includes summary, deviations, validation results in PR body
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

# Specific aspects only
/prp-core:review 123 security deps

# Performance + accessibility focus
/prp-core:review 123 perf a11y

# Incremental re-review (only changes since last review)
/prp-core:review 123 --since-last-review

# View review metrics summary
/prp-core:review --metrics
```

**Output**: `.prp-output/reviews/pr-{NUMBER}-review.md`

**11 Review Passes** (v2.1.0):
1. Code Quality & Guidelines (always)
2. Documentation Impact (almost always)
3. Security — OWASP Top 10 (always)
4. Dependency Analysis (always)
5. Test Coverage (when tests changed)
6. Comment Analysis (when comments added)
7. Error Handling (when error handling changed)
8. Type Design (when types changed)
9. **Performance** (conditional — auto-dispatched when DB/API/async patterns detected)
10. **Accessibility** (conditional — auto-dispatched when UI/frontend files changed)
11. Simplification (last, after other passes)

**Features**:
- **Conditional pass dispatch** — auto-detects file types and adds perf/a11y passes
- **Large PR strategy** — 4-tier risk categorization for PRs >500 lines
- **Result deduplication** — merges duplicate findings across passes
- **Review metrics** — appends JSONL to `review-metrics.jsonl`, `--metrics` shows aggregate
- **Incremental review** — `--since-last-review` reviews only changes since last review
- Appends "Review Outcome" to implementation report (if found)
- Updates Source PRD phase status

---

### 8. `/prp-core:review-fix` - Fix Review Issues

**เมื่อไหร่ใช้**: หลัง review แล้ว ต้องการให้ AI แก้ไข issues ทั้งหมดที่พบ

```bash
# Fix all issues (critical → high → medium → suggestion)
/prp-core:review-fix 123

# Fix only critical and high
/prp-core:review-fix 123 --severity critical,high

# Fix from current branch's PR
/prp-core:review-fix

# Fix from specific review artifact
/prp-core:review-fix .prp-output/reviews/pr-123-review-codex.md
```

**กระบวนการ**:
1. **Detect toolchain** — อ่าน lock file เพื่อหา package manager, ดึง validation commands จาก completed plan ที่ตรงกับ PR branch (รองรับ JS/TS, Python, Rust, Go)
2. Load review artifact จาก `.prp-output/reviews/pr-{NUMBER}-*review*.md` (รองรับทั้ง `prp-review-agents` และ `prp-review`)
3. ถ้ามีหลาย artifact (หลาย tool review) — แสดง list ให้เลือก, PR number extract อัตโนมัติจากชื่อไฟล์
4. Checkout PR branch
5. **TRIAGE** — แสดง fix plan ก่อนแก้: จำนวน issue ต่อ severity, list ทุก issue พร้อม file/description, group by file, แสดง issues ที่จะ skip (severity filter)
6. Fix issues เรียง Critical → High → Medium → Suggestion
7. Validate หลังแต่ละ severity batch (type-check + lint); **GATE** — full suite ต้องผ่านก่อน commit
8. Commit ด้วย safe staging (`git diff --name-only` + `git ls-files --others`) และ push ไปที่ PR branch
9. Comment สรุป fixed/skipped บน PR

**`--severity` options**:

| Flag | Issues ที่จะแก้ |
|------|----------------|
| `--severity critical` | Critical เท่านั้น |
| `--severity critical,high` | Critical + High |
| `--severity critical,high,medium` | ทุกอย่างยกเว้น Suggestion |
| ไม่ระบุ | ทุก severity (default) |

**Output**: `.prp-output/reviews/pr-{NUMBER}-fix-summary-{TIMESTAMP}.md`

---

### 9. `/prp-core:run-all` - Full Workflow

**เมื่อไหร่ใช้**: ต้องการ automate ทั้ง workflow — ตั้งแต่ issue ถึง merge

```bash
# Issue-driven: fetch issue → smart plan → implement → PR → review loop → merge → cleanup
/prp-core:run-all --issue 87 --merge

# Fully autonomous issue lifecycle (no questions asked)
/prp-core:run-all --issue 42 --merge --no-interact

# Issue-driven without auto-merge
/prp-core:run-all --issue 100

# Custom review-fix rounds (default: 5, target: 0 issues)
/prp-core:run-all --issue 55 --max-review-rounds 3 --merge

# Full workflow from feature description
/prp-core:run-all "Add dark mode toggle"

# From existing plan
/prp-core:run-all --prp-path .prp-output/plans/dark-mode-plan.md

# Skip review
/prp-core:run-all "Add dark mode" --skip-review

# No PR (just implement + commit)
/prp-core:run-all "Add dark mode" --no-pr

# Use ralph loop for implement step
/prp-core:run-all "Add dark mode" --ralph

# Resume from last failed step (requires state file)
/prp-core:run-all --resume

# Override review-fix severity (default: critical,high,medium,suggestion)
/prp-core:run-all "Add dark mode" --fix-severity critical,high

# Fully unattended (no user questions, uses best judgment)
/prp-core:run-all "Add dark mode" --no-interact

# Preview steps + estimated token cost (no execution)
/prp-core:run-all "Add dark mode" --dry-run
```

**Smart Plan Detection** (เมื่อใช้ `--issue`):
| Issue Scope | Action |
|-------------|--------|
| Small (score 0-1) | Skip plan — สร้าง stub plan อัตโนมัติ |
| Medium (score 2-3) | Fast-track plan |
| Large (score 4-5) | Full plan |

**Flow**:
```
[Issue] → Branch → [Smart Plan] → Implement → Commit → PR → Review/Fix Loop (→0 issues) → [Merge] → [Cleanup]
```

**Supported Flags**:

| Flag | Description |
|------|-------------|
| `--prp-path <path>` | Use existing plan, skip plan step |
| `--skip-plan` | Alias for `--prp-path` — prompts to select from available plans in `.prp-output/plans/` |
| `--fast` | Use fast-track plan mode (lighter codebase analysis, good for simple features) |
| `--ralph` | Use ralph loop instead of one-shot implement |
| `--ralph-max-iter N` | Set ralph max iterations (default: 10) |
| `--resume` | Resume from last failed step using saved state |
| `--skip-review` | Skip review step |
| `--no-pr` | Skip PR and review steps |
| `--fix-severity <levels>` | Override review-fix severity (default: `critical,high,medium,suggestion`) |
| `--no-interact` | ไม่ถามคำถาม — ใช้ best judgment สำหรับ requirements ที่คลุมเครือ, เลือก defaults อัตโนมัติ |
| `--dry-run` | Preview ทุก step ที่จะ run + estimated token cost โดยไม่ execute จริง |

**State Management**:

run-all สร้าง state file `.prp-output/state/run-all.state.md` เพื่อ track progress ระหว่าง run — ถ้า session crash สามารถใช้ `--resume` เพื่อ resume จาก step ที่ fail ได้ State file จะถูกลบอัตโนมัติเมื่อ workflow สำเร็จ

**Review-Fix Loop**:

หลัง review จะเข้า fix loop สูงสุด 5 รอบ — fix ทุก issues ที่ตรงกับ `FIX_SEVERITY` (default: critical, high, medium, suggestion ทุก level) เป้าหมายคือ 0 issues ก่อน merge ถ้า review-fix skip issues ทั้งหมดติดต่อกัน 2 รอบ workflow จะหยุด สร้าง escalation issue หรือ local escalation artifact และ report ว่าต้อง manual fix

**Token Optimization** (v2.1.0):

- Re-verify (Step 6.4) ใช้ `--since-last-review` สำหรับ incremental review เฉพาะเมื่อ review-fix ไม่ได้ skip issue ใด ๆ (`PENDING_SKIPPED=false`) — ถ้ามี skipped issues จะบังคับ full review พร้อม context เพื่อให้ skipped issues กลับมาในผล review
- `--dry-run` แสดง preview ทุก step พร้อม estimated token cost ก่อน execute

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

### 3. `/prp-core:cleanup` - Post-Merge Cleanup

**เมื่อไหร่ใช้**: หลัง PR ถูก merge แล้ว ต้องการลบ branch ทั้ง local และ remote

```bash
# Clean up current branch
/prp-core:cleanup

# Clean up specific branch
/prp-core:cleanup feat/user-auth

# Clean all merged branches
/prp-core:cleanup --all

# Preview batch cleanup (no deletion)
/prp-core:cleanup --all --dry-run
```

**กระบวนการ**:
1. Verify PR is merged via `gh` (ไม่ลบถ้า PR ยังไม่ merge)
2. **Archive artifacts** — manifest-first discovery (check `.prp-output/manifests/{BRANCH}.json` first, fallback to glob)
3. Delete local branch (`git branch -d`)
4. Delete remote branch (`git push origin --delete`)
5. Prune stale remote tracking refs (`git remote prune origin`)
6. **Remove orphaned state files** (`.prp-output/state/run-all.state.md` if references cleaned branch)

**Flags**:

| Flag | Description |
|------|-------------|
| `--all` | Clean up all local branches that are merged into main |
| `--dry-run` | Preview what would be deleted without executing |

**Safety**:
- Never deletes main/master branches
- Always verifies PR is merged before deleting
- `--dry-run` shows preview without executing
- Auto-switches off target branch if needed

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

## Permissions & Unattended Mode (Claude Code)

### ปัญหา: Permission Prompts ระหว่าง Workflow

เมื่อรัน PRP workflows (โดยเฉพาะ `run-all`) Claude Code จะถามขอ permission ทุกครั้งที่ใช้ tools เช่น edit file, run bash command ทำให้ workflow ถูกขัดจังหวะบ่อย

มี 3 ระดับในการจัดการ:

| ระดับ | วิธี | ความเสี่ยง | เหมาะกับ |
|-------|------|-----------|----------|
| **1. Allowlist (แนะนำ)** | `.claude/settings.json` | ต่ำ — allow เฉพาะ commands ที่ต้องใช้ | Dev ทั่วไป |
| **2. `--no-interact`** | PRP flag | ไม่มี — แค่ไม่ถาม questions ใน prompt | ทุกกรณี |
| **3. `--dangerously-skip-permissions`** | Claude CLI flag | สูง — ข้ามทุก permission | CI/CD only |

### วิธีที่ 1: Allowlist Permissions (แนะนำ)

มี 2 ระดับให้เลือกตาม trust level:

#### 1a. Scoped Config (แนะนำสำหรับ team)

จำกัด `rm` และ `sed` ให้ทำงานได้เฉพาะใน PRP directories:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(ls *)",
      "Bash(mkdir *)",
      "Bash(mv *)",
      "Bash(cp *)",
      "Bash(cat *)",
      "Bash(test *)",
      "Bash(find *)",
      "Bash(stat *)",
      "Bash(date *)",
      "Bash(head *)",
      "Bash(wc *)",
      "Bash(tree *)",
      "Bash(echo *)",
      "Bash(grep *)",
      "Bash(jq *)",
      "Bash(chmod *)",
      "Bash(ln *)",
      "Bash(mktemp*)",
      "Bash(rm -rf .prp-output/*)",
      "Bash(sed -i* .prp-output/*)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(bun *)",
      "Bash(pnpm *)",
      "Bash(yarn *)"
    ],
    "deny": []
  }
}
```

> **หมายเหตุ**: Config นี้ scope `rm` ให้ลบได้เฉพาะ PRP artifacts และ state files (`.prp-output/*`) และ scope `sed` ให้แก้ไขได้เฉพาะ artifacts เท่านั้น

#### 1b. Full Trust Config (solo dev / CI ที่ควบคุม environment เอง)

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(ls *)",
      "Bash(mkdir *)",
      "Bash(mv *)",
      "Bash(cp *)",
      "Bash(rm *)",
      "Bash(cat *)",
      "Bash(test *)",
      "Bash(find *)",
      "Bash(stat *)",
      "Bash(date *)",
      "Bash(head *)",
      "Bash(wc *)",
      "Bash(tree *)",
      "Bash(echo *)",
      "Bash(grep *)",
      "Bash(sed *)",
      "Bash(jq *)",
      "Bash(chmod *)",
      "Bash(ln *)",
      "Bash(mktemp*)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(bun *)",
      "Bash(pnpm *)",
      "Bash(yarn *)"
    ],
    "deny": []
  }
}
```

> **คำเตือน**: `Bash(rm *)` และ `Bash(sed *)` แบบ wildcard เต็มให้ AI ลบหรือแก้ไขไฟล์ใดก็ได้ในระบบ — ใช้เฉพาะ solo dev ที่เข้าใจความเสี่ยง หรือใน CI environment ที่ควบคุม

**เพิ่มเติมตาม tech stack:**

```json
// Python projects — เพิ่ม:
"Bash(python *)", "Bash(pytest *)", "Bash(mypy *)",
"Bash(ruff *)", "Bash(uv *)", "Bash(pip *)"

// Rust projects — เพิ่ม:
"Bash(cargo *)"

// Go projects — เพิ่ม:
"Bash(go *)"

// Integration tests — เพิ่ม:
"Bash(curl *)", "Bash(sleep *)", "Bash(kill *)"
```

### วิธีที่ 2: `--no-interact` Flag

`--no-interact` เป็น PRP flag ที่ป้องกัน orchestrator ถามคำถามผ่าน AskUserQuestion:

```bash
/prp-core:run-all "Add feature X" --no-interact
```

**ทำอะไร**: ไม่ถามเรื่อง ambiguous requirements, template selection, stale state — ใช้ best judgment แทน

**ไม่ทำอะไร**: ไม่ข้าม Claude Code permission prompts (ต้องใช้ร่วมกับวิธีที่ 1)

**แนะนำ**: ใช้ `--no-interact` + allowlist config ร่วมกันสำหรับ smooth workflow

### วิธีที่ 3: `--dangerously-skip-permissions` (CI/CD เท่านั้น)

```bash
claude --dangerously-skip-permissions "/prp-core:run-all Add feature X --no-interact"
```

> **คำเตือน**: Flag นี้ข้ามทุก permission prompt — ทุก tool call จะ execute โดยไม่ถาม รวมถึง destructive commands. ใช้เฉพาะใน isolated environment (CI/CD, containers, VMs) เท่านั้น

| สถานการณ์ | วิธีที่แนะนำ |
|-----------|-------------|
| Dev ใช้เอง, interactive | Allowlist + ไม่ต้อง `--no-interact` |
| Dev ใช้เอง, ปล่อยรัน | Allowlist + `--no-interact` |
| CI/CD pipeline | `--dangerously-skip-permissions` + `--no-interact` |
| Demo/showcase | Allowlist + `--no-interact` |

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

### Agent files แสดงเป็น `T` (typechange) ใน `.prp/adapters/claude-code-agents/`

เกิดจาก install.sh เวอร์ชันเก่ามี bug ด้าน bash `||`/`&&` operator precedence ทำให้ `rm` ถูกเรียกบน regular files แล้วสร้าง self-referencing symlinks แทนที่ใน `.prp/adapters/claude-code-agents/`

**แก้ไข** (3 ขั้นตอน):
```bash
# 1. Restore damaged files จาก git
git -C .prp checkout -- adapters/claude-code-agents/

# 2. Pull install.sh ที่ fix แล้ว
git -C .prp pull origin main

# 3. Re-install (auto-recover + migrate directory symlink)
cd .prp && ./scripts/install.sh && cd ..
```

`install.sh` เวอร์ชันใหม่จะ auto-detect และ restore typechanged files ทุกครั้งที่รัน รวมถึง migrate `.claude/agents` จาก directory symlink → real directory + per-file symlinks

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

> **ดูรายละเอียดทุก script:** [docs/SCRIPTS-REFERENCE.md](SCRIPTS-REFERENCE.md)

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
│   ├── feature-context-*.md  # Cached context (feature review)
│   └── pr-context-*.md       # Pre-generated PR context (implement/ralph)
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
| แก้ไข Review Issues | `/prp-core:review-fix 123` |
| Full workflow | `/prp-core:run-all "description"` |
| Full workflow (resume) | `/prp-core:run-all --resume` |
| Full workflow (ralph) | `/prp-core:run-all "description" --ralph` |
| Full workflow (unattended) | `/prp-core:run-all "description" --no-interact` |
| Post-merge cleanup | `/prp-core:cleanup` |
| Batch cleanup (all merged) | `/prp-core:cleanup --all` |

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

*Document version: 2.0*
*Last updated: 2026-03-16*

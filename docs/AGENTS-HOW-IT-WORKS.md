# Agents — หลักการทำงานฉบับเข้าใจง่าย

คู่มือนี้อธิบาย **หลักการออกแบบ สถาปัตยกรรม และวิธีใช้งาน** Agents ใน PRP Framework

---

## สารบัญ

1. [Agent คืออะไร?](#agent-คืออะไร)
2. [ทำไมต้องใช้หลาย Agents?](#ทำไมต้องใช้หลาย-agents)
3. [สถาปัตยกรรม Agent](#สถาปัตยกรรม-agent)
4. [หลักการออกแบบ 4 ข้อ](#หลักการออกแบบ-4-ข้อ)
5. [Agent Categories](#agent-categories)
6. [วิธีเรียกใช้ Agent 3 ระดับ](#วิธีเรียกใช้-agent-3-ระดับ)
7. [Multi-Agent Review 2 แบบ](#multi-agent-review-2-แบบ)
8. [Token Optimization — Context Sharing](#token-optimization--context-sharing)
9. [Best Practices](#best-practices)

---

## Agent คืออะไร?

Agent คือ **AI subprocess ที่ถูกออกแบบให้เชี่ยวชาญเรื่องเดียว**

เปรียบเทียบง่ายๆ:

| แบบเดิม | แบบ Agent |
|---------|-----------|
| หมอทั่วไป 1 คนตรวจทุกอย่าง | ส่งผู้ป่วยไปหาหมอเฉพาะทางแต่ละด้าน |
| AI ตัวเดียวทำทุกงาน | แต่ละ Agent เชี่ยวชาญเรื่องเดียว ผลลัพธ์ลึกกว่า |

**ตัวอย่าง**: แทนที่จะบอก AI ว่า "review code ให้หน่อย" แล้วได้คำตอบกว้างๆ → PRP ส่งงานไปให้:

- `code-reviewer` — ตรวจ code quality
- `security-reviewer` — หาช่องโหว่
- `performance-analyzer` — หา bottlenecks
- `silent-failure-hunter` — หา error ที่ถูก swallow

แต่ละตัวรู้ลึก รู้จริง เรื่องของตัวเอง

---

## ทำไมต้องใช้หลาย Agents?

### ปัญหาของ AI ตัวเดียว

```
Prompt: "review code ให้หน่อย"

AI ตัวเดียว:
├── ดู code style นิดหน่อย          ← ตื้น
├── พูดเรื่อง security กว้างๆ       ← ไม่ลึก
├── แนะนำ performance บ้าง         ← ไม่ครบ
└── ลืมดู error handling            ← ตกหล่น
```

### วิธีแก้: แบ่งงานให้ผู้เชี่ยวชาญ

```
Multi-Agent Review:
├── code-reviewer      → ตรวจ 200+ patterns, confidence score   ✅ ลึก
├── security-reviewer  → OWASP Top 10, attack vectors           ✅ ลึก
├── performance-analyzer → N+1 queries, memory leaks            ✅ ลึก
└── silent-failure-hunter → ทุก catch block, ทุก fallback       ✅ ลึก
```

**ผลลัพธ์**: ครอบคลุมกว่า ลึกกว่า แม่นกว่า

---

## สถาปัตยกรรม Agent

### Agent Definition File

แต่ละ agent เป็นไฟล์ `.md` ใน `adapters/claude-code-agents/`:

```yaml
---
name: code-reviewer          # ชื่อ agent
description: Reviews code... # อธิบายความเชี่ยวชาญ
model: sonnet                # model ที่ใช้ (sonnet / opus)
color: green                 # สีแสดงใน UI
---

# System Prompt ของ Agent
You are an expert code reviewer...

## สิ่งที่ต้องทำ
- ตรวจ guidelines compliance
- หา bugs

## สิ่งที่ห้ามทำ
- ไม่ comment เรื่อง performance
- ไม่ flag style preferences
```

### องค์ประกอบสำคัญ

| ส่วน | หน้าที่ |
|------|---------|
| `name` | ชื่อที่ Claude Code ใช้เรียก agent |
| `model` | กำหนด AI model (sonnet = เร็ว/ถูก, opus = ลึก/แพง) |
| `description` | บอก Claude Code ว่าเมื่อไหร่ควรใช้ agent นี้ |
| **System prompt** | สอน agent ให้โฟกัสเฉพาะเรื่อง + กำหนดสิ่งที่ห้ามทำ |
| **Output format** | กำหนดรูปแบบ report ที่ต้องส่งกลับ |

### ไฟล์ทั้งหมด (31 agents)

```
adapters/claude-code-agents/
├── code-reviewer.md            # Code quality
├── code-simplifier.md          # Simplify code
├── codebase-analyst.md         # Architecture analysis
├── codebase-explorer.md        # Find code patterns
├── comment-analyzer.md         # Comment accuracy
├── docs-impact-agent.md        # Update docs
├── pr-test-analyzer.md         # Test coverage
├── silent-failure-hunter.md    # Error handling
├── type-design-analyzer.md     # Type design
├── performance-analyzer.md     # Performance
├── security-reviewer.md        # Security (Opus)
├── accessibility-reviewer.md   # WCAG compliance
├── dependency-analyzer.md      # Package health
├── observability-reviewer.md   # Logging & metrics
├── product-ideas-agent.md      # Feature ideas (Opus)
├── web-researcher.md           # Web research
├── business-context-agent.md   # Business context (Opus)
├── customer-discovery-agent.md # Customer research
├── sales-enablement-agent.md   # Sales materials
├── positioning-strategy-agent.md
├── content-marketing-agent.md
├── seo-sem-agent.md
├── pricing-strategy-agent.md
├── customer-success-agent.md
├── partnership-agent.md
├── outreach-agent.md
├── proposal-agent.md
├── case-study-agent.md
├── financial-agent.md
├── automation-agent.md
└── personal-brand-agent.md
```

---

## หลักการออกแบบ 4 ข้อ

### 1. Single Responsibility — แต่ละ agent ทำเรื่องเดียว

ทุก agent มี **"สิ่งที่ห้ามทำ"** ชัดเจน เพื่อป้องกันไม่ให้ออกนอกขอบเขต:

| Agent | ทำ | ห้ามทำ |
|-------|-----|--------|
| `security-reviewer` | หา vulnerabilities, attack vectors | ไม่ comment code quality หรือ performance |
| `code-reviewer` | ตรวจ guidelines, หา bugs | ไม่ดู performance, ไม่ suggest refactoring ที่ไม่จำเป็น |
| `performance-analyzer` | หา bottlenecks, N+1 queries | ไม่ดู security, ไม่ comment style |
| `silent-failure-hunter` | หา swallowed errors, bad fallbacks | ไม่ report code quality issues |

**ทำไม?** → ถ้า agent ทำหลายเรื่อง ผลจะตื้น ถ้าโฟกัสเรื่องเดียว ผลจะลึก

### 2. Confidence Threshold — รายงานเฉพาะเรื่องที่แน่ใจ

`code-reviewer` จะ **ไม่รายงาน issue ที่ confidence ต่ำกว่า 80/100**:

```
Score 0-25   → Likely false positive      → ทิ้ง
Score 26-50  → Minor nitpick              → ทิ้ง
Score 51-79  → Valid but low-impact        → ทิ้ง
Score 80-89  → Important issue             → รายงาน ✅
Score 90-100 → Critical bug                → รายงาน ✅
```

`security-reviewer` ต้อง **แสดง attack vector ได้จริง** ถึงจะรายงาน:

```
❌ "ไม่มี rate limiting" (theoretical)
✅ "POST /login ไม่มี rate limit → brute force ได้ 1000 req/s → attack vector: ..." (exploitable)
```

**ทำไม?** → ลด noise ได้แต่ issue ที่สำคัญจริงๆ ไม่ต้องเสียเวลาอ่านเรื่องไม่สำคัญ

### 3. Model Selection — เลือก model ตามงาน

| Model | ใช้กับ Agent แบบ | เหตุผล | ค่าใช้จ่าย |
|-------|-------------------|--------|-----------|
| **Sonnet** | Technical / Pattern matching | เร็วกว่า, เพียงพอสำหรับตรวจ patterns | ถูกกว่า |
| **Opus** | Strategic / Creative / Security | ต้องการ deep reasoning | แพงกว่า |

**ตัวอย่าง:**

| Agent | Model | เหตุผล |
|-------|-------|--------|
| `code-reviewer` | Sonnet | Pattern matching → Sonnet เพียงพอ |
| `security-reviewer` | **Opus** | ต้อง trace attack vectors ลึกๆ |
| `product-ideas-agent` | **Opus** | ต้องการ creative thinking |
| `comment-analyzer` | Sonnet | เทียบ comment กับ code → ไม่ต้อง Opus |

**ทำไม?** → ใช้ Opus ทุก agent = แพงและช้า ใช้ Sonnet ที่ทำได้ = ประหยัดและเร็ว

### 4. Context Sharing — แชร์ context ไม่อ่านซ้ำ

```
❌ แบบเปลือง token (ไม่มี context sharing):

Agent 1 → อ่าน codebase      50K tokens
Agent 2 → อ่าน codebase      50K tokens  ← ซ้ำ!
Agent 3 → อ่าน codebase      50K tokens  ← ซ้ำ!
                              ─────────
                        Total: 150K tokens

✅ แบบ PRP (มี context sharing):

Orchestrator → สร้าง context file    10K tokens (ทำครั้งเดียว)
Agent 1 → อ่าน context file          10K tokens
Agent 2 → อ่าน context file          10K tokens
Agent 3 → อ่าน context file          10K tokens
                                     ─────────
                               Total: 40K tokens (ประหยัด 73%)
```

Context file เก็บอะไร?
- Project guidelines (จาก CLAUDE.md)
- Package structure
- Key files (entry points, config)
- File inventory

**ทำไม?** → ประหยัด **60-70% tokens** = ถูกลง + เร็วขึ้น

---

## Agent Categories

### ภาพรวม: 31 Agents, 3 กลุ่มใหญ่

```
┌─────────────────────────────────────────────────────┐
│                  PRP Framework Agents                │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Development (16 agents) ──── Technical agents      │
│  ├── Quality:     code-reviewer                     │
│  │                code-simplifier                   │
│  │                comment-analyzer                  │
│  ├── Analysis:    codebase-analyst                  │
│  │                codebase-explorer                 │
│  │                dependency-analyzer               │
│  ├── Security:    security-reviewer (Opus)          │
│  │                silent-failure-hunter              │
│  ├── Performance: performance-analyzer              │
│  ├── Testing:     pr-test-analyzer                  │
│  │                type-design-analyzer              │
│  ├── Docs:        docs-impact-agent                 │
│  │                accessibility-reviewer            │
│  ├── Ops:         observability-reviewer            │
│  ├── Research:    web-researcher                    │
│  └── Product:     product-ideas-agent (Opus)        │
│                                                     │
│  Foundation (1 agent) ──── รันก่อน business agents   │
│  └── business-context-agent (Opus)                  │
│                                                     │
│  Business (14 agents) ──── Strategy & sales         │
│  ├── Acquisition: customer-discovery                │
│  │                sales-enablement                  │
│  │                positioning-strategy              │
│  ├── Growth:      content-marketing                 │
│  │                seo-sem                           │
│  │                pricing-strategy                  │
│  ├── Retention:   customer-success                  │
│  │                partnership                       │
│  ├── Sales:       outreach                          │
│  │                proposal                          │
│  │                case-study                        │
│  └── Operations:  financial                         │
│                   automation                        │
│                   personal-brand                    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Development Agents — ใช้ตอนไหน?

| Agent | ใช้ตอน | ผลลัพธ์ |
|-------|--------|---------|
| `code-reviewer` | ก่อน commit, PR review | Issues + Verdict |
| `code-simplifier` | หลัง implement | Simplified code + commits |
| `comment-analyzer` | เพิ่ม comments แล้ว | Comment accuracy report |
| `codebase-analyst` | ทำความเข้าใจ codebase | Architecture doc with file:line |
| `codebase-explorer` | หา code patterns | File locations + patterns |
| `dependency-analyzer` | Security audit, updates | CVEs, outdated packages |
| `security-reviewer` | ก่อน deploy, PR review | Vulnerabilities + attack vectors |
| `silent-failure-hunter` | แก้ error handling | Swallowed errors report |
| `performance-analyzer` | Optimization | Bottlenecks + fixes |
| `pr-test-analyzer` | PR review | Test coverage gaps |
| `type-design-analyzer` | TypeScript review | Type quality scores |
| `docs-impact-agent` | หลัง code changes | Updated docs (commits ให้) |
| `accessibility-reviewer` | UI review | WCAG compliance report |
| `observability-reviewer` | Production readiness | Logging/metrics gaps |
| `web-researcher` | ต้องการข้อมูลจาก web | Research summary |
| `product-ideas-agent` | Product planning | Feature ideas + UX improvements |

### Business Agents — ใช้ตามลำดับ Stage

```
Stage 1: เริ่มต้น
└── business-context-agent    ← ทำก่อนเสมอ!

Stage 2: หาลูกค้า (0 → 1)
├── customer-discovery        ← เข้าใจ target
├── positioning-strategy      ← กำหนด positioning
└── pricing-strategy          ← กำหนดราคา

Stage 3: ขาย
├── outreach                  ← Cold email/LinkedIn
├── sales-enablement          ← Scripts, objection handling
└── proposal                  ← สร้าง proposal

Stage 4: Scale (1 → 10)
├── content-marketing         ← Inbound content
├── seo-sem                   ← Organic + paid traffic
├── customer-success          ← Onboarding, retention
└── case-study                ← Social proof

Stage 5: Optimize
├── financial                 ← Unit economics
├── automation                ← Process automation
├── partnership               ← Channel partnerships
└── personal-brand            ← LinkedIn, thought leadership
```

---

## วิธีเรียกใช้ Agent 3 ระดับ

### ระดับ 1: เรียกตรง (Manual)

พิมพ์ prompt แล้วระบุชื่อ agent:

```
"ใช้ security-reviewer review code ใน src/api/"

"ใช้ customer-discovery-agent สร้าง persona สำหรับ e-commerce SMB"

"ใช้ code-reviewer ตรวจ PR diff"
```

Claude Code จะ spawn agent ที่ตรงกับชื่อโดยอัตโนมัติ

**เหมาะกับ**: ต้องการใช้ agent เฉพาะตัว, งานเฉพาะทาง

### ระดับ 2: ผ่าน Commands (Semi-auto)

Commands จะ **เลือก + จัดการ agents ให้อัตโนมัติ**:

```bash
# PR Review — 7 agents ตรวจ PR diff
/prp-core:prp-review-agents 163

# Feature Review — 10 agents ตรวจทั้ง package
/prp-core:prp-feature-review-agents packages/web

# Feature Review แบบ quick (3 agents)
/prp-core:prp-feature-review-agents src/api --quick

# Feature Review เฉพาะด้าน
/prp-core:prp-feature-review-agents packages/web --focus security
```

**เหมาะกับ**: ต้องการ review ครบทุกด้าน, ให้ระบบเลือก agents ให้

### ระดับ 3: ผ่าน Workflow (Full-auto)

Agents ถูกเรียกเป็นส่วนหนึ่งของ workflow ทั้งหมด:

```bash
# Full workflow: Plan → Implement → Review → PR
/prp-core:prp-core-run-all

# Autonomous loop จนผ่าน validation
/prp-core:prp-ralph
```

**เหมาะกับ**: ต้องการให้ AI ทำตั้งแต่ต้นจนจบ

---

## Multi-Agent Review 2 แบบ

PRP มี multi-agent review 2 แบบที่ต่างกัน:

### แบบ 1: `prp-review-agents` — รีวิว PR

**เป้าหมาย**: ตรวจ diff ก่อน merge

```
Flow:

  PR #163 (diff)
       │
       ▼
  ┌─── Phase 0: เช็ค pre-generated context ───┐
  │  มี context file? → ใช้เลย (ประหยัด token) │
  │  ไม่มี? → ดึงจาก gh pr diff               │
  └────────────────────────────────────────────┘
       │
       ▼
  ┌─── Agents (เลือกตาม changed files) ────────┐
  │  1. code-reviewer        ← รันเสมอ         │
  │  2. docs-impact-agent    ← เกือบเสมอ       │
  │  3. pr-test-analyzer     ← ถ้า test changed │
  │  4. comment-analyzer     ← ถ้า comments เพิ่ม│
  │  5. silent-failure-hunter ← ถ้า error handling│
  │  6. type-design-analyzer ← ถ้า types changed │
  │  7. code-simplifier      ← รันท้ายสุด       │
  └────────────────────────────────────────────┘
       │
       ▼
  ┌─── Output ─────────────────────────────────┐
  │  Verdict: READY TO MERGE / NEEDS FIXES     │
  │  → บันทึก .prp-output/reviews/             │
  │  → โพสต์ comment ลง GitHub PR              │
  │  → อัพเดท implementation report            │
  └────────────────────────────────────────────┘
```

**Agents 7 ตัว** เน้น code change quality

### แบบ 2: `prp-feature-review-agents` — รีวิว Package

**เป้าหมาย**: ตรวจสุขภาพโดยรวมของ feature/package

```
Flow:

  packages/web (ทั้ง folder)
       │
       ▼
  ┌─── Phase 1: Extract Context ───────────────┐
  │  อ่าน CLAUDE.md + structure + key files     │
  │  → สร้าง context file (ทำครั้งเดียว)        │
  └────────────────────────────────────────────┘
       │
       ▼
  ┌─── Phase 2: เลือก Agents ─────────────────┐
  │  มี .tsx/.jsx?     → เพิ่ม accessibility    │
  │  มี package.json?  → เพิ่ม dependency       │
  │  เป็น TypeScript?  → เพิ่ม type-design      │
  └────────────────────────────────────────────┘
       │
       ▼
  ┌─── Phase 3: รัน Agents (สูงสุด 10 ตัว) ───┐
  │  Core:                                      │
  │    code-reviewer                            │
  │    codebase-analyst                         │
  │    silent-failure-hunter                    │
  │  Domain:                                    │
  │    product-ideas-agent                      │
  │    performance-analyzer                     │
  │    security-reviewer                        │
  │    accessibility-reviewer (ถ้ามี UI)        │
  │    dependency-analyzer (ถ้ามี package.json) │
  │    observability-reviewer                   │
  │    type-design-analyzer (ถ้า TypeScript)    │
  └────────────────────────────────────────────┘
       │
       ▼
  ┌─── Phase 4-5: Score + Report ──────────────┐
  │  Health Score: 7.5/10                       │
  │  ┌────────────────────────────────────┐     │
  │  │ Code Quality    8/10  ✅           │     │
  │  │ Security        6/10  ⚠️           │     │
  │  │ Performance     8/10  ✅           │     │
  │  │ Accessibility   7/10  ✅           │     │
  │  │ Dependencies    9/10  ✅           │     │
  │  │ Observability   6/10  ⚠️           │     │
  │  │ Product Ideas   8/10  ✅           │     │
  │  └────────────────────────────────────┘     │
  │  → บันทึก .prp-output/reviews/             │
  │  → Action items: Immediate / Short / Long   │
  └────────────────────────────────────────────┘
```

**Agents 10 ตัว** เน้น holistic review

### เปรียบเทียบ

| | `prp-review-agents` | `prp-feature-review-agents` |
|---|---|---|
| **Scope** | PR diff เท่านั้น | ทั้ง package/folder |
| **เมื่อไหร่ใช้** | ก่อน/ระหว่าง merge PR | ประเมินสุขภาพ feature |
| **Agents** | 7 ตัว (code change focus) | 10 ตัว (holistic) |
| **Output** | Verdict + PR comment | Health Score + Report |
| **โพสต์ GitHub** | ใช่ (PR comment) | ไม่ (local report) |
| **Token cost** | ~60-100K | ~60-200K |
| **Quick mode** | ไม่มี | `--quick` (3 agents) |
| **Focus mode** | เลือก aspects ได้ | `--focus` เลือกด้านได้ |

**ใช้ร่วมกัน**: Feature review ตอนพัฒนา → PR review ตอนจะ merge

---

## Token Optimization — Context Sharing

### ปัญหา: Agents อ่าน codebase ซ้ำ

ถ้ามี 10 agents แต่ละตัวอ่าน codebase เอง = **อ่านซ้ำ 10 ครั้ง**

### วิธีแก้: Orchestrator Pattern

```
┌──────────────────────────────────┐
│          Orchestrator            │
│  (prp-review-agents command)    │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Phase 1: Extract Context Once  │
│                                  │
│  อ่าน:                          │
│  ├── CLAUDE.md (guidelines)     │
│  ├── Package structure          │
│  ├── Key files (entry points)   │
│  └── File inventory             │
│                                  │
│  เขียน → context-file.md        │
└──────────────┬───────────────────┘
               │
    ┌──────────┼──────────┐
    ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐
│Agent 1 │ │Agent 2 │ │Agent 3 │
│อ่าน    │ │อ่าน    │ │อ่าน    │
│context │ │context │ │context │
│file    │ │file    │ │file    │
└────────┘ └────────┘ └────────┘
```

### ผลลัพธ์

| | ไม่มี Context Sharing | มี Context Sharing |
|---|---|---|
| **10 agents** | ~500K tokens | ~150-200K tokens |
| **3 agents (quick)** | ~150K tokens | ~60-80K tokens |
| **ประหยัด** | — | **60-70%** |

### Context File เก็บที่ไหน?

```
.prp-output/reviews/
├── feature-context-{package-name}.md    ← Feature review context
├── pr-context-{branch-name}.md          ← PR review context
├── pr-{number}-agents-review.md         ← Review results
└── feature-review-{pkg}-agents-{date}.md ← Feature review results
```

---

## Best Practices

### 1. เลือก Agent ให้ถูก

| ถ้าต้องการ... | ใช้ Agent | ระดับ |
|--------------|-----------|-------|
| Review PR ก่อน merge | `/prp-review-agents <pr>` | Command |
| ประเมินสุขภาพ feature | `/prp-feature-review-agents <path>` | Command |
| ตรวจ security เฉพาะ | `security-reviewer` | Manual |
| หาลูกค้า | `customer-discovery-agent` | Manual |
| สร้าง proposal | `proposal-agent` | Manual |
| เข้าใจ codebase | `codebase-analyst` | Manual |

### 2. Combine Agents ให้ได้ผลดี

**Development chains:**
```
code-reviewer → code-simplifier → comment-analyzer
security-reviewer → silent-failure-hunter → dependency-analyzer
codebase-explorer → codebase-analyst → performance-analyzer
```

**Business chains:**
```
business-context-agent → customer-discovery → positioning-strategy
outreach → sales-enablement → proposal
content-marketing → seo-sem → personal-brand
```

### 3. เริ่มจาก Foundation

**สำหรับ Development**: ใช้ `code-reviewer` ก่อนเสมอ → แล้วค่อยเพิ่ม specialist agents

**สำหรับ Business**: ใช้ `business-context-agent` ก่อนเสมอ → สร้าง BUSINESS-CONTEXT.md → agents อื่นอ่านจากไฟล์นี้

### 4. ใช้ Quick Mode เมื่อเวลาจำกัด

```bash
# Full review: 10 agents, ~200K tokens
/prp-feature-review-agents packages/web

# Quick review: 3 agents, ~80K tokens
/prp-feature-review-agents packages/web --quick
```

### 5. ใช้ Focus Mode เมื่อรู้ว่าต้องการอะไร

```bash
# ตรวจ security อย่างเดียว
/prp-feature-review-agents packages/api --focus security

# ตรวจ accessibility อย่างเดียว
/prp-feature-review-agents packages/ui --focus a11y

# ตรวจหลายด้าน
/prp-feature-review-agents packages/core --focus "code security perf"
```

---

## สรุปหลักการ

| หลักการ | ทำอะไร | ทำไม |
|---------|--------|------|
| **Single Responsibility** | 1 agent = 1 ความเชี่ยวชาญ | ผลลัพธ์ลึกและแม่นกว่า |
| **Confidence Threshold** | รายงานเฉพาะ ≥80 confidence | ลด noise, ได้แต่ issue สำคัญ |
| **Model Selection** | Sonnet=technical, Opus=strategic | ประหยัดค่าใช้จ่าย + เร็วขึ้น |
| **Context Sharing** | แชร์ context file ระหว่าง agents | ประหยัด 60-70% tokens |
| **Orchestrator Pattern** | Commands จัดการ agents ให้ | ใช้งานง่าย ไม่ต้องเลือกเอง |

---

*Document version: 1.0*
*Last updated: 2026-03-13*

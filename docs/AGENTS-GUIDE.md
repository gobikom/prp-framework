# Agents Guide - คู่มือการใช้งาน Agents

คู่มือนี้อธิบายวิธีใช้งาน 31 agents ใน PRP Framework พร้อม strategy สำหรับ solopreneurs และ startups

---

## สารบัญ

1. [ภาพรวม Agents](#ภาพรวม-agents)
2. [Development Agents](#development-agents-16-agents)
3. [Business Strategy Agents](#business-strategy-agents-14-agents)
4. [Strategy Workflows](#strategy-workflows)
5. [Use Cases](#use-cases)
6. [Best Practices](#best-practices)

---

## ภาพรวม Agents

### จำนวน Agents ทั้งหมด: 31

| Category | Count | Model | Purpose |
|----------|-------|-------|---------|
| Development | 16 | Sonnet/Opus | Code review, analysis, testing |
| **Foundation** | **1** | **Opus** | **Centralized business context** |
| Business Strategy | 8 | Opus | Customer acquisition, growth |
| Sales & Deals | 3 | Opus | Outreach, proposals, case studies |
| Operations & Brand | 3 | Opus | Finance, automation, personal brand |

### Model Selection

| Model | ใช้กับ | ทำไม |
|-------|--------|------|
| **Opus** | Strategic agents | ต้องการ reasoning ลึก, creative thinking |
| **Sonnet** | Technical agents | เร็วกว่า, ถูกกว่า, เพียงพอสำหรับ pattern matching |

---

## Development Agents (16 agents)

### Code Quality

| Agent | Purpose | เมื่อไหร่ใช้ |
|-------|---------|-------------|
| **code-reviewer** | Review code quality, patterns | ก่อน commit, PR review |
| **code-simplifier** | Simplify complex code | หลัง implement, refactoring |
| **comment-analyzer** | ตรวจสอบ comments accuracy | Documentation review |

**Workflow: Code Review**
```
code-reviewer → code-simplifier → comment-analyzer
```

### Code Analysis

| Agent | Purpose | เมื่อไหร่ใช้ |
|-------|---------|-------------|
| **codebase-analyst** | Deep analysis, architecture | เข้าใจ codebase ใหม่ |
| **codebase-explorer** | Find files, patterns | ค้นหา code |
| **dependency-analyzer** | Analyze dependencies | Security audit, updates |

**Workflow: Codebase Understanding**
```
codebase-explorer → codebase-analyst → dependency-analyzer
```

### Security & Performance

| Agent | Purpose | เมื่อไหร่ใช้ |
|-------|---------|-------------|
| **security-reviewer** (Opus) | OWASP vulnerabilities | Security audit, PR review |
| **performance-analyzer** | Performance bottlenecks | Optimization |
| **silent-failure-hunter** | Find hidden errors | Error handling review |

**Workflow: Security Audit**
```
security-reviewer → silent-failure-hunter → dependency-analyzer
```

### Testing & Types

| Agent | Purpose | เมื่อไหร่ใช้ |
|-------|---------|-------------|
| **pr-test-analyzer** | Analyze test coverage | PR review |
| **type-design-analyzer** | Type system design | TypeScript/type review |

### Documentation & Accessibility

| Agent | Purpose | เมื่อไหร่ใช้ |
|-------|---------|-------------|
| **docs-impact-agent** | Update affected docs | หลัง code changes |
| **accessibility-reviewer** | A11y compliance | UI review |

### Observability & Research

| Agent | Purpose | เมื่อไหร่ใช้ |
|-------|---------|-------------|
| **observability-reviewer** | Logging, monitoring | Production readiness |
| **web-researcher** | Research topics online | Need external info |

### Product Ideas

| Agent | Purpose | เมื่อไหร่ใช้ |
|-------|---------|-------------|
| **product-ideas-agent** (Opus) | Feature ideas, UX improvements | Product planning |

---

## Foundation Agent (1 agent)

### business-context-agent (Opus)

**Purpose**: สร้างและ maintain centralized business context เป็น foundation ให้ business agents ทั้งหมด

**ทำไมต้องใช้**:
- ไม่ต้องพิมพ์ context ซ้ำทุกครั้งที่ใช้ agent
- ทุก agent ใช้ข้อมูลเดียวกัน = output ที่ consistent
- Track การเปลี่ยนแปลงของธุรกิจได้

**Modes**:

| Mode | ใช้เมื่อ |
|------|---------|
| Extract | ดึง context จาก CLAUDE.md, README, files ที่มี |
| Interview | สร้าง context ใหม่ผ่านการถาม-ตอบ |
| Hybrid | Extract ก่อน แล้วถามเฉพาะส่วนที่ขาด (แนะนำ) |
| Update | อัพเดท context ที่มีอยู่ |
| Validate | ตรวจสอบความครบถ้วน |

**Prompt Examples**:
```
"ใช้ business-context-agent สร้าง business context
สำหรับ AI chatbot service แบบ hybrid (extract ก่อนแล้วถามเพิ่ม)"

"ใช้ business-context-agent ดึง context จาก CLAUDE.md และ README"

"ใช้ business-context-agent อัพเดท context
เพิ่ม customer segment ใหม่: Enterprise healthcare"

"ใช้ business-context-agent ตรวจสอบว่า context ครบถ้วนไหม"
```

**Output ที่ได้**:
- `.prp-output/BUSINESS-CONTEXT.md` - Centralized context file

**ใช้ร่วมกับ Agents อื่น**:
```
                 ┌──────────────────────┐
                 │ business-context-agent│
                 │  (run once / update) │
                 └──────────┬───────────┘
                            │
                            ▼
                 ┌──────────────────────┐
                 │ BUSINESS-CONTEXT.md  │
                 └──────────┬───────────┘
                            │
      ┌─────────┬───────────┼───────────┬─────────┐
      ▼         ▼           ▼           ▼         ▼
  customer-  outreach-  content-  proposal-  financial-
  discovery   agent    marketing   agent      agent
```

**Best Practice**:
1. รัน `business-context-agent --hybrid` ครั้งแรกเมื่อเริ่ม project
2. รัน `--update` เมื่อธุรกิจเปลี่ยน (pricing, target customer, etc.)
3. รัน `--validate` ทุกเดือนเพื่อตรวจสอบความ fresh

---

## Business Strategy Agents (14 agents)

### Tier 1: Customer Acquisition (Critical)

ใช้ agents เหล่านี้เมื่อ **หาลูกค้ารายแรก**

#### customer-discovery-agent
**Purpose**: Customer research, personas, pain points

**เมื่อไหร่ใช้**:
- เริ่มต้น product/service ใหม่
- ไม่แน่ใจว่า target customer คือใคร
- ต้องการเข้าใจ pain points ลึกขึ้น

**Prompt Examples**:
```
"ช่วยสร้าง customer persona สำหรับ AI chatbot service
ที่เน้น SMB ในไทย ธุรกิจ e-commerce"

"ออกแบบ customer interview questions สำหรับ
ธุรกิจ call center ที่กำลังมองหา AI solution"

"วิเคราะห์ pain points ของ customer support manager
ในบริษัทขนาด 50-200 คน"
```

**Output ที่ได้**:
- Customer persona with demographics
- Pain points analysis
- Interview guide (15-20 questions)
- Jobs-to-be-done framework

---

#### sales-enablement-agent
**Purpose**: Sales scripts, objection handling, follow-up

**เมื่อไหร่ใช้**:
- เตรียม sales call
- ไม่รู้จะ handle objections อย่างไร
- ต้องการ follow-up sequence

**Prompt Examples**:
```
"สร้าง discovery call script สำหรับ AI chatbot service
กับ e-commerce business"

"เตรียม objection handling สำหรับ:
- ราคาแพงเกินไป
- ไม่มี budget ตอนนี้
- ใช้ competitor อยู่แล้ว"

"ออกแบบ follow-up email sequence หลัง demo
(5 emails, 21 days)"
```

**Output ที่ได้**:
- Discovery call script
- Demo presentation guide
- Objection handling playbook
- Follow-up email sequence
- Closing techniques

---

#### positioning-strategy-agent
**Purpose**: Market positioning, differentiation

**เมื่อไหร่ใช้**:
- ไม่รู้จะ position ตัวเองอย่างไร
- มี competitors เยอะ
- ต้องการ unique value proposition

**Prompt Examples**:
```
"ช่วยวิเคราะห์ positioning สำหรับ AI chatbot service
ในตลาดไทย เทียบกับ Intercom, Zendesk, LINE OA"

"สร้าง value proposition statement ที่ชัดเจน
สำหรับ SMB e-commerce"

"ออกแบบ messaging framework
สำหรับ CEO vs Customer Support Manager"
```

**Output ที่ได้**:
- Competitive analysis
- Positioning statement
- Value proposition
- Messaging framework by audience
- Differentiation strategy

---

### Tier 2: Growth & Scale

ใช้ agents เหล่านี้เมื่อ **มีลูกค้าแล้ว ต้องการ scale**

#### content-marketing-agent
**Purpose**: Content strategy, blog posts, thought leadership

**เมื่อไหร่ใช้**:
- วางแผน content strategy
- เขียน blog posts
- สร้าง thought leadership

**Prompt Examples**:
```
"วางแผน content strategy 3 เดือน
สำหรับ AI chatbot service, target: SMB e-commerce"

"เขียน blog post: '5 วิธีลด customer support costs ด้วย AI'
ยาว 1,500 คำ, SEO optimized"

"สร้าง LinkedIn post series (5 posts)
เกี่ยวกับ AI in customer service"
```

**Output ที่ได้**:
- Content calendar
- Blog post drafts
- Social media posts
- Content pillars
- Distribution plan

---

#### seo-sem-agent
**Purpose**: SEO strategy, keyword research, Google Ads

**เมื่อไหร่ใช้**:
- ต้องการ organic traffic
- วางแผน Google Ads
- Keyword research

**Prompt Examples**:
```
"ทำ keyword research สำหรับ AI chatbot service
ในไทย, budget: 50,000/เดือน"

"วิเคราะห์ SEO สำหรับ landing page
และแนะนำ on-page optimization"

"ออกแบบ Google Ads campaign structure
สำหรับ B2B lead generation"
```

**Output ที่ได้**:
- Keyword research with volume
- On-page SEO recommendations
- Google Ads campaign structure
- Content brief for SEO
- Competitor analysis

---

#### pricing-strategy-agent
**Purpose**: Pricing models, packaging, tiers

**เมื่อไหร่ใช้**:
- กำหนดราคาครั้งแรก
- ปรับ pricing model
- สร้าง pricing tiers

**Prompt Examples**:
```
"ออกแบบ pricing tiers สำหรับ AI chatbot service
(Starter, Pro, Enterprise)"

"วิเคราะห์ unit economics:
CAC, LTV, payback period"

"เทียบ pricing กับ competitors
และแนะนำ positioning"
```

**Output ที่ได้**:
- Pricing tiers with features
- Unit economics analysis
- Competitor pricing comparison
- Price sensitivity analysis
- Annual vs monthly strategy

---

### Tier 3: Long-term Success

ใช้ agents เหล่านี้เมื่อ **มีลูกค้าแล้ว ต้องการ retain และ grow**

#### customer-success-agent
**Purpose**: Onboarding, retention, churn prevention

**เมื่อไหร่ใช้**:
- ออกแบบ onboarding flow
- Churn rate สูง
- ต้องการ improve retention

**Prompt Examples**:
```
"ออกแบบ onboarding flow 30 วัน
สำหรับ AI chatbot service"

"สร้าง health score model
เพื่อ identify at-risk customers"

"ออกแบบ QBR (Quarterly Business Review) template
สำหรับ enterprise customers"
```

**Output ที่ได้**:
- Onboarding timeline
- Email sequences
- Health score model
- Churn prevention playbook
- QBR template

---

#### partnership-agent
**Purpose**: Partner identification, co-marketing

**เมื่อไหร่ใช้**:
- หา partners/resellers
- วางแผน co-marketing
- Integration partnerships

**Prompt Examples**:
```
"ระบุ potential partners สำหรับ AI chatbot service
(integration, reseller, co-marketing)"

"ออกแบบ partner program
(tiers, benefits, requirements)"

"สร้าง partnership proposal template
สำหรับ e-commerce platforms"
```

**Output ที่ได้**:
- Partner identification list
- Partnership program structure
- Proposal templates
- Co-marketing campaign ideas
- Partner enablement materials

---

### Tier 4: Sales & Deals

ใช้ agents เหล่านี้เมื่อ **ต้องการปิด deals**

#### outreach-agent
**Purpose**: Cold email/LinkedIn outreach

**เมื่อไหร่ใช้**:
- เริ่ม cold outreach campaigns
- ไม่รู้จะเขียน cold email อย่างไร
- ต้องการ LinkedIn strategy

**Prompt Examples**:
```
"สร้าง cold email sequence 5 emails
สำหรับ e-commerce business owners"

"ออกแบบ LinkedIn outreach strategy
(connection request + follow-up messages)"

"สร้าง personalization framework
สำหรับ cold outreach at scale"
```

**Output ที่ได้**:
- Email sequence (5 emails)
- LinkedIn templates
- Personalization framework
- A/B testing plan
- Tracking metrics

---

#### proposal-agent
**Purpose**: Winning proposals, scope definition

**เมื่อไหร่ใช้**:
- ส่ง proposal ให้ลูกค้า
- Define scope of work
- Pricing presentation

**Prompt Examples**:
```
"สร้าง proposal สำหรับ AI chatbot implementation
บริษัท e-commerce, budget 50,000/เดือน"

"ออกแบบ scope of work template
สำหรับ chatbot projects"

"สร้าง ROI calculator
เพื่อ justify investment"
```

**Output ที่ได้**:
- Full proposal document
- Scope of work
- Pricing options
- ROI analysis
- Next steps

---

#### case-study-agent
**Purpose**: Customer success stories

**เมื่อไหร่ใช้**:
- มีลูกค้าที่ประสบความสำเร็จ
- ต้องการ social proof
- Sales enablement

**Prompt Examples**:
```
"สร้าง case study จากข้อมูล:
- ลูกค้า: E-commerce brand
- Challenge: High support volume
- Result: 40% ticket reduction"

"ออกแบบ customer interview questions
เพื่อเก็บข้อมูลทำ case study"

"สร้าง social media snippets
จาก case study ที่มี"
```

**Output ที่ได้**:
- Full case study (PDF format)
- One-pager version
- Social media snippets
- Interview guide
- Quote collection

---

### Tier 5: Operations & Brand

ใช้ agents เหล่านี้เมื่อ **ต้องการ optimize operations**

#### financial-agent
**Purpose**: Unit economics, runway, cash flow

**เมื่อไหร่ใช้**:
- วิเคราะห์ financial health
- คำนวณ runway
- Pricing decisions

**Prompt Examples**:
```
"วิเคราะห์ unit economics:
- MRR: 100,000
- Customers: 20
- CAC: 5,000
- Monthly expenses: 80,000"

"คำนวณ runway และ break-even point"

"แนะนำ pricing adjustments
based on current unit economics"
```

**Output ที่ได้**:
- Unit economics dashboard
- Runway calculation
- Break-even analysis
- Pricing recommendations
- Financial projections

---

#### automation-agent
**Purpose**: Process automation opportunities

**เมื่อไหร่ใช้**:
- ทำงานซ้ำๆ เยอะ
- ต้องการ scale without hiring
- Identify automation opportunities

**Prompt Examples**:
```
"วิเคราะห์ process automation opportunities
สำหรับ solopreneur ที่ทำ AI chatbot service"

"ออกแบบ automation stack
(Zapier, Make, etc.) สำหรับ:
- Lead capture → CRM
- Onboarding emails
- Invoice generation"

"สร้าง automation ROI analysis"
```

**Output ที่ได้**:
- Automation opportunities list
- Tool recommendations
- Workflow designs
- Implementation roadmap
- ROI analysis

---

#### personal-brand-agent
**Purpose**: LinkedIn presence, thought leadership

**เมื่อไหร่ใช้**:
- สร้าง personal brand
- LinkedIn content strategy
- Thought leadership

**Prompt Examples**:
```
"ออกแบบ LinkedIn profile optimization
สำหรับ founder ของ AI chatbot service"

"สร้าง content calendar 1 เดือน
(3-5 posts/week)"

"เขียน LinkedIn post series
เกี่ยวกับ building in public"
```

**Output ที่ได้**:
- Profile optimization
- Content calendar
- Post templates
- Engagement strategy
- Growth tactics

---

## Strategy Workflows

### Workflow 1: Getting First Customer (0 → 1)

**เหมาะกับ**: Solopreneurs ที่ยังไม่มีลูกค้า

```
Week 1-2: Research & Positioning
├── customer-discovery-agent → เข้าใจ target customer
├── positioning-strategy-agent → กำหนด positioning
└── pricing-strategy-agent → กำหนดราคา

Week 3-4: Outreach Preparation
├── content-marketing-agent → สร้าง initial content
├── personal-brand-agent → Optimize LinkedIn
└── outreach-agent → สร้าง cold email sequence

Week 5-6: Active Selling
├── sales-enablement-agent → Prepare sales materials
├── proposal-agent → Create proposal templates
└── Execute outreach campaigns

Week 7+: Close & Document
├── Close first customer
├── customer-success-agent → Onboard
└── case-study-agent → Document success
```

**Daily Routine**:
```
Morning:
- 30 min: LinkedIn engagement (personal-brand-agent guidance)
- 30 min: Cold outreach (outreach-agent templates)

Afternoon:
- Sales calls (sales-enablement-agent scripts)
- Follow-up (automated sequences)

Weekly:
- Review metrics
- Adjust strategy based on feedback
```

---

### Workflow 2: Scaling (1 → 10 Customers)

**เหมาะกับ**: มีลูกค้าแล้ว 1-3 ราย ต้องการ scale

```
Foundation:
├── case-study-agent → Document current success
├── customer-success-agent → Systematize onboarding
└── financial-agent → Validate unit economics

Growth Engines:
├── content-marketing-agent → Inbound content
├── seo-sem-agent → Organic + Paid traffic
└── partnership-agent → Channel partnerships

Sales Optimization:
├── sales-enablement-agent → Improve conversion
├── outreach-agent → Scale outreach
└── proposal-agent → Streamline proposals

Operations:
├── automation-agent → Automate repetitive tasks
└── pricing-strategy-agent → Optimize pricing
```

---

### Workflow 3: Enterprise Sales

**เหมาะกับ**: ต้องการขาย enterprise deals

```
Pre-Sales:
├── customer-discovery-agent → Understand enterprise needs
├── positioning-strategy-agent → Enterprise positioning
└── outreach-agent → Executive outreach

Sales Process:
├── sales-enablement-agent → Enterprise sales playbook
├── proposal-agent → Enterprise proposals
└── security-reviewer → Security compliance docs

Post-Sales:
├── customer-success-agent → Enterprise onboarding
├── case-study-agent → Enterprise case studies
└── partnership-agent → Strategic partnerships
```

---

### Workflow 4: Product Development

**เหมาะกับ**: ต้องการ build/improve product

```
Research:
├── customer-discovery-agent → Understand needs
├── product-ideas-agent → Feature ideas
└── web-researcher → Market research

Development:
├── codebase-analyst → Understand codebase
├── code-reviewer → Review code quality
└── security-reviewer → Security review

Launch:
├── docs-impact-agent → Update documentation
├── content-marketing-agent → Launch content
└── personal-brand-agent → Announce on LinkedIn
```

---

## Use Cases

### Use Case 1: "ผมมี AI Chatbot Service แต่ยังไม่มีลูกค้า"

**Step-by-step**:

1. **เข้าใจ Target Customer**
   ```
   Prompt: "ใช้ customer-discovery-agent
   ช่วยวิเคราะห์ target customer สำหรับ AI chatbot service
   ที่เน้น SMB e-commerce ในไทย"
   ```

2. **กำหนด Positioning**
   ```
   Prompt: "ใช้ positioning-strategy-agent
   ช่วยสร้าง positioning statement
   เทียบกับ LINE OA, Intercom, manual support"
   ```

3. **เตรียม Outreach**
   ```
   Prompt: "ใช้ outreach-agent
   สร้าง cold email sequence 5 emails
   target: e-commerce owners"
   ```

4. **เตรียม Sales Materials**
   ```
   Prompt: "ใช้ sales-enablement-agent
   สร้าง discovery call script และ demo guide"
   ```

5. **LinkedIn Presence**
   ```
   Prompt: "ใช้ personal-brand-agent
   optimize LinkedIn profile และ content plan"
   ```

---

### Use Case 2: "มีลูกค้า 3 ราย อยากได้เพิ่ม"

**Step-by-step**:

1. **Document Success**
   ```
   Prompt: "ใช้ case-study-agent
   สร้าง case study จากลูกค้าที่ประสบความสำเร็จ"
   ```

2. **Analyze Unit Economics**
   ```
   Prompt: "ใช้ financial-agent
   วิเคราะห์ CAC, LTV, payback period"
   ```

3. **Scale Outreach**
   ```
   Prompt: "ใช้ outreach-agent
   scale outreach campaign ด้วย personalization framework"
   ```

4. **Add Content Marketing**
   ```
   Prompt: "ใช้ content-marketing-agent
   วางแผน content strategy 3 เดือน"
   ```

5. **Automate Operations**
   ```
   Prompt: "ใช้ automation-agent
   identify automation opportunities
   เพื่อ handle more customers"
   ```

---

### Use Case 3: "ต้องการ Review Code ก่อน Deploy"

**Step-by-step**:

1. **Security Review**
   ```
   Prompt: "ใช้ security-reviewer
   review code ใน src/api/ สำหรับ vulnerabilities"
   ```

2. **Code Quality**
   ```
   Prompt: "ใช้ code-reviewer
   review code quality และ patterns"
   ```

3. **Performance**
   ```
   Prompt: "ใช้ performance-analyzer
   identify performance bottlenecks"
   ```

4. **Test Coverage**
   ```
   Prompt: "ใช้ pr-test-analyzer
   analyze test coverage และ gaps"
   ```

---

## Best Practices

### 1. เลือก Agent ที่ถูกต้อง

| ถ้าต้องการ... | ใช้ Agent |
|--------------|-----------|
| **เริ่มต้นใช้ business agents** | **business-context-agent (ทำก่อน!)** |
| เข้าใจ customers | customer-discovery-agent |
| ขายของ | sales-enablement-agent |
| เขียน content | content-marketing-agent |
| Review code | code-reviewer + security-reviewer |
| สร้าง proposal | proposal-agent |
| วิเคราะห์ตัวเลข | financial-agent |

### 2. Combine Agents for Better Results

**Good Combinations**:
```
customer-discovery → positioning-strategy → sales-enablement
outreach → sales-enablement → proposal
content-marketing → seo-sem → personal-brand
code-reviewer → security-reviewer → performance-analyzer
```

### 3. Iterate Based on Results

```
1. Use agent → Get output
2. Review output → Identify gaps
3. Refine prompt → Use again
4. Implement → Measure results
5. Adjust strategy
```

### 4. Save Successful Prompts

เก็บ prompts ที่ได้ผลดีไว้ใช้ซ้ำ:
```
/my/prompts/
├── customer-discovery-prompts.md
├── outreach-templates.md
├── proposal-templates.md
└── review-checklists.md
```

### 5. Model Selection Guide

| Situation | Recommended Model |
|-----------|-------------------|
| Strategic decisions | Opus |
| Creative content | Opus |
| Code review | Sonnet (faster) |
| Quick tasks | Haiku (cheapest) |
| Complex analysis | Opus |

---

## Quick Reference

### Agent Categories

```
Development (16):
├── Quality: code-reviewer, code-simplifier, comment-analyzer
├── Analysis: codebase-analyst, codebase-explorer, dependency-analyzer
├── Security: security-reviewer, silent-failure-hunter
├── Performance: performance-analyzer
├── Testing: pr-test-analyzer, type-design-analyzer
├── Docs: docs-impact-agent, accessibility-reviewer
├── Observability: observability-reviewer
├── Research: web-researcher
└── Product: product-ideas-agent

Foundation (1):
└── business-context-agent ⭐ (ใช้ก่อน business agents อื่น)

Business (14):
├── Customer Acquisition: customer-discovery, sales-enablement, positioning-strategy
├── Growth: content-marketing, seo-sem, pricing-strategy
├── Long-term: customer-success, partnership
├── Sales: outreach, proposal, case-study
└── Operations: financial, automation, personal-brand
```

### When to Use Each Tier

| Stage | Agents to Focus |
|-------|-----------------|
| **เริ่มต้น (ทำก่อน!)** | **business-context-agent** |
| Pre-launch | customer-discovery, positioning |
| Launch | outreach, sales-enablement, personal-brand |
| First customers | proposal, customer-success |
| Growth | content-marketing, seo-sem, case-study |
| Scale | automation, financial, partnership |

---

*Document version: 1.1*
*Last updated: 2026-02-09*

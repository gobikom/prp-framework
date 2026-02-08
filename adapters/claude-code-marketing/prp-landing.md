---
description: Analyze and improve landing page for conversion - copy, CTA, trust signals, SEO
argument-hint: "[--analyze URL] [--generate] [--improve 'suggestions'] [--target 'audience']"
---

# Landing Page Optimizer

**Input**: $ARGUMENTS

---

## Your Mission

Analyze, improve, or generate landing page content that converts visitors into leads/customers for your AI Call Center & Chatbot service.

**Golden Rule**: Focus on clarity, value proposition, and conversion. Every element should move visitors toward action.

---

## Phase 1: PARSE INPUT

### Input Options

| Input | Action |
|-------|--------|
| `--analyze URL` | Analyze existing landing page |
| `--generate` | Generate new landing page content |
| `--improve "suggestions"` | Improve based on specific feedback |
| `--target "audience"` | Customize for specific audience (SMB, Enterprise, Industry) |

### Default Behavior

If no flags provided, ask:
1. Do you have an existing landing page URL?
2. What's your target audience?
3. What's your main value proposition?

---

## Phase 2: ANALYZE (if --analyze)

### 2.1 Fetch and Review Page

```bash
# Use WebFetch to analyze the page
```

### 2.2 Evaluation Criteria

#### Above the Fold (First Screen)

| Element | Check | Score 1-10 |
|---------|-------|------------|
| **Headline** | Clear value proposition? | |
| **Subheadline** | Explains how/what? | |
| **Hero Image/Video** | Relevant, professional? | |
| **CTA Button** | Visible, action-oriented? | |
| **Trust Signal** | Logo, testimonial, stat? | |

#### Value Proposition

| Check | Status |
|-------|--------|
| Problem clearly stated? | |
| Solution benefits (not features) emphasized? | |
| Differentiation from competitors? | |
| Specific outcomes/results mentioned? | |

#### Social Proof

| Element | Present? | Quality |
|---------|----------|---------|
| Customer logos | | |
| Testimonials with names/photos | | |
| Case study snippets | | |
| Statistics/metrics | | |
| Trust badges (security, awards) | | |

#### Call-to-Action

| Check | Status |
|-------|--------|
| Primary CTA visible above fold? | |
| CTA text action-oriented? | |
| Secondary CTA for not-ready visitors? | |
| Form fields minimal? | |

#### SEO & Technical

| Element | Check |
|---------|-------|
| Title tag optimized? | |
| Meta description compelling? | |
| H1 includes main keyword? | |
| Page load speed acceptable? | |
| Mobile responsive? | |

### 2.3 AI Call Center/Chatbot Specific

| Element | Check |
|---------|-------|
| Demo/trial CTA prominent? | |
| Integration logos (CRM, helpdesk)? | |
| Use cases by industry? | |
| ROI calculator or stats? | |
| Live chat/demo available? | |

---

## Phase 3: GENERATE/IMPROVE

### 3.1 Landing Page Structure

```markdown
## Landing Page Blueprint

### Section 1: Hero (Above the Fold)
**Headline**: [Problem-focused or benefit-focused]
**Subheadline**: [How you solve it]
**CTA**: [Primary action]
**Trust**: [Quick credibility]

### Section 2: Problem Agitation
**Pain Points**: [3 specific problems your audience faces]
**Cost of Inaction**: [What happens if they don't solve it]

### Section 3: Solution Introduction
**How It Works**: [3 simple steps]
**Key Benefits**: [Top 3 benefits with icons]

### Section 4: Features (Benefit-Oriented)
**Feature 1**: [Benefit it provides]
**Feature 2**: [Benefit it provides]
**Feature 3**: [Benefit it provides]

### Section 5: Social Proof
**Testimonials**: [2-3 with photos, names, companies]
**Logos**: [Customer/partner logos]
**Stats**: [Key metrics]

### Section 6: Use Cases / Industries
**Use Case 1**: [Industry + outcome]
**Use Case 2**: [Industry + outcome]
**Use Case 3**: [Industry + outcome]

### Section 7: Pricing/CTA
**Pricing Preview**: [Optional - or "Get Quote"]
**Primary CTA**: [Main action]
**Secondary CTA**: [Lower commitment option]

### Section 8: FAQ
**Q1**: [Most common objection]
**Q2**: [Technical concern]
**Q3**: [Pricing/commitment concern]

### Section 9: Final CTA
**Urgency/Scarcity**: [Optional]
**CTA**: [Repeat primary action]
**Contact**: [Alternative contact method]
```

### 3.2 Copy Templates for AI Call Center/Chatbot

#### Headlines (Test Multiple)

```markdown
## Problem-Focused
- "Stop Losing Customers to Long Hold Times"
- "Your Call Center is Costing You Customers"
- "80% of Callers Hang Up After 2 Minutes on Hold"

## Benefit-Focused
- "Handle 10x More Calls Without Hiring"
- "24/7 Customer Service That Never Sleeps"
- "Reduce Call Center Costs by 60%"

## Curiosity-Focused
- "The AI That Sounds More Human Than Your Agents"
- "What If Every Customer Got Instant Support?"
```

#### Subheadlines

```markdown
- "AI-powered call center and chatbot that handles inquiries 24/7, in any language, at a fraction of the cost"
- "Automate 70% of customer calls while improving satisfaction scores"
- "Enterprise-grade AI voice and chat that integrates with your existing systems in days, not months"
```

#### CTAs

```markdown
## High Commitment
- "Start Free Trial"
- "Book a Demo"
- "Get Started Free"

## Low Commitment
- "See How It Works"
- "Watch Demo Video"
- "Calculate Your Savings"

## Urgency
- "Start Your Free 14-Day Trial"
- "Book Your Demo (Limited Slots)"
```

#### Trust Signals

```markdown
## Stats to Highlight
- "Trusted by X+ businesses"
- "X million conversations handled"
- "99.9% uptime SLA"
- "60% average cost reduction"
- "4.8/5 customer satisfaction"

## Certifications/Compliance
- SOC 2 compliant
- GDPR ready
- Enterprise security
```

---

## Phase 4: OUTPUT

### 4.1 Analysis Report (if --analyze)

**Path**: `.claude/PRPs/marketing/landing-analysis-{date}.md`

```markdown
---
url: "{URL}"
analyzed: {ISO_TIMESTAMP}
---

# Landing Page Analysis

## Overall Score: {N}/100

### Summary
{2-3 sentences on current state}

### Scores by Section

| Section | Score | Status |
|---------|-------|--------|
| Above the Fold | {N}/10 | {GOOD/NEEDS_WORK} |
| Value Proposition | {N}/10 | |
| Social Proof | {N}/10 | |
| Call-to-Action | {N}/10 | |
| SEO | {N}/10 | |

### Critical Issues

1. **{Issue}**: {Why it matters} → {Fix}
2. **{Issue}**: {Why it matters} → {Fix}

### Quick Wins

1. {Change} → Expected impact: {X}
2. {Change} → Expected impact: {X}

### Recommended Changes (Priority Order)

| Priority | Change | Effort | Impact |
|----------|--------|--------|--------|
| 1 | {Change} | Low | High |
| 2 | {Change} | Medium | High |

### Copy Suggestions

**Current Headline**: "{current}"
**Suggested Headlines**:
1. "{option 1}"
2. "{option 2}"

**Current CTA**: "{current}"
**Suggested CTAs**:
1. "{option 1}"
2. "{option 2}"
```

### 4.2 Generated Content (if --generate)

**Path**: `.claude/PRPs/marketing/landing-content-{date}.md`

```markdown
---
target: "{TARGET_AUDIENCE}"
generated: {ISO_TIMESTAMP}
---

# Landing Page Content

## Hero Section

### Headline
{headline}

### Subheadline
{subheadline}

### Primary CTA
{cta_text}

### Hero Image Suggestion
{description of ideal hero image}

---

## Problem Section

### Pain Point 1
**Title**: {title}
**Description**: {1-2 sentences}

### Pain Point 2
...

---

## Solution Section

### How It Works

**Step 1**: {title}
{description}

**Step 2**: {title}
{description}

**Step 3**: {title}
{description}

---

## Benefits Section

### Benefit 1
**Title**: {benefit}
**Description**: {how it helps}
**Icon suggestion**: {icon name}

...

---

## Social Proof Section

### Testimonial Template 1
> "{quote}"
>
> — {Name}, {Title} at {Company}

### Stats to Display
- {stat 1}
- {stat 2}
- {stat 3}

---

## FAQ Section

### Q: {question}
A: {answer}

...

---

## SEO Elements

### Title Tag (50-60 chars)
{title}

### Meta Description (150-160 chars)
{description}

### H1
{h1}
```

---

## Phase 5: PRESENT TO USER

```markdown
## Landing Page Analysis Complete

**URL**: {URL or "New page generated"}
**Target Audience**: {audience}
**Overall Score**: {N}/100

### Top 3 Improvements Needed

1. {improvement}
2. {improvement}
3. {improvement}

### Artifacts

📄 **Full Report**: `.claude/PRPs/marketing/landing-{type}-{date}.md`

### Next Steps

1. {immediate action}
2. {follow-up}
```

---

## AI Call Center/Chatbot Specific Guidance

### Target Audiences

| Audience | Pain Points | Value Props |
|----------|-------------|-------------|
| **SMB** | Cost, hiring, 24/7 coverage | Affordable, easy setup, no coding |
| **Enterprise** | Scale, integration, compliance | Enterprise security, API, SLA |
| **Call Centers** | Volume, agent burnout, wait times | Handle overflow, reduce load |
| **E-commerce** | Cart abandonment, support load | Instant answers, upselling |
| **Healthcare** | Appointment booking, FAQs | HIPAA compliant, after-hours |

### Industry-Specific Copy

| Industry | Headline Focus | Key Metrics |
|----------|----------------|-------------|
| Retail | "Never Miss a Sale" | Cart recovery %, response time |
| Healthcare | "24/7 Patient Support" | Appointment bookings, wait time |
| Finance | "Secure, Compliant AI" | Compliance, fraud prevention |
| Travel | "Instant Booking Assistance" | Booking completion rate |

---

## Success Criteria

- **ANALYZED**: Current page evaluated with scores
- **ISSUES_IDENTIFIED**: Critical problems documented
- **SOLUTIONS_PROVIDED**: Specific copy and changes suggested
- **REPORT_SAVED**: Analysis/content saved to file
- **ACTIONABLE**: Clear next steps for implementation

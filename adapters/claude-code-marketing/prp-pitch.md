---
description: Generate pitch materials - deck, one-pager, email templates, proposals
argument-hint: "[--deck] [--one-pager] [--email] [--proposal] [--target 'audience/industry']"
---

# Pitch Materials Generator

**Input**: $ARGUMENTS

---

## Your Mission

Generate compelling pitch materials that convert prospects into customers. Materials should be clear, benefit-focused, and tailored to the audience.

**Golden Rule**: Focus on the customer's problem and desired outcome, not your features.

---

## Phase 1: PARSE INPUT

### Input Options

| Input | Action |
|-------|--------|
| `--deck` | Generate pitch deck outline + content |
| `--one-pager` | Generate one-page sales sheet |
| `--email` | Generate outreach email templates |
| `--proposal` | Generate proposal template |
| `--target "audience"` | Customize for specific audience |
| No flags | Generate all materials |

### Target Audiences

| Audience | Focus |
|----------|-------|
| `SMB` | Cost savings, easy setup, no IT needed |
| `Enterprise` | Security, compliance, integration, SLA |
| `Call Center` | Volume handling, agent support, efficiency |
| `E-commerce` | Cart recovery, 24/7 support, sales |
| `Healthcare` | Compliance, appointments, after-hours |
| `{Industry}` | Industry-specific pain points |

---

## Phase 2: GATHER CONTEXT

### 2.1 Product Information

Before generating, confirm or gather:

```markdown
## Product Context

### Core Offering
- Product name:
- One-liner description:
- Primary use case:

### Key Differentiators
1.
2.
3.

### Pricing Model
- Entry tier:
- Growth tier:
- Enterprise tier:

### Proof Points
- Customer count:
- Key metrics (response time, resolution rate):
- Notable customers:
- Case study available:

### Technical
- Deployment: Cloud/On-prem
- Integration time:
- Security certifications:
```

### 2.2 Prospect Context (if specific target)

```markdown
## Prospect Context

### Company
- Name:
- Industry:
- Size:
- Current solution:

### Decision Maker
- Name:
- Title:
- Reported pain points:

### Opportunity
- Budget indication:
- Timeline:
- Competitors in consideration:
```

---

## Phase 3: PITCH DECK

### 3.1 Deck Structure (10-12 slides)

```markdown
## Pitch Deck Outline

### Slide 1: Title
- Company name + logo
- Tagline
- Contact info

### Slide 2: Problem
- The pain your customers feel
- Statistics that quantify the problem
- Cost of doing nothing

### Slide 3: Solution
- Your solution in one sentence
- High-level how it works
- Key benefit (not feature)

### Slide 4: How It Works
- 3 simple steps or visual flow
- Emphasize ease/speed
- Show, don't tell

### Slide 5: Demo/Product
- Screenshot or video
- Key interface elements
- "See it in action"

### Slide 6: Benefits (not features)
- Benefit 1: Customer outcome
- Benefit 2: Customer outcome
- Benefit 3: Customer outcome

### Slide 7: Social Proof
- Customer logos
- Key testimonial quote
- Impressive metric

### Slide 8: Case Study
- Customer name + challenge
- Solution implemented
- Results with numbers

### Slide 9: Why Us
- Differentiators vs alternatives
- Team/expertise (brief)
- Technology advantage

### Slide 10: Pricing
- Simple pricing tiers
- Or "Let's discuss your needs"
- ROI framing

### Slide 11: Next Steps
- Clear CTA
- What happens next
- Contact information

### Slide 12: Q&A
- "Questions?"
- Contact details
- Website/demo link
```

### 3.2 Deck Content for AI Call Center/Chatbot

```markdown
## Slide Content

### Slide 2: Problem

**Headline**: "Your Support Team is Overwhelmed"

**Stats**:
- 67% of customers hang up after 2 min on hold
- Average cost per support call: $12-$35
- Support teams spend 60% of time on repetitive questions

**Visual**: Graph showing rising support costs vs. customer satisfaction declining

---

### Slide 3: Solution

**Headline**: "AI That Handles Routine Inquiries 24/7"

**Subheadline**: "So your team can focus on what matters"

**Key message**:
"Our AI voice and chat assistant handles common customer inquiries instantly,
around the clock, while seamlessly escalating complex issues to your team."

---

### Slide 4: How It Works

**Step 1**: Customer reaches out (call or chat)
**Step 2**: AI understands and responds naturally
**Step 3**: Complex issues escalate to humans with full context

**Visual**: Simple flow diagram

---

### Slide 6: Benefits

**Benefit 1**: "Reduce Costs by 60%"
Handle more inquiries with fewer resources

**Benefit 2**: "24/7 Availability"
Never miss a customer, any timezone

**Benefit 3**: "Happier Customers"
Instant responses, no hold times

**Benefit 4**: "Empowered Agents"
Let humans handle meaningful work

---

### Slide 7: Social Proof

**Logos**: [Customer logos]

**Quote**:
> "We reduced our call volume by 45% in the first month.
> Our agents are happier and our customers are too."
> — VP of Customer Success, [Company]

**Metric**: "500,000+ conversations handled"

---

### Slide 8: Case Study

**[Company Name] - E-commerce**

**Challenge**:
- 2,000 support tickets/day
- 10-minute average wait time
- Rising cart abandonment

**Solution**:
- AI chatbot on website
- Voice AI for order status calls

**Results**:
- 70% of inquiries handled by AI
- Wait time: 0 for AI, 2 min for human
- 25% increase in customer satisfaction
- $200K annual savings

---

### Slide 10: Pricing

**Starter**: $X/month
- Up to Y conversations
- Chat + basic voice
- Standard support

**Growth**: $X/month
- Up to Y conversations
- Full voice + chat
- Priority support
- CRM integration

**Enterprise**: Custom
- Unlimited scale
- Custom integrations
- Dedicated success manager
- SLA guarantee

**ROI**: "Most customers see positive ROI in 30 days"
```

---

## Phase 4: ONE-PAGER

### 4.1 One-Pager Structure

```markdown
## One-Pager Template

┌─────────────────────────────────────────────────────────────┐
│  [LOGO]                                    [TAGLINE]        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  THE PROBLEM                                                │
│  ─────────────                                              │
│  [2-3 sentences on customer pain]                           │
│                                                             │
│  • Stat 1                                                   │
│  • Stat 2                                                   │
│  • Stat 3                                                   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  THE SOLUTION                                               │
│  ────────────                                               │
│  [2-3 sentences on your solution]                           │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ Benefit 1│  │ Benefit 2│  │ Benefit 3│                  │
│  │   Icon   │  │   Icon   │  │   Icon   │                  │
│  │  Detail  │  │  Detail  │  │  Detail  │                  │
│  └──────────┘  └──────────┘  └──────────┘                  │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  HOW IT WORKS                                               │
│  ─────────────                                              │
│  1. [Step 1] → 2. [Step 2] → 3. [Step 3]                   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  RESULTS                                                    │
│  ───────                                                    │
│  "Quote from customer" — Name, Title, Company               │
│                                                             │
│  [60%]        [24/7]        [2 min]                         │
│  Cost savings  Availability  Avg response                   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [Customer logos row]                                       │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  READY TO GET STARTED?                                      │
│                                                             │
│  [CTA Button]     [Phone]     [Email]     [Website]        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 One-Pager Content

```markdown
## AI Call Center & Chatbot - One Pager

### THE PROBLEM

Customer expectations are higher than ever, but support teams are stretched thin.
Long wait times frustrate customers and cost you business.

• 67% of customers abandon calls after 2 minutes on hold
• Support costs are rising 15% year-over-year
• 60% of inquiries are routine and repetitive

### THE SOLUTION

[Product Name] is an AI-powered call center and chatbot that handles
routine customer inquiries instantly, 24/7, while seamlessly escalating
complex issues to your team.

**Always Available**: 24/7 support without hiring night shift
**Instantly Responsive**: No hold times, instant answers
**Seamlessly Integrated**: Works with your existing CRM and tools
**Continuously Learning**: Improves with every conversation

### HOW IT WORKS

1. **Connect** - Easy setup with your existing phone and chat systems
2. **Configure** - Customize responses for your specific use cases
3. **Go Live** - AI handles routine inquiries, escalates the rest

### RESULTS

> "We reduced support costs by 60% while improving customer satisfaction.
> The AI handles 70% of our inquiries without human involvement."
> — Sarah Chen, VP Support, TechCorp

| 60% | 24/7 | 70% | 4.8★ |
|-----|------|-----|------|
| Cost Reduction | Availability | AI Resolution | Customer Rating |

### TRUSTED BY

[Logo] [Logo] [Logo] [Logo] [Logo]

### GET STARTED

Book a demo: calendly.com/yourcompany
Email: sales@yourcompany.com
Phone: (555) 123-4567
Website: www.yourcompany.com
```

---

## Phase 5: EMAIL TEMPLATES

### 5.1 Cold Outreach (First Touch)

```markdown
## Cold Email Template

**Subject Lines (A/B test)**:
- "Quick question about [Company]'s support"
- "[First name], reducing support costs at [Company]"
- "Saw [Company] is hiring for support - here's an alternative"

**Body**:

Hi [First Name],

I noticed [Company] is [growing rapidly / hiring support staff / in [industry]].

Most [industry] companies I talk to struggle with:
- Long customer wait times
- Rising support costs
- Agents overwhelmed with repetitive questions

We help companies like [Similar Company] handle 70% of support inquiries
automatically with AI, while routing complex issues to humans.

[Similar Company] reduced their support costs by 60% in 90 days.

Worth a 15-minute chat to see if this could help [Company]?

Best,
[Your name]

P.S. Here's a 2-minute demo: [link]
```

### 5.2 Follow-up Email

```markdown
## Follow-up Email Template

**Subject**: "Re: Quick question about [Company]'s support"

Hi [First Name],

Just floating this back up - thought this might be relevant given
[recent news / your growth / the holiday rush coming].

Happy to share how [Similar Company] reduced wait times from
10 minutes to instant with AI support.

Open to a quick call this week?

Best,
[Your name]
```

### 5.3 Post-Demo Follow-up

```markdown
## Post-Demo Email Template

**Subject**: "Next steps for [Company] + [Your Company]"

Hi [First Name],

Thanks for taking the time today. It was great learning about
[specific thing they mentioned].

As promised, here's what we discussed:

**Your Challenges**:
- [Challenge 1 they mentioned]
- [Challenge 2 they mentioned]

**How We Can Help**:
- [Specific solution point 1]
- [Specific solution point 2]

**Next Steps**:
1. [Action item 1]
2. [Action item 2]

I'll [follow up action] by [date]. In the meantime, here's
[relevant resource / case study].

Looking forward to working together!

Best,
[Your name]

Attachments:
- [One-pager]
- [Case study]
- [Proposal if discussed]
```

### 5.4 Referral Request

```markdown
## Referral Email Template

**Subject**: "Know anyone struggling with customer support?"

Hi [First Name],

Hope things are going well at [Company]!

Quick question: do you know anyone who's struggling with
high support volume or rising support costs?

We're looking to help a few more companies this quarter,
and happy to offer [incentive] for any introductions.

Just reply with their name/email and I'll take it from there.

Thanks!
[Your name]
```

---

## Phase 6: PROPOSAL TEMPLATE

```markdown
## Proposal Template

---

# Proposal: AI Support Solution for [Company]

**Prepared for**: [Contact Name], [Title]
**Prepared by**: [Your Name], [Your Company]
**Date**: [Date]

---

## Executive Summary

[Company] is experiencing [pain points discussed]. This proposal outlines
how [Your Company] will help [Company] achieve [desired outcomes].

---

## Understanding Your Needs

Based on our conversations, [Company] is looking to:

- [ ] Reduce customer wait times
- [ ] Lower support costs
- [ ] Provide 24/7 coverage
- [ ] Improve customer satisfaction
- [ ] Enable agents to focus on complex issues

**Current State**:
- Support volume: X inquiries/month
- Average wait time: X minutes
- Current cost per inquiry: $X

---

## Proposed Solution

### Overview
[Brief description of the solution]

### Components
1. **AI Chatbot**: Handles web/app inquiries
2. **AI Voice**: Handles phone inquiries
3. **Dashboard**: Analytics and management
4. **Integrations**: [CRM], [Helpdesk]

### Implementation Timeline
- Week 1-2: Setup and configuration
- Week 3: Testing and training
- Week 4: Go-live with monitoring
- Ongoing: Optimization and support

---

## Expected Outcomes

| Metric | Current | Expected | Timeline |
|--------|---------|----------|----------|
| AI Resolution Rate | 0% | 60-70% | 90 days |
| Wait Time | X min | < 30 sec | 30 days |
| Cost per Inquiry | $X | $Y | 90 days |
| Customer Satisfaction | X | +20% | 90 days |

---

## Investment

### Option A: Growth Plan
- $X/month
- Up to Y conversations
- Full features
- Standard support

### Option B: Enterprise Plan
- Custom pricing
- Unlimited scale
- Premium support
- Dedicated success manager

### ROI Projection
Based on X inquiries/month at $Y current cost:
- Monthly savings: $Z
- Payback period: X months

---

## Why [Your Company]

1. **Proven Results**: [X] customers, [Y] conversations handled
2. **Easy Implementation**: Live in weeks, not months
3. **Dedicated Support**: Named success manager
4. **Continuous Improvement**: AI learns and improves

---

## Next Steps

1. [ ] Review and approve proposal
2. [ ] Sign agreement
3. [ ] Kick-off call
4. [ ] Implementation begins

---

## Contact

[Your Name]
[Email] | [Phone]
[Website]

---

*Proposal valid for 30 days*
```

---

## Phase 7: OUTPUT

### 7.1 Save Materials

**Paths**:
- `.prp-output/marketing/pitch-deck-{date}.md`
- `.prp-output/marketing/one-pager-{date}.md`
- `.prp-output/marketing/email-templates-{date}.md`
- `.prp-output/marketing/proposal-{company}-{date}.md`

### 7.2 Present to User

```markdown
## Pitch Materials Generated

**Target Audience**: {audience}
**Generated**: {timestamp}

### Materials Created

| Material | Path | Status |
|----------|------|--------|
| Pitch Deck | `.prp-output/marketing/pitch-deck-{date}.md` | Ready |
| One-Pager | `.prp-output/marketing/one-pager-{date}.md` | Ready |
| Email Templates | `.prp-output/marketing/email-templates-{date}.md` | Ready |
| Proposal | `.prp-output/marketing/proposal-{date}.md` | Ready |

### Next Steps

1. Review and customize for your specific situation
2. Add company-specific logos, screenshots
3. Test email templates with A/B testing
4. Practice pitch deck delivery

### Tips

- Customize for each prospect
- Focus on their problems, not your features
- Use specific numbers when possible
- Follow up within 48 hours
```

---

## Success Criteria

- **CONTEXT_GATHERED**: Product and audience information collected
- **DECK_GENERATED**: Pitch deck outline and content created
- **ONE_PAGER_GENERATED**: One-page sales sheet created
- **EMAILS_GENERATED**: Outreach templates created
- **PROPOSAL_GENERATED**: Proposal template created
- **FILES_SAVED**: All materials saved to appropriate paths

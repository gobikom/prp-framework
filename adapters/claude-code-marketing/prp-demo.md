---
description: Prepare demo environment for customer presentations - setup, sample data, scripts
argument-hint: "[--setup] [--reset] [--scenario 'customer-name'] [--checklist]"
---

# Demo Environment Manager

**Input**: $ARGUMENTS

---

## Your Mission

Prepare and manage demo environments for customer presentations. Ensure demos run smoothly, showcase key features, and handle edge cases gracefully.

**Golden Rule**: A failed demo loses deals. Prepare thoroughly, have fallbacks ready, and practice the flow.

---

## Phase 1: PARSE INPUT

### Input Options

| Input | Action |
|-------|--------|
| `--setup` | Set up fresh demo environment |
| `--reset` | Reset demo to clean state |
| `--scenario "customer-name"` | Customize for specific prospect |
| `--checklist` | Generate pre-demo checklist |
| `--script` | Generate demo script |
| `--record` | Prepare for recorded demo |

### Default Behavior

If no flags provided, show current demo status and options.

---

## Phase 2: DEMO SETUP

### 2.1 Environment Checklist

```bash
# Check demo environment status
echo "=== Demo Environment Check ==="

# Check services are running
curl -s http://localhost:3000/health || echo "Frontend: DOWN"
curl -s http://localhost:8000/health || echo "Backend: DOWN"

# Check database
# pg_isready -h localhost -p 5432 || echo "Database: DOWN"

# Check external services
# curl -s https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY" | head -1
```

### 2.2 Sample Data Setup

#### Default Demo Personas

```markdown
## Demo Accounts

### Admin User
- Email: demo-admin@example.com
- Password: Demo123!
- Role: Administrator
- Features: Full access

### Agent User
- Email: demo-agent@example.com
- Password: Demo123!
- Role: Agent
- Features: Limited dashboard

### Customer View
- Phone: +1-555-DEMO-001
- Name: John Smith
- History: 3 previous conversations
```

#### Sample Conversations

```markdown
## Pre-loaded Conversations

### Successful Resolution
- Customer: Order status inquiry
- AI handled: 100%
- Outcome: Customer satisfied
- Duration: 45 seconds

### Handoff to Human
- Customer: Complex billing issue
- AI handled: Initial triage
- Outcome: Smooth handoff to agent
- Duration: 2 min AI + handoff

### Multi-turn Conversation
- Customer: Product recommendation
- AI handled: 3 follow-up questions
- Outcome: Upsell successful
- Duration: 3 minutes
```

### 2.3 Feature Showcase Setup

```markdown
## Key Features to Demo

### 1. AI Call Handling
- [ ] Inbound call simulation ready
- [ ] Sample prompts configured
- [ ] Fallback responses set

### 2. Chatbot Widget
- [ ] Widget embedded on demo page
- [ ] Greeting message customized
- [ ] Quick replies configured

### 3. Dashboard Analytics
- [ ] Sample metrics populated
- [ ] Charts showing improvement
- [ ] Export feature ready

### 4. Integration Demo
- [ ] CRM sync visible
- [ ] Ticket creation demo
- [ ] Webhook logs ready

### 5. Admin Panel
- [ ] Settings accessible
- [ ] Prompt editor demo
- [ ] User management visible
```

---

## Phase 3: SCENARIO CUSTOMIZATION

### 3.1 Industry-Specific Setup

#### E-commerce

```markdown
## E-commerce Demo Scenario

### Company Profile
- Name: "Fashion Forward"
- Industry: Online Retail
- Size: 50 employees
- Current challenge: High cart abandonment, support overload

### Sample Data
- Products: 50 sample products with images
- Orders: 100 recent orders (various statuses)
- Customers: 200 customer profiles

### Demo Flows
1. "Where is my order?" → AI retrieves order status
2. "I want to return this" → AI initiates return process
3. "Which size should I get?" → AI product recommendation

### Metrics to Show
- 70% of inquiries handled by AI
- 45 second average response time
- 35% reduction in support tickets
```

#### Healthcare

```markdown
## Healthcare Demo Scenario

### Company Profile
- Name: "CareFirst Clinic"
- Industry: Healthcare
- Size: 20 providers
- Current challenge: Appointment no-shows, after-hours calls

### Sample Data
- Providers: 10 doctors with specialties
- Appointments: This week's schedule
- Patients: 100 sample patient profiles

### Demo Flows
1. "I need to schedule an appointment" → AI books appointment
2. "What are your hours?" → AI provides info
3. "I need to cancel my appointment" → AI handles rescheduling

### Compliance
- HIPAA notice visible
- PHI handling demonstrated
- Consent flow shown

### Metrics to Show
- 60% reduction in no-shows (reminders)
- 24/7 appointment booking
- 50% fewer front desk calls
```

#### Call Center

```markdown
## Call Center Demo Scenario

### Company Profile
- Name: "TechSupport Pro"
- Industry: IT Support
- Size: 100 agents
- Current challenge: High call volume, agent burnout

### Sample Data
- Tickets: 500 recent tickets
- Agents: 20 agent profiles
- Knowledge base: 100 articles

### Demo Flows
1. "My internet is not working" → AI troubleshooting
2. Complex issue → AI escalation to human
3. "Check my account status" → AI authentication + info

### Metrics to Show
- 40% of calls handled by AI
- 2 minute average handle time
- 30% improvement in agent satisfaction
```

### 3.2 Prospect-Specific Customization

```markdown
## Custom Scenario: {CUSTOMER_NAME}

### Research (Pre-Demo)
- Company website: {URL}
- Industry: {industry}
- Size: {employees}
- Current solution: {if known}
- Pain points: {from discovery call}

### Customizations Made
- [ ] Company logo in demo
- [ ] Industry-specific prompts
- [ ] Relevant use case scenarios
- [ ] Competitive comparison ready

### Talking Points
1. {Pain point 1} → Our solution
2. {Pain point 2} → Our solution
3. {Their goal} → How we help

### Objection Preparation
- "How is this different from {competitor}?"
- "What about {specific concern}?"
- "How long does implementation take?"
```

---

## Phase 4: DEMO SCRIPT

### 4.1 Standard Demo Flow (30 minutes)

```markdown
## Demo Script: AI Call Center & Chatbot

### Opening (3 min)
"Thanks for joining. Today I'll show you how [Company] can [main benefit].
Before we dive in, what's the biggest challenge you're facing with customer support right now?"

[Listen and adapt demo focus]

### Problem Validation (2 min)
"Many companies like yours struggle with:
- Long wait times frustrating customers
- Rising support costs
- Agents overwhelmed with repetitive questions

Does that resonate with your experience?"

### Solution Overview (3 min)
"Our AI handles routine inquiries 24/7, so your team can focus on complex issues."

[Show high-level architecture diagram]

### Live Demo: Chatbot (7 min)

**Demo 1: Simple Inquiry**
"Let me show you a customer asking about order status..."
[Trigger demo conversation]
"Notice how the AI understood the intent, retrieved the info, and responded naturally."

**Demo 2: Complex Handoff**
"Now let's see what happens with a complex issue..."
[Show escalation flow]
"The AI recognizes when to involve a human and does a warm handoff."

**Demo 3: Customization**
"Everything is customizable..."
[Show prompt editor, quick replies]

### Live Demo: Voice (5 min)

**Demo 1: Inbound Call**
"Let me play a recorded call..."
[Play sample call]
"Notice the natural conversation flow and accurate responses."

**Demo 2: Outbound (if applicable)**
"We can also handle outbound calls like appointment reminders..."

### Dashboard & Analytics (5 min)
"Here's where you see the impact..."
[Show metrics, charts, reports]
"You can track resolution rates, common topics, and agent performance."

### Integration (3 min)
"This integrates with your existing tools..."
[Show CRM integration, API docs]

### Closing (2 min)
"Based on what you've seen, which use case would be most valuable for you?"

[Discuss next steps, trial, pricing]

### Q&A
[Address questions, objections]
```

### 4.2 Quick Demo Flow (15 minutes)

```markdown
## Quick Demo Script

### Intro (1 min)
Quick intro, one key benefit

### Problem (1 min)
"Companies like yours typically see..."

### Live Demo (8 min)
- Chatbot: 1 conversation
- Voice: 1 sample call
- Dashboard: Key metrics

### Close (2 min)
"What questions do you have?"

### Next Steps (1 min)
Trial or follow-up call
```

---

## Phase 5: PRE-DEMO CHECKLIST

### 5.1 24 Hours Before

```markdown
## Day Before Checklist

### Environment
- [ ] Demo environment accessible
- [ ] All services running
- [ ] Sample data refreshed
- [ ] No outstanding errors in logs

### Preparation
- [ ] Prospect research completed
- [ ] Custom scenario configured
- [ ] Demo script reviewed
- [ ] Backup plan ready

### Technical
- [ ] Screen sharing tested
- [ ] Audio/video working
- [ ] Browser cache cleared
- [ ] Notifications disabled
```

### 5.2 1 Hour Before

```markdown
## Pre-Demo Checklist

### Environment
- [ ] Demo URL loads
- [ ] Login works
- [ ] Sample conversations visible
- [ ] Dashboard shows data

### Setup
- [ ] Browser tabs pre-loaded
- [ ] Demo accounts logged in
- [ ] Fullscreen mode ready
- [ ] Notes/script accessible

### Technical
- [ ] Close unnecessary apps
- [ ] Disable notifications
- [ ] Check internet speed
- [ ] Backup hotspot ready

### Mental
- [ ] Review prospect notes
- [ ] Key talking points ready
- [ ] Objection responses prepared
- [ ] Calm and confident
```

### 5.3 Fallback Plans

```markdown
## If Things Go Wrong

### Demo Environment Down
→ Switch to recorded video
→ Show slide deck with screenshots
→ Offer to reschedule

### Feature Not Working
→ "Let me show you this another way..."
→ Skip and continue
→ Follow up with recording

### Unexpected Question
→ "Great question, let me note that..."
→ "I'll get back to you on that specific detail"
→ Don't make things up

### Technical Issues
→ Have mobile hotspot ready
→ Pre-downloaded backup videos
→ Slide deck offline
```

---

## Phase 6: OUTPUT

### 6.1 Demo Status Report

**Path**: `.claude/PRPs/demos/demo-status-{date}.md`

```markdown
---
checked: {ISO_TIMESTAMP}
status: READY | ISSUES
---

# Demo Environment Status

## Overall: {READY/NOT READY}

### Services
| Service | Status | URL |
|---------|--------|-----|
| Frontend | {UP/DOWN} | {url} |
| Backend | {UP/DOWN} | {url} |
| Database | {UP/DOWN} | - |

### Sample Data
| Data Type | Count | Status |
|-----------|-------|--------|
| Users | {N} | {OK/MISSING} |
| Conversations | {N} | {OK/MISSING} |
| Analytics | {N} days | {OK/MISSING} |

### Issues Found
{List of issues if any}

### Recommended Actions
1. {Action}
2. {Action}
```

### 6.2 Demo Script

**Path**: `.claude/PRPs/demos/demo-script-{customer}-{date}.md`

### 6.3 Checklist

**Path**: `.claude/PRPs/demos/demo-checklist-{date}.md`

---

## Phase 7: PRESENT TO USER

```markdown
## Demo Environment Status

**Status**: {READY/NOT READY}
**Last Checked**: {timestamp}

### Quick Actions

- `/prp-demo --reset` - Reset to clean state
- `/prp-demo --scenario "CompanyName"` - Customize for prospect
- `/prp-demo --checklist` - Pre-demo checklist

### Artifacts

📄 **Status Report**: `.claude/PRPs/demos/demo-status-{date}.md`
📋 **Demo Script**: `.claude/PRPs/demos/demo-script-{date}.md`
✅ **Checklist**: `.claude/PRPs/demos/demo-checklist-{date}.md`

### Next Steps

1. {action based on status}
2. {preparation needed}
```

---

## Success Criteria

- **ENVIRONMENT_CHECKED**: All services verified
- **DATA_READY**: Sample data populated
- **SCENARIO_CONFIGURED**: Customer-specific setup done
- **SCRIPT_PREPARED**: Demo flow documented
- **CHECKLIST_GENERATED**: Pre-demo checklist ready
- **FALLBACKS_READY**: Backup plans documented

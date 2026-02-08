---
description: Voice UX design and analysis - call flows, speech patterns, IVR optimization
argument-hint: "[--design 'flow'] [--analyze] [--optimize] [--script]"
---

# Voice UX Design

**Input**: $ARGUMENTS

---

## Your Mission

Design voice experiences that feel natural, efficient, and human. Create call flows that callers want to use instead of "press 0 for agent."

**Golden Rule**: Voice is the most natural interface - your AI should feel like talking to a helpful person, not navigating a phone tree.

---

## Phase 1: PARSE INPUT

### Input Options

| Input | Action |
|-------|--------|
| `--design "flow"` | Design voice flow/script |
| `--analyze` | Analyze existing voice UX |
| `--optimize` | Find and fix voice UX issues |
| `--script` | Generate voice scripts |
| `--ivr` | Design/optimize IVR menu |
| No flags | Interactive voice UX session |

---

## Phase 2: VOICE UX FUNDAMENTALS

### 2.1 Voice vs Text Differences

```markdown
## Key Differences: Voice vs Chat

| Aspect | Text/Chat | Voice |
|--------|-----------|-------|
| **Pace** | User controls | Bot controls pace |
| **Memory** | Scrollable history | Limited recall |
| **Input** | Precise typing | Imprecise speech |
| **Output** | Scannable | Linear listening |
| **Patience** | Higher | Lower (phone = urgent) |
| **Context** | Desktop/mobile | Often mobile, driving, busy |

### Voice-Specific Challenges

1. **No Visual Cues**
   - Can't show buttons or menus
   - Can't display options list
   - Can't confirm with checkmarks

2. **Temporal Nature**
   - Information flies by
   - Users forget what was said
   - Can't go back easily

3. **Speech Recognition**
   - Accents, dialects
   - Background noise
   - Similar-sounding words
   - Numbers and letters

4. **Cognitive Load**
   - Remembering options
   - Multi-step instructions
   - Complex information
```

### 2.2 Voice UX Principles

```markdown
## Voice UX Best Practices

### 1. Be Concise
- Short sentences (10-15 words max)
- One idea per sentence
- Get to the point quickly

**Bad**: "Thank you for calling. We appreciate your business and are here to help. Before we get started, please note that this call may be recorded for quality and training purposes. Now, how may I assist you today?"

**Good**: "Hi! How can I help you today?"

### 2. Be Conversational
- Use contractions (it's, we'll, I'm)
- Use "you" and "I"
- Sound like a human

**Bad**: "The order status is: shipped. Estimated delivery date: January 18th."

**Good**: "Great news! Your order shipped yesterday and should arrive Thursday."

### 3. Confirm Understanding
- Repeat back key information
- Ask for confirmation on important actions
- Use implicit confirmation where appropriate

**Bad**: "I'll cancel your order."

**Good**: "Just to confirm, you'd like to cancel order 12345 for $79.99. Is that right?"

### 4. Handle Errors Gracefully
- Never blame the user
- Offer alternatives
- Make it easy to try again

**Bad**: "I didn't understand that. Please try again."

**Good**: "I didn't catch that. Could you tell me your order number? It starts with ORD."

### 5. Manage Expectations
- Tell them what's happening
- Provide time estimates
- Fill silence with status updates

**Bad**: [Long silence while looking up order]

**Good**: "Let me look that up... I'm checking our system now... Found it!"
```

---

## Phase 3: VOICE FLOW DESIGN

### 3.1 Call Flow Template

```markdown
## Voice Call Flow: [Name]

### Overview
- **Purpose**: [What this flow accomplishes]
- **Avg Duration**: [Expected call length]
- **Handoff Rate Target**: [<X%]

### Entry Point
[How callers reach this flow - direct dial, IVR selection, transfer]

### Opening
```
[Greeting - max 10 words]
[How can I help - max 10 words]
```

### Core Flow
[Detailed turn-by-turn script]

### Closing
```
[Confirmation of resolution]
[Offer further help]
[Goodbye]
```

### Escalation Triggers
- [Trigger 1]
- [Trigger 2]
- [Trigger 3]
```

### 3.2 Order Status Voice Flow

```markdown
## Voice Flow: Order Status

### Opening

**Bot**: "Hi! Looking for an order? What's your order number?"

[If caller gives order number]
**Bot**: "Got it. Let me look up [order number]...
         Your order shipped yesterday and should arrive Thursday.
         Would you like the tracking number?"

[If caller says yes]
**Bot**: "It's [tracking number]. I can also text this to you. Want me to send it?"

[If caller doesn't have order number]
**Bot**: "No problem. I can look it up by your phone number or email.
         Which would you prefer?"

### Error Handling

**Didn't catch order number**:
"I didn't catch that. Could you say the order number again slowly?
It usually starts with O-R-D."

**Order not found**:
"I couldn't find that order. Let me try looking you up another way.
Can you tell me the email address you used?"

**Multiple orders**:
"I found 3 recent orders. Is this about the one from [date] for [amount]?
Or a different one?"

### Closing

**Bot**: "Anything else I can help with today?"

[If no]
**Bot**: "Great! Your order should arrive Thursday. Have a good one!"

[If yes]
**Bot**: [Route to appropriate flow]
```

### 3.3 Appointment Booking Voice Flow

```markdown
## Voice Flow: Appointment Booking

### Opening

**Bot**: "Hi! I can help you schedule an appointment.
         What type of appointment do you need?"

[Present options verbally or let them speak naturally]

### Collecting Information

**Bot**: "Got it, a [type] appointment.
         Do you have a preferred day this week or next?"

[User responds with preferred time]

**Bot**: "Let me check... I have [time] on [day] available.
         Does that work for you?"

[Confirmation]
**Bot**: "Perfect! I've booked you for [day] at [time].
         We'll send a reminder the day before.
         What number should we text the confirmation to?"

### Confirmation

**Bot**: "You're all set!
         [Day] at [time] with [provider if applicable].
         We'll text you at [number].
         Anything else I can help with?"

### Error Handling

**No availability**:
"I don't have any openings on [day].
How about [alternative day]? I have [time] and [time] available."

**User unsure of type**:
"No worries! Let me ask a few questions to figure out what you need.
[Qualifying questions]"
```

---

## Phase 4: IVR OPTIMIZATION

### 4.1 IVR Best Practices

```markdown
## IVR Design Principles

### 1. Limit Options
- Maximum 4-5 options per menu
- Most common first
- "Something else" always last

**Bad**:
"Press 1 for billing, 2 for orders, 3 for returns, 4 for technical support,
5 for account changes, 6 for new orders, 7 for shipping, 8 for..."

**Good**:
"For orders, press 1.
For returns, press 2.
For something else, press 3."

### 2. Offer Speech
- Let users speak naturally
- "Say 'orders' or press 1"
- Handle common variations

### 3. Fast Path to Human
- Don't bury the agent option
- "Say 'agent' anytime to speak with someone"

### 4. Context Awareness
- Use caller ID for returning customers
- "Hi Sarah, calling about your recent order?"
- Skip unnecessary verification
```

### 4.2 IVR Flow Redesign

```markdown
## Optimized IVR Flow

### Before (Traditional)
```
Welcome to Company. Your call is important to us.
Please listen carefully as our menu has changed.
Para español, presione dos.
For billing, press 1.
For orders, press 2.
For technical support, press 3.
For sales, press 4.
For all other inquiries, press 5.
To repeat this menu, press 9.
[30 seconds before any action]
```

### After (Conversational)
```
Hi! How can I help today?

[Wait for natural speech input]

[If unclear]: "I can help with orders, returns, or connect you with our team.
              Which would you like?"

[If "agent"]: "Sure, connecting you now. Short wait."

[If specific request]: [Route to appropriate AI flow or agent]
```

### Metrics Comparison

| Metric | Before | After |
|--------|--------|-------|
| Avg IVR time | 45 sec | 10 sec |
| Zero-out rate | 35% | 15% |
| Misroutes | 20% | 5% |
| CSAT | 3.2 | 4.5 |
```

---

## Phase 5: VOICE SCRIPT WRITING

### 5.1 Script Writing Guidelines

```markdown
## Voice Script Guidelines

### Structure
1. **Opening**: Greeting + offer to help (< 5 sec)
2. **Body**: Conversation turns (aim for < 30 sec each)
3. **Closing**: Confirm + goodbye (< 10 sec)

### Language Rules

#### Use
- Contractions (I'm, we'll, it's)
- Simple words
- Active voice
- "You" and "I"
- Present tense

#### Avoid
- Jargon
- Acronyms (spell them out)
- Passive voice
- Formal language
- Long sentences

### Number Handling

**Phone Numbers**:
Say: "5-5-5, 1-2-3, 4-5-6-7" (grouped)
Not: "five five five one two three four five six seven"

**Order Numbers**:
Say: "O-R-D, one-two-three-four-five"
Not: "ORD12345"

**Dates**:
Say: "Thursday, January 18th"
Not: "01/18/2024"

**Money**:
Say: "seventy-nine dollars and ninety-nine cents"
Not: "$79.99"

### Pacing

- Pause after questions
- Slow down for important info
- Speed up for routine confirmations
- Use filler for processing time
```

### 5.2 Voice Script Templates

```markdown
## Common Voice Scripts

### Greeting

**Standard**:
"Hi! How can I help you today?"

**Returning Customer**:
"Hi [Name]! Good to hear from you. What can I help with?"

**After Hours**:
"Thanks for calling. We're currently closed but I can still help with [options].
Or leave a message and we'll call you back tomorrow."

### Hold Messages

**Short Hold** (< 30 sec):
"Just a moment while I look that up."
"Checking that now..."
"Almost there..."

**Longer Hold**:
"This is taking a bit longer than usual.
Just another minute..."
"Thanks for your patience. Still working on this..."

### Confirmation

**Simple**:
"Got it!"
"Perfect."
"Done."

**Important Action**:
"Just to confirm: you want to cancel order 12345 for seventy-nine dollars.
Is that right?"

### Error Recovery

**Didn't Understand**:
"Sorry, I didn't catch that. Could you say it again?"

**Still Didn't Understand**:
"I'm having trouble understanding.
Let me try asking differently: [rephrase question]"

**Third Attempt**:
"I'm sorry, I'm not getting this right.
Let me connect you with someone who can help."

### Handoff

**To Agent**:
"I'll connect you with a specialist now.
I've shared our conversation so you won't have to repeat anything.
Just a moment..."

**Queue Wait**:
"Connecting you now. The wait is about [X] minutes.
I'll stay on the line until someone picks up."

### Closing

**Resolved**:
"Great! Is there anything else I can help with?
[If no] Alright, have a great day!"

**Follow-up Needed**:
"I've started that process. You'll get an email confirmation in the next hour.
Any questions before I let you go?"
```

---

## Phase 6: VOICE QUALITY METRICS

### 6.1 Key Metrics

```markdown
## Voice UX Metrics

### Efficiency
| Metric | Target | Description |
|--------|--------|-------------|
| Avg Call Duration | < 3 min | Total call time |
| Avg Turns | < 6 | Back-and-forth exchanges |
| First Call Resolution | > 75% | Resolved without callback |
| Containment Rate | > 60% | Handled by AI, no human |

### Speech Recognition
| Metric | Target | Description |
|--------|--------|-------------|
| Word Error Rate | < 10% | Transcription accuracy |
| Intent Accuracy | > 85% | Correct intent detected |
| Entity Accuracy | > 90% | Correct data extracted |
| Retry Rate | < 15% | "Say that again" requests |

### Experience
| Metric | Target | Description |
|--------|--------|-------------|
| CSAT | > 4.0 | Post-call survey |
| Zero-out Rate | < 15% | Press 0 for agent |
| Hang-up Rate | < 20% | Abandoned before resolution |
| Repeat Call Rate | < 10% | Same issue within 24h |
```

### 6.2 Quality Monitoring

```markdown
## Voice Quality Checklist

### Daily Monitoring
- [ ] Review failed intent detections
- [ ] Check high-volume error types
- [ ] Monitor zero-out patterns
- [ ] Sample call recordings

### Weekly Analysis
- [ ] Containment rate trends
- [ ] Top reasons for handoff
- [ ] Speech recognition issues
- [ ] Customer feedback themes

### Monthly Review
- [ ] Script effectiveness
- [ ] New use cases needed
- [ ] Voice/tone consistency
- [ ] Competitive benchmark
```

---

## Phase 7: OUTPUT

### 7.1 Voice Flow Documentation

**Path**: `.claude/PRPs/voice/flow-{name}-{date}.md`

```markdown
---
flow: "{FLOW_NAME}"
created: {ISO_TIMESTAMP}
version: "1.0"
---

# Voice Flow: {FLOW_NAME}

## Overview
- **Purpose**: [Description]
- **Entry**: [How users reach this flow]
- **Avg Duration**: [Expected time]
- **Containment Target**: [X%]

## Script

### Opening
```
[Opening script]
```

### Main Flow
[Detailed turn-by-turn]

### Error Handling
[Recovery scripts]

### Closing
```
[Closing script]
```

## Metrics
| Metric | Target | Current |
|--------|--------|---------|
| [Metric] | [Target] | [Current] |

## Test Scenarios
1. [Scenario 1]
2. [Scenario 2]
3. [Scenario 3]
```

### 7.2 Summary Output

```markdown
## Voice UX Design Complete

**Flow**: {flow_name}
**Created**: {timestamp}

### Flow Summary

| Aspect | Value |
|--------|-------|
| Entry Points | {N} |
| Avg Turns | {N} |
| Scripts Written | {N} |
| Test Scenarios | {N} |

### Artifacts

📞 **Voice Flow**: `.claude/PRPs/voice/flow-{name}.md`
📝 **Scripts**: `.claude/PRPs/voice/scripts-{name}.md`
🧪 **Test Cases**: `.claude/PRPs/voice/tests-{name}.md`

### Next Steps

1. Record with voice talent / TTS
2. Test with real callers
3. Monitor metrics
4. Iterate on scripts
```

---

## Success Criteria

- **FLOW_DESIGNED**: Complete call flow documented
- **SCRIPTS_WRITTEN**: All turns scripted
- **ERRORS_HANDLED**: Recovery paths defined
- **METRICS_DEFINED**: Success criteria set
- **TESTS_CREATED**: Scenarios for QA
- **VOICE_OPTIMIZED**: Natural, conversational language

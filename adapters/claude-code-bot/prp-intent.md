---
description: Design and analyze chatbot/voicebot intents - intent architecture, utterances, entities
argument-hint: "[--design 'use-case'] [--analyze] [--optimize] [--export]"
---

# Intent Design & Analysis

**Input**: $ARGUMENTS

---

## Your Mission

Design, analyze, and optimize intent architecture for conversational AI. Create robust intent structures that accurately understand user requests.

**Golden Rule**: Good intent design is the foundation of great conversational AI. Be comprehensive, handle edge cases, and avoid overlapping intents.

---

## Phase 1: PARSE INPUT

### Input Options

| Input | Action |
|-------|--------|
| `--design "use-case"` | Design intents for a use case |
| `--analyze` | Analyze existing intent configuration |
| `--optimize` | Find and fix intent issues |
| `--export` | Export intent schema |
| `--test "utterance"` | Test utterance classification |
| No flags | Interactive intent design session |

---

## Phase 2: INTENT DESIGN FUNDAMENTALS

### 2.1 Intent Hierarchy

```markdown
## Intent Architecture Levels

### Level 1: Domains
High-level categories of user needs:
- Support
- Sales
- Account Management
- General Information

### Level 2: Intents
Specific user goals:
- Support > Check Order Status
- Support > Return Item
- Sales > Product Inquiry
- Account > Update Address

### Level 3: Sub-Intents (Optional)
Fine-grained variations:
- Return Item > Initiate Return
- Return Item > Check Return Status
- Return Item > Cancel Return
```

### 2.2 Core Intent Components

```markdown
## Intent Definition Template

### Intent: {intent_name}

**Description**: What the user wants to accomplish

**Training Utterances** (15-30 minimum):
- "{utterance 1}"
- "{utterance 2}"
- "{utterance 3}"
- [variations with different phrasing]

**Required Entities**:
- @order_id: The order number
- @product_name: Product being discussed

**Optional Entities**:
- @date: When applicable
- @reason: For context

**Confidence Threshold**: 0.7 (adjust based on testing)

**Fallback Behavior**: [What to do if below threshold]

**Related Intents**:
- [Similar intents that might overlap]

**Sample Response**:
"I'll help you with [intent]. [Action or question]"
```

---

## Phase 3: DESIGN BY USE CASE

### 3.1 Customer Support Intents

```markdown
## Customer Support Intent Set

### Order Management
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `order.status` | Check order status | "Where's my order?", "Track my package", "When will it arrive?" |
| `order.modify` | Change order | "Change my order", "Update shipping address", "Add item to order" |
| `order.cancel` | Cancel order | "Cancel my order", "I don't want it anymore", "Stop my order" |

### Returns & Refunds
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `return.initiate` | Start return | "I want to return this", "Send it back", "How do I return?" |
| `return.status` | Check return status | "Where's my refund?", "Return status", "When will I get my money?" |
| `return.policy` | Return policy info | "What's your return policy?", "How long to return?", "Can I return this?" |

### Billing & Payment
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `billing.question` | Billing inquiries | "Why was I charged?", "Explain my bill", "Double charged" |
| `billing.update_payment` | Update payment method | "Change my card", "New payment method", "Update billing info" |
| `billing.refund` | Request refund | "I want a refund", "Give me my money back", "Refund please" |

### Account Management
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `account.update` | Update account info | "Change my email", "Update phone number", "New address" |
| `account.password` | Password issues | "Reset password", "Can't log in", "Forgot password" |
| `account.delete` | Delete account | "Delete my account", "Close my account", "Remove my data" |

### Product & Service
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `product.info` | Product information | "Tell me about", "What does it do?", "Product details" |
| `product.availability` | Stock check | "Is it in stock?", "When available?", "Do you have...?" |
| `product.compare` | Compare products | "Difference between", "Which is better?", "Compare..." |

### General
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `greeting` | Hello/Hi | "Hello", "Hi there", "Good morning" |
| `goodbye` | End conversation | "Bye", "Thanks, goodbye", "That's all" |
| `thanks` | Express gratitude | "Thank you", "Thanks", "Appreciate it" |
| `human_handoff` | Request human | "Talk to human", "Real person", "Agent please" |
| `fallback` | Unknown intent | [Catch-all for unrecognized input] |
```

### 3.2 Sales Intents

```markdown
## Sales Intent Set

### Product Interest
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `sales.inquiry` | Product interest | "I'm interested in", "Tell me about pricing", "Looking for..." |
| `sales.demo` | Request demo | "Can I see a demo?", "Show me how it works", "Trial?" |
| `sales.pricing` | Pricing questions | "How much?", "What's the cost?", "Pricing info" |
| `sales.quote` | Request quote | "Get a quote", "Custom pricing", "Enterprise pricing" |

### Evaluation
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `sales.comparison` | Compare to competitors | "vs [competitor]", "How are you different?", "Why should I choose you?" |
| `sales.features` | Feature questions | "Does it have...?", "Can it do...?", "Features?" |
| `sales.integration` | Integration questions | "Works with [tool]?", "API available?", "Integrations?" |

### Conversion
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `sales.signup` | Ready to buy | "I want to sign up", "Ready to start", "Let's do it" |
| `sales.objection` | Hesitation | "Too expensive", "Not sure", "Need to think" |
| `sales.followup` | Follow-up request | "Call me later", "Send info", "Email me details" |
```

### 3.3 Appointment/Booking Intents

```markdown
## Appointment Intent Set

### Booking
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `appointment.book` | Schedule appointment | "Book an appointment", "Schedule a visit", "I need to see..." |
| `appointment.available` | Check availability | "What times available?", "Any openings?", "When can I come?" |
| `appointment.confirm` | Confirm booking | "Confirm my appointment", "Yes that works", "Book that time" |

### Management
| Intent | Description | Example Utterances |
|--------|-------------|-------------------|
| `appointment.reschedule` | Change appointment | "Reschedule", "Change my appointment", "Different time" |
| `appointment.cancel` | Cancel appointment | "Cancel my appointment", "Can't make it", "Need to cancel" |
| `appointment.reminder` | Get reminder | "Remind me", "When's my appointment?", "Appointment details" |
```

---

## Phase 4: ENTITY DESIGN

### 4.1 Common Entity Types

```markdown
## Entity Reference

### System Entities (Built-in)
| Entity | Examples | Use Case |
|--------|----------|----------|
| `@sys.date` | "tomorrow", "next Monday" | Scheduling |
| `@sys.time` | "3pm", "in 2 hours" | Scheduling |
| `@sys.number` | "5", "twenty" | Quantities |
| `@sys.email` | "user@email.com" | Contact info |
| `@sys.phone` | "555-1234" | Contact info |
| `@sys.currency` | "$50", "100 dollars" | Payments |

### Custom Entities
| Entity | Type | Examples |
|--------|------|----------|
| `@order_id` | Pattern | "ORD-12345", "#12345" |
| `@product` | List | Product catalog |
| `@category` | List | "electronics", "clothing" |
| `@size` | List | "small", "medium", "large" |
| `@color` | List | "red", "blue", "green" |
| `@reason` | Free-form | Return/cancel reasons |
```

### 4.2 Entity Extraction Patterns

```markdown
## Entity Patterns

### Order ID
**Pattern**: `ORD-\d{5,8}` or `#\d{5,8}`
**Training Examples**:
- "My order number is ORD-12345"
- "Order #98765"
- "It's 12345678"

### Product Names
**Type**: List with synonyms
**Structure**:
```json
{
  "product_name": "iPhone 15 Pro",
  "synonyms": ["iPhone 15", "new iPhone", "latest iPhone"]
}
```

### Date Expressions
**Handle Relative Dates**:
- "yesterday" → resolve to date
- "last week" → resolve to date range
- "2 days ago" → resolve to date
```

---

## Phase 5: INTENT OPTIMIZATION

### 5.1 Common Issues

```markdown
## Intent Issues to Check

### Overlapping Intents
**Problem**: Multiple intents match same utterance
**Solution**: Merge, differentiate, or add more training data

**Example Overlap**:
- `order.status` vs `shipping.tracking`
- Both triggered by "Where's my package?"
- **Fix**: Merge into single intent or differentiate by context

### Under-trained Intents
**Problem**: Too few training utterances (<15)
**Solution**: Add more varied examples

### Over-fitted Intents
**Problem**: Too specific, misses variations
**Solution**: Add diverse phrasing, handle typos

### Missing Intents
**Problem**: Common requests not handled
**Solution**: Analyze fallback logs, add new intents

### Low Confidence
**Problem**: Correct intent but low confidence score
**Solution**: Add more training examples, reduce overlap
```

### 5.2 Testing Matrix

```markdown
## Intent Testing

### Test Cases Template

| Test Utterance | Expected Intent | Actual Intent | Confidence | Status |
|----------------|-----------------|---------------|------------|--------|
| "Where's my order?" | order.status | order.status | 0.95 | ✅ |
| "Track package" | order.status | shipping.info | 0.72 | ❌ Fix |
| "Whrre is my ordr" | order.status | order.status | 0.85 | ✅ (typo handled) |
| "asdfghjkl" | fallback | fallback | N/A | ✅ |

### Test Categories
- [ ] Happy path (clear, well-formed requests)
- [ ] Typos and misspellings
- [ ] Informal language / slang
- [ ] Multiple intents in one utterance
- [ ] Edge cases and ambiguous requests
- [ ] Adversarial inputs
```

---

## Phase 6: OUTPUT

### 6.1 Intent Schema Export

```markdown
## Intent Schema

**Path**: `.claude/PRPs/intents/intent-schema-{date}.json`

```json
{
  "version": "1.0",
  "created": "{timestamp}",
  "intents": [
    {
      "name": "order.status",
      "description": "Check order status",
      "training_phrases": [
        "Where is my order?",
        "Track my package",
        "Order status for {order_id}"
      ],
      "entities": [
        {
          "name": "order_id",
          "required": false
        }
      ],
      "responses": [
        "Let me check on order {order_id} for you.",
        "I'll look up your order status."
      ],
      "confidence_threshold": 0.7,
      "contexts": []
    }
  ],
  "entities": [
    {
      "name": "order_id",
      "type": "pattern",
      "pattern": "ORD-\\d{5,8}|#\\d{5,8}"
    }
  ]
}
```

### 6.2 Intent Documentation

**Path**: `.claude/PRPs/intents/intent-documentation-{date}.md`

```markdown
## Intent Documentation

### Overview
- Total Intents: {N}
- Total Entities: {N}
- Coverage: {list of use cases}

### Intent Reference

#### order.status
**Purpose**: Check order status
**Required Entities**: None (order_id optional)
**Confidence Threshold**: 0.7

**Training Phrases**:
1. Where is my order?
2. Track my package
3. When will order {order_id} arrive?
[... 15+ more]

**Responses**:
- With order_id: "Let me check on order {order_id}..."
- Without order_id: "I can help! What's your order number?"

**Edge Cases**:
- Multiple orders: Ask which one
- No orders found: Verify identity

---
[Repeat for each intent]
```

### 6.3 Summary Output

```markdown
## Intent Design Complete

**Use Case**: {use_case}
**Intents Created**: {N}
**Entities Defined**: {N}

### Intent Summary

| Domain | Intents | Coverage |
|--------|---------|----------|
| Order Management | 5 | ✅ Complete |
| Returns | 3 | ✅ Complete |
| Account | 4 | ✅ Complete |
| General | 4 | ✅ Complete |

### Entities Summary

| Entity | Type | Examples |
|--------|------|----------|
| order_id | Pattern | ORD-12345 |
| product | List | [catalog] |

### Artifacts

📄 **Schema**: `.claude/PRPs/intents/intent-schema-{date}.json`
📋 **Documentation**: `.claude/PRPs/intents/intent-documentation-{date}.md`
🧪 **Test Cases**: `.claude/PRPs/intents/intent-tests-{date}.md`

### Next Steps

1. Import schema to your NLU platform
2. Run test cases
3. Review confidence scores
4. Iterate based on real conversations
```

---

## Success Criteria

- **INTENTS_DESIGNED**: All user needs mapped to intents
- **UTTERANCES_CREATED**: 15+ training phrases per intent
- **ENTITIES_DEFINED**: All extractable data identified
- **OVERLAPS_RESOLVED**: No conflicting intents
- **SCHEMA_EXPORTED**: Ready for import
- **TESTS_CREATED**: Test cases for validation

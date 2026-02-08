---
description: Plan and design integrations - CRM, ticketing, telephony, and custom APIs
argument-hint: "[--plan 'system-name'] [--design] [--document] [--troubleshoot]"
---

# Integration Planning & Design

**Input**: $ARGUMENTS

---

## Your Mission

Plan, design, and document integrations that connect your AI call center/chatbot with customer systems like CRMs, helpdesks, and telephony platforms.

**Golden Rule**: Good integrations are invisible to users - data flows seamlessly, and the AI always has context.

---

## Phase 1: PARSE INPUT

### Input Options

| Input | Action |
|-------|--------|
| `--plan "system"` | Plan integration with specific system |
| `--design` | Design integration architecture |
| `--document` | Generate integration documentation |
| `--troubleshoot` | Diagnose integration issues |
| `--api` | Generate API documentation |
| No flags | Interactive integration planning |

---

## Phase 2: COMMON INTEGRATIONS

### 2.1 Integration Categories

```markdown
## Integration Landscape

### CRM Systems
| System | Use Case | Complexity |
|--------|----------|------------|
| Salesforce | Customer data, cases | High |
| HubSpot | Contacts, deals | Medium |
| Zoho CRM | Customer info | Medium |
| Pipedrive | Sales pipeline | Low |

### Helpdesk/Ticketing
| System | Use Case | Complexity |
|--------|----------|------------|
| Zendesk | Tickets, knowledge base | Medium |
| Freshdesk | Tickets, contacts | Medium |
| Intercom | Conversations | Low |
| ServiceNow | Enterprise tickets | High |

### Telephony
| System | Use Case | Complexity |
|--------|----------|------------|
| Twilio | Voice, SMS | Medium |
| Vonage | Voice, messaging | Medium |
| Amazon Connect | Contact center | High |
| Genesys Cloud | Enterprise CC | High |

### E-commerce
| System | Use Case | Complexity |
|--------|----------|------------|
| Shopify | Orders, products | Low |
| WooCommerce | Orders, products | Low |
| Magento | Orders, inventory | Medium |
| BigCommerce | Orders, customers | Medium |

### Messaging
| System | Use Case | Complexity |
|--------|----------|------------|
| WhatsApp Business | Messaging | Medium |
| Facebook Messenger | Chat | Low |
| Slack | Internal comms | Low |
| Microsoft Teams | Internal comms | Medium |

### Custom/Other
| System | Use Case | Complexity |
|--------|----------|------------|
| REST APIs | Custom data | Varies |
| Webhooks | Event notifications | Low |
| Database | Direct access | Medium |
| Legacy systems | SOAP, FTP | High |
```

### 2.2 Integration Data Flows

```markdown
## Common Data Flows

### Customer Lookup
```
[User calls/chats]
     │
     ▼
[Identify user: phone/email/account]
     │
     ▼
[Query CRM: GET /contacts?phone={phone}]
     │
     ▼
[Receive: name, history, segment, preferences]
     │
     ▼
[Personalize conversation: "Hi Sarah!"]
```

### Ticket Creation
```
[Conversation ends - unresolved or escalated]
     │
     ▼
[Gather: transcript, summary, intent, entities]
     │
     ▼
[Create ticket: POST /tickets]
     │
     Body: {
       subject: "AI summary",
       description: "Transcript",
       priority: "based on sentiment",
       customer_id: "from CRM",
       tags: ["ai-created", "intent"]
     }
     │
     ▼
[Return ticket ID to conversation]
[Notify: "Created ticket #12345"]
```

### Order Status
```
[User: "Where's my order?"]
     │
     ▼
[Extract: order_id or identify customer]
     │
     ▼
[Query: GET /orders/{id} or /customers/{id}/orders]
     │
     ▼
[Receive: status, shipping, tracking]
     │
     ▼
[Format response: "Your order shipped yesterday..."]
```
```

---

## Phase 3: INTEGRATION DESIGN

### 3.1 Design Template

```markdown
## Integration Design: [System Name]

### Overview
- **System**: [Name and version]
- **Purpose**: [What this integration enables]
- **Direction**: Inbound / Outbound / Bidirectional
- **Priority**: Must-have / Nice-to-have

### Use Cases
1. [Use case 1: description]
2. [Use case 2: description]
3. [Use case 3: description]

### Data Requirements

#### Data We Need (Inbound)
| Field | Source | Required | Used For |
|-------|--------|----------|----------|
| [Field] | [API endpoint] | Yes/No | [Purpose] |

#### Data We Send (Outbound)
| Field | Destination | Required | Trigger |
|-------|-------------|----------|---------|
| [Field] | [API endpoint] | Yes/No | [When] |

### Authentication
- **Method**: OAuth 2.0 / API Key / Basic Auth
- **Credentials**: [Where stored]
- **Refresh**: [Token refresh strategy]

### API Endpoints

#### Endpoint 1: [Name]
- **URL**: `{base_url}/api/v1/resource`
- **Method**: GET/POST/PUT/DELETE
- **Purpose**: [Description]
- **Request**:
  ```json
  {
    "field": "value"
  }
  ```
- **Response**:
  ```json
  {
    "field": "value"
  }
  ```

### Error Handling
| Error Code | Meaning | Action |
|------------|---------|--------|
| 401 | Unauthorized | Refresh token |
| 404 | Not found | Return "not found" to user |
| 429 | Rate limited | Queue and retry |
| 500 | Server error | Fallback, alert |

### Rate Limits
- **Limit**: [X requests per Y time]
- **Strategy**: [Queue, cache, or throttle]

### Testing
- [ ] Unit tests for API calls
- [ ] Integration tests with sandbox
- [ ] Error scenario tests
- [ ] Performance tests under load
```

### 3.2 Salesforce Integration Example

```markdown
## Integration Design: Salesforce

### Overview
- **System**: Salesforce Sales Cloud
- **Purpose**: Customer lookup, case creation, activity logging
- **Direction**: Bidirectional

### Use Cases
1. **Customer Identification**: Look up caller by phone/email
2. **Context Retrieval**: Get recent cases, orders, account info
3. **Case Creation**: Create case from unresolved conversation
4. **Activity Logging**: Log conversation as activity

### Authentication
- **Method**: OAuth 2.0 (JWT Bearer Flow for server-to-server)
- **Credentials**: Connected App credentials in secure vault
- **Refresh**: Auto-refresh before expiration

### API Endpoints

#### 1. Customer Lookup
- **URL**: `/services/data/v58.0/query`
- **Method**: GET
- **Query**:
  ```sql
  SELECT Id, Name, Email, Phone, Account.Name
  FROM Contact
  WHERE Phone = '{phone}'
  ```
- **Response**:
  ```json
  {
    "records": [{
      "Id": "003xx",
      "Name": "John Smith",
      "Email": "john@email.com",
      "Account": {"Name": "Acme Corp"}
    }]
  }
  ```

#### 2. Create Case
- **URL**: `/services/data/v58.0/sobjects/Case`
- **Method**: POST
- **Request**:
  ```json
  {
    "Subject": "AI: Order inquiry",
    "Description": "Customer called about order #12345...",
    "ContactId": "003xx",
    "Priority": "Medium",
    "Origin": "AI Voice",
    "AI_Summary__c": "Customer inquired about order status...",
    "AI_Sentiment__c": "Neutral"
  }
  ```

#### 3. Log Activity
- **URL**: `/services/data/v58.0/sobjects/Task`
- **Method**: POST
- **Request**:
  ```json
  {
    "Subject": "AI Call - Order Status",
    "Description": "Full transcript...",
    "WhoId": "003xx",
    "Status": "Completed",
    "Priority": "Normal",
    "Type": "Call"
  }
  ```

### Error Handling
| Scenario | Response Code | Action |
|----------|---------------|--------|
| Auth expired | 401 | Refresh token, retry |
| Contact not found | 200 (empty) | Create new or continue anonymously |
| Rate limited | 429 | Queue, exponential backoff |
| Field validation error | 400 | Log, proceed without logging |

### Custom Fields (Recommended)
Create these custom fields in Salesforce:
- `AI_Summary__c`: Text - AI-generated conversation summary
- `AI_Sentiment__c`: Picklist - Positive/Neutral/Negative
- `AI_Intent__c`: Text - Detected customer intent
- `AI_Resolved__c`: Checkbox - Was AI able to resolve?
```

### 3.3 Zendesk Integration Example

```markdown
## Integration Design: Zendesk

### Overview
- **System**: Zendesk Support
- **Purpose**: Ticket creation, knowledge base queries
- **Direction**: Bidirectional

### Use Cases
1. **Ticket Creation**: Create ticket from unresolved conversations
2. **Ticket Lookup**: Check status of existing tickets
3. **Knowledge Base**: Search articles for answers

### Authentication
- **Method**: API Token
- **Header**: `Authorization: Basic {base64(email:token)}`

### API Endpoints

#### 1. Create Ticket
- **URL**: `/api/v2/tickets.json`
- **Method**: POST
- **Request**:
  ```json
  {
    "ticket": {
      "subject": "AI: Order return request",
      "comment": {
        "body": "Customer transcript:\n\n...",
        "public": false
      },
      "requester": {
        "email": "customer@email.com",
        "name": "Customer Name"
      },
      "priority": "normal",
      "tags": ["ai-created", "return-request"],
      "custom_fields": [
        {"id": 12345, "value": "ai_sentiment_neutral"}
      ]
    }
  }
  ```

#### 2. Search Knowledge Base
- **URL**: `/api/v2/help_center/articles/search.json`
- **Method**: GET
- **Query**: `?query={search_terms}`
- **Response**:
  ```json
  {
    "results": [{
      "title": "How to return an item",
      "body": "To return an item...",
      "html_url": "https://help.company.com/article/123"
    }]
  }
  ```

#### 3. Get Ticket Status
- **URL**: `/api/v2/tickets/{id}.json`
- **Method**: GET
```

---

## Phase 4: TELEPHONY INTEGRATION

### 4.1 Twilio Integration

```markdown
## Integration Design: Twilio

### Overview
- **System**: Twilio Voice & Messaging
- **Purpose**: Handle inbound/outbound calls, SMS
- **Direction**: Bidirectional

### Voice Flow

#### Inbound Call
```
[User calls Twilio number]
         │
         ▼
[Twilio webhook: POST /incoming-call]
         │
         ▼
[Your server returns TwiML]
         │
    ┌────┴────┐
    ▼         ▼
[Stream to    [Gather DTMF/
 AI service]   Speech]
         │
         ▼
[AI processes, generates response]
         │
         ▼
[TwiML <Say> or <Play> response]
```

#### TwiML Example
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Gather input="speech" action="/process-speech" timeout="5">
    <Say voice="Polly.Joanna">Hi! How can I help you today?</Say>
  </Gather>
  <Say>I didn't hear anything. Goodbye.</Say>
</Response>
```

### Webhook Endpoints

#### POST /incoming-call
Triggered when call starts
- Returns: Initial greeting TwiML

#### POST /process-speech
Triggered with speech recognition result
- Input: `SpeechResult`, `Confidence`
- Returns: AI response TwiML

#### POST /call-status
Triggered on call status change
- Input: `CallStatus`, `CallDuration`
- Action: Log call, update CRM

### SMS Flow

#### Inbound SMS
```
[User texts Twilio number]
         │
         ▼
[Twilio webhook: POST /incoming-sms]
         │
         ▼
[AI processes message]
         │
         ▼
[Respond via Twilio API]
```

#### Send SMS
```python
client.messages.create(
    body="Your order shipped! Track: {link}",
    from_="+1XXXXXXXXXX",
    to="+1YYYYYYYYYY"
)
```
```

---

## Phase 5: INTEGRATION TESTING

### 5.1 Test Plan

```markdown
## Integration Test Plan

### Unit Tests
- [ ] Authentication works
- [ ] API calls return expected format
- [ ] Error handling catches all cases
- [ ] Rate limiting is respected

### Integration Tests
- [ ] End-to-end customer lookup
- [ ] End-to-end ticket creation
- [ ] Webhook receives and processes correctly
- [ ] Data syncs both directions

### Scenario Tests

| Scenario | Steps | Expected | Pass/Fail |
|----------|-------|----------|-----------|
| New customer | Call, not in CRM | Create contact | |
| Known customer | Call, in CRM | Personalized greeting | |
| Create ticket | Unresolved conversation | Ticket in Zendesk | |
| Order lookup | Ask for order status | Correct status returned | |

### Error Scenarios

| Scenario | Expected Behavior |
|----------|-------------------|
| CRM down | Fallback to anonymous, log error |
| Auth expired | Auto-refresh, retry |
| Rate limited | Queue, retry with backoff |
| Invalid data | Log, continue without integration |
```

### 5.2 Monitoring

```markdown
## Integration Monitoring

### Health Checks
- [ ] Ping each integration every 5 minutes
- [ ] Alert on 3 consecutive failures
- [ ] Dashboard showing integration status

### Metrics to Track
| Metric | Threshold | Alert |
|--------|-----------|-------|
| API latency | > 500ms | Warning |
| Error rate | > 1% | Alert |
| Auth failures | Any | Immediate |
| Rate limit hits | > 10/hour | Warning |

### Logging
Log all integration calls:
```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "integration": "salesforce",
  "endpoint": "/contacts/lookup",
  "duration_ms": 150,
  "status": "success",
  "request_id": "abc123"
}
```
```

---

## Phase 6: DOCUMENTATION

### 6.1 Integration Documentation Template

```markdown
## Integration Documentation: [System Name]

### Quick Start

#### Prerequisites
- [ ] API credentials from [System]
- [ ] Webhook URL configured
- [ ] IP whitelist updated

#### Setup Steps
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Configuration

#### Environment Variables
```env
SYSTEM_API_KEY=xxxx
SYSTEM_API_SECRET=yyyy
SYSTEM_BASE_URL=https://api.system.com
SYSTEM_WEBHOOK_SECRET=zzzz
```

#### Webhook Configuration
| Webhook | URL | Events |
|---------|-----|--------|
| [Name] | `https://your-app.com/webhooks/system` | [events] |

### API Reference

[Detailed API endpoints]

### Troubleshooting

#### Common Issues

**Issue: Authentication fails**
- Check: API key validity
- Check: IP whitelist
- Solution: Regenerate credentials

**Issue: Data not syncing**
- Check: Webhook configuration
- Check: Field mapping
- Solution: Verify webhook URL, check logs

### Support
- [System] Documentation: [link]
- [System] Status Page: [link]
- Internal Contact: [name/email]
```

---

## Phase 7: OUTPUT

### 7.1 Save Documentation

**Paths**:
- `.claude/PRPs/integrations/{system}-design.md`
- `.claude/PRPs/integrations/{system}-documentation.md`
- `.claude/PRPs/integrations/{system}-tests.md`

### 7.2 Summary Output

```markdown
## Integration Planning Complete

**System**: {system_name}
**Status**: {Planned / In Progress / Live}

### Integration Summary

| Aspect | Details |
|--------|---------|
| Direction | Inbound / Outbound / Bidirectional |
| Auth Method | OAuth / API Key / etc. |
| Endpoints | {N} configured |
| Data Flows | {N} use cases |

### Artifacts

📐 **Design Doc**: `.claude/PRPs/integrations/{system}-design.md`
📖 **Documentation**: `.claude/PRPs/integrations/{system}-docs.md`
🧪 **Test Plan**: `.claude/PRPs/integrations/{system}-tests.md`

### Next Steps

1. Obtain API credentials
2. Set up development/sandbox environment
3. Implement and test each endpoint
4. Deploy to staging
5. Go live with monitoring
```

---

## Success Criteria

- **REQUIREMENTS_GATHERED**: All use cases documented
- **DESIGN_COMPLETE**: Architecture and data flows defined
- **AUTH_CONFIGURED**: Authentication method set up
- **ENDPOINTS_DOCUMENTED**: All API endpoints detailed
- **ERRORS_HANDLED**: Error scenarios planned
- **TESTS_CREATED**: Test plan ready
- **DOCUMENTATION_COMPLETE**: Ready for implementation

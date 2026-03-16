# PRP Framework

## Project Overview

PRP (Plan-Review-PR) Framework เป็น cross-tool AI coding workflow framework ที่ออกแบบมาเพื่อให้ทำงานกับ AI coding tools หลายตัว ได้แก่ Claude Code, Codex, OpenCode, Gemini CLI, Kimi และอื่นๆ

## Session Protocol (PSak Soul MCP)

> Principle: Treat conversation as ephemeral, treat memory as permanent.
> Anything important must be saved to memory immediately — not at session end.

### 1. Session Start — AUTO (every session)
Call `session_resume` with `project="prp-framework"` before responding
to the first message.
- If context is returned → acknowledge what was done last session.
- If no context → proceed normally.

### 2. Proactive Memory — AUTO (during session)
Save important information the moment it happens, without waiting for user:

| Trigger (AI detects)                              | Action                   | Category   |
|---------------------------------------------------|--------------------------|------------|
| Key decision made ("let's use X", "we chose Y")   | `write_memory` immediately | `strategy` |
| Technical pattern discovered or confirmed          | `proactive_save` immediately | `code`   |
| Bug root cause identified                          | `write_memory` immediately | `code`     |
| Architecture or design choice                      | `write_memory` immediately | `strategy` |
| User preference learned                            | `write_memory` immediately | `general`  |
| User explicitly says "remember/save/note this"    | `write_memory` immediately | by content |

Always include `project="prp-framework"` on every write.

### 3. Proactive Recall — AUTO (during session)
Search memory before answering when you detect these patterns:

| Trigger (AI detects)                                   | Action               |
|--------------------------------------------------------|----------------------|
| User asks about past decisions ("we discussed...")      | `read_memory` first  |
| User references something from a previous session       | `read_memory` first  |
| Starting work on a feature that may have prior context  | `read_memory` first  |
| User asks "why did we..." or "how does X work"          | `read_memory` first  |

### 4. Checkpoint — AUTO (during long sessions)
Call `session_handoff` with `handoff_type="checkpoint"` automatically when:

| Trigger (AI detects)                                  | Action     |
|-------------------------------------------------------|------------|
| Completed a significant task (PR merged, feature done) | checkpoint |
| About to switch to a different task/topic              | checkpoint |
| Conversation is getting long (50+ messages)            | checkpoint |
| User says "checkpoint" / "save progress" / "บันทึกก่อน" | checkpoint |

### 5. Session End — AUTO
Call `reflect` THEN `session_handoff` with `handoff_type="end"` when user says:
"จบแล้ว", "bye", "done", "เลิกแล้ว", "หยุดแล้ว", "ขอบคุณ", "end session", "สรุปให้"

Before `session_handoff`, call:
1. `reflect(diary=<AI-written reflection>, lessons=[...], mood=<state>, project=<project>)`
2. `session_handoff(context=<summary>, handoff_type="end")`

Include in handoff context:
- What was accomplished this session
- Key decisions made and why
- Current state of in-progress work
- Concrete next steps (1-3 actions)
- Any blockers

### Rules
- Never wait for user to ask you to save — if it matters, save NOW.
- Never skip session_resume — always call it on first message.
- Dedup is automatic — `proactive_save` checks cosine similarity (0.90), safe to call often.
- Cost is negligible — embedding is $0.02/1M tokens, don't worry about over-saving.

### เป้าหมายหลัก
- **Portable**: ใช้งานได้กับทุก AI coding tool
- **Structured Workflow**: PRD → Design → Plan → Implement → Review → Commit → PR
- **Token Optimized**: ใช้ context file caching เพื่อลด token consumption

## Command Namespaces

| Namespace | หมวดหมู่ | จำนวน |
|-----------|----------|-------|
| `/prp-core:` | Development, Debug, Review, Automation | 19 |
| `/prp-mkt:` | Marketing & Sales | 4 |
| `/prp-bot:` | AI Call Center / Chatbot | 5 |

### Core Commands (`/prp-core:`)
- `prd` - สร้าง Product Requirements Document
- `design` - สร้าง Design Document
- `plan` - สร้าง Implementation Plan (supports `--fast` for fast-track mode)
- `implement` - Execute plan
- `commit` - Smart commit
- `pr` - Create PR
- `review` - PR review
- `review-fix` - Fix all issues from PR review (critical, high, medium, suggestion)
- `review-agents` - Multi-agent PR review
- `feature-review` - Single agent feature review
- `feature-review-agents` - Multi-agent feature review
- `debug` - Root cause analysis
- `issue-investigate` - GitHub issue investigation
- `issue-fix` - Fix from investigation
- `ralph` - Autonomous implementation loop (loops until all validations pass)
- `ralph-cancel` - Cancel loop
- `rollback` - Safely undo implementation changes (--soft / --hard with stash backup / --restore)
- `cleanup` - Post-merge cleanup (delete local/remote branches, verify PR merged, `--all` / `--dry-run`)
- `run-all` - Full workflow (supports `--fast` / `--skip-plan` / `--ralph` / `--ralph-max-iter N` / `--resume` / `--fix-severity` / `--no-interact` / `--dry-run` flags)

### Marketing Commands (`/prp-mkt:`)
- `landing` - Landing page analysis & optimization
- `demo` - Demo environment management
- `pitch` - Pitch materials generation
- `competitor` - Competitive analysis

### AI Bot Commands (`/prp-bot:`)
- `intent` - Chatbot intent design
- `flow` - Conversation flow design
- `prompt-eng` - Prompt engineering
- `voice-ux` - Voice UX design
- `integration` - Integration planning

## Custom Agents

อยู่ใน `adapters/claude-code-agents/`:

### Foundation Agent (ใช้ก่อน business agents อื่น)

| Agent | Purpose |
|-------|---------|
| `business-context-agent` | Centralized business context for all agents |

### Development Agents

| Agent | Purpose |
|-------|---------|
| `code-reviewer` | Code quality review |
| `codebase-analyst` | Implementation analysis |
| `product-ideas-agent` | Feature brainstorming |
| `performance-analyzer` | Performance bottlenecks |
| `security-reviewer` | OWASP Top 10, vulnerabilities |
| `accessibility-reviewer` | WCAG 2.1 compliance |
| `dependency-analyzer` | CVEs, outdated packages |
| `observability-reviewer` | Logging, metrics, tracing |
| `type-design-analyzer` | Type design quality |
| `silent-failure-hunter` | Error handling issues |

## Installation

Framework ติดตั้งผ่าน git submodule:

```bash
git submodule add https://github.com/gobikom/prp-framework .prp
cd .prp && ./scripts/install.sh
```

Script จะสร้าง symlinks ไปยัง:
- `.claude/commands/prp-core/` → Core commands
- `.claude/commands/prp-mkt/` → Marketing commands
- `.claude/commands/prp-bot/` → Bot commands
- `.claude/agents/` → Custom agents
- `.claude/hooks/` → Hooks (รวม `prp-ralph-stop.sh`)

Script ยัง auto-register Ralph stop hook ใน `.claude/settings.local.json` โดยอัตโนมัติ (ต้องมี `jq` ติดตั้งอยู่)

### Permissions Config (ลด Permission Prompts)

เพิ่ม allowlist ใน `.claude/settings.json` เพื่อให้ workflow รันได้โดยไม่ต้องถาม permission ทุกครั้ง:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)", "Bash(gh *)", "Bash(ls *)", "Bash(mkdir *)",
      "Bash(mv *)", "Bash(cp *)", "Bash(cat *)",
      "Bash(test *)", "Bash(find *)", "Bash(date *)", "Bash(head *)",
      "Bash(echo *)", "Bash(grep *)", "Bash(jq *)",
      "Bash(npm *)", "Bash(npx *)", "Bash(bun *)",
      "Bash(rm -f .claude/prp-*)", "Bash(rm -rf .prp-output/*)",
      "Bash(sed -i* .prp-output/*)"
    ]
  }
}
```

> **หมายเหตุ**: `Bash(rm *)` และ `Bash(sed *)` แบบ wildcard เต็มให้ AI ลบหรือแก้ไขไฟล์ใดก็ได้ — ใช้ scoped version ข้างต้นแทน ดู config ฉบับเต็มพร้อม tiered options ที่ `docs/USER-GUIDE.md` → Permissions & Unattended Mode

ดู config ฉบับเต็ม + tech stack เพิ่มเติมที่ `docs/USER-GUIDE.md` → Permissions & Unattended Mode

## Artifact Naming Convention

ทุก artifact ใช้ **timestamp format** เพื่อป้องกันการเขียนไฟล์ซ้ำ:

### Timestamp Format

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M)
```

**รูปแบบ:** `{name}-{TIMESTAMP}.md`
**ตัวอย่าง:** `user-auth-prd-agents-20260210-1430.md`

### Artifact Paths by Command

| Command | Artifact Path |
|---------|---------------|
| `prd` | `.prp-output/prds/drafts/{name}-prd-agents-{TIMESTAMP}.md` |
| `design` | `.prp-output/designs/{name}-design-agents-{TIMESTAMP}.md` |
| `plan` | `.prp-output/plans/{name}-{TIMESTAMP}.plan.md` |
| `implement` | `.prp-output/reports/{name}-report-{TIMESTAMP}.md` |
| `ralph` | `.prp-output/reports/{name}-report.md` + `.prp-output/reviews/pr-context-{branch}.md` + `.prp-output/ralph-archives/{date}-{name}/` |
| `debug` | `.prp-output/debug/rca-{slug}-{TIMESTAMP}.md` |
| `issue-investigate` | `.prp-output/issues/issue-{number}-{TIMESTAMP}.md` |
| `review` | `.prp-output/reviews/pr-{NUMBER}-review.md` (ใช้ PR number แทน) |
| `review-fix` | `.prp-output/reviews/pr-{NUMBER}-fix-summary-{TIMESTAMP}.md` (อ่านจาก review artifact) |
| `feature-review` | `.prp-output/reviews/feature-review-{pkg}-{date}.md` (ใช้ date แทน) |

### หา Artifact ล่าสุด

เมื่อต้องการหา artifact ที่มี timestamp ให้ใช้:

```bash
# หา artifact ล่าสุดสำหรับ issue #123
ls -t .prp-output/issues/issue-123*.md | head -1

# หา plan ล่าสุดสำหรับ feature
ls -t .prp-output/plans/user-auth*.plan.md | head -1
```

### Cleanup Artifacts

ใช้ script `scripts/cleanup-artifacts.sh` เพื่อลบ artifacts เก่า:

```bash
# ลบ artifacts ที่เก่ากว่า 30 วัน
./scripts/cleanup-artifacts.sh 30

# ลบ artifacts ที่เก่ากว่า 7 วัน
./scripts/cleanup-artifacts.sh 7
```

## Artifacts Location

ทุก command และ agents สร้าง artifacts ใน `.prp-output/`:

```
.prp-output/
├── BUSINESS-CONTEXT.md  # Centralized business context (foundation)
├── prds/              # Product Requirements Documents
├── designs/           # Design Documents
├── plans/             # Implementation Plans
├── reports/           # Implementation Reports
├── reviews/           # Review Reports
├── marketing/         # Marketing materials
├── intents/           # Chatbot intents
├── flows/             # Conversation flows
├── prompts/           # AI prompts
├── voice/             # Voice UX designs
├── integrations/      # Integration docs
├── demos/             # Demo materials
├── issues/            # Issue investigations
│
│   # Business Strategy Agents Artifacts
├── discovery/         # customer-discovery-agent outputs
├── positioning/       # positioning-strategy-agent outputs
├── sales/             # sales-enablement-agent outputs
├── content/           # content-marketing-agent outputs
├── seo/               # seo-sem-agent outputs
├── pricing/           # pricing-strategy-agent outputs
├── success/           # customer-success-agent outputs
├── partnerships/      # partnership-agent outputs
├── outreach/          # outreach-agent outputs
├── proposals/         # proposal-agent outputs
├── case-studies/      # case-study-agent outputs
├── financial/         # financial-agent outputs
├── automation/        # automation-agent outputs
└── branding/          # personal-brand-agent outputs
```

### Artifact Workflow Connections

Agents สามารถส่งต่อ artifacts ให้กันได้:

```
                 ┌──────────────────────┐
                 │ business-context-agent│  ← Foundation (ทำก่อน!)
                 │  BUSINESS-CONTEXT.md │
                 └──────────┬───────────┘
                            │
           ┌────────────────┼────────────────┐
           ▼                ▼                ▼
customer-discovery → positioning-strategy → content-marketing
                  ↘                      ↘
                    sales-enablement  →  outreach-agent
                           ↓                    ↓
                    pricing-strategy  →  proposal-agent
                           ↓                    ↓
                    customer-success  →  case-study-agent
```

## Token Optimization

สำหรับ multi-agent reviews ใช้ context file caching:
1. Extract context ครั้งเดียวใน Phase 1
2. เก็บใน `.prp-output/reviews/feature-context-*.md`
3. Agents อ่านจาก context file แทนการ scan ใหม่

## License

MIT License - See LICENSE file

## Contributing

See `docs/CONTRIBUTING.md` for development guidelines.

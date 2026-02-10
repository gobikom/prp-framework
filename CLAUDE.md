# PRP Framework

## Project Overview

PRP (Plan-Review-PR) Framework เป็น cross-tool AI coding workflow framework ที่ออกแบบมาเพื่อให้ทำงานกับ AI coding tools หลายตัว ได้แก่ Claude Code, Codex, OpenCode, Gemini CLI, Kimi และอื่นๆ

### เป้าหมายหลัก
- **Portable**: ใช้งานได้กับทุก AI coding tool
- **Structured Workflow**: PRD → Design → Plan → Implement → Review → Commit → PR
- **Token Optimized**: ใช้ context file caching เพื่อลด token consumption

## Project Structure

```
prp-framework/
├── adapters/                      # Tool-specific adapters
│   ├── claude-code/               # Core commands (16 commands)
│   ├── claude-code-marketing/     # Marketing commands (4 commands)
│   ├── claude-code-bot/           # AI Bot commands (5 commands)
│   ├── claude-code-agents/        # Custom agents (31 agents)
│   ├── claude-code-skills/        # Skills
│   ├── claude-code-hooks/         # Hooks
│   ├── codex/                     # Codex adapter
│   ├── opencode/                  # OpenCode adapter
│   ├── gemini/                    # Gemini adapter
│   └── generic/                   # Generic AGENTS.md
├── prompts/                       # Source prompts (tool-agnostic)
├── scripts/                       # Installation scripts
│   └── install.sh                 # Main installer
├── docs/                          # Documentation
│   ├── USER-GUIDE.md              # Complete command reference
│   ├── GETTING_STARTED.md
│   ├── WORKFLOWS.md
│   └── CONTRIBUTING.md
└── README.md
```

## Command Namespaces

| Namespace | หมวดหมู่ | จำนวน |
|-----------|----------|-------|
| `/prp-core:` | Development, Debug, Review, Automation | 16 |
| `/prp-mkt:` | Marketing & Sales | 4 |
| `/prp-bot:` | AI Call Center / Chatbot | 5 |

### Core Commands (`/prp-core:`)
- `prd` - สร้าง Product Requirements Document
- `design` - สร้าง Design Document
- `plan` - สร้าง Implementation Plan
- `implement` - Execute plan
- `commit` - Smart commit
- `pr` - Create PR
- `review` - PR review
- `review-agents` - Multi-agent PR review
- `feature-review` - Single agent feature review
- `feature-review-agents` - Multi-agent feature review
- `debug` - Root cause analysis
- `issue-investigate` - GitHub issue investigation
- `issue-fix` - Fix from investigation
- `ralph` - Autonomous loop
- `ralph-cancel` - Cancel loop
- `run-all` - Full workflow

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
| `prd` | `.claude/PRPs/prds/drafts/{name}-prd-agents-{TIMESTAMP}.md` |
| `design` | `.claude/PRPs/designs/{name}-design-agents-{TIMESTAMP}.md` |
| `plan` | `.claude/PRPs/plans/{name}-{TIMESTAMP}.plan.md` |
| `implement` | `.claude/PRPs/reports/{name}-report-{TIMESTAMP}.md` |
| `debug` | `.claude/PRPs/debug/rca-{slug}-{TIMESTAMP}.md` |
| `issue-investigate` | `.claude/PRPs/issues/issue-{number}-{TIMESTAMP}.md` |
| `review` | `.claude/PRPs/reviews/pr-{NUMBER}-review.md` (ใช้ PR number แทน) |
| `feature-review` | `.claude/PRPs/reviews/feature-review-{pkg}-{date}.md` (ใช้ date แทน) |

### หา Artifact ล่าสุด

เมื่อต้องการหา artifact ที่มี timestamp ให้ใช้:

```bash
# หา artifact ล่าสุดสำหรับ issue #123
ls -t .claude/PRPs/issues/issue-123*.md | head -1

# หา plan ล่าสุดสำหรับ feature
ls -t .claude/PRPs/plans/user-auth*.plan.md | head -1
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

ทุก command และ agents สร้าง artifacts ใน `.claude/PRPs/`:

```
.claude/PRPs/
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

## Development Guidelines

### Adding New Commands

1. สร้างไฟล์ `.md` ใน folder ที่เหมาะสม (`adapters/claude-code/`, `claude-code-marketing/`, หรือ `claude-code-bot/`)
2. ใช้ format: `prp-{command-name}.md`
3. รัน `install.sh` ใหม่เพื่อสร้าง symlinks

### Adding New Agents

1. สร้างไฟล์ `.md` ใน `adapters/claude-code-agents/`
2. ใส่ frontmatter:
   ```yaml
   ---
   name: agent-name
   description: What the agent does
   model: sonnet (or haiku/opus)
   color: "#hexcode"
   ---
   ```
3. รัน `install.sh` ใหม่

### Token Optimization

สำหรับ multi-agent reviews ใช้ context file caching:
1. Extract context ครั้งเดียวใน Phase 1
2. เก็บใน `.claude/PRPs/reviews/feature-context-*.md`
3. Agents อ่านจาก context file แทนการ scan ใหม่

## Testing

ทดสอบ commands หลังแก้ไข:
```bash
# ทดสอบการติดตั้ง
./scripts/install.sh

# ตรวจสอบ symlinks
ls -la ~/.claude/commands/prp-core/
ls -la ~/.claude/commands/prp-mkt/
ls -la ~/.claude/commands/prp-bot/
```

## Key Files

- `scripts/install.sh` - Main installation script
- `docs/USER-GUIDE.md` - Complete command reference (Thai)
- `README.md` - Project overview (English)
- `adapters/claude-code/prp-feature-review.md` - Feature review with token optimization
- `adapters/claude-code/prp-feature-review-agents.md` - Multi-agent feature review

## Contributing

1. Fork repository
2. Create feature branch
3. Make changes
4. Run install.sh to test
5. Submit PR

## License

MIT License - See LICENSE file

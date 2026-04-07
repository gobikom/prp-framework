# Quick Start: PRP Framework with Claude Code

Claude Code เป็น primary tool ของ PRP (Prompt-Run-Perfect) Framework -- รองรับครบทุก feature: 19 core commands, 31 agents, hooks, skills, และ multi-agent parallel execution

## Setup

```bash
# 1. เพิ่ม PRP เป็น submodule หรือ local clone
git submodule add https://github.com/gobikom/prp-framework .prp
# หรือ
git clone https://github.com/gobikom/prp-framework .prp

# 2. Run install script (สร้าง symlinks + register hooks)
cd .prp && ./scripts/install.sh && cd ..

# 3. Configure permissions (ลด permission prompts)
# ดู docs/USER-GUIDE.md#permissions--unattended-mode-claude-code
```

> `install.sh` จะสร้าง symlinks ไปยัง `.claude/commands/`, `.claude/agents/`, `.claude/hooks/` อัตโนมัติ

## Command Format

```bash
/prp-core:{command}    # Core development commands (19)
/prp-mkt:{command}     # Marketing commands (4)
/prp-bot:{command}     # AI Bot commands (5)
```

## Available Commands

### Development

| Command | Description |
|---------|-------------|
| `/prp-core:prd` | Interactive PRD generation |
| `/prp-core:design` | Technical design document (optional) |
| `/prp-core:plan` | Implementation plan (`--fast` for simple changes) |
| `/prp-core:implement` | Execute plan (one-shot) |
| `/prp-core:ralph` | Autonomous loop จนกว่า validations จะผ่าน |
| `/prp-core:ralph-cancel` | Cancel active ralph loop |
| `/prp-core:commit` | Smart staging + conventional commit |
| `/prp-core:pr` | Create pull request |

### Review

| Command | Description |
|---------|-------------|
| `/prp-core:review` | Single-agent PR review |
| `/prp-core:review-agents` | Multi-agent parallel PR review |
| `/prp-core:review-fix` | Auto-fix all review issues |
| `/prp-core:feature-review` | Single-agent feature review |
| `/prp-core:feature-review-agents` | Multi-agent parallel feature review |

### Debug & Issue

| Command | Description |
|---------|-------------|
| `/prp-core:debug` | Root cause analysis |
| `/prp-core:issue-investigate` | GitHub issue investigation |
| `/prp-core:issue-fix` | Fix from investigation report |

### Automation

| Command | Description |
|---------|-------------|
| `/prp-core:run-all` | Full workflow end-to-end (supports `--fast`, `--ralph`, `--resume`, `--no-interact`, `--dry-run`) |
| `/prp-core:rollback` | Undo changes (`--soft` / `--hard` / `--restore`) |
| `/prp-core:cleanup` | Post-merge branch cleanup (`--all` / `--dry-run`) |

## Common Workflows

### Basic: Plan -> Implement -> PR

```bash
/prp-core:plan Add JWT authentication
/prp-core:implement .prp-output/plans/jwt-auth-20260316-1400.plan.md
/prp-core:commit
/prp-core:pr
```

### Full Auto: run-all with --ralph

```bash
# Fully automated -- plan, ralph loop, commit, PR, review, fix
/prp-core:run-all Add JWT auth --ralph --no-interact
```

### Debug: Investigate -> Fix

```bash
/prp-core:debug "Login fails with 500 error"
/prp-core:issue-investigate 42
/prp-core:issue-fix .prp-output/issues/issue-42-20260316-1400.md
```

### Review: Multi-agent -> Fix

```bash
/prp-core:review-agents 25       # Parallel review by multiple agents
/prp-core:review-fix 25          # Auto-fix all found issues
```

## Marketing & Bot Commands (Claude Code Exclusive)

### Marketing (`/prp-mkt:`)

| Command | Description |
|---------|-------------|
| `/prp-mkt:landing` | Landing page analysis & optimization |
| `/prp-mkt:demo` | Demo environment management |
| `/prp-mkt:pitch` | Pitch materials generation |
| `/prp-mkt:competitor` | Competitive analysis |

### AI Bot (`/prp-bot:`)

| Command | Description |
|---------|-------------|
| `/prp-bot:intent` | Chatbot intent design |
| `/prp-bot:flow` | Conversation flow design |
| `/prp-bot:prompt-eng` | Prompt engineering |
| `/prp-bot:voice-ux` | Voice UX design |
| `/prp-bot:integration` | Integration planning |

## Claude Code Exclusive Features

- **30 Specialized Agents** -- `.claude/agents/` directory, ใช้ได้ทั้ง development, business, และ strategy agents
- **Skills Support** -- `.claude/skills/` for reusable prompt patterns
- **Hooks** -- Ralph stop hook auto-registered โดย `install.sh` (ต้องมี `jq`)
- **Multi-Agent Parallel Execution** -- `review-agents` และ `feature-review-agents` รัน agents พร้อมกัน
- **3 Command Namespaces** -- `/prp-core:` (19), `/prp-mkt:` (4), `/prp-bot:` (5) — total 28 commands

## Permissions Config

ลด permission prompts โดยเพิ่ม allowlist ใน `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)", "Bash(gh *)", "Bash(ls *)", "Bash(mkdir *)",
      "Bash(mv *)", "Bash(cp *)", "Bash(cat *)",
      "Bash(npm *)", "Bash(npx *)", "Bash(bun *)",
      "Bash(rm -rf .prp-output/*)"
    ]
  }
}
```

> ดู config ฉบับเต็ม + tiered options ที่ [USER-GUIDE.md -- Permissions](../USER-GUIDE.md#permissions--unattended-mode-claude-code)

## Cross-Adapter Comparison

| Adapter | Format | Syntax | Commands | Storage |
|---------|--------|--------|----------|---------|
| **Claude Code** | **`.md`** | **`/prp-core:cmd`** | **19** | **`.claude/commands/`** |
| Codex | `SKILL.md` | `$prp-cmd` | 17 | `.codex/skills/` |
| OpenCode | `.md` | `/prp:cmd` | 17 | `.opencode/commands/prp/` |
| Gemini | `.toml` | `/prp:cmd` | 17 | `.gemini/commands/prp/` |
| Antigravity | `.md` | `/prp-cmd` | 17 | `.agents/workflows/prp/` |

## Tips

- ใช้ `--fast` flag สำหรับ changes ง่ายๆ -- skip design doc, short plan
- ใช้ `--no-interact` สำหรับ unattended mode (ไม่ถามคำถาม)
- ใช้ `--resume` เมื่อ run-all fail กลางทาง -- กลับมาต่อจาก step ที่ค้าง
- ใช้ `--dry-run` เพื่อ preview steps + token estimate ก่อนรัน
- Ralph hook auto-registered -- ไม่ต้อง config เอง
- Artifacts ทั้งหมดอยู่ใน `.prp-output/` -- ใช้ `ls -t` หา latest

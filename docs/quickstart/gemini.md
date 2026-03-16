# Quick Start: PRP Framework with Gemini CLI

Gemini CLI adapter ใช้ TOML-based configuration -- commands อยู่ใน `.gemini/commands/prp/` เรียกผ่าน `/prp:{command}` syntax

## Setup

```bash
# 1. เพิ่ม PRP เป็น submodule หรือ local clone
git submodule add https://github.com/gobikom/prp-framework .prp
# หรือ
git clone https://github.com/gobikom/prp-framework .prp

# 2. Run install script
cd .prp && ./scripts/install.sh && cd ..
```

> `install.sh` สร้าง TOML command files ใน `.gemini/commands/prp/` อัตโนมัติ

## Command Format

```bash
/prp:{command}         # เรียก command ผ่าน Gemini command system
/prp:{command} args    # พร้อม arguments
```

## Available Commands (17)

### Development

| Command | Description |
|---------|-------------|
| `/prp:prd` | Interactive PRD generation |
| `/prp:design` | Technical design document |
| `/prp:plan` | Implementation plan (`--fast` for simple changes) |
| `/prp:implement` | Execute plan (one-shot) |
| `/prp:ralph` | Autonomous loop จนกว่า validations จะผ่าน |
| `/prp:ralph-cancel` | Cancel active ralph loop |
| `/prp:commit` | Smart staging + conventional commit |
| `/prp:pr` | Create pull request |

### Review

| Command | Description |
|---------|-------------|
| `/prp:review` | PR code review |
| `/prp:review-fix` | Auto-fix all review issues |
| `/prp:feature-review` | Feature review (single pass) |

### Debug & Issue

| Command | Description |
|---------|-------------|
| `/prp:debug` | Root cause analysis |
| `/prp:issue-investigate` | GitHub issue investigation |
| `/prp:issue-fix` | Fix from investigation report |

### Automation

| Command | Description |
|---------|-------------|
| `/prp:run-all` | Full workflow end-to-end |
| `/prp:rollback` | Undo changes (`--soft` / `--hard` / `--restore`) |
| `/prp:cleanup` | Post-merge branch cleanup |

## TOML Configuration

Gemini commands ใช้ TOML format แทน Markdown:

```toml
# ตัวอย่าง .gemini/commands/prp/plan.toml
[command]
name = "plan"
description = "Create implementation plan"

[prompt]
content = "..."   # Canonical prompt content
```

> TOML format ทำให้ Gemini CLI parse metadata ได้ง่าย (name, description, args) แยกจาก prompt content

## Common Workflows

### Basic: Plan -> Implement -> PR

```bash
/prp:plan Add JWT authentication
/prp:implement .prp-output/plans/jwt-auth-20260316-1400.plan.md
/prp:commit
/prp:pr
```

### Full Auto: run-all

```bash
/prp:run-all Add JWT auth --ralph
```

### Debug: Investigate -> Fix

```bash
/prp:debug "Login fails with 500 error"
/prp:issue-investigate 42
/prp:issue-fix .prp-output/issues/issue-42-20260316-1400.md
```

### Review -> Fix

```bash
/prp:review 25
/prp:review-fix 25
```

## Gemini-Specific Notes

- **TOML-Based Config** -- `.toml` files แทน `.md` (ต่างจาก OpenCode ที่ใช้ markdown)
- **Command Storage** -- `.gemini/commands/prp/` directory
- **Sequential Execution** -- ไม่มี parallel agents
- **No Multi-Agent Review** -- ใช้ `/prp:review` (single pass)
- **Full Prompt Parity** -- canonical prompts เหมือนกันทุก tool
- **Artifact Naming** -- ใช้ `-gemini` suffix (e.g., `jwt-prd-gemini.md`)
- **Same Syntax as OpenCode** -- `/prp:command` format เหมือนกัน

## Differences from Claude Code

| Feature | Claude Code | Gemini CLI |
|---------|------------|------------|
| Commands | 19 | 17 |
| Parallel agents | review-agents, feature-review-agents | ไม่มี |
| Command format | `/prp-core:command` | `/prp:command` |
| Storage | `.claude/commands/` | `.gemini/commands/prp/` |
| File format | `.md` | `.toml` |
| Hooks | Ralph stop hook | ไม่มี |
| Namespaces | 3 (core, mkt, bot) | 1 (prp) |

## Cross-Adapter Comparison

| Adapter | Format | Syntax | Commands | Storage |
|---------|--------|--------|----------|---------|
| Claude Code | `.md` | `/prp-core:cmd` | 19 | `.claude/commands/` |
| Codex | `SKILL.md` | `$prp-cmd` | 17 | `.codex/skills/` |
| OpenCode | `.md` | `/prp:cmd` | 17 | `.opencode/commands/prp/` |
| **Gemini** | **`.toml`** | **`/prp:cmd`** | **17** | **`.gemini/commands/prp/`** |
| Antigravity | `.md` | `/prp-cmd` | 17 | `.agents/workflows/prp/` |

## Tips

- ใช้ `--fast` flag สำหรับ changes ง่ายๆ
- Artifacts ทั้งหมดอยู่ใน `.prp-output/` -- format เดียวกับทุก tool
- ใช้ `ls -t .prp-output/plans/*.plan.md | head -1` หา plan ล่าสุด
- TOML format ช่วยให้ Gemini CLI ทำ auto-complete ได้ดีกว่า plain markdown
- Command syntax เหมือน OpenCode -- ถ้าใช้ทั้งสอง tool ไม่ต้องจำ syntax ใหม่

# Quick Start: PRP Framework with Google Antigravity

Google Antigravity adapter ใช้ workflows system -- workflows อยู่ใน `.agents/workflows/prp/` เรียกผ่าน `/prp-{command}` syntax

## Setup

```bash
# 1. เพิ่ม PRP เป็น submodule หรือ local clone
git submodule add https://github.com/gobikom/prp-framework .prp
# หรือ
git clone https://github.com/gobikom/prp-framework .prp

# 2. Run install script
cd .prp && ./scripts/install.sh && cd ..
```

> `install.sh` สร้าง workflow files ใน `.agents/workflows/prp/` อัตโนมัติ

## Command Format

```bash
/prp-{command}         # เรียก workflow ผ่าน Antigravity system
/prp-{command} args    # พร้อม arguments
```

## Available Commands (17)

### Development

| Command | Description |
|---------|-------------|
| `/prp-prd` | Interactive PRD generation |
| `/prp-design` | Technical design document |
| `/prp-plan` | Implementation plan (`--fast` for simple changes) |
| `/prp-implement` | Execute plan (one-shot) |
| `/prp-ralph` | Autonomous loop จนกว่า validations จะผ่าน |
| `/prp-ralph-cancel` | Cancel active ralph loop |
| `/prp-commit` | Smart staging + conventional commit |
| `/prp-pr` | Create pull request |

### Review

| Command | Description |
|---------|-------------|
| `/prp-review` | PR code review |
| `/prp-review-fix` | Auto-fix all review issues |
| `/prp-feature-review` | Feature review (single pass) |

### Debug & Issue

| Command | Description |
|---------|-------------|
| `/prp-debug` | Root cause analysis |
| `/prp-issue-investigate` | GitHub issue investigation |
| `/prp-issue-fix` | Fix from investigation report |

### Automation

| Command | Description |
|---------|-------------|
| `/prp-run-all` | Full workflow end-to-end |
| `/prp-rollback` | Undo changes (`--soft` / `--hard` / `--restore`) |
| `/prp-cleanup` | Post-merge branch cleanup |

## Common Workflows

### Basic: Plan -> Implement -> PR

```bash
/prp-plan Add JWT authentication
/prp-implement .prp-output/plans/jwt-auth-20260316-1400.plan.md
/prp-commit
/prp-pr
```

### Full Auto: run-all

```bash
/prp-run-all Add JWT auth --ralph
```

### Debug: Investigate -> Fix

```bash
/prp-debug "Login fails with 500 error"
/prp-issue-investigate 42
/prp-issue-fix .prp-output/issues/issue-42-20260316-1400.md
```

### Review -> Fix

```bash
/prp-review 25
/prp-review-fix 25
```

## Antigravity-Specific Notes

- **Workflow Storage** -- `.agents/workflows/prp/` directory
- **File Format** -- `.md` files (e.g., `prp-plan.md`, `prp-implement.md`)
- **Prefix Naming** -- files ใช้ `prp-` prefix (e.g., `prp-plan.md` ไม่ใช่ `plan.md`)
- **Sequential Execution** -- ไม่มี parallel agents
- **No Multi-Agent Review** -- ใช้ `/prp-review` (single pass)
- **Full Prompt Parity** -- canonical prompts เหมือนกันทุก tool
- **Artifact Naming** -- ใช้ timestamp-based naming

## Differences from Claude Code

| Feature | Claude Code | Antigravity |
|---------|------------|-------------|
| Commands | 19 | 17 |
| Parallel agents | review-agents, feature-review-agents | ไม่มี |
| Command format | `/prp-core:command` | `/prp-command` |
| Storage | `.claude/commands/` | `.agents/workflows/prp/` |
| File format | `.md` | `.md` |
| Hooks | Ralph stop hook | ไม่มี |
| Namespaces | 3 (core, mkt, bot) | 1 (prp) |

## Differences from Other Adapters

| Adapter | Format | Syntax | Storage |
|---------|--------|--------|---------|
| Claude Code | `.md` | `/prp-core:cmd` | `.claude/commands/` |
| Codex | `SKILL.md` | `$prp-cmd` | `.codex/skills/` |
| OpenCode | `.md` | `/prp:cmd` | `.opencode/commands/prp/` |
| Gemini | `.toml` | `/prp:cmd` | `.gemini/commands/prp/` |
| **Antigravity** | **`.md`** | **`/prp-cmd`** | **`.agents/workflows/prp/`** |

## Tips

- ใช้ `--fast` flag สำหรับ changes ง่ายๆ
- Artifacts ทั้งหมดอยู่ใน `.prp-output/` -- format เดียวกับทุก tool
- ใช้ `ls -t .prp-output/plans/*.plan.md | head -1` หา plan ล่าสุด
- Antigravity ใช้ dash syntax (`/prp-plan`) ไม่ใช่ colon syntax (`/prp:plan`)
- Workflow files มี `prp-` prefix ในชื่อไฟล์ -- ต่างจาก OpenCode/Gemini ที่ไม่มี prefix

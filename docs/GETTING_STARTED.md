# Getting Started with PRP Framework

This guide will help you set up PRP Framework in your project.

## Prerequisites

- Git installed
- One or more supported AI coding tools:
  - Claude Code CLI
  - OpenAI Codex CLI
  - OpenCode
  - Gemini CLI
  - Kimi or other AI tools that support custom instructions

## Installation Methods

### Method 1: Git Submodule

Best for team projects where everyone needs PRP workflows.

```bash
# 1. Navigate to your project
cd your-project

# 2. Add PRP Framework as submodule
git submodule add https://github.com/gobikom/prp-framework .prp

# 3. Run installation script
cd .prp
./scripts/install.sh
cd ..

# 4. Commit the submodule
git add .gitmodules .prp
git commit -m "feat: add PRP Framework via submodule"
```

**Result:**
- Framework code in `.prp/` (submodule, committed to git)
- Symlinks created to adapters (`.claude/`, `.codex/`, etc. — gitignored, regenerate with `install.sh`)
- Runtime artifact directory `.prp-output/` created (gitignored)

> **Deploy note:** Submodules are tracked in git. If your CI/CD (Railway, Vercel, etc.) can't clone the submodule, use Method 2 instead.

### Method 2: Local Clone (Recommended for Deploy)

Best for projects deployed to CI/CD platforms. Nothing PRP-related is committed — clean deploys.

```bash
# 1. Navigate to your project
cd your-project

# 2. Clone framework locally (not tracked by git)
git clone https://github.com/gobikom/prp-framework .prp

# 3. Run installation script
cd .prp
./scripts/install.sh
cd ..
```

**Result:**

- Framework code in `.prp/` (local only, gitignored)
- Symlinks created to adapters (`.claude/`, `.codex/`, etc. — gitignored)
- Runtime artifact directory `.prp-output/` created (gitignored)
- No `.gitmodules`, no submodule reference — CI/CD sees nothing

**Update later:**
```bash
cd .prp && git pull origin main && cd ..
```

### Method 3: Template Repository

Best for one-time setup without tracking framework updates.

```bash
# Use GitHub template
gh repo create my-project --template gobikom/prp-framework
cd my-project

# Or manual copy
git clone https://github.com/gobikom/prp-framework my-project
cd my-project
rm -rf .git
git init
```

## Verify Installation

### Check Files

```bash
# Verify directory structure
ls -la .prp-output/         # Runtime artifacts directory
ls -la .claude/commands/    # Should have prp-core/
ls -la .codex/skills/       # Should have prp-*/
```

### Verify Ralph Hook (Claude Code)

`install.sh` automatically registers the Ralph stop hook. Verify it worked:

```bash
# Check hook is registered
cat .claude/settings.local.json | jq '.hooks.Stop'
# Expected: [{"hooks": [{"type": "command", "command": ".claude/hooks/prp-ralph-stop.sh"}]}]

# Check hook is executable
ls -la .claude/hooks/prp-ralph-stop.sh
# Expected: -rwxr-xr-x
```

If hook registration was skipped (e.g. `jq` was not installed), install jq and re-run:

```bash
brew install jq        # macOS
cd .prp && ./scripts/install.sh
```

### Configure Permissions (Claude Code — แนะนำ)

เพื่อลด permission prompts ระหว่าง workflow ให้เพิ่ม allowlist ใน `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)", "Bash(gh *)", "Bash(ls *)", "Bash(mkdir *)",
      "Bash(mv *)", "Bash(cp *)", "Bash(rm *)", "Bash(cat *)",
      "Bash(test *)", "Bash(find *)", "Bash(date *)", "Bash(head *)",
      "Bash(echo *)", "Bash(grep *)", "Bash(sed *)", "Bash(jq *)",
      "Bash(npm *)", "Bash(npx *)", "Bash(bun *)"
    ]
  }
}
```

> ดู config ฉบับเต็มที่ [USER-GUIDE.md — Permissions & Unattended Mode](USER-GUIDE.md#permissions--unattended-mode-claude-code)

### Test Commands

PRP Framework มี 19 core commands ใน 4 หมวดหมู่:

```
Development:  prd, design, plan, implement, commit, pr
Review:       review, review-fix, review-agents, feature-review, feature-review-agents
Debug/Issue:  debug, issue-investigate, issue-fix
Automation:   ralph, ralph-cancel, rollback, cleanup, run-all
```

**Claude Code:**
```bash
claude
# Type: /prp-core:
# Should see all 19 commands listed above
```

**Codex:**
```bash
codex
# Type: $prp
# Should see: $prp-prd, $prp-plan, $prp-implement, etc.
```

## Create Project Conventions

Create `CLAUDE.md` (or equivalent) with project-specific conventions:

```markdown
# My Project

## AI Workflows

PRP framework installed via: `.prp/` (submodule v1.0.0)

Available commands (19 core commands):
- Development: prd, design, plan, implement, commit, pr
- Review: review, review-fix, review-agents, feature-review, feature-review-agents
- Debug/Issue: debug, issue-investigate, issue-fix
- Automation: ralph, ralph-cancel, rollback, cleanup, run-all
- Claude Code prefix: /prp-core:  |  Codex prefix: $prp-
- Other tools: See AGENTS.md

## Project-Specific Conventions

**Tech Stack:**
- Framework: [Your framework]
- Language: [Your language]
- Database: [Your database]

**Code Style:**
- [Your conventions]

**Testing:**
- [Your test framework]

**File Structure:**
- [Your structure]
```

## First Workflow

Let's create your first PRD!

### With Claude Code

```bash
claude
```

In Claude session:
```
/prp-core:prd Add user authentication
```

Follow the interactive prompts. The PRD will be saved to:
`.prp-output/prds/drafts/user-auth-prd-agents-20260210-1430.md`

> **Note**: All artifacts use timestamp format `YYYYMMDD-HHMM` to prevent overwrites.

### Create Plan from PRD

After finalizing your PRD (find latest with `ls -t .prp-output/prds/*.md | head -1`):

```
/prp-core:plan .prp-output/prds/user-auth-prd.md
```

Plan will be saved to:
`.prp-output/plans/user-auth-20260210-1445.plan.md`

### Implement the Plan

```
/prp-core:implement .prp-output/plans/user-auth-20260210-1445.plan.md
```

### Debug Flow

วิเคราะห์ root cause ของปัญหา:

```
/prp-core:debug "Login fails after session timeout"
```

ผลลัพธ์จะถูกบันทึกใน `.prp-output/debug/rca-{slug}-{TIMESTAMP}.md`

### Issue Flow

ตรวจสอบและแก้ไข GitHub issue:

```
/prp-core:issue-investigate 45
/prp-core:issue-fix 45
```

`issue-investigate` จะวิเคราะห์ issue และสร้าง investigation report ก่อน จากนั้น `issue-fix` จะอ่าน report แล้ว implement fix ให้

### Full Automation Flow

รัน workflow ทั้งหมดแบบอัตโนมัติ (Plan → Implement → Commit → PR → Review/Fix):

```
/prp-core:run-all "Add dark mode toggle" --ralph --no-interact
```

`--ralph` เปิด autonomous implementation loop ที่จะ iterate จนกว่า validations จะผ่านทั้งหมด `--no-interact` ข้ามการถามยืนยันทุกขั้นตอน

## Updating Framework

### With Submodule (Symlinks)

```bash
cd .prp && git pull origin main && cd ..
# Command content updates automatically via symlinks!
```

**After major version updates** (re-run install to update directory structure and .gitignore):

```bash
cd .prp && git pull origin main && ./scripts/install.sh && cd ..
```

### With Submodule (Hard Copy)

```bash
cd .prp && git pull origin main && ./scripts/sync.sh && cd ..
```

### With Template

Manual update - copy new files from framework repo.

### Re-install from Scratch

If something is broken, force a clean re-install:
```bash
cd .prp && ./scripts/install.sh && cd ..
```

## Troubleshooting

### Symlinks Not Working

**Windows Users:**
```bash
# Enable Developer Mode or run as Administrator
git config --global core.symlinks true
```

**Fallback:**
The install script automatically falls back to hard copy if symlinks fail.

### Commands Not Found

**Claude Code:**
```bash
# Verify installation
ls -la .claude/commands/prp-core/
# Should show prp-*.md files

# Restart Claude Code
claude
```

**Codex:**
```bash
# Verify installation
ls -la .codex/skills/
# Should show prp-*/ directories
```

### Update Issues

```bash
# Force re-install
cd .prp
./scripts/install.sh
```

### Agent Files Appearing as Changes in `.prp/adapters/claude-code-agents/`

After updating the framework, you may see all agent `.md` files as type-changed (`T`) in source control under `.prp/adapters/claude-code-agents/`.

**Root cause**: A buggy `install.sh` (operator precedence in `rm` guard) deleted the original files from `.prp/adapters/claude-code-agents/` and replaced them with self-referencing symlinks. This happened when `.claude/agents` was a whole-directory symlink — path resolution caused `target_file` to resolve into `.prp/` instead of `.claude/agents/`.

**Fix**: Pull the latest framework (which has the fixed `install.sh`) and re-run — it auto-recovers:
```bash
git -C .prp checkout -- adapters/claude-code-agents/   # restore damaged files
git -C .prp pull origin main                           # get fixed install.sh
cd .prp && ./scripts/install.sh && cd ..               # re-install (auto-migrates)
```

The fixed `install.sh` will:
1. Detect and restore any typechanged files automatically on every run
2. Migrate `.claude/agents` from directory symlink → real directory with per-file symlinks

After this, agent files will no longer appear as changes in `.prp/`.

### Git Edge Cases

**Detached HEAD State:**
```bash
# run-all can't create branch from detached HEAD
git checkout main
# Then start workflow again
```

**Shallow Clone Issues:**
```bash
# Some CI/CD do shallow clone — git fetch may fail
git fetch --unshallow origin
```

### GitHub CLI Issues

**gh CLI Not Installed:**
PR and review commands require GitHub CLI (`gh`).
```bash
brew install gh       # macOS
gh auth login         # First-time login
```

**gh CLI Auth Expired:**
```bash
gh auth status        # Check status
gh auth refresh       # Refresh token
```

### Run-All Workflow Issues

**Lock File Stuck** ("Another workflow is active"):
```bash
# Check if stale (>2 hours = safe to remove)
cat .claude/prp-run-all.lock
# Remove stale lock
rm .claude/prp-run-all.lock
```

**State File Corrupt** (--resume fails):
```bash
# Delete state and start fresh
rm .claude/prp-run-all.state.md
# Re-run without --resume
```

## Next Steps

- Read [WORKFLOWS.md](WORKFLOWS.md) for detailed workflow documentation
- Read per-tool quick start guides in [docs/quickstart/](quickstart/)
- See [CONTRIBUTING.md](CONTRIBUTING.md) to contribute improvements
- Check [README.md](../README.md) for architecture overview

## Getting Help

- **Issues:** [GitHub Issues](https://github.com/gobikom/prp-framework/issues)
- **Discussions:** [GitHub Discussions](https://github.com/gobikom/prp-framework/discussions)
- **Documentation:** This docs folder

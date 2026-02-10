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

### Method 1: Git Submodule (Recommended)

Best for projects that want automatic updates.

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
git add .gitmodules .prp .ai-workflows .claude .codex .opencode .gemini AGENTS.md
git commit -m "feat: add PRP Framework via submodule"
```

**Result:**
- Framework code in `.prp/` (submodule)
- Symlinks created to adapters (auto-updates on `git pull`)
- Runtime artifact directories created

### Method 2: Template Repository

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
ls -la .ai-workflows/       # Should have prompts/
ls -la .claude/commands/    # Should have prp-core/
ls -la .codex/skills/       # Should have prp-*/
ls -la .claude/PRPs/        # Runtime artifacts directory
```

### Test Commands

**Claude Code:**
```bash
claude
# Type: /prp
# Should see: /prp-prd, /prp-plan, /prp-implement, etc.
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

Available commands:
- Claude Code: /prp-prd, /prp-design, /prp-plan, /prp-implement, /prp-review-agents, /prp-commit, /prp-pr
- Codex: $prp-prd, $prp-design, $prp-plan, etc.
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
/prp-prd Add user authentication
```

Follow the interactive prompts. The PRD will be saved to:
`.claude/PRPs/prds/drafts/user-auth-prd-agents-20260210-1430.md`

> **Note**: All artifacts use timestamp format `YYYYMMDD-HHMM` to prevent overwrites.

### Create Plan from PRD

After finalizing your PRD (find latest with `ls -t .claude/PRPs/prds/*.md | head -1`):

```
/prp-plan .claude/PRPs/prds/user-auth-prd.md
```

Plan will be saved to:
`.claude/PRPs/plans/user-auth-20260210-1445.plan.md`

### Implement the Plan

```
/prp-implement .claude/PRPs/plans/user-auth-20260210-1445.plan.md
```

## Updating Framework

### With Submodule (Symlinks)

```bash
cd .prp
git pull origin main
# Changes applied automatically via symlinks!
```

### With Submodule (Hard Copy)

```bash
cd .prp
git pull origin main
./scripts/sync.sh
```

### With Template

Manual update - copy new files from framework repo.

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

## Next Steps

- Read [WORKFLOWS.md](WORKFLOWS.md) for detailed workflow documentation
- See [CONTRIBUTING.md](CONTRIBUTING.md) to contribute improvements
- Check [README.md](../README.md) for architecture overview

## Getting Help

- **Issues:** [GitHub Issues](https://github.com/gobikom/prp-framework/issues)
- **Discussions:** [GitHub Discussions](https://github.com/gobikom/prp-framework/discussions)
- **Documentation:** This docs folder

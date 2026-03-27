# PRP Framework

Cross-tool AI coding workflow framework that works with Claude Code, Codex, OpenCode, Gemini CLI, Google Antigravity, Kimi, and any other AI coding tool.

## Overview

PRP (Plan-Review-PR) Framework is a portable, tool-agnostic workflow system for AI-assisted software development. It provides structured prompts and adapters for multiple AI coding tools, enabling consistent workflows across different platforms.

### Key Features

✅ **Cross-Tool Compatibility** - Works with Claude Code, Codex, OpenCode, Gemini CLI, Kimi, and more
✅ **Portable Design** - Use as Git submodule or template
✅ **Tool-Specific Naming** - Parallel artifact creation for comparison
✅ **Complete Workflows** - PRD → Design → Plan → Implement → Review → Commit → PR
✅ **Resilient Automation** - State management with `--resume`, review-fix loops, coverage enforcement (90%)
✅ **Quality Built-in** - TDD approach, conditional design docs, pre-commit checks, security/performance validation
✅ **100% Workflow Parity** - All tools follow the same workflow steps with equivalent review depth (11-pass review across all adapters). Claude Code adds 19 commands, 30 agents, hooks, and skills; other adapters use multi-pass architecture for the same quality.
✅ **Claude Code Advanced** - 30 specialized agents, skills, hooks for enhanced workflows
✅ **Domain Extensions** - Marketing automation and AI Bot development command packs

## Quick Start

### Installation via Git Submodule

Best for team projects where everyone needs PRP workflows.

```bash
# Add PRP Framework as submodule
git submodule add https://github.com/gobikom/prp-framework .prp

# Run installation script
cd .prp && ./scripts/install.sh && cd ..

# Start using workflows
/prp-core:plan "Add user authentication"
```

### Configure Permissions (Claude Code)

ลด permission prompts ระหว่าง workflow โดยเพิ่ม allowlist ใน `.claude/settings.json`:

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

> `Bash(rm *)` และ `Bash(sed *)` แบบ wildcard เต็มให้ AI ลบ/แก้ไขไฟล์ใดก็ได้ — ใช้ scoped version ข้างต้นสำหรับ team และดู full config + tiered options ที่ [USER-GUIDE.md — Permissions](docs/USER-GUIDE.md#permissions--unattended-mode-claude-code)

### Installation via Local Clone (Recommended for Deploy)

Best for projects deployed to Railway, Vercel, etc. — nothing PRP-related goes to CI/CD.

```bash
# Clone framework locally (not tracked by git)
git clone https://github.com/gobikom/prp-framework .prp

# Run installation script
cd .prp && ./scripts/install.sh && cd ..

# Start using workflows
/prp-core:plan "Add user authentication"
```

### Installation via Template

```bash
# Use this repository as template on GitHub
gh repo create my-project --template gobikom/prp-framework

# Or manually copy
cp -r prp-framework/* my-project/
```

## Available Workflows

| Workflow | Description | When to Use |
|----------|-------------|-------------|
| **PRD** | Interactive PRD generator | Need product spec before planning |
| **Design** | Technical design doc (optional) | Complex features needing architecture blueprint |
| **Plan** | Implementation plan with validation | Starting a new feature |
| **Implement** | Execute plan with validation loops | Have a plan, ready to code |
| **Ralph** | Autonomous loop until all validations pass | Complex features where first-pass impl may fail |
| **Review** | Multi-pass PR code review (11 passes: code, security, deps, docs, tests, comments, errors, types, perf, a11y, simplify) | PR created, need review |
| **Review Fix** | Auto-fix all review issues to PR branch | After review, fix critical/high/medium/suggestions |
| **Commit** | Smart staging + conventional commit | Code ready to commit |
| **PR** | Create pull request | Ready to push |
| **Rollback** | Safely undo implementation changes (--soft / --hard with stash backup / --restore) | Implementation went wrong |
| **Cleanup** | Post-merge cleanup (delete local/remote branches, verify PR merged, `--all` / `--dry-run`) | After PR merged |
| **Run All** | Full workflow end-to-end (supports `--fast`, `--skip-plan`, `--ralph`, `--resume`, `--fix-severity`, `--no-interact`, `--dry-run`) | Complete automation |

## Tool Support

### Claude Code
```bash
# Core Workflows (/prp-core:*)
/prp-core:prd                                              # Interactive PRD generation
/prp-core:plan Add JWT authentication                      # Create plan (full)
/prp-core:plan "simple bug fix" --fast                     # Create plan (fast-track)
/prp-core:implement plan.md                                # Execute plan (one-shot)
/prp-core:ralph plan.md                                    # Execute plan (autonomous loop until pass)
/prp-core:ralph plan.md --max-iterations 10                # Ralph with custom iterations
/prp-core:ralph-cancel                                     # Cancel active ralph loop
/prp-core:rollback                                         # Undo changes (interactive)
/prp-core:rollback --hard                                  # Revert to origin/main (stash backup first)
/prp-core:rollback --restore                               # Restore from rollback stash
/prp-core:cleanup                                          # Clean up current branch after merge
/prp-core:cleanup --all --dry-run                          # Preview batch cleanup of all merged branches
/prp-core:run-all Add JWT auth                             # Full workflow (plan→implement→commit→PR→review)
/prp-core:run-all Add JWT auth --fast                      # Full workflow with fast-track plan
/prp-core:run-all --skip-plan                              # Select existing plan, then implement
/prp-core:run-all Add JWT auth --ralph                     # Full workflow using ralph loop
/prp-core:run-all Add JWT auth --resume                    # Resume from last failed step
/prp-core:run-all Add JWT auth --fix-severity critical     # Override review-fix severity
/prp-core:run-all Add JWT auth --no-interact               # Fully unattended (no questions asked)
/prp-core:run-all Add JWT auth --dry-run                   # Preview steps + token estimate (no execution)
/prp-core:review-agents 25                                 # Multi-agent PR review
/prp-core:review-fix 25                                    # Fix all review issues
/prp-core:commit                                           # Smart commit
/prp-core:pr                                               # Create PR

# Marketing Commands (/prp-mkt:*)
/prp-mkt:landing                       # Landing page analysis
/prp-mkt:demo                          # Demo environment setup
/prp-mkt:pitch                         # Pitch deck generation
/prp-mkt:competitor                    # Competitive analysis

# AI Bot Commands (/prp-bot:*)
/prp-bot:intent                        # Chatbot intent design
/prp-bot:flow                          # Conversation flow design
/prp-bot:prompt-eng                    # Prompt engineering
/prp-bot:voice-ux                      # Voice UX design
/prp-bot:integration                   # Integration planning
```

### Codex
```bash
$prp-prd Add usage metrics
$prp-design .prp-output/prds/metrics-prd.md
$prp-plan Add JWT authentication
$prp-implement plan.md
$prp-review 25
$prp-review-fix 25
$prp-commit
$prp-pr
```

### OpenCode / Gemini
```bash
/prp:prd Add usage metrics
/prp:design .prp-output/prds/metrics-prd.md
/prp:plan Add JWT authentication
/prp:implement plan.md
/prp:review 25
/prp:review-fix 25
/prp:commit
/prp:pr
```

### Google Antigravity
```bash
/prp-prd Add usage metrics
/prp-design .prp-output/prds/metrics-prd.md
/prp-plan Add JWT authentication
/prp-implement plan.md
/prp-review 25
/prp-review-fix 25
/prp-commit
/prp-pr
```

### Kimi / Other Tools
Use natural language:
```
"Create a PRD for usage metrics dashboard"
"Create a design doc for the PRD at ..."
"Create a plan for adding JWT authentication"
"Implement the plan at ..."
"Fix review issues for PR #25"
```

## Architecture

```
prp-framework/
├── prompts/                    # Source prompts (tool-agnostic)
│   ├── prd.md
│   ├── design.md
│   ├── plan.md
│   ├── implement.md
│   ├── review.md
│   ├── review-fix.md
│   ├── commit.md
│   ├── pr.md
│   ├── cleanup.md
│   ├── run-all.md
│   ├── ralph.md
│   ├── debug.md
│   ├── rollback.md
│   ├── issue-investigate.md
│   ├── issue-fix.md
│   └── feature-review.md
├── adapters/                   # Tool-specific adapters
│   ├── claude-code/            # Claude Code core commands (19 commands)
│   ├── claude-code-marketing/  # Marketing commands (4 commands)
│   ├── claude-code-bot/        # AI Bot commands (5 commands)
│   ├── claude-code-agents/     # Claude Code agents (30 agents)
│   ├── claude-code-skills/     # Claude Code skills (1 skill)
│   ├── claude-code-hooks/      # Claude Code hooks (Ralph stop)
│   ├── claude-code-plugin/     # Claude Code plugin metadata
│   ├── codex/                  # Codex skills (16 skills)
│   ├── opencode/               # OpenCode commands (16 commands)
│   ├── gemini/                 # Gemini commands (16 commands)
│   ├── antigravity/            # Antigravity workflows (16 workflows)
│   └── generic/                # AGENTS.md for Kimi/others
├── docs/                       # Documentation
│   └── SCRIPTS-REFERENCE.md   # Detailed script docs
├── scripts/                    # Installation & utility scripts
└── LICENSE
```

## Artifacts

All tools produce artifacts in `.prp-output/`:

```
.prp-output/
├── prds/
│   ├── drafts/          # Draft PRDs with tool suffixes
│   └── {name}-prd.md    # Final merged PRD
├── designs/             # Design docs (optional reference)
├── plans/               # Implementation plans
│   └── completed/
├── reports/             # Implementation reports
└── reviews/             # PR review reports
```

**Tool-Specific Naming:**
- Claude Code: `-agents` suffix (e.g., `jwt-prd-agents.md`)
- Codex: `-codex` suffix
- OpenCode: `-opencode` suffix
- Gemini: `-gemini` suffix
- Kimi/Generic: timestamp-based (e.g., `jwt-report-20260210-1430.md`)

## Updating Framework

> For detailed documentation on all scripts, see [docs/SCRIPTS-REFERENCE.md](docs/SCRIPTS-REFERENCE.md).

### With Submodule (Symlinks)

```bash
cd .prp && git pull --rebase origin main && cd ..
# Command content updates automatically via symlinks!
```

**After major version updates** (re-run install to update directory structure, .gitignore, and migrate agent/hook symlinks):

```bash
cd .prp && git pull --rebase origin main && ./scripts/install.sh && cd ..
```

> If agent files appear as changes in `.prp/adapters/claude-code-agents/` after updating, re-run `install.sh` — it will automatically migrate the old whole-directory symlink for `.claude/agents/` to per-file symlinks.

### With Local Clone

```bash
cd .prp && git pull --rebase origin main && cd ..
```

### With Submodule (Hard Copy)

```bash
cd .prp && git pull --rebase origin main && ./scripts/sync.sh && cd ..
```

### With Template

Manual update — copy new files from framework repo.

### Re-install from Scratch

If something is broken, force a clean re-install:

```bash
cd .prp && ./scripts/install.sh && cd ..
```

### Troubleshooting: "divergent branches" error

If you see `fatal: Need to specify how to reconcile divergent branches`, your `.prp` directory has local commits. Since `.prp` is a read-only framework, reset to remote:

```bash
cd .prp && git fetch origin && git reset --hard origin/main && cd ..
```

To prevent this in future pulls:

```bash
cd .prp && git config pull.rebase true && cd ..
```

## Documentation

- [Getting Started Guide](docs/GETTING_STARTED.md) - Step-by-step setup
- [User Guide](docs/USER-GUIDE.md) - Complete command reference (28 commands)
- [Agents Guide](docs/AGENTS-GUIDE.md) - How to use 30 specialized agents with strategy workflows
- [Workflows Documentation](docs/WORKFLOWS.md) - Detailed workflow descriptions
- [Contributing Guide](docs/CONTRIBUTING.md) - How to contribute
- [Changelog](CHANGELOG.md) - Version history

## Attribution

This framework is derived from [PRPs-agentic-eng](https://github.com/Wirasm/PRPs-agentic-eng) by Wirasm.

Significant modifications and enhancements by gobikom team:
- Added Design Doc workflow
- Cross-tool adapters (Codex, OpenCode, Gemini, Kimi)
- Tool-specific naming conventions for parallel generation
- Portable submodule architecture
- Comprehensive documentation

## License

MIT License - see [LICENSE](LICENSE) file for details.

Original work Copyright (c) 2024 Wirasm
Modified work Copyright (c) 2025 gobikom

## Support

- Issues: [GitHub Issues](https://github.com/gobikom/prp-framework/issues)
- Discussions: [GitHub Discussions](https://github.com/gobikom/prp-framework/discussions)
- Documentation: [docs/](docs/)

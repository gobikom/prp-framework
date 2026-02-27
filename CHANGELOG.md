# Changelog

All notable changes to PRP Framework will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Ralph enhancements** (Claude Code only):
  - `install.sh` now auto-registers ralph stop hook in `.claude/settings.local.json` via `jq` merge — no manual setup required
  - `install.sh` now auto-`chmod +x` the ralph stop hook on installation
  - `prp-ralph.md`: ralph now generates `pr-context-{branch}.md` after COMPLETE, enabling token optimization (~60K saved) when used via `run-all --ralph`
  - `prp-run-all.md`: added `--ralph` and `--ralph-max-iter N` flags — replaces implement step with ralph loop
  - `prp-run-all.md`: added hook pre-check and token warning when `--ralph` is used
  - `tests/ralph/ralph-stop.bats`: 23 automated bats-core tests for the stop hook
- **Run-all workflow improvements** (all adapters):
  - State file management (`.claude/prp-run-all.state.md`) for crash recovery
  - `--resume` flag to continue from last failed step
  - `--fix-severity <levels>` flag to override review-fix severity (default: `critical,high`)
  - `--prp-path` validation — checks file exists before skipping plan step
  - Lock file (`.claude/prp-run-all.lock`) prevents concurrent execution (2-hour stale timeout)
  - Unified `RUN_TIMESTAMP` for artifact correlation across workflow steps
  - Auto-select review artifact in review-fix step (skip interactive selection)
  - `scripts/prp-run-all-state.sh`: state management helper (8 commands)
  - `tests/run-all/state-file.bats`: 20 automated tests for state management
- **Review context handoff** (all adapters):
  - `prp-review-agents.md`: Phase 0 context detection — reads `pr-context-{BRANCH}.md`
  - `prp-run-all.md`: passes context path explicitly via `--context` flag (~60K token savings)
- **Coverage enforcement** (all adapters):
  - `prp-implement`: Phase 4.2.1 — 90% coverage on new/changed code
  - Auto-detect coverage tool (jest, vitest, pytest, cargo tarpaulin, go test)
  - Graceful skip if no coverage tool available
  - `prp-ralph`: coverage check added to validation loop
  - `prp-plan`: target updated 80% → 90%
- **Generic base improvements**:
  - `prompts/implement.md`: Section 5.5 pr-context generation + Phase 4.2.1 coverage check
  - `prompts/plan.md`: coverage target 80% → 90%
- **SKILL.md update**: 5-step → 7-step workflow, added flags table and examples
- **Google Antigravity adapter**: 9 core commands in `.agents/workflows/prp/`

### Fixed
- **Ralph stop hook bugs** (`prp-ralph-stop.sh`):
  - False positive: promise detection now requires `<promise>COMPLETE</promise>` on its own line (`grep -qE '^...$'`) — prevents accidental trigger from code blocks or comments
  - Missing field crash: `grep` on missing YAML frontmatter fields now uses `|| true` to prevent `set -euo pipefail` from crashing the hook with exit code 1

### Changed
- Coverage target: 80% → 90% on new/changed code (plan + implement, all adapters)
- `prp-core-runner/SKILL.md`: updated 5-step → 7-step workflow description
- **BREAKING**: Unified all artifact output paths to `.prp-output/`
  - `.claude/PRPs/` (Claude Code) → `.prp-output/`
  - `.ai-workflows/plans/` (Codex/OpenCode/Gemini/Generic) → `.prp-output/plans/`
  - `.ai-workflows/reports/` → `.prp-output/reports/`
- Removed `.ai-workflows/prompts` symlink from install.sh (source prompts accessible via `.prp/prompts/`)
- Updated `.gitignore` to ignore `.prp-output/` instead of `.ai-workflows/plans/`
- Added `scripts/migrate-artifacts.sh` for migrating existing artifacts
- Gitignore generated adapter directories (`.claude/`, `.claude-plugin/`, `.codex/`, `.opencode/`, `.gemini/`, `AGENTS.md`)
- Streamlined `CLAUDE.md` to user-facing content only; moved dev guidelines to `docs/CONTRIBUTING.md`
- `install.sh` now auto-configures consumer project `.gitignore` (adapters + artifact visibility)
- `.prp-output/` directory visible to AI tools while content is not tracked in git

### Documentation
- Updated README.md, USER-GUIDE.md, WORKFLOWS.md, CLAUDE.md with new features and flags
- Added feature availability table to generic/AGENTS.md
- Added git edge case troubleshooting to GETTING_STARTED.md
- Added common issues & recovery table to WORKFLOWS.md

### Planned
- GitHub Actions workflow templates
- Example projects showcase
- Video tutorials
- CLI tool for framework management
- Additional language support (Python, Go, Rust)

## [1.5.0] - 2026-02-09

### Added
- **Artifact Output Instructions** for all 14 business agents
  - Each agent now saves structured output to `.prp-output/{category}/`
  - 14 new artifact directories for business workflows
  - Workflow connections between agents documented

### Changed
- All business agents now produce persistent artifacts
- Agents can chain outputs: discovery → positioning → sales → proposal

### Documentation
- Updated CLAUDE.md with artifact directory structure
- Added workflow connection diagram

## [1.4.0] - 2026-02-08

### Added
- **6 Additional Business Agents** for solopreneurs:
  - High Impact: outreach-agent, proposal-agent, case-study-agent
  - Nice to Have: financial-agent, automation-agent, personal-brand-agent
- All new agents use Opus model for strategic thinking

### Changed
- Total agent count now: 30 (16 development + 14 business)

### Documentation
- Updated README.md and CLAUDE.md with new agent count
- Added new agents to USER-GUIDE.md

## [1.3.0] - 2026-02-08

### Added
- **8 Business Strategy Agents** for solopreneurs and startups:
  - Tier 1 (Customer Acquisition): customer-discovery-agent, sales-enablement-agent, positioning-strategy-agent
  - Tier 2 (Growth): content-marketing-agent, seo-sem-agent, pricing-strategy-agent
  - Tier 3 (Long-term): customer-success-agent, partnership-agent
- All business agents use Opus model for strategic thinking

### Changed
- Updated security-reviewer and product-ideas-agent to use Opus model
- Total agent count now: 24 (16 development + 8 business)

### Documentation
- Updated README.md and CLAUDE.md with new agent count
- Added Business Strategy Agents section to USER-GUIDE.md

## [1.2.0] - 2026-02-08

### Added
- **Domain Extensions**:
  - Marketing commands (`/prp-mkt:*`): landing, demo, pitch, competitor
  - AI Bot commands (`/prp-bot:*`): intent, flow, prompt-eng, voice-ux, integration
- New command namespace structure for better organization
- 6 additional development agents: accessibility-reviewer, dependency-analyzer, observability-reviewer, performance-analyzer, product-ideas-agent, security-reviewer

### Changed
- Reorganized command namespaces:
  - Core commands now under `/prp-core:*`
  - Marketing commands under `/prp-mkt:*`
  - Bot commands under `/prp-bot:*`
- Updated installation script for new folder structure

### Documentation
- Created comprehensive USER-GUIDE.md with Thai documentation
- Updated all command references to new namespace format

## [1.1.0] - 2025-02-03

### Added
- **Claude Code Advanced Features**:
  - 10 specialized agents (code-reviewer, code-simplifier, codebase-analyst, codebase-explorer, comment-analyzer, docs-impact-agent, pr-test-analyzer, silent-failure-hunter, type-design-analyzer, web-researcher)
  - Skills directory with prp-core-runner skill
  - Hooks directory with Ralph stop mechanism
  - Plugin metadata for Claude Code marketplace
- Installation script now installs Claude Code agents, skills, hooks, and plugin metadata
- Sync script updated to sync all Claude Code advanced features

### Changed
- Enhanced `/prp-review-agents` command - now fully functional with all 7+ specialized agents
- Improved `/prp-plan` and `/prp-design` commands - now use Task tool with Explore agent
- Updated documentation to reflect Claude Code advanced capabilities

### Fixed
- Missing agents causing `/prp-review-agents` to fail in new installations
- Missing Task tool agents for codebase exploration commands

## [1.0.0] - 2025-02-03

### Added
- Initial release of PRP Framework
- 8 core workflows: PRD, Design, Plan, Implement, Review, Commit, PR, Run-all
- Cross-tool adapters for:
  - Claude Code (15 commands)
  - Codex (8 skills)
  - OpenCode (8 commands)
  - Gemini CLI (8 commands)
  - Generic/Kimi (AGENTS.md)
- Installation scripts with symlink support and hard copy fallback
- Tool-specific naming convention for parallel artifact generation
- Comprehensive documentation (README, GETTING_STARTED, WORKFLOWS, CONTRIBUTING)
- MIT License with attribution to original work by Wirasm

### Features
- **Design Doc Workflow**: Optional reference material for complex features
- **Tool-Specific Suffixes**: `-agents`, `-codex`, `-opencode`, `-gemini`, `-other`
- **Portable Architecture**: Works as Git submodule or standalone template
- **100% Feature Parity**: All tools implement same logic from source prompts
- **Auto-update**: Symlink-based installation updates automatically on git pull
- **Cross-platform**: macOS, Linux, Windows (with Git symlink support)

### Documentation
- README.md with quick start and overview
- docs/GETTING_STARTED.md for step-by-step setup
- docs/WORKFLOWS.md with detailed workflow descriptions
- docs/CONTRIBUTING.md with contribution guidelines

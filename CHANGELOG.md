# Changelog

All notable changes to PRP Framework will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Breaking Change Policy

### What constitutes a breaking change (requires major version bump)

- **Artifact format changes**: changes to frontmatter fields, section names, or required structure in `.prp-output/` files that would make existing artifacts unreadable by newer commands
- **State file format changes**: changes to `.claude/prp-run-all.state.md` schema that break `--resume` for in-progress runs
- **Flag removal or rename**: removing or renaming flags that users depend on (e.g. `--ralph`, `--resume`, `--no-interact`)
- **Install path changes**: moving adapter directories to different locations (breaks existing symlinks)
- **Hook interface changes**: changing the stop hook output format that `prp-ralph-stop.sh` reads

### What is NOT a breaking change

- Adding new optional flags
- Adding new phases or sections to prompts (additive)
- Adding new commands or agents
- Changing prompt wording or logic that does not affect artifact format
- Bug fixes that change behavior from wrong to correct

### Migration guide requirement

Every major version release MUST include a `docs/migration/vX.0-to-vY.0.md` file documenting:
1. What changed and why
2. Step-by-step migration for existing artifacts
3. How to update `--resume` state files if format changed
4. Any adapter-specific differences

## [Unreleased]

### Fixed
- **`prp-run-all` Step 6.2 review-fix trigger condition** (Claude Code):
  - Bug: loop only triggered `prp-review-fix` when critical/high issues found — medium and suggestion were silently skipped
  - Fixed: trigger condition now checks "any issues matching `FIX_SEVERITY`" (default: critical, high, medium, suggestion — all levels)
  - Removed misleading Step 7 note suggesting manual `prp-review-fix` for medium/suggestion (now handled automatically)
- **`prp-run-all` Step 4→5 transition pause** (Claude Code):
  - Bug: AI occasionally paused after commit step waiting for user input before creating PR
  - Fixed: strengthened transition instruction — explicitly prohibits `AskUserQuestion` and instructs immediate Skill tool call
- **`prp-review-fix` Phase 1.1: PR number not extracted when artifact path provided** (Claude Code):
  - Bug: when called with artifact path (e.g. from run-all), `{NUMBER}` was undefined for checkout and PR comment phases
  - Fixed: added explicit bash snippet to extract PR number from filename pattern `pr-{NUMBER}-*.md`, with `gh pr view` fallback
- **`prp-review-fix` Phase 1.2: discovery glob missed `prp-review-agents` artifacts** (Claude Code):
  - Bug: glob `pr-{NUMBER}-review*.md` did not match `pr-{NUMBER}-agents-review.md` (agents artifacts)
  - Fixed: updated glob to `pr-{NUMBER}-*review*.md` — matches both `pr-123-review.md` and `pr-123-agents-review.md`

### Added
- **`prp-rollback` command** (Claude Code only):
  - `/prp-core:prp-rollback [--soft | --hard | --restore]`
  - `--soft`: unstage changes, keep working directory (safe, no data loss)
  - `--hard`: reset to `origin/main` with stash backup created first
  - `--restore`: pop most recent PRP rollback stash to recover changes
  - Never deletes branches — only suggests cleanup after `--hard`
- **`--dry-run` flag for run-all** (Claude Code only):
  - Preview all workflow steps without executing anything
  - Shows: steps, estimated token cost per phase, artifacts that would be created
  - All 6 adapters updated
- **`install.sh` idempotency**:
  - `install_directory`: skips if target is already the correct symlink (fast path)
  - `install_file`: skips if already correct symlink
  - Re-running install.sh is now a safe no-op when nothing changed
- **`install.sh` per-file install for agents and hooks**:
  - `.claude/agents/` and `.claude/hooks/` now use per-file symlinks instead of whole-directory symlink
  - Preserves custom agents/hooks added by user — only PRP-owned files are managed
- **`install.sh` auto-recovery**:
  - On startup, detects typechanged files (blob → symlink) in `adapters/claude-code-agents/` and `adapters/claude-code-hooks/`
  - Automatically restores via `git checkout --` before proceeding — no manual intervention needed

### Fixed
- **`install.sh` bash `||`/`&&` operator precedence bug** (critical):
  - `[ -e "$f" ] || [ -L "$f" ] && rm` was parsed as `([ -e ] || [ -L ]) && rm` (left-associative, equal precedence)
  - When file existed, `rm` was called — deleted regular files and replaced with self-referencing symlinks in `.prp/adapters/claude-code-agents/`
  - Fixed to explicit `if [ -e ] || [ -L ]; then rm; fi` in both `install_files_into_dir` and `install_file`
- **`install.sh` directory symlink migration**:
  - `install_files_into_dir` failed silently when target was an old whole-directory symlink (`.claude/agents → .prp/adapters/claude-code-agents/`)
  - `mkdir -p` was a no-op, causing `target_file` to resolve into `.prp/` and damage source files
  - Fixed: detect directory symlink and remove it before `mkdir -p`

### Tests
- **14 new bats tests** (install.bats + structure.bats + parity.bats):
  - `install_files_into_dir` function existence and per-file behavior
  - `readlink` idempotency check (already-correct symlink skipped)
  - Agents and hooks use per-file install (not whole-dir symlink)
  - `prp-rollback` command exists and has `--soft`/`--hard`/`--restore` modes
  - `--dry-run` flag exists in run-all Claude Code adapter
  - Rollback stash backup, Success Criteria, never-delete-branches rule

### Added
- **Conditional Design Doc in Plan** (all adapters):
  - Phase 5.2: TECHNICAL DESIGN with 5 sub-sections (API Contracts, DB Schema, Sequence Diagrams, NFRs, Migration & Rollback)
  - COMPLEXITY_TRIGGERS system: LOW skips design, MEDIUM includes if API/DB changes, HIGH includes all
  - References existing Design Doc at `.prp-output/designs/` if available
- **TDD Approach in Implement** (all adapters):
  - Phase 3 restructured: Write Test First (RED) → Implement (GREEN) → Validate
  - Applies to tasks creating new functions/modules; config/wiring/schema tasks skip test-first
  - TDD progress tracking: `Task 1: Test ✅ (3 cases) — Impl ✅`
- **PRD Enhanced Sections** (all adapters):
  - Deployment & Rollback Strategy (conditional — feature flags, rollback triggers, gradual rollout)
  - Backward Compatibility (conditional — breaking changes, migration path, deprecation timeline)
  - Privacy & Compliance (conditional — GDPR, data handling, consent, retention)
  - Risk Analysis (conditional — technical/business/operational/security risks)
- **Validation Levels Enhancement in Implement** (all adapters):
  - Integration Tests (conditional — if plan specifies or project has `test:integration`)
  - Security Checks (basic SAST — hardcoded secrets, SQL injection, unsafe eval/exec)
  - Performance Regression (conditional — benchmark comparison, flag >20% regression)
  - API Contract Validation (conditional — OpenAPI/GraphQL schema validation)
- **Pre-commit Quality Check in Commit** (all adapters):
  - Phase 0: Advisory scan for debug artifacts (TODO/FIXME, console.log/debugger)
  - Type safety check (`any` type usage in TypeScript)
  - Quick validation (skip in run-all context)
  - Warns but does NOT block commit
- **Expanded Testing Strategy in Plan** (all adapters):
  - Integration Tests (conditional — MEDIUM+ with multi-component interactions)
  - Test Data Requirements (category, data needed, source)
  - Performance Benchmarks (conditional — HIGH or performance-sensitive)
- **19 new structural tests** (structure.bats + parity.bats):
  - 14 structure tests for plan, implement, prd, commit quality enhancements
  - 5 cross-adapter parity tests for Technical Design, TDD, security checks, Backward Compatibility, pre-commit

### Added
- **10 new AI-user structural tests** (structure.bats + parity.bats):
  - Plan template ↔ implement cross-reference integrity (sections plan generates vs implement expects)
  - TRANSITION marker completeness for all run-all workflow steps
  - State file + lock file documentation tests
  - Review severity mapping test (Important → High)
  - Conditional guard format tests (plan template)
  - Report artifact wildcard glob in summary template
  - `--prp-path` flag name consistency parity across all 6 adapters

### Fixed
- **`--plan-path` → `--prp-path`** flag name standardized (all adapters):
  - Generic source and 4 condensed adapters used `--plan-path` while Claude Code adapter and all docs used `--prp-path`
  - Unified to `--prp-path` across all 6 adapters + generic AGENTS.md
- **Missing TRANSITION marker** after Step 3 (implement) in generic run-all:
  - Steps 4 and 5 had explicit "proceed to next step" but Step 3 did not
  - AI could stop after implement instead of continuing to commit
- **Report path in run-all summary** used exact `{name}-report.md` which misses tool-suffixed reports
  - Fixed to `{name}-report*.md` (wildcard glob)

### Enhanced
- **`--no-interact` enforced across full workflow** (all adapters):
  - Added "ZERO questions" critical rule in all run-all adapters — orchestrator must NEVER use AskUserQuestion when flag set
  - run-all now passes `--no-interact` to `/prp-pr` sub-command
  - All PR commands handle `--no-interact` for multiple template selection (auto-select default)
  - Covers all interactive points: plan (ambiguous reqs), PR (template choice), stale state (auto-clean)

### Added
- **Phase 0: Context Detection in Review** (all adapters):
  - Review checks for pre-generated `pr-context-{BRANCH}.md` before fetching PR diff
  - Supports `--context` flag from run-all for explicit context passing
  - Saves ~60K tokens when context file available
- **Success Criteria in all 9 core prompts** — ensures every workflow has clear pass/fail conditions
- **Edge Cases in all 9 core prompts** — documents error handling and boundary scenarios for AI consumers
- **38 new structural/parity/negative tests** (structure.bats + parity.bats):
  - `--no-interact` structure + parity tests
  - `--severity` parity test
  - Expanded design.md, review.md, pr.md, review-fix.md structure tests
  - Cross-reference integrity tests (report glob, implement→review artifact naming)
  - Deprecated pattern negative tests
  - Success Criteria + Edge Cases completeness tests
  - Artifact variable naming consistency tests

### Fixed
- **Report glob mismatch** (all review/review-agents files):
  - `*-report.md` didn't match tool-suffixed reports like `*-report-agents.md`
  - Fixed to `*-report*.md` across all review adapters
- **run-all `--context` passing** (all adapters):
  - Step 6 now checks for `pr-context-{BRANCH}.md` and passes `--context` flag to review
- **Artifact variable naming** standardized across all source prompts:
  - `{kebab-case-name}` (prd.md), `{feature}` (design.md), `{kebab-case-feature-name}` / `{feature-name}` (plan.md), `{plan-name}` (implement.md) → all unified to `{name}`

### Added
- **`--no-interact` flag** (all adapters):
  - Enables fully unattended workflow execution — no user prompts
  - Plan step uses best judgment instead of asking for clarification (documents assumptions)
  - Stale state file auto-cleaned instead of waiting for user decision
  - All 6 adapters updated (Claude Code, Codex, OpenCode, Gemini, Antigravity, generic)

### Fixed
- **PR→Review transition** in run-all workflow:
  - `prp-pr` output "Next Steps" (wait for CI, request review) caused orchestrator to stop after PR creation
  - Added explicit transition instruction after Step 5 and orchestrator note to `prp-pr` output (all adapters)
- **Commit→PR transition** in run-all workflow:
  - `prp-commit` output "Next: git push or /prp-pr" caused orchestrator to stop
  - Added explicit transition instruction and orchestrator note to all adapters

### Changed
- **FIX_SEVERITY default** changed from `critical,high` to `critical,high,medium,suggestion` in all run-all adapters
  - Review-fix now fixes all severity levels by default for comprehensive code quality
  - Use `--fix-severity critical,high` to fix only blocking issues
- **Renamed** `prp-core-run-all.md` → `prp-run-all.md` for consistent naming
  - Old: `/prp-core:prp-core-run-all` (redundant "prp-core" twice)
  - New: `/prp-core:prp-run-all` (consistent with all other commands)

### Previous
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
  - `--fix-severity <levels>` flag to override review-fix severity (default: `critical,high,medium,suggestion`)
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
- **Recommended Claude Code permissions config** added to USER-GUIDE.md and GETTING_STARTED.md
  - Allowlist-based config for all PRP-required bash commands (git, gh, file ops, build tools)
  - Three-tier approach: allowlist (recommended), `--no-interact` flag, `--dangerously-skip-permissions` (CI only)
  - Scenario-based recommendation table
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

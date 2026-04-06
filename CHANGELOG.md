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

## [2.4.0] — 2026-04-06

**Issue-Driven Lifecycle Release** — `run-all` now supports full issue-to-merge lifecycle with `--issue N` flag. Smart plan detection analyzes issue scope and auto-decides whether to skip plan, fast-track, or full plan. Review-fix loop targets 0 issues (configurable up to 5 rounds). `--merge` flag auto squash-merges and cleans up after review passes.

### Added

- **`--issue <N>` flag** — fetch GitHub issue context, extract feature description from title/body. Smart plan detection scores issue scope (0-1: skip plan, 2-3: fast plan, 4-5: full plan) (#56)
- **`--merge` flag** — auto squash-merge PR after review passes (0 issues all severities). Runs `{TOOL}:cleanup` and closes issue if `--issue` was used (#56)
- **`--max-review-rounds <N>` flag** — configurable review-fix loop limit (default: 5, was hardcoded 2) (#56)
- **Step 0.8: Fetch Issue Context** — new workflow step with smart plan detection scoring table (#56)
- **Step 8: Merge & Cleanup** — new workflow step with pre-check (mergeable state, already-merged), squash merge, cleanup, and issue close verification (#56)
- **Stub plan generation** — when plan is skipped (small issue), generates minimal stub plan file instead of passing sentinel string (#56)
- **Flag conflict validation** — `--merge` + `--skip-review` or `--no-pr` now STOP with clear error (#56)
- **`mergeable=UNKNOWN` handler** — retry once after 5s, then STOP with actionable message (#56)
- **Empty issue body guard** — warns user and defaults to fast plan instead of silently scoring 0 (#56)

### Changed

- **Review-fix loop** — target changed from "MAX_CYCLES reached" to "0 issues all severities OR MAX_CYCLES reached". Default MAX_CYCLES increased from 2 to 5 (#56)
- **State file schema** — added `issue_number`, `auto_merge`, `max_cycles`, `review_verdict`, `review_cycle` fields for complete `--resume` support (#56)
- **State cleanup timing** — moved from Step 7 to Step 8.4 (after merge succeeds), enabling `--resume` if merge fails (#56)
- **`--since-last-review` fallback** — now displays visible warning when falling back to full review (#56)
- **All 5 adapters regenerated** — claude-code, codex, opencode, gemini, antigravity (#56)
- **prp-core-runner skill** — updated with new flags, step count, and issue-driven examples (#56)

## [2.3.0] — 2026-03-29

**Parallel Agent Release** — Three commands now spawn parallel Agent subprocesses: `prp-review-agents`, `prp-feature-review-agents`, and `prp-design`. Each agent gets a fresh context window for deep exploration. Also includes token optimization, error handling improvements, and review quality enhancements.

### Added

- **`prompts/review-agents.md`** (1141 lines) — new canonical prompt for multi-agent parallel PR review. Spawns `code-reviewer`, `security-reviewer`, `silent-failure-hunter` as core agents in parallel, with conditional dispatch for `dependency-analyzer`, `accessibility-reviewer`, `performance-analyzer`, `type-design-analyzer`, `docs-impact-agent`, `comment-analyzer`, `pr-test-analyzer` (#38)
- **Full `Agent()` dispatch blocks** — explicit `Agent(subagent_type=..., prompt="...")` call blocks for all 10 agents with 20-30 line prompts each (replacing v2.1.0's 1-3 sentence hints)
- **Sequential fallback** — graceful fallback to `{TOOL}:review` (single-session) when Agent tool is unavailable
- **Core agent failure handling** — if any core agent fails, verdict forced to minimum NEEDS FIXES
- **`--context` path validation** — rejects absolute paths and `..` traversal, validates non-empty diff section
- **Context file verification** — STOP if context file fails to create before spawning agents
- **No-PR detection** — explicit STOP with diagnostic when no PR exists for current branch
- **`gh pr review` error handling** — logs actual error, displays WARNING, then falls back to comment
- **Metrics `review_type` field** — JSONL records now distinguish `"agents"` vs `"single"` review type
- **Review artifact frontmatter** — YAML frontmatter with `agents:` field listing which agents ran
- **`prompts/feature-review-agents.md`** (618 lines) — new canonical prompt for multi-agent parallel feature review. Spawns `code-reviewer`, `security-reviewer`, `product-ideas-agent`, `performance-analyzer` as core agents, with conditional dispatch for `accessibility-reviewer`, `dependency-analyzer`, `silent-failure-hunter`, `observability-reviewer` (#48)
- **`design` parallel exploration** — Phase 2 (codebase explore) and Phase 3 (web research) now spawn as parallel agents: `codebase-explorer` + `web-researcher` × 2. Phase 4+ synthesis unchanged. (#49)
- **TDD for UPDATE** — `implement.md` TDD spec now covers UPDATE of existing business logic functions, not just CREATE (#44)
- **Per-task focused tests** — `implement.md` runs focused tests after each task that modifies existing code (#44)
- **Fix bisection** — `review-fix.md` quick-check includes tests for critical/high batches; bisection instruction for unclear batch regressions (#44)

### Fixed

- **`prp-review` error handling backport** — backported all 10 error handling improvements to single-session `prp-review` (#40)
- **Missing error paths** — PRD file-not-found, plan write verification, circular dependency detection in `plan.md`; PARTIAL status format in `implement.md`; fix-summary input validation and "already fixed" tracking in `review-fix.md` (#43)
- **Token optimization** — skip redundant Phase 0 in `implement.md`/`review-fix.md` when plan provides commands; remove 4 duplicate "common patterns" tables; skip output phases in sub-command mode; scope "read similar files" in `review-fix.md` (~12-21K tokens saved per workflow) (#42)
- **`run-all` REVIEW_ARTIFACT path** — correct path for review-agents output (`-agents-review.md` vs `-review-{TOOL}.md`)

### Changed

- **`silent-failure-hunter`** promoted from conditional to **core agent** (always-run, 3rd alongside code-reviewer and security-reviewer)
- **`dependency-analyzer`** demoted from always-run to conditional (triggers on package file changes)
- **`adapters.yml`** — `review-agents` and `feature-review-agents` changed from `alias: true` to standalone command config
- **All adapter variants** regenerated from new canonical prompts
- **Review summary format** — adds "Agents Dispatched" table and "(Multi-Agent)" heading

### Migration

- No breaking changes — `run-all` and all existing flags work identically
- `prp-review-agents` and `prp-feature-review-agents` now spawn parallel Agent subprocesses instead of aliasing to single-session commands
- `design` now parallelizes Phase 2+3 (explore+research) — synthesis unchanged
- Use `--review-single-agent` flag in `run-all` for single-session review behavior
- Use `feature-review` or `review` for single-session sequential alternatives

---

## [2.2.0] — 2026-03-28

**Auto-Generation & Cross-Adapter Expansion Release** — Adapter files are now auto-generated from `prompts/` as single source of truth. Marketing/bot commands expanded to all 5 adapters. Monorepo support added.

### Added

- **Adapter auto-generation** (`scripts/generate-adapters.py`) — generates all 140 adapter files (28 commands × 5 adapters) from canonical `prompts/` with a single command. Supports `--dry-run`, `--diff`, `--adapter` filter. Eliminates manual 5-adapter sync and prevents cross-adapter drift. (PR #34)
- **`adapters.yml`** — central config defining transformation rules for all adapters: file patterns, placeholder mappings (`{ARGS}` → `$ARGUMENTS`/`{{args}}`), frontmatter formats, tool command syntax
- **Overlay system** (`prompts/overlays/`) — tool-specific content (XML wrapping, agent strategies) that extends base prompts without modifying them. Currently used for Claude Code `plan` XML structure
- **9 marketing/bot commands cross-adapter** — `landing`, `demo`, `pitch`, `competitor`, `intent`, `flow`, `prompt-eng`, `voice-ux`, `integration` now available in all 5 adapters (were Claude Code-only). Total commands: 19 → 28. (PR #35)
- **`group_dirs`** config — routes marketing/bot commands to separate directories for Claude Code (`claude-code-marketing/`, `claude-code-bot/`) while other adapters keep all commands in one directory
- **Monorepo support** — auto-detects pnpm workspaces, Turborepo, Nx, Lerna, yarn/npm workspaces. New `--package <name>` flag for `plan`, `implement`, and `run-all` to scope to a specific package. Per-tool scoped validation commands (e.g., `pnpm --filter api test`, `turbo run lint --filter=api`, `nx run api:lint`). (PR #36)
- **Monorepo-aware commits** — `commit` adds package scope to conventional commit format: `feat(api): description`
- **`requirements.txt`** — Python dependencies for the generator (`pyyaml>=6.0,<7.0`)
- **17 new tests** — overlay XML output, monorepo detection, group_dirs routing, placeholder substitution, TOML validity, idempotency. Total: 244 → 271

### Changed

- **`docs/CONTRIBUTING.md`** — new editing workflow: edit `prompts/` → run `generate-adapters.py` → test. Manual adapter editing no longer needed
- **Adapter files** — all 95 existing + 45 new adapter files are now generated from canonical prompts, fixing accumulated drift from manual editing

### Migration

See `docs/migration/v2.1-to-v2.2.md` for details. Key changes:

- **Do NOT manually edit files in `adapters/`** — they are now generated. Edit `prompts/` instead, then run `python3 scripts/generate-adapters.py`
- **New dependency**: Python 3.10+ with `pyyaml` for running the generator
- **No breaking changes** — all existing commands, flags, and artifacts work identically

---

## [2.1.0] — 2026-03-28

**Cross-Adapter Parity Release** — All 8 core commands upgraded to feature parity across 5 adapters. +11,835 lines across 32 files. Every adapter now has phase checkpoints, full templates, failure diagnostics, and unique features ported across tools.

### Changed

- **`review`** — All adapters upgraded to 11-pass multi-pass review with incremental review, large PR strategy, conditional dispatch, dedup examples, metrics, per-file checklist, PRD update, critical reminders, success criteria
- **`implement`** — Full TDD approach (RED/GREEN), phase checkpoints, context file template, report template, PRD update with before/after examples, failure diagnostics per type, artifact fallback
- **`review-fix`** — 9-phase workflow with artifact discovery (multi-tool support), fix plan output, skip logic, per-batch validation, detailed commit template, edge cases (drift, already-fixed, all-skipped), adapter-specific artifact suffix examples
- **`pr`** — Phase checkpoints, implementation report enrichment (PR body includes validation results and deviations from plan), commit prefix table, full output template
- **`commit`** — Plan-aware commit messages (Phase 1.5: loads completed plan context to enrich commit body), pre-commit quality check with bash commands, phase checkpoints
- **`cleanup`** — Manifest-first artifact discovery (check `.prp-output/manifests/` before glob fallback), orphaned state file cleanup (`.claude/prp-run-all.state.md`), phase checkpoints, detailed error handling for branch deletion
- **`run-all`** — Dry-run mode (preview with token estimate), Ralph mode support, full state/lock management with resume, artifact fallback templates, `--since-last-review` for incremental re-verify (token optimization), token budget tables, 10 critical rules, 12 usage examples
- **`plan`** — Full PRD parsing (6 steps), toolchain detection with tables, complexity triggers, testing decision gates, fast-track mode, explore fallback with source tagging, technical design (5 sub-sections), UX diagrams, 18-section plan structure, 5-category verification checklist, confidence scoring

### Added (new features across all adapters)

- **Implementation Report Enrichment** (`pr`) — PR body automatically includes summary, deviations, and validation results from `.prp-output/reports/`
- **Plan-Aware Commit** (`commit`) — Commit message enriched with completed plan context (summary, task count)
- **Manifest-First Discovery** (`cleanup`) — Precise artifact lookup via `.prp-output/manifests/{BRANCH}.json` before glob fallback
- **Orphaned State Cleanup** (`cleanup`) — Removes `.claude/prp-run-all.state.md` when cleaning branches
- **Incremental Re-verify** (`run-all`) — Step 6.4 uses `--since-last-review` flag for token-efficient re-review after fixes
- **Dry-Run Mode** (`run-all`) — Preview all steps with estimated token cost without executing
- **Ralph Mode** (`run-all`) — Autonomous implementation loop support in all adapters

### Line count changes (before → after)

| Command | Codex | OpenCode | Antigravity | Gemini | Claude Code |
|---------|-------|----------|-------------|--------|-------------|
| review | 307→876 | 205→874 | 201→873 | 154→655 | 775→846 |
| implement | 200→755 | 88→754 | 86→753 | 53→752 | 755 (baseline) |
| review-fix | 307→674 | 259→673 | 246→672 | 90→671 | 696 (baseline) |
| pr | 149→406 | 61→405 | 62→404 | 42→403 | 346→388 |
| commit | 95→211 | 50→210 | 42→209 | 27→208 | 161→204 |
| cleanup | 185→297 | 78→296 | 74→295 | 35→294 | 292→325 |
| run-all | 170→464 | 139→463 | 133→462 | 87→461 | 777→780 |
| plan | 197→522 | 72→521 | 80→520 | 38→519 | 1039 (baseline) |

---

## [2.0.0] — 2026-03-16

**Full Cross-Tool Portability Release** — All 17 canonical prompts with 85 adapter files across 5 tools (Claude Code, Codex, OpenCode, Gemini CLI, Antigravity). Breaking change: unified artifact paths to `.prp-output/`.

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

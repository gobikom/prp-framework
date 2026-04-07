# Contributing to PRP Framework

Thank you for considering contributing to PRP (Prompt-Run-Perfect) Framework! This document provides guidelines for contributing.

## Ways to Contribute

- 🐛 Report bugs
- 💡 Suggest new features or workflows
- 📝 Improve documentation
- 🔧 Fix bugs or implement features
- 🧪 Add tests or examples
- 🌍 Add support for new AI tools

## Development Setup

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/prp-framework.git
cd prp-framework

# Install dev dependencies (for running tests)
brew install bats-core jq   # macOS
# apt-get install bats jq   # Ubuntu/Debian

# Create feature branch
git checkout -b feature/your-feature-name

# Test your changes in a project
cd ../test-project
git submodule add ../prp-framework .prp
cd .prp && ./scripts/install.sh
```

## Running Tests

### All Tests

```bash
# Run every test suite
bats tests/install/install.bats tests/run-all/state-file.bats tests/ralph/ralph-stop.bats \
     tests/scripts/scripts.bats tests/commands/structure.bats tests/adapters/parity.bats \
     tests/e2e/install-sandbox.bats tests/e2e/state-lifecycle.bats tests/e2e/scripts-sandbox.bats
```

### Unit Tests by Suite

```bash
bats tests/install/install.bats    # install script integrity (32 tests)
bats tests/run-all/state-file.bats # state management helper (20 tests)
bats tests/ralph/ralph-stop.bats   # ralph stop hook (23 tests)
bats tests/scripts/scripts.bats    # helper scripts (8 tests)
bats tests/commands/structure.bats # command markdown structure (89 tests)
bats tests/adapters/parity.bats    # cross-adapter parity (28 tests)
```

### E2E Infrastructure Tests

```bash
bats tests/e2e/install-sandbox.bats  # install.sh in real temp sandbox (11 tests)
bats tests/e2e/state-lifecycle.bats  # full state machine lifecycle (8 tests)
bats tests/e2e/scripts-sandbox.bats  # cleanup-artifacts.sh with real files (5 tests)
```

E2E tests cover the **shell/infrastructure layer** only (~40% of workflow). AI prompt logic requires Claude running and is not testable in CI.

See `tests/e2e/README.md` for details on the sandbox strategy.

### Ralph Stop Hook Tests

```bash
# Verbose output
bats --verbose-run tests/ralph/ralph-stop.bats

# TAP format (for CI)
bats --formatter tap tests/ralph/ralph-stop.bats
```

Tests cover: no state file, COMPLETE detection, iteration increment, max iterations, false positive prevention, corrupt state handling, missing transcript, JSON output format.

> **Note:** `bats-core` and `jq` are dev dependencies for testing the framework itself. Consumer projects do not need them.

## Project Structure

```
prp-framework/
├── prompts/              # Source of truth (tool-agnostic)
├── adapters/
│   ├── claude-code/      # Claude Code specific
│   ├── codex/           # Codex specific
│   ├── opencode/        # OpenCode specific
│   ├── gemini/          # Gemini specific
│   └── generic/         # Generic/Kimi
├── scripts/             # Installation scripts
└── docs/               # Documentation
```

## Editing Workflow

**IMPORTANT:** Always maintain 100% workflow parity across all tools — every tool must support the same workflow steps (PRD → Plan → Implement → Review → Commit → PR). All adapters are auto-generated from `prompts/` as the single source of truth.

### 1. Edit Source Prompt

Edit the canonical reference in `prompts/`:

```bash
# Example: Adding a new phase to plan workflow
vim prompts/plan.md
```

If you need tool-specific content (e.g., Claude Code XML wrapping), edit the overlay instead:

```bash
vim prompts/overlays/claude-code/plan.md
```

### 2. Generate All Adapters

Run the auto-generation script to produce all 5 adapter formats:

```bash
# Generate all adapters from prompts/
python3 scripts/generate-adapters.py

# Preview without writing (dry run)
python3 scripts/generate-adapters.py --dry-run

# Generate only one adapter
python3 scripts/generate-adapters.py --adapter gemini
```

**Do NOT manually edit files in `adapters/`** — they are generated and will be overwritten.

### 3. Run Parity Tests

```bash
bats tests/adapters/parity.bats
```

### 4. Test with Tools (optional)

Test changes with each tool:

```bash
# Test Claude Code
claude
/prp-plan test-feature

# Test Codex
codex
$prp-plan test-feature

# Test OpenCode
opencode
/prp:plan test-feature

# Test Gemini
gemini
/prp:plan test-feature
```

## Adding a New Agent

Create a new agent file in `adapters/claude-code-agents/`:

```bash
vim adapters/claude-code-agents/my-agent.md
```

Required frontmatter:
```yaml
---
name: my-agent
description: What the agent does
model: sonnet (or haiku/opus)
color: "#hexcode"
---
```

Then run `install.sh` to create symlinks.

## Key Files

| File | Purpose |
| ------ | ------- |
| `scripts/generate-adapters.py` | Auto-generate all 5 adapters from prompts/ |
| `scripts/install.sh` | Main installation script (auto-registers ralph hook) |
| `scripts/sync.sh` | Sync updates for hard-copy (non-symlink) installs |
| `scripts/cleanup-artifacts.sh` | Artifact cleanup utility |
| `scripts/migrate-artifacts.sh` | Migration from old artifact paths |
| `scripts/prp-run-all-state.sh` | State management for run-all workflow |
| `adapters.yml` | Adapter transformation config (placeholders, frontmatter, formats) |
| `prompts/overlays/` | Tool-specific overlay content (XML wrapping, agent strategies) |
| `docs/SCRIPTS-REFERENCE.md` | Detailed documentation for all scripts |
| `docs/USER-GUIDE.md` | Complete command reference (Thai) |
| `README.md` | Project overview (English) |
| `adapters/claude-code/prp-ralph.md` | Ralph autonomous loop command |
| `adapters/claude-code/prp-run-all.md` | End-to-end workflow orchestrator (supports --ralph) |
| `adapters/claude-code-hooks/prp-ralph-stop.sh` | Stop hook — core mechanism for ralph loop |
| `adapters/claude-code-hooks/README.md` | Hook setup documentation |
| `tests/ralph/ralph-stop.bats` | bats tests for stop hook (23 test cases) |
| `tests/e2e/install-sandbox.bats` | E2E install tests in real sandbox (11 test cases) |
| `tests/e2e/state-lifecycle.bats` | E2E state machine lifecycle tests (8 test cases) |
| `tests/e2e/scripts-sandbox.bats` | E2E cleanup-artifacts.sh tests (5 test cases) |
| `adapters/claude-code/prp-feature-review.md` | Feature review with token optimization |
| `adapters/claude-code/prp-feature-review-agents.md` | Multi-agent feature review |

## Adding a New Workflow

### 1. Create Source Prompt

```bash
# Create new workflow prompt
vim prompts/my-workflow.md
```

Template:
```markdown
# My Workflow Name

**Input**: `{ARGS}`

## Mission
{What this workflow does}

## Phases
1. Phase 1: {Description}
2. Phase 2: {Description}

## Output
{What gets produced}

## Success Criteria
- {Criterion 1}
- {Criterion 2}
```

### 2. Add Command to adapters.yml

Add an entry under `commands:` in `adapters.yml`:

```yaml
  my-workflow:
    description:
      claude-code: "Short description for Claude Code"
      default: "Longer description for other adapters."
    argument-hint: "<input> [--flags]"
    codex-short-description: "Short name"
    opencode-agent: "plan"  # or "build"
```

### 3. Generate Adapters

```bash
python3 scripts/generate-adapters.py
bats tests/adapters/parity.bats
```

If Claude Code needs tool-specific content (XML wrapping, agent strategies), create an overlay:

```bash
vim prompts/overlays/claude-code/my-workflow.md
```

See `prompts/overlays/README.md` for overlay format.

### 3. Update Documentation

Add to `docs/WORKFLOWS.md`:
```markdown
## Workflow: My Workflow

**Purpose:** {Description}

### Usage
...
```

Add to `README.md`:
```markdown
| Workflow | Description | When to Use |
|----------|-------------|-------------|
| **My Workflow** | {Description} | {When to use} |
```

### 4. Test Installation

```bash
cd ../test-project
cd .prp && git pull && ./scripts/install.sh
# Verify new workflow appears
```

## Code Style

### Prompts

- Use clear, actionable language
- Include concrete examples
- Document all phases explicitly
- Specify success criteria

### Scripts

- Use bash with `set -e`
- Include error handling
- Provide colored output
- Test on multiple platforms

### Documentation

- Use GitHub-flavored Markdown
- Include code examples
- Keep formatting consistent
- Update all relevant docs

## Commit Guidelines

Use conventional commits:

```bash
feat: add new workflow for X
fix: correct Y in Z workflow
docs: update WORKFLOWS.md with examples
refactor: improve install script
test: add validation for X
chore: update dependencies
```

## Pull Request Process

1. **Fork** the repository
2. **Create** a feature branch
3. **Make** your changes
4. **Test** thoroughly across all tools
5. **Update** documentation
6. **Commit** with conventional format
7. **Push** to your fork
8. **Open** a pull request

### PR Template

```markdown
## Description
{What does this PR do?}

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring

## Testing
- [ ] Tested with Claude Code
- [ ] Tested with Codex
- [ ] Tested with OpenCode
- [ ] Tested with Gemini
- [ ] Documentation updated

## Checklist
- [ ] Workflow parity across all tools (same steps, not necessarily same depth)
- [ ] All adapters updated
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
```

## Versioning

We use [Semantic Versioning](https://semver.org/):

- **Major (X.0.0):** Breaking changes — artifact format, state schema, flag removal, install path changes
- **Minor (0.X.0):** New features, backward compatible — new commands, agents, optional flags, additive prompt changes
- **Patch (0.0.X):** Bug fixes — prompt logic corrections, wording improvements, doc fixes

### Breaking Change Definition

See `CHANGELOG.md` → Breaking Change Policy for the full list of what constitutes a breaking change.

**Key rule**: If an existing `.prp-output/` artifact or `.prp-output/state/run-all.state.md` would stop working correctly after the update, it is a breaking change.

### Migration Guide Requirement

Every **major** version MUST ship with `docs/migration/vX.0-to-vY.0.md` covering:
1. What changed and why
2. Step-by-step artifact migration
3. State file format changes (affects `--resume`)
4. Adapter-specific differences

## Release Process

1. Update `CHANGELOG.md`
2. Update version in `README.md`
3. Create git tag: `git tag -a v1.1.0 -m "Release v1.1.0"`
4. Push tag: `git push origin v1.1.0`
5. Create GitHub Release with changelog

## Getting Help

- **Questions:** [GitHub Discussions](https://github.com/gobikom/prp-framework/discussions)
- **Bugs:** [GitHub Issues](https://github.com/gobikom/prp-framework/issues)
- **Chat:** (if applicable)

## Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on the problem, not the person
- Help others learn and grow

## Attribution

When contributing significant changes:
- Add yourself to AUTHORS file (if exists)
- Update copyright in LICENSE if appropriate

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

# Changelog

All notable changes to PRP Framework will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

## [Unreleased]

### Planned
- GitHub Actions workflow templates
- Example projects showcase
- Video tutorials
- CLI tool for framework management
- Additional language support (Python, Go, Rust)

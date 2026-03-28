<!-- PRP-FRAMEWORK:BEGIN v{VERSION} (managed by prp-framework — do not edit manually) -->
## PRP Workflow

| Action | Command | Description |
|--------|---------|-------------|
| Plan | `/prp-core:prp-plan` | Create implementation plan |
| Implement | `/prp-core:prp-implement` | Execute plan with validation |
| Review | `/prp-core:prp-review-agents` | Multi-agent PR review |
| Commit | `/prp-core:prp-commit` | Smart commit with context |
| PR | `/prp-core:prp-pr` | Create PR from branch |
| Cleanup | `/prp-core:prp-cleanup` | Post-merge branch cleanup |
| Full workflow | `/prp-core:prp-run-all` | Plan → Implement → PR → Review |

Artifacts: `.prp-output/` | All commands: `/prp-core:prp-*`, `/prp-mkt:prp-*`, `/prp-bot:prp-*`
<!-- PRP-FRAMEWORK:END -->

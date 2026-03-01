# PRP Framework — E2E Infrastructure Tests

End-to-end tests that exercise the framework's **shell/infrastructure layer** against real files and directories. AI prompt logic is not testable without Claude running; these tests cover the ~40% of the workflow that runs in the terminal.

## What's Covered

| Test File | What It Tests | Tests |
|-----------|--------------|-------|
| `install-sandbox.bats` | `install.sh` in a real temp sandbox | 11 |
| `state-lifecycle.bats` | State machine create→update→resume→cleanup sequence | 8 |
| `scripts-sandbox.bats` | `cleanup-artifacts.sh` with real files and fake mtimes | 5 |

**Total: 24 tests**

## What's NOT Covered

- AI prompt execution (requires Claude)
- Actual `git` operations (commit, push, PR creation)
- Multi-agent orchestration
- Review/implement workflow correctness

## Prerequisites

```bash
brew install bats-core   # macOS
# apt-get install bats  # Ubuntu/Debian
```

## Running

```bash
# Individual suites
bats tests/e2e/install-sandbox.bats
bats tests/e2e/state-lifecycle.bats
bats tests/e2e/scripts-sandbox.bats

# All e2e tests
bats tests/e2e/

# Full test suite (all 220+ tests)
bats tests/
```

## Sandbox Strategy

### install-sandbox.bats

`install.sh` derives `FRAMEWORK_DIR` and `PROJECT_DIR` from `BASH_SOURCE[0]` at runtime. To get a clean `PROJECT_DIR`, the tests copy the framework into a temp dir:

```
$SANDBOX/
├── prp-framework/    ← copied from repo (FRAMEWORK_DIR)
│   └── scripts/install.sh
└── .claude/          ← created by install.sh (PROJECT_DIR = $SANDBOX)
    ├── commands/prp-core → ../prp-framework/adapters/claude-code
    ├── agents/
    └── hooks/
```

Each test runs in a fresh sandbox; `teardown()` removes it completely.

### state-lifecycle.bats

Tests use `mktemp -d` + `cd` to isolate state files. Tests simulate the full call sequence that `prp-run-all` makes: create → lock → update-step × N → add-artifact → unlock → cleanup.

### scripts-sandbox.bats

`cleanup-artifacts.sh` uses interactive `read -p` prompts. Tests pipe `echo "y"` or `echo "n"` to stdin. Old file modification times are faked with `touch -t 202401010000`.

## sample-project/

A minimal reference project structure. The install sandbox tests create their own temp projects dynamically in `setup()` — this directory is for documentation and reference only.

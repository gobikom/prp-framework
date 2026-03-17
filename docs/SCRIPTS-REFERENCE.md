# Scripts Reference

The PRP Framework ships with five utility scripts in the `scripts/` directory. These handle installation, syncing, migration, state management, and artifact cleanup.

## Quick Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `install.sh` | Install adapters into a project via symlinks (with copy fallback) | `./scripts/install.sh [PROJECT_DIR]` |
| `sync.sh` | Re-sync hard-copied adapters from the framework source | `cd .prp && ./scripts/sync.sh` |
| `migrate-artifacts.sh` | Migrate artifacts from legacy paths to `.prp-output/` | `./scripts/migrate-artifacts.sh` |
| `prp-run-all-state.sh` | State management for the `run-all` workflow | `./scripts/prp-run-all-state.sh <command> [args]` |
| `cleanup-artifacts.sh` | Delete artifacts older than N days | `./scripts/cleanup-artifacts.sh [days]` |

## Table of Contents

- [install.sh](#installsh)
- [sync.sh](#syncsh)
- [migrate-artifacts.sh](#migrate-artifactssh)
- [prp-run-all-state.sh](#prp-run-all-statesh)
- [cleanup-artifacts.sh](#cleanup-artifactssh)

---

## install.sh

### Purpose

Main installation script. Sets up all PRP Framework adapters in a consumer project by creating symlinks (preferred) with an automatic fallback to hard copies when symlinks are not supported.

### Usage

```bash
./scripts/install.sh [PROJECT_DIR]
```

`PROJECT_DIR` is resolved in this order:

1. First positional argument (`$1`)
2. `PROJECT_DIR` environment variable
3. Parent directory of the framework (`$FRAMEWORK_DIR/..`)

### How It Works

1. **Auto-recovery** -- Detects git typechange (`T`) status on agent and hook adapter files. If a previous buggy install converted blob files into self-referencing symlinks, the script restores them via `git checkout`.

2. **Adapter installation** -- Installs adapters into the project using two strategies:
   - **Directory symlinks** (`install_directory`) for adapter directories that PRP fully owns (commands, skills, plugin, Codex, OpenCode, Gemini, Antigravity).
   - **Per-file symlinks** (`install_files_into_dir`) for shared directories where the project may have its own custom files (`.claude/agents/` and `.claude/hooks/`). This preserves any non-PRP files already present.
   - **Single-file symlinks** (`install_file`) for standalone files like `AGENTS.md` and `marketplace.json`.

   If symlink creation fails (e.g., on filesystems that do not support them), the script falls back to `cp -r`.

3. **Installed adapter targets:**

   | Source | Target in Project |
   |--------|-------------------|
   | `adapters/claude-code` | `.claude/commands/prp-core/` |
   | `adapters/claude-code-marketing` | `.claude/commands/prp-mkt/` |
   | `adapters/claude-code-bot` | `.claude/commands/prp-bot/` |
   | `adapters/claude-code-agents` | `.claude/agents/` (per-file) |
   | `adapters/claude-code-skills/*` | `.claude/skills/<skill>/` |
   | `adapters/claude-code-hooks` | `.claude/hooks/` (per-file) |
   | `adapters/claude-code-plugin/marketplace.json` | `.claude-plugin/marketplace.json` |
   | `adapters/codex/prp-*` | `.codex/skills/<skill>/` |
   | `adapters/opencode` | `.opencode/commands/prp/` |
   | `adapters/gemini` | `.gemini/commands/prp/` |
   | `adapters/antigravity` | `.agents/workflows/prp/` |
   | `adapters/generic/AGENTS.md` | `AGENTS.md` |

4. **Ralph stop hook registration** -- Makes `prp-ralph-stop.sh` executable and registers it in `.claude/settings.local.json` under `hooks.Stop`. Requires `jq` to be installed; if `jq` is missing, the script prints the JSON snippet for manual addition.

5. **Runtime directories** -- Creates the `.prp-output/` directory tree:
   ```
   .prp-output/
   ├── prds/drafts/
   ├── designs/
   ├── plans/completed/
   ├── reports/
   ├── reviews/
   ├── debug/
   ├── issues/completed/
   └── ralph-archives/
   ```

6. **Gitignore configuration** -- Appends PRP-specific rules to `.gitignore`:
   - Ignores all adapter directories (`.claude/`, `.codex/`, `.opencode/`, etc.)
   - Keeps `.prp-output/` directory visible but ignores tracked file contents
   - If the framework is a local clone (not a git submodule), also ignores `.prp/`

### Examples

```bash
# Install into the current project (framework at .prp)
cd my-project
.prp/scripts/install.sh .

# Install into a specific project directory
./scripts/install.sh /home/user/projects/my-app

# Install using the PROJECT_DIR env var
PROJECT_DIR=/home/user/projects/my-app ./scripts/install.sh
```

### Notes

- The script is **idempotent**. Running it again skips symlinks that are already correct.
- When migrating from an old whole-directory symlink to per-file symlinks (for agents and hooks), the script automatically removes the old directory symlink and creates individual file symlinks instead.
- Requires `jq` for automatic hook registration. Without `jq`, everything else still works -- you just need to register the hook manually.

---

## sync.sh

### Purpose

Re-syncs adapter files for projects that use **hard copies** instead of symlinks. If a target is already a symlink, it is skipped (symlinked installs update automatically when you `git pull` the framework).

### Usage

```bash
cd .prp && ./scripts/sync.sh
```

The script derives `PROJECT_DIR` as the parent of the framework directory. It does not accept arguments.

### How It Works

1. Iterates over all adapter targets (same set as `install.sh`).
2. For each target:
   - If it is a **symlink**, skip it (already up to date).
   - If it is a **real directory/file**, delete it and copy the latest version from the framework source.
   - If it **does not exist**, print a warning and skip.

3. Synced targets include: Claude Code commands, agents, skills, hooks, plugin metadata, Codex skills, OpenCode commands, Gemini commands, and `AGENTS.md`.

### Examples

```bash
# Pull latest framework and re-sync hard copies
cd .prp
git pull origin main
./scripts/sync.sh
```

### Notes

- This script is only needed for hard-copy installations. Symlinked installations stay in sync automatically.
- Unlike `install.sh`, this script does **not** create directories, update `.gitignore`, or register hooks. It only refreshes existing adapter files.
- The script does not sync Antigravity adapters (this is handled only by `install.sh`).

---

## migrate-artifacts.sh

### Purpose

Migrates artifacts from legacy directory paths to the current `.prp-output/` structure. This is a one-time migration script for projects upgrading from older versions of the framework.

### Usage

```bash
./scripts/migrate-artifacts.sh
```

Run from the project root directory.

### How It Works

1. Checks for legacy artifact directories and copies their contents:

   | Old Path | New Path |
   |----------|----------|
   | `.claude/PRPs/*` | `.prp-output/` |
   | `.ai-workflows/plans/*` | `.prp-output/plans/` |
   | `.ai-workflows/reports/*` | `.prp-output/reports/` |

2. Creates target directories if they do not exist.
3. Uses `cp -r` to copy files. Errors on individual files are suppressed to handle empty directories gracefully.

### Examples

```bash
# Run migration from project root
./scripts/migrate-artifacts.sh

# After verifying migration, manually clean up old directories
rm -rf .claude/PRPs
rm -rf .ai-workflows
```

### Notes

- **Non-destructive**: The script copies files but does **not** delete the old directories. You must remove them manually after verifying the migration.
- Safe to run multiple times. Existing files in `.prp-output/` will be overwritten by the copy.
- If no legacy directories are found, the script reports that there is nothing to migrate and exits cleanly.

---

## prp-run-all-state.sh

### Purpose

State management helper for the `run-all` workflow. Manages a state file that tracks the current step, configuration variables, completed steps, and artifacts across the multi-step PRP pipeline.

### Usage

```bash
./scripts/prp-run-all-state.sh <command> [args]
```

### Commands

| Command | Arguments | Description |
|---------|-----------|-------------|
| `create` | `<feature> [use_ralph] [ralph_max_iter] [fix_severity] [skip_review] [no_pr]` | Create a new state file |
| `update-step` | `<step_number> <step_name> <result>` | Record a completed step |
| `get-step` | (none) | Print the current step number |
| `get-var` | `<name>` | Print a variable from YAML frontmatter |
| `add-artifact` | `<artifact_line>` | Add an artifact entry to the state file |
| `cleanup` | (none) | Remove state and lock files |
| `exists` | (none) | Exit 0 if state file exists, exit 1 otherwise |
| `lock` | (none) | Acquire workflow lock (exit 1 if already locked) |
| `unlock` | (none) | Release workflow lock |

### How It Works

1. **State file** is stored at `.claude/prp-run-all.state.md`. It uses YAML frontmatter for configuration variables and a markdown table to track completed steps.

2. **YAML frontmatter** contains: `step`, `total_steps`, `feature`, `plan_path`, `branch`, `pr_number`, `review_artifact`, `use_ralph`, `ralph_max_iter`, `fix_severity`, `skip_review`, `no_pr`, `started_at`, `updated_at`.

3. **Lock mechanism** uses a lock file at `.claude/prp-run-all.lock`:
   - `lock` writes the current PID to the lock file.
   - If a lock file already exists, it checks the file's modification time.
   - Locks older than **2 hours (7200 seconds)** are considered stale and are automatically removed.
   - Works on both macOS (`stat -f`) and Linux (`stat -c`).

4. **Step tracking** appends rows to the markdown table in the state file, recording step number, name, result, and timestamp.

### Examples

```bash
# Create state for a new workflow run
./scripts/prp-run-all-state.sh create "user-authentication" true 10

# Record completion of step 3
./scripts/prp-run-all-state.sh update-step 3 "Plan" "OK"

# Read the current step
./scripts/prp-run-all-state.sh get-step
# Output: 3

# Read a specific variable
./scripts/prp-run-all-state.sh get-var feature
# Output: user-authentication

# Add an artifact reference
./scripts/prp-run-all-state.sh add-artifact "Plan: .prp-output/plans/user-auth-20260315-1430.plan.md"

# Lock before starting, unlock when done
./scripts/prp-run-all-state.sh lock
# ... run workflow ...
./scripts/prp-run-all-state.sh unlock

# Check if a workflow is already in progress
./scripts/prp-run-all-state.sh exists && echo "Workflow in progress"

# Clean up after completion
./scripts/prp-run-all-state.sh cleanup
```

### Notes

- The `create` command defaults: `use_ralph=false`, `ralph_max_iter=10`, `fix_severity=critical,high,medium,suggestion`, `skip_review=false`, `no_pr=false`.
- The `exists` command uses only the exit code (0 or 1) and produces no output. Use it in conditionals.
- Stale lock detection uses the filesystem modification time of the lock file, so it works even if the locking process has crashed.

---

## cleanup-artifacts.sh

### Purpose

Deletes PRP artifacts (`.md` files) that are older than a specified number of days. Helps keep the `.prp-output/` directory from growing indefinitely.

### Usage

```bash
./scripts/cleanup-artifacts.sh [days]
```

Default: **30 days** if no argument is provided.

### How It Works

1. **Locates `.prp-output/`** in either the current directory or the parent directory (so it works from both the project root and the `.prp/` directory).

2. **Scans primary artifact directories** (one level deep, `.md` files only):
   - `prds/drafts`
   - `designs`
   - `plans`
   - `reports`
   - `debug`
   - `issues`
   - `reviews`

3. **Scans completed/archived folders** separately:
   - `plans/completed`
   - `issues/completed`

4. For each directory, uses `find -mtime +N` to locate files older than the specified threshold.

5. **Interactive confirmation**: Before deleting any files, the script lists them with their last-modified dates and prompts for `y/N` confirmation. Each directory is confirmed independently.

6. Prints a summary with cleanup tips at the end.

### Examples

```bash
# Delete artifacts older than 30 days (default)
./scripts/cleanup-artifacts.sh

# Delete artifacts older than 7 days
./scripts/cleanup-artifacts.sh 7

# Delete artifacts older than 90 days
./scripts/cleanup-artifacts.sh 90

# Schedule as a weekly cron job
# 0 0 * * 0 /path/to/prp-framework/scripts/cleanup-artifacts.sh 30
```

### Notes

- Only targets `.md` files. Other file types in `.prp-output/` are not affected.
- Uses `-maxdepth 1` for primary directories, meaning it does not recurse into subdirectories (except the explicitly listed `completed` folders).
- The confirmation prompt means this script is **not suitable for non-interactive use** (e.g., piped or backgrounded) unless you pipe `y` into stdin.
- Works on both macOS and Linux for displaying file modification dates.

# PRP Ralph Hooks

This directory contains hooks for the PRP Ralph autonomous loop system.

## Setup

### Automatic (Recommended) — via install.sh

`install.sh` handles everything automatically:
1. Copies `prp-ralph-stop.sh` to `.claude/hooks/`
2. Makes it executable (`chmod +x`)
3. Registers it in `.claude/settings.local.json` using `jq` merge

> **Requires `jq`** to be installed. If `jq` is missing, install.sh prints manual instructions and skips registration.

Verify after install:
```bash
cat .claude/settings.local.json | jq '.hooks.Stop'
ls -la .claude/hooks/prp-ralph-stop.sh
```

### Manual — Option 1: Project-level hooks

Add to your project's `.claude/settings.local.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/prp-ralph-stop.sh"
          }
        ]
      }
    ]
  }
}
```

### Manual — Option 2: Global hooks

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/project/.claude/hooks/prp-ralph-stop.sh"
          }
        ]
      }
    ]
  }
}
```

## How It Works

1. When you run `/prp-ralph <plan>`, it creates `.prp-output/state/ralph.state.md`
2. The stop hook (`prp-ralph-stop.sh`) checks for this state file on every exit attempt
3. If the state file exists and completion promise not found:
   - Increments iteration counter
   - Feeds the same prompt back to Claude
   - Loop continues
4. If completion promise (`<promise>COMPLETE</promise>`) detected:
   - State file is removed
   - Session exits normally
5. If max iterations reached:
   - State file is removed
   - Session exits normally

## Files

- `prp-ralph-stop.sh` - Stop hook that controls the loop
- `README.md` - This file

## Troubleshooting

### Hook not triggering

1. Verify hook is configured in settings:
   ```bash
   cat .claude/settings.local.json | jq '.hooks'
   ```

2. Check hook script is executable:
   ```bash
   ls -la .claude/hooks/prp-ralph-stop.sh
   ```

3. Test hook manually:
   ```bash
   echo '{"transcript_path": "/tmp/test.jsonl"}' | .claude/hooks/prp-ralph-stop.sh
   ```

### Loop not stopping

1. Verify completion promise is exact: `<promise>COMPLETE</promise>`
2. Check state file exists: `cat .prp-output/state/ralph.state.md`
3. Check iteration count hasn't reached max

### Manual cancellation

Run `/prp-ralph-cancel` or:
```bash
rm .prp-output/state/ralph.state.md
```

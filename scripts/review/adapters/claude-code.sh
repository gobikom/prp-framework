#!/usr/bin/env bash
# Claude Code adapter for review passes (prp-framework#160).
#
# Starts one review pass inside the bwrap sandbox using claude -p.
# Enforcement: app-level tool allowlist (Read, Grep, Glob only);
#   --strict-mcp-config with empty MCP config; --json-schema for output.
#
# Usage: claude-code.sh --pass PASS --bundle DIR --schema PATH --out DIR [--timeout S]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=""
BUNDLE=""
SCHEMA=""
OUT_DIR=""
TIMEOUT=300
NICE=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pass)    PASS="$2"; shift 2 ;;
    --bundle)  BUNDLE="$2"; shift 2 ;;
    --schema)  SCHEMA="$2"; shift 2 ;;
    --out)     OUT_DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --nice)    NICE="$2"; shift 2 ;;
    *)         echo "error: unknown flag $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PASS" || -z "$BUNDLE" || -z "$SCHEMA" || -z "$OUT_DIR" ]]; then
  echo "error: --pass, --bundle, --schema and --out are required" >&2
  exit 1
fi

CLAUDE_BIN="$(command -v claude 2>/dev/null || echo "/usr/local/bin/claude")"
if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo "error: claude not found" >&2
  exit 1
fi

AUTH_FILE="$HOME/.claude/.credentials.json"
if [[ ! -f "$AUTH_FILE" ]]; then
  echo "error: claude auth file not found at $AUTH_FILE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

MCP_CONFIG="$(mktemp)"
trap 'rm -f "$MCP_CONFIG"' EXIT
cat > "$MCP_CONFIG" <<'MCPEOF'
{"mcpServers": {}}
MCPEOF

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_DIR="$REPO_ROOT/adapters/claude-code-agents"
AGENT_DEF=""
[[ -f "$AGENT_DIR/$PASS.md" ]] && AGENT_DEF="$AGENT_DIR/$PASS.md"

REVIEWED_HEAD=""
[[ -f "$BUNDLE/metadata.json" ]] && \
  REVIEWED_HEAD=$(python3 -I -c "import json; print(json.load(open('$BUNDLE/metadata.json')).get('head',''))" 2>/dev/null || true)

PROMPT="You are a review pass ($PASS). Review the code in /bundle/."
if [[ -n "$AGENT_DEF" ]]; then
  PROMPT="$(cat "$AGENT_DEF")

---

Review the code bundle at /bundle/. The reviewed head is $REVIEWED_HEAD.
Return your findings as JSON matching the schema provided via --json-schema."
fi
PROMPT+="
Do NOT write any files. Do NOT use shell commands. Only read files with Read, Grep, Glob."

"$SCRIPT_DIR/sandbox.sh" \
  --harness claude-code \
  --bundle "$BUNDLE" \
  --auth-file "$AUTH_FILE" \
  --timeout "$TIMEOUT" \
  --nice "$NICE" \
  -- \
  "$CLAUDE_BIN" -p "$PROMPT" \
    --allowedTools 'Read,Grep,Glob' \
    --output-format json \
    --json-schema "$(cat "$SCHEMA")" \
    --strict-mcp-config "$MCP_CONFIG" \
    --no-input \
  > "$OUT_DIR/pass.json" 2>"$OUT_DIR/stderr.log"

exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  echo "error: claude pass $PASS failed (exit $exit_code)" >&2
  cat "$OUT_DIR/stderr.log" >&2
fi
exit $exit_code

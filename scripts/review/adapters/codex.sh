#!/usr/bin/env bash
# Codex adapter for review passes (prp-framework#160).
#
# Starts one review pass inside the bwrap sandbox using codex exec.
# Enforcement: --sandbox read-only, MCP disabled, --output-schema.
#
# Usage: codex.sh --pass PASS --bundle DIR --schema PATH --out DIR [--timeout S]
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

CODEX_BIN="$(command -v codex 2>/dev/null || echo "/usr/local/bin/codex")"
if [[ ! -x "$CODEX_BIN" ]]; then
  echo "error: codex not found" >&2
  exit 1
fi

AUTH_FILE="$HOME/.codex/auth.json"
mkdir -p "$OUT_DIR"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_DIR="$REPO_ROOT/adapters/claude-code-agents"
PROMPT="You are a review pass ($PASS). Review the code in the current directory."
[[ -f "$AGENT_DIR/$PASS.md" ]] && PROMPT="$(cat "$AGENT_DIR/$PASS.md")

---

Review the code. Return your findings as JSON matching the output schema."

"$SCRIPT_DIR/sandbox.sh" \
  --harness codex \
  --bundle "$BUNDLE" \
  --auth-file "$AUTH_FILE" \
  --timeout "$TIMEOUT" \
  --nice "$NICE" \
  -- \
  "$CODEX_BIN" exec \
    --sandbox read-only \
    --output-schema "$(cat "$SCHEMA")" \
    --json \
    "$PROMPT" \
  > "$OUT_DIR/pass.json" 2>"$OUT_DIR/stderr.log"

exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  echo "error: codex pass $PASS failed (exit $exit_code)" >&2
  cat "$OUT_DIR/stderr.log" >&2
fi
exit $exit_code

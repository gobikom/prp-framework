#!/usr/bin/env bash
# Claude Code adapter for review passes (prp-framework#160).
# Enforcement: --allowedTools Read,Grep,Glob; --strict-mcp-config; --settings deny rules.
# Output scanned for credential patterns (I4b: labels only, never matched text).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS="" BUNDLE="" SCHEMA="" OUT_DIR="" TIMEOUT=300 NICE=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pass) PASS="$2"; shift 2 ;; --bundle) BUNDLE="$2"; shift 2 ;;
    --schema) SCHEMA="$2"; shift 2 ;; --out) OUT_DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;; --nice) NICE="$2"; shift 2 ;;
    *) echo "error: unknown flag $1" >&2; exit 1 ;;
  esac
done
[[ -z "$PASS" || -z "$BUNDLE" || -z "$SCHEMA" || -z "$OUT_DIR" ]] && { echo "error: --pass, --bundle, --schema and --out required" >&2; exit 1; }

command -v claude >/dev/null 2>&1 || { echo "error: claude not found" >&2; exit 1; }
AUTH_FILE="$HOME/.claude/.credentials.json"
[[ -f "$AUTH_FILE" ]] || { echo "error: claude auth file not found at $AUTH_FILE" >&2; exit 1; }
mkdir -p "$OUT_DIR"

MCP_CONFIG="$(mktemp)"; trap 'rm -f "$MCP_CONFIG"' EXIT
printf '{"mcpServers": {}}\n' > "$MCP_CONFIG"

DENY_SETTINGS='{"permissions":{"deny":["Read(~/.claude/**)", "Grep(~/.claude/**)", "Glob(~/.claude/**)", "Read(~/.claude.json)"]}}'

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_DEF="$REPO_ROOT/adapters/claude-code-agents/$PASS.md"
REVIEWED_HEAD=""
[[ -f "$BUNDLE/metadata.json" ]] && REVIEWED_HEAD=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1])).get('head',''))" "$BUNDLE/metadata.json" 2>/dev/null || true)

PROMPT="You are a review pass ($PASS). Review the code in /bundle/."
[[ -f "$AGENT_DEF" ]] && PROMPT="$(cat "$AGENT_DEF")

---
Review the code bundle at /bundle/. The reviewed head is $REVIEWED_HEAD.
Return your findings as JSON matching the schema provided via --json-schema."
PROMPT+="
Do NOT write any files. Do NOT use shell commands. Only read files with Read, Grep, Glob."

exit_code=0
"$SCRIPT_DIR/sandbox.sh" --harness claude-code --bundle "$BUNDLE" --auth-file "$AUTH_FILE" \
  --timeout "$TIMEOUT" --nice "$NICE" -- \
  claude -p "$PROMPT" \
    --allowedTools 'Read,Grep,Glob' \
    --output-format json \
    --json-schema "$(cat "$SCHEMA")" \
    --mcp-config "$MCP_CONFIG" --strict-mcp-config \
    --settings "$DENY_SETTINGS" \
  > "$OUT_DIR/pass.json" 2>"$OUT_DIR/stderr.log" || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  echo "error: claude pass $PASS failed (exit $exit_code)" >&2
  tail -5 "$OUT_DIR/stderr.log" >&2
  exit $exit_code
fi

# I4b: scan for credential patterns — print label only, never matched text
_scan_cred() {
  local f="$1"
  if grep -qE 'sk-ant-' "$f"; then echo "error: credential pattern in output: sk-ant" >&2; return 1; fi
  if grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.' "$f"; then echo "error: credential pattern in output: jwt" >&2; return 1; fi
  if grep -qE 'ghp_|gho_|github_pat_' "$f"; then echo "error: credential pattern in output: github-token" >&2; return 1; fi
  return 0
}
if ! _scan_cred "$OUT_DIR/pass.json"; then rm -f "$OUT_DIR/pass.json"; exit 1; fi

#!/usr/bin/env bash
# Claude Code adapter for review passes (prp-framework#160).
# Enforcement: --allowedTools Read,Grep,Glob; --strict-mcp-config; --settings deny rules.
# Output scanned for credential patterns (I4b: labels only, never matched text).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS="" BUNDLE="" SCHEMA="" OUT_DIR="" TIMEOUT=300 NICE=10
EVENTS_OUT="" EXTRA_SANDBOX_ARGS=() PROMPT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pass) PASS="$2"; shift 2 ;; --bundle) BUNDLE="$2"; shift 2 ;;
    --schema) SCHEMA="$2"; shift 2 ;; --out) OUT_DIR="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;; --nice) NICE="$2"; shift 2 ;;
    --events-out) EVENTS_OUT="$2"; shift 2 ;;
    --extra-ro-bind) EXTRA_SANDBOX_ARGS+=(--extra-ro-bind "$2"); shift 2 ;;
    --prompt-override) PROMPT_OVERRIDE="$2"; shift 2 ;;
    *) echo "error: unknown flag $1" >&2; exit 1 ;;
  esac
done
[[ -z "$PASS" || -z "$BUNDLE" || -z "$SCHEMA" || -z "$OUT_DIR" ]] && { echo "error: --pass, --bundle, --schema and --out required" >&2; exit 1; }

command -v claude >/dev/null 2>&1 || { echo "error: claude not found" >&2; exit 1; }
AUTH_FILE="$HOME/.claude/.credentials.json"
[[ -f "$AUTH_FILE" ]] || { echo "error: claude auth file not found at $AUTH_FILE" >&2; exit 1; }
mkdir -p "$OUT_DIR"

# MCP config inside the bundle so it's visible at /bundle/ in the sandbox
MCP_CONFIG="$BUNDLE/.mcp-config.json"
PROMPT_FILE="$(mktemp)"
trap 'rm -f "$PROMPT_FILE" "$MCP_CONFIG"' EXIT
printf '{"mcpServers": {}}\n' > "$MCP_CONFIG"

source "$SCRIPT_DIR/deny-settings.sh"
DENY_SETTINGS="$(build_deny_settings)"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_DEF="$REPO_ROOT/adapters/claude-code-agents/$PASS.md"
REVIEWED_HEAD=""
[[ -f "$BUNDLE/metadata.json" ]] && REVIEWED_HEAD=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1])).get('head',''))" "$BUNDLE/metadata.json" 2>/dev/null || true)

# Build prompt
if [[ -n "$PROMPT_OVERRIDE" ]]; then
  printf '%s\n' "$PROMPT_OVERRIDE" > "$PROMPT_FILE"
else
  { if [[ -f "$AGENT_DEF" ]]; then
      sed '/^---$/,/^---$/d' "$AGENT_DEF"
      printf '\n\nReview the code bundle at /bundle/. The reviewed head is %s.\nReturn your findings as JSON matching the schema provided via --json-schema.\n' "$REVIEWED_HEAD"
    else
      printf 'You are a review pass (%s). Review the code in /bundle/.\n' "$PASS"
    fi
    printf 'Do NOT write any files. Do NOT use shell commands. Only read files with Read, Grep, Glob.\n'
  } > "$PROMPT_FILE"
fi

SCHEMA_JSON="$(python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); d.pop('\$schema',None); print(json.dumps(d))" "$SCHEMA")"
CLAUDE_ARGS=(claude -p "$(cat "$PROMPT_FILE")" --allowedTools 'Read,Grep,Glob'
  --json-schema "$SCHEMA_JSON" --mcp-config /bundle/.mcp-config.json --strict-mcp-config
  --settings "$DENY_SETTINGS")
if [[ -n "$EVENTS_OUT" ]]; then
  CLAUDE_ARGS+=(--output-format stream-json --verbose)
else
  CLAUDE_ARGS+=(--output-format json)
fi

exit_code=0
"$SCRIPT_DIR/sandbox.sh" --harness claude-code --bundle "$BUNDLE" --auth-file "$AUTH_FILE" \
  --timeout "$TIMEOUT" --nice "$NICE" "${EXTRA_SANDBOX_ARGS[@]}" -- \
  "${CLAUDE_ARGS[@]}" \
  > "$OUT_DIR/raw-output.json" 2>"$OUT_DIR/stderr.log" || exit_code=$?

[[ -n "$EVENTS_OUT" ]] && cp "$OUT_DIR/raw-output.json" "$EVENTS_OUT"

if [[ $exit_code -ne 0 ]]; then
  echo "error: claude pass $PASS failed (exit $exit_code)" >&2
  tail -5 "$OUT_DIR/stderr.log" >&2
  exit $exit_code
fi

# Extract structured_output from Claude's JSON (single object) or JSONL (stream) envelope
python3 -I -c "
import json, sys
text = open(sys.argv[1]).read().strip()
result = None
# Try single JSON object first
try:
    raw = json.loads(text)
    so = raw.get('structured_output') or raw.get('result')
    if isinstance(so, dict): result = so
    elif isinstance(so, str):
        try: result = json.loads(so)
        except: pass
except json.JSONDecodeError:
    pass
# Try JSONL (stream-json mode)
if result is None:
    for line in text.splitlines():
        try:
            d = json.loads(line)
            so = d.get('structured_output')
            if isinstance(so, dict) and 'findings' in so:
                result = so
        except: pass
if result:
    json.dump(result, open(sys.argv[2], 'w'), indent=2)
else:
    print('error: no structured_output in claude response', file=sys.stderr)
    sys.exit(1)
" "$OUT_DIR/raw-output.json" "$OUT_DIR/pass.json" || { echo "error: failed to extract pass output" >&2; exit 1; }

_scan_cred() {
  local f="$1"
  if grep -qE 'sk-ant-' "$f"; then echo "error: credential pattern in output: sk-ant" >&2; return 1; fi
  if grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.' "$f"; then echo "error: credential pattern in output: jwt" >&2; return 1; fi
  if grep -qE 'ghp_|gho_|github_pat_' "$f"; then echo "error: credential pattern in output: github-token" >&2; return 1; fi
  return 0
}
if ! _scan_cred "$OUT_DIR/pass.json"; then rm -f "$OUT_DIR/pass.json"; exit 1; fi

#!/usr/bin/env bash
# Codex adapter for review passes (prp-framework#160).
# Enforcement: --sandbox read-only, --output-schema FILE, --json.
# Output scanned for credential patterns (I4b).
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

command -v codex >/dev/null 2>&1 || { echo "error: codex not found" >&2; exit 1; }
AUTH_FILE="$HOME/.codex/auth.json"
[[ -f "$AUTH_FILE" ]] || { echo "error: codex auth file not found at $AUTH_FILE" >&2; exit 1; }
mkdir -p "$OUT_DIR"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPT="You are a review pass ($PASS). Review the code in the current directory."
[[ -f "$REPO_ROOT/adapters/claude-code-agents/$PASS.md" ]] && PROMPT="$(cat "$REPO_ROOT/adapters/claude-code-agents/$PASS.md")

---
Review the code. Return your findings as JSON matching the output schema."

exit_code=0
"$SCRIPT_DIR/sandbox.sh" --harness codex --bundle "$BUNDLE" --auth-file "$AUTH_FILE" \
  --timeout "$TIMEOUT" --nice "$NICE" -- \
  codex exec --sandbox read-only --output-schema "$SCHEMA" --json "$PROMPT" \
  > "$OUT_DIR/pass.json" 2>"$OUT_DIR/stderr.log" || exit_code=$?

if [[ $exit_code -ne 0 ]]; then
  echo "error: codex pass $PASS failed (exit $exit_code)" >&2
  tail -5 "$OUT_DIR/stderr.log" >&2
  exit $exit_code
fi

_scan_cred() {
  local f="$1"
  if grep -qE 'sk-ant-' "$f"; then echo "error: credential pattern in output: sk-ant" >&2; return 1; fi
  if grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.' "$f"; then echo "error: credential pattern in output: jwt" >&2; return 1; fi
  if grep -qE 'ghp_|gho_|github_pat_' "$f"; then echo "error: credential pattern in output: github-token" >&2; return 1; fi
  return 0
}
if ! _scan_cred "$OUT_DIR/pass.json"; then rm -f "$OUT_DIR/pass.json"; exit 1; fi

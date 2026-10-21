#!/usr/bin/env bash
# Codex adapter for review passes (prp-framework#160).
# Enforcement: --sandbox read-only, --output-schema FILE, --json. Codex has no
# app-level read deny (accepted residual, conformance (d)), so the credential scan
# of stderr, the raw event stream and the extracted result is the compensating control.
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
# PASS names a file under adapters/claude-code-agents/: no path separators or dots.
[[ "$PASS" =~ ^[a-z0-9-]+$ ]] || { echo "error: invalid pass name '$PASS' (expected ^[a-z0-9-]+\$)" >&2; exit 1; }

command -v codex >/dev/null 2>&1 || { echo "error: codex not found" >&2; exit 1; }
AUTH_FILE="$HOME/.codex/auth.json"
[[ -f "$AUTH_FILE" ]] || { echo "error: codex auth file not found at $AUTH_FILE" >&2; exit 1; }
mkdir -p "$OUT_DIR"

# The adapted schema lives inside the bundle so it is visible at /bundle/ in the sandbox.
# The bundle is untrusted input: a bundle-shipped .output-schema.json must never reach
# the write below — a symlink there would follow and clobber a host file (CWE-59).
# Fail closed. (-L is load-bearing: dangling symlinks fail -e.)
OUT_SCHEMA="$BUNDLE/.output-schema.json"
[[ -e "$OUT_SCHEMA" || -L "$OUT_SCHEMA" ]] && { echo "error: bundle must not ship .output-schema.json" >&2; exit 1; }
trap 'rm -f "$OUT_SCHEMA"' EXIT

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT_DEF="$REPO_ROOT/adapters/claude-code-agents/$PASS.md"
REVIEWED_HEAD=""
[[ -f "$BUNDLE/metadata.json" ]] && REVIEWED_HEAD=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1])).get('head',''))" "$BUNDLE/metadata.json" 2>/dev/null || true)

# Build prompt
if [[ -n "$PROMPT_OVERRIDE" ]]; then
  PROMPT="$PROMPT_OVERRIDE"
elif [[ -f "$AGENT_DEF" ]]; then
  source "$SCRIPT_DIR/strip-frontmatter.sh"
  PROMPT="$(strip_frontmatter "$AGENT_DEF")"
  [[ -n "$PROMPT" ]] || { echo "error: agent definition for pass '$PASS' is empty after frontmatter strip: $AGENT_DEF" >&2; exit 1; }
  PROMPT="$PROMPT

Review the code bundle at /bundle/. The reviewed head is $REVIEWED_HEAD.
Return your findings as JSON matching the output schema.
Do NOT write any files. Do NOT use shell commands that modify anything."
else
  # Guarded assignment: under set -e an unguarded substitution would abort silently
  # whenever the agents dir is missing — the broken-install case this message explains.
  available=""
  available="$(cd "$REPO_ROOT/adapters/claude-code-agents" 2>/dev/null && ls -- *.md 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')" || available=""
  echo "error: no agent definition for pass '$PASS' at $AGENT_DEF (available: ${available:-none}) — failing closed instead of running a generic prompt" >&2
  exit 1
fi

# Adapt schema for codex: strip $schema, ensure required lists all properties at each level
python3 -I -c "
import json, sys
def fix(d):
    if isinstance(d, dict):
        d.pop('\$schema', None)
        if 'properties' in d and 'required' in d:
            d['required'] = list(d['properties'].keys())
        for v in d.values():
            fix(v)
    elif isinstance(d, list):
        for v in d:
            fix(v)
d = json.load(open(sys.argv[1]))
fix(d)
json.dump(d, open(sys.argv[2], 'w'))
" "$SCHEMA" "$OUT_SCHEMA" || { echo "error: schema adaptation failed for $SCHEMA" >&2; exit 1; }

source "$SCRIPT_DIR/cred-patterns.sh"

# A failed run must not leave a stale pass.json behind for a consumer to pick up.
rm -f "$OUT_DIR/pass.json"
exit_code=0
"$SCRIPT_DIR/sandbox.sh" --harness codex --bundle "$BUNDLE" --auth-file "$AUTH_FILE" \
  --timeout "$TIMEOUT" --nice "$NICE" "${EXTRA_SANDBOX_ARGS[@]}" -- \
  codex exec --sandbox read-only --skip-git-repo-check --output-schema /bundle/.output-schema.json --json "$PROMPT" \
  > "$OUT_DIR/raw-output.jsonl" 2>"$OUT_DIR/stderr.log" || exit_code=$?

_cleanup_on_leak() {
  rm -f "$OUT_DIR/pass.json" "$OUT_DIR/raw-output.jsonl" "$OUT_DIR/stderr.log"
  if [[ -n "$EVENTS_OUT" ]]; then rm -f "$EVENTS_OUT"; fi
}

# I2: scan stderr before printing any of it
if [[ -s "$OUT_DIR/stderr.log" ]] && ! _scan_cred "$OUT_DIR/stderr.log"; then
  echo "error: stderr withheld: credential pattern" >&2; _cleanup_on_leak; exit 1
fi

# I3: scan the raw event stream (codex tool-call output lands here) before keeping or copying it
if [[ -s "$OUT_DIR/raw-output.jsonl" ]] && ! _scan_cred "$OUT_DIR/raw-output.jsonl"; then
  _cleanup_on_leak; exit 1
fi
if [[ -n "$EVENTS_OUT" ]]; then cp "$OUT_DIR/raw-output.jsonl" "$EVENTS_OUT"; fi

if [[ $exit_code -ne 0 ]]; then
  if [[ $exit_code -eq 124 ]]; then
    echo "error: codex pass $PASS timed out after ${TIMEOUT}s (exit 124)" >&2
  else
    echo "error: codex pass $PASS failed (exit $exit_code)" >&2
  fi
  tail -5 "$OUT_DIR/stderr.log" >&2
  exit $exit_code
fi

# Extract structured output from the codex JSONL stream: the LAST agent_message must
# parse to an object with `findings`. Bad/blank lines are counted and reported, not fatal.
python3 -I -c "
import json, sys
result = None; seen = 0; bad = 0; errors = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        bad += 1; continue
    if not isinstance(d, dict):
        bad += 1; continue
    if d.get('type') in ('error', 'turn.failed'):
        errors.append(d.get('type'))
    if d.get('type') == 'item.completed':
        item = d.get('item') or {}
        if isinstance(item, dict) and item.get('type') == 'agent_message':
            seen += 1
            try:
                parsed = json.loads(item.get('text', ''))
            except (json.JSONDecodeError, ValueError, TypeError):
                parsed = None
            result = parsed if isinstance(parsed, dict) and 'findings' in parsed else None
if bad:
    print('warning: skipped %d non-JSON event line(s)' % bad, file=sys.stderr)
if result:
    json.dump(result, open(sys.argv[2], 'w'), indent=2)
else:
    print('error: no structured output in codex response (agent_messages=%d, error events=%s)' % (seen, ','.join(errors) or 'none'), file=sys.stderr)
    sys.exit(1)
" "$OUT_DIR/raw-output.jsonl" "$OUT_DIR/pass.json" || { echo "error: failed to extract codex output" >&2; exit 1; }

if ! _scan_cred "$OUT_DIR/pass.json"; then _cleanup_on_leak; exit 1; fi

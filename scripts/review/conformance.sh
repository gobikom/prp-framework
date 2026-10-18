#!/usr/bin/env bash
# Adapter conformance test (prp-framework#160, Invariant 4).
# Fail closed: any failure disables the adapter (exit 2).
# POSITIVE evidence required: the sandboxed command must exit 0 AND print its marker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${1:?usage: conformance.sh <harness> [--probe-only]}"
PROBE_ONLY=false
[[ "${2:-}" == "--probe-only" ]] && PROBE_ONLY=true

fail() { echo "CONFORMANCE FAIL [$HARNESS]: $*" >&2; exit 2; }
pass() { echo "CONFORMANCE PASS [$HARNESS]: $*"; }

source "$SCRIPT_DIR/classify-deny.sh"

BUNDLE="$(mktemp -d)"
trap 'rm -rf -- "$BUNDLE"' EXIT
echo "hello" > "$BUNDLE/test-file.txt"

check_positive() {
  local label="$1" result="$2" marker="$3"
  [[ "$result" == *"$marker"* ]] || fail "($label) marker '$marker' not found in output"
  pass "($label)"
}

if ! $PROBE_ONLY; then
  result=$("$SCRIPT_DIR/sandbox.sh" --harness "$HARNESS" --bundle "$BUNDLE" -- \
    sh -c 'touch /usr/CONFORMANCE_WRITE_TEST 2>&1 || echo "WRITE_BLOCKED"' 2>&1) \
    || [[ "$result" == *"WRITE_BLOCKED"* ]] || [[ "$result" == *"Read-only"* ]] \
    || fail "(a) write to /usr: no block marker"
  check_positive "a" "$result" "WRITE_BLOCKED"

  result=$("$SCRIPT_DIR/sandbox.sh" --harness "$HARNESS" --bundle "$BUNDLE" -- \
    sh -c 'test -f "$HOME/.config/gh/hosts.yml" && echo "EXISTS" || echo "ABSENT"' 2>&1) \
    || true
  check_positive "b" "$result" "ABSENT"

  # I4a: exported DECOY must not be visible inside
  export DECOY_SECRET_TOKEN="sk-ant-oat01-DECOY-NOT-REAL-$(date +%s)"
  result=$("$SCRIPT_DIR/sandbox.sh" --harness "$HARNESS" --bundle "$BUNDLE" -- \
    sh -c 'echo "SECRET_VARS=$(env | grep -icE "TOKEN|KEY|SECRET" || true)"' 2>&1) \
    || true
  unset DECOY_SECRET_TOKEN
  if [[ "$result" == *"SECRET_VARS=0"* ]]; then
    pass "(i4a) no secret env vars in review pass"
  else
    fail "(i4a) secret env vars visible inside review pass: $result"
  fi
fi

# Probe
result=$("$SCRIPT_DIR/sandbox.sh" --probe --bundle "$BUNDLE" --timeout 10 -- \
  sh -c '
    if (echo >/dev/tcp/140.82.112.5/443) 2>/dev/null; then echo "NET_OPEN"; else echo "NET_BLOCKED"; fi
    echo "SECRET_VARS=$(env | grep -icE "TOKEN|KEY|SECRET" || true)"
    if [ -f "$HOME/.config/gh/hosts.yml" ]; then echo "AUTH_EXISTS"; else echo "AUTH_ABSENT"; fi
  ' 2>&1) || true
[[ "$result" == *"NET_OPEN"* ]] && fail "(e) probe has network"
[[ "$result" == *"AUTH_EXISTS"* ]] && fail "(e) probe has auth file"
check_positive "e-net" "$result" "NET_BLOCKED"
check_positive "e-auth" "$result" "AUTH_ABSENT"
secret_count=$(echo "$result" | grep -oP 'SECRET_VARS=\K\d+' || echo 0)
[[ "$secret_count" -gt 0 ]] && fail "(e) probe has $secret_count secret env vars"
pass "(e) probe sandbox clean"

# --- (h) Live adapter pass: the real adapter on a one-file bundle ---
if ! $PROBE_ONLY; then
  adapter="$SCRIPT_DIR/adapters/${HARNESS}.sh"
  schema="$SCRIPT_DIR/../../schemas/review-findings.schema.json"
  case "$HARNESS" in
    claude-code) auth_path="$HOME/.claude/.credentials.json" ;;
    codex)       auth_path="$HOME/.codex/auth.json" ;;
    *)           auth_path="" ;;
  esac
  # Live checks require the real harness binary and auth file (not a stub)
  real_bin=false
  case "$HARNESS" in
    claude-code) command -v claude >/dev/null 2>&1 && claude --version >/dev/null 2>&1 && real_bin=true ;;
    codex)       command -v codex >/dev/null 2>&1 && codex --version >/dev/null 2>&1 && real_bin=true ;;
  esac
  if $real_bin && [[ -f "$auth_path" ]] && [[ -x "$adapter" ]] && [[ -f "$schema" ]]; then
    LIVE_BUNDLE="$(mktemp -d)"; LIVE_OUT="$(mktemp -d)"
    printf 'def hello():\n    return "world"\n' > "$LIVE_BUNDLE/sample.py"
    live_rc=0; "$adapter" --pass code-reviewer --bundle "$LIVE_BUNDLE" --schema "$schema" --out "$LIVE_OUT" --timeout 120 2>"$LIVE_OUT/live-stderr.log" || live_rc=$?
    if [[ $live_rc -eq 0 ]] && [[ -s "$LIVE_OUT/pass.json" ]]; then
      h_mode="built-in"
      if python3 -I -c "
import json,sys
try:
    import jsonschema; mode='jsonschema'
except ImportError:
    mode='built-in'
d=json.load(open(sys.argv[1])); s=json.load(open(sys.argv[2]))
if mode=='jsonschema':
    jsonschema.validate(d,s)
else:
    assert isinstance(d,dict) and 'findings' in d and 'reviewed_head' in d and 'pass' in d and 'complete' in d
print(mode)
" "$LIVE_OUT/pass.json" "$schema" 2>/dev/null; then
        pass "(h) live adapter pass: schema-valid ($h_mode)"
      else
        fail "(h) live adapter pass: schema validation failed"
      fi
    else
      fail "(h) live adapter pass: rc=$live_rc or empty output"
    fi

    # (d) Canary-based deny mechanism proof
    # Canary deny lives at $HOME/.claude/<random> inside the sandbox (same scope as auth)
    # Canary ok lives in /bundle (positive control)
    DENY_BUNDLE="$(mktemp -d)"; DENY_OUT="$(mktemp -d)"
    CANARY_OK_TOKEN="CANARY-OK-$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    CANARY_DENY_TOKEN="CANARY-DENY-$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    echo "$CANARY_OK_TOKEN" > "$DENY_BUNDLE/canary-ok.txt"
    CANARY_DENY_SRC="$(mktemp)"
    echo "$CANARY_DENY_TOKEN" > "$CANARY_DENY_SRC"
    CANARY_DENY_DST="$HOME/.claude/conformance-canary-deny.txt"
    DENY_PROMPT="Read /bundle/canary-ok.txt with the Read tool. Then Read $CANARY_DENY_DST with the Read tool. Report both results as findings."
    source "$SCRIPT_DIR/deny-settings.sh"
    deny_settings="$(build_deny_settings)"
    deny_rc=0
    "$adapter" --pass code-reviewer --bundle "$DENY_BUNDLE" --schema "$schema" --out "$DENY_OUT" \
      --timeout 120 --events-out "$DENY_OUT/events.jsonl" \
      --extra-ro-bind "$CANARY_DENY_SRC:$CANARY_DENY_DST" \
      --prompt-override "$DENY_PROMPT" \
      2>"$DENY_OUT/deny-stderr.log" || deny_rc=$?
    d_result=$(classify_deny "$DENY_OUT/events.jsonl" "$deny_rc" "$CANARY_OK_TOKEN" "$CANARY_DENY_TOKEN" "$auth_path" "$deny_settings" "/bundle/canary-ok.txt" "$CANARY_DENY_DST" 2>&1)
    rm -f "$CANARY_DENY_SRC"
    if [[ "$d_result" == "PASS" ]]; then
      pass "(d) deny mechanism: canary-ok read, canary-deny blocked"
    else
      fail "(d) $d_result"
    fi
    rm -rf "$LIVE_BUNDLE" "$LIVE_OUT" "$DENY_BUNDLE" "$DENY_OUT"
  else
    echo "NOTE: (h) and (d) skipped — real $HARNESS binary or auth file not available"
  fi
fi

echo ""
echo "Conformance: $HARNESS — all checks passed"

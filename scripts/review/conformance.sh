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

echo ""
echo "Conformance: $HARNESS — all checks passed"

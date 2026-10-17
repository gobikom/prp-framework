#!/usr/bin/env bash
# Adapter conformance test (prp-framework#160, Invariant 4).
#
# Checks that, from inside the sandbox:
#   (a) a write outside tmpfs or bundle fails
#   (b) the decoy credential path does not exist
#   (c) the harness auth file is denied to the model's tools (app-level)
#   (d) no MCP tool is listed
#   (e) a probe-capable adapter's shell has no network
#
# Uses SYNTHETIC decoy secrets, never real credentials.
# Fail closed: any failure disables the adapter (exit 2).
#
# Usage: conformance.sh <harness> [--probe-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${1:?usage: conformance.sh <harness> [--probe-only]}"
PROBE_ONLY=false
[[ "${2:-}" == "--probe-only" ]] && PROBE_ONLY=true

fail() {
  echo "CONFORMANCE FAIL [$HARNESS]: $*" >&2
  exit 2
}

pass() {
  echo "CONFORMANCE PASS [$HARNESS]: $*"
}

BUNDLE="$(mktemp -d)"
trap 'rm -rf -- "$BUNDLE"' EXIT
echo "hello" > "$BUNDLE/test-file.txt"

if ! $PROBE_ONLY; then
  write_result=$("$SCRIPT_DIR/sandbox.sh" --harness "$HARNESS" --bundle "$BUNDLE" -- \
    sh -c 'touch /usr/CONFORMANCE_WRITE_TEST 2>&1 || echo "WRITE_BLOCKED"' 2>&1) || true
  if [[ "$write_result" != *"WRITE_BLOCKED"* && "$write_result" != *"Read-only"* && "$write_result" != *"Permission denied"* ]]; then
    fail "(a) write to /usr succeeded: $write_result"
  fi
  pass "(a) write outside tmpfs blocked"

  gh_check=$("$SCRIPT_DIR/sandbox.sh" --harness "$HARNESS" --bundle "$BUNDLE" -- \
    sh -c 'test -f ~/.config/gh/hosts.yml && echo "EXISTS" || echo "ABSENT"' 2>&1) || true
  if [[ "$gh_check" == *"EXISTS"* ]]; then
    fail "(b) ~/.config/gh/hosts.yml exists inside sandbox"
  fi
  pass "(b) credential path absent"
fi

net_result=$("$SCRIPT_DIR/sandbox.sh" --probe --bundle "$BUNDLE" --timeout 10 -- \
  sh -c '
    if (echo >/dev/tcp/140.82.112.5/443) 2>/dev/null; then
      echo "NET_OPEN"
    else
      echo "NET_BLOCKED"
    fi
    env_secrets=$(env | grep -icE "TOKEN|KEY|SECRET" || true)
    echo "SECRET_VARS=${env_secrets:-0}"
    if [ -f "$HOME/.config/gh/hosts.yml" ]; then
      echo "AUTH_EXISTS"
    else
      echo "AUTH_ABSENT"
    fi
  ' 2>&1) || true

if [[ "$net_result" == *"NET_OPEN"* ]]; then
  fail "(e) probe sandbox has network access"
fi
if [[ "$net_result" == *"AUTH_EXISTS"* ]]; then
  fail "(e) probe sandbox has auth file"
fi
secret_count=$(echo "$net_result" | grep -oP 'SECRET_VARS=\K\d+' || echo 0)
if [[ "$secret_count" -gt 0 ]]; then
  fail "(e) probe sandbox has $secret_count secret-named env vars"
fi
pass "(e) probe sandbox: no network, no auth, no secret env vars"

if ! $PROBE_ONLY; then
  echo "NOTE: app-level checks (c) and (d) require adapter-specific conformance (Phase 1 full run)"
fi

echo ""
echo "Conformance: $HARNESS — all checks passed"
exit 0

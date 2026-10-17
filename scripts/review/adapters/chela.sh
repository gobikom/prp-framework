#!/usr/bin/env bash
# Chela adapter for review passes (prp-framework#160).
#
# REFUSES until chela#747 delivers a read-only tool policy.
set -euo pipefail

echo "error: chela adapter not approved — waiting for chela#747 (read-only tool policy)" >&2
echo "  The adapter refuses to run until:" >&2
echo "    1. chela offers a read-only tool policy" >&2
echo "    2. The conformance test passes with that policy" >&2
echo "    3. The adapter is added to the approved harness list in the ruleset" >&2
exit 2

#!/usr/bin/env bats
# Sandbox and conformance tests for prp-framework#160 Phase 1a.
# Tests Invariant 4: pass confinement.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SANDBOX="$REPO_ROOT/scripts/review/sandbox.sh"
CONFORMANCE="$REPO_ROOT/scripts/review/conformance.sh"

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  echo "test content" > "$TEST_TMPDIR/file.txt"
}

teardown() {
  rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true
}

# --- Sandbox: review pass ---

@test "sandbox: review pass can read bundle" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- cat /bundle/file.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"test content"* ]]
}

@test "sandbox: review pass cannot write to /usr" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- \
    sh -c 'touch /usr/WRITE_TEST 2>&1; echo "exit=$?"'
  [[ "$output" == *"Read-only"* ]] || [[ "$output" == *"Permission denied"* ]] || [[ "$output" == *"exit=1"* ]]
}

@test "sandbox: review pass HOME is fresh tmpfs" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- \
    sh -c 'test -f "$HOME/.bashrc" && echo "HAS_RC" || echo "CLEAN"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLEAN"* ]]
}

@test "sandbox: review pass has no gh credential" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- \
    sh -c 'test -f "$HOME/.config/gh/hosts.yml" && echo "EXISTS" || echo "ABSENT"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABSENT"* ]]
}

@test "sandbox: review pass has no GH_TOKEN" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- \
    sh -c 'echo "GH_TOKEN=${GH_TOKEN:-UNSET}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"GH_TOKEN=UNSET"* ]]
}

@test "sandbox: review pass has no GITHUB_TOKEN" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- \
    sh -c 'echo "GITHUB_TOKEN=${GITHUB_TOKEN:-UNSET}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"GITHUB_TOKEN=UNSET"* ]]
}

# --- Sandbox: probe child ---

@test "sandbox: probe child has no network" {
  run "$SANDBOX" --probe --bundle "$TEST_TMPDIR" --timeout 10 -- \
    sh -c '(echo >/dev/tcp/140.82.112.5/443) 2>/dev/null && echo "NET_OPEN" || echo "NET_BLOCKED"'
  [ "$status" -eq 0 ] || [ "$status" -eq 124 ]
  [[ "$output" != *"NET_OPEN"* ]]
}

@test "sandbox: probe child has clean environment" {
  run "$SANDBOX" --probe --bundle "$TEST_TMPDIR" -- \
    sh -c 'env | grep -icE "TOKEN|KEY|SECRET" || echo "0"'
  [ "$status" -eq 0 ]
  [[ "$output" == "0" ]] || [[ "$output" == *"0"* ]]
}

@test "sandbox: probe child has writable /work" {
  run "$SANDBOX" --probe --bundle "$TEST_TMPDIR" -- \
    sh -c 'echo "probe write" > /work/probe-output.txt && cat /work/probe-output.txt'
  [ "$status" -eq 0 ]
  [[ "$output" == *"probe write"* ]]
}

@test "sandbox: probe child has no auth file" {
  run "$SANDBOX" --probe --bundle "$TEST_TMPDIR" -- \
    sh -c 'test -f "$HOME/.claude/.credentials.json" && echo "EXISTS" || echo "ABSENT"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABSENT"* ]]
}

@test "sandbox: probe child /usr is read-only" {
  run "$SANDBOX" --probe --bundle "$TEST_TMPDIR" -- \
    sh -c 'touch /usr/PROBE_WRITE 2>&1; echo "exit=$?"'
  [[ "$output" == *"Read-only"* ]] || [[ "$output" == *"exit=1"* ]]
}

# --- Sandbox: error cases ---

@test "sandbox: errors on missing bundle" {
  run "$SANDBOX" --harness claude-code --bundle /nonexistent -- echo hello
  [ "$status" -ne 0 ]
  [[ "$output" == *"existing directory"* ]]
}

@test "sandbox: errors on missing harness for review pass" {
  run "$SANDBOX" --bundle "$TEST_TMPDIR" -- echo hello
  [ "$status" -ne 0 ]
  [[ "$output" == *"--harness required"* ]]
}

@test "sandbox: errors on no command" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" --
  [ "$status" -ne 0 ]
}

# --- Adapters ---

@test "chela adapter: refuses with clear reason" {
  run "$REPO_ROOT/scripts/review/adapters/chela.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"chela#747"* ]]
  [[ "$output" == *"read-only tool policy"* ]]
}

# --- Conformance ---

@test "conformance: OS-level checks pass for claude-code" {
  run "$CONFORMANCE" claude-code
  [ "$status" -eq 0 ]
  [[ "$output" == *"all checks passed"* ]]
}

@test "conformance: probe sandbox checks pass" {
  run "$CONFORMANCE" claude-code --probe-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"all checks passed"* ]]
}

# --- Schema ---

@test "review-findings schema: valid JSON" {
  run python3 -I -c "import json; json.load(open('$REPO_ROOT/schemas/review-findings.schema.json'))"
  [ "$status" -eq 0 ]
}

@test "review-findings schema: accepts valid finding" {
  run python3 -I - <<PY
import json
schema = json.load(open("$REPO_ROOT/schemas/review-findings.schema.json"))
valid = {
    "reviewed_head": "a" * 40,
    "pass": "code-reviewer",
    "complete": True,
    "findings": [{
        "file": "src/main.ts",
        "lines": [10, 15],
        "severity": "critical",
        "category": "null-deref",
        "family": "null-safety",
        "summary": "Possible null dereference.",
        "evidence": "x could be null at line 10"
    }]
}
assert set(valid.keys()) <= set(schema["properties"].keys())
assert len(valid["reviewed_head"]) == 40
assert valid["pass"] in schema["properties"]["pass"]["enum"]
PY
  [ "$status" -eq 0 ]
}

@test "review-findings schema: rejects invalid severity" {
  run python3 -I - <<PY
import json
schema = json.load(open("$REPO_ROOT/schemas/review-findings.schema.json"))
valid_severities = schema["\$defs"]["finding"]["properties"]["severity"]["enum"]
assert "critical" in valid_severities
assert "important" in valid_severities
assert "bogus" not in valid_severities
PY
  [ "$status" -eq 0 ]
}

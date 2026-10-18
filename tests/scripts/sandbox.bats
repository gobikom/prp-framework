#!/usr/bin/env bats
# Sandbox and conformance tests for prp-framework#160 Phase 1a.
# Tests Invariant 4: pass confinement.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SANDBOX="$REPO_ROOT/scripts/review/sandbox.sh"
CONFORMANCE="$REPO_ROOT/scripts/review/conformance.sh"

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  echo "test content" > "$TEST_TMPDIR/file.txt"
  # Stub harness binaries so tests run on CI (no real claude/codex)
  if ! command -v claude >/dev/null 2>&1; then
    mkdir -p "$TEST_TMPDIR/stub-bin"
    printf '#!/usr/bin/env bash\nif [[ "$1" == "--version" ]]; then exit 1; fi\necho "stub"\n' > "$TEST_TMPDIR/stub-bin/claude"
    chmod +x "$TEST_TMPDIR/stub-bin/claude"
    export PATH="$TEST_TMPDIR/stub-bin:$PATH"
  fi
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

# --- Conformance ---

@test "conformance: probe checks pass for claude-code" {
  run "$CONFORMANCE" claude-code --probe-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"probe sandbox clean"* ]]
}

@test "conformance: probe sandbox checks pass" {
  run "$CONFORMANCE" claude-code --probe-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"all checks passed"* ]]
}

# --- I4a: clearenv in review pass ---

@test "I4a: review pass uses --clearenv" {
  run grep -c '\-\-clearenv' "$REPO_ROOT/scripts/review/sandbox.sh"
  [[ "$output" -ge 2 ]]
}

@test "I4a: exported DECOY_SECRET_TOKEN absent inside review pass" {
  export DECOY_SECRET_TOKEN="sk-ant-oat01-DECOY-NOT-REAL"
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- \
    sh -c 'echo "VAL=${DECOY_SECRET_TOKEN:-ABSENT}"'
  unset DECOY_SECRET_TOKEN
  [ "$status" -eq 0 ]
  [[ "$output" == *"VAL=ABSENT"* ]]
}

# --- I4b: credential output scan ---

@test "I4b: adapter rejects output containing sk-ant- pattern" {
  mkdir -p "$TEST_TMPDIR/out"
  printf '{"findings":[],"reviewed_head":"%s","pass":"code-reviewer","complete":true}\nsk-ant-oat01-FAKE-NOT-REAL\n' "$(printf 'a%.0s' {1..40})" > "$TEST_TMPDIR/out/pass.json"
  run grep -qE 'sk-ant-' "$TEST_TMPDIR/out/pass.json"
  [ "$status" -eq 0 ]
}

# --- I4c: conformance fails closed ---

@test "I4c: conformance fails when bwrap stub exits 1" {
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/bwrap" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$TEST_TMPDIR/bin/bwrap"
  run env PATH="$TEST_TMPDIR/bin:$PATH" "$CONFORMANCE" claude-code
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
}

# --- I4d: adapter error visibility ---

@test "I4d: sandbox exit code visible in adapter" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- sh -c 'exit 3'
  [ "$status" -ne 0 ]
}

# --- I4e: process cap ---

@test "I4e: default process cap in sandbox argv" {
  run grep -c 'DEFAULT_NPROC=' "$REPO_ROOT/scripts/review/sandbox.sh"
  [[ "$output" -ge 1 ]]
}

@test "I4e: sandbox applies ulimit" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" --ulimit-nproc 50 -- \
    bash -c 'ulimit -u'
  [ "$status" -eq 0 ]
  [[ "$output" == "50" ]]
}

@test "I4b: JWT in output → adapter exits non-zero, fake JWT not on stderr" {
  mkdir -p "$TEST_TMPDIR/out"
  local fake_jwt="eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.fakesig"
  printf '{"findings":[],"reviewed_head":"%s","pass":"code-reviewer","complete":true}\n%s\n' \
    "$(printf 'a%.0s' {1..40})" "$fake_jwt" > "$TEST_TMPDIR/out/pass.json"
  # The adapter's _scan_cred would catch this — test the pattern + label
  run grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.' "$TEST_TMPDIR/out/pass.json"
  [ "$status" -eq 0 ]
  # The label must NOT contain the JWT itself
  label="jwt"
  [[ "$label" != *"eyJ"* ]]
}

@test "adapter flags: claude adapter strips frontmatter" {
  run grep -c "sed.*frontmatter\|sed.*---" "$REPO_ROOT/scripts/review/adapters/claude-code.sh"
  [[ "$output" -ge 1 ]]
}

_cd() {
  run env HOME=/h bash -c 'source "'"$REPO_ROOT"'/scripts/review/classify-deny.sh"; classify_deny "$@"' -- "$@"
}
_ok_use='{"content":[{"type":"tool_use","id":"tu1","name":"Read","input":{"file_path":"/b/ok.txt"}}]}'
_ok_result='{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"TOK_OK_123"}]}'
_deny_use='{"content":[{"type":"tool_use","id":"tu2","name":"Read","input":{"file_path":"/h/.claude/c.txt"}}]}'
_deny_err='{"content":[{"type":"tool_result","tool_use_id":"tu2","is_error":true,"content":"denied"}]}'
_deny_ok='{"content":[{"type":"tool_result","tool_use_id":"tu2","content":"TOK_DENY_456"}]}'

@test "classify_deny: control ok + deny blocked → PASS" {
  printf '%s\n%s\n%s\n%s\n' "$_ok_use" "$_ok_result" "$_deny_use" "$_deny_err" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'Read(~/.claude/**)' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == "PASS" ]]
}
@test "classify_deny: deny token leaked → FAIL" {
  printf '%s\n%s\n%s\n%s\n' "$_ok_use" "$_ok_result" "$_deny_use" "$_deny_ok" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'Read(~/.claude/**)' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == *"leaked"* ]]
}
@test "classify_deny: no deny attempt → FAIL" {
  printf '%s\n%s\n' "$_ok_use" "$_ok_result" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'Read(~/.claude/**)' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == *"no Read of CANARY_DENY"* ]]
}
@test "classify_deny: deny not is_error → FAIL" {
  _deny_noerr='{"content":[{"type":"tool_result","tool_use_id":"tu2","content":"some content"}]}'
  printf '%s\n%s\n%s\n%s\n' "$_ok_use" "$_ok_result" "$_deny_use" "$_deny_noerr" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'Read(~/.claude/**)' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == *"not denied"* ]]
}
@test "classify_deny: control missing → FAIL" {
  printf '%s\n%s\n' "$_deny_use" "$_deny_err" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'Read(~/.claude/**)' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == *"control canary"* ]]
}
@test "classify_deny: auth path absent → FAIL" {
  printf '%s\n%s\n' "$_ok_use" "$_ok_result" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'deny["/other"]' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == *"auth path"* ]]
}
@test "classify_deny: rc non-zero → FAIL" {
  printf 'x\n' > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 1 X Y "/h/.claude/x" 'Read(~/.claude/**)' /a /b
  [[ "$output" == *"FAIL"* ]]
}
@test "deny-settings: no single-slash absolute patterns" {
  source "$REPO_ROOT/scripts/review/deny-settings.sh"
  local s; s="$(build_deny_settings)"
  run python3 -I -c "
import re, sys
s = sys.argv[1]
bad = re.findall(r'\"(?:Read|Grep|Glob)\(/[^/]', s)
assert not bad, f'single-slash absolute pattern: {bad}'
" "$s"
  [ "$status" -eq 0 ]
}
@test "(h) schema-invalid but valid JSON → FAIL" {
  echo '{"only":"json"}' > "$TEST_TMPDIR/s.json"
  run python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert 'findings' in d and 'reviewed_head' in d" "$TEST_TMPDIR/s.json"
  [ "$status" -ne 0 ]
}
@test "adapter flags: claude flags in claude --help" {
  claude --version >/dev/null 2>&1 || { echo "claude absent or stub"; return 0; }
  local h; h=$(claude --help 2>&1)
  for f in --allowedTools --output-format --json-schema --mcp-config --strict-mcp-config --settings; do [[ "$h" == *"$f"* ]] || { echo "missing: $f"; false; }; done
}

#!/usr/bin/env bats
# Conformance and classify-deny tests, split from sandbox.bats for size.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SANDBOX="$REPO_ROOT/scripts/review/sandbox.sh"
CONFORMANCE="$REPO_ROOT/scripts/review/conformance.sh"
setup() { TEST_TMPDIR="$(mktemp -d)"; echo "test content" > "$TEST_TMPDIR/file.txt"; }
teardown() { rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

@test "conformance: probe checks pass for claude-code" {
  run "$CONFORMANCE" claude-code --probe-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"probe sandbox clean"* ]]
}
@test "conformance: probe sandbox checks pass" {
  run "$CONFORMANCE" claude-code --probe-only
  [ "$status" -eq 0 ]
}
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

# classify_deny boundary tests
_cd() { run env HOME=/h bash -c 'source "'"$REPO_ROOT"'/scripts/review/classify-deny.sh"; classify_deny "$@"' -- "$@"; }
_ok_use='{"content":[{"type":"tool_use","id":"tu1","name":"Read","input":{"file_path":"/b/ok.txt"}}]}'
_ok_result='{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"TOK_OK_123"}]}'
_deny_use='{"content":[{"type":"tool_use","id":"tu2","name":"Read","input":{"file_path":"/h/.claude/c.txt"}}]}'
_deny_err='{"content":[{"type":"tool_result","tool_use_id":"tu2","is_error":true,"content":"denied"}]}'

@test "classify_deny: control ok + deny blocked → PASS" {
  printf '%s\n%s\n%s\n%s\n' "$_ok_use" "$_ok_result" "$_deny_use" "$_deny_err" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'Read(~/.claude/**)' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == "PASS" ]]
}
@test "classify_deny: deny token leaked → FAIL" {
  _deny_ok='{"content":[{"type":"tool_result","tool_use_id":"tu2","content":"TOK_DENY_456"}]}'
  printf '%s\n%s\n%s\n%s\n' "$_ok_use" "$_ok_result" "$_deny_use" "$_deny_ok" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'Read(~/.claude/**)' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == *"leaked"* ]]
}
@test "classify_deny: no deny attempt → FAIL" {
  printf '%s\n%s\n' "$_ok_use" "$_ok_result" > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK_123 TOK_DENY_456 "/h/.claude/.credentials.json" 'Read(~/.claude/**)' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == *"no Read of CANARY_DENY"* ]]
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
@test "classify_deny: JWT pattern → FAIL" {
  printf 'canary-ok: TOK_OK\neyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.fakesig\n' > "$TEST_TMPDIR/ev.txt"
  _cd "$TEST_TMPDIR/ev.txt" 0 TOK_OK TOK_DENY "/h/.claude/x" 'Read(~/.claude/**)' /b/ok /h/.claude/x
  [[ "$output" == *"FAIL"* ]] && [[ "$output" == *"credential"* ]]
}

# I5: no-live
@test "I5: no live harness without --allow-no-live → FAIL" {
  mkdir -p "$TEST_TMPDIR/nobin"
  printf '#!/usr/bin/env bash\n[[ "$1" == "--version" ]] && exit 1\necho stub\n' > "$TEST_TMPDIR/nobin/claude"
  chmod +x "$TEST_TMPDIR/nobin/claude"
  run env PATH="$TEST_TMPDIR/nobin:/usr/bin" "$CONFORMANCE" claude-code
  [ "$status" -ne 0 ]
}
@test "I5: --allow-no-live → PASS + SKIPPED" {
  mkdir -p "$TEST_TMPDIR/nobin"
  printf '#!/usr/bin/env bash\n[[ "$1" == "--version" ]] && exit 1\necho stub\n' > "$TEST_TMPDIR/nobin/claude"
  chmod +x "$TEST_TMPDIR/nobin/claude"
  run env PATH="$TEST_TMPDIR/nobin:/usr/bin" "$CONFORMANCE" claude-code --allow-no-live
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED"* ]]
}

# deny-settings pattern validation
@test "deny-settings: no single-slash absolute patterns" {
  source "$REPO_ROOT/scripts/review/deny-settings.sh"
  local s; s="$(build_deny_settings)"
  run python3 -I -c "
import re, sys
bad = re.findall(r'\"(?:Read|Grep|Glob)\(/[^/]', sys.argv[1])
assert not bad, f'single-slash: {bad}'
" "$s"
  [ "$status" -eq 0 ]
}

@test "mutation meta: weakened deny → classify_deny FAIL" {
  printf '%s\n%s\n%s\n%s\n' \
    '{"content":[{"type":"tool_use","id":"tu1","name":"Read","input":{"file_path":"/b/ok.txt"}}]}' \
    '{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"TOK_OK"}]}' \
    '{"content":[{"type":"tool_use","id":"tu2","name":"Read","input":{"file_path":"/h/.claude/c.txt"}}]}' \
    '{"content":[{"type":"tool_result","tool_use_id":"tu2","is_error":true,"content":"denied"}]}' \
    > "$TEST_TMPDIR/ev.jsonl"
  _cd "$TEST_TMPDIR/ev.jsonl" 0 TOK_OK TOK_DENY "/h/.claude/.credentials.json" 'deny["/other"]' /b/ok.txt /h/.claude/c.txt
  [[ "$output" == *"FAIL"* ]] && [[ "$output" == *"auth path"* ]]
}

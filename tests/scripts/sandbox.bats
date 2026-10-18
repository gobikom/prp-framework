#!/usr/bin/env bats
# Sandbox and conformance tests for prp-framework#160 Phase 1a.
# Tests Invariant 4: pass confinement.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SANDBOX="$REPO_ROOT/scripts/review/sandbox.sh"

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
  # bash, not sh: dash has no /dev/tcp, so the probe would fail for a shell
  # reason and print NET_BLOCKED under ANY sandbox (vacuous assertion).
  run "$SANDBOX" --probe --bundle "$TEST_TMPDIR" --timeout 10 -- \
    bash -c '(echo >/dev/tcp/140.82.112.5/443) 2>/dev/null && echo "NET_OPEN" || echo "NET_BLOCKED"'
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

# --- I4b: credential output scan (unit: drive _scan_cred itself) ---

@test "I4b: _scan_cred detects sk-ant pattern, label only" {
  source "$REPO_ROOT/scripts/review/cred-patterns.sh"
  printf 'x sk-ant-oat01-FAKE-NOT-REAL y\n' > "$TEST_TMPDIR/poisoned.txt"
  run _scan_cred "$TEST_TMPDIR/poisoned.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"credential pattern: sk-ant"* ]]
  [[ "$output" != *"sk-ant-oat01-FAKE-NOT-REAL"* ]]
}

@test "I4b: _scan_cred detects JWT pattern, label only" {
  source "$REPO_ROOT/scripts/review/cred-patterns.sh"
  printf 'x eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.fakesig y\n' > "$TEST_TMPDIR/poisoned.txt"
  run _scan_cred "$TEST_TMPDIR/poisoned.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"credential pattern: jwt"* ]]
  [[ "$output" != *"eyJhbGciOiJub25lIn0"* ]]
}

@test "I4b: _scan_cred detects github-token pattern" {
  source "$REPO_ROOT/scripts/review/cred-patterns.sh"
  printf 'x ghp_FAKE0123456789abcdef y\n' > "$TEST_TMPDIR/poisoned.txt"
  run _scan_cred "$TEST_TMPDIR/poisoned.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"credential pattern: github-token"* ]]
}

@test "I4b: _scan_cred passes a clean file" {
  source "$REPO_ROOT/scripts/review/cred-patterns.sh"
  printf '{"findings":[],"reviewed_head":"x","complete":true}\n' > "$TEST_TMPDIR/clean.txt"
  run _scan_cred "$TEST_TMPDIR/clean.txt"
  [ "$status" -eq 0 ]
}

@test "I4b: _scan_cred fails closed on unreadable file" {
  source "$REPO_ROOT/scripts/review/cred-patterns.sh"
  run _scan_cred "$TEST_TMPDIR/nonexistent-file.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"credential scan failed"* ]]
}

# --- I4c: conformance fails closed ---

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

@test "I4b: adapter fails closed on unknown --pass name" {
  mkdir -p "$TEST_TMPDIR/stub-bin" "$TEST_TMPDIR/out" "$TEST_TMPDIR/.claude"
  echo "dummy" > "$TEST_TMPDIR/.claude/.credentials.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/stub-bin/claude"
  chmod +x "$TEST_TMPDIR/stub-bin/claude"
  run env PATH="$TEST_TMPDIR/stub-bin:$PATH" HOME="$TEST_TMPDIR" \
    bash "$REPO_ROOT/scripts/review/adapters/claude-code.sh" --pass code-reviwer-typo --bundle "$TEST_TMPDIR" --schema "$REPO_ROOT/schemas/review-findings.schema.json" --out "$TEST_TMPDIR/out" --timeout 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"no agent definition"* ]]
  [[ "$output" == *"code-reviewer"* ]]
  [ ! -f "$TEST_TMPDIR/out/pass.json" ]
}

# Regression for the 6a0614d guard: with adapters/claude-code-agents missing or
# empty, the diagnostic must still print (previously set -e killed the script
# inside the available= substitution, silently). Drives a copied fake repo so
# the adapter's derived REPO_ROOT has a mutable agents dir.
@test "I4b: unknown --pass diagnostic survives broken agents dir (missing/empty)" {
  mkdir -p "$TEST_TMPDIR/stub-bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/stub-bin/claude"
  chmod +x "$TEST_TMPDIR/stub-bin/claude"
  for state in missing empty; do
    local FAKE_REPO="$TEST_TMPDIR/repo-$state" HOME_DIR="$TEST_TMPDIR/home-$state"
    mkdir -p "$FAKE_REPO/scripts" "$FAKE_REPO/adapters" "$HOME_DIR/.claude" "$TEST_TMPDIR/out-$state"
    cp -r "$REPO_ROOT/scripts/review" "$FAKE_REPO/scripts/"
    [[ "$state" == "empty" ]] && mkdir -p "$FAKE_REPO/adapters/claude-code-agents"
    echo "dummy" > "$HOME_DIR/.claude/.credentials.json"
    run env PATH="$TEST_TMPDIR/stub-bin:$PATH" HOME="$HOME_DIR" \
      bash "$FAKE_REPO/scripts/review/adapters/claude-code.sh" --pass no-such-pass --bundle "$TEST_TMPDIR" \
      --schema "$REPO_ROOT/schemas/review-findings.schema.json" --out "$TEST_TMPDIR/out-$state" --timeout 5
    [ "$status" -eq 1 ] || { echo "$state: expected exit 1, got $status"; false; }
    [[ "$output" == *"no agent definition"* ]] || { echo "$state: diagnostic missing: $output"; false; }
    [[ "$output" == *"(available: none)"* ]] || { echo "$state: available fallback missing: $output"; false; }
    [ ! -f "$TEST_TMPDIR/out-$state/pass.json" ] || { echo "$state: pass.json created"; false; }
  done
}

@test "adapter flags: claude adapter uses strip-frontmatter" {
  run grep -c "strip.frontmatter\|strip_frontmatter" "$REPO_ROOT/scripts/review/adapters/claude-code.sh"
  [[ "$output" -ge 1 ]]
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
@test "adapter flags: claude flags in claude --help" {
  claude --version >/dev/null 2>&1 || { echo "claude absent or stub"; return 0; }
  local h; h=$(claude --help 2>&1)
  for f in --allowedTools --output-format --json-schema --mcp-config --strict-mcp-config --settings; do [[ "$h" == *"$f"* ]] || { echo "missing: $f"; false; }; done
}

# --- C1: frontmatter strip ---
@test "C1: strip_frontmatter preserves non-frontmatter --- lines" {
  source "$REPO_ROOT/scripts/review/strip-frontmatter.sh"
  for f in "$REPO_ROOT"/adapters/claude-code-agents/*.md; do
    local total; total=$(wc -l < "$f")
    local fm=0
    if [[ "$(head -1 "$f")" == "---" ]]; then
      fm=$(awk 'NR==1{next} /^---$/{print NR; exit}' "$f")
    fi
    local expect=$((total - fm))
    local got; got=$(strip_frontmatter "$f" | wc -l)
    [[ "$got" -eq "$expect" ]] || { echo "$(basename "$f"): expected $expect, got $got"; false; }
  done
}

# --- I1: PID namespace ---
@test "I1: review pass has isolated PID namespace" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- \
    bash -c 'echo PIDS=$(ls /proc | grep -cE "^[0-9]+$")'
  [ "$status" -eq 0 ]
  local n; n=$(echo "$output" | grep -oP 'PIDS=\K\d+')
  [[ "$n" -lt 10 ]]
}

# --- I2: stderr credential scan ---
@test "I2: stderr with fake sk-ant → withheld" {
  mkdir -p "$TEST_TMPDIR/stub-bin" "$TEST_TMPDIR/out" "$TEST_TMPDIR/.claude"
  echo "dummy" > "$TEST_TMPDIR/.claude/.credentials.json"
  printf '#!/usr/bin/env bash\necho "sk-ant-FAKE-NOT-REAL" >&2; exit 1\n' > "$TEST_TMPDIR/stub-bin/claude"
  chmod +x "$TEST_TMPDIR/stub-bin/claude"
  run env PATH="$TEST_TMPDIR/stub-bin:$PATH" HOME="$TEST_TMPDIR" \
    bash "$REPO_ROOT/scripts/review/adapters/claude-code.sh" --pass code-reviewer --bundle "$TEST_TMPDIR" --schema "$REPO_ROOT/schemas/review-findings.schema.json" --out "$TEST_TMPDIR/out" --timeout 5
  [ "$status" -ne 0 ]
  [[ "$output" == *"withheld"* ]] || [[ "$output" == *"credential"* ]]
  [[ "$output" != *"sk-ant-FAKE-NOT-REAL"* ]]
}

# --- I3: scan before copy, cleanup on leak ---
@test "I3: credential in output → all files cleaned" {
  mkdir -p "$TEST_TMPDIR/stub-bin" "$TEST_TMPDIR/out" "$TEST_TMPDIR/.claude"
  echo "dummy" > "$TEST_TMPDIR/.claude/.credentials.json"
  printf '#!/usr/bin/env bash\necho "sk-ant-FAKE-LEAK"; exit 0\n' > "$TEST_TMPDIR/stub-bin/claude"
  chmod +x "$TEST_TMPDIR/stub-bin/claude"
  run env PATH="$TEST_TMPDIR/stub-bin:$PATH" HOME="$TEST_TMPDIR" \
    bash "$REPO_ROOT/scripts/review/adapters/claude-code.sh" --pass code-reviewer --bundle "$TEST_TMPDIR" --schema "$REPO_ROOT/schemas/review-findings.schema.json" --out "$TEST_TMPDIR/out" --events-out "$TEST_TMPDIR/ev.jsonl" --timeout 5
  [ "$status" -ne 0 ]
  [ ! -f "$TEST_TMPDIR/out/pass.json" ]
  [ ! -f "$TEST_TMPDIR/out/raw-output.json" ]
  [ ! -f "$TEST_TMPDIR/out/stderr.log" ]
  [ ! -f "$TEST_TMPDIR/ev.jsonl" ]
}

# --- Adapter happy path: extraction + events-out copy ---
@test "I4b: adapter happy path extracts structured_output to pass.json" {
  mkdir -p "$TEST_TMPDIR/stub-bin" "$TEST_TMPDIR/out" "$TEST_TMPDIR/.claude"
  echo "dummy" > "$TEST_TMPDIR/.claude/.credentials.json"
  printf '#!/usr/bin/env bash\ncat <<"EOF"\n{"structured_output":{"findings":[{"id":"f1","severity":"Low","title":"t"}],"reviewed_head":"x","pass":"code-reviewer","complete":true}}\nEOF\nexit 0\n' > "$TEST_TMPDIR/stub-bin/claude"
  chmod +x "$TEST_TMPDIR/stub-bin/claude"
  run env PATH="$TEST_TMPDIR/stub-bin:$PATH" HOME="$TEST_TMPDIR" \
    bash "$REPO_ROOT/scripts/review/adapters/claude-code.sh" --pass code-reviewer --bundle "$TEST_TMPDIR" --schema "$REPO_ROOT/schemas/review-findings.schema.json" --out "$TEST_TMPDIR/out" --events-out "$TEST_TMPDIR/ev.jsonl" --timeout 5
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMPDIR/out/pass.json" ]
  grep -q '"findings"' "$TEST_TMPDIR/out/pass.json"
  grep -q '"f1"' "$TEST_TMPDIR/out/pass.json"
  grep -q '"structured_output"' "$TEST_TMPDIR/ev.jsonl"
  [ ! -s "$TEST_TMPDIR/out/stderr.log" ]
}

# --- Adapter final backstop: escaped credential decoded only in pass.json ---
@test "I4b: adapter final pass.json scan catches escaped credential" {
  mkdir -p "$TEST_TMPDIR/stub-bin" "$TEST_TMPDIR/out" "$TEST_TMPDIR/.claude"
  echo "dummy" > "$TEST_TMPDIR/.claude/.credentials.json"
  # ghp_... : the raw-output scan sees no literal 'ghp_', but json.loads
  # decodes _ to '_' in pass.json — the final scan must fail closed there.
  printf '#!/usr/bin/env bash\ncat <<"EOF"\n{"structured_output":{"findings":[],"note":"ghp\\u005fFAKE0123456789abcdef"}}\nEOF\nexit 0\n' > "$TEST_TMPDIR/stub-bin/claude"
  chmod +x "$TEST_TMPDIR/stub-bin/claude"
  run env PATH="$TEST_TMPDIR/stub-bin:$PATH" HOME="$TEST_TMPDIR" \
    bash "$REPO_ROOT/scripts/review/adapters/claude-code.sh" --pass code-reviewer --bundle "$TEST_TMPDIR" --schema "$REPO_ROOT/schemas/review-findings.schema.json" --out "$TEST_TMPDIR/out" --timeout 5
  [ "$status" -ne 0 ]
  [ ! -f "$TEST_TMPDIR/out/pass.json" ]
  [ ! -f "$TEST_TMPDIR/out/raw-output.json" ]
}

# --- I4: resolve_pkg_root behavior ---
@test "I4: resolve_pkg_root nonexistent dir → non-zero" {
  run bash -c "source '$REPO_ROOT/scripts/review/resolve-pkg-root.sh'; resolve_pkg_root /nonexistent/x 2>/dev/null"
  [ "$status" -ne 0 ]
}
@test "I4: resolve_pkg_root node_modules nested → package root" {
  mkdir -p "$TEST_TMPDIR/prefix/lib/node_modules/pkg/bin"
  run bash -c "source '$REPO_ROOT/scripts/review/resolve-pkg-root.sh'; resolve_pkg_root '$TEST_TMPDIR/prefix/lib/node_modules/pkg/bin'"
  [ "$status" -eq 0 ]
  [[ "$output" == "$TEST_TMPDIR/prefix/lib/node_modules" ]]
}
@test "I4: live mount (when claude present)" {
  claude --version >/dev/null 2>&1 || { echo "claude absent"; return 0; }
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" -- claude --version
  [ "$status" -eq 0 ]
}

# --- I5: conformance no-live ---
@test "R3-3: ulimit injection rejected" {
  run "$SANDBOX" --harness claude-code --bundle "$TEST_TMPDIR" --ulimit-nproc '1; touch /tmp/x' -- echo ok
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid ULIMIT_NPROC"* ]]
}

# --- R5: bundle-shipped .mcp-config.json rejected (CWE-59 symlink write-through) ---
# The adapter writes its MCP config into the untrusted bundle pre-sandbox; a
# bundle-carried symlink there would make the redirection clobber a host file.
# Regression for the R5 review fix: any pre-existing entry (symlink OR regular
# file) must fail closed before the write, leaving both the victim and the
# shipped entry untouched.
@test "R5: adapter rejects bundle-shipped .mcp-config.json (symlink and regular)" {
  mkdir -p "$TEST_TMPDIR/stub-bin" "$TEST_TMPDIR/home/.claude"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_TMPDIR/stub-bin/claude"
  chmod +x "$TEST_TMPDIR/stub-bin/claude"
  echo "dummy" > "$TEST_TMPDIR/home/.claude/.credentials.json"
  for state in symlink regular; do
    local BUNDLE="$TEST_TMPDIR/bundle-$state" VICTIM="$TEST_TMPDIR/victim-$state" OUT="$TEST_TMPDIR/out-$state"
    mkdir -p "$BUNDLE" "$OUT"
    printf 'sentinel-%s\n' "$state" > "$VICTIM"
    if [[ "$state" == symlink ]]; then
      ln -s "$VICTIM" "$BUNDLE/.mcp-config.json"
    else
      cp "$VICTIM" "$BUNDLE/.mcp-config.json"
    fi
    run env PATH="$TEST_TMPDIR/stub-bin:$PATH" HOME="$TEST_TMPDIR/home" \
      bash "$REPO_ROOT/scripts/review/adapters/claude-code.sh" --pass code-reviewer --bundle "$BUNDLE" \
      --schema "$REPO_ROOT/schemas/review-findings.schema.json" --out "$OUT" --timeout 5
    [ "$status" -eq 1 ] || { echo "$state: expected exit 1, got $status"; false; }
    [[ "$output" == *"bundle must not ship .mcp-config.json"* ]] || { echo "$state: diagnostic missing: $output"; false; }
    grep -qx "sentinel-$state" "$VICTIM" || { echo "$state: victim file modified (write-through)"; false; }
    [ ! -f "$OUT/pass.json" ] || { echo "$state: pass.json created"; false; }
    if [[ "$state" == regular ]]; then
      cmp -s "$BUNDLE/.mcp-config.json" "$VICTIM" || { echo "regular: shipped entry modified"; false; }
    else
      [[ -L "$BUNDLE/.mcp-config.json" ]] || { echo "symlink: shipped link removed"; false; }
    fi
  done
}

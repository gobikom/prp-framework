#!/usr/bin/env bats
# codex review adapter (prp-framework#160): fail-closed behaviour and credential cleanup.
# The sandbox is stubbed (it just execs the command after `--`); codex is a stub on PATH.
# Run: bats tests/scripts/review-codex-adapter.bats

FRAMEWORK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    T="$(mktemp -d)"
    mkdir -p "$T/fw/scripts/review/adapters" "$T/fw/adapters" "$T/home/.codex" "$T/bin" "$T/bundle" "$T/out"
    cp "$FRAMEWORK_DIR"/scripts/review/*.sh "$T/fw/scripts/review/"
    cp "$FRAMEWORK_DIR/scripts/review/adapters/codex.sh" "$T/fw/scripts/review/adapters/"
    cp -r "$FRAMEWORK_DIR/adapters/claude-code-agents" "$T/fw/adapters/"
    printf '#!/usr/bin/env bash\nwhile [ "$1" != -- ]; do shift; done; shift; exec "$@"\n' > "$T/fw/scripts/review/sandbox.sh"
    chmod +x "$T/fw/scripts/review/sandbox.sh"
    echo '{}' > "$T/home/.codex/auth.json"
    printf '{"head":"%s"}\n' "$(printf 'a%.0s' $(seq 40))" > "$T/bundle/metadata.json"
    printf '#!/usr/bin/env bash\ncat "$CODEX_STDOUT"; [ -n "${CODEX_STDERR:-}" ] && cat "$CODEX_STDERR" >&2; exit "${CODEX_RC:-0}"\n' > "$T/bin/codex"
    chmod +x "$T/bin/codex"
    SCHEMA="$FRAMEWORK_DIR/schemas/review-findings.schema.json"
}
teardown() { rm -rf "$T"; }

run_adapter() {
    HOME="$T/home" PATH="$T/bin:$PATH" run "$T/fw/scripts/review/adapters/codex.sh" \
        --pass "${PASS:-code-reviewer}" --bundle "$T/bundle" --schema "$SCHEMA" --out "$T/out"
}
msg() { printf '{"type":"item.completed","item":{"type":"agent_message","text":%s}}\n' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")"; }

@test "codex adapter fails closed on a missing agent definition" {
    PASS=no-such-pass run_adapter
    [ "$status" -eq 1 ]
    [[ "$output" == *"no agent definition"* ]]
}

@test "codex adapter rejects a path-like pass name" {
    PASS='../x' run_adapter
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid pass name"* ]]
}

@test "codex adapter refuses a bundle-shipped .output-schema.json symlink and leaves the target alone" {
    echo keep > "$T/victim"
    ln -s "$T/victim" "$T/bundle/.output-schema.json"
    export CODEX_STDOUT=/dev/null
    run_adapter
    [ "$status" -eq 1 ]
    [ "$(cat "$T/victim")" = keep ]
}

@test "codex adapter removes the adapted schema from the bundle on exit" {
    msg '{"findings":[]}' > "$T/stdout"; export CODEX_STDOUT="$T/stdout"
    run_adapter
    [ ! -e "$T/bundle/.output-schema.json" ]
}

@test "codex adapter extracts the last agent_message, tolerating blank and non-JSON lines" {
    { echo; echo 'not json'; msg '{"findings":[]}'; echo; } > "$T/stdout"; export CODEX_STDOUT="$T/stdout"
    run_adapter
    [ "$status" -eq 0 ]
    [ -s "$T/out/pass.json" ]
    [[ "$output" == *"skipped 1 non-JSON"* ]]
}

@test "codex adapter fails (no pass.json) when the last agent_message is not a findings object" {
    { msg '{"findings":[]}'; msg 'oops'; } > "$T/stdout"; export CODEX_STDOUT="$T/stdout"
    run_adapter
    [ "$status" -eq 1 ]
    [ ! -e "$T/out/pass.json" ]
}

@test "codex adapter on a non-zero exit leaves no pass.json" {
    : > "$T/stdout"; export CODEX_STDOUT="$T/stdout" CODEX_RC=3
    run_adapter
    [ "$status" -eq 3 ]
    [ ! -e "$T/out/pass.json" ]
}

@test "codex adapter: a credential in the raw event stream removes every output file" {
    { echo '{"type":"item.completed","item":{"type":"command_execution","aggregated_output":"sk-proj-abcdefghijklmnopqrstuvwx"}}'; msg '{"findings":[]}'; } > "$T/stdout"
    export CODEX_STDOUT="$T/stdout"
    run_adapter
    [ "$status" -eq 1 ]
    [ ! -e "$T/out/pass.json" ] && [ ! -e "$T/out/raw-output.jsonl" ] && [ ! -e "$T/out/stderr.log" ]
}

@test "codex adapter: a credential on stderr is withheld and everything is removed" {
    msg '{"findings":[]}' > "$T/stdout"; printf 'token ghp_abcdefghijklmnop\n' > "$T/stderr"
    export CODEX_STDOUT="$T/stdout" CODEX_STDERR="$T/stderr" CODEX_RC=1
    run_adapter
    [ "$status" -eq 1 ]
    [[ "$output" == *"stderr withheld"* ]]
    [[ "$output" != *ghp_abc* ]]
    [ ! -e "$T/out/raw-output.jsonl" ] && [ ! -e "$T/out/stderr.log" ]
}

@test "cred-patterns: codex refresh_token and OpenAI key shapes are caught; task-* names are not" {
    source "$FRAMEWORK_DIR/scripts/review/cred-patterns.sh"
    printf '{"refresh_token": "abcdefghijkl"}\n' > "$T/a"; run _scan_cred "$T/a"; [ "$status" -eq 1 ]
    printf 'sk-abcdefghijklmnopqrstuv\n' > "$T/b"; run _scan_cred "$T/b"; [ "$status" -eq 1 ]
    printf 'task-management-system-overview-doc\n' > "$T/c"; run _scan_cred "$T/c"; [ "$status" -eq 0 ]
    run _scan_cred "$T/nonexistent"; [ "$status" -eq 1 ]
}

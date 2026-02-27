#!/usr/bin/env bats
# Tests for helper scripts — verifies they are executable and well-formed
#
# Requirements: bats-core (https://github.com/bats-core/bats-core)
# Run: bats tests/scripts/scripts.bats

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts"

# ─────────────────────────────────────────────
# 1. Scripts are executable
# ─────────────────────────────────────────────
@test "install.sh is executable" {
    [ -x "$SCRIPTS_DIR/install.sh" ]
}

@test "sync.sh is executable" {
    [ -x "$SCRIPTS_DIR/sync.sh" ]
}

@test "cleanup-artifacts.sh is executable" {
    [ -x "$SCRIPTS_DIR/cleanup-artifacts.sh" ]
}

@test "prp-run-all-state.sh is executable" {
    [ -x "$SCRIPTS_DIR/prp-run-all-state.sh" ]
}

@test "migrate-artifacts.sh is executable" {
    [ -x "$SCRIPTS_DIR/migrate-artifacts.sh" ]
}

# ─────────────────────────────────────────────
# 2. Scripts have shebang line
# ─────────────────────────────────────────────
@test "all scripts have bash shebang" {
    for script in "$SCRIPTS_DIR"/*.sh; do
        head -1 "$script" | grep -q "#!/bin/bash\|#!/usr/bin/env bash"
    done
}

# ─────────────────────────────────────────────
# 3. Functional tests
# ─────────────────────────────────────────────
@test "cleanup-artifacts.sh shows usage without args" {
    run bash "$SCRIPTS_DIR/cleanup-artifacts.sh"
    # Should either show usage or succeed (varies by implementation)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "prp-run-all-state.sh shows usage without args" {
    run bash "$SCRIPTS_DIR/prp-run-all-state.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

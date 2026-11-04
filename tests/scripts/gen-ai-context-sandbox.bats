#!/usr/bin/env bats
# scripts/gen-ai-context.sh must not scan agent runtime sandboxes (.sandbox-*) inside the repo (#133).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
  TEST_TMPDIR="$(mktemp -d)"
  cd "$TEST_TMPDIR" || exit 1
  git init -q .
  mkdir -p .prp src .sandbox-home .sandbox-tmp .sandbox-custom
  cp -r "$REPO_ROOT/templates" .prp/templates
  echo '{}' > package.json
  echo 'x=1' > src/a.py
  echo 'import sqlite3' > .sandbox-home/x.py
  echo 'app.getHostCapabilities()' > .sandbox-home/y.js
  echo 'import sqlite3' > .sandbox-custom/z.py
  echo 'app.get("/leak")' > .sandbox-custom/q.js
}

teardown() { rm -rf "$TEST_TMPDIR"; }

@test "--init does not leak sandbox dirs into stack, endpoints or context map" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  [ -f PROJECT.md ]
  grep -q 'Node.js' PROJECT.md
  run grep -iE 'sqlite|getHostCapabilities|/leak|\.sandbox' PROJECT.md
  [ "$status" -eq 1 ]
}

@test "S-NESTED-MAP: code only under a nested .sandbox-* does not put the dir in the Context Map" {
  mkdir -p foo/.sandbox-home
  echo 'x=1' > foo/.sandbox-home/x.py
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  run grep -q 'foo/' PROJECT.md
  [ "$status" -eq 1 ]
}

@test "S-NESTED-CHECK: nested .sandbox-* does not make --check report the dir as missing" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  mkdir -p foo/.sandbox-home
  echo 'x=1' > foo/.sandbox-home/x.py
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 0 ]
  ! grep -qF "Directory 'foo/' not in Context Map" <<< "$output"
}

@test "S-REAL-NESTED: real code one level down still appears in the Context Map" {
  mkdir -p foo
  echo 'x=1' > foo/real.py
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  grep -qF '`foo/`' PROJECT.md
}

@test "S-STACK-POISONED: substring Stack line is reported outdated" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  sed -i '/AUTO-GEN:BEGIN/,/AUTO-GEN:END/s/^- \*\*Stack:\*\* .*/- **Stack:** Node.js, SQLite/' PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'Stack may be outdated' <<< "$output"
}

@test "S-STACK-EXACT: clean init reports Stack is up-to-date" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 0 ]
  grep -q 'Stack is up-to-date' <<< "$output"
}

@test "S-TOP-CHECK: top-level .sandbox-* dirs never produce a check warning" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 0 ]
  ! grep -qi 'sandbox' <<< "$output"
}

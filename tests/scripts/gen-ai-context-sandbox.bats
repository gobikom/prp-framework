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
  echo 'y=2' > .sandbox-custom/z.py
}

teardown() { rm -rf "$TEST_TMPDIR"; }

@test "--init does not leak sandbox dirs into stack, endpoints or context map" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  ! grep -qiE 'sqlite|getHostCapabilities|\.sandbox' PROJECT.md
}

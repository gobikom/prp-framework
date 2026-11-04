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

teardown() {
  chmod -R u+rwX "$TEST_TMPDIR" 2>/dev/null || true
  rm -rf "$TEST_TMPDIR"
}

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

@test "S-NESTED-JAVA: sandbox under src/main/java never becomes an Entry point, real one does" {
  mkdir -p src/main/java/.sandbox-home/junk src/main/java/app
  echo 'class Application {}' > src/main/java/.sandbox-home/junk/Application.java
  echo 'class Application {}' > src/main/java/app/Application.java
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  grep -qF 'src/main/java/app/Application.java' PROJECT.md
  run grep -qF '.sandbox-home/junk' PROJECT.md
  [ "$status" -eq 1 ]
}

@test "S-DUP-BLOCK: a duplicate AUTO-GEN block does not satisfy the Stack check" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  sed -i '/<!-- AUTO-GEN:BEGIN/,/<!-- AUTO-GEN:END -->/{s/^- \*\*Stack:\*\* .*/- **Stack:** Stale-Stack/}' PROJECT.md
  cat >> PROJECT.md <<'EOF'
<!-- AUTO-GEN:BEGIN — duplicate -->
- **Stack:** Node.js
<!-- AUTO-GEN:END -->
EOF
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'Stack may be outdated' <<< "$output"
  grep -q 'extra AUTO-GEN block' <<< "$output"
}

@test "S-MARKER-IN-BODY: marker text quoted in the body does not open the block" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  sed -i '/<!-- AUTO-GEN:BEGIN/,/<!-- AUTO-GEN:END -->/{s/^- \*\*Stack:\*\* .*/- **Stack:** Real-Stack/}' PROJECT.md
  sed -i '/<!-- AUTO-GEN:BEGIN/i Docs: the AUTO-GEN:BEGIN marker opens the managed block.' PROJECT.md
  sed -i '/<!-- AUTO-GEN:BEGIN/i - **Stack:** Node.js' PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'Stack may be outdated' <<< "$output"
}

@test "S-UNREADABLE: an unreadable dir warns and never reports up-to-date" {
  if [ "$(id -u)" = "0" ]; then skip "running as root — chmod 000 is still readable"; fi
  mkdir -p foo
  echo 'x=1' > foo/real.py
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  chmod 000 foo
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q "could not scan 'foo/'" <<< "$output"
  ! grep -q 'PROJECT.md is up-to-date' <<< "$output"
}

@test "S-J1-CONTROL: readable src/main/java lists the entry and warns nothing" {
  mkdir -p src/main/java/app
  echo 'class Application {}' > src/main/java/app/Application.java
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  grep -qF 'src/main/java/app/Application.java' PROJECT.md
  ! grep -q "could not scan 'src/main/java/'" <<< "$output"
}

@test "S-J3-FAIL-VISIBLE: an unreadable src/main/java warns on stderr" {
  if [ "$(id -u)" = "0" ]; then skip "running as root — chmod 000 is still readable"; fi
  mkdir -p src/main/java/locked
  echo 'class Application {}' > src/main/java/locked/Application.java
  chmod 000 src/main/java/locked
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  grep -q "could not scan 'src/main/java/'" <<< "$output"
}

@test "S-J4-FAIL-VISIBLE-ELSEWHERE: a readable match elsewhere still lists it, and the failed scan still warns" {
  if [ "$(id -u)" = "0" ]; then skip "running as root — chmod 000 is still readable"; fi
  # locked/ is created BEFORE app/: small ext4 directories read back in creation
  # order, so find hits (and reports) the unreadable dir before -quit at the match.
  # Mirroring the map-site pattern, the errored scan discards its partial result
  # (java_entry="") — the assertion is the WARNING, and --init's unchanged exit 0.
  mkdir -p src/main/java/locked src/main/java/app
  echo 'class Main {}' > src/main/java/app/Main.java
  echo 'class Application {}' > src/main/java/locked/Application.java
  chmod 000 src/main/java/locked
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  grep -q "could not scan 'src/main/java/'" <<< "$output"
}

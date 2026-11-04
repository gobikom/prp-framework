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

@test "S-J4-FAIL-VISIBLE-ELSEWHERE: a scan that errors after printing a match discards it and still warns" {
  # A1 (psak, 2026-11-05): the old J4 relied on readdir visiting the unreadable
  # sibling before -print -quit quit at the match — order luck (CI red
  # 41880242912 at e5d51d2). A find shim makes the arm deterministic: the java
  # scan prints its match, errors on stderr, exits 1. The script must warn,
  # read the scan as no entry (Main.java never listed), and not abort --init.
  # Trigger is the literal first arg src/main/java — the only call shaped that
  # way; the map scans (for dir in */) pass top-level names. The shim dir is a
  # dotdir so no scan or entry arm sees it.
  REAL_FIND=$(command -v find)
  mkdir -p .shim-bin src/main/java
  cat > .shim-bin/find <<SH
#!/usr/bin/env bash
if [ "\$1" = "src/main/java" ]; then
  printf '%s\n' 'src/main/java/app/Main.java'
  printf 'find: %s: Permission denied\n' "'src/main/java/locked'" >&2
  exit 1
fi
exec "$REAL_FIND" "\$@"
SH
  chmod +x .shim-bin/find
  export PATH="$PWD/.shim-bin:$PATH"
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  grep -q "could not scan 'src/main/java/'" <<< "$output"
  ! grep -q 'Main\.java' PROJECT.md
}

@test "S1-STREAMS: check-path could-not-scan warnings go to stderr, not stdout" {
  # A2 (psak, 2026-11-05): the --check dir loop's find failure warning must be
  # fail-visible on stderr only — stdout carries the human summary, so a buried
  # warning must never look like a clean check. Same shim trick as J4, but the
  # trigger is the check-path scan's first arg `foo`, and streams are asserted
  # directly (bats `run` merges them, which is what hid the bug).
  mkdir -p foo
  echo 'x=1' > foo/real.py
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  REAL_FIND=$(command -v find)
  mkdir -p .shim-bin
  cat > .shim-bin/find <<SH
#!/usr/bin/env bash
if [ "\$1" = "foo" ]; then
  printf 'find: %s: Permission denied\n' "'foo/locked'" >&2
  exit 1
fi
exec "$REAL_FIND" "\$@"
SH
  chmod +x .shim-bin/find
  export PATH="$PWD/.shim-bin:$PATH"
  bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check >stdout.log 2>stderr.log && rc=0 || rc=$?
  [ "$rc" -ne 0 ]
  grep -q "could not scan 'foo/'" stderr.log
  ! grep -q "could not scan 'foo/'" stdout.log
}

@test "S2-UNTERMINATED: BEGIN without END reads as stale, never up-to-date" {
  # A2 (psak, 2026-11-05): a BEGIN whose END line was deleted must never let
  # body prose below the dangling block satisfy the Stack check — do_update
  # refuses this file (it would lose content), so do_check must say stale.
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  sed -i '/<!-- AUTO-GEN:BEGIN/,/<!-- AUTO-GEN:END -->/{s/^- \*\*Stack:\*\* .*/- **Stack:** Rotten-Stack/}' PROJECT.md
  sed -i '/<!-- AUTO-GEN:END -->/d' PROJECT.md
  printf '%s\n' '- **Stack:** Node.js' >> PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'AUTO-GEN:BEGIN found but AUTO-GEN:END missing' <<< "$output"
  ! grep -q 'Stack is up-to-date' <<< "$output"
}

@test "S3-FILES-ONLY: a repo with no top-level dirs never scans a phantom glob" {
  # A2 (psak, 2026-11-05): with no non-hidden dirs, `for dir in */` stays
  # unexpanded as the literal `*/`; the dir guard must skip it instead of
  # running find on it — otherwise a files-only repo is permanently STALE.
  rm -rf src .sandbox-home .sandbox-tmp .sandbox-custom
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  ! grep -qF "could not scan '*/'" <<< "$output"
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 0 ]
  ! grep -qF "could not scan '*/'" <<< "$output"
}

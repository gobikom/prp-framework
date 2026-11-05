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
  # Stream pin (bats `run` merges them, which is what hid the bug): the warn
  # is log_warn output and must be on stderr only.
  bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init >stdout.log 2>stderr.log
  grep -q "could not scan 'src/main/java/'" stderr.log
  ! grep -q "could not scan 'src/main/java/'" stdout.log
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

# ─── Invariant M (r4 of #245, re-route of #249): one marker predicate ───
# Every M case builds PROJECT.md by hand so only the marker shape varies.

m_body() { # prints a marker-bearing prelude: all five sections, a col-1 BEGIN,
  # and NO real END — M cases append their own body lines
  cat <<'PRE'
# Proj

## What & Why
x

## Problem
x

## Requirements
x

## Key Decisions
x

## Constraints
x

<!-- AUTO-GEN:BEGIN — Do not edit manually. Run: gen-ai-context.sh --update -->
PRE
}

@test "M0: only autogen_span/autogen_begin_count match AUTO-GEN" {
  # Structural tripwire on the three line tools: a raw AUTO-GEN match in any
  # grep/sed/awk command outside the two helpers turns this red. It does NOT
  # pin case/[[ ]]/perl/rg or indirected matchers — the invariant itself is
  # the plan's; this test only guards its grep/sed/awk surface.
  local script="$REPO_ROOT/scripts/gen-ai-context.sh"
  local s1 e1 s2 e2
  s1=$(grep -n '^autogen_span() {' "$script" | cut -d: -f1)
  e1=$(awk -v s="$s1" 'NR>s && /^}/{print NR; exit}' "$script")
  s2=$(grep -n '^autogen_begin_count() {' "$script" | cut -d: -f1)
  e2=$(awk -v s="$s2" 'NR>s && /^}/{print NR; exit}' "$script")
  [ -n "$s1" ] && [ -n "$e1" ] && [ -n "$s2" ] && [ -n "$e2" ]
  local bad=0 ln
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    if ! { [ "$ln" -ge "$s1" ] && [ "$ln" -le "$e1" ]; } && ! { [ "$ln" -ge "$s2" ] && [ "$ln" -le "$e2" ]; }; then
      echo "raw AUTO-GEN match outside the helpers at line $ln"
      bad=1
    fi
  done < <(grep -nE '(grep|sed|awk)[^#]*AUTO-GEN' "$script" | cut -d: -f1)
  [ "$bad" -eq 0 ]
}

@test "M1-REPLAY: prose AUTO-GEN:END mention cannot defeat the update guard (C-1)" {
  { m_body
    printf '%s\n' 'The block used to end at AUTO-GEN:END (quoted in prose).'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do printf 'body line %d\n' "$i"; done
  } > PROJECT.md
  cp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 1 ]
  grep -q 'refusing to update' <<< "$output"
  ! grep -q 'Updated AUTO-GEN sections' <<< "$output"
  cmp PROJECT.md PROJECT.md.copy
}

@test "M1-CONTROL: the same file with a real END updates and keeps the body" {
  { m_body
    printf '%s\n' '<!-- AUTO-GEN:END -->'
    printf '%s\n' 'The block used to end at AUTO-GEN:END (quoted in prose).'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do printf 'body line %d\n' "$i"; done
  } > PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  grep -q 'Updated AUTO-GEN sections' <<< "$output"
  grep -q 'body line 14' PROJECT.md
  grep -qF 'AUTO-GEN:END (quoted in prose)' PROJECT.md
}

@test "M2: the prose-mention file fails --check with END missing, never up-to-date (I-1)" {
  { m_body
    printf '%s\n' 'The block used to end at AUTO-GEN:END (quoted in prose).'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do printf 'body line %d\n' "$i"; done
  } > PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'END missing' <<< "$output"
  ! grep -q 'up-to-date' <<< "$output"
}

@test "M3: END mid-line in prose refuses update and reports stale" {
  { m_body
    printf '%s\n' 'see <!-- AUTO-GEN:END --> above, in prose'
    printf '%s\n' 'body line'
  } > PROJECT.md
  cp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 1 ]
  cmp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'STALE' <<< "$output"
}

@test "M4: END before BEGIN fails closed" {
  { printf '%s\n' '# Proj' '' '<!-- AUTO-GEN:END -->'
    m_body
    printf '%s\n' 'body line'
  } > PROJECT.md
  cp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 1 ]
  cmp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'STALE' <<< "$output"
}

@test "M5: END with trailing spaces fails closed" {
  # The generator always writes the exact line '<!-- AUTO-GEN:END -->', so a
  # spaced variant is damage, not a marker — refuse rather than guess.
  { m_body
    printf '%s\n' '<!-- AUTO-GEN:END --> '
    printf '%s\n' 'body line'
  } > PROJECT.md
  cp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 1 ]
  cmp PROJECT.md PROJECT.md.copy
}

@test "M6: indented BEGIN is no BEGIN — rc 1 paths" {
  { printf '%s\n' '# Proj' '' '  <!-- AUTO-GEN:BEGIN — indented -->'
    printf '%s\n' 'body line'
  } > PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  grep -q 'No AUTO-GEN markers' <<< "$output"
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 0 ]
  grep -q 'markers missing' <<< "$output"
}

@test "M7: prose AUTO-GEN:BEGIN mention is no marker — rc 1 paths" {
  { printf '%s\n' '# Proj' '' 'Docs mention AUTO-GEN:BEGIN in a sentence.'
    printf '%s\n' 'body line'
  } > PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  grep -q 'No AUTO-GEN markers' <<< "$output"
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 0 ]
  grep -q 'markers missing' <<< "$output"
}

@test "M8: two real blocks — update keeps the second, check reports stale" {
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init
  [ "$status" -eq 0 ]
  cat >> PROJECT.md <<'EOF'
<!-- AUTO-GEN:BEGIN — duplicate -->
- **Stack:** Whatever
<!-- AUTO-GEN:END -->
EOF
  cp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  grep -q 'extra AUTO-GEN block' <<< "$output"
  grep -qF '<!-- AUTO-GEN:BEGIN — duplicate -->' PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'extra AUTO-GEN block' <<< "$output"
}

# ─── I-1 (fix of #250 R1): rc 3 cannot-read — an unreadable PROJECT.md is never the rc-1 "no markers" branch (root skips: chmod 000 stays readable) ───

init_ok() { run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init; [ "$status" -eq 0 ]; }

@test "M-UNREADABLE: unreadable PROJECT.md is rc 3 — all three modes exit 1, none claims markers or freshness; readable marker-less control still rc 1" {
  if [ "$(id -u)" = "0" ]; then skip "running as root — chmod 000 stays readable, rc 3 not reachable via chmod"; fi
  init_ok
  chmod 000 PROJECT.md
  bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update >u.out 2>u.err && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'cannot read' u.err
  ! grep -q 'Skipping update' u.out
  bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check >c.out 2>c.err && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'cannot read' c.err
  ! grep -q 'up-to-date' c.out
  bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check --quiet >q.out 2>q.err && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
  [ ! -s q.out ]
  grep -q 'cannot read' q.err
  chmod 644 PROJECT.md
  { printf '%s\n' '# Proj' ''; printf '%s\n' 'body line'; } > PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  grep -q 'No AUTO-GEN markers' <<< "$output"
}

@test "M-CRLF: an END with a trailing carriage return is no END — update refuses (rc 2), check reports it" {
  { m_body
    printf '<!-- AUTO-GEN:END -->\r\n'
    printf '%s\n' 'body line'
  } > PROJECT.md
  cp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 1 ]
  grep -q 'refusing to update' <<< "$output"
  cmp PROJECT.md PROJECT.md.copy
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'END missing' <<< "$output"
}

@test "M-EMPTY-NUL: empty and NUL-bearing marker-less files are the rc-1 issue path, not fatal (decision: no readable BEGIN line reads as marker-less; never aliases to rc 3)" {
  : > PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  grep -q 'No AUTO-GEN markers' <<< "$output"
  : > PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 0 ]
  grep -q 'markers missing' <<< "$output"
  printf 'x' > PROJECT.md; head -c 1 /dev/zero >> PROJECT.md; printf 'y\n' >> PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  grep -q 'No AUTO-GEN markers' <<< "$output"
}

@test "M-BEGIN1: BEGIN at line 1 updates, converges to a stable shape, never loses the tail" {
  { printf '%s\n' '<!-- AUTO-GEN:BEGIN — Do not edit manually. Run: gen-ai-context.sh --update -->'
    printf '%s\n' '- **Stack:** Old'
    printf '%s\n' '<!-- AUTO-GEN:END -->'
    printf '%s\n' 'body line'
  } > PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  # before="" still echoes one blank line: BEGIN converges to line 2 and stays
  [ "$(sed -n 2p PROJECT.md)" = '<!-- AUTO-GEN:BEGIN — Do not edit manually. Run: gen-ai-context.sh --update -->' ]
  grep -q 'body line' PROJECT.md
  cp PROJECT.md P2
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  cmp P2 PROJECT.md
}

@test "R-BACKUP-PRESENT: a backup-pattern entry in the first block warns and goes stale" {
  init_ok
  sed -i '/<!-- AUTO-GEN:END -->/i | Legacy | `old/` |' PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 1 ]
  grep -q "matches backup-dir skip pattern" <<< "$output"
}

@test "R-BACKUP-SECOND-BLOCK: a backup entry in a later block never warns (scan reads the first block)" {
  init_ok
  cat >> PROJECT.md <<'EOF'
<!-- AUTO-GEN:BEGIN — duplicate -->
| Legacy | `old/` |
<!-- AUTO-GEN:END -->
EOF
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -ne 0 ]
  grep -q 'extra AUTO-GEN block' <<< "$output"
  ! grep -q 'matches backup-dir skip pattern' <<< "$output"
}

@test "R-BACKUP-PROSE: a backup-style path in body prose never warns" {
  init_ok
  printf '%s\n' 'see `old/` for legacy notes' >> PROJECT.md
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check
  [ "$status" -eq 0 ]
  ! grep -q 'matches backup-dir skip pattern' <<< "$output"
}

@test "W-CONTRACT: --update refreshes Stack inside the span, keeps prelude and tail byte-identical, second run is a no-op" {
  init_ok
  printf '%s\n' 'Trailer line below the block.' >> PROJECT.md
  sed -i '/<!-- AUTO-GEN:BEGIN/,/<!-- AUTO-GEN:END -->/{s/^- \*\*Stack:\*\* .*/- **Stack:** Stale-Stack/}' PROJECT.md
  B=$(grep -n '^<!-- AUTO-GEN:BEGIN' PROJECT.md | head -1 | cut -d: -f1)
  E=$(grep -nxF '<!-- AUTO-GEN:END -->' PROJECT.md | head -1 | cut -d: -f1)
  sed -n "1,$((B - 1))p" PROJECT.md > pre.expected
  sed -n "$((E + 1)),\$p" PROJECT.md > tail.expected
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  B2=$(grep -n '^<!-- AUTO-GEN:BEGIN' PROJECT.md | head -1 | cut -d: -f1)
  E2=$(grep -nxF '<!-- AUTO-GEN:END -->' PROJECT.md | head -1 | cut -d: -f1)
  sed -n "${B2},${E2}p" PROJECT.md | grep -qF -- '- **Stack:** Node.js'
  cmp <(sed -n "1,$((B2 - 1))p" PROJECT.md) pre.expected
  cmp <(sed -n "$((E2 + 1)),\$p" PROJECT.md) tail.expected
  cp PROJECT.md P2
  run bash "$REPO_ROOT/scripts/gen-ai-context.sh" --update
  [ "$status" -eq 0 ]
  cmp P2 PROJECT.md
}

@test "W-INIT-SCAN-WARN: init-path map-scan failure warns on stderr only" {
  if [ "$(id -u)" = "0" ]; then skip "running as root — chmod 000 stays readable"; fi
  mkdir -p locked
  echo 'x=1' > locked/a.py
  chmod 000 locked
  bash "$REPO_ROOT/scripts/gen-ai-context.sh" --init >stdout.log 2>stderr.log
  [ -f PROJECT.md ]
  grep -q "could not scan 'locked/'" stderr.log
  ! grep -q "could not scan 'locked/'" stdout.log
}

# ─── Invariant W (r4 of #245): every warning reaches stderr ───

@test "W1: missing-section warning is on stderr, not stdout" {
  init_ok
  sed -i '/^## Key Decisions$/d' PROJECT.md
  bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check >stdout.log 2>stderr.log && rc=0 || rc=$?
  [ "$rc" -eq 0 ]
  grep -q 'Key Decisions section MISSING' stderr.log
  ! grep -q 'Key Decisions section MISSING' stdout.log
}

@test "W2: --quiet emits no warning on either stream" {
  init_ok
  sed -i '/^## Key Decisions$/d' PROJECT.md
  bash "$REPO_ROOT/scripts/gen-ai-context.sh" --check --quiet >stdout.log 2>stderr.log && rc=0 || rc=$?
  [ "$rc" -eq 0 ]
  [ ! -s stderr.log ]
  ! grep -q 'section MISSING' stdout.log
}

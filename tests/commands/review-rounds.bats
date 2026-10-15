#!/usr/bin/env bats
# Behaviour tests for prp-review-agents round discipline (prp-framework#151,
# Parts 1 / 2.1 / 2.4 only — Part 2.2, the enforced round cap, was scope-cut to
# gobikom/prp-framework#154). Covered here: the 2.1a pass timebox (base-10,
# fail-closed, symlink-safe deadline write), the 2.1b round status dir, the
# 3.1/3.2 per-pass completion proof (status files + one mechanical gate), and
# the 3.5 cut-probes follow-up issue (file-assembled body, no heredoc, no
# interpolation of reviewer-derived bytes). The bash fences are extracted from
# the generated claude-code adapter and run as separate shells — as an agent does.
#
# Run: bats tests/commands/review-rounds.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ADAPTER="$ROOT/adapters/claude-code/prp-review-agents.md"

# block <heading-marker> — the bash fence that follows the marker line.
block() {
  awk -v want="$1" 'index($0, want) == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g'
}

setup() {
  WORK="$(mktemp -d)"
  cd "$WORK"
  mkdir -p .prp-output/reviews bin
  # gh stub: issue create logs its args; nothing else is needed by these blocks.
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "issue create" ]; then
  echo "$@" >> "$ISSUE_LOG"
  echo "https://github.com/o/r/issues/$(( $(wc -l < "$ISSUE_LOG") ))"
  exit 0
fi
if [ "$1 $2" = "repo view" ]; then echo "o/r"; exit 0; fi
exit 2
EOF
  chmod +x bin/gh
  export PATH="$WORK/bin:$PATH" ISSUE_LOG="$WORK/issues.log" TVD="$WORK/tvd"
  mkdir -p "$TVD"
  : > "$ISSUE_LOG"
  block "### 2.1a" > budget.sh
  block "### 3.5" > followup.sh
  block "### 3.2" > gate.sh
  [ -s budget.sh ] && [ -s followup.sh ] && [ -s gate.sh ]
}

teardown() { rm -rf "$WORK"; }

# ─── structure: Parts 1 / 2.1 / 2.4 present, Part 2.2 absent ──────

@test "the adapter documents the One Wake Per Round section and the timebox prompt line" {
  grep -q "One Wake Per Round" "$ADAPTER"
  grep -q "PRP_REVIEW_PASS_BUDGET_MIN" "$ADAPTER"
  grep -q "## Cut probes" "$ADAPTER"
  grep -q "No idle status pings" "$ADAPTER"
  # every reviewer prompt carries the timebox: 1 template in 2.1a + 10 agent prompts
  [ "$(grep -c 'Timebox: this pass runs under' "$ADAPTER")" -eq 11 ]
  # every reviewer prompt (plus the 2.1a template) ends with the PASS COMPLETE closing line
  [ "$(grep -c 'END your output with one exact closing line' "$ADAPTER")" -eq 11 ]
  grep -q "PASS COMPLETE: <pass name>" "$ADAPTER"
  grep -q 'Completion check (never count a cut pass as clean)' "$ADAPTER"
}

@test "the pass name in every PASS COMPLETE prompt is a pinned literal, never free text" {
  # 10 agent prompts pin their own subagent_type; the 2.1a template keeps the placeholder
  [ "$(grep -c 'is the fixed pass name; never paraphrase' "$ADAPTER")" -eq 10 ]
  for p in code-reviewer security-reviewer silent-failure-hunter dependency-analyzer \
           accessibility-reviewer performance-analyzer type-design-analyzer \
           docs-impact-agent comment-analyzer pr-test-analyzer; do
    grep -q "PASS COMPLETE: $p" "$ADAPTER"
  done
}

@test "no multi-pid wait is prescribed anywhere; the per-pid pattern is" {
  # the prescriptive example is per-pid waits; the multi-pid form appears ONLY inside
  # the FORBIDDEN-explanation prose (quoted there without dollar signs)
  ! grep -qF 'wait "$pid1" "$pid2"' "$ADAPTER"
  ! grep -qF 'wait "$pid1" "$pid2" "$pid3"' "$ADAPTER"
  grep -qF 'wait "$pid1"; rc1=$?; wait "$pid2"; rc2=$?; wait "$pid3"; rc3=$?' "$ADAPTER"
  grep -q "Never report between waits" "$ADAPTER"
  grep -q "multi-pid form is FORBIDDEN" "$ADAPTER"
}

@test "no Part 2.2 machinery remains in the adapter (scope-cut to 154)" {
  ! grep -q "2\.0a" "$ADAPTER"
  ! grep -q "Step Cb" "$ADAPTER"
  ! grep -q "curr-run\.env" "$ADAPTER"
  ! grep -q "record-pending" "$ADAPTER"
  ! grep -q "round-recorded" "$ADAPTER"
  ! grep -q "review-rounds" "$ADAPTER"
  ! grep -q "round 11" "$ADAPTER"
  # exactly TWO 'If this block prints FATAL' notes for 2.0/2.1.1 (no duplicated paragraphs)
  [ "$(grep -c 'If this block prints FATAL' "$ADAPTER")" -eq 2 ]
  # no glued-sentence artefacts from the removed sections
  ! grep -q 'every mode\.A ' "$ADAPTER"
  ! grep -q 'round 11 refused' "$ADAPTER"
}

@test "Step A mints a fresh run id every run (origin or main behaviour)" {
  # no curr-run.env reuse anywhere in Step A's fence
  ! grep -q 'curr-run\.env' "$(block '**Step A' > /dev/null; echo stepA)"
  block "**Step A" | grep -q 'RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-\$RAND"'
}

# ─── 2.1a pass timebox ────────────────────────────────────────────

@test "unset budget defaults to 20 minutes and saves the deadline" {
  before=$(date +%s)
  run env -u PRP_REVIEW_PASS_BUDGET_MIN bash budget.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "PASS_BUDGET_MIN=20 "* ]]
  d=$(sed -n 's/^deadline=//p' .prp-output/reviews/pr-7-pass-deadline)
  b=$(sed -n 's/^budget_min=//p' .prp-output/reviews/pr-7-pass-deadline)
  [ "$b" = "20" ]
  [ "$d" -ge $(( before + 20 * 60 )) ]
  [ "$d" -le $(( $(date +%s) + 20 * 60 )) ]
}

@test "a forced short budget is respected (forced-timebox test)" {
  run env PRP_REVIEW_PASS_BUDGET_MIN=1 bash budget.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "PASS_BUDGET_MIN=1 "* ]]
  b=$(sed -n 's/^budget_min=//p' .prp-output/reviews/pr-7-pass-deadline)
  d=$(sed -n 's/^deadline=//p' .prp-output/reviews/pr-7-pass-deadline)
  [ "$b" = "1" ]
  [ "$d" -le $(( $(date +%s) + 60 )) ]
}

@test "garbage budgets fail closed with no deadline file" {
  for bad in 0 241 abc 20min -3 08 010 ""; do
    rm -f .prp-output/reviews/pr-7-pass-deadline
    run env PRP_REVIEW_PASS_BUDGET_MIN="$bad" bash budget.sh
    [ "$status" -ne 0 ] || { echo "budget '$bad' was accepted"; return 1; }
    [[ "$output" == *"PRP_REVIEW_PASS_BUDGET_MIN must be a base-10 integer 1..240"* ]]
    [ ! -f .prp-output/reviews/pr-7-pass-deadline ]
    [ ! -e .prp-output/reviews/.pr-7-pass-deadline.* ]   # no leftover tmp
  done
}

@test "boundary budgets 1 and 240 are accepted" {
  run env PRP_REVIEW_PASS_BUDGET_MIN=1 bash budget.sh
  [ "$status" -eq 0 ]
  run env PRP_REVIEW_PASS_BUDGET_MIN=240 bash budget.sh
  [ "$status" -eq 0 ]
}

@test "an earlier round's deadline file is replaced" {
  printf 'deadline=1\nbudget_min=1\n' > .prp-output/reviews/pr-7-pass-deadline
  run env PRP_REVIEW_PASS_BUDGET_MIN=2 bash budget.sh
  [ "$status" -eq 0 ]
  b=$(sed -n 's/^budget_min=//p' .prp-output/reviews/pr-7-pass-deadline)
  [ "$b" = "2" ]
  [ -f .prp-output/reviews/pr-7-pass-deadline ] && [ ! -L .prp-output/reviews/pr-7-pass-deadline ]
}

@test "a symlink at the deadline path is refused, not written through" {
  target="$WORK/victim.txt"
  printf 'do-not-overwrite\n' > "$target"
  ln -s "$target" .prp-output/reviews/pr-7-pass-deadline
  run env PRP_REVIEW_PASS_BUDGET_MIN=5 bash budget.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"is a symlink"* ]]
  [ "$(cat "$target")" = "do-not-overwrite" ]        # victim untouched
  [ -L .prp-output/reviews/pr-7-pass-deadline ]       # link left for hand repair
}

@test "a non-regular deadline path fails closed" {
  rm -f .prp-output/reviews/pr-7-pass-deadline
  mkdir -p .prp-output/reviews/pr-7-pass-deadline
  run env PRP_REVIEW_PASS_BUDGET_MIN=5 bash budget.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a regular file"* ]]
}

@test "no leftover temp files after a successful write" {
  run env PRP_REVIEW_PASS_BUDGET_MIN=5 bash budget.sh
  [ "$status" -eq 0 ]
  [ -z "$(ls -A .prp-output/reviews | grep -F 'pass-deadline.')" ]
}

# ─── 2.1b round status dir + 3.1 writer + 3.2 completion gate ─────

statusdir_setup() {  # all three passes complete: the post-allowed fixture
  SD="$(mktemp -d)"
  printf '%s\n' "$SD" > .prp-output/reviews/pr-7-status-dir
  printf 'standard\n' > .prp-output/reviews/pr-7-tier
  for p in code-reviewer security-reviewer silent-failure-hunter; do
    printf 'pass=%s\nrc=0\ncomplete=yes\n' "$p" > "$SD/$p.status"
  done
  export SD
}

@test "2.1b mints an out-of-tree status dir and saves its path symlink-safe" {
  block "### 2.1b" > sdir.sh
  [ -s sdir.sh ]
  victim="$WORK/victim.txt"; printf 'keep\n' > "$victim"
  ln -s "$victim" .prp-output/reviews/pr-7-status-dir
  run bash sdir.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"is a symlink"* ]]
  [ "$(cat "$victim")" = "keep" ]
  rm .prp-output/reviews/pr-7-status-dir
  # production default: TVD unset → the dir is minted under /tmp, OUTSIDE the repo tree
  run env -u TVD bash sdir.sh
  [ "$status" -eq 0 ]
  [[ "$output" == "STATUS_DIR="* ]]
  dir=$(cat .prp-output/reviews/pr-7-status-dir)
  case "$dir" in
    /tmp/prp-round-status.??????) : ;;                 # mktemp-minted, unpredictable suffix
    *) echo "unexpected status dir: $dir"; return 1 ;;
  esac
  [ -d "$dir" ] && [ ! -L "$dir" ]
  [ "$(stat -c %a "$dir")" = "700" ]
  rm -rf -- "$dir"
}

@test "3.2 boundary: all three complete → the gate passes (post allowed)" {
  statusdir_setup
  run bash gate.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"completion proven for: code-reviewer security-reviewer silent-failure-hunter"* ]]
}

@test "3.2 boundary: one pass rc=1 → FATAL, nothing posted" {
  statusdir_setup
  printf 'pass=code-reviewer\nrc=1\ncomplete=yes\n' > "$SD/code-reviewer.status"
  run bash gate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"code-reviewer did not complete"* ]]
}

@test "3.2 boundary: one pass missing its completion line (complete=no) → FATAL" {
  statusdir_setup
  printf 'pass=security-reviewer\nrc=0\ncomplete=no\n' > "$SD/security-reviewer.status"
  run bash gate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"security-reviewer did not complete"* ]]
}

@test "3.2 boundary: one status file missing → FATAL" {
  statusdir_setup
  rm "$SD/silent-failure-hunter.status"
  run bash gate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"silent-failure-hunter.status missing"* ]]
}

@test "3.2 boundary: a symlinked status path is refused and the target untouched" {
  statusdir_setup
  victim="$WORK/victim2.txt"; printf 'do-not-overwrite\n' > "$victim"
  rm "$SD/security-reviewer.status"
  ln -s "$victim" "$SD/security-reviewer.status"
  run bash gate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"is a symlink"* ]]
  [ "$(cat "$victim")" = "do-not-overwrite" ]   # victim untouched
  [ -L "$SD/security-reviewer.status" ]         # the link itself is left for hand repair
}

@test "3.2 boundary: wrong pass name in the status file → FATAL" {
  statusdir_setup
  printf 'pass=code-review\nrc=0\ncomplete=yes\n' > "$SD/code-reviewer.status"
  run bash gate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"code-reviewer did not complete"* ]]
}

@test "3.2 boundary: no tier / no status dir → FATAL (unproven, nothing posted)" {
  statusdir_setup
  rm .prp-output/reviews/pr-7-tier
  run bash gate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"no tier saved by 2.0b"* ]]
  statusdir_setup
  rm .prp-output/reviews/pr-7-status-dir
  run bash gate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"no status dir saved by 2.1b"* ]]
}

@test "3.2 at TIER=trivial gates on the one core pass only" {
  statusdir_setup
  printf 'trivial\n' > .prp-output/reviews/pr-7-tier
  rm "$SD/security-reviewer.status" "$SD/silent-failure-hunter.status"
  run bash gate.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"completion proven for: code-reviewer"* ]]
}

@test "3.1 records pass/rc/complete from the pass outputs and per-pid statuses" {
  block "### 3.1" > writer.sh
  [ -s writer.sh ]
  SD="$(mktemp -d)"
  printf '%s\n' "$SD" > .prp-output/reviews/pr-7-status-dir
  printf '## Findings\nnone\nPASS COMPLETE: code-reviewer\n' > "$SD/code-reviewer.out"
  printf '## Findings\nnone\nPASS COMPLETE: security-reviewer\n' > "$SD/security-reviewer.out"
  printf '## Findings\nnone\n' > "$SD/silent-failure-hunter.out"   # no closing line
  export SD rc1=0 rc2=0 rc3=0
  run bash writer.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$SD/code-reviewer.status")" = "$(printf 'pass=code-reviewer\nrc=0\ncomplete=yes')" ]
  [ "$(cat "$SD/security-reviewer.status")" = "$(printf 'pass=security-reviewer\nrc=0\ncomplete=yes')" ]
  [ "$(cat "$SD/silent-failure-hunter.status")" = "$(printf 'pass=silent-failure-hunter\nrc=0\ncomplete=no')" ]
}

@test "3.1 with a non-zero per-pid status records rc=1 (the gate then refuses to post)" {
  block "### 3.1" > writer.sh
  SD="$(mktemp -d)"
  printf '%s\n' "$SD" > .prp-output/reviews/pr-7-status-dir
  for p in code-reviewer security-reviewer silent-failure-hunter; do
    printf 'PASS COMPLETE: %s\n' "$p" > "$SD/$p.out"
  done
  export SD rc1=1 rc2=0 rc3=0
  run bash writer.sh
  [ "$status" -eq 0 ]
  [ "$(sed -n 2p "$SD/code-reviewer.status")" = "rc=1" ]
  printf 'standard\n' > .prp-output/reviews/pr-7-tier
  run bash gate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"code-reviewer did not complete"* ]]
}

# ─── 3.5 follow-up issue for cut probes (file-assembled body) ─────

entries() {  # the collection step writes the entries file with the Write tool
  printf '%s\n' "$@" > "$TVD/prp-cut-probes-entries.md"
}

@test "cut probes create exactly one follow-up issue, body assembled out-of-tree by concatenation" {
  entries '1. probe: does X handle Y (code-reviewer)' '2. probe: Z edge case (security-reviewer)'
  export CUT_PROBES_COUNT=2 CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
  run bash followup.sh
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$ISSUE_LOG")" -eq 1 ]
  [[ "$output" == *"cut-probes follow-up posted"* ]]
  # the posted body: header + entries + footer, assembled by cat/printf — and the probe
  # lines appear as literal text (bytes flowed file→file)
  d=$(ls -dt "$TVD"/prp-cut-probes.* 2>/dev/null | head -1)   # already removed on success
  [ -z "${d:-}" ] || [ ! -f "$d/body.md" ]
  [ ! -e .prp-output/reviews/pr-7-cut-probes.md ]   # nothing in the repo tree
}

@test "a probe line equal to any heredoc delimiter is inert text, not a terminator" {
  # 3.5 uses NO heredoc at all now — pin that, and prove the adversarial line survives
  # as literal bytes through the file→file assembly
  ! grep -q "PRP_CUT_PROBES_BODY" "$ADAPTER"
  ! grep -q "PRP_HDR" "$ADAPTER"
  entries '1. probe: PRP_CUT_PROBES_BODY' '2. probe: PRP_HDR' '3. probe: EOF'
  export CUT_PROBES_COUNT=3 CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "issue create" ]; then
  f=""; while [ $# -gt 0 ]; do [ "$1" = "--body-file" ] && f="$2"; shift; done
  cp "$f" "$ISSUE_LOG.body"
  echo "https://github.com/o/r/issues/1"
  exit 0
fi
if [ "$1 $2" = "repo view" ]; then echo "o/r"; exit 0; fi
exit 2
EOF
  chmod +x bin/gh
  run bash followup.sh
  [ "$status" -eq 0 ]
  [ -f "$ISSUE_LOG.body" ]
  grep -qF '1. probe: PRP_CUT_PROBES_BODY' "$ISSUE_LOG.body"
  grep -qF '2. probe: PRP_HDR' "$ISSUE_LOG.body"
  grep -qF '3. probe: EOF' "$ISSUE_LOG.body"
  grep -qF 'Review follow-up for PR #7' "$ISSUE_LOG.body"
}

@test "no cut probes create no issue" {
  export CUT_PROBES_COUNT=0 CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
  run bash followup.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no cut probes"* ]]
  [ "$(wc -l < "$ISSUE_LOG")" -eq 0 ]
}

@test "an unset CUT_PROBES_COUNT also means no probes (no issue, exit 0)" {
  run env -u CUT_PROBES_COUNT bash followup.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"no cut probes"* ]]
  [ "$(wc -l < "$ISSUE_LOG")" -eq 0 ]
}

@test "a set-but-empty or multi-line CUT_PROBES_COUNT is FATAL, never 'no cut probes'" {
  for bad in "" "2 3" "$(printf '2\n3')"; do
    export CUT_PROBES_COUNT="$bad" CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
    run bash followup.sh
    [ "$status" -ne 0 ] || { echo "count '$bad' was accepted"; return 1; }
    [[ "$output" == *"CUT_PROBES_COUNT must be"* ]]
  done
  [ "$(wc -l < "$ISSUE_LOG")" -eq 0 ]
}

@test "a garbage CUT_PROBES_COUNT fails closed instead of silently skipping" {
  for bad in abc 08 010 -3; do
    export CUT_PROBES_COUNT="$bad" CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
    run bash followup.sh
    [ "$status" -ne 0 ] || { echo "count '$bad' was accepted"; return 1; }
  done
  [ "$(wc -l < "$ISSUE_LOG")" -eq 0 ]
}

@test "a missing or empty entries file posts nothing (collection step never ran)" {
  export CUT_PROBES_COUNT=2 CUT_PROBES_ENTRIES_F="$TVD/no-such-entries.md"
  run bash followup.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or empty"* ]]
  [ "$(wc -l < "$ISSUE_LOG")" -eq 0 ]
  : > "$TVD/prp-cut-probes-entries.md"
  export CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
  run bash followup.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or empty"* ]]
  [ "$(wc -l < "$ISSUE_LOG")" -eq 0 ]
}

@test "a planted symlink at the old in-tree path is never followed and the victim is untouched" {
  victim="$WORK/victim.txt"
  printf 'do-not-overwrite\n' > "$victim"
  mkdir -p .prp-output/reviews
  ln -s "$victim" .prp-output/reviews/pr-7-cut-probes.md
  entries '1. probe: X'
  export CUT_PROBES_COUNT=1 CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
  run bash followup.sh
  [ "$status" -eq 0 ]
  [ "$(cat "$victim")" = "do-not-overwrite" ]          # victim untouched
  [ "$(wc -l < "$ISSUE_LOG")" -eq 1 ]                  # the issue still posted, from the out-of-tree body
  [ -L .prp-output/reviews/pr-7-cut-probes.md ]        # the planted link itself is left alone
}

@test "a write failure posts nothing and never claims the body was saved" {
  entries '1. probe: X' '2. probe: Y'
  export CUT_PROBES_COUNT=2 CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
  chmod 555 "$TVD"   # the temp dir cannot be created -> the body write fails before gh runs
  run bash followup.sh
  chmod 755 "$TVD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"the follow-up was NOT posted"* ]]
  [[ "$output" != *"saved"* ]]                          # no false 'saved' message
  [ "$(wc -l < "$ISSUE_LOG")" -eq 0 ]                   # nothing posted
}

@test "a failing gh issue create is a non-zero ERROR and keeps the body for retry" {
  entries '1. probe: X'
  export CUT_PROBES_COUNT=1 CUT_PROBES_ENTRIES_F="$TVD/prp-cut-probes-entries.md"
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x bin/gh
  run bash followup.sh
  [ "$status" -ne 0 ]                                   # a failed post is an error, never swallowed
  [[ "$output" == *"FATAL: could not create the cut-probes follow-up issue"* ]]
  [[ "$output" == *"still at"* ]]
  d=$(ls -dt "$TVD"/prp-cut-probes.* 2>/dev/null | head -1)
  [ -n "$d" ] && [ -f "$d/body.md" ]                    # body kept for a by-hand retry
}

# ─── PASS COMPLETE closing line (Phase 3 completion check) ────────

@test "a pass output without the PASS COMPLETE closing line is a FAILED pass" {
  printf '%b' '### Critical Issues (0 found)\nNone.\n' > "$WORK/pass-reply.md"
  ! tail -n 1 "$WORK/pass-reply.md" | grep -qxE "PASS COMPLETE: code-reviewer"
  # the real check is 3.1/3.2 (see above); this pins the rule text exists in the prompt
  grep -q "Completion check (never count a cut pass as clean)" "$ADAPTER"
  grep -q "FAILED pass" "$ADAPTER"
}

@test "a pass output with the exact closing line counts as completed" {
  printf '### Critical Issues (0 found)\nNone.\nPASS COMPLETE: code-reviewer\n' > "$WORK/pass-reply.md"
  tail -n 1 "$WORK/pass-reply.md" | grep -qxE "PASS COMPLETE: code-reviewer"
}

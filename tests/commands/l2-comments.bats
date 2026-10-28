#!/usr/bin/env bats
# Behaviour tests for prp-review-agents --l2-comments (prp-framework#142).
#
# The posting is two bash fences in the claude-code adapter (Step A starts the run and saves its
# values; Step C checks all three bodies, then posts). These tests extract both, stub `gh`, and run
# them as separate shells — as an agent does — with the bodies written in between (Step B).
#
# Run: bats tests/commands/l2-comments.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
source "$ROOT/tests/helpers/fence.bash"
# L2_ADAPTER (prp-framework#151): which of the 7 EXPECTED_FILES this run exercises.
# tests/commands/l2-adapters-matrix.bats sets it to each of the 6 non-claude-code
# files in turn, via a nested bats run, so the whole suite below — not just the
# claude-code-specific checks review-rounds.bats used to carry — runs against
# every adapter. Defaults to claude-code for a plain, unparametrised run.
ADAPTER="$ROOT/${L2_ADAPTER:-adapters/claude-code/prp-review-agents.md}"
HEAD_SHA="0123456789abcdef0123456789abcdef01234567"

step() { # step <A|C> -> the bash fence after "**Step <X>", {NUMBER} filled in
  fence "$ADAPTER" "**Step $1"
}

setup() {
  WORK="$(mktemp -d)"
  cd "$WORK"
  git init -q prp && git -C prp commit -q --allow-empty -m init && git -C prp tag v9.9.9
  mkdir -p prp/scripts && cp -r "$ROOT/scripts/review" prp/scripts/   # what Phase 2.0 and Step C run from the installed framework
  ln -s "$WORK/prp" .prp
  mkdir -p .prp-output/reviews bin
  # gh stub: `pr view` prints $FAKE_HEAD (or fails with GH_FAIL=1); `pr comment` logs the body file, prints a URL
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "pr view" ]; then
  [ -n "${GH_FAIL:-}" ] && exit 1
  shift 2; j=""; while [ $# -gt 0 ]; do [ "$1" = "--json" ] && j="$2"; shift; done
  [ "$j" = "additions,deletions" ] && { printf '%s\n' "${FAKE_TOTAL:-0}"; exit 0; }
  printf '%s\n' "$FAKE_HEAD"; exit 0
fi
if [ "$1 $2" = "api user" ]; then   # the trusted-login lookup (Phase 2.0, unchanged-head author check)
  [ -n "${USER_API_FAIL:-}" ] && exit 1
  printf '{"login":"%s"}\n' "${FAKE_LOGIN:-bot}" | jq -r '.login'
  exit 0
fi
if [ "$1" = "api" ]; then   # the round-cap read (Phase 2.0): last lines of the PR comments
  [ -n "${API_FAIL:-}" ] && exit 1
  # apply the REAL --jq filter from the prompt to comment JSON, as `gh api --paginate --jq` does per page
  filter=""; while [ $# -gt 0 ]; do [ "$1" = "--jq" ] && filter="$2"; shift; done
  [ -n "$filter" ] || exit 1
  if [ -n "${FAKE_COMMENTS_JSON:-}" ]; then jq -r "$filter" "$FAKE_COMMENTS_JSON" || exit 1; exit 0; fi
  # FAKE_COMMENTS = one footer line per comment; wrap each as a multi-line body with a trailing newline
  # user.login matches the "api user" mock's default login ("bot", or $FAKE_LOGIN) so these
  # fixture comments count as trusted by default (prp-framework#228's round-cap/mode-decision
  # author filter); a test exercising the untrusted-author path sets FAKE_COMMENTS_JSON instead.
  [ -n "${FAKE_COMMENTS:-}" ] && jq -R -s --arg login "${FAKE_LOGIN:-bot}" 'split("\n")[:-1] | map({user: {login: $login}, body: ("Reviewed head: x\n\n### Could not verify\nNothing.\n\n" + . + "\n")})' "$FAKE_COMMENTS" | jq -r "$filter"
  exit 0
fi
if [ "$1 $2" = "pr comment" ]; then
  f=""; while [ $# -gt 0 ]; do [ "$1" = "--body-file" ] && f="$2"; shift; done
  [ -n "${FAIL_POST:-}" ] && grep -q "Passes run: $FAIL_POST" "$f" && exit 1
  echo "$f" >> "$WORK_LOG"; echo "https://github.com/o/r/pull/7#issuecomment-$(wc -l < "$WORK_LOG")"; exit 0
fi
exit 2
EOF
  chmod +x bin/gh
  # pr-risk-tier stub (agent-devops#1259): prints $FAKE_TIER (default standard); TIER_FAIL=1 prints
  # "trivial" but exits 1; a set PR_RISK_TIER_GH makes it print standard (callers must scrub it).
  cat > bin/pr-risk-tier <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORK/tier.calls"
[ -n "${PR_RISK_TIER_GH:-}" ] && { echo standard; exit 0; }
[ -n "${TIER_FAIL:-}" ] && { echo trivial; exit 1; }
echo "${FAKE_TIER:-standard}"
EOF
  chmod +x bin/pr-risk-tier
  export PATH="$WORK/bin:$PATH" WORK_LOG="$WORK/posted.log" FAKE_HEAD="$HEAD_SHA" WORK
  : > "$WORK_LOG"
  printf '%s\n' "$HEAD_SHA" > .prp-output/reviews/pr-7-reviewed-head   # what Phase 2.0 saves
  printf 'standard\n' > .prp-output/reviews/pr-7-tier                    # what 2.0b saves (default)
  printf 'full\n\n' > .prp-output/reviews/pr-7-mode                      # what 2.0a saves (default)
  step A > stepA.sh; step C > stepC.sh
  [ -s stepA.sh ] && [ -s stepC.sh ]
}

teardown() { rm -rf "$WORK"; }

# Step B: write a well-formed body for one pass from the saved run values
body() {
  local pass="$1" sfx="" modeline; . .prp-output/reviews/pr-7-l2-run.env   # the test reads its own fixture file
  [ "${TIER:-}" = trivial ] && sfx=" tier=trivial"
  if [ "${MODE:-full}" = delta ]; then modeline="Review-mode: delta $BASE_SHA..$REVIEWED_HEAD_SHA"; else modeline="Review-mode: full"; fi
  printf 'Reviewed head: %s\nPasses run: %s\n%s\n\n### Critical Issues (0 found)\nNone.\n\n### Important Issues (0 found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\nGenerated-by: prp-review-agents v%s run=%s pass=%s%s\n' \
    "$REVIEWED_HEAD_SHA" "$pass" "$modeline" "$PRP_VERSION" "$RUN_ID" "$pass" "$sfx" > ".prp-output/reviews/pr-7-l2-$pass.md"
}

start() { run env -u REVIEWED_HEAD_SHA -u L2_COMMENTS bash stepA.sh; }   # a fresh shell: nothing inherited
write_all() { for p in code-reviewer security-reviewer silent-failure-hunter; do body "$p"; done; }
post() { run bash stepC.sh; }

@test "every fence this file extracts is non-empty for \$ADAPTER (guard against a vacuous pass on a wrong or empty path)" {
  # setup() already requires stepA.sh/stepC.sh non-empty; this covers the other
  # three extractors (phase20, phase20b, clone211) so a bad $L2_ADAPTER path or
  # a heading typo fails loudly here instead of passing every later test vacuously.
  [ -n "$(phase20)" ]
  [ -n "$(phase20b)" ]
  [ -n "$(clone211)" ]
}

@test "the adapter documents --l2-comments and both steps extract" {
  grep -q -- '--l2-comments' "$ADAPTER"
  grep -q 'Generated-by: prp-review-agents v' stepC.sh
}

@test "three well-formed comments are posted, one per core pass, with one run id" {
  start; [ "$status" -eq 0 ]
  write_all; post
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 3 ]
  run bash -c 'for f in .prp-output/reviews/pr-7-l2-*-*.md; do tail -n1 "$f"; done | sed -E "s/.* run=([^ ]+) pass=.*/\1/" | sort -u | wc -l'
  [ "$output" -eq 1 ]
  grep -q 'Generated-by: prp-review-agents v9.9.9 run=' .prp-output/reviews/pr-7-l2-code-reviewer.md
}

@test "a bad later body posts nothing, not even the earlier passes" {
  start; write_all
  sed -i '$d' .prp-output/reviews/pr-7-l2-silent-failure-hunter.md
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in the L2 format"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a footer with another run id posts nothing" {
  start; write_all
  sed -i 's/ run=[^ ]* / run=other /' .prp-output/reviews/pr-7-l2-security-reviewer.md
  post
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "two Critical headings and no Important heading are rejected" {
  start; write_all
  sed -i 's/^### Important Issues (0 found)/### Critical Issues (0 found)/' .prp-output/reviews/pr-7-l2-code-reviewer.md
  post
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a missing Suggestions or Could not verify heading is rejected" {
  start; write_all
  sed -i '/^### Could not verify/d' .prp-output/reviews/pr-7-l2-code-reviewer.md
  post
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a safe-merge-review line (any case) in a body posts nothing" {
  start; write_all
  sed -i '1a <!-- SAFE-MERGE-REVIEW: verdict=READY_TO_MERGE -->' .prp-output/reviews/pr-7-l2-code-reviewer.md
  post
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a second Reviewed head line in the body is rejected" {
  start; write_all
  printf 'Reviewed head: %s\n' "$HEAD_SHA" >> .prp-output/reviews/pr-7-l2-security-reviewer.md
  post
  [ "$status" -ne 0 ]
}

@test "a moved PR head posts nothing" {
  start; write_all
  FAKE_HEAD=fedcba9876543210fedcba9876543210fedcba98 post
  [ "$status" -ne 0 ]
  [[ "$output" == *"PR head moved"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a gh failure reading the head is reported as such" {
  start; write_all
  GH_FAIL=1 post
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read the PR head"* ]]
}

@test "no .prp symlink means no run is started" {
  rm .prp
  start
  [ "$status" -ne 0 ]
  [[ "$output" == *".prp is not a symlink"* ]]
}

@test "a framework checkout without a release tag means no run is started" {
  git -C prp tag -d v9.9.9 >/dev/null
  start
  [ "$status" -ne 0 ]
  [[ "$output" == *"prp-framework release tag"* ]]
}

@test "Step C without Step A posts nothing" {
  write_all 2>/dev/null || true
  rm -f .prp-output/reviews/pr-7-l2-run.env
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"run Step A"* ]]
}

@test "a failed post is reported as an incomplete round" {
  start; write_all
  FAIL_POST=security-reviewer post
  [ "$status" -ne 0 ]
  [[ "$output" == *"posting the security-reviewer comment failed"* ]]
}

@test "Step A in a fresh shell takes the reviewed head from the Phase 2.0 file" {
  start; [ "$status" -eq 0 ]
  grep -q "^REVIEWED_HEAD_SHA=$HEAD_SHA\$" .prp-output/reviews/pr-7-l2-run.env
}

@test "no saved reviewed head means no run (never re-query the PR head)" {
  rm .prp-output/reviews/pr-7-reviewed-head
  start
  [ "$status" -ne 0 ]
  [[ "$output" == *"no reviewed head saved by Phase 2.0"* ]]
}

@test "Step C cannot be replayed: a second run posts nothing" {
  start; write_all; post
  [ "$status" -eq 0 ]
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"run Step A"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 3 ]
}

@test "a run file from another review (other head) posts nothing" {
  start; write_all
  printf '%s\n' fedcba9876543210fedcba9876543210fedcba98 > .prp-output/reviews/pr-7-reviewed-head
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"not from this review"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "the run file is parsed, never executed" {
  start; write_all
  printf 'touch %s/pwned\n' "$WORK" >> .prp-output/reviews/pr-7-l2-run.env
  post
  [ "$status" -ne 0 ]
  [ ! -e "$WORK/pwned" ]
}

@test "Step A clears an earlier run's bodies" {
  start; write_all
  start
  [ ! -e .prp-output/reviews/pr-7-l2-code-reviewer.md ]
}

phase20() { fence "$ADAPTER" "### 2.0 Capture the Reviewed Head"; }

@test "Phase 2.0 comes before the agents start (2.1.1)" {
  a=$(grep -n '^### 2.0 Capture the Reviewed Head' "$ADAPTER" | cut -d: -f1)
  b=$(grep -n '^### 2.1.1 ' "$ADAPTER" | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

repo_here() { git init -q . && git commit -q --allow-empty -m pr; FAKE_HEAD=$(git rev-parse HEAD); export FAKE_HEAD; }

@test "Phase 2.0 saves the PR head when it is the local HEAD the agents read" {
  phase20 > p20.sh; repo_here
  run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

@test "Phase 2.0 refuses a PR head that is not the local HEAD (no agents, no head file)" {
  phase20 > p20.sh; repo_here
  FAKE_HEAD=fedcba9876543210fedcba9876543210fedcba98 run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not the local HEAD"* ]]
  [ ! -e .prp-output/reviews/pr-7-reviewed-head ]
}

@test "Phase 2.0 ignores a REVIEWED_HEAD_SHA inherited from the environment" {
  phase20 > p20.sh; repo_here
  run env REVIEWED_HEAD_SHA=fedcba9876543210fedcba9876543210fedcba98 bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

@test "Phase 2.0 replaces an earlier round's head file (reused context, Phase 1 skipped)" {
  phase20 > p20.sh; repo_here
  printf '%s\n' fedcba9876543210fedcba9876543210fedcba98 > .prp-output/reviews/pr-7-reviewed-head
  run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

# footers of <n> distinct review runs, three comments each (the last line of each comment)
runs() { local i p; for ((i = 1; i <= $1; i++)); do for p in code-reviewer security-reviewer silent-failure-hunter; do
  printf 'Generated-by: prp-review-agents v9.9.9 run=20261021T%06dZ-%08x pass=%s\n' "$i" "$i" "$p"; done; done; }

@test "Phase 2.0 allows round 6 (five runs on the PR) and saves the head" {
  phase20 > p20.sh; repo_here; runs 5 > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

@test "Phase 2.0 refuses round 7 (six runs) before any head file or agent (default cap is 6)" {
  phase20 > p20.sh; repo_here; runs 6 > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"ROUND-CAP: refused"* ]]
  [[ "$output" == *"round cap — no agents started"* ]]
  [ ! -e .prp-output/reviews/pr-7-reviewed-head ]
}

@test "Phase 2.0 runs the real jq filter over paginated comment JSON" {
  phase20 > p20.sh; repo_here
  # two pages (gh --paginate applies --jq per page): a multi-line body, a plain comment and a CRLF-free footer
  # page1 = runs 1-3 (ids1-3), page2 keeps runs 4-6 (tail skips the 9 lines of ids1-3) -> 6 unique = at cap (default cap is 6)
  # tagged with the default trusted login ("bot") so Phase 2.0's TRUSTED_LOGIN filter
  # (FOOTERS, same as CLEAN_ROWS) keeps these rows instead of silently dropping them
  { runs 3 | jq -R -s 'split("\n")[:-1] | map({user: {login: "bot"}, body: ("review text\nmore\n" + . + "\n")})'
    runs 6 | tail -n +10 | jq -R -s 'split("\n")[:-1] | map({user: {login: "bot"}, body: ("other\n" + . + "\n")}) + [{user: {login: "bot"}, body: "LGTM"}]'; } > c.json
  FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"ROUND-CAP: refused"* ]]
}

@test "Phase 2.0 allows round 6 over paginated comment JSON with ordinary comments" {
  phase20 > p20.sh; repo_here
  # page1 = runs 1-2 (ids1-2), page2 keeps runs 3-5 (tail skips the 6 lines of ids1-2) -> 5 unique = one under cap (default cap is 6)
  # tagged with the default trusted login ("bot"), same reason as the test above
  { runs 2 | jq -R -s 'split("\n")[:-1] | map({user: {login: "bot"}, body: ("text\n" + . + "\n")}) + [{user: {login: "bot"}, body: "LGTM"}, {user: {login: "bot"}, body: "a\nb\nc"}]'
    runs 5 | tail -n +7 | jq -R -s 'split("\n")[:-1] | map({user: {login: "bot"}, body: ("text\n" + . + "\n")})'; } > c.json
  FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

@test "Phase 2.0 refuses on a comment with a null body" {
  phase20 > p20.sh; repo_here
  # tagged with the default trusted login so the TRUSTED_LOGIN filter passes it through
  # to the null-body handling this test actually exercises, instead of dropping it first
  printf '[{"user": {"login": "bot"}, "body": null}]\n' > c.json
  FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [ ! -e .prp-output/reviews/pr-7-reviewed-head ]
}

@test "Phase 2.0 refuses when the PR comments cannot be read" {
  phase20 > p20.sh; repo_here
  API_FAIL=1 run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read the PR comments"* ]]
  [ ! -e .prp-output/reviews/pr-7-reviewed-head ]
}

@test "Phase 2.0 counts a review footer with no well-formed run id as zero (round-guard v6: content never refuses)" {
  phase20 > p20.sh; repo_here
  printf 'Generated-by: prp-review-agents v1 run=oops pass=x\n' > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

@test "Phase 2.0 still refuses round 7 when a malformed footer sits among six runs (it cannot lower R; default cap is 6)" {
  phase20 > p20.sh; repo_here
  { runs 6; printf 'Generated-by: prp-review-agents v1 run=oops pass=x\n'; } > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"ROUND-CAP: refused"* ]]
  [[ "$output" == *"round cap — no agents started"* ]]
  [ ! -e .prp-output/reviews/pr-7-reviewed-head ]
}

@test "Phase 2.0 refuses when .prp is not a symlink to the framework" {
  phase20 > p20.sh; repo_here; rm .prp; mkdir .prp
  run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"round cap not checkable"* ]]
}

@test "Phase 2.0 fails before any agent when the head cannot be captured" {
  phase20 > p20.sh; repo_here
  GH_FAIL=1 run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read the PR head (gh failed) — no agents started"* ]]
  [ ! -e .prp-output/reviews/pr-7-reviewed-head ]
}

# ---- unchanged-head author trust + run completeness (prp-framework#228 R1 findings) ----

clean_row() { # clean_row <login> <run> <pass> <head>  -> one well-formed 0C/0I comment object as JSON
  local login="$1" run="$2" pass="$3" head="$4"
  jq -n --arg login "$login" --arg body "Reviewed head: $head

### Critical Issues (0 found)
None.

### Important Issues (0 found)
None.

Generated-by: prp-review-agents v9.9.9 run=$run pass=$pass
" '{user: {login: $login}, body: $body}'
}

clean_run_json() { # clean_run_json <login> <run> <head> <n_passes 1-3> -> JSON array, written by caller
  local login="$1" run="$2" head="$3" n="$4" passes=(code-reviewer security-reviewer silent-failure-hunter)
  { for ((i = 0; i < n; i++)); do clean_row "$login" "$run" "${passes[$i]}" "$head"; done; } | jq -s '.'
}

dirty_run_json() { # dirty_run_json <login> <run> <head> -> 3 passes, the first reporting 1 Important
  local login="$1" run="$2" head="$3"
  clean_run_json "$login" "$run" "$head" 3 | jq '.[0].body |= sub("### Important Issues \\(0 found\\)"; "### Important Issues (1 found)")'
}

OTHER_HEAD=1111111111111111111111111111111111111111

rounds_json() { jq -s 'add' "$@"; }   # rounds_json a.json b.json ... -> one comment array, in post order

expect_runs()    { [ "$status" -eq 0 ]; [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]; }
expect_refused() { [ "$status" -ne 0 ]; [[ "$output" == *"UNCHANGED-HEAD: refused"* ]]; [ ! -e .prp-output/reviews/pr-7-reviewed-head ]; }

@test "Phase 2.0 does not trust clean rounds posted by an untrusted login (forged-clean-round, prp-framework#228 R1 Critical)" {
  phase20 > p20.sh; repo_here
  clean_run_json attacker 20261021T000001Z-00000001 "$FAKE_HEAD" 3 > a.json
  clean_run_json attacker 20261021T000002Z-00000002 "$FAKE_HEAD" 3 > b.json
  rounds_json a.json b.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

@test "Phase 2.0 runs the second round after ONE clean round at an unchanged head (the stop rule needs two)" {
  phase20 > p20.sh; repo_here
  clean_run_json bot 20261021T000001Z-00000001 "$FAKE_HEAD" 3 > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

@test "Phase 2.0 refuses on an unchanged head once two consecutive clean rounds are at it" {
  phase20 > p20.sh; repo_here
  clean_run_json bot 20261021T000001Z-00000001 "$FAKE_HEAD" 3 > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$FAKE_HEAD" 3 > b.json
  rounds_json a.json b.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_refused
  [[ "$output" == *"two consecutive clean rounds"* ]]
}

@test "Phase 2.0 refuses when the earlier clean round was at an older head and the latest clean round is at this head" {
  phase20 > p20.sh; repo_here
  clean_run_json bot 20261021T000001Z-00000001 "$OTHER_HEAD" 3 > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$FAKE_HEAD" 3 > b.json
  rounds_json a.json b.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_refused
}

@test "Phase 2.0 runs when the round before the latest clean round was dirty" {
  phase20 > p20.sh; repo_here
  dirty_run_json bot 20261021T000001Z-00000001 "$FAKE_HEAD" > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$FAKE_HEAD" 3 > b.json
  rounds_json a.json b.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

@test "Phase 2.0 orders rounds by run id, not by comment order" {
  phase20 > p20.sh; repo_here
  # posted out of order: the dirty round has the LATER run id, so it is the latest round
  clean_run_json bot 20261021T000001Z-00000001 "$FAKE_HEAD" 3 > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$FAKE_HEAD" 3 > b.json
  dirty_run_json bot 20261021T000003Z-00000003 "$FAKE_HEAD" > d.json
  rounds_json d.json a.json b.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

@test "Phase 2.0 runs when the two clean rounds are at another head (the head moved)" {
  phase20 > p20.sh; repo_here
  clean_run_json bot 20261021T000001Z-00000001 "$OTHER_HEAD" 3 > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$OTHER_HEAD" 3 > b.json
  rounds_json a.json b.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

@test "Phase 2.0 runs when the latest round is incomplete, even after two clean rounds" {
  phase20 > p20.sh; repo_here
  clean_run_json bot 20261021T000001Z-00000001 "$FAKE_HEAD" 3 > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$FAKE_HEAD" 3 > b.json
  clean_run_json bot 20261021T000003Z-00000003 "$FAKE_HEAD" 2 > d.json   # only 2 of 3 core passes posted
  rounds_json a.json b.json d.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

@test "Phase 2.0 counts a round with no Reviewed-head line as a not-clean round (it is not skipped)" {
  phase20 > p20.sh; repo_here
  clean_run_json bot 20261021T000001Z-00000001 "$FAKE_HEAD" 3 > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$FAKE_HEAD" 3 | jq '.[].body |= sub("^Reviewed head: [0-9a-f]+\n"; "")' > n.json
  clean_run_json bot 20261021T000003Z-00000003 "$FAKE_HEAD" 3 > b.json
  rounds_json a.json n.json b.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

@test "Phase 2.0 fails open (does not refuse) when the trusted-login lookup itself fails" {
  phase20 > p20.sh; repo_here
  clean_run_json bot 20261021T000001Z-00000001 "$FAKE_HEAD" 3 > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$FAKE_HEAD" 3 > b.json
  rounds_json a.json b.json > c.json
  FAKE_LOGIN=bot USER_API_FAIL=1 FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

@test "Phase 2.0 does not treat a partial run (missing core-pass comment) as clean" {
  phase20 > p20.sh; repo_here
  clean_run_json bot 20261021T000001Z-00000001 "$FAKE_HEAD" 3 > a.json
  clean_run_json bot 20261021T000002Z-00000002 "$FAKE_HEAD" 2 > b.json   # only 2 of 3 core passes posted
  rounds_json a.json b.json > c.json
  FAKE_LOGIN=bot FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  expect_runs
}

clonedir() { ls -d "$PWD"/s/prp-review-clone-*-pr-7 | head -n1; }

@test "2.1.1 leaves unrelated worktrees with missing directories registered (no prune)" {
  phase20 > p20.sh; clone211 > c211.sh; repo_here
  run env -u REVIEWED_HEAD_SHA bash p20.sh; [ "$status" -eq 0 ]
  git worktree add -q --detach "$PWD/other" HEAD && mv other other.moved   # e.g. on an unmounted disk
  mkdir -p s; run env SCRATCHPAD="$PWD/s" bash c211.sh; [ "$status" -eq 0 ]
  git worktree list --porcelain | grep -q "^worktree $PWD/other\$"
}

@test "2.1.1 clone paths differ between repos for the same PR number" {
  clone211 > c211.sh
  mkdir -p a b s
  for r in a b; do (cd $r && git init -q . && git commit -q --allow-empty -m x && mkdir -p .prp-output/reviews && git rev-parse HEAD > .prp-output/reviews/pr-7-reviewed-head); done
  (cd a && env SCRATCHPAD="$OLDPWD/s" bash ../c211.sh) && (cd b && env SCRATCHPAD="$OLDPWD/s" bash ../c211.sh)
  [ "$(ls -d s/prp-review-clone-*-pr-7 | wc -l)" -eq 2 ]
}

clone211() { fence "$ADAPTER" "### 2.1.1 "; }

@test "2.1.1 clones the agents' tree at the saved head even when HEAD moved after Phase 2.0" {
  phase20 > p20.sh; clone211 > c211.sh; repo_here
  run env -u REVIEWED_HEAD_SHA bash p20.sh; [ "$status" -eq 0 ]
  saved=$FAKE_HEAD
  git commit -q --allow-empty -m moved            # the shared checkout moves on
  mkdir -p s; run env SCRATCHPAD="$PWD/s" bash c211.sh
  [ "$status" -eq 0 ]
  [ "$(git -C "$(clonedir)" rev-parse HEAD)" = "$saved" ]
}

@test "2.1.1 runs again in a later round even when the earlier clone was never cleaned up" {
  phase20 > p20.sh; clone211 > c211.sh; repo_here
  run env -u REVIEWED_HEAD_SHA bash p20.sh; [ "$status" -eq 0 ]
  mkdir -p s
  run env SCRATCHPAD="$PWD/s" bash c211.sh; [ "$status" -eq 0 ]
  rm -rf -- "$(clonedir)"                          # directory gone, registration left behind
  run env SCRATCHPAD="$PWD/s" bash c211.sh; [ "$status" -eq 0 ]
  touch "$(clonedir)/stale"                         # a kept tree would still have this
  run env SCRATCHPAD="$PWD/s" bash c211.sh; [ "$status" -eq 0 ]   # and with the clone still present
  [ ! -e "$(clonedir)/stale" ]
  [ "$(git -C "$(clonedir)" rev-parse HEAD)" = "$FAKE_HEAD" ]
}

@test "2.1.1 starts no clone without a head saved by Phase 2.0" {
  clone211 > c211.sh; repo_here; rm -f .prp-output/reviews/pr-7-reviewed-head
  mkdir -p s; run env SCRATCHPAD="$PWD/s" bash c211.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"no reviewed head saved by Phase 2.0"* ]]
  [ -z "$(ls s)" ]
}

@test "--l2-comments implies no artifact commit (documented flag mapping)" {
  grep -q -- '`--l2-comments` → `L2_COMMENTS=1` and `NO_COMMIT=1`' "$ADAPTER"
}

# ---- risk tier (agent-devops#1259) ---------------------------------------------------------------
phase20b() { fence "$ADAPTER" "### 2.0b Risk Tier"; }
trivial_run() { printf 'trivial\n' > .prp-output/reviews/pr-7-tier; export FAKE_TIER=trivial; start; }

@test "2.0b saves trivial only when pr-risk-tier prints trivial at the reviewed head" {
  phase20b > p20b.sh; rm -f .prp-output/reviews/pr-7-tier
  FAKE_TIER=trivial run bash p20b.sh
  [ "$status" -eq 0 ]; [ "$(cat .prp-output/reviews/pr-7-tier)" = trivial ]
  grep -qx -- "--head $HEAD_SHA 7" "$WORK/tier.calls"
}

@test "2.0b saves standard on standard, an error, a missing tool, or an inherited PR_RISK_TIER_GH" {
  phase20b > p20b.sh
  FAKE_TIER=standard run bash p20b.sh; [ "$(cat .prp-output/reviews/pr-7-tier)" = standard ]
  TIER_FAIL=1 run bash p20b.sh; [ "$(cat .prp-output/reviews/pr-7-tier)" = standard ]
  FAKE_TIER=trivial PR_RISK_TIER_GH=/evil/gh run bash p20b.sh; [ "$(cat .prp-output/reviews/pr-7-tier)" = trivial ]   # scrubbed: the stub saw no override
  rm bin/pr-risk-tier   # and no real one either: a PATH with only the stubs and the system dirs
  FAKE_TIER=trivial PATH="$WORK/bin:/usr/bin:/bin" run bash p20b.sh; [ "$status" -eq 0 ]; [ "$(cat .prp-output/reviews/pr-7-tier)" = standard ]
}

@test "2.0b comes after Phase 2.0 and before the agents start (2.1.1)" {
  a=$(grep -n '^### 2.0 Capture' "$ADAPTER" | cut -d: -f1); b=$(grep -n '^### 2.0b Risk Tier' "$ADAPTER" | cut -d: -f1)
  c=$(grep -n '^### 2.1.1 ' "$ADAPTER" | cut -d: -f1)
  [ -n "$b" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]
}

@test "Step A records the tier; no saved tier means no run" {
  trivial_run; [ "$status" -eq 0 ]; grep -qx 'TIER=trivial' .prp-output/reviews/pr-7-l2-run.env
  rm .prp-output/reviews/pr-7-tier; start
  [ "$status" -ne 0 ]; [[ "$output" == *"no tier saved by 2.0b"* ]]
}

@test "a trivial run posts exactly one code-reviewer comment with tier=trivial" {
  trivial_run; body code-reviewer; post
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 1 ]
  [ "$(tail -n1 .prp-output/reviews/pr-7-l2-code-reviewer.md | sed -E 's/.* (pass=.*)/\1/')" = "pass=code-reviewer tier=trivial" ]
}

@test "a trivial run whose classifier now says standard posts nothing" {
  trivial_run; body code-reviewer
  FAKE_TIER=standard post
  [ "$status" -ne 0 ]; [[ "$output" == *"no longer says trivial"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a trivial run with the classifier failing or missing posts nothing" {
  trivial_run; body code-reviewer
  TIER_FAIL=1 post; [ "$status" -ne 0 ]; [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
  rm bin/pr-risk-tier
  PATH="$WORK/bin:/usr/bin:/bin" post; [ "$status" -ne 0 ]; [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a tier=trivial footer in a standard run is rejected" {
  start; write_all
  sed -i '$ s/$/ tier=trivial/' .prp-output/reviews/pr-7-l2-code-reviewer.md
  post
  [ "$status" -ne 0 ]; [[ "$output" == *"footer"* ]]; [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a trivial run's footer without tier=trivial is rejected" {
  trivial_run; body code-reviewer
  sed -i '$ s/ tier=trivial$//' .prp-output/reviews/pr-7-l2-code-reviewer.md
  post
  [ "$status" -ne 0 ]; [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a run file whose TIER is edited to something else posts nothing" {
  start; write_all
  sed -i 's/^TIER=standard$/TIER=lite/' .prp-output/reviews/pr-7-l2-run.env
  post
  [ "$status" -ne 0 ]; [[ "$output" == *"not a valid run file"* ]]
}

# --- pass timebox (prp-framework#151 AC2): Step C refuses a timeboxed body without a follow-up link ---

timeboxed() { # timeboxed <pass> [link]: rewrite one body so its Could not verify says the pass was timeboxed
  local f=".prp-output/reviews/pr-7-l2-$1.md" link="${2:-}"
  { sed -n '1,/^### Could not verify$/p' "$f"; printf 'Pass timeboxed: 1 probe(s) not completed: bats\n'; [ -n "$link" ] && printf 'Follow-up: %s\n' "$link"
    printf '\n'; tail -n1 "$f"; } > t.md && mv t.md "$f"
}

@test "a timeboxed body without a follow-up link posts nothing" {
  start; write_all; timeboxed security-reviewer
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"timebox without a Follow-up issue link"* ]]
  [[ "$output" == *"pass mentions a timebox"* ]]
  [ ! -s "$WORK_LOG" ]
}

@test "a timebox mention in any markup posts nothing without a link" {
  start; write_all
  f=".prp-output/reviews/pr-7-l2-security-reviewer.md"
  { sed -n '1,/^### Could not verify$/p' "$f"; printf '## **Pass** time-boxed\n\n'; tail -n1 "$f"; } > t.md && mv t.md "$f"
  post
  [ "$status" -ne 0 ]
  [ ! -s "$WORK_LOG" ]
}

@test "a timeboxed body with a follow-up issue link is posted with the other passes" {
  start; write_all; timeboxed security-reviewer https://github.com/o/r/issues/12
  post
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 3 ]
}

@test "Step C posts nothing when the installed framework scripts cannot be found" {
  start; write_all; rm -rf prp/scripts
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot find the installed prp-framework scripts"* ]]
  [ ! -s "$WORK_LOG" ]
}

# The next two tests moved here from tests/commands/review-rounds.bats
# (prp-framework#151): both used to hardcode $ADAPTER to claude-code, so the
# behaviour they pin — the pass-deadline-mint FATAL guard actually aborting,
# and the round-cap guard running before the reviewed head is saved — was
# never exercised against the other 6 files. Moving them here, under the
# parametrised $ADAPTER, closes that gap the same way the rest of this file
# does: tests/commands/l2-adapters-matrix.bats runs this whole suite once per
# EXPECTED_FILES entry.

@test "the pass-deadline-mint FATAL guard actually aborts closed: script failure and a broken .prp symlink (round-6 Important)" {
  guard="$BATS_TEST_TMPDIR/guard.sh"
  fence "$ADAPTER" "### 2.2.0 Pass Budget" > "$guard"
  [ -s "$guard" ]
  grep -qE -- 'FATAL: cannot mint the pass deadline' "$guard"
  grep -qE -- 'echo "PASS_DEADLINE=\$PASS_DEADLINE PRP_DIR=\$PRP_DIR"' "$guard"

  work="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work"

  # Failure mode 1: pass-budget.sh itself exits non-zero (forced bad budget).
  ln -s "$ROOT" "$work/.prp"
  run bash -c "cd \"$work\" && PRP_PASS_BUDGET_SECS=abc bash \"$guard\""
  rm -f "$work/.prp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FATAL: cannot mint the pass deadline — no agents started"* ]]

  # Failure mode 2: .prp is a broken symlink (script path under it doesn't exist).
  ln -s "$BATS_TEST_TMPDIR/does-not-exist" "$work/.prp"
  run bash -c "cd \"$work\" && bash \"$guard\""
  rm -f "$work/.prp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FATAL: cannot mint the pass deadline — no agents started"* ]]

  # Success path: still mints the deadline AND now prints it (the regression
  # this test closes — a prior fix silently dropped the echo).
  ln -s "$ROOT" "$work/.prp"
  run bash -c "cd \"$work\" && bash \"$guard\""
  rm -f "$work/.prp"
  [ "$status" -eq 0 ]
  real_root="$(readlink -f "$ROOT")"
  [[ "$output" == *"PASS_DEADLINE="*"PRP_DIR=$real_root"* ]]
  [[ "$output" =~ PASS_DEADLINE=[0-9]+ ]]
}

@test "the round-cap guard runs in Phase 2.0 before the reviewed head is saved" {
  # Plain line numbers, not a fence extraction — verified this does not need
  # fence()/tomllib decoding: unlike a multi-line bash fence, a single-line
  # grep match on gemini's raw .toml is byte-identical to the decoded prompt
  # text for both patterns below (the TOML escaping only affects embedded
  # backslash-newline continuations, not the matched substrings themselves).
  g=$(grep -n 'round-guard.sh" --cap 6' "$ADAPTER" | head -1 | cut -d: -f1)
  h=$(grep -n "> \"\$D/pr-{NUMBER}-reviewed-head\"" "$ADAPTER" | head -1 | cut -d: -f1)
  [ -n "$g" ] && [ -n "$h" ] && [ "$g" -lt "$h" ]
}

# --- 2.0a Review Mode Decision (review-diet plan PR-3 v1.3) ---

phase20a() { fence "$ADAPTER" "### 2.0a Review Mode Decision"; }

# One fake PR comment whose body is "Reviewed head: <head>\nReview-mode: <mode-line>\n...".
# mode-line is "full" (so it is also a valid LAST_FULL candidate for G2) or omitted ("" -> a
# plain line that is neither full nor delta, so G2 never picks it as LAST_FULL).
fake_mode_comment() {
  local head="$1" modeline="${2:-full}"
  # user.login must match the "api user" mock's default login ("bot", or $FAKE_LOGIN when the
  # caller set it) — 2.0a's own TRUSTED_LOGIN filter (prp-framework#228) now excludes any comment
  # whose author doesn't match, same as Phase 2.0's CLEAN_ROWS check.
  # Line 2 is "Passes run: ..." (the real posted-body shape) so 2.0a's split("\n")[2] reader
  # for Review-mode exercises the same index as production comments.
  jq -n --arg b "Reviewed head: $head
Passes run: code-reviewer
Review-mode: $modeline

### Could not verify
Nothing.
" --arg login "${FAKE_LOGIN:-bot}" '[{user: {login: $login}, body: $b}]' > "$WORK/comments.json"
  export FAKE_COMMENTS_JSON="$WORK/comments.json"
}

run_20a() { # run 2.0a in $WORK with REVIEWED_HEAD_SHA already saved to pr-7-reviewed-head
  phase20a > p20a.sh
  run env -u REVIEWED_HEAD_SHA bash p20a.sh
}

@test "a well-formed delta line is accepted (G1 ancestor + G2 under 40%)" {
  repo_here
  SHA0="$FAKE_HEAD"
  printf 'line1\n' > f.txt; git add f.txt; git commit -q -m c1; printf 'line1\nline2\n' >> f.txt; git commit -aq -m c2
  SHA1=$(git rev-parse HEAD)
  printf '%s\n' "$SHA1" > .prp-output/reviews/pr-7-reviewed-head
  fake_mode_comment "$SHA0" full
  FAKE_TOTAL=100 run_20a
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p .prp-output/reviews/pr-7-mode)" = delta ]
  [ "$(sed -n 2p .prp-output/reviews/pr-7-mode)" = "$SHA0" ]
}

@test "a rebase (base not an ancestor) is forced to full" {
  git init -q .
  git commit -q --allow-empty -m c0; SHA0=$(git rev-parse HEAD)
  git checkout -q --orphan newroot
  git commit -q --allow-empty -m c1; SHA1=$(git rev-parse HEAD)
  printf '%s\n' "$SHA1" > .prp-output/reviews/pr-7-reviewed-head
  fake_mode_comment "$SHA0" full
  FAKE_TOTAL=100 run_20a
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p .prp-output/reviews/pr-7-mode)" = full ]
  [ -z "$(sed -n 2p .prp-output/reviews/pr-7-mode)" ]
}

@test "a 40% overflow (cumulative delta too large) is forced to full" {
  repo_here
  SHA0="$FAKE_HEAD"
  seq 1 50 > f.txt; git add f.txt; git commit -q -m c1
  seq 51 100 > f.txt; git commit -aq -m c2
  SHA1=$(git rev-parse HEAD)
  printf '%s\n' "$SHA1" > .prp-output/reviews/pr-7-reviewed-head
  fake_mode_comment "$SHA0" full
  # SHA0..SHA1 adds f.txt with 50 lines = 50 changed; 50 > 40% of FAKE_TOTAL=100 (40) -> overflow
  FAKE_TOTAL=100 run_20a
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p .prp-output/reviews/pr-7-mode)" = full ]
  [ -z "$(sed -n 2p .prp-output/reviews/pr-7-mode)" ]
}

@test "2.0a forces full when pr-risk-tier is missing from PATH, even when G1/G2 would allow delta (gate-tier-forces-full)" {
  repo_here
  SHA0="$FAKE_HEAD"
  printf 'line1\n' > f.txt; git add f.txt; git commit -q -m c1; printf 'line1\nline2\n' >> f.txt; git commit -aq -m c2
  SHA1=$(git rev-parse HEAD)
  printf '%s\n' "$SHA1" > .prp-output/reviews/pr-7-reviewed-head
  fake_mode_comment "$SHA0" full
  rm -f bin/pr-risk-tier
  phase20a > p20a.sh
  FAKE_TOTAL=100 PATH="$WORK/bin:/usr/bin:/bin" run env -u REVIEWED_HEAD_SHA bash p20a.sh
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p .prp-output/reviews/pr-7-mode)" = full ]
}

@test "2.0a forces full when pr-risk-tier is installed but the --rounds call errors, even when G1/G2 would allow delta (gate-tier-forces-full)" {
  repo_here
  SHA0="$FAKE_HEAD"
  printf 'line1\n' > f.txt; git add f.txt; git commit -q -m c1; printf 'line1\nline2\n' >> f.txt; git commit -aq -m c2
  SHA1=$(git rev-parse HEAD)
  printf '%s\n' "$SHA1" > .prp-output/reviews/pr-7-reviewed-head
  fake_mode_comment "$SHA0" full
  TIER_FAIL=1 FAKE_TOTAL=100 run_20a
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p .prp-output/reviews/pr-7-mode)" = full ]
  grep -q -- '--rounds 7' "$WORK/tier.calls"
}

@test "B11: a missing Review-mode line is refused" {
  start; write_all
  sed -i '/^Review-mode: /d' .prp-output/reviews/pr-7-l2-code-reviewer.md
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 3"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "B12: a Review-mode line that disagrees with the other two passes is refused" {
  start; write_all
  sed -i 's/^Review-mode: full$/Review-mode: delta 0000000000000000000000000000000000000000..0123456789abcdef0123456789abcdef01234567/' .prp-output/reviews/pr-7-l2-security-reviewer.md
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 3"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "B13: line 2 of every well-formed body is exactly 'Passes run: <pass>' — the consumer contract safe-merge, merger-policy and the generator read" {
  start; write_all
  for pass in code-reviewer security-reviewer silent-failure-hunter; do
    [ "$(sed -n 2p ".prp-output/reviews/pr-7-l2-$pass.md")" = "Passes run: $pass" ]
  done
  post
  [ "$status" -eq 0 ]
}

@test "B14: a missing Passes run line is refused" {
  start; write_all
  sed -i '/^Passes run: /d' .prp-output/reviews/pr-7-l2-code-reviewer.md
  post
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 2"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

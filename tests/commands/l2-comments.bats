#!/usr/bin/env bats
# Behaviour tests for prp-review-agents --l2-comments (prp-framework#142).
#
# The posting is two bash fences in the claude-code adapter (Step A starts the run and saves its
# values; Step C checks all three bodies, then posts). These tests extract both, stub `gh`, and run
# them as separate shells — as an agent does — with the bodies written in between (Step B).
#
# Run: bats tests/commands/l2-comments.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ADAPTER="$ROOT/adapters/claude-code/prp-review-agents.md"
HEAD_SHA="0123456789abcdef0123456789abcdef01234567"

step() { # step <A|C> -> the bash fence after "**Step <X>", {NUMBER} filled in
  awk -v want="**Step $1" 'index($0, want) == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g'
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
if [ "$1 $2" = "pr view" ]; then [ -n "${GH_FAIL:-}" ] && exit 1; printf '%s\n' "$FAKE_HEAD"; exit 0; fi
if [ "$1" = "api" ]; then   # the round-cap read (Phase 2.0): last lines of the PR comments
  [ -n "${API_FAIL:-}" ] && exit 1
  # apply the REAL --jq filter from the prompt to comment JSON, as `gh api --paginate --jq` does per page
  filter=""; while [ $# -gt 0 ]; do [ "$1" = "--jq" ] && filter="$2"; shift; done
  [ -n "$filter" ] || exit 1
  if [ -n "${FAKE_COMMENTS_JSON:-}" ]; then jq -r "$filter" "$FAKE_COMMENTS_JSON" || exit 1; exit 0; fi
  # FAKE_COMMENTS = one footer line per comment; wrap each as a multi-line body with a trailing newline
  [ -n "${FAKE_COMMENTS:-}" ] && jq -R -s 'split("\n")[:-1] | map({body: ("Reviewed head: x\n\n### Could not verify\nNothing.\n\n" + . + "\n")})' "$FAKE_COMMENTS" | jq -r "$filter"
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
  step A > stepA.sh; step C > stepC.sh
  [ -s stepA.sh ] && [ -s stepC.sh ]
}

teardown() { rm -rf "$WORK"; }

# Step B: write a well-formed body for one pass from the saved run values
body() {
  local pass="$1" sfx=""; . .prp-output/reviews/pr-7-l2-run.env   # the test reads its own fixture file
  [ "${TIER:-}" = trivial ] && sfx=" tier=trivial"
  printf 'Reviewed head: %s\nPasses run: %s\n\n### Critical Issues (0 found)\nNone.\n\n### Important Issues (0 found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\nGenerated-by: prp-review-agents v%s run=%s pass=%s%s\n' \
    "$REVIEWED_HEAD_SHA" "$pass" "$PRP_VERSION" "$RUN_ID" "$pass" "$sfx" > ".prp-output/reviews/pr-7-l2-$pass.md"
}

start() { run env -u REVIEWED_HEAD_SHA -u L2_COMMENTS bash stepA.sh; }   # a fresh shell: nothing inherited
write_all() { for p in code-reviewer security-reviewer silent-failure-hunter; do body "$p"; done; }
post() { run bash stepC.sh; }

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

phase20() { awk 'index($0, "### 2.0 Capture the Reviewed Head") == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g'; }

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

@test "Phase 2.0 allows round 10 (nine runs on the PR) and saves the head" {
  phase20 > p20.sh; repo_here; runs 9 > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

@test "Phase 2.0 refuses round 11 (ten runs) before any head file or agent" {
  phase20 > p20.sh; repo_here; runs 10 > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"ROUND-CAP: refused"* ]]
  [[ "$output" == *"round cap — no agents started"* ]]
  [ ! -e .prp-output/reviews/pr-7-reviewed-head ]
}

@test "Phase 2.0 runs the real jq filter over paginated comment JSON" {
  phase20 > p20.sh; repo_here
  # two pages (gh --paginate applies --jq per page): a multi-line body, a plain comment and a CRLF-free footer
  { runs 5 | jq -R -s 'split("\n")[:-1] | map({body: ("review text\nmore\n" + . + "\n")})'
    runs 10 | tail -n +16 | jq -R -s 'split("\n")[:-1] | map({body: ("other\n" + . + "\n")}) + [{body: "LGTM"}]'; } > c.json
  FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"ROUND-CAP: refused"* ]]
}

@test "Phase 2.0 allows round 10 over paginated comment JSON with ordinary comments" {
  phase20 > p20.sh; repo_here
  { runs 4 | jq -R -s 'split("\n")[:-1] | map({body: ("text\n" + . + "\n")}) + [{body: "LGTM"}, {body: "a\nb\nc"}]'
    runs 9 | tail -n +13 | jq -R -s 'split("\n")[:-1] | map({body: ("text\n" + . + "\n")})'; } > c.json
  FAKE_COMMENTS_JSON="$PWD/c.json" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

@test "Phase 2.0 refuses on a comment with a null body" {
  phase20 > p20.sh; repo_here
  printf '[{"body": null}]\n' > c.json
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

@test "Phase 2.0 refuses on a review footer it cannot parse" {
  phase20 > p20.sh; repo_here
  printf 'Generated-by: prp-review-agents v1 run=oops pass=x\n' > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
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

clone211() { awk 'index($0, "### 2.1.1 ") == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g'; }

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
phase20b() { awk 'index($0, "### 2.0b Risk Tier") == 1 {f=1} f && /^```bash$/ {b=1; next} b && /^```$/ {exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g'; }
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

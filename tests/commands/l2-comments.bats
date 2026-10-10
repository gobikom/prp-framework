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
  ln -s "$WORK/prp" .prp
  mkdir -p .prp-output/reviews bin
  # gh stub: `pr view` prints $FAKE_HEAD (or fails with GH_FAIL=1); `pr comment` logs the body file, prints a URL
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "pr view" ]; then [ -n "${GH_FAIL:-}" ] && exit 1; printf '%s\n' "$FAKE_HEAD"; exit 0; fi
if [ "$1 $2" = "pr comment" ]; then
  f=""; while [ $# -gt 0 ]; do [ "$1" = "--body-file" ] && f="$2"; shift; done
  [ -n "${FAIL_POST:-}" ] && grep -q "Passes run: $FAIL_POST" "$f" && exit 1
  echo "$f" >> "$WORK_LOG"; echo "https://github.com/o/r/pull/7#issuecomment-$(wc -l < "$WORK_LOG")"; exit 0
fi
exit 2
EOF
  chmod +x bin/gh
  export PATH="$WORK/bin:$PATH" WORK_LOG="$WORK/posted.log" FAKE_HEAD="$HEAD_SHA"
  : > "$WORK_LOG"
  step A > stepA.sh; step C > stepC.sh
  [ -s stepA.sh ] && [ -s stepC.sh ]
}

teardown() { rm -rf "$WORK"; }

# Step B: write a well-formed body for one pass from the saved run values
body() {
  local pass="$1"; . .prp-output/reviews/pr-7-l2-run.env
  printf 'Reviewed head: %s\nPasses run: %s\n\n### Critical Issues (0 found)\nNone.\n\n### Important Issues (0 found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\nGenerated-by: prp-review-agents v%s run=%s pass=%s\n' \
    "$REVIEWED_HEAD_SHA" "$pass" "$PRP_VERSION" "$RUN_ID" "$pass" > ".prp-output/reviews/pr-7-l2-$pass.md"
}

start() { run env L2_COMMENTS=1 REVIEWED_HEAD_SHA="$HEAD_SHA" bash stepA.sh; }
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
  [[ "$output" == *"prp-framework version"* ]]
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

@test "L2_COMMENTS is required (not an --l2-comments run starts nothing)" {
  run env REVIEWED_HEAD_SHA="$HEAD_SHA" bash stepA.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an --l2-comments run"* ]]
}

@test "--l2-comments implies no artifact commit (documented flag mapping)" {
  grep -q -- '`--l2-comments` → `L2_COMMENTS=1` and `NO_COMMIT=1`' "$ADAPTER"
}

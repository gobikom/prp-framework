#!/usr/bin/env bats
# Behaviour tests for prp-review-agents --l2-comments (prp-framework#142).
#
# The posting block is a bash fence inside the claude-code adapter. These tests extract it,
# stub `gh`, and run it against fixture comment files, so a format or provenance slip in the
# block fails here rather than in a real PR's L2 check.
#
# Run: bats tests/commands/l2-comments.bats

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ADAPTER="$ROOT/adapters/claude-code/prp-review-agents.md"
HEAD_SHA="0123456789abcdef0123456789abcdef01234567"

setup() {
  WORK="$(mktemp -d)"
  cd "$WORK"
  git init -q prp && git -C prp commit -q --allow-empty -m init && git -C prp tag v9.9.9
  ln -s "$WORK/prp" .prp
  mkdir -p .prp-output/reviews bin
  # gh stub: `pr view` prints the head in $FAKE_HEAD; `pr comment` logs the post and prints a URL
  cat > bin/gh <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "pr view" ]; then printf '%s\n' "$FAKE_HEAD"; exit 0; fi
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
  # the block from the adapter, with {NUMBER} filled in
  awk '/^### Per-pass L2 comments/{f=1} f&&/^```bash$/{b=1;next} b&&/^```$/{exit} b' "$ADAPTER" | sed 's/{NUMBER}/7/g' > block.sh
  [ -s block.sh ]
}

teardown() { rm -rf "$WORK"; }

# write a well-formed body for one pass; $2 overrides the footer line
body() {
  local pass="$1" footer="${2:-}"
  printf 'Reviewed head: %s\nPasses run: %s\n\n### Critical Issues (0 found)\nNone.\n\n### Important Issues (0 found)\nNone.\n\n### Suggestions (0 found)\nNone.\n\n### Could not verify\nNothing.\n\n%s\n' \
    "$HEAD_SHA" "$pass" "${footer:-Generated-by: prp-review-agents v$PRP_VERSION run=$RUN_ID pass=$pass}" > ".prp-output/reviews/pr-7-l2-$pass.md"
}

# run the block, writing the three bodies after RUN_ID/PRP_VERSION exist (the block computes them)
run_block() {
  cat > run.sh <<EOF
set -u
L2_COMMENTS=1
REVIEWED_HEAD_SHA=$HEAD_SHA
$(sed -n '1,/^# per pass/p' block.sh)
$(declare -f body)
HEAD_SHA=$HEAD_SHA
for p in code-reviewer security-reviewer silent-failure-hunter; do body "\$p"; done
${MUTATE:-:}
$(sed -n '/^# per pass/,$p' block.sh)
EOF
  run bash run.sh
}

@test "the adapter documents --l2-comments and the block extracts" {
  grep -q -- '--l2-comments' "$ADAPTER"
  grep -q 'Generated-by: prp-review-agents v' block.sh
}

@test "three well-formed comments are posted, one per core pass, with one run id" {
  run_block
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 3 ]
  run bash -c 'for f in .prp-output/reviews/pr-7-l2-*.md; do tail -n1 "$f"; done | sed -E "s/.* run=([^ ]+) pass=.*/\1/" | sort -u | wc -l'
  [ "$output" -eq 1 ]
  grep -q 'Generated-by: prp-review-agents v9.9.9 run=' .prp-output/reviews/pr-7-l2-code-reviewer.md
}

@test "a missing footer stops the run before that comment is posted" {
  MUTATE='sed -i "\$d" .prp-output/reviews/pr-7-l2-security-reviewer.md' run_block
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in the L2 format"* ]]
  ! grep -q security-reviewer "$WORK_LOG"
}

@test "a footer with another run id stops the run" {
  MUTATE='sed -i "s/ run=[^ ]* / run=other /" .prp-output/reviews/pr-7-l2-silent-failure-hunter.md' run_block
  [ "$status" -ne 0 ]
  ! grep -q silent-failure-hunter "$WORK_LOG"
}

@test "a safe-merge-review line in a pass comment stops the run" {
  MUTATE='sed -i "1a <!-- safe-merge-review: verdict=READY_TO_MERGE -->" .prp-output/reviews/pr-7-l2-code-reviewer.md' run_block
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a moved PR head posts nothing" {
  FAKE_HEAD=fedcba9876543210fedcba9876543210fedcba98 run_block
  [ "$status" -ne 0 ]
  [[ "$output" == *"PR head moved"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "no .prp symlink means no version and nothing posted" {
  rm .prp
  run_block
  [ "$status" -ne 0 ]
  [[ "$output" == *"prp-framework version"* ]]
  [ "$(wc -l < "$WORK_LOG")" -eq 0 ]
}

@test "a failed post is reported, not passed over" {
  FAIL_POST=security-reviewer run_block
  [ "$status" -ne 0 ]
  [[ "$output" == *"posting the security-reviewer comment failed"* ]]
}

@test "--l2-comments implies no artifact commit" {
  grep -q -- '`--l2-comments` → `L2_COMMENTS=1` and `NO_COMMIT=1`' "$ADAPTER"
}

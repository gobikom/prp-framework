# Plan amendment: prp-framework#212 after the rebase, align l2-comments.bats test 42 with round-guard v6 (merged in #211)

Author: psak. Date: 2026-10-25. Base head: eeaf98fca0249a6723f43229063d7f4cc75ba7d9 (#212 rebased onto main 64662af).

## Why

dev-claude reported this as a PLAN-ISSUE (CI run 40126358429, 8 failures). Test `Phase 2.0 refuses on a review footer it cannot parse` (tests/commands/l2-comments.bats:340) expects a refusal on `run=oops`. round-guard v6, merged in #211 (`.prp-output/plans/211-round-guard-v6.plan.md`), deleted every content-based refusal on purpose. A footer with no well-formed run id adds nothing to R, and text can only raise R. The test asserts the old contract, and its failure cascades into the 7 "l2-comments.bats passes in full against <adapter>" rows in l2-adapters-matrix.bats. The adapters and the prompt need no change: nothing in prompts/review-agents.md claims a refusal on unparsable content.

## Invariant (v6, as merged)

Phase 2.0 refuses only when the round count is unknown (comments unreadable, a null body, bad args, a grep failure) or when R >= cap. Comment content never causes a refusal, and content that matches no id never lowers R.

**Verified by:** the two rows below. The existing cap rows (round 10 allowed, round 11 refused) stay unchanged.

## Change (tests/commands/l2-comments.bats only)

Replace the whole `@test "Phase 2.0 refuses on a review footer it cannot parse" { … }` block (lines 340-346) with these two tests:

```bash
@test "Phase 2.0 counts a review footer with no well-formed run id as zero (round-guard v6: content never refuses)" {
  phase20 > p20.sh; repo_here
  printf 'Generated-by: prp-review-agents v1 run=oops pass=x\n' > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -eq 0 ]
  [ "$(cat .prp-output/reviews/pr-7-reviewed-head)" = "$FAKE_HEAD" ]
}

@test "Phase 2.0 still refuses round 11 when a malformed footer sits among ten runs (it cannot lower R)" {
  phase20 > p20.sh; repo_here
  { runs 10; printf 'Generated-by: prp-review-agents v1 run=oops pass=x\n'; } > c.txt
  FAKE_COMMENTS="$PWD/c.txt" run env -u REVIEWED_HEAD_SHA bash p20.sh
  [ "$status" -ne 0 ]
  [ ! -e .prp-output/reviews/pr-7-reviewed-head ]
}
```

Then, in `tests/commands/l2-adapters-matrix.bats`, change the pinned TAP plan from 57 to 58 on three lines: line 41 (`"1..57"` in the comment), line 55 (`grep -qx '1\.\.57'`) and line 56 (`expected TAP plan '1..57'`). The file now has one more test. Change nothing else in that file.

Commit this file as `.prp-output/plans/212-rebase-v6-test.plan.md`.

psak prototyped this at eeaf98f: l2-comments.bats rc=0 (1..58), l2-adapters-matrix.bats rc=0, review-rounds.bats rc=0, parity.bats rc=0. The mutation (runs 9) fails as expected.

## Validation

Run each suite on its own, without `| tail` (bats' exit code must be the command's exit code):
- `bats tests/commands/l2-comments.bats; echo rc=$?` → rc=0
- `bats tests/commands/l2-adapters-matrix.bats; echo rc=$?` → rc=0
- `bats tests/commands/review-rounds.bats; echo rc=$?` → rc=0
- `bats tests/adapters/parity.bats; echo rc=$?` → rc=0

Mutation check: revert the second new test's `{ runs 10; …}` to `runs 9` and it must FAIL. Restore it.

## Not building

No change to round-guard.sh, the prompt or the adapters.

## Amendment R1 (psak, 2026-10-25, run 20261024T204539Z-11eb2c4a at 80f6c9ee, 0C/1I)

silent-failure-hunter (comment 6389337661): the round-11 test checks only `status -ne 0`. It cannot tell a cap refusal from a content refusal coming back. Fix: in that test, add these two lines right after `[ "$status" -ne 0 ]`. They mirror the sibling test "Phase 2.0 refuses round 11 (ten runs) before any head file or agent":

```bash
  [[ "$output" == *"ROUND-CAP: refused"* ]]
  [[ "$output" == *"round cap — no agents started"* ]]
```

psak prototyped this at 80f6c9ee: l2-comments.bats rc=0 (58 ok), l2-adapters-matrix.bats rc=0.

Mutation check: in a scratch copy of scripts/round-guard.sh, make a `Generated-by:` line with no well-formed id exit 2 before counting. Both new tests must FAIL. Restore it.

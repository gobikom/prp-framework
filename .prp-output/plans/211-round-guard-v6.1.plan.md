# Plan amendment: prp-framework#211 v6.1: correct the #212 author-filter claim (R7 Important)

Author: psak. Date: 2026-10-25. Base head: 6cc6867cb023a9cff5289c52ef363fb9f1d9d3a9 (v6).
This amends `211-round-guard-v6.plan.md`. Its Change 1 step 3 wording ("caller-side author filtering is in #212") was psak's error. Everything else in v6 stays, and the code does not change.

## Why

R7 is run `20261024T175452Z-303ba021`, comment 6387600583 (code-reviewer, Important). PR #212's caller has no `user.login` filter, so the header and PR body point at a mitigation that does not exist. An author filter also could not work here, because every agent on this host comments as `gobikom`.

The real situation:
- Inflation is the fail-safe direction. A forged id can only push R to the cap early, which refuses another round; it can never undercount.
- The fix is ledger-only counting, now added to #213's scope (comment 6387615258).

## Change (comments and PR body only; no code)

1. `scripts/review/round-guard.sh`, in "Boundaries, stated": replace the two lines
   `#   out of scope, prp-framework#213 (durable ledger). Any text can only raise R; caller-side author`
   `#   filtering is in #212.`
   with:
   `#   out of scope, prp-framework#213 (durable ledger). Any text can only raise R: a forged id can push`
   `#   R to the cap early (refuses another round, never undercounts). Every agent comments as one user,`
   `#   so an author filter cannot help; ledger-only counting (#213) closes it.`
2. PR body, Invariant paragraph: replace `; caller-side author filtering (so a non-reviewer comment can't inflate R) is prp-framework#212.` with `. A forged id can only inflate R toward the cap (fail-safe: refuses another round, never undercounts); ledger-only counting in prp-framework#213 closes it.`
3. PR body, follow-up list: delete the "Caller-side author filtering (prp-framework#212)" bullet (3 lines), because #213 tracks it now. Keep every other bullet.
4. Commit this file as `.prp-output/plans/211-round-guard-v6.1.plan.md`. Do not edit the v6 plan file.
5. Check: `grep -n '212' scripts/review/round-guard.sh` prints nothing. `gh pr view 211 --json body --jq .body | grep -c 'author filtering'` prints 0.

## Validation

`bash -n scripts/review/round-guard.sh`; `bats tests/scripts/round-guard.bats` passes, with the same count as at 6cc6867c; `git diff 6cc6867c -- scripts/` touches only comment lines (every changed line starts with `#`).

## Not building

- Any code change.
- Changes to #212.
- The R7 Suggestions (`tr|sort|wc` rc guard and the rest): psak files them in the PR's ONE follow-up issue at merge.

# Plan: prp-framework#211: round-guard counts run ids, not footer shapes (re-plan v3 after R3)

Author: psak. Under นุด's rule of 2026-10-24, psak writes every plan and the dev implements it exactly.
Date: 2026-10-24. Base head: 4d16c6a4 (the commit "replace footer substring check with shape grammar (R2)").
This plan supersedes `.prp-output/plans/211-round-guard-footer-shape.plan.md`. Keep that file; it records the design this plan replaces.

## Why a second re-plan (stop rule: same family 3 rounds → change the design)

All three rounds found the same family: a line that is *almost* a review footer is silently ignored instead of refused.
- R1 (f7308983) and R2 (d09a2668) each found more spellings that slipped through.
- R3 is run 20261024T145009Z-03c4d72e on head 4d16c6a4, comments 6385639138 / 6385639469 / 6385639753.
  - It found 2 Critical and 2 Important against the R2 shape grammar: `pass:`, `run =`, a bounded separator, a singular typo, a whitespace gap, and an order asymmetry.
  - It also timed a regex DoS: a 64KB line took 14.4s, because of the `.*` alternations.

Recognising "a footer-like line" is an open set, so any enumeration of near-miss shapes will keep leaking.
This plan removes the shape classification entirely.

## Invariant

**Invariant:** the round count R is the number of distinct run-id tokens (`[0-9]{8}T[0-9]{6}Z-<hex>+`, compared lower-cased) found anywhere in the input lines. Every exact footer carries its run id, so R ≥ (distinct ids in exact footers). Changing anything on a line except the id itself (prefix, separators, word order, case, quoting, CR, a missing `pass=`, a split line) cannot lower R.

**Verified by:**
- the boundary rows below: every former "fails closed" shape now *counts*;
- two mutants;
- the real-data run (R = 325 on the sample, against 324 exact-footer ids).

**Boundary, stated:** a line whose run id *itself* is altered (digits removed or separated) is not counted. That is equivalent to deleting the comment, which this guard cannot see either. It is out of scope, as stated in the header.

**Direction of error:** a run id cited in prose (an L2 note, a provenance notice) is counted too. This can only raise R, which makes the guard stricter.
- On the real sample it adds 1 id across 75 PRs (325 vs 324).
- On a normal PR, a cited id is one of that PR's own footer ids, so dedup absorbs it.

## Input (unchanged, from the caller in PR-B #212)

`gh api repos/{owner}/{repo}/issues/{N}/comments --paginate --jq '.[].body | rtrimstr("\n") | split("\n") | last'`
This gives one line per comment: that comment's last line. Exit 2 is kept for bad arguments, unreadable input or a grep failure, and fails closed.

## Real-data sample (Real inputs first)

`~/tmp/rg-lastlines-sample.txt` is read-only: 1255 real last lines from 75 PRs, from the caller's exact jq.
- 966 lines are exact footers.
- 13 non-footer lines carry run ids: L2 notes, provenance notices and "stop rule met" notes. Only 1 of those ids has no footer anywhere in the sample.
- The 3 hand-built 9-hex ids (`20261022T044148Z-312938296`) count as ids, which is the strict direction.
- Prototype result (psak, scratch copy): `bash round-guard.sh --cap 999 < sample` prints `rounds so far: 325 of 999`.

## Change 1: `scripts/review/round-guard.sh` (only this file and the bats file change)

1. Replace the header Invariant paragraph (lines 4-9) with the Invariant, boundary and direction-of-error text above, in 6-8 comment lines.
2. Delete everything from `RUN_RE='…'` through the line `[[ -n "$IDS" ]] && R=$(printf '%s' "$IDS" | sort -u | wc -l | tr -d ' ')`, and put exactly this in its place:

```bash
# A review round is one distinct run id. Every run id token anywhere in the input counts, whatever the rest
# of its line looks like, so no footer shape can hide a round. Ids are compared lower-cased.
ID_RE='[0-9]{8}[Tt][0-9]{6}[Zz]-[0-9A-Fa-f]+'
IN=$(cat) || { echo "error: cannot read input — round count unknown, refusing" >&2; exit 2; }
rc=0
IDS=$(printf '%s\n' "$IN" | LC_ALL=C grep -aoE "$ID_RE") || rc=$?
(( rc <= 1 )) || { echo "error: grep failed (exit $rc) — round count unknown, refusing" >&2; exit 2; }
R=0
[[ -n "$IDS" ]] && R=$(printf '%s\n' "$IDS" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sort -u | wc -l | tr -d ' ')
```

3. Update the usage comment: `exit 2 = bad argument, unreadable input, or grep failure (fail closed)`. Do not change anything else; the cap block and the output text stay as they are.

## Change 2: `tests/scripts/round-guard.bats`

Keep every test. Rename and re-assert the ones that change. psak ran the current suite against the prototype; exactly these 14 flip.

| # | Test (old name) | New name | New assertion |
|---|---|---|---|
| 7 | a malformed review footer fails closed | a footer with no run id is ignored | `run=BAD` has no id: status 0, `rounds so far: 0 of 10` |
| 8 | a footer without a pass fails closed | a footer without a pass still counts its run | status 0, `rounds so far: 1 of 10` |
| 16-20, 22-26 | a 10th footer with … fails closed | a 10th footer with … still counts (hits the cap) | status 3, output has `ROUND-CAP` |
| 27 | a real 9-hex malformed run id fails closed | a real 9-hex run id counts (hits the cap) | status 3 |
| 29 | a real prose note citing run ids is ignored, not refused | a prose note citing new run ids counts them | status 3 (9 + 2 new ids = 11) |

Add these 6 rows:
1. **The R3 shapes, in one row:** "R3 near-miss shapes each still count". Loop over these 10th lines; each must give status 3:
   - `Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a pass:code-reviewer`
   - `Generated-by: prp-review-agents v1 run = 20261024T000000Z-0000000a pass=code-reviewer`
   - `Generated-by:    prp-review-agents    v1 run=20261024T000000Z-0000000a pass=code-reviewer`
   - `Generated-by: prp-review-agent v1 run=20261024T000000Z-0000000a pass=code-reviewer`
   - `pass=code-reviewer run=20261024T000000Z-0000000a`
2. **"an id repeated in another case counts once":** `boundary_footers`, then the 9th id lower-cased (`20261024t000000z-00000009`) as a 10th line. Expect status 0 and `rounds so far: 9 of 10`. This row kills mutant A.
3. **"a prose note citing this PR's own run ids adds nothing":** `boundary_footers`, then `Review stop rule met: round 1 (run 20261024T000000Z-00000001) and round 2 (run 20261024T000000Z-00000002)`. Expect status 0 and `9 of 10`.
4. **"a 64KB line is processed in under 2 seconds":** use a python3 one-liner to build `run=20261024T000000Z-0000000a pass=` plus `'x'*65536` plus ` run=`. Time it with `SECONDS`; expect status 0 and an elapsed time under 2 s.
5. **"a run id with altered digits is not counted (stated boundary)":** `boundary_footers`, then `… run=2026-10-24T00:00:00Z-0000000a …`. Expect status 0 and `9 of 10`. This documents the out-of-scope boundary.
6. **"a grep failure exits 2":** put a `grep` shim on PATH (`#!/bin/sh` + `exit 2`) and run the script with that PATH. Expect status 2 and the output `grep failed`.

Update the R2 comment block above test 22 so it cites this plan.

## Validation

1. `bash -n scripts/review/round-guard.sh` exits 0.
2. `bats tests/scripts/round-guard.bats` passes every test. Then run the full suite: `bats -r tests` (it was 800/800 at 4d16c6a4).
3. Real data: `bash scripts/review/round-guard.sh --cap 999 < ~/tmp/rg-lastlines-sample.txt` prints `rounds so far: 325 of 999; this is round 326`.
4. **Mutant A** (no case fold): delete `LC_ALL=C tr '[:upper:]' '[:lower:]' |`. The row "an id repeated in another case counts once" must FAIL. Revert.
5. **Mutant B** (back to exact footers only): change `grep -aoE "$ID_RE"` to `grep -aE '^Generated-by: prp-review-agents ' | grep -aoE "$ID_RE"`. The leading-space row and the R3-shapes row must FAIL. Revert.

## PR body (replace the R2 section)

- The plan path: `.prp-output/plans/211-round-guard-id-count.plan.md`. Commit it, and keep the R2 plan file.
- The Invariant line plus the "Verified by:" line, both as written above.
- Both mutant commands, each with its FAIL lines.
- The real-data output (`325 of 999`) and the R3 timing line (64KB: under 2 s).

## Not building

- Any footer-shape grammar or near-miss refusal.
- Detecting altered ids. That is out of scope, stated in the header.
- Any change to #212 (the caller). Exit codes 0/2/3 keep their meaning for it.

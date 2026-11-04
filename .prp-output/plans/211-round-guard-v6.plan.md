# Plan: prp-framework#211 — round-guard v6: count ids, drop the edited-text refusal arms (re-route after R6)

Author: psak. Under นุด's rule of 2026-10-24, psak writes every plan and the dev implements it exactly.
Date: 2026-10-25. Base head: 519b3f628750435227076d3523fd46e4c3954707 (v5).
This plan supersedes the refusal design of v3-v5 (`211-round-guard-footer-shape`, `-id-count`, `-v4`, `-v5`). Keep all those plan files. Everything else in v5 stays.

## Why (R6: the same family for the 6th time, so cut scope, don't narrow again)

R6 is run `20261024T165904Z-c21a0e08` at 519b3f62 (comments 6387021254 / 6387021737 / 6387022130). It found 3 Critical and 1 Important, and every one is another spelling of an edited footer that the fuzzy refusal arms either miss or over-match:
- an NBSP inside `run=`;
- a zero-width space inside `prp-review-agents`;
- a gap of 21 characters;
- `index()` matching the tool name anywhere on the line.

R1-R5 each fixed one spelling, and the next round found another. Detecting edited text by pattern is unbounded, so any v7 regex would get an R7 finding of the same family.

**Root cause:** v3-v5 claimed the guard "refuses when a footer is corrupted". Only a human edit can corrupt a footer. The producer never posts one: `adapters/claude-code/prp-review-agents.md` checks the footer is byte-exact (`Generated-by: prp-review-agents v<ver> run=<id> pass=<name>`) before posting and aborts otherwise. So the refusal arms defend against edited comments with a heuristic, and #213 already owns the structural answer (a durable run-id ledger).

**Design change (scope cut):** delete both refusal arms. R is the number of distinct well-formed ids anywhere in the input.
- Extra text, including any commenter's, can only raise R (pushing toward the cap is the safe direction).
- An edit can lower R only by removing or garbling an id the producer wrote. The guard makes no claim about that; #213 does.

This also removes the two remaining refusal false positives (R6 code-reviewer Critical; security Suggestions 1-2): no content can make the guard refuse any more.

## Invariant (replaces v5's)

**Invariant:** R = |{ lower-cased matches of `[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}` anywhere in the input }|.
- Adding any text never lowers R.
- On unedited producer footers (byte-exact by the adapter's pre-post check), R equals the number of review runs.
- The guard refuses (exit 2) only on bad arguments, unreadable input, or a grep failure. It never refuses on content.
- Out of scope, stated: a comment edited to remove or garble its id is not counted (prp-framework#213, durable ledger).

**Verified by:**
- the rewritten rows below (each edited-footer case gives status 0 and counts only the well-formed ids);
- the "text can only raise R" row;
- mutants M1-M3;
- real sample `325 of 999`, exit 0, under gawk and mawk.

## Change 1: `scripts/review/round-guard.sh`

1. Delete the whole `if ! printf '%s\n' "$IN" | LC_ALL=C awk … fi` block. That is from the `if ! printf` line through its closing `fi`, including the "unreadable run id" error line. Delete the comment block directly above it as well.
2. Keep everything else: arg parsing, `--cap` check, `ID_RE`, `IN=$(cat) ||`, the grep/rc block, the count, the cap message and the output line.
3. Header:
   - replace the Invariant with the one above, in 6-10 lines;
   - in "Boundaries, stated", replace the "Fail-closed cost" bullet and any bullet about generated-by / `run=` refusal with: `Never refuses on content. An edited comment whose id was removed or garbled is not counted — out of scope, prp-framework#213 (durable ledger). Any text can only raise R; caller-side author filtering is in #212.`
   - remove any header line that still describes the refusal arms.
4. Run `grep -n 'unreadable\|generated\|awk' scripts/review/round-guard.sh`. It must print nothing, except a mention of #213 if your wording includes one.

## Change 2: `tests/scripts/round-guard.bats`

psak ran all 53 tests at 519b3f62 against this prototype. Exactly 12 flip, and they are all refusal rows: 7, 35, 38, 39, 40, 42, 43, 44, 45, 49, 50, 51.
- Rewrite each one to assert the new behaviour: status 0, the count shown, and `output` not containing "unreadable".
- Rename each to start with `edited footer is counted by its ids only (#213):`, followed by the old case words.
- Expected counts, default cap 10:

| Old test | Expected |
|---|---|
| 7 "unreadable run id" | `0 of 10` |
| 35 "altered digits after run=" (after `boundary_footers`) | `9 of 10` |
| 38 foreign footer bad run= | `0 of 10` |
| 39 run= without generated-by bad id | `0 of 10` |
| 40 run = with spaces bad id | `0 of 10` |
| 42 second bad run= with a good id | `1 of 10` |
| 43 generated-by line with no id | `0 of 10` |
| 44 truncated id | `0 of 10` |
| 45 id split across two lines | `0 of 10` |
| 49 64KB line ending in bare run= | `1 of 10`, still `[ "$SECONDS" -lt 2 ]` |
| 50 2-space gap | `0 of 10` |
| 51 tab gap | `0 of 10` |

Add these rows:
1. **"text can only raise R, never lower it"**: `boundary_footers` (9 rounds), then each R6 line: an NBSP in `run=` (`printf 'Generated-by: prp-review-agents v1 run\xc2\xa0=x\n'`), a ZWSP inside the tool name (`printf 'Generated by prp-review\xe2\x80\x8b-agents v1\n'`), a 21-character gap, and `Generated by Jenkins. prp-review-agents mentioned`. Expect status 0, `9 of 10` for all of them together, and no "unreadable".
2. **"no content makes the guard refuse"**: a loop over the 12 old refusal inputs plus the 4 R6 lines, each alone. Status must never be 2.
3. If no existing row already checks this: **"duplicate and case-variant ids count once"**: the same id three times, once upper-cased (`20261024t000000z-0000000A`) → `1 of 10`.

Keep every other existing row unchanged (Jenkins/graphviz/Sphinx 0, glued ids 3, cap/arg/input refusals).

## Validation

1. `bash -n`; `bats tests/scripts/round-guard.bats` (all pass, count printed); `bats -r tests` all pass.
2. Run the mawk suite as v4 Validation 3 describes. Every test must pass.
3. Real data: `--cap 999 < ~/tmp/rg-lastlines-sample.txt` → `rounds so far: 325 of 999; this is round 326`, exit 0.
4. Mutants. These replace v4/v5's; the refusal mutants no longer apply. Each must make a named row fail, and the PR body names the row:
   - **M1** (unbounded hex): `{8}'` → `+'` in `ID_RE`. The glued-ids row fails.
   - **M2** (no dedupe): `sort -u` → `sort`. The duplicate row fails.
   - **M3** (no case fold): delete `LC_ALL=C tr '[:upper:]' '[:lower:]' |`. The case-variant row fails.

## PR body

- Plan path: `.prp-output/plans/211-round-guard-v6.plan.md`. Commit it, and keep the older plans.
- Replace the Invariant and Verified-by lines with v6's.
- Add one paragraph: "Scope cut (stop rule, same family R1-R6): the guard no longer guesses at edited footers; it counts ids, and text can only raise R. Edited comments → #213."
- Mutant FAIL lines for M1-M3, the real-data line, the mawk totals.
- Under the follow-up section, list R5/R6 Suggestions and the pass-budget carry-overs (pass-budget.sh:70-77 and :90-93) as items for the PR's ONE follow-up issue. psak files that issue at merge, so the dev doesn't file it.

## Not building

- The ledger (#213).
- Any Unicode normalisation or near-miss detection.
- Changes to pass-budget.sh or #212.

# Plan: prp-framework#211: round-guard bounds the id and refuses unreadable ids (re-plan v4 after R4)

Author: psak. Under นุด's rule of 2026-10-24, psak writes every plan and the dev implements it exactly.
Date: 2026-10-24. Base head: df36a2fccdc20473ad78daa1a2f999d47d6c0b84 (v3, "count run ids, not footer shapes").
This plan supersedes `.prp-output/plans/211-round-guard-id-count.plan.md`. Keep both older plan files; they record the designs this one replaces.

## Why a third re-plan (same family in a 4th round)

R4 is run `20261024T154231Z-801d6028` on df36a2fc (comments 6386181823 / 6386182164 / 6386182563). It found 2 Critical:
1. **code-reviewer:** `[0-9A-Fa-f]+` is unbounded. Two ids written with no gap between them (`…-0000000a20261024T…-0000000b`) match as ONE token, so R undercounts.
2. **silent-failure-hunter:** a footer whose id is garbled or truncated (`run=2026-10-24T…`, `run=20261024T000000Z-`) contributes 0 and nothing refuses. That is the R1-R3 family ("a near-footer is silently ignored") again.

v3 was right to count ids rather than classify shapes. v4 keeps that and closes both holes with two small, closed rules (no shape grammar):
- the id is a fixed 8-hex width;
- a line refuses (exit 2) when a `run=` marker is not followed by a readable id, or when a `generated-by` line has no id anywhere.

## Invariant

**Invariant:** the round count R is the number of distinct run ids (`[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}`, lower-cased) in the input. A footer's round can go uncounted without a refusal only if its id is altered **and** the line loses both of its markers (the `run=` and the `generated-by`). At that point the line is no longer a footer, which is the same as deleting the comment.

**Verified by:**
- the boundary rows below: glued ids count 2, and every unreadable-id row refuses;
- one row per refusal rule that only that rule refuses;
- five mutants, each killed by a named row;
- the real-data run (`325 of 999`, exit 0) under both gawk and mawk.

**Boundaries, stated:**
- An id split across two lines refuses: the first half follows `run=` and is not a readable id.
- A 9-hex id (3 hand-built ones in the sample, e.g. `20261022T044148Z-312938296`) counts as its 8-hex prefix. Two ids that differ only in the 9th hex digit therefore count once. The review runner emits 8 hex, so only a hand-built id can hit this.
- `run` must start a word: `workflow_run=`, `rerun=` and the prose "did not run: it" are not markers. Only `run=` (optional spaces around `=`) is a marker; `run:` is not.
- **Fail-closed cost:** a foreign bot's last line `Generated-by: <tool> … run=<non-id>`, or a `generated-by` line with no id, refuses. This blocks the review rather than undercounting it. None of the 969 `generated.by` lines or the 970 `run=` markers in the sample does this.

## Real-data sample (Real inputs first)

`~/tmp/rg-lastlines-sample.txt` is read-only: 1255 real last lines from 75 PRs, taken with the caller's exact jq.
- 970 `run=` occurrences, every one followed by a readable id. 969 `generated.by` lines, every one with an id.
- 1043 lines contain `prp-review-agents`; 71 of them have no id (L2 markers `<!-- safe-merge-review: … tool=prp-review-agents … -->` and prose). So that word cannot be a refusal trigger, and v4 does not use it.
- Hex lengths: 980 are 8 hex and 3 are 9 hex. The sample has no glued ids.
- A first prototype that also treated `run:` as a marker false-refused line 1143 ("Deploy UAT did not run: it triggers only on `workflow_run` from…"). That is why only `run=` is a marker and `run` must start a word.
- Prototype (psak, scratch copy `~/tmp/rg4/round-guard.sh`): `--cap 999 < sample` prints `rounds so far: 325 of 999; this is round 326` with exit 0, under both gawk 5.2.1 and mawk 1.3.4 20240123. CI runs ubuntu-24.04, whose default awk is mawk.

## Change 1: `scripts/review/round-guard.sh` (only this file and the bats file change)

1. Replace the header Invariant comment with the Invariant and Boundaries above, in 6-10 comment lines.
2. Change the `ID_RE` line to:
   `ID_RE='[0-9]{8}[Tt][0-9]{6}[Zz]-[0-9A-Fa-f]{8}'`
3. Directly after the line `IN=$(cat) || { …; exit 2; }`, insert exactly:

```bash
# A footer whose id is unreadable must not vanish: refuse when a run= marker is not followed by an id,
# or when a generated-by line carries no id at all. "run" must start a word (workflow_run=, rerun= are not markers).
if ! printf '%s\n' "$IN" | LC_ALL=C awk -v id="$ID_RE" '
  { l = tolower($0); t = l
    while (match(t, /(^|[^a-z0-9_])run[[:space:]]*=[[:space:]]*/)) {
      rest = substr(t, RSTART + RLENGTH)
      if (match(rest, "^" tolower(id)) == 0) { bad = 1 }
      t = rest }
    if (l ~ /generated.?by/ && l !~ tolower(id)) { bad = 1 } }
  END { exit bad }'; then
  echo "error: a review footer has an unreadable run id — round count unknown, refusing" >&2; exit 2
fi
```

4. Update the usage comment so exit 2 reads: `bad argument, unreadable input, an unreadable run id, or grep failure (fail closed)`.
5. Change nothing else. The grep/rc block, the count, the cap block and the output text stay exactly as they are at df36a2fc.

## Change 2: `tests/scripts/round-guard.bats`

Keep every test. psak ran the current suite against the prototype; exactly these 4 flip.

| # | Old name | New name | New input / assertion |
|---|---|---|---|
| 7 | a footer with no run id is ignored | a footer with an unreadable run id refuses | same input (`run=BAD`): status 2, output has `unreadable run id` |
| 9 | ordinary last lines, null and blanks are ignored | ordinary last lines, null and blanks are ignored | drop the `Generated-by: someone-else v1 run=x` line from the input; still status 0, `this is round 1` |
| 34 | a 64KB line is processed in under 2 seconds | (same) | drop the trailing `' run='` from the python string; status 0, `SECONDS -lt 2` |
| 35 | a run id with altered digits is not counted (stated boundary) | a run id with altered digits after run= refuses | same input: status 2, `unreadable run id` |

Add these rows. Each one-line input is `printf '%s\n' '<line>'`, run with `--cap 10` unless a row says otherwise:
1. **"two glued ids count as two"**: `Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a20261024T000000Z-0000000b pass=x` → status 0, `rounds so far: 2 of 10`. Kills mutant 1.
2. **"a foreign footer with an unreadable run= refuses (fail closed)"**: `Generated-by: someone-else v1 run=x` → status 2.
3. **"a run= marker without generated-by refuses on a bad id"**: `prp-review-agents v1 run=2026-10-24T000000Z-0000000a pass=x` → status 2. Kills mutant 2.
4. **"a run = marker with spaces refuses on a bad id"**: `prp-review-agents v1 run = 2026-10-24T000000Z-0000000a pass=x` → status 2. Kills mutant 3.
5. **"a run = marker with spaces and a good id counts"**: `prp-review-agents v1 run = 20261024T000000Z-0000000a pass=x` → status 0, `1 of 10`.
6. **"a second bad run= on a line with a good id refuses"**: `Generated-by: prp-review-agents v1 run=20261024T000000Z-0000000a run=BAD` → status 2.
7. **"a generated-by line with no id refuses"**: `Generated by prp-review-agents v1` → status 2. Kills mutant 4.
8. **"a truncated id refuses"**: `Generated-by: prp-review-agents v1 run=20261024T000000Z- pass=code-reviewer` → status 2.
9. **"an id split across two lines refuses (stated boundary)"**: the two lines `Generated-by: prp-review-agents v1 run=20261024T00` and `0000Z-0000000a pass=x` → status 2.
10. **"run inside a word or prose is not a marker"**: the two lines `Deploy UAT did not run: it triggers only on workflow_run from main` and `rerun=yes; workflow_run=3` → status 0, `0 of 10`. Kills mutant 5.
11. **"an L2 marker is not a footer"**: `<!-- safe-merge-review: verdict=READY_TO_MERGE critical=0 important=0 agents=a tool=prp-review-agents head=abc -->` → status 0, `0 of 10`.
12. **"a 9-hex id counts as its 8-hex prefix (stated boundary)"**: footers with `run=20261022T044148Z-312938296` and `run=20261022T044148Z-312938297` → status 0, `1 of 10`.
13. **"a 64KB line ending in a bare run= refuses in under 2 seconds"**: the old test-34 input (with the trailing `' run='`) → status 2 and `SECONDS -lt 2`.

Update the comment block above the R2/R3 rows so it cites this plan.

## Validation

1. `bash -n scripts/review/round-guard.sh` exits 0.
2. `bats tests/scripts/round-guard.bats` passes every test; then the full suite `bats -r tests` passes.
3. The suite under mawk: make a scratch copy of the script with `LC_ALL=C awk ` replaced by `LC_ALL=C mawk `, point the bats file's `G` at that copy (scratch only, never committed), and run it. Every test must pass. Paste the totals into the PR body.
4. Real data: `bash scripts/review/round-guard.sh --cap 999 < ~/tmp/rg-lastlines-sample.txt` prints `rounds so far: 325 of 999; this is round 326` with exit 0.
5. Run each mutant on a scratch copy, confirm the named row FAILS, and revert:
   - **M1** (unbounded hex): `{8}'` back to `+'` in `ID_RE`. Row 1 fails.
   - **M2** (no run-marker rule): in the awk, change `if (match(rest, "^" tolower(id)) == 0) { bad = 1 }` to `… { bad = bad }`. Row 3 fails.
   - **M3** (no spaces around `=`): `run[[:space:]]*=[[:space:]]*` becomes `run=`. Row 4 fails.
   - **M4** (no generated-by rule): in the `generated.?by` line, `{ bad = 1 }` becomes `{ bad = bad }`. Row 7 fails.
   - **M5** (no word boundary): `(^|[^a-z0-9_])run` becomes `run`. Row 10 fails.

## PR body (replace the v3 section)

- The plan path: `.prp-output/plans/211-round-guard-v4.plan.md`. Commit it, and keep the two older plan files.
- The Invariant line plus the "Verified by:" line, both as written above.
- All five mutant commands, each with its FAIL line.
- The real-data output (`325 of 999`, exit 0), the mawk suite totals, and both 64KB timings.

## Not building

- Any footer-shape grammar or near-miss enumeration. The two rules above are closed and do not grow.
- Treating `prp-review-agents` or `run:` as markers (the sample shows both appear in non-footer lines).
- Any change to the caller (#212). Exit codes 0/2/3 keep their meaning for it.
- pass-budget.sh. R4's pass-budget Suggestions go to the follow-up issue.

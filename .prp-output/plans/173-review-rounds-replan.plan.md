# Plan: #173 review-rounds.py — re-plan after a repeated finding family (R1 → R2)

Issue: gobikom/prp-framework#160 (AC0.4). PR: gobikom/prp-framework#173.
Trigger: the review stop rule (นุด 2026-10-10) — the same finding family in 2 rounds means
re-plan with the invariant and a boundary test per arm, not a third patch.

Review runs: R1 `20261018T094902Z-8e1435b3` (head 858843f), R2 `20261018T100529Z-55b82879` (head d71010b).

## Repeated families

| family | R1 | R2 |
|---|---|---|
| F1 classifier arm untested | `unknown.jsonl` exists but no test references it | the fixture's prompt has no `--since-last-review`, so it classifies as `full-requested`; the `unknown` arm has no coverage |
| F2 a failure reads as data or crashes | blanket `except Exception` in `cmd_rounds` hides the error | the comment loop sits outside the new `try`, so a `body: null` or non-dict comment crashes the whole batch |

Both are symptoms of a missing invariant, not missing patches.

## Invariant I1 — every classifier arm is reached by its own fixture

Invariant: each `return` of `classify_mode` has a fixture whose ONLY route is that return,
and a bats test asserting the mode by name.

Boundary cases (one fixture per arm):

| arm | fixture | the evidence that routes it |
|---|---|---|
| full-requested | `full-requested.jsonl` | prompt has no `--since-last-review` |
| incremental (two-SHA) | `incremental.jsonl` | `git diff <sha> <sha>` tool_use |
| incremental (incr-diff file) | `incremental-diff-file.jsonl` (new) | `pr-N-incremental.diff` in a tool event |
| fell-back | `fell-back-no-prev.jsonl`, `fell-back-full.jsonl` | review-file check returns not-found |
| unknown | `unknown.jsonl` (fixed) | `--since-last-review` invoked, no diff and no not-found result |

Verified by: a bats test runs `fallback --json` over all arm fixtures and asserts the SET of
modes produced equals the set of arms {full-requested, incremental, fell-back, unknown}, so
a fixture that drifts to another arm fails the test (the failure F1 was).

## Invariant I2 — every failure is reported, scoped to the unit that failed, and the batch never crashes

Invariant: for any input, `review-rounds.py` either exits 0 with results, or reports each
failing unit (a PR for `rounds`, a line for `fallback`) as an error/skip, keeps the rest of
the batch, and exits non-zero (2 for a data error, 1 for usage). There are no uncaught
tracebacks.

Boundary cases:

| unit | bad input | expected |
|---|---|---|
| rounds: pulls fetch | missing fixture / gh error | that PR `status: error`, exit 2 (existing tests) |
| rounds: comments fetch | missing fixture | that PR `status: error`, exit 2 (existing test) |
| rounds: comment shape | a non-dict element in `comments` | that PR `status: error`, exit 2 (new) |
| rounds: comment body | `"body": null` | `status: error` for that PR, exit 2 (new) |
| rounds: batch | one PR errors, another is fine | the good PR is still reported (new) |
| fallback: line shape | a valid-JSON line that is not an object (`[1]`) | counted in `skipped_lines`, no crash (new) |
| CLI | `--repo` without a value; `--prs abc` | usage error on stderr, exit 1, no traceback (new) |

Verified by: the bats cases above, each asserting the exit code and that `Traceback` is
absent from the output.

Implementation: the whole per-PR body of `cmd_rounds` (fetch + parse + classify) runs inside
one `try`, with `(RuntimeError, OSError, ValueError, TypeError, AttributeError, KeyError)`
mapped to `status: error`; `_read_jsonl` counts a non-object line as skipped; argument
parsing validates before indexing.

## Revision 2 — R3 (run `20261018T102114Z-bafe73d6`, head 24728c0): the I2 table was incomplete

R3 found the same family a third time: `cmd_fallback` had no per-file guard, so a missing
path crashed the batch. Cause: the I2 boundary table above was built from the review findings,
not from the code, so it covered only the units the reviewers had already hit.

Fix to the method: the boundary list is now every input point in the script, taken from
`grep -nE 'open\(|json\.load|subprocess|int\(|args\[|raw_decode'`:

| # | input point | bad input | expected | test |
|---|---|---|---|---|
| P1 | fallback `open(path)` | missing / a directory / non-UTF-8 | listed in `errors`, excluded from counts, exit 2 | `fallback: I2 — a missing file …`, `… a directory and a non-UTF-8 file …` |
| P2 | fallback `json.loads(line)` | not JSON | skipped line | `fallback: truncated line counted` |
| P3 | fallback line shape | JSON, not an object | skipped line | `fallback: valid-JSON non-object lines …` |
| P4 | fallback paths | none given | usage, exit 1 | `fallback: no paths …` |
| P5 | rounds fixture / gh JSON | not JSON | that PR `status: error`, exit 2 | `rounds: non-JSON comments response …` |
| P6 | rounds `subprocess` gh | missing binary / non-404 failure | `OSError` / `RuntimeError` → `status: error` | covered by the same `except`; live gh is not run in tests (follow-up) |
| P7 | rounds comments shape | non-object / non-string body | `status: error` | `rounds: non-object comment …`, `… body null …` |
| P8 | CLI | missing value / non-integer `--prs` | usage, exit 1 | `rounds: --repo without a value …`, `… non-numeric --prs …` |

`fallback` now returns an exit code (0 all read, 2 any error) the way `rounds` already did.
`int(cm.group(2))` reads `\d+` only and cannot raise.

## Revision 3 — R5 (run `20261018T104358Z-cd554329`, head 0a77fda): enumeration cannot close this family

R5 found the I2 family a fourth time: `_extract_tool_events` called `.get()` on a `tool_use`
`input` that was not an object, and `classify_mode` ran outside the per-file guard. The rev2
method (grep for input CALLS) cannot see a shape assumption inside a `.get()` chain. Listing
spots is the wrong method; this revision changes the structure instead.

1. **Parse at the boundary.** `_normalise_event` is the only code that reads raw transcript
   JSON. It returns a fixed shape (`type`/`text` str, `blocks` of str fields); every wrong-type
   field becomes `""`/`[]` there. `_first_prompt` and `_extract_tool_events` read only that
   shape. (`rounds` already checks pulls/comments shape in `_rounds_from_comments`.)
2. **Guard every unit.** The whole per-file body of `fallback` and the whole per-PR body of
   `rounds` sit in one `try`. Expected bad input is mapped by type. Anything else is a bug: it
   is reported as `internal <Type>: <msg> at line N (<function>)` for that unit and makes the
   exit 2. It is never swallowed and never stops the batch.
3. **Verified by: shape mutation, not hand-picked cases.** `tests/bench/mutate_fixtures.py`
   replaces EVERY value inside the real fixtures (each path, the root included) with each of
   `None, 0, 1.5, True, "x", [], ["x"], {}, {"x": 1}`:
   - `fallback` over all 1332 transcript variants: exit 0, no traceback, `errors == []` (so the
     normaliser handles every shape; the catch-all of point 2 is never needed).
   - `rounds` over every pulls/comments variant of PR 77: never raises, exit only 0 or 2,
     never an `internal` error, and both exit codes occur.

Proof that the test detects the family: the 1332 variants run against the R5 head (0a77fda)
crash with `AttributeError: 'NoneType' object has no attribute 'get'` (exit 1); against this
revision they exit 0.

No behaviour change on real data: `fallback --json` over all 57 real review transcripts
(`~/.claude/projects/*rv-prp*/*.jsonl`) gives identical output before and after this revision.

Stop condition: if R6 or later finds this family again, the PR is closed and re-routed, not
patched.

## Out of scope (to the ONE follow-up issue)

Footer authorship is forgeable (security); the live `GhNotFound` path and the `gh api
--paginate` multi-document parser have no fixture-driven test; `not-found` drops the
endpoint from the log.

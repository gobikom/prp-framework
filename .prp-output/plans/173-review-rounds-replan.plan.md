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

## Revision 4 — R7 (run `20261018T111551Z-616b3373`, head 09f8017): scope cut, `rounds` moves to a stacked PR

R6 (`20261018T110101Z-5382492b`) and R7 core passes were 0C/0I, and the I2 family was judged
closed. R7's conditional agents (local aggregate, not posted) raised 5 Important findings. All are
in this PR's own diff, so none can go to an issue. Four are in the `rounds` subcommand: the
undocumented a/c/clean classes, the `_section_titles` header skip that only knows "severity", and
no test for the live `gh api --paginate` parser or the `GhNotFound` → `not-found` path. The fifth
is `docs/CONTRIBUTING.md` not listing the new suite.

Fixing all five here takes the PR past the 840-line hard stop (837 before the fix). So the scope
is cut, which the stop rule allows ("cut scope"):
- **This PR (#173):** the `fallback` classifier only, plus the CONTRIBUTING fix. The `rounds`
  code, its gh fixtures, its 17 tests and the `gh` mutation mode are removed. 18 bats tests pass.
- **Stacked PR (`feat/160-ac04b-rounds`, base this branch):** `rounds` back, with the four
  Important fixes and their tests. Its own review count starts at 0.

The review count of this PR restarts too: the head changes, so clean=0.

## Revision 5 — S1 (run `20261018T113756Z-703e6598`, head 4c5d0de): classifier precision, a new family

S1 found 0 Critical and 3 Important. This family is new (classifier precision), not F1/F2/I2:
1. `extra_tokens_delta` was a placeholder string. It is removed. AC0.4's token delta needs
   `review-cost.py` over the session and its sub-agent transcripts, so it ships with `rounds` in
   the stacked PR.
2. `has_incr_diff` also matched tool RESULTS, so a failed `cat pr-N-incremental.diff` read as
   incremental. Now each command is paired with its own result (by `tool_use_id`, else by order),
   and a diff command counts only when its result is not a not-found.
3. Any not-found result containing the word "review" read as fell-back. Now fell-back needs a
   not-found result of a command on the review file or `.prp-output/reviews`, or the assistant's
   AC0.4 phrases ("No previous review found" / "Running full review").

Invariant: a run is `incremental` only on a diff command that did not fail, and `fell-back` only
on evidence about the review file itself; otherwise it is `unknown`, never a guess.
Verified by: three new fixtures (`incr-diff-failed`, `review-word-not-found`, `paired-by-id`) that
the S1 head misclassifies and this head classifies correctly; all three join the 1332+ shape-mutation
run. Over the 60 real review transcripts, 7 runs change mode, all to the stricter side (fell-back →
unknown 4, incremental → fell-back 2, incremental → unknown 1).

## Revision 6 — S2 (run `20261018T115147Z-d693210b`, head e2684b2): same family again, so the representation changes

S2 found 1 Critical in the classifier-precision family of rev 5: a diff command with NO paired
result counted as incremental, because the result was `Optional[str]` and `_failed(None)` is
False, so absence read as success. Same family in two rounds → no third point-patch. The
representation is replaced instead.

Invariant: classification uses only tool calls whose outcome is KNOWN. Each tool call has exactly
one outcome, `ok` (a paired result that is not a not-found), `failed` (a paired not-found
result) or `missing` (no paired result), and `missing` is never evidence for any arm.

Pairing invariant: a result that carries a `tool_use_id` pairs only with the use of that id; a
result without one pairs with the earliest unpaired use that also has no id. A result that pairs
with nothing is an orphan. It is counted per session (`orphan_results`), never attached to a guess
and never dropped silently.

Boundary cases (one fixture per arm, each must fail on e2684b2 or be new behaviour):

| case | fixture | expected |
|---|---|---|
| diff command, no result | `incr-diff-no-result.jsonl` | `unknown` (e2684b2: incremental) |
| review-file command, no result | `review-file-no-result.jsonl` | `unknown` |
| result whose id matches no use | `orphan-id.jsonl` | the use stays `missing` → `unknown`, `orphan_results` 1 (e2684b2: paired by position → incremental) |
| id-less result after an id'd use | `id-use-idless-result.jsonl` | no positional pairing to the id'd use → `unknown`, `orphan_results` 1 |
| ok / failed / phrase arms | existing fixtures | unchanged modes |

### Rev 6 amendment: what counts as `failed` (from the real data, before S3)

Sample: every tool_result in the real transcripts that `fallback` reads. `is_error` is `False` in 1323
results, absent in 820, `True` in 69. Of the not-found lines, 17 name a review-target path, 17 are a
bare `NOT_FOUND` token, 26 are a line inside diff output, and 173 are other text. Treating "any line
contains not-found" as `failed` wrongly moved transcript `00ecdf39` from incremental to fell-back,
because the diff it fetched contained the string `NOT_FOUND`.

Rule: a result is `failed` when a not-found line names a review target
(`pr-N-agents-review.md`, `.prp-output/reviews`, `pr-N-incremental.diff`), or when the whole line is a bare
`NOT_FOUND…` token. A result with `is_error: true` that has a not-found line is also `failed`. One with no
not-found line gets a fourth outcome, `error`, which like `missing` is never evidence. Every other
result is `ok`.

| case | fixture | expected |
|---|---|---|
| diff output that contains `NOT_FOUND` | `diff-output-says-not-found.jsonl` | `incremental` |
| diff command, `is_error` true, no not-found line | `diff-command-errored.jsonl` | `unknown` |

Two more rules come from the same real-data run:

- **Evidence comes only from a shell command or a Read.** A tool_use's command is `input.command`,
  or a Read's `input.file_path`. Any other tool's input is not a command. In the real review
  sessions, 1164 Agent uses and 1100 Write uses name a review path, and e2684b2 treated all of them as
  commands on that file. A sub-agent prompt that mentions `pr-N-incremental.diff` and returns ok
  became false incremental evidence. Review prose saying "not found" became false fell-back evidence.
- **A replayed id pairs FIFO.** A resumed session replays history, so one `tool_use_id` can appear
  more than once (1408 repeated uses in the sample). Each id keeps a queue of unpaired uses. Before,
  a later copy overwrote the earlier one, which left it `missing` and made its result an orphan.

| case | fixture | expected (e2684b2) |
|---|---|---|
| Agent prompt names the incremental diff, result ok | `agent-prompt-names-diff.jsonl` | `unknown` (incremental) |
| Read of the incremental diff, result is diff text | `read-incremental-diff.jsonl` | `incremental` |
| same id used twice, two results | `replayed-id.jsonl` | `incremental`, `orphan_results` 0 |

Real-data measurement: the 212 sessions on this host whose first prompt is
`/prp-core:prp-review-agents`, run through e2684b2 and then through rev6.

| mode | e2684b2 | rev6 |
|---|---|---|
| full-requested | 118 | 118 |
| incremental | 51 | 50 |
| fell-back | 16 | 8 |
| unknown | 27 | 36 |
| errors | 0 | 0 |

Every session whose mode changed was checked, by the shape of its evidence lines only: matched
token, line length, path-shaped tokens.
- **9 fell-back → unknown.** The only "failed" evidence was a not-found phrase in review prose, or in a
  result about some other path, such as a missing review clone. None of it was about the review file.
- **1 incremental → fell-back (6c45fd03).** Its incremental diff command failed, and the review-file
  read returned a bare `NOT_FOUND`.

Transcript `00ecdf39` is incremental again. Rev6 also reports 22 `orphan_results` across the 212
sessions: results with more copies than their uses. They are counted and never paired by guess.

Verified by: the nine rev6 fixtures plus every existing arm fixture, the shape-mutation run over all
of them (exit 0, `errors == []`), and `bats tests/bench/review-rounds.bats` at 31/31.

Stop condition: if a later round finds this family again, the PR is closed and re-routed.

## Out of scope (to the ONE follow-up issue)

Footer authorship is forgeable (security); the live `GhNotFound` path and the `gh api
--paginate` multi-document parser have no fixture-driven test; `not-found` drops the
endpoint from the log.

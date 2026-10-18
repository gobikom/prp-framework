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

## Out of scope (to the ONE follow-up issue)

Footer authorship is forgeable (security); the live `GhNotFound` path and the `gh api
--paginate` multi-document parser have no fixture-driven test; `not-found` drops the
endpoint from the log.

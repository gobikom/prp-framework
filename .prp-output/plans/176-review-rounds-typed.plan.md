---
status: pending
runner: python3 -I + bats
mode: full
issue: gobikom/prp-framework#176
replaces: gobikom/prp-framework#173 (closed at round 10, same finding family x5)
---

# Plan: review-rounds.py with one typed normalisation boundary (#160 AC0.4, re-route of #173)

## Summary
Re-ship #173's read-only `review-rounds.py fallback` classifier, built around one boundary that turns each raw transcript record into typed values with an explicit `UNKNOWN`. #173 failed 5 times on one family: an ambiguous field read as a definite value (absent `tool_result`, then non-Bash inputs, then `is_error` via `is True`). Each fix patched one field. This plan removes the family by construction: the classifier never sees raw JSON, and any `UNKNOWN` it would read forces `mode=unknown`.

## User story
As the #160 owner measuring how often `--since-last-review` falls back to a full review,
I want a classifier whose counts are never inflated by malformed transcript fields,
so that the fallback rate reported for AC0.4 is trustworthy.

## Metadata
| | |
|---|---|
| Type | REFACTOR + BUG_FIX (re-ship of closed #173) |
| Complexity | MEDIUM: one script, its tests and fixtures; parser work, so design-first |
| Runner | `python3 -I` (stdlib only); tests `bats` |
| Test | `bats tests/bench/review-rounds.bats` |
| Lint / type / build | none in repo for bench scripts; `python3 -I -m py_compile scripts/bench/review-rounds.py` |
| Size cap | ≤ 800 changed lines, this plan included. At > 840 stop and split (the field-arm table tests move to a stacked PR). |

## Invariant
**Invariant:** every value `review-rounds.py` reads from a transcript record passes through ONE function, `_normalise_event`. It returns typed values in which each field is either a value of its expected type or the sentinel `UNKNOWN`, and it records the name of each field that came out `UNKNOWN`. No other function reads raw JSON. If any field the classifier reads is `UNKNOWN` in a session, that session's mode is `unknown`: never `incremental`, `fell-back` or `full-requested`. The session's `unknown_fields` lists the field names.

**Verified by:** the field-arm table tests (one row per field × value, below), plus a source check that the classifier functions never call `.get(` (only `_normalise_event` and `_read_jsonl` may).

## Real inputs (sampled 2026-10-18, 212 review sessions, list from #173 plan Rev 6 `review-sessions.txt`; counts in `~/tmp/rr-field-types.out`)
| field | observed | decision |
|---|---|---|
| record `type` | str 56538 | str else UNKNOWN |
| `message` | absent 31304 (system/summary records), dict 25234 | absent → no blocks (legit); non-dict → UNKNOWN |
| `message.content` | list 24499, str 735 | str / list; absent → no blocks; other → UNKNOWN |
| block | always dict | non-dict → UNKNOWN |
| `block.type` | text 9624, tool_use 8823, tool_result 6298, thinking 4813, tool_addition 291 | str; unrecognised strings are ignored (not evidence); non-str → UNKNOWN |
| `tool_use.id` | str 8823 (never absent) | non-empty str else UNKNOWN (no id-less pairing any more) |
| `tool_use.name` | str 8823 | str else UNKNOWN |
| `tool_use.input` | dict 8823 | dict else UNKNOWN |
| `Bash.command` | str 6095 | str else UNKNOWN |
| `Read.file_path` | str 235 | str else UNKNOWN |
| other tools' input | — | not a command: `None` (legit, never evidence) |
| `tool_result.tool_use_id` | str 6298 | non-empty str else UNKNOWN |
| `tool_result.is_error` | False 3455, **absent 2655**, True 188 | `type(v) is bool` → v; absent → False (absent is how successes are written, per the data); anything else (null, 0, 1, str, list, object) → UNKNOWN |
| `tool_result.content` | str 5064, list 1234 (items text 1198, tool_reference 36) | str; list → join the `text` of items whose `type` is "text" (other dict items ignored); a non-dict item, absent or other → UNKNOWN |

All 212 sessions are fully well-typed, so the strict rule changes no real classification. That is a gate in Task 5.

## Patterns to mirror (SOURCE: codebase, /home/goko/tmp/wt-prp-160-ac04 @68b179e)
- `scripts/bench/review-rounds.py:51-76`: today's `_normalise_event`. Same location and role, but `""` / `False` / `[]` defaults become `UNKNOWN` per the table.
- `:97-105` `_outcome`, `:107-130` `_tool_calls` (FIFO per-id pairing, orphans counted), `:139-156` `classify_mode`, `:158-201` `cmd_fallback` (error list, exit 2): keep them, reading only typed fields.
- `tests/bench/review-rounds.bats:9-171` (31 tests), `tests/bench/mutate_fixtures.py` (wrong-type variants: `WRONG = [None, 0, 1.5, True, "x", [], ["x"], {}, {"x": 1}]`).
- Fixture shape: today's fixtures omit `id`/`name`/`tool_use_id`, which real data never does. They are rewritten to the real shape (Task 3).

## Files to change
| file | action |
|---|---|
| `scripts/bench/review-rounds.py` | CREATE (from 68b179e, refactored per Tasks 1–2) |
| `tests/bench/review-rounds.bats` | CREATE (from 68b179e; id-less tests replaced, field-arm tests added) |
| `tests/bench/mutate_fixtures.py` | CREATE (from 68b179e plus a `field-arms` mode; guarded file read) |
| `tests/bench/fixtures/*.jsonl` | CREATE (68b179e set, real shape; drop `id-use-idless-result`) |
| `docs/CONTRIBUTING.md` | UPDATE lines 42, 56, 211-212 (test list and count; fix the stale "18 test cases") |

## NOT building
- The `rounds` subcommand (gh api) and the extra-tokens delta: stacked PR (`~/tmp/wt-prp-160-ac04b`), rebased after this merges.
- Any change to `review-cost.py` or the review skill.

## Tasks
1. **Typed boundary.** Add a module-level `UNKNOWN` sentinel (a unique object with `__repr__` "UNKNOWN"). `_normalise_event(obj)` returns `{"type", "text", "blocks", "unknown": [field names]}`, following the decision column of the real-inputs table exactly. It is the only function that calls `.get(` on transcript data. Block fields are `type`, `text`, `command` (str | None | UNKNOWN), `content` (str | UNKNOWN), `id`, `tool_use_id`, `is_error` (bool | UNKNOWN).
   - GOTCHA: `isinstance(True, int)` is true, so `is_error` uses `type(v) is bool`.
   - GOTCHA: absent `message` is legit (31304 real records). Do not mark it UNKNOWN.
   - VALIDATE: `python3 -I -m py_compile scripts/bench/review-rounds.py`.
2. **Classifier on typed values.** `classify_mode` returns `(mode, invoked, orphans, unknown_fields)`.
   - If any event's `unknown` list is non-empty: `mode="unknown"`, `invoked=None` when the first prompt itself is UNKNOWN, else the real flag.
   - A tool call whose use or paired result carries UNKNOWN is outcome `UNKNOWN`, never evidence.
   - `_outcome`: an `is_error` result whose not-found line is not about the target is `ERROR`, not `FAILED` (the #173 round-10 Suggestion).
   - `cmd_fallback`: JSON carries `unknown_fields` per session plus a total `sessions_with_unknown_fields`. The markdown adds a row. `fallback_rate` stays over `invoked is True` only.
   - VALIDATE: `bats tests/bench/review-rounds.bats`.
3. **Fixtures to real shape.**
   - Every `tool_use` gets `"id"` and `"name"`; every `tool_result` gets `"tool_use_id"`.
   - Delete `id-use-idless-result.jsonl` and its test. Add `idless-use.jsonl`: a use with no id → unknown.
   - VALIDATE: `bats tests/bench/review-rounds.bats` (all 30 carried tests pass).
4. **Field-arm table tests.** `mutate_fixtures.py field-arms <out_dir>` writes one variant per (field, value) from two base fixtures: `incremental.jsonl` (evidence: an OK two-SHA `git diff`) and `fell-back-full.jsonl` (a FAILED review-file command). It also writes a `expected.tsv` row per variant: `field<TAB>value<TAB>expected_mode`. One bats `@test` per field loops its rows and fails naming the field and value.
   - Fields: `is_error`, `tool_use_id`, result `content`, `command`, `file_path` (on a Read use), use `id`, `name`, `block.type`, `message`, `message.content`.
   - Values: absent, null, true, false, 0, 1, "x", [], {} (each field's legit values expect the base mode; every other value expects `unknown`), plus a replayed id (expects the base mode, orphans 0).
   - Wrap the mutator's own read in try/except: name the file on stderr, exit 2.
   - VALIDATE: `bats tests/bench/review-rounds.bats -f 'field-arm'`.
5. **Real-data gate.** Run old (e2684b2 copy `rr-old.py`), #173 (68b179e) and new over the 212 sessions, then diff per session (`rr-diff.py`). Expected: new == 68b179e for every session, and `sessions_with_unknown_fields` = 0. Any transition is listed in the PR body with its cause, or the PR does not open.
   - VALIDATE: `python3 -I scripts/bench/review-rounds.py fallback --json $(cat review-sessions.txt) | python3 -I -c 'import json,sys;d=json.load(sys.stdin);print(d["sessions_with_unknown_fields"],d["incremental"],d["fell_back"],d["unknown"],d["full_requested"])'`
6. **Docs.** CONTRIBUTING lines 42, 56, 211-212: the test count from `grep -c '^@test'`, with no hand-typed number elsewhere.

## Testing strategy and edge cases
- Field-arm table (Task 4) is the invariant test, one row per arm.
- Kept from #173: replayed id (FIFO), orphan result, missing result, diff output containing NOT_FOUND, Agent prompt naming the diff, Read of the diff, non-UTF-8 / directory / missing file → errors + exit 2, non-object lines skipped, no-write source check.
- No-write check: widen the regex to append-mode `open(..., "a")`, `os.remove`, `os.unlink` and `shutil.` (#173 Suggestion).
- Source check: `.get(` appears only inside `_normalise_event` / `_read_jsonl` (awk over function bodies).

## Validation commands
1. `python3 -I -m py_compile scripts/bench/review-rounds.py`
2. `bats tests/bench/review-rounds.bats`
3. `bats tests/bench/*.bats tests/scripts/*.bats` (full suite, as CI runs it)
4. Database: N/A (no DB).
5. Browser: N/A (CLI).
6. Manual: Task 5 real-data gate output pasted in the PR body.

## Docs impact
`docs/CONTRIBUTING.md` only (dev-only bench script, not installed into consumer projects).

## Gate Compliance
N/A, checked against each category:
- no consumer-facing command or skill changes;
- no install path (bench scripts are excluded from `install.sh`);
- no workflow change (CI already runs `tests/bench/*.bats`);
- no schema, flag or billing.

The PR touches `scripts/**` so it gets the `ci-change` label per the merger policy.

## Acceptance criteria
- The invariant holds: field-arm table all green, and the source check passes.
- The 30 carried tests are green on real-shape fixtures.
- Real-data gate: new == 68b179e on 212 sessions, `sessions_with_unknown_fields` 0.
- ≤ 800 changed lines.
- Review stop rule: 2 consecutive `--l2-comments` rounds at 0C/0I. **Stop condition:** this family (an ambiguous field read as a definite value) found again → the invariant is wrong; stop and re-plan, no patch.

## Risks
| risk | likelihood | mitigation |
|---|---|---|
| Strict rule hides real sessions as unknown | low (0 of 212 have UNKNOWN) | Task 5 gate; `unknown_fields` named per session |
| Over 800 lines | medium | plan is short; split field-arm tests to stacked PR at 840 |
| A future Claude Code transcript shape (new block type) | medium | unrecognised `block.type` strings are ignored, not UNKNOWN; non-string types are UNKNOWN |

## Confidence
8/10 (Patterns 2, Gotchas 2, Integration 2, Validation 1, Testing 1). The field table is mechanical; the risk is size.

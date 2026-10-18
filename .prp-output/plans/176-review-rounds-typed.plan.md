---
status: implemented
runner: python3 -I + bats
issue: gobikom/prp-framework#176
replaces: gobikom/prp-framework#173 (closed at round 10, same finding family x5)
---

# Plan: review-rounds.py with one typed normalisation boundary (#160 AC0.4, re-route of #173)

## Summary
Re-ship #173's read-only `review-rounds.py fallback` classifier around one boundary that turns each raw transcript record into typed values with an explicit `UNKNOWN`. #173 failed 5 times on one family: an ambiguous field read as a definite value (absent `tool_result`, then non-Bash inputs, then `is_error` via `is True`). Each fix patched one field. This plan removes the family by construction: the classifier never sees raw JSON, and any `UNKNOWN` forces `mode=unknown`. Goal: a fallback rate for AC0.4 that malformed fields can never inflate.

Type REFACTOR + BUG_FIX; complexity MEDIUM (parser work, so design-first). Stdlib Python run with `python3 -I`; tests `bats tests/bench/review-rounds.bats`; no lint/build for bench scripts (`python3 -I -m py_compile`). Size cap ≤ 800 changed lines, this plan included; > 840 → split.

## Invariant
**Invariant:** every value `review-rounds.py` reads from a transcript record passes through ONE boundary, the `_norm_*` functions (`_norm_event` and the helpers it calls). It returns each field as a value of its expected type or the sentinel `UNKNOWN`, and records the name of each field that came out `UNKNOWN`. No other function reads raw JSON. If any field is `UNKNOWN` in a session, that session's mode is `unknown`, never `incremental`, `fell-back` or `full-requested`, and `unknown_fields` lists the names.

**Verified by:** the field-arm table tests (one row per field × value, below), a mutation check (weakening the `is_error` type test makes the table fail), and a source check that `.get(` appears only in `_norm_*` / `_read_jsonl`.

## Real inputs (sampled 2026-10-18: 212 review sessions, the #173 Rev 6 list; per-field type counts)
| field | observed | decision |
|---|---|---|
| record `type` | str 56538 | str else UNKNOWN |
| `message` | absent 31304 (system/summary records), dict 25234 | absent → no blocks (legit); non-dict → UNKNOWN |
| `message.content` | list 24499, str 735 | str / list; absent → no blocks; other → UNKNOWN |
| block | always dict | non-dict → UNKNOWN |
| `block.type` | text 9624, tool_use 8823, tool_result 6298, thinking 4813, tool_addition 291 | str; unrecognised strings ignored (not evidence); non-str → UNKNOWN |
| `tool_use.id` / `.name` / `.input` | str / str / dict, 8823 each, never absent | non-empty str / str / dict, else UNKNOWN (no id-less pairing any more) |
| `Bash.command`, `Read.file_path` | str 6095, str 235 | str else UNKNOWN; other tools' input is not a command (`None`, never evidence) |
| `tool_result.tool_use_id` | str 6298 | non-empty str else UNKNOWN |
| `tool_result.is_error` | False 3455, **absent 2655**, True 188 | `type(v) is bool` → v; absent → False (how successes are written); anything else → UNKNOWN |
| `tool_result.content` | str 5064, list 1234 (items text 1198, tool_reference 36) | str; list → join the `text` of `type=="text"` items; a non-dict item, absent or other → UNKNOWN |

All 212 sessions are fully well-typed, so the strict rule should change no real classification. That is the Task 5 gate.

## Patterns to mirror (#173 head 68b179e)
`_outcome`, `_tool_calls` (FIFO per-id pairing, orphans counted), `classify_mode`, `cmd_fallback` (error list, exit 2) are kept, reading only typed fields. The 31 bats tests and `mutate_fixtures.py transcripts` (wrong-type variants) are kept. Today's fixtures omit `id`/`name`/`tool_use_id`, which real data never does; they move to the real shape.

## Files
| file | action |
|---|---|
| `scripts/bench/review-rounds.py` | CREATE (68b179e, refactored per Tasks 1–2) |
| `tests/bench/review-rounds.bats` | CREATE (68b179e; id-less test replaced, field-arm + source tests added) |
| `tests/bench/mutate_fixtures.py` | CREATE (68b179e + `field-arms` / `check` modes; guarded reads, exit 2) |
| `tests/bench/fixtures/*.jsonl` | CREATE (68b179e set in real shape; `id-use-idless-result` → `idless-use`) |
| `docs/CONTRIBUTING.md` | UPDATE (suite list, test count, file table) |

NOT building: the `rounds` subcommand (gh api) and the extra-tokens delta (stacked PR, rebased after this merges); any change to `review-cost.py` or the review skill.

## Tasks
1. **Typed boundary.** Module-level `UNKNOWN` sentinel (its truth value raises, so it cannot be read as a bool by accident). `_norm_event(obj)` returns `{"type", "text", "blocks", "unknown"}` per the decision column. GOTCHA: `isinstance(True, int)` is true, so `is_error` uses `type(v) is bool`. GOTCHA: absent `message` is legit.
2. **Classifier on typed values.** `classify_mode` returns `(mode, invoked, orphans, unknown_fields)`; any UNKNOWN → `unknown` before pairing (`invoked=None` when the first prompt is UNKNOWN). `_outcome`: an `is_error` result whose not-found line is not about the target is ERROR, not FAILED (#173 round-10 Suggestion). `cmd_fallback`: per-session `unknown_fields`, total `sessions_with_unknown_fields`, a markdown row; `fallback_rate` over `invoked is True` only.
3. **Fixtures to real shape.** Every use gets `id` + `name`, every result `tool_use_id`. `idless-use.jsonl` (a use with no id) → unknown, `unknown_fields == ["tool_use.id"]`.
4. **Field-arm table.** `mutate_fixtures.py field-arms` writes one variant per (field, value) and an `expected.tsv` whose expectations are hand-written (the oracle, never derived from the script); `check` names every mismatch. Fields: `is_error`, `tool_use_id`, `content` (each on an incremental and a fell-back base), `command`, `file_path` (Read), `id`, `name`, `block.type`, `message`, `message.content`. Values: absent, null, true, false, 0, 1, "x", [], {}, plus a replayed id (base mode, 0 orphans). One bats test per field.
5. **Real-data gate.** Run 68b179e and the new script over the 212 sessions; diff mode / invoked / orphans per session. Expected: 0 differences, `sessions_with_unknown_fields` 0. Any transition is listed in the PR body with its cause, or the PR does not open.
6. **Docs.** CONTRIBUTING suite list, count (`grep -c '^@test'`), file table.

## Validation
`python3 -I -m py_compile scripts/bench/review-rounds.py`; `bats tests/bench/review-rounds.bats`; `bats tests/bench/*.bats tests/scripts/*.bats` (as CI runs it); Task 5 output in the PR body. No DB, no browser. Docs impact: CONTRIBUTING only (dev-only bench script, excluded from `install.sh`). Gate compliance: no consumer command/skill, install path, workflow, schema or flag change; `scripts/**` → label `ci-change`.

## Acceptance criteria
- Field-arm table and source check green; the mutation check fails the table.
- Carried tests green on real-shape fixtures.
- Real-data gate: 0 per-session differences from 68b179e on 212 sessions; `sessions_with_unknown_fields` 0.
- ≤ 800 changed lines.
- Review stop rule: 2 consecutive `--l2-comments` rounds at 0C/0I. **Stop condition:** this family (an ambiguous field read as a definite value) found again → the invariant is wrong; stop and re-plan, no patch.

## Risks
| risk | mitigation |
|---|---|
| Strict rule hides real sessions as unknown (0 of 212 today) | Task 5 gate; `unknown_fields` named per session |
| A future transcript shape (new block type) | unrecognised `block.type` strings ignored; non-string types UNKNOWN |
| Over 800 lines | plan kept short; split at 840 |

---
status: planned
issue: gobikom/prp-framework#178
parent: gobikom/soul-orchestra#1367 PR-C0 (plan feat/1367-review-rules-ce @ 82f06b5, devlead-codex APPROVE; sections R2-1, R2-2, R3-1, R3-2)
runner: bats (tests/commands/l2-comments.bats) + python3 -I
---

# Plan: --l2-comments start comment, review-findings block, Prior findings (#178)

## Summary
SO#1367's Rule E counts a review round only from a server-timestamped start comment posted before any pass runs. Rule C needs each pass's findings as structured data, plus an itemized closure of the previous round's findings with a regression test. Today `--l2-comments` posts three prose comments and draws the run id at posting time, after the agents. This PR adds the three pieces to the posting format.

Nothing reads them yet. They are inert until SO#1367 PR-A changes merger's policy. Type ENHANCEMENT, MEDIUM (format/parser work → design-first). Size target ≤ 600 changed lines; regenerated adapters excluded.

## Invariant
**Invariant:** in an `--l2-comments` run, the PR receives exactly one start comment, posted before any review agent starts. It carries the reviewed head and the run id that the run's pass comments use. Each pass comment carries a one-line `review-findings` JSON that `scripts/review/validate-findings.py` accepts, for the same head and pass, with `complete: true`. Its critical and important counts equal the comment's two heading counts.

Every existing L2 format rule still holds. In particular, nothing the new sections add can be read as a second `Reviewed head:`/`Passes run:`/`Generated-by:` line, a severity heading, or `safe-merge-review` text by the three current readers (cited below).

**Verified by:** bats tests that run the extracted Step A / Step C fences:
- Step A posts one start comment, and nothing else, before Step C.
- Step C refuses every malformed arm listed under boundary cases.
- A fixture body that injects a heading, footer or marker inside the JSON or Prior findings is refused.
- A replay of the three real readers' selection expressions (copied verbatim, quoted below) over the full comment set of a run selects exactly the three pass comments.

## Real readers sampled (2026-10-18; these are the parsers the new comments must not disturb)
| reader | selection / checks (verbatim) | effect of the new comments |
|---|---|---|
| ops `bin/safe-merge` (master, lines 485–515) | line 1 `== "Reviewed head: $head"`; `grep -ciP '^###\s+(Critical\|Important)\s+Issues' == 2`; footer = last non-blank line matched by `^Generated-by: prp-review-agents v… run=… pass=$pass$` | start comment: line 1 is `Review started:` → not selected. JSON is one line starting `{`, and Prior findings lines start `- ` → no heading match. The footer stays last. |
| soul-skills `cloud-delegate` L2 recipe (main, lines 330–380) | `select(.body \| startswith("Reviewed head: $L2_SHA"))`; `^\s{0,3}#{1,6}\s+(Critical\|Important)\s+Issues` count 2; no `safe-merge-review:` | same as above |
| soul-orchestra `.github/merger-policy.yaml` `review_evidence` (main, lines 150–157) | "THREE per-pass comments … line 1 exactly 'Reviewed head: <head>' … last line 'Generated-by: … pass=<pass>'"; "A ROUND is … three per-pass comments with the same Generated-by run id" | **A risk:** merger is an LLM reading this text. A 4th comment carrying the run id (`pass=start`) is not a per-pass comment by line 1, but the text does not say so. Mitigation: the PR body states it, and the first merger verdict after merge is the live check (AC5). If merger rejects, SO#1367 PR-A carries the sentence; until then PR-C0 is reverted rather than patched. |
| psak `~/tmp/prov-tick.sh`, per-pass count query | `test("^Reviewed head: <sha7>")` | not selected |

Schema sampled: `schemas/review-findings.schema.json` @ 0aac4e1. `family` is OPTIONAL and `evidence` is free text, so no schema change is made. Missing `family` is allowed here; it makes merger's ID impossible and so voids Rule C (SO#1367 R2-2 "fail closed"), which is merger's job.

## Design
1. **Step A moves before the agents** (new position: right after 2.0b, before 2.1.1). It keeps everything it does today (run id, version, tier, run file) and then posts the start comment:
   ```
   Review started: head=<REVIEWED_HEAD_SHA> run=<RUN_ID>
   Generated-by: prp-review-agents v<PRP_VERSION> run=<RUN_ID> pass=start
   ```
   - It re-reads the PR head first; a moved head posts nothing.
   - It records the start comment URL in the run file (5 keys).
   - A failed post is FATAL: no agents start.
   - "Output → Per-pass L2 comments" keeps Steps B/C and points back to Step A.
2. **Agents emit the JSON.** Each core agent prompt gains one instruction: end the reply with a fenced `review-findings` block of that pass's findings, per the schema, with `family` set on every critical/important finding. The orchestrator copies the block into the body; it never writes findings for an agent. Severity mapping is the agents' existing one: High → important.
3. **Body format** (Step B). After `### Could not verify`, before the footer:
   ```
   ### Prior findings
   - <id12> resolved <file>:<start>-<end> regression_test: <path>::<name>|none
   - <id12> open regression_test: none
   (or the single line "None." when the previous round had no critical/important finding for this pass,
    or "Not recorded: the previous round has no review-findings block." )

   ```review-findings
   {"reviewed_head":"…","pass":"…","complete":true,"findings":[…]}
   ```
   ```
   - IDs come from a new helper, `scripts/review/prior-findings.py`. It takes the previous round's pass comment bodies (fetched by Step B with `gh api --paginate`, the latest complete run before this one, same pass), extracts their `review-findings` JSON and prints `id12 file start end severity family` for critical/important findings. The ID is `sha256("pass|file|start|end|family|summary")[:12]`, matching SO#1367 R2-2.
   - No family → the helper prints `-` for the ID and the line becomes `- - open …`, so Rule C stays void.
   - The helper is read-only, uses stdlib only and runs with `python3 -I`.
4. **Step C adds these checks** through one helper, `scripts/review/check-l2-body.py <body> <head> <pass>`, run as `python3 -I "$PRP_DIR/scripts/review/check-l2-body.py"`. It is the installed framework's copy and is called once per pass after the existing checks. It exits 0 for valid, 1 for invalid (reasons on stderr) and 3 for usage/IO, and nothing posts unless every pass gets exit 0. The run file gains `START_URL` (5 keys) and Step C refuses a run file without it. The helper checks:
   - exactly one `### Prior findings` heading;
   - exactly one ```` ```review-findings ```` fence, holding exactly one line;
   - `validate-findings.py` exits 0 on it, using the installed framework's copy (`$PRP_DIR/scripts/review/validate-findings.py`, never the PR's);
   - `reviewed_head` = the run file's head, `pass` = PASS, `complete` = true;
   - the count of `severity=="critical"` = the Critical heading N, and the same for important;
   - every Prior-findings item line matches `^- ([0-9a-f]{12}|-) (resolved|open) [^ ]+:[0-9]+-[0-9]+ regression_test: ([^ ]+::.+|none)$`, and an `open` item has `regression_test: none`. Otherwise the section is exactly `None.` or one `Not recorded: …` line;
   - order: `### Could not verify` < `### Prior findings` < the fence < the footer, with only blank lines between the fence and the footer;
   - every critical/important finding has `family`.

   Draft helpers (not wired, untested) are on branch `feat/178-pr-c0-wip` @ ef4a6b7: `check-l2-body.py`, `prior-findings.py` (input: a TSV `created_at\tbase64(body)` from `gh api --paginate .../issues/N/comments`), and `178-wip-step-a-draft.md` (the new 2.0c Step A). The implementer may rewrite them; the plan, not the draft, is the spec.
5. **Test stub change:** the `gh pr comment` stub logs a body whose line 1 is `Review started:` to `$START_LOG`, not `$WORK_LOG`, so the existing "3 comments posted" counts still hold. A `FAIL_START` env var makes the start post fail. A `gh api` stub prints `$FAKE_COMMENTS_TSV`. The validator, schema and helpers are copied into the fixture `.prp` checkout.

   The existing whole-file checks (one `Reviewed head:`, one footer, two severity headings, no `safe-merge-review`) already cover injection through the JSON; the new tests pin that.

## Boundary cases (each a bats test)
- P1: a well-formed run → start comment posted first, then 3 pass comments, all with one run id.
- P2: Step A with a moved head → nothing posted, no agents (FATAL).
- P3: a failed start post → FATAL, the run file is not usable by Step C.
- P4: a pass comment without the fence, with two fences, or with a two-line JSON → nothing posted.
- P5: invalid JSON, or JSON that the schema refuses → nothing posted.
- P6: JSON for another head or another pass, or `complete:false` → nothing posted.
- P7: JSON critical count ≠ heading N (each direction), and the same for important → nothing posted.
- P8: a JSON `summary` containing `\n### Critical Issues (0 found)`. Escaped `\n` stays on one line, so it is accepted. A raw newline breaks the one-line rule, so it is refused.
- P9: a JSON string containing `safe-merge-review` → refused by the existing check.
- P10: a Prior-findings line in a bad shape (no `regression_test:`, a bad ID, `resolved` without a range) → nothing posted.
- P11: `prior-findings.py` on bodies without a fence → "Not recorded", exit 0. On a missing family → `-` ID. On malformed JSON → exit 2, Step B stops.
- P12: reader replay. The three verbatim selection expressions above, run over {start, 3 passes, a plain "abandoned" comment}, select exactly the 3 pass comments, and safe-merge's heading counts equal the JSON counts.
- P13: the trivial tier → start comment, then one `code-reviewer` comment with JSON.

## Files
| file | action |
|---|---|
| `prompts/review-agents.md` | UPDATE: Step A moved and extended; agent prompts + JSON instruction; body format; Step C checks |
| `adapters/*` (6) | REGENERATE (`python3 scripts/generate-adapters.py`) |
| `scripts/review/prior-findings.py` | CREATE (~60 lines) |
| `scripts/review/check-l2-body.py` | CREATE (~70 lines) |
| `tests/scripts/check-l2-body.bats` | CREATE (P4–P10 at the helper level; the l2-comments.bats arms run it through Step C) |
| `tests/commands/l2-comments.bats` | UPDATE: `body()` emits the new sections; P1–P13 |
| `tests/scripts/prior-findings.bats` | CREATE (P11) |
| `docs/CONTRIBUTING.md`, `CHANGELOG.md` | UPDATE |

## Acceptance criteria
- AC1: the bats suites pass, P1–P13 included, as does `bats tests/commands/*.bats tests/scripts/*.bats tests/bench/*.bats` (as CI runs it).
- AC2: the adapters regenerate with no diff left over (`generate-adapters.py` then `git diff --exit-code adapters/`).
- AC3: mutation check. Removing the JSON-count check from Step C makes P7 fail.
- AC4: ≤ 600 changed lines excluding adapters.
- AC5 (live, after merge): the first `--l2-comments` round on the next PR (prp#177) posts a start comment before its passes. psak's L2 recipe and safe-merge accept that round, and merger's verdict on it does not cite the start comment. A failure → revert this PR (safe-merge), never patch forward.
- Review stop rule: 2 consecutive `--l2-comments` rounds at 0C/0I. Stop condition: the same finding family twice → re-plan.

## Not building
- Any stop-rule or merger-policy change (SO#1367 PR-A).
- A schema change.
- The reference checker (PR-A).
- #154 (on hold).
- Running regression tests: that is merger's job (R3-2).

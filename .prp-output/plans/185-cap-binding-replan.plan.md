---
status: pending
runner: bash + python3 (scripts repo — no package manager)
mode: replan
pr: 185
plan: cap-enforcement binding (BLOCKED-REPLAN)
created: 2026-10-20
head-at-planning: 9cfdde735ca005f3a5b993ca2435512075499af0
---

# Plan — 185-cap-binding-replan: machine-bind the L2 per-pass body to this run's validator output

## Summary

PR #185 reached the 10-round cap with two open Importants from the R7 family ("a cap
breach or dropped finding gets lost"): a stale `pr-{N}-l2-<pass>.fence` / `.fence.ok`
from an earlier attempt survives every Step A cleanup list (comment 6287513115), and
nothing machine-binds the posted body to `.fence.ok` — the orchestrator copies line 1
and the CAP lines by following prose only (comment 6287514348). This plan re-plans the
cap-enforcement **binding**: run-stamped artifact names, a bind manifest, a
`check-l2-body.py --bind` gate run before posting, a widened Step A cleanup, boundary
tests for every arm, and a re-route onto a fresh PR. PLAN ONLY — nothing here is
implemented by this plan.

## Invariant

`Invariant: the findings and L2-FINDING-CAP lines in each posted per-pass body are exactly the validator's output for THIS run (same run id), checked by a machine gate before posting; no artifact from an earlier attempt, run or PR can be consumed or posted.`

Boundary cases (one test per arm, see "Boundary Tests"):

- (a) a stale `.fence` exists and the agent wrote no new fence → FATAL;
- (b) a stale `.fence.ok` exists → not consumed;
- (c) the body omits the CAP lines that `.fence.ok` has → FATAL;
- (d) the body's JSON line differs from `.fence.ok` line 1 → FATAL;
- (e) a fence or `.fence.ok` carries a different run id or PR number → FATAL;
- (f) a clean match → passes;
- (g) cleanup removes `*.fence` and `*.fence.ok` in Step A, across all 6 adapters.

## User Story

As a review consumer (safe-merge review gate, merger, นุด)
I want every posted per-pass L2 body to be provably the validator's output for the run
it claims to be from
So that a dropped finding or an unposted cap breach can never reach a merge decision
silently.

## Problem / Solution

**Problem (specific, testable):** In the 2.0c pipeline at head 9cfdde7, Step B
(`prompts/review-agents.md:1412-1416`) validates a filename-fixed
`pr-{NUMBER}-l2-<pass>.fence` into `pr-{NUMBER}-l2-<pass>.fence.ok`, and Step C
(`prompts/review-agents.md:1426`, `:1486-1488`) assembles the body from that file by
prose instruction. Three machine gaps: (1) Step A's cleanup
(`prompts/review-agents.md:505`) does not remove `*.fence` / `*.fence.ok`, so an
artifact from a dead run (e.g. R9's 1b33d983) can be consumed as this round's output;
(2) no check compares the posted body's JSON line and CAP lines to `.fence.ok`
byte-for-byte; (3) no artifact carries run identity — the fence JSON schema has no
run-id field, and nothing binds PR number either.

**Solution:** make run identity and content binding machine-checked: run-stamped
artifact filenames (`pr-{N}-l2-<pass>.<RUN_ID>.fence/.ok/.bind`), a 3-line bind
manifest (run, pr, sha256 of `.fence.ok`), a `--bind` mode in `check-l2-body.py` run
as a third Step C gate, and a widened Step A `rm` list — all flowing from the single
source `prompts/review-agents.md` into the 6 generated adapters.

## Metadata

| Key | Value |
|-----|-------|
| Type | BUG_FIX (gate hardening) / ENHANCEMENT of the L2 pipeline |
| Complexity | MEDIUM — 3 scripts + 1 prompt source + regenerated adapters + boundary tests; no API/DB |
| Systems | prp-framework review pipeline (prompts, scripts/review, adapters, tests) |
| Dependencies | none new (python3 stdlib, sha256sum, bats — all already used) |
| Task count | 8 |
| Runner | `bash` + `python3` (scripts repo — no lockfile) |
| Type Check | `python3 -m py_compile scripts/review/check-l2-body.py scripts/review/validate-findings.py` |
| Lint | N/A — repo configures no linter (verified: no ruff/flake8 config in repo) |
| Test | `bats tests/scripts/check-l2-body.bats tests/commands/l2-comments.bats` |
| Build | `python3 scripts/generate-adapters.py` (adapter regeneration; sync check below) |
| Monorepo | none |

## Assumptions (--no-interact)

1. **PR size vs the ≤ ~800 rule — measured, not assumed.** At 9cfdde7,
   `git diff origin/main...HEAD --shortstat` = 17 files, +2012/−285 (2297 changed
   lines); excluding the 6 generated adapter files = 11 files, +1244/−141 (1385).
   The re-route PR therefore CANNOT be ≤ ~800 total against origin/main while
   carrying #185's product paths, even with generated adapters excluded. Readings:
   (i) the budget binds THIS plan's increment (fix ≤ ~400 changed lines — met, see
   "PR size") with the 1385-line carry flagged for psak's explicit accept as
   already-reviewed content; (ii) strict-total reading forces splitting the carry
   into stacked PRs, which contradicts brief 8348's "one new PR". **Recommendation:
   (i).** This is an open decision for psak at plan check — do not implement either
   reading until psak confirms.
2. **"All 6 adapters"** = the 6 adapter files #185 touches (antigravity, claude-code,
   codex, gemini, opencode, thclaws). `scripts/generate-adapters.py:5` documents
   `prompts/` as the single source of truth, so the hand edit is
   `prompts/review-agents.md` only; adapters regenerate.
3. **Bind sidecar instead of a fence-JSON `run_id` field**: adding a key inside the
   posted JSON line would change the body contract consumed by safe-merge's L2 marker
   and the schema (`schemas/review-findings.schema.json`). A sidecar `.bind` file
   keeps the posted format byte-frozen. (The real fence JSON's top-level keys are
   `complete, findings, pass, reviewed_head` — no run id; finding keys are
   `category, evidence, family, file, lines, severity, summary`.)
4. **PLAN ONLY is honored over the skill's commit-artifact step** (brief: "Do not
   commit it yet", agent-devops#801 tension noted): the plan stays uncommitted in the
   #185 worktree for psak's check; the re-route PR commits it on the new branch.

## Real Inputs (sampled 2026-10-20, R8 + R10)

| Artifact | Path / ref | Shape |
|---|---|---|
| R10 fences | `~/tmp/wt-prp-178c0/.prp-output/reviews/pr-185-l2-<pass>.fence` | exactly 1 JSON line; 2644 B (code-reviewer) / 118 B (security) / 5305 B (silent-failure-hunter); keys as in Assumption 3 |
| R10 fence.ok | same dir, `pr-185-l2-<pass>.fence.ok` | 1 line each (line 1 = validated JSON); 0 CAPLINEs in R10 |
| R10 posted bodies | same dir, `pr-185-l2-<pass>.md` | 26 / 25 / 28 lines; `Review-mode: full`; footer run=20261020T084354Z-c5bec7ba |
| R10 run env | `pr-185-l2-run.env.used` | 7 keys: REVIEWED_HEAD_SHA, PRP_VERSION, RUN_ID, TIER, START_URL, MODE, ORCHESTRATOR_LOGIN |
| R8 posted bodies (CAP-carrying) | GitHub `#issuecomment-6285050625` | 28 lines, 1 `- L2-FINDING-CAP … not-posted` line, incremental |
| R8 posted bodies (CAP-heavy) | GitHub `#issuecomment-6285051569` | 30 lines, 5 CAPLINEs, incremental |
| Stale-consumption is real | R9 start `#issuecomment-6285204589` (run 20261020T065243Z-1b33d983 died on 429) | a dead run's intermediates stayed on disk until manually cleared — the exact arm-(a)/(b) scenario |
| CAPLINE shape | `scripts/review/check-l2-body.py:45` | `^- L2-FINDING-CAP (findings\|probe_requests)[N].(field) LEN>CAP not-posted$` |

## UX Design (artifact flow, not user UI)

```
BEFORE (prose-trusted)                      AFTER (machine-bound)
agent → pr-N-l2-<pass>.fence                agent → pr-N-l2-<pass>.<RUN_ID>.fence
        (fixed name; stale survives)                 (name carries THIS run)
validate --enforce-caps > .fence.ok          validate --enforce-caps > .<RUN_ID>.fence.ok
                                              + .<RUN_ID>.bind (run=, pr=, sha256=)
Step C: copies line 1 + CAPs by prose        Step C: check-l2-body --bind (3rd gate)
post body                                    post body  (byte-equal or FATAL, no post)
```

| Location | Before | After | Action | Impact |
|---|---|---|---|---|
| Step A (prompts:505) | rm list omits `*.fence`/`*.fence.ok` | rm includes `pr-{N}-l2-*.fence*` + `*.bind` | none (script) | stale artifacts gone each round (g) |
| Step B (prompts:1412-1416) | fixed fence name | run-stamped name + bind manifest | none (script) | stale cannot be found (a, b, e) |
| Step C (prompts:1486-1490) | 2 checker calls | + `--bind` as 3rd call before posting | none (script) | body == validator output (c, d, e, f) |

## Mandatory Reading (implementer)

- **P0** `prompts/review-agents.md` — Step A block at :505; agent fence contract :1355-1430; Step C gates :1480-1500 (file is 1728 lines; read those ranges)
- **P0** `scripts/review/check-l2-body.py` (248 lines, whole file) — CAPLINE :45, `check()` :108, `check_prior()` :160, argv dispatch :240
- **P0** `scripts/review/validate-findings.py` (192 lines) — `enforce_caps()` :138, `--enforce-caps` dispatch :165
- **P1** `tests/scripts/check-l2-body.bats`, `tests/commands/l2-comments.bats` (14 fence references — the pipeline-level harness)
- **P1** `scripts/generate-adapters.py` header (:5-6) + `adapters.yml`
- **P2** R8/R10 real inputs table above (shapes to build fixtures from)

## Patterns to Mirror

- **FATAL guard + stderr, fail-closed** — SOURCE: codebase (`prompts/review-agents.md:1415-1416`):
  `python3 -I …/validate-findings.py --enforce-caps "$D/….fence" > "$D/….fence.ok" || { echo "FATAL: …" >&2; exit 1; }`
  The new `--bind` call and the bind-manifest write copy this exact shape.
- **argv-dispatch CLI** — SOURCE: codebase (`scripts/review/check-l2-body.py:240`): `if len(sys.argv) == 6 and sys.argv[1] == "--prior":` → add a parallel `--bind` branch; exit codes 0/2/3 as documented in its header.
- **bats fixtures under `tests/scripts/fixtures/`** — SOURCE: codebase (`tests/scripts/` layout; existing check-l2-body.bats cases build fixture bodies inline — extend, don't invent a harness).
- **7-key run env as the run-identity source** — SOURCE: codebase (Step A writes `pr-{N}-l2-run.env` with RUN_ID; Step B already sources it for the MODE check). RUN_ID never comes from the agent.

## Files to Change

| File | Op | Insert At | Why |
|---|---|---|---|
| `prompts/review-agents.md` | UPDATE | :505 (Step A rm list); :1412-1416 (Step B fence names + bind write); :1426 (caps prose: name change only); :1486-1490 (Step C 3rd gate) | single source of truth for all adapters |
| `scripts/review/check-l2-body.py` | UPDATE | new `check_bind()` near `check_prior()` :160; dispatch near :240 | the machine gate (arms c/d/e/f) |
| `scripts/review/validate-findings.py` | UPDATE | ~:165 guard | refuse a missing input fence loudly (arm a) if not already fatal via shell redirect order — verify, only touch if needed |
| `tests/scripts/check-l2-body.bats` | UPDATE | new `@test` cases | arms c/d/e/f unit tests |
| `tests/commands/l2-comments.bats` | UPDATE | new pipeline cases | arms a/b/g Step A/B script tests |
| `tests/scripts/fixtures/` | UPDATE | new fixture files from Real Inputs shapes | stable, schema-valid inputs |
| `CHANGELOG.md` | UPDATE | top | entry per repo convention |
| `docs/CONTRIBUTING.md` | UPDATE | artifact-name references only if it names `.fence` files | #185 already touched it; keep names in sync |
| 6 adapter files under `adapters/` | REGENERATE | `python3 scripts/generate-adapters.py` | generated — no hand edits |

## Integration Points

- Step B fence run: `prompts/review-agents.md:1412-1416` — the extraction + `--enforce-caps` block gains the run-stamped name and the `.bind` write immediately after the redirect succeeds.
- Step C pass loop: `prompts/review-agents.md:1486-1490` — insert the `--bind` invocation beside the existing plain and `--prior` calls; it must run BEFORE any `gh pr comment` post.
- Run env: `pr-{NUMBER}-l2-run.env` RUN_ID key (already written by Step A) is the only legal RUN_ID source for stamping and checking.
- Sweep for other name references before renaming: `grep -rn '\.fence' scripts/ prompts/ tests/ docs/` (includes `scripts/verify-review-artifact.sh` — update if it greps the fixed name).

## NOT Building

- No change to the posted body format, the fence JSON schema, or safe-merge's L2 marker checks — the body contract stays byte-frozen (Assumption 3).
- No retry/resume of dead runs; R9 (1b33d983) stays dead. Orphan start comments are never edited or deleted.
- No fix for #185's other open Suggestions (they go to the follow-up issue per the stop rule).
- No implementation in this plan — PLAN ONLY (brief 8348).

## Step-by-Step Tasks

- **T1 — Widen Step A cleanup (arm g).** ACTION: UPDATE `prompts/review-agents.md:505`. IMPLEMENT: append `"$D"/pr-{NUMBER}-l2-*.fence "$D"/pr-{NUMBER}-l2-*.fence.ok "$D"/pr-{NUMBER}-l2-*.bind` to the `rm -f` list. MIRROR: the existing list's quoting style. GOTCHA: `{NUMBER}` is a shell-unquoted glob segment in the current line — keep the exact style so the generated adapters stay identical. VALIDATE: `grep -c 'l2-\*\.fence' prompts/review-agents.md` ≥ 1.
- **T2 — Run-stamp the fence artifacts (arms a/b/e).** ACTION: UPDATE Step B block (:1412-1416) and every Step C reference. IMPLEMENT: fence / ok / bind names become `pr-{NUMBER}-l2-<pass>.<RUN_ID>.fence|.fence.ok|.bind`, RUN_ID sourced from the run env; keep the existing `|| { echo FATAL; exit 1; }` so a missing fence for THIS run is a FATAL (arm a). Sweep all references per Integration Points. GOTCHA: a stale un-stamped or differently-stamped file must simply never match the lookup — do NOT add "fallback to the un-stamped name". VALIDATE: `grep -rn 'l2-<pass>\.fence' prompts/ scripts/ tests/` returns only run-stamped forms.
- **T3 — Bind manifest.** ACTION: after the `--enforce-caps` redirect succeeds, write `.<RUN_ID>.bind`: line 1 `run=<RUN_ID>`, line 2 `pr=<NUMBER>`, line 3 `sha256=$(sha256sum < .fence.ok | cut -d' ' -f1)`. MIRROR: Step A's env-write style. GOTCHA: write it only on the success path (after the guard), so a failed validation leaves no bind. VALIDATE: unit-tested via T6 cases.
- **T4 — `check-l2-body.py --bind` (arms c/d/e/f).** ACTION: UPDATE the script. IMPLEMENT: `check_bind(body, fence_ok, bind, env, pass)`: (1) body's review-findings JSON line byte-equals fence_ok line 1 else exit 2 (d); (2) set(body CAPLINEs) == set(fence_ok lines 2+) else exit 2 (c); (3) bind run == env RUN_ID and bind pr == the env file's `pr-{N}-` prefix and bind sha256 == sha256(fence_ok) else exit 2 (e); else exit 0 (f). Reuse the CAPLINE regex (:45) and the fence extraction already in `check()`. MIRROR: `check_prior()` argv style (:240). GOTCHA: compare SETS of CAPLINEs, not concatenations — order-insensitive, omission and injection both fail. VALIDATE: `python3 -m py_compile scripts/review/check-l2-body.py && bats tests/scripts/check-l2-body.bats`.
- **T5 — Regenerate adapters.** ACTION: run `python3 scripts/generate-adapters.py`; verify `git diff --exit-code -- adapters` after a clean regen cycle and that all 6 adapter files carry the new names. GOTCHA: never hand-edit adapters. VALIDATE: `grep -l '<RUN_ID>\.fence' adapters/*/…/prp-review-agents* | wc -l` = 6 (path forms differ per adapter).
- **T6 — Boundary tests (a)–(g).** ACTION: UPDATE both bats files + fixtures. IMPLEMENT: one `@test` per arm exactly as the Boundary Tests table maps them. MIRROR: existing bats style (inline fixtures, `run …`, `[ "$status" -eq 2 ]`). VALIDATE: `bats tests/scripts/check-l2-body.bats tests/commands/l2-comments.bats`.
- **T7 — Docs.** CHANGELOG entry; CONTRIBUTING artifact-name sync only if needed (grep first). VALIDATE: `grep -n 'fence' docs/CONTRIBUTING.md` reviewed.
- **T8 — Full validation + PR-size check.** Run every Validation Command below, then `git diff origin/main...HEAD --shortstat` and record the split (hand-written vs generated) in the PR body.

## Boundary Tests (one per arm)

| Arm | Test | File | Mechanism / assertion |
|---|---|---|---|
| (a) | stale fence + no new fence → FATAL | tests/commands/l2-comments.bats | fixture: stale `pr-9-l2-x.OLD_RUN.fence` present; Step B invoked with run env RUN_ID=NEW; expect non-zero + `FATAL` on stderr; no `.fence.ok` for NEW created |
| (b) | stale fence.ok not consumed | tests/commands/l2-comments.bats | fixture: stale `.<OLD_RUN>.fence.ok` with different line 1; run Step C; assert the stale file is never read (no body produced from it; bind check fails closed) |
| (c) | body omits CAPLINEs → FATAL | tests/scripts/check-l2-body.bats | fixture fence.ok with 1 CAPLINE (R8 shape: `#issuecomment-6285050625`); body without it; `--bind` → exit 2 |
| (d) | body JSON ≠ fence.ok line 1 → FATAL | tests/scripts/check-l2-body.bats | byte-flip one summary char (R10 fixture 118 B security fence); exit 2 |
| (e) | wrong run id / PR → FATAL | tests/scripts/check-l2-body.bats | bind `run=OLD` vs env RUN_ID; bind `pr=8` vs `pr-9-` env; sha256 mismatch; each exit 2 |
| (f) | clean match → passes | tests/scripts/check-l2-body.bats | R10 fixtures (body + fence.ok + bind agree); exit 0 |
| (g) | Step A cleanup across 6 adapters | tests/commands/l2-comments.bats + structure test | seed `pr-9-l2-x.fence`, `.fence.ok`, `.bind`; run Step A script; all gone; `grep -c 'l2-\*\.fence'` in each of the 6 generated adapter files ≥ 1 |

## Testing Strategy

- **Unit**: arms (c)–(f) in `tests/scripts/check-l2-body.bats`, fixtures cloned from the Real Inputs shapes (never live URLs, never secrets).
- **Integration (pipeline)**: arms (a)/(b)/(g) drive the Step A/B script fragments as the bats harness already does.
- **Test data**: `tests/scripts/fixtures/` — R8 CAP-carrying and R10 zero-cap variants both covered.
- **Edge cases checklist**: empty fence.ok (0 CAPLINEs) must pass cleanly (f); bind file missing → FATAL; fence.ok missing → FATAL; extra CAPLINE injected into body → FATAL (set inequality, not just omission).
- **Perf**: none (string/sha256 ops on ≤ 6 KB files).

## Docs Impact

CHANGELOG.md entry (repo convention) + CONTRIBUTING artifact-name references if present. No `packages/docs/` tree and no 13-locale docs exist in this repo — internal dev-tooling change with no user-facing product surface.

## Gate Compliance

Gate Compliance: internal-only with enumeration — no `packages/web` pages (no web app), no `/api` routes (scripts repo), no DB schema/entities (no database), no feature flags or billing (none), no new endpoints. This is the framework's own review tooling: the operative gates are the ones this plan STRENGTHENS (review stop rule, safe-merge L2 marker evidence), and the boundary tests are the compliance evidence. This project ships no `/gate` skill for its toolchain (bash/python — the `/gate` path is a claude-code-adapter feature of consumer projects), so no `/gate audit pre-implement` run; classification above stands for the L3 auditor.

## Validation Commands

| Level | Command |
|---|---|
| Static Analysis | `python3 -m py_compile scripts/review/check-l2-body.py scripts/review/validate-findings.py` |
| Unit Tests | `bats tests/scripts/check-l2-body.bats` |
| Full Suite | `bats tests/scripts/check-l2-body.bats tests/scripts/prior-findings.bats tests/scripts/review-schema.bats tests/commands/l2-comments.bats tests/commands/review-rounds.bats` |
| Database | N/A — no database in this repo |
| Browser | N/A — no browser surface |
| Manual | `python3 scripts/generate-adapters.py && git diff --exit-code -- adapters/ && grep -rn '\.fence' scripts/ prompts/ tests/ docs/ | grep -v '<RUN_ID>' | wc -l` (expect 0 stale fixed-name references) |

## PR size (the ≤ ~800 constraint)

**RESOLVED (psak, brief 20261020-1648-2d5a): reading (ii), stacked PRs.** Reading (i) is
rejected — the 1385-line carry is NOT already-reviewed content (#185 ended at the cap with
open Importants; the new PRs are reviewed fresh). This replaces "one new PR" (brief 8348,
psak's error) and supersedes Assumption 1's recommendation (i).

Measured carry at 9cfdde7, hand-written (generated adapters excluded):

| File | + | − |
|---|---|---|
| prompts/review-agents.md | 128 | 24 |
| scripts/review/prior-findings.py | 100 | 19 |
| scripts/review/validate-findings.py | 52 | 5 |
| scripts/review/check-l2-body.py | 33 | 10 |
| schemas/review-findings.schema.json | 6 | 1 |
| tests/commands/l2-comments.bats | 575 | 8 |
| tests/scripts/check-l2-body.bats | 80 | 42 |
| tests/scripts/prior-findings.bats | 167 | 29 |
| tests/scripts/review-schema.bats | 86 | 2 |
| CHANGELOG.md | 10 | 1 |
| docs/CONTRIBUTING.md | 7 | 0 |

Fix increment (estimated): prompts ~20 (stamped names + rm-glob + bind write + Step C third
gate), check-l2-body.py ~110 (`--bind` + dispatch), validate-findings.py ~10 (missing-input
guard), tests ~127 across three files, docs ~18. Total ≈ 265.

**The stack (3 PRs, cut by measurement; every PR ≤ ~800 hand-written changed lines):**

| PR | Files | Lines (measured + est.) | Base | Boundary arms |
|---|---|---|---|---|
| PR-1 — caps/prior engine | prior-findings.py, prior-findings.bats, validate-findings.py (+guard), schema, review-schema.bats (+arm-a refusal test, MINUS the two drift tests — deferred to PR-3) | 443 + ~20 = ~463 | origin/main | (a) script-side refusal |
| PR-2 — checker + `--bind` | check-l2-body.py (+`--bind`), check-l2-body.bats (+arm tests) | 165 + ~210 = ~375 | PR-1 branch | (b) (c) (d) (e) (f) |
| PR-3 — wiring + binding activation | prompts/review-agents.md (+fix), l2-comments.bats (+arm g), tests/commands/structure.bats (+adapter grep), CHANGELOG, CONTRIBUTING, review-schema.bats drift tests re-added from 9cfdde7; 6 regenerated adapters (excluded); plan artifact (excluded) | 753 + 24 + ~25 = ~802 | PR-2 branch | (g) + MUST re-add both deferred drift tests |

Drift-test deferral (remedy A, psak brief 20261020-1723-9dbe): the two review-schema.bats
drift tests (24 measured lines: "caps: the prompt states exactly the schema's length caps
(no drift)" and "caps: every regenerated adapter carries the prompt's cap tokens") move
from PR-1 to PR-3 — they assert PR-3's prompt/adapter cap tokens and can never pass
before PR-3 lands. PR-3 MUST re-add both tests verbatim from 9cfdde7 once its
prompts/adapters are in; if PR-3's realized size then exceeds ~800, move CHANGELOG.md
(11 lines) to PR-1 or PR-2 rather than trimming tests.

Only PR-3 changes `prompts/`, so only PR-3 regenerates the 6 adapters (per the rule:
regenerate in each PR that changes `prompts/`). Stack total ≈ 1640 hand-written lines
(1385 measured carry + ~255 fix), versus 2297 raw / 1385 hand-written for one-PR.

## Re-route (after psak checks this plan) — stacked PRs (psak brief 20261020-1648-2d5a)

1. **Stack mechanics**: PR-1 branches from `origin/main`; PR-2 branches from PR-1's branch;
   PR-3 branches from PR-2's branch. Each later PR is rebased onto `main` after the previous
   one merges. All three PR bodies carry this plan's path (Design-first). Commit the plan
   artifact itself on PR-1's branch (`git add -f .prp-output/plans/185-cap-binding-replan.plan.md`,
   agent-devops#801); it is a docs artifact, excluded from line counts.
2. **PR-1 — caps/prior engine** (files/lines per the PR-size table). Safe alone: it changes
   no prompts/wiring, so main's posting path is untouched; the new script modes
   (`--enforce-caps` plumbing, prior-findings) are invoked by nothing on main — code that
   nothing calls yet. No path is added where a body posts unbound or a stale fence is consumed.
3. **PR-2 — checker + `--bind`**. Safe alone: it only strengthens `check-l2-body.py`, which
   main's wiring calls in plain mode with the plain contract preserved (the CAPLINE rejection
   matches lines main's pipeline never emits; `--prior`/`--bind` are invoked by nothing yet).
   No new posting path.
4. **PR-3 — wiring + binding activation**. The only PR that changes `prompts/` (hence the
   only one regenerating the 6 adapters). It lands the 2.0c wiring TOGETHER with the
   run-stamped fence names, the bind manifest, the widened Step A cleanup and the Step C
   `--bind` gate in ONE diff — the first body posted under it is already machine-bound; there
   is never a merged state with new wiring unbound. Fail-closed out of order: if PR-3 merged
   without PR-1/PR-2, its gate would call a `check-l2-body.py` lacking `--bind` → checker
   fails → FATAL, nothing posted — never an unbound post.
5. **No `.prp-output/reviews/` content in any PR of the stack** (R10 verified the count at
   0; re-verify per PR: `gh pr diff <N> --name-only | grep -c '^\.prp-output/reviews/'` = 0).
6. **Review rounds per PR, fresh**: round 1 = FULL `/prp-core:prp-review-agents <N>
   --l2-comments` (no `--since-last-review`); stop rule 2 consecutive rounds 0 Critical /
   0 Important; cap 10; `--since-last-review` from round 2; merge via `safe-merge` only.
   Rounds do NOT carry across PRs of the stack.
7. **#185 gets NO more rounds** (10/10 used). Closing/re-routing #185 is psak's call, not
   this plan's.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Renamed artifacts break a consumer grepping the fixed name | Medium | Medium | T5 sweep (`grep -rn '\.fence' scripts/ prompts/ tests/ docs/`) + manual-level validation expecting 0 stale references |
| Step B guard ordering writes an empty `.fence.ok` before a failed validation | Low | High | keep redirect AFTER the rc guard pattern; T4 treats empty/short fence.ok as FATAL; arm-(a) test covers |
| Bind manifest spoofed alongside a doctored fence.ok | Low | High | sha256 binds content; run/pr bind identity; filename stamp binds lookup — three independent checks |
| Generated-adapter drift (hand edit sneaks in) | Low | Medium | `git diff --exit-code -- adapters/` after regen is a validation command |
| PR-size reading disputed at plan check | Medium | Low | Assumption 1 keeps both readings on record; nothing implements the re-route before psak confirms |

## Confidence Score

9/10 — Patterns: 2 (FATAL guard, argv dispatch, both cited) + Gotchas: 2 (glob style, set-compare) + Integration: 2 (line-anchored Step A/B/C + run env) + Validation: 2 (all levels pre-filled, boundary tests per arm) + Testing: 1 (unit + pipeline bats exist and are extended, but no CI run yet — PLAN ONLY).

## Acceptance Criteria

1. The invariant holds by machine: every posted per-pass body passed `check-l2-body.py --bind` against THIS run's `.fence.ok` + `.bind` before posting.
2. Boundary tests (a)–(g) exist, one per arm, and pass.
3. All 6 regenerated adapters carry the run-stamped names and widened cleanup.
4. `bats` suites green; py_compile clean; adapter regen idempotent (`git diff --exit-code -- adapters/`).
5. Fix increment ≤ ~400 changed lines (hand-written), measured and recorded in the PR body.
6. Re-route executed per the Re-route section ONLY after psak confirms the plan and the Assumption-1 size reading.

## Completion Checklist

- [ ] Static Analysis passes
- [ ] Unit Tests pass
- [ ] Full Suite passes
- [ ] Adapter regen sync check passes
- [ ] Boundary arms (a)–(g) each demonstrated
- [ ] PR-size split recorded
- [ ] Plan committed on the re-route branch (not before)

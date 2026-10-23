---
status: pending
runner: bats + python3 (no package manager)
mode: full
issue: gobikom/prp-framework#202
base: origin/main @ ee2b518
created: 2026-10-24
---

# Plan: `prp-plan` design alternatives + project-local verification map (autonomous)

## Summary

Three stacked PRs (A; B = script; C = prompts wiring B) to the canonical prompts in `prompts/`; adapters are regenerated with `scripts/generate-adapters.py`.

- **PR-A, design alternatives.** For Design-first work (gate, security, policy, parser, validator or scanner), `prp-plan` drafts 2–3 competing designs. Each design gets its own `Invariant:` and boundary-case table, and the plan selects one by a **mechanical** rule. The plan gains a required `## Invariant` section for that class. No human picks.
- **PR-B + PR-C, verification map.** `prp-verify --init` generates a committed, project-local `.prp-verify/feature-map.yaml` that maps each feature to a runnable exercise and its expected observable result. `prp-verify` then judges each matched AC by **running** that exercise, not by grepping the diff. It re-syncs stale entries, and reports env-limited ACs as **UNVERIFIED**. `run-all` stops and escalates on UNVERIFIED instead of merging. A bundled script, `scripts/prp-verify-map.sh`, does the mechanics.

## User Story

As an autonomous agent running `/prp-core:prp-run-all --no-interact`
I want the plan to have compared designs and the verify step to have exercised real behaviour
So that wrong designs are rejected before code and "PASS" means the behaviour was observed, with no human picking or approving

## Problem / Solution

**Problem (real data, sampled 2026-10-24).** Of 128 unique plans under `~/repos/*/*/.prp-output/plans/`:
- only **27 (21%)** carry an `Invariant:` line, and only **4 (3%)** compare alternatives, as free text. One example, `soul-orchestra-1351/.prp-output/plans/phase6-multi-task-orchestration-20260330.plan.md:50-53`, has three one-line rejections with no test per arm.
- `prompts/plan.md` has **no Invariant field at all** (`grep -n -i invariant prompts/plan.md` returns nothing). Phase 4 (`prompts/plan.md:391-413`) asks for `APPROACH_CHOSEN` / `ALTERNATIVES_REJECTED` as free text. The Design-first rule lives only in agent CLAUDE.md files, not in the prompt that writes the plan.
- `prompts/verify.md:83-103` judges every AC by **searching the PR diff** ("New feature → new function/class/endpoint in diff"). That contradicts our "AC = behavior, not grep" rule.
- `prp-qa` re-derives how to exercise each AC on every run. For example, `agent-vera-claude/.prp-output/qa/run-002-orchestra-goko-digital/qa-report.md` measured sidebar widths (208px → 56px) and localStorage keys by hand, and the next run starts over. Its AC6 was marked **FAIL** for what was really an env limit ("Native browser tooltip not capturable"), and today there is no UNVERIFIED verdict.

**Solution.** (A) put design comparison and the Invariant into the plan prompt, with a deterministic selection rule; (B) add a committed feature map that verify runs, with an honest UNVERIFIED verdict that blocks auto-merge.

## Invariant

**Invariant:** neither change needs a human to pick or approve anything, and neither weakens an existing gate.

1. For non-Design-first input, `prp-plan` output is unchanged in structure and cost.
2. Every plan still satisfies `plan-validate`. That tool checks for the presence of regex patterns (`soul-orchestra/scripts/plan-validate.py:35-40`), so additive sections cannot break it, but the plan verifies it anyway.
3. An AC that `prp-verify` marked PASS before must, after the change, be PASS (behaviour observed), FAIL, or UNVERIFIED. It is never dropped and never silently skipped.
4. `run-all` never auto-merges with `criteria_unverified > 0`.
5. The safe-merge verify gate keeps working: same artifact path `.prp-output/reviews/pr-{N}-verify.md` (`~/ops/bin/safe-merge:1354`), same frontmatter keys, and the `verdict` enum stays `PASS | FAIL | PARTIAL`. Only additive keys are allowed.
6. **A feature map makes verify mandatory.** Today Step 7.5 runs only with `--verify` (`prompts/run-all.md:44,79,631`). If `.prp-verify/feature-map.yaml` exists on the PR head, run-all forces `VERIFY = true`, and no flag can turn that off. This is recomputed from the file at Step 0 and again at `--resume`, never read from saved state alone. Step 8 additionally requires a verify artifact whose new `verified_sha` equals the PR head; otherwise it runs Step 7.5 first.
7. **A mapped AC is never judged by diff evidence.** Once an AC matches a live entry or a `removed:` tombstone, its verdict comes only from running the exercise, or else it is UNVERIFIED and escalated. That covers an invalid map, a tombstone, a failed sync, or an unavailable env. Diff evidence remains only for ACs that never matched any entry, live or removed.
8. **No vacuous entry.** An entry is written or kept only if it passes on HEAD **and** its negative proof fails: the exercise rerun in a scratch worktree with the entry's product `paths` deleted must not meet `expect`. A static denylist also rejects trivial exercises (`true`, `:`, `exit 0`, `echo …` alone, an empty command).

**Verified by:**
- `tests/commands/structure.bats` (new @tests pin the prompt text for A and B);
- `tests/scripts/verify-map.bats` (new; exercises `prp-verify-map.sh`);
- `tests/adapters/parity.bats` + `tests/scripts/generate-adapters.bats` (adapters regenerated, no drift);
- a recorded `plan-validate` run on the fixture plan for both arms.

All of them run in CI (`.github/workflows/ci.yml`, "Run the bats suites", where every `*.bats` file is counted).

### Boundary cases

| # | Case | Expected | Pinned by |
|---|---|---|---|
| A1 | Task not Design-first (e.g. "add a CLI flag to the README generator") | single design, no `## Design Alternatives` section; `## Invariant` optional | structure.bats: trigger list present; the rule says "otherwise skip" |
| A2 | Design-first by keyword or path (`.github/**`, `scripts/**gate*`, `*validat*`, `*pars*`, `*scan*`, `auth`, `policy`, `security`) or `--alternatives N` | 2–3 designs, each with Invariant + boundary table + one test per arm + estimated changed lines + files touched | structure.bats |
| A3 | Two designs survive and tie | tie-break: (1) the design covering all boundary cases → (2) smaller estimated changed lines → (3) fewer files touched → (4) lowest index (D1 = closest to the existing pattern). **Never AskUserQuestion**, including in interactive mode | structure.bats: the tie-break text and the literal "never ask" sentence |
| A4 | No design covers every boundary case | plan status `blocked-design`; record the uncovered cases; do not proceed to implement. `run-all` treats it as STOP + issue comment, not a question | structure.bats (plan.md + run-all.md text) |
| A5 | `--no-alternatives` on Design-first input | allowed, but the plan must record `Design alternatives: skipped — <reason>`; a blank reason is invalid | structure.bats |
| A6 | `plan-validate` on a fixture plan with alternatives | exit code identical to the same plan without the section | manual L6 step, recorded in the PR |
| B1 | No `.prp-verify/feature-map.yaml` | `prp-verify` behaves exactly as today (diff evidence) and adds one line: `No feature map — run {TOOL}:verify --init` | structure.bats |
| B2 | Map exists, AC matches an entry, exercise passes | PASS with evidence `map:<id> exit=0 matched=<expect>` | verify-map.bats `run` |
| B3 | Map exists, exercise fails, entry not stale | FAIL (behaviour), with the command output | verify-map.bats |
| B4 | Entry `env:` ≠ `local` and that env is unavailable | **UNVERIFIED**; `criteria_unverified` increments; never PASS | verify-map.bats (`run` exits 4 for env-unavailable) |
| B5 | Entry stale (`git diff --name-only <entry.synced_sha>..HEAD` touches its `paths:`) | `prp-verify-map.sh sync <id>` runs: it re-runs the positive check and the negative proof. On pass it advances that entry's `synced_sha`; on fail it exits 1, the entry stays stale and the AC is FAIL. The agent may rewrite `exercise`/`expect` first (prompt step), but only `sync` exiting 0 makes the new text count. Never skipped | verify-map.bats `sync`: stale→pass, stale→fail, stale→rewritten-then-pass |
| B6 | All of an entry's `paths:` deleted | `sync` moves it to `removed:` with an auto `removed_reason` (`paths deleted at <sha>`) and `removed_sha`. An AC that matches the tombstone is **UNVERIFIED + escalate**, with the tombstone cited, never diff evidence | verify-map.bats `sync` removed-case; `validate` rejects a tombstone without a reason |
| B7 | `run-all` sees `criteria_unverified > 0` | STOP auto-merge, comment on the issue/PR, add label `status:escalated`, report; no question | structure.bats (run-all.md text) |
| B8 | Map schema invalid (missing `expect`, unknown `env`, duplicate id) | `prp-verify-map.sh validate` exits 1 and lists every error. Verify then marks **every AC UNVERIFIED** (`criteria_unverified = criteria_total`, heading `VERIFY INCOMPLETE (invalid feature map)`) and escalates. It never falls back to diff evidence while a map file exists | verify-map.bats + structure.bats |
| B11 | Map present, run-all invoked without `--verify` (fresh, or `--resume` from a state saved with `VERIFY=false`) | `VERIFY` forced to true and logged as `feature map present → verify enforced`; Step 8 refuses unless the artifact's `verified_sha` equals the PR head | structure.bats (run-all.md Step 0 + resume + Step 8 text) |
| B12 | `--init`/`sync` gets a vacuous exercise (`true`, or a test that passes with the product paths deleted) | entry refused (`sync` exit 1: `vacuous: negative proof met expect`); `--init` lists it as not written | verify-map.bats `prove-negative` |
| B13 | Negative proof itself errors (worktree add fails, git missing) | exit 3 → entry not accepted; never treated as "negative proven" | verify-map.bats |
| B9 | Exercise hangs | `timeout` (default 120s per entry) → FAIL with `timeout`, never PASS | verify-map.bats |
| B10 | All adapters | regenerated; parity holds; no `{TOKEN}` leaks | parity.bats + generate-adapters.bats |

## Real inputs sampled (Real-inputs-first rule)

1. Plans: 400 plan paths across worktrees, deduped by basename to 128 unique; 27 with `Invariant:`, 4 with alternatives (commands in the PR body). Example quoted above.
2. Prompt sources: `prompts/plan.md:391-413` (Phase 4 text), `prompts/verify.md:79-103` (diff-grep verdicts) and `:113-170` (artifact format), `prompts/run-all.md:640-648` (PARTIAL proceeds to merge).
3. Consumers of the verify artifact: `~/ops/bin/safe-merge:1353-1371` checks **existence only** at `.prp-output/reviews/pr-${PR}-verify.md`, and only for `agent:`-labelled PRs. `prompts/done.md:100-112` (Gate 3) also checks existence. `prompts/run-all.md:642` reads `verdict`. No other consumer was found by grep across prp-framework, soul-orchestra and soul-skills. So frontmatter keys may only be added.
4. QA run: `agent-vera-claude/.prp-output/qa/run-002-orchestra-goko-digital/qa-report.md` shows hand-derived exercises and an env-limited AC6 recorded as FAIL. That is the motivation for `env:` and UNVERIFIED.

## Metadata

| Field | Value |
|---|---|
| Type | ENHANCEMENT |
| Complexity | MEDIUM (prompt + script + tests; no API or DB; touches the safe-merge-adjacent artifact contract additively) |
| Systems | `prompts/plan.md`, `prompts/verify.md`, `prompts/run-all.md`, `prompts/qa.md` (read-only hint), `adapters.yml` (verify argument-hint), new `scripts/prp-verify-map.sh`, new `schemas/verify-map.schema.json`, tests, regenerated `adapters/**` |
| Runner | none (no package manager): bats 1.13.0 + python3 with PyYAML (per `ci.yml`) |
| Type Check | n/a (prompts + bash) · `python3 -m json.tool schemas/verify-map.schema.json` |
| Lint | `bash -n scripts/prp-verify-map.sh` |
| Test | `bats tests/commands/structure.bats tests/scripts/verify-map.bats tests/adapters/parity.bats tests/scripts/generate-adapters.bats` · full: `bats -r tests` |
| Build | `python3 scripts/generate-adapters.py` then `git diff --stat adapters/` |

## UX Design

```
PR-A  BEFORE: plan → APPROACH_CHOSEN (free text) → implement → review finds design flaw → re-plan (round N)
      AFTER : plan ─Design-first?─no──► unchanged
                       └─yes─► D1..D3 {Invariant, boundary table, test/arm, est lines}
                               → mechanical select (cover-all → smaller diff → fewer files → D1)
                               → none covers all → status: blocked-design (STOP, no question)

PR-B  BEFORE: verify → grep diff for "evidence" → PASS
      AFTER : verify ─map?─no──► unchanged (+ hint --init)
                       └─yes─► AC↔entry match → stale? → --sync entry → run exercise (timeout)
                               → PASS (observed) | FAIL | UNVERIFIED (env) → artifact (+criteria_unverified)
              run-all: criteria_unverified>0 → STOP merge, escalate label + comment
```

| Location | Before | After | User action | Impact |
|---|---|---|---|---|
| `/prp-core:prp-plan` on gate/parser work | 1 design | 2–3 designs, mechanical pick | none (`--alternatives N` / `--no-alternatives <reason>` optional) | design flaws caught before code |
| `/prp-core:prp-verify --init` | n/a | writes `.prp-verify/feature-map.yaml` | run once per repo (or let run-all suggest it) | reusable behavioural checks |
| `/prp-core:prp-verify N` | diff grep | runs mapped exercises | none | PASS means observed |
| `/prp-core:prp-run-all --merge` | merges on PARTIAL | stops on UNVERIFIED | none | no silent merge of unverified ACs |

## Mandatory Reading

| Priority | File | Why |
|---|---|---|
| P0 | `prompts/plan.md:391-460` | where 4.1 is inserted |
| P0 | `prompts/verify.md` (whole, 220 lines) | the B rewrite of Phase 2/3 |
| P0 | `prompts/run-all.md:630-656` | verify handling before merge |
| P0 | `~/ops/bin/safe-merge:1353-1371` | the artifact contract that must not change |
| P1 | `scripts/generate-adapters.py` header + `adapters.yml:273-280` | regeneration; the verify entry's description and argument-hint |
| P1 | `tests/commands/structure.bats:1-40` | @test style for prompt pins |
| P1 | `tests/scripts/check-l2-body.bats`, `tests/scripts/scripts.bats` | bats style for bundled scripts |
| P2 | `schemas/review-findings.schema.json` | JSON-schema style |
| P2 | `soul-orchestra/scripts/plan-validate.py:35-75` | confirms additive sections are safe |

## Patterns to Mirror

**Free-text architecture block being extended.** SOURCE: codebase (`prompts/plan.md:401-413`)
```
APPROACH_CHOSEN: {description}
RATIONALE: {why this over alternatives — reference codebase patterns}

ALTERNATIVES_REJECTED:
- {Alt 1}: Rejected because {reason}
```

**Prompt structure pins.** SOURCE: codebase (`tests/commands/structure.bats:15-27`)
```
@test "plan.md contains Phase sections" {
@test "plan.md contains Validation Commands section" {
@test "plan.md specifies 90% coverage target" {
```

**Verify artifact contract (keep keys; add only).** SOURCE: codebase (`prompts/verify.md:137-150`)
```yaml
verdict: PASS | FAIL | PARTIAL
criteria_total: {N}
criteria_passed: {N}
criteria_failed: {N}
criteria_partial: {N}
```

**Consumer (existence only).** SOURCE: codebase (`~/ops/bin/safe-merge:1354-1356`)
```bash
VERIFY_ARTIFACT=".prp-output/reviews/pr-${PR}-verify.md"
if [[ "$LOCAL_EVIDENCE" != "1" || ! -f "$VERIFY_ARTIFACT" ]]; then
```

**run-all verdict table being tightened.** SOURCE: codebase (`prompts/run-all.md:644-648`)
```
| VERIFY PASSED (with gaps) | WARN: "Verify has partial coverage — proceeding to merge." Proceed to Step 8. |
```

## Files to Change

| PR | Action | File | Est. lines | Insert at |
|---|---|---|---|---|
| A | UPDATE | `prompts/plan.md` | +75 | new `### Phase 4.1: DESIGN ALTERNATIVES (Design-first only)` after the Phase 4 Document block (line 413), before `### Design Doc Integration`; add `## Invariant` + `## Design Alternatives` to Plan Structure (after line 504's list item 3); add flags `--alternatives N` / `--no-alternatives <reason>` to the Phase 0 flag table |
| A | UPDATE | `prompts/run-all.md` | +6 | Step 2 plan handling: `status: blocked-design` → STOP + comment (A4) |
| A | UPDATE | `tests/commands/structure.bats` | +35 | after the line-27 block |
| A | REGEN | `adapters/**` | generated | `python3 scripts/generate-adapters.py` |
| B | CREATE | `scripts/prp-verify-map.sh` | ~260 | subcommands `validate`, `stale`, `match <ac-text>`, `run <id>`, `prove-negative <id>`, `sync <id>` |
| B | CREATE | `schemas/verify-map.schema.json` | ~70 | |
| B | CREATE | `tests/scripts/verify-map.bats` | ~300 | temp git repos |
| B | CREATE | `tests/scripts/fixtures/verify-map/*.yaml` | ~70 | good + each invalid shape |
| C | UPDATE | `prompts/verify.md` | +130 | new `### 0.4 Load Feature Map`; Phase 2 branch: mapped/tombstoned → run or UNVERIFIED, never-mapped → existing diff evidence; verdict table + `🔍 UNVERIFIED`; frontmatter adds `criteria_unverified`, `map_entries_run`, `map_synced`, `verified_sha`; any UNVERIFIED → `PARTIAL` + heading `VERIFY INCOMPLETE (…)`; new `## Init Mode (--init)` and `## Sync Mode (--sync)` |
| C | UPDATE | `prompts/run-all.md` | +20 | Step 0 + `--resume`: map present → `VERIFY = true` (B11); Step 7.5 heading/skip-condition updated; table row `criteria_unverified > 0` → STOP + escalate (B7) placed **before** the PARTIAL row; Step 8 prerequisite `verified_sha == head` when map present |
| C | UPDATE | `prompts/qa.md` | +12 | `0.2` reads mapped entries as exercise hints; `env:` informs the environment check |
| C | UPDATE | `adapters.yml:273-280` | 2 | verify argument-hint `[--init] [--sync [id]]` |
| C | UPDATE | `tests/commands/structure.bats` | +40 | verify + run-all pins |
| C | REGEN | `adapters/**` | generated | |
| C | UPDATE | `README.md`, `CHANGELOG.md` | +25 | docs |

Estimates (generated adapters excluded): PR-A ≈ 120, PR-B ≈ 700 (the script and its tests ship first and are inert until C calls them), PR-C ≈ 230. All are under 800. Generated diff is measured at implement time with `git diff --stat origin/main -- adapters/` and reported in each PR body. Non-generated lines are measured with `git diff --shortstat origin/main -- . ':!adapters'`, and over 800 means split again before opening.

## Deviation from issue #202 (recorded, resolved here)

The issue proposed generating a project-local `.claude/skills/verify/` (+ adapters) per project. This plan instead ships **one framework script + a committed data file** (`.prp-verify/feature-map.yaml`) consumed by the existing `{TOOL}:verify` command. The reasons:
- `verify` already exists in all 6 adapters, so "no adapter drift" holds by construction, with no per-project generated skill ×6 to keep in sync;
- the map is data, so it can be validated mechanically (`validate`, `prove-negative`), whereas a generated per-project skill is prose that cannot be;
- an adapter-neutral path works for codex/kimi/etc.

The issue's acceptance intent is met: there is a project-local feature → exercise → expected map, verify/qa use it when present, and maintain mode re-syncs it. Action: comment this deviation on #202 and update the issue's "What B" text when PR-B opens.

## Feature map format (PR-B)

```yaml
# .prp-verify/feature-map.yaml  — committed; generated by {TOOL}:verify --init
version: 1
features:
  - id: review-l2-comments            # [a-z0-9-]+, unique
    summary: "review-agents posts 3 per-pass comments with Generated-by footer"
    match: ["l2-comments", "per-pass comment", "Generated-by"]   # AC text keywords (case-insensitive)
    paths: ["prompts/review-agents.md", "scripts/review/**"]
    surface: cli                        # cli | api | ui | lib
    env: local                          # local | uat | staging | browser | creds:<NAME>
    exercise: "bats tests/commands/l2-comments.bats"
    expect: { exit: 0 }                 # exit | stdout_regex | http_status | json_path
    timeout: 120
    synced_sha: <full sha>              # per entry; advanced only by `sync` exit 0
    negative_proof: { sha: <full sha>, exit: 1 }   # exercise with product paths deleted did NOT meet expect
removed:
  - id: old-feature
    removed_reason: "paths deleted in <sha>: feature dropped by #123"
    removed_sha: <sha>
```

The `run` exit contract: 0 = expectation met; 1 = not met (FAIL); 3 = tool or internal error, reported as FAIL with the reason and never PASS; 4 = env unavailable (UNVERIFIED). Env availability is checked mechanically: for `uat`/`staging` the URL in `PRP_VERIFY_<ENV>_URL` must answer `curl -fsS -m 10`; for `browser`, `npx playwright --version` must succeed; for `creds:<NAME>`, the env var name must be set (checked by name only, never printed).

## Integration Points

- `prompts/plan.md` Phase 4 → the new 4.1 feeds `## Design Alternatives` and `## Invariant` into the Phase 6 Plan Structure.
- `prompts/run-all.md` Step 2 (plan) → reads plan frontmatter `status`; Step 7.5 (verify) → reads artifact frontmatter `criteria_unverified`.
- `prompts/verify.md` Phase 0 → calls `.prp/scripts/prp-verify-map.sh` (the framework is installed at `.prp` in projects via the symlink or submodule; mirror how `prp-validate.sh` is referenced in implement.md).
- `scripts/generate-adapters.py` → all 6 adapters; `adapters.yml` for metadata.
- No change to `~/ops/bin/safe-merge` or `prompts/done.md`, since the artifact path and existence are unchanged.

## NOT Building

- Multi-model review (นุด skipped it 2026-10-24).
- Parallel sub-agent design generation (pstack `arena`). v1 drafts designs inline; sub-agents are a possible follow-up if quality needs it.
- Formal verification (TLA+/Lean/Kani).
- Changing safe-merge to read verify verdicts. That is a separate gate change and would need its own plan.
- Auto-generating Playwright UI exercises in `--init`. `ui` entries may be written by hand or by qa; `--init` covers `cli`/`api`/`lib` from existing tests and scripts.

## Step-by-Step Tasks

### PR-A

**Task A1. UPDATE `prompts/plan.md`: flags.** Add `--alternatives N` (2 ≤ N ≤ 3) and `--no-alternatives "<reason>"` rows to the Phase 0 flag table.
- VALIDATE: `grep -n -- "--alternatives" prompts/plan.md`

**Task A2. UPDATE `prompts/plan.md`: Phase 4.1.** Write the trigger list (A2), the per-design template, and the selection rule (A3) with the literal sentence **"Selection is mechanical — never ask the user to pick a design, in any mode."** Add the A4 `blocked-design` outcome and the A5 skip-with-reason rule.
- Per-design template:
  ```
  ### D{n}: {name}
  Invariant: {property}
  | Boundary case | Handled how | Test (one per arm) |
  Est. changed lines: {N} · Files: {list}
  Covers all boundary cases: yes|no (missing: …)
  ```
- Selection record:
  ```
  SELECTED: D{n} — rule step {1-4} decided
  REJECTED: D{m} — {failed step + detail}
  ```
- GOTCHA: keep the existing `APPROACH_CHOSEN` block for non-Design-first tasks (A1). Phase 4.1 *replaces* `ALTERNATIVES_REJECTED` only when triggered.
- VALIDATE: `bats tests/commands/structure.bats`

**Task A3. UPDATE `prompts/plan.md`: Plan Structure.** Add item `**Invariant** (required for Design-first; "Invariant: <property>" + "Verified by: <check>")` and item `**Design Alternatives** (Design-first only)`. Add frontmatter `status: pending | blocked-design`.
- VALIDATE: `grep -n "Verified by:" prompts/plan.md`

**Task A4. UPDATE `prompts/run-all.md`.** In Step 2, if plan `status: blocked-design`, STOP. Comment the uncovered boundary cases on the issue (`gh issue comment`) and add label `status:escalated`. No AskUserQuestion.
- VALIDATE: `grep -n "blocked-design" prompts/run-all.md`

**Task A5. UPDATE `tests/commands/structure.bats`.** Pins:
- plan.md contains `Phase 4.1: DESIGN ALTERNATIVES`;
- the trigger keywords;
- the tie-break order;
- the "never ask the user to pick" sentence;
- `blocked-design`;
- `Invariant:` + `Verified by:`;
- `--no-alternatives`;
- run-all.md contains `blocked-design`.
- MIRROR: `structure.bats:15-27`
- VALIDATE: `bats tests/commands/structure.bats`

**Task A6. REGEN adapters.**
- VALIDATE: `python3 scripts/generate-adapters.py && bats tests/adapters/parity.bats tests/scripts/generate-adapters.bats && git status --porcelain adapters | wc -l` (non-zero: commit the regenerated files)

**Task A7. Record the A6 boundary.** Run `plan-validate --plan <fixture-with-alternatives> --rules <soul-orchestra gate rules yaml>` against the same plan with the section removed; the exit codes must be equal. Paste both into the PR body.

### PR-B (stacked on A): script + schema + tests (inert until PR-C)

**Task B1. CREATE `schemas/verify-map.schema.json`** (draft 2020-12, matching `review-findings.schema.json` style): `version` const 1; `features[]` with required `id, summary, match, paths, surface, env, exercise, expect, synced_sha (40-hex), negative_proof {sha, exit≠0}`; `env` pattern `^(local|uat|staging|browser|creds:[A-Z0-9_]+)$`; `removed[]` with required `removed_reason` (minLength 10) and `removed_sha`.
- VALIDATE: `python3 -m json.tool schemas/verify-map.schema.json >/dev/null`

**Task B2. CREATE `scripts/prp-verify-map.sh`.**
- `validate <map>`: python3 + PyYAML; schema checks done by hand, since there is no jsonschema dependency, following the CI venv, which has PyYAML only. Also checks unique ids. Prints every error. Exits 0/1/2/3.
- `stale <map> [--head REF]`: for each feature, run `git diff --name-only <entry.synced_sha>..HEAD`, glob-match against `paths`, and print the stale ids. An unknown `synced_sha` exits 3.
- `run <map> <id>`: check env availability (exit 4), then `timeout "$t" nice -n 10 bash -c "$exercise"` and compare against `expect`. A timeout (124) counts as a 1 with the reason. Stdout is captured to a tmp file and truncated to 4KB for evidence. A `git status --porcelain` change after the run gives exit 1 with `exercise mutated worktree`.
- `match <map> "<ac text>"`: print `live:<id>` / `removed:<id>` for entries whose `match` keywords appear in the AC text (case-insensitive, whole-word). Tombstones keep their `match` list for this.
- `prove-negative <map> <id>`: first apply the static denylist (`^\s*(true|:|exit 0|echo\b.*)?\s*$` → exit 1 `vacuous: trivial exercise`). Then `git worktree add --detach "$tmp/neg" HEAD`, `git rm -q` the entry's `paths` there (exercise and test files must not be inside `paths`; overlap gives exit 1 `paths include the exercise`), and run the exercise in `$tmp/neg` with the same timeout. Exit 0 = the negative held (expect NOT met); exit 1 = `vacuous: negative proof met expect`; exit 3 = tool error (worktree/git failure). Never read 3 as proven. The worktree is removed in `trap`.
- `sync <map> <id> [--write]`: (i) if every `paths` glob matches no file at HEAD → move to `removed:` with `removed_reason: "paths deleted at <sha>"` and `removed_sha`, then exit 0; (ii) else `run` (must be 0) **and** `prove-negative` (must be 0) → set `synced_sha=HEAD` and `negative_proof`, exit 0; (iii) any other result → exit 1 (or 3/4 passed through), map unchanged. Without `--write` it is a dry run, printing the would-be YAML. Writes go through `yaml.safe_dump` to a temp file + `mv`.
- MIRROR: header and exit-contract style from `scripts/verify-review-artifact.sh`
- GOTCHA:
  - never `eval` in the parent shell;
  - never echo env var values (`creds:` is checked with `[[ -n ${!name+x} ]]`);
  - `paths` globs use python `fnmatch` with `**` support, not bash globbing.
- VALIDATE: `bash -n scripts/prp-verify-map.sh && bats tests/scripts/verify-map.bats`

**Task B3. CREATE `tests/scripts/verify-map.bats` + fixtures.**
- Cover:
  - B2 and B3;
  - B4 (exit 4 for missing `PRP_VERIFY_UAT_URL`, and for an unset `creds:` var);
  - B5 (`sync`: stale→pass advances `synced_sha`; stale→fail leaves the map byte-identical and exits 1; rewritten exercise then pass);
  - B6 (`sync` with all paths deleted → tombstone; `match` returns `removed:<id>`);
  - B8 (each invalid fixture);
  - B9 (`sleep 5` with timeout 1);
  - B12 (`exercise: true` refused; a test that passes without the product file refused; exercise inside `paths` refused);
  - B13 (`PATH` without git → exit 3);
  - a worktree-mutating exercise → exit 1.
- Use temp git repos with `-c core.hooksPath=/dev/null` and set `GIT_*` identity env.
- VALIDATE: `bats tests/scripts/verify-map.bats`

### PR-C (stacked on B): prompts wire the script in

**Task B4. UPDATE `prompts/verify.md`.**
- **0.4 Load Feature Map:** if `.prp-verify/feature-map.yaml` exists, run `validate`. An invalid map means every AC is UNVERIFIED (B8); stop judging, write the artifact, and escalate. No diff fallback.
- **Phase 2:** for each AC, run `match`.
  - `live:<id>`: run `stale`. If the entry is stale, run `sync <id> --write`. On sync exit 1 the AC is FAIL (with output); on 3 it is FAIL (tool error); on 4 it is UNVERIFIED. The agent may first rewrite that entry's `exercise`/`expect`, and then must re-run `sync`. Then `run`, mapping exit codes: 0 = PASS, 1 = FAIL, 3 = FAIL with a tool-error note, 4 = 🔍 UNVERIFIED.
  - `removed:<id>` only: UNVERIFIED + escalate, citing the tombstone reason (B6).
  - No match: use the existing diff-evidence path unchanged, and tag the evidence `diff-evidence`.
- Set the frontmatter key `verified_sha: <PR head sha>`.
- **Verdict table:** add `🔍 UNVERIFIED | env required by map entry is unavailable — not a pass`.
- **3.2:** any UNVERIFIED gives frontmatter `verdict: PARTIAL` with heading `VERIFY INCOMPLETE (unverified)`. Add frontmatter keys `criteria_unverified`, `map_entries_run` and `map_synced: [ids]`. No existing key is renamed.
- **Init Mode `--init`:** derive candidate entries from existing test suites, CLIs and scripts (`cli`/`api`/`lib`). Each candidate is written only via `sync <id> --write` exit 0, which proves both a positive run and the negative proof. Failures are listed with their reason and not written. Commit on the current feature branch only, guarded the same way as the plan artifact commit.
- **Sync Mode `--sync [id]`:** for every stale id (or the given one), run `sync`. Allow at most one rewrite attempt per entry, then report.
- **Edge Cases:** add B1, B4, B5, B6, B8, B12 and B13.
- VALIDATE: `bats tests/commands/structure.bats`

**Task B5a. UPDATE `prompts/run-all.md` Step 0 + `--resume` + Step 8 (B11).**
- After flag parsing, and again in the resume path after loading state: `if [ -f .prp-verify/feature-map.yaml ]; then VERIFY=true; echo "feature map present → verify enforced"; fi`. This is recomputed from the file, never only from state.
- Step 7.5 skip condition becomes `skip if not AUTO_MERGE or (VERIFY != true) or REVIEW_VERDICT != "0_issues"`, where VERIFY is already forced when a map exists.
- Step 8 prerequisites add: map present ⇒ `.prp-output/reviews/pr-{N}-verify.md` exists **and** its `verified_sha` equals `gh pr view N --json headRefOid`; otherwise go back to Step 7.5.
- The `--verify` flag row text adds "(automatic when .prp-verify/feature-map.yaml exists)".

**Task B5. UPDATE `prompts/run-all.md` Step 7.5.** Add `VERIFY_UNVERIFIED = criteria_unverified`. In the result table, the new first row reads `criteria_unverified > 0 → STOP: do not merge; gh issue comment with the UNVERIFIED ACs + env needed; add label status:escalated`. It is placed above the PARTIAL row. The PARTIAL row itself is unchanged for diff-evidence gaps.
- VALIDATE: `grep -n "criteria_unverified" prompts/run-all.md`

**Task B6. UPDATE `prompts/qa.md` 0.2.** If a map exists, list the mapped exercises as hints, and treat an entry's `env` as the environment requirement. QA verdict logic is unchanged.

**Task B7. UPDATE `adapters.yml`** verify `argument-hint` to add `[--init] [--sync [id]]`. The description adds "runs mapped behavioural checks when .prp-verify/feature-map.yaml exists".

**Task B8. UPDATE `structure.bats`.** Pins:
- verify.md contains `UNVERIFIED`, `criteria_unverified`, `--init`, `--sync`, `feature-map.yaml`, and the sentence "never PASS on env-unavailable";
- the artifact path line is unchanged;
- run-all.md has the `criteria_unverified > 0` STOP row before the PARTIAL row (an order test using `grep -n`);
- run-all.md contains `feature map present → verify enforced` in Step 0 **and** in the resume section (2 hits);
- the Step 8 prerequisites contain `verified_sha`;
- verify.md contains "No diff fallback" in 0.4 and the `removed:` → UNVERIFIED rule.

**Task B9. REGEN adapters + parity** (as A6).

**Task B10. Comment the deviation on #202** (see "Deviation from issue"), and edit the issue's "What B" bullet when PR-B opens.

## Testing Strategy

| Suite | New cases | Covers |
|---|---|---|
| `tests/commands/structure.bats` | ~14 pins | A1–A5, B1, B7, artifact path unchanged, row order |
| `tests/scripts/verify-map.bats` | ~18 | B2–B6, B8, B9; `match` whole-word (`scan` must not match `scanner`); creds name-only check |
| `tests/adapters/parity.bats`, `tests/scripts/generate-adapters.bats` | existing | B10 |
| Manual L6 | 2 | A6 plan-validate equality; `--init` on prp-framework itself produces ≥3 entries (it has bats suites), all passing `run` |

Edge cases checklist: map with zero features is valid (all ACs unmapped, giving B1 behaviour plus a WARN); AC matching two entries runs both, and all must pass for PASS (stricter); `synced_sha` not in history (shallow clone) exits 3 → that AC is FAIL (tool error), never diff evidence; exercise writes to the worktree (it runs in the repo and `git status --porcelain` must be unchanged after the run, otherwise FAIL with `exercise mutated worktree`).

Coverage target: every subcommand branch and exit code in `prp-verify-map.sh` is exercised (≥90%).

## Docs Impact

- `README.md`: the command table entry for verify (`--init`/`--sync`) and a short "Feature map" subsection; the plan entry mentions Design alternatives for Design-first work.
- `docs/`: update the verify section if `docs/` has a per-command page (check `ls docs` during implementation; add one paragraph per change).
- `CHANGELOG.md`: one entry per PR.
- No `packages/docs/` in this repo, so EN+TH locales do not apply.

## Gate Compliance

`Gate Compliance: N/A for product gates`. Checked: prp-framework has no web pages, no `/api` routes, no schema or entities, no feature flags or billing, and no deploy workflow. `ci.yml` runs bats only, with no `environment:` key. Applicable gates are the bats suites in CI, `/prp-core:prp-review-agents --l2-comments` to the stop rule, L2 marker, merger, and `safe-merge`.

**Merger class:**
- PR-A changes prompt text that shapes review/plan behaviour across the fleet → label `gate-rules-change`.
- PR-B adds `scripts/**` → labels `ci-change` + `gate-rules-change`. PR-C changes the verify artifact contract additively and run-all's merge decision (stricter: forced verify, `verified_sha`, UNVERIFIED STOP) → label `gate-rules-change`; its PR body quotes before/after pairs for run-all Step 0/7.5/8 and verify 0.4/3.2.
- The PR body must quote before/after pairs for `run-all.md` Step 7.5 and `verify.md` 3.2/3.3, showing nothing is narrowed.

## Validation Commands

1. Static: `bash -n scripts/prp-verify-map.sh && python3 -m json.tool schemas/verify-map.schema.json >/dev/null`
2. Unit: `bats tests/scripts/verify-map.bats tests/commands/structure.bats`
3. Full suite: `bats -r tests`
4. Database: N/A (no DB)
5. Generated: `python3 scripts/generate-adapters.py && bats tests/adapters/parity.bats tests/scripts/generate-adapters.bats && git diff --stat adapters/`
6. Manual:
   - (A) run `plan-validate` on the fixture plan with and without `## Design Alternatives`; the exit codes must be equal.
   - (B) run `/prp-core:prp-verify --init` in a scratch clone of prp-framework; it must write ≥3 entries, and `scripts/prp-verify-map.sh run` must exit 0 for each.
   - (B) run `/prp-core:prp-verify <a merged PR>` with `PRP_VERIFY_UAT_URL` unset and one `env: uat` entry; it must produce UNVERIFIED, `criteria_unverified: 1` and `verdict: PARTIAL`.

## Acceptance Criteria

- [ ] AC-A1: Design-first input yields 2–3 designs, each with Invariant, boundary table, one test per arm and size estimates; non-Design-first output is unchanged.
- [ ] AC-A2: selection follows the 4-step rule and is recorded; the prompt forbids asking the user to pick in any mode.
- [ ] AC-A3: no design covering all cases gives `blocked-design`, and run-all STOPs with an issue comment and escalated label.
- [ ] AC-A4: plan output passes `plan-validate` with an exit code identical to the same plan without the section (A6).
- [ ] AC-B1: no map gives verify behaviour identical to today plus a one-line `--init` hint.
- [ ] AC-B2: a mapped AC is judged by running its exercise; PASS only on observed expectation.
- [ ] AC-B3: env-unavailable gives UNVERIFIED, never PASS; the artifact has `criteria_unverified`; `verdict` stays in the `PASS|FAIL|PARTIAL` enum; the path is unchanged.
- [ ] AC-B4: a stale entry is re-synced before judging; deleted features move to `removed:` with a reason.
- [ ] AC-B5: run-all never auto-merges with `criteria_unverified > 0`.
- [ ] AC-B6: all 6 adapters are regenerated and the parity suites pass.
- [ ] AC-B7: ≥90% of `prp-verify-map.sh` branches are covered by bats.
- [ ] AC-B8: a feature map present forces verify in run-all (fresh and `--resume`); Step 8 refuses without an artifact whose `verified_sha` equals the head.
- [ ] AC-B9: a mapped or tombstoned AC is never judged by diff evidence; an invalid map gives all ACs UNVERIFIED.
- [ ] AC-B10: no entry is accepted without a passing run **and** a negative proof; trivial exercises are refused.

## Completion Checklist

- [ ] L1 static · [ ] L2 unit · [ ] L3 `bats -r tests` · [ ] L4 N/A · [ ] L5 adapters regenerated + parity · [ ] L6 manual A + B runs recorded in PR bodies

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Design-first trigger too broad, so plan cost rises on ordinary tasks | M | M | narrow keyword and path list, `--no-alternatives <reason>` escape, A1 pin. Measure: in the first 2 weeks, count plans with the section vs. Design-first PRs (follow-up) |
| Agent writes 2 "straw-man" designs to tick the box | M | M | each design needs its own test per arm and size estimate; reviewers see the REJECTED reasons. Accepted residual risk |
| `--init` writes weak exercises (e.g. `true`) | M | H | an entry must pass `run` before it is written, and the review sees the map diff. Follow-up idea (Suggestion, not built): a mutation check per entry, like soul-skills#267's vacuous-check gate |
| UNVERIFIED blocks many auto-merges on repos with UAT-only features | M | M | intended (it was silently PASS-by-grep before). Escalation is a label + comment, not a human question; set `PRP_VERIFY_UAT_URL` on hosts that can reach UAT |
| Some consumer parses the verify heading text | L | M | grep found none beyond run-all (updated) and done.md/safe-merge (existence only); the frontmatter enum is unchanged |
| Adapter drift | L | M | regen + parity suites in CI |

## Confidence Score

**8/10** (Patterns 2, Gotchas 2, Integration 2, Validation 1, Testing 1). The prompt behaviour (designs drafted, map derived) is only checked by text pins and manual L6 runs. There is no automated end-to-end LLM run, which is inherent to prompt changes.

---
status: pending
runner: bash + python3 + bats (scripts repo, no package manager)
mode: full
issue: gobikom/prp-framework#151 (AC2 + AC3); supersedes the ledger design of #152/#154
created: 2026-10-22
base: origin/main ee2b518 (v2.12.0 + #195)
---

# Plan: 151-timebox-round-cap — stateless round cap (AC3) + pass timebox (AC2)

## Summary

Two mechanical guards for `prp-review-agents`, as scripts the prompt calls (one implementation,
six adapters just reference it):

- **AC3 `scripts/review/round-guard.sh`**: before any agent starts (Phase 2.0, every mode), count the
  distinct review runs already on the PR from `Generated-by: prp-review-agents … run=<id> …` footers;
  refuse round 11 with a clear message. **No ledger, no state file** (derived from PR comments each time).
- **AC2 `scripts/review/pass-budget.sh`**: the round mints ONE absolute deadline; every probe an agent
  executes runs as `pass-budget.sh run <deadline> -- <cmd>` (wrapped in `timeout`, refused after the
  deadline). A pass that hit the deadline returns a partial report whose `### Could not verify` section says
  `Pass timeboxed: …` and carries `Follow-up: <issue url>`; Step C refuses to post a body that claims
  `Pass timeboxed` without that link.

AC1 shipped (#195). AC4 (scratch-probe allow rules) is fleet settings: written in the PR body only, no
settings.json edit. AC5 is psak's 24h measurement.

## Invariant

**Invariant: no review round can exceed 10, and no pass can run a probe past its budget without
returning a partial report plus a follow-up link.**

Decomposed (each half has a test arm per boundary below):

- **I-ROUND**: a new round starts only if the PR already carries fewer than 10 distinct review run ids in
  `Generated-by` footers. Anything the guard cannot establish (comments unreadable, a footer it cannot
  parse, bad cap argument) refuses (exit non-zero). The guard runs before the head is saved, so a refused
  round starts no agent and posts nothing.
- **I-BUDGET**: a probe started through `pass-budget.sh run` never outlives its deadline (`timeout` kills it;
  after the deadline it is not started). A posted pass body that says `Pass timeboxed` has a
  `Follow-up: https://github.com/<o>/<r>/issues/<n>` line in `### Could not verify`, else Step C posts nothing.

## Real inputs sampled (design rule: sample before writing a parser)

Footers of real `--l2-comments` rounds on PR #170 (`gh api repos/gobikom/prp-framework/issues/170/comments`):

```
Generated-by: prp-review-agents v2.12.0 run=20261021T192036Z-fac7a4d3 pass=code-reviewer
Generated-by: prp-review-agents v2.12.0 run=20261021T192036Z-fac7a4d3 pass=security-reviewer
Generated-by: prp-review-agents v2.12.0 run=20261021T192036Z-fac7a4d3 pass=silent-failure-hunter
Generated-by: prp-review-agents v2.12.0 run=20261021T193243Z-29365139 pass=code-reviewer
```

So: one footer per comment, always the LAST line of the body; a round = one `run=` id across 3 comments
(1 comment at `tier=trivial`, suffix ` tier=trivial`). Counting **distinct run ids** gives rounds, independent
of tier. Run id shape (Step A): `[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}` (existing Step A/C regexes). Aggregated
(non-L2) reviews carry no footer, so they are invisible to the guard (see NOT Building).

Step A/C extraction in `tests/commands/l2-comments.bats` (lines 14-17): `awk` takes the first ```bash fence
after a line starting `**Step A` / `**Step C` from `adapters/claude-code/prp-review-agents.md`, substitutes
`{NUMBER}`, runs it in a temp dir with a stub `gh` (handles only `pr view` and `pr comment`) and a `.prp`
symlink to a fresh git repo tagged `v9.9.9`. Consequences for this plan:
(a) Step A must stay byte-compatible: the guard goes in **Phase 2.0**, not Step A (Step A's run file is
exactly 4 lines, checked by `wc -l`); (b) Step C gets one new call, so the test's fake `.prp` needs
`scripts/review/pass-budget.sh` (copy in `setup`); (c) a stub `gh` must also answer `api …` for the guard
only in the guard's own tests, not in l2-comments.bats (Phase 2.0 is not extracted there).

## Why stateless (lessons from #152 → #154)

The first attempt used a per-PR round ledger and reached 3 consecutive Important rounds in one family
(crash between two writes, retried run id reuse, leftover `record-pending`, symlink writes, ledger text
evaluated as shell arithmetic). Root cause per #154: a state machine spread over prose steps that an LLM runs
in separate shell calls. This design has **no write path at all** for AC3 (read comments → count → exit
code) and an absolute-epoch argument (no state file) for AC2, so none of those arms exist. Hostile-input
rules still apply: counts are never evaluated by the shell (`[ "$n" -ge "$cap" ]` only after a
`^[0-9]{1,4}$` match), bats test names contain no shell metacharacters.

## Files to change

| Action | File | Insert At / Purpose |
|---|---|---|
| CREATE | `scripts/review/round-guard.sh` | stdin = footer lines; `--cap N` (default 10) |
| CREATE | `scripts/review/pass-budget.sh` | `deadline`, `remaining`, `run`, `check-body` |
| UPDATE | `prompts/review-agents.md` | Phase 2.0 block (after `REVIEWED_HEAD_SHA` check, before save); new "### 2.2.0 Pass Budget" before 2.2 Agent 1; one line in each core + conditional agent prompt; Step C per-pass loop (+1 line + `PRP_DIR`); Success Criteria (+2 bullets) |
| UPDATE | `adapters/**` (6 generated) | `python3 scripts/generate-adapters.py` — never hand-edited |
| CREATE | `tests/scripts/round-guard.bats` | boundary arms (below) |
| CREATE | `tests/scripts/pass-budget.bats` | boundary arms + forced-short-budget demonstration |
| UPDATE | `tests/commands/l2-comments.bats` | fake `.prp` gets scripts; 3 new Step C arms |
| UPDATE | `tests/commands/review-rounds.bats` | header comment; replace the "no Part 2.1 / 2.2 machinery" negatives that the new text legitimately trips (`round 11 refused`, timebox words) with positive pins; KEEP negatives for ledger machinery (`record-pending`, `curr-run.env`, `round-recorded`, `.prp-output/review-rounds`, `status-dir`, completion-proof strings); add a "scripts are referenced in all 7 files" sync test |

No settings.json, no workflow, no `.github/**` edit. Gate-integrity PR: label `gate-rules-change`.

## Design

### round-guard.sh (AC3)

```
usage: round-guard.sh [--cap N] < footer-lines
exit 0  print "rounds so far: R of N; this is round R+1"
exit 3  print "ROUND-CAP: refused — PR already has R review runs (cap N). Review stop rule: ..." 
exit 2  unreadable/unparseable input or bad argument (fail closed)
```

Input contract: one line per PR comment = that comment's LAST line (the caller extracts it, see Phase 2.0
snippet). Parsing is strict:

- line matches `^Generated-by: prp-review-agents v[^ ]+ run=([0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}) pass=[a-z-]+( tier=trivial)?$` → record run id;
- any other line starting `Generated-by: prp-review-agents` → exit 2 ("cannot parse a review footer"), fail closed;
- every other line (a comment's ordinary last line) → ignored;
- empty stdin is VALID only when the caller proves it read zero comments is impossible to tell from a failed
  read → the **caller** treats a failed `gh` as FATAL (pipeline status checked) and the script treats empty
  input as "0 runs".
- distinct ids via `sort -u | wc -l`; compare with `[ "$R" -ge "$CAP" ]` after regex-validating both as digits.
- `--cap` must match `^[0-9]{1,3}$` and be ≥ 1, else exit 2. No env override, no bypass flag: the cap
  is the review stop rule (CLAUDE.md), raising it is a code change.

Refusal text names what to do (from the stop rule): fix open Critical/Important or re-route; file
Medium/Low in ONE follow-up issue; do not start another round; escalate (`delegate_or_escalate`).

### Phase 2.0 wiring (both modes; before the head file is written)

```bash
# inside the existing 2.0 fence, after the LOCAL_HEAD/REVIEWED_HEAD_SHA equality check, before the printf > head file
PRP_DIR=$(readlink -f .prp) || { echo "FATAL: cannot resolve .prp — no agents started" >&2; exit 1; }
FOOTERS=$(gh api "repos/{owner}/{repo}/issues/{NUMBER}/comments" --paginate \
  --jq '.[].body | rtrimstr("\n") | split("\n") | last') \
  || { echo "FATAL: cannot read the PR comments (gh failed) — round cap not checkable, no agents started" >&2; exit 1; }
printf '%s\n' "$FOOTERS" | bash "$PRP_DIR/scripts/review/round-guard.sh" --cap 10 \
  || { echo "FATAL: round cap — no agents started" >&2; exit 1; }
```

`{owner}/{repo}` are `gh api` literals that `gh` fills from the current repo. `gh` prints one line per
comment; `last` of an empty body is `null`, ignored. Guard runs the installed framework's copy
(`readlink -f .prp`), not the PR's, like `check-l2-body.py`. The existing "If this block prints FATAL" note
already covers recovery text; it gets one clause for the cap.

### pass-budget.sh (AC2)

```
pass-budget.sh deadline            -> prints epoch = now + ${PRP_PASS_BUDGET_SECS:-1200}
pass-budget.sh remaining <epoch>   -> prints seconds left (>=0); exit 1 when expired
pass-budget.sh run <epoch> -- cmd… -> expired: exit 124 + "PASS-TIMEBOXED: deadline passed, probe not started: <argv0>"
                                       else timeout --kill-after=5 <remaining> cmd…; rc 124/137 -> "PASS-TIMEBOXED: probe cut at deadline: <argv0>", exit 124; else cmd's rc
pass-budget.sh check-body <file>   -> exit 0 unless body has a line starting "Pass timeboxed" and lacks
                                       a line matching ^Follow-up: https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+$ ; exit 1 with reason
```

- `PRP_PASS_BUDGET_SECS` must match `^[0-9]{1,5}$`, 1..14400, else exit 2 (the override exists so tests can
  force a 1-second budget; it is read ONLY by `deadline`, which the orchestrator runs — agents cannot widen
  an already-minted epoch).
- `<epoch>` validated `^[0-9]{10}$` (never evaluated); `timeout` from coreutils (present on goko, macOS has
  `gtimeout` — script prefers `timeout`, falls back to `gtimeout`, else exit 2 "no timeout command": fail
  closed, not "run unbounded").
- The `Pass timeboxed` marker must be a whole line start (`^Pass timeboxed`) inside the body; the check is
  intentionally a fixed-string anchor, not prose matching.

### Prompt wiring (AC2)

1. New "### 2.2.0 Pass Budget" (before Agent 1): the orchestrator runs
   `PASS_DEADLINE=$(bash "$PRP_DIR/scripts/review/pass-budget.sh" deadline)` ONCE per round (Bash tool call;
   PRP_DIR from 2.0 re-derived with `readlink -f .prp`), and pastes the number and the script path into every
   agent prompt (core and conditional, same value: all passes run in parallel under one deadline).
2. Each agent prompt gets 4 lines: `PASS_DEADLINE={PASS_DEADLINE}`; run every command that executes PR code or
   can run long (tests, scripts, builds, probes) via `bash {PRP_DIR}/scripts/review/pass-budget.sh run
   {PASS_DEADLINE} -- <cmd>`; when it prints `PASS-TIMEBOXED` (or the time is up) STOP probing, finish from
   what you have read, and put `Pass timeboxed: <n> probe(s) not completed: <names>` first in
   `### Could not verify`.
3. Orchestrator, Step B: if any pass says `Pass timeboxed`, file ONE follow-up issue
   (`gh issue create`) listing the unfinished probes of the round and add `Follow-up: <url>` as the next
   line of that pass's `### Could not verify`. (Existing fail-closed defaults unchanged: an inconclusive
   probe is "Could not verify", never a clean pass.)
4. Step C per-pass loop, one line added: `bash "$PRP_DIR/scripts/review/pass-budget.sh" check-body "$F" || why="$why timeboxed without follow-up"`
   with `PRP_DIR=$(readlink -f .prp)` resolved and `[ -r ... ]` checked at the top of Step C (fail closed
   if the script is missing). The existing heading/footer checks and the merger-visible body format are
   unchanged (`Pass timeboxed`/`Follow-up` live inside the free-text `Could not verify` section).
5. `{PASS_DEADLINE}` and `{PRP_DIR}` are runtime fill-ins like `{NUMBER}`; they are NOT generator
   placeholders (those are `AGENT_*` and registered in `GEN_PLACEHOLDERS`) — verified by running the
   generator, not assumed.

## Boundary cases per arm (each is a bats arm)

**AC3 round-guard**

| # | Input | Expect |
|---|---|---|
| R1 | empty stdin | exit 0, "round 1" |
| R2 | 9 distinct run ids (27 footers) | exit 0, "round 10" |
| R3 | 10 distinct run ids | exit 3, message names 10 and cap 10, mentions stop rule |
| R4 | 11 distinct | exit 3 |
| R5 | same run id on 3 comments + trivial 1-comment run | counts as 2 runs |
| R6 | footer line with `tier=trivial` suffix | parsed, counted |
| R7 | `Generated-by: prp-review-agents v2 run=BAD pass=x` | exit 2 (fail closed), no count |
| R8 | ordinary lines, `null`, blank lines mixed in | ignored |
| R9 | `--cap 0`, `--cap abc`, `--cap 99999`, `--cap $(touch PWNED)` (literal text) | exit 2, no file created |
| R10 | run id with 20-digit / `08`-style hostile numerics in a count position | no arithmetic on input text; exit as per regex |
| R11 | same 10 ids repeated twice (30+ lines) | still 10 distinct → refused |
| R12 | Phase 2.0 block extracted with a `gh` stub that exits 1 | FATAL, no head file written |
| R13 | Phase 2.0 block with 10-run stub | FATAL "round cap", `pr-N-reviewed-head` NOT created |
| R14 | Phase 2.0 block with 9-run stub | head file written as before |

**AC2 pass-budget**

| # | Case | Expect |
|---|---|---|
| B1 | `PRP_PASS_BUDGET_SECS=1 deadline` then `run <epoch> -- sleep 30` | exit 124 in < 5 s, `PASS-TIMEBOXED: probe cut` — **the forced-short-budget demonstration** |
| B2 | `run` with an epoch in the past | exit 124 immediately, command NOT started (side-effect file absent) |
| B3 | `run <future> -- true` / `-- false` | rc 0 / rc 1 passed through |
| B4 | stubborn child (`trap '' TERM; sleep 30`) | killed via `--kill-after`, still ≤ 10 s |
| B5 | `deadline` with unset env → now+1200; with `0`, `abc`, `99999`, `-5` | default / exit 2 |
| B6 | `remaining` future → positive, past → exit 1 | |
| B7 | non-numeric / 11-digit / injection-text epoch | exit 2, nothing executed |
| B8 | no `timeout`/`gtimeout` on PATH (empty PATH sandbox) | exit 2, command NOT run |
| B9 | `check-body`: no marker → 0; marker + valid Follow-up → 0; marker alone → 1; marker + `Follow-up: http://…` / non-issue URL / trailing text → 1; marker mid-line only → 0 (not a claim) | |
| B10 | Step C (l2-comments.bats): timeboxed body without link → nothing posted, FATAL names it; with link → all three posted; body unchanged otherwise → posts as before | |

## Structure / sync tests (review-rounds.bats)

- all 7 files (prompt + 6 adapters) mention `round-guard.sh` and `pass-budget.sh` (count via the existing
  `count()` helper so a grep error is never a pass);
- Phase 2.0 fence precedes `printf … reviewed-head` with the guard (order test on the prompt);
- ledger machinery stays absent (existing negatives kept, minus strings the new text owns).

## Mandatory reading for the implementer (P0 first)

- P0 `prompts/review-agents.md` lines 462-480 (Phase 2.0), 546-680 (2.2 agents), 1297-1402 (Step A/B/C), 1628 (success criteria)
- P0 `tests/commands/l2-comments.bats` lines 14-70 (step extraction, stubs), `tests/commands/review-rounds.bats` lines 283-320
- P1 `scripts/review/check-l2-body.py` header (how Step C runs the installed copy), `scripts/review/sandbox.sh` lines 1-30 (script style: `set -euo pipefail`, header comment with invariant)
- P1 `scripts/generate-adapters.py` lines 108-120, 430-470 (placeholder registry)
- P2 issue #154 body (the failure families to avoid), `.prp-output/plans/185-cap-binding-replan.plan.md` (format precedent)

## Patterns to mirror

- Script header + fail-closed style: `scripts/review/sandbox.sh` (`#!/usr/bin/env bash`, invariant comment, `set -euo pipefail`, `error:` messages to stderr, exit codes documented).
- Helper-level bats + temp dir: `tests/scripts/prior-findings.bats` (`setup() { TEST_TMPDIR="$(mktemp -d)" … }`, `teardown` rm -rf).
- Command-level fence extraction: `tests/commands/l2-comments.bats:14-17` `step()` awk.
- FATAL message idiom in fences: `|| { echo "FATAL: … — nothing posted" >&2; exit 1; }`.

## Step-by-step tasks

1. **CREATE `scripts/review/round-guard.sh`** — implement per Design; `chmod +x`. VALIDATE: `bash scripts/review/round-guard.sh --cap 10 </dev/null; echo rc=$?` → `rc=0`.
2. **CREATE `tests/scripts/round-guard.bats`** — arms R1-R11. GOTCHA: test names plain words only (#154: a test name once executed `touch PWNED`). VALIDATE: `bats tests/scripts/round-guard.bats`.
3. **CREATE `scripts/review/pass-budget.sh`** — per Design. GOTCHA: `timeout` rc 124 vs the child's own 124 are indistinguishable; document it, message says "cut or exited 124". VALIDATE: `PRP_PASS_BUDGET_SECS=1 bash -c 'E=$(scripts/review/pass-budget.sh deadline); scripts/review/pass-budget.sh run "$E" -- sleep 30; echo rc=$?'` → `rc=124` in ~1 s.
4. **CREATE `tests/scripts/pass-budget.bats`** — arms B1-B9. VALIDATE: `bats tests/scripts/pass-budget.bats`.
5. **UPDATE `prompts/review-agents.md`** — Phase 2.0 guard; 2.2.0 Pass Budget; agent-prompt lines (core 3 + conditional 7); Step B note; Step C call; success criteria bullets `ROUND_CAP_ENFORCED`, `PASS_TIMEBOXED_PARTIAL`. GOTCHA: do not touch Step A (4-line run file, `wc -l` check). VALIDATE: `grep -c 'round-guard.sh' prompts/review-agents.md`.
6. **Regenerate adapters** — `python3 scripts/generate-adapters.py && git diff --stat adapters`. VALIDATE: `python3 scripts/generate-adapters.py --dry-run` reports no drift on a second run.
7. **UPDATE `tests/commands/l2-comments.bats`** — copy `scripts/review` into the fake `.prp` in `setup`; add B10 arms (three tests); add R12-R14 by extracting the Phase 2.0 fence (new `step`-like helper keyed on `### 2.0 `). VALIDATE: `bats tests/commands/l2-comments.bats`.
8. **UPDATE `tests/commands/review-rounds.bats`** — per table above. VALIDATE: `bats tests/commands/review-rounds.bats`.
9. **Full suite + size check** — `bats -r tests` (≈2 min, run in background, no trailing `&`); `git diff --stat origin/main -- . ':!adapters' | tail -1` must be ≈800 changed lines or fewer. VALIDATE: rc 0, 0 failures.
10. **Commit, push, open PR** with label `gate-rules-change`; PR body: plan path, Invariant, AC4 requirements (below), NOT-building list, forced-budget transcript.

## AC4 text for the PR body (no settings.json edit)

Review passes need unprompted permission for scratch probes: allow `Bash(bash */scripts/review/pass-budget.sh run *)`
and `Bash(bash */scripts/review/round-guard.sh *)` plus write access under the review clone
`/tmp/prp-review-clone-*` and `$TMPDIR`; deny nothing new. Fleet owner (psak) applies it; this PR does not
touch any settings file.

## NOT building

- No round ledger / run-state file / `record-pending` (the #152 family; stateless instead).
- No guard for aggregated (non-L2) rounds: they leave no footer, so they are invisible to a comments-only
  counter. safe-merge/merger accept only `--l2-comments` rounds, so those are the rounds that matter; a
  footer-less marker for aggregated reviews is a follow-up if psak wants it (Medium).
- No mechanical proof that a pass honestly reported its expiry (`completion proof`, #154): the budget is
  enforced on probes (kill/refuse) and on posting (link required), not on a pass's silence. Residual,
  stated in the PR body.
- No counting abandoned runs differently: any run id with at least one posted footer is a round
  (conservative; a failed-after-first-post run uses one of the 10).
- No change to the L2 body format, `check-l2-body.py`, Step A, or merger/safe-merge contracts.
- No edit of any settings.json (AC4), no CHANGELOG/version entry (#187, last).

## Docs Impact

N/A beyond the generated adapters: behaviour is documented in the skill itself (prompt + 6 adapters);
no `docs/` page describes the round cap or probe timing (checked: `grep -rn "round cap\|timebox" docs README.md`
in task 9). CHANGELOG entry is added by the #187 changelog cut.

## Gate Compliance

Internal tooling change, no user-facing endpoint, schema, entity, flag, billing or web page. Checked:
no `/api` routes, no DB/schema, no new entity, no feature flag, no billing, no `packages/web` page,
no workflow/cron/systemd unit (so the Automation-Is-Live rule does not apply). Gate-integrity by effect
(review-agents skill code + `scripts/**`): label `gate-rules-change`; CI (`bats -r tests`) green at
the head is the merger evidence, with a quoted before/after of the Phase 2.0 and Step C blocks in the PR body.

## Validation commands

```
Level 1 static:   bash -n scripts/review/round-guard.sh scripts/review/pass-budget.sh && command -v shellcheck >/dev/null && shellcheck scripts/review/round-guard.sh scripts/review/pass-budget.sh || true
Level 2 unit:     bats tests/scripts/round-guard.bats tests/scripts/pass-budget.bats
Level 3 command:  bats tests/commands/l2-comments.bats tests/commands/review-rounds.bats tests/commands/structure.bats
Level 4 full:     bats -r tests
Level 5 drift:    python3 scripts/generate-adapters.py && git diff --exit-code -- adapters  (after commit)
Level 6 demo:     PRP_PASS_BUDGET_SECS=1 bash -c 'E=$(bash scripts/review/pass-budget.sh deadline); bash scripts/review/pass-budget.sh run "$E" -- sleep 30; echo rc=$?'
```

## Risks and mitigations

| Risk | L | I | Mitigation |
|---|---|---|---|
| Same finding family as #152 (state/crash arms) | M | H | No state at all; hostile-input arms R7-R10, B5-B8 |
| Comment-count inflation by a third party's quoted footer (DoS) | L | L | Only last line of a body counts; error direction is "refuse" (fails closed); same threat model as #184 |
| `gh api --paginate --jq` prints per-page output fine, but pagination failure mid-way | L | M | pipeline failure → FATAL (`|| {…}`), tested with a failing stub |
| Agent ignores the BUDGET instruction | M | M | Probes are the only long-running thing agents execute; wrapped runs are killed; un-wrapped probes are a prompt violation the reviewer of the review can see; completion proof is explicitly out of scope (#154) |
| Existing negative tests trip on new text | H | L | Task 8 audits `all_neg` strings against new text before editing the prompt |
| 800-line budget | M | M | scripts ~170 + tests ~320 + prompt ~60 + test edits ~60 ≈ 610 excluding adapters |

## Confidence: 8/10 (Patterns 2, Gotchas 2, Integration 2 — Phase 2.0/Step C insert points read, Validation 2, Testing 0 — the l2-comments Step C fixture change and the generator's treatment of `{PASS_DEADLINE}` are unverified until task 5/6)

## Acceptance criteria

- [ ] `round-guard.sh` refuses round 11 with a clear message, at Phase 2.0, before any agent and before the head file is written; every R-arm green.
- [ ] `pass-budget.sh run` kills/declines probes at the deadline; B1 demonstrates it with a forced 1 s budget.
- [ ] Step C posts nothing for a `Pass timeboxed` body without a `Follow-up:` issue link; posts normally otherwise; body format otherwise unchanged.
- [ ] 7 files in sync (prompt + 6 adapters regenerated); no ledger strings; `bats -r tests` green; ≈800 lines.
- [ ] PR body carries the plan path, Invariant, AC4 text, NOT-building list, forced-budget transcript.

## Re-plan R2: check-body trigger (psak brief 20261022-0538-b200, after FIX-BLOCKED re-plan-needed)

Why: the line-shape matcher (prefix denylist) came back as the same finding family in rounds 1 and 2.

**Invariant: a pass body that mentions a timebox in any form cannot pass `check-body` without a `Follow-up:` line linking an issue.**

- Matching: normalise the body (NFKC, drop `\r`, every Unicode space and `\p{Zs}` to ASCII space, remove zero-width characters, lowercase), then match `time[\s-]*box` anywhere. Line shape, headings, list markers and emphasis are never inspected. Over-matching fails closed (a passing mention needs a link too).
- Normaliser failure (no perl, perl error) exits 2, never 0.
- Threat model: the body is written by our own reviewer pass, not an adversary, so the defect class is accidental omission. Homoglyph evasion is out of scope (follow-up issue).
- Step C stops discarding `check-body` stderr.
- Boundary tests (each must exit 1 without a Follow-up): `## Pass timeboxed`, `### **Pass timeboxed**`, `1. Pass timeboxed`, `**Pass** timeboxed`, `Pass: timeboxed`, NBSP variant, zero-width variant, `time-boxed`, `TIMEBOXED` mid-sentence. Plus: valid link passes, no mention passes. Mutation check: break the normaliser and the tests go red.

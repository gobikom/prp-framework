# Plan: prp-framework#151 — One wake per review round, probe timebox, enforced round cap, no idle status pings

Scope: Part 1 (one caller wake per round), 2.1 (probe timebox), 2.4 (no idle status pings).
**Part 2.3 (allow rules for scratch probes) is OUT of scope** — it waits on soul-orchestra#1338/#1347 (same settings generator).
**UPDATE (round 3, 2026-10-15): Part 2.2 (enforced round cap / round ledger) was scope-cut out of this PR to #154** after three review rounds in that mechanism; the round-1/2 history below documents what was tried and why it was cut.

**Invariant: a review round costs the caller one context read, no probe can extend a round without bound, and no 11th round can run.**

## Boundary cases this design must survive

1. **Timebox exactly hit** — a pass finishes at the same epoch its deadline passes: the pass
   result stands (report as completed), any single probe still open at the deadline is cut and
   becomes one entry in the follow-up issue. Budget is checked before starting a NEW probe,
   not to abort a completed analysis.
2. **One pass times out, two finish** (and the trivial-tier mirror: the one pass times out) —
   the timed-out pass is an incomplete round under the existing rules (core-pass missing ⇒
   verdict floor NEEDS FIXES / L2 run posts nothing); the finished passes' results are kept
   and carried into the partial report; the follow-up issue records the cut probe. The round
   is NOT recorded in the rounds ledger (a round is only recorded after a completed posting).
3. **Cap at round 10 vs round 11** — with 10 recorded rounds, an 11th invocation is refused
   FATAL before 2.0b/the Agent tool run (no agents spawned, nothing posted, message says how
   to proceed: fix forward via a fresh PR or a human decision; `--since-last-review` at an
   unchanged head is NOT a new round — it exits earlier at Phase 0.5 "nothing to re-review").
4. **A round with missing comments** — Step C already fails-closed (nothing posted) when any
   body is missing/off-format; therefore the ledger must be written only AFTER the last
   comment URL is printed. A failed post consumes no round (run file consumed ⇒ new RUN_ID
   required anyway). The ledger append itself is idempotent per run id: re-appending the same
   run id is a no-op, so a crash between the last post and the append cannot double-count.
5. **`--since-last-review` at an unchanged head** — unchanged: Phase 0.5 detects no changes
   since the last review and exits BEFORE Phase 2, so no round is consumed.
6. **Garbage budget values** — `PRP_REVIEW_PASS_BUDGET_MIN` that is not an integer 1..240
   fails closed: FATAL, no agents started (an unbounded "20min" string parsed as 0 would
   silently give probes an instant deadline; garbage must not widen or corrupt the bound).
7. **Garbage ledger** — a `pr-{N}-review-rounds` file that is not exactly `round=<n>\n`
   integers, or a value ≥ 10, is treated as AT the cap: FATAL, refuse to start (fail-closed;
   never "reset and continue").
8. **Background-shell runtimes (no blocking Agent tool)** — when the runtime can only launch
   reviewers as background shells, the skill prescribes the blocking-wait pattern (wait on
   the PIDs/monitors in the same turn; `tail --pid` poll loop with sleep) so the caller takes
   ONE wake covering all passes, not one per completion notification.

## File changes

### 1. prompts/review-agents.md (source of truth)

- **New "One Wake Per Round (Part 1, prp-framework#151)" section**, placed right before
  "Phase 2: Spawn Parallel Agent Subprocesses" (after Phase 1.5), stating:
  - all passes of a round are dispatched in ONE message (already true for core agents —
    now stated as a wake-budget invariant covering conditional agents too);
  - between that dispatch and the round's completion (last per-pass comment posted /
    aggregated review posted) the caller takes **no turn**: no status lines, no partial
    collection, no per-agent wake. Collection starts only after ALL agents returned;
  - runtimes whose Agent tool returns per-agent notifications must batch: either use the
    blocking Agent tool calls in the same message (Claude Code), or, when only background
    shells exist, use the blocking-wait pattern given in the section;
  - **no idle status pings (2.4)**: report on state changes only — dispatch line, completion,
    verdict. Never "still waiting on X" updates, never per-agent progress relays.
- **New 2.0a Round Cap (before 2.0b)****: bash block validating
  `.prp-output/reviews/pr-{NUMBER}-review-rounds` (one line `round=<int>`), failing closed on
  garbage/≥10 with FATAL "round 11 refused"; appends `round=<n+1>` ONLY as instructed by
  Step C / aggregated posting (ledger append after last URL; idempotent per run id).
- **New 2.1a Pass Timebox (after 2.1, before 2.1.1)**: resolves
  `PRP_REVIEW_PASS_BUDGET_MIN` (default 20, integer 1..240, garbage ⇒ FATAL fail-closed),
  saves `deadline=<epoch>` to `pr-{NUMBER}-pass-deadline`, and instructs that EVERY reviewer
  prompt (core + conditional) carries the budget line. Deadline is per run (all passes of the
  round share it — the round is the wake unit).
- **Reviewer prompts (2.2 core + 2.3 conditional)**: add one shared line to each prompt:
  budget, deadline epoch, and the instruction: report what you have when the budget expires;
  list any probe you could not finish under `## Cut probes`; never block on an interactive
  prompt; a probe that cannot finish in the remaining budget is not started.
- **Phase 3 collection discipline**: after all agents return, collect in the same turn;
  per-agent `## Cut probes` sections are merged into ONE follow-up issue (see 3.5) — a cut
  probe never blocks the round and never extends it.
- **New 3.5 Follow-up issue for cut probes**: if any pass reported cut probes (or a pass was
  cut by the deadline), open exactly ONE GitHub issue per run collecting them (title prefixed
  `review-followup:`), link it in the round record; failed/cut core pass ⇒ existing
  incomplete-round rules apply (verdict floor, L2 run posts nothing).
- **Step C append + aggregated mode append**: after the last comment URL / after posting the
  aggregated review and appending metrics, append the round to the ledger (bash provided,
  idempotent per RUN_ID; validated by tests).
- **Metrics**: add `"round": <n>` and `"cut_probes": <n>` fields to the JSONL example and
  field list.
- **Edge cases table + Usage + Success criteria + Input flags line**: document
  `PRP_REVIEW_PASS_BUDGET_MIN`, the cap, the one-wake discipline, round-11 refusal.

### 2. tests/commands/review-rounds.bats (new)

Extracts the 2.0a / 2.1a / Step C-append bash fences from the generated claude-code adapter
(same `step()` extraction technique as l2-comments.bats), runs them against a scratch repo
with a stubbed `gh`:
- cap: 9 recorded rounds ⇒ 10th allowed; 10 recorded ⇒ FATAL "round 11" and no ledger write;
  garbage ledger (non-integer, ≥10, extra lines) ⇒ FATAL;
- budget: unset ⇒ 20 default + deadline = now+20*60; forced valid (5) ⇒ respected; invalid
  (0, 241, "abc", "20min") ⇒ FATAL, no deadline file;
- follow-up issue block: cut probes present ⇒ exactly one issue created via stubbed
  `gh issue create`, body contains each probe; no cut probes ⇒ no issue;
- round recording: Step C success path appends round; FAIL_POST path consumes no round;
  double append same RUN_ID idempotent;
- adapter contains the One Wake section text and the reviewer budget line (structure checks).

### 3. Regenerated adapters

`python3 scripts/generate-adapters.py` — all 6 adapter trees (claude-code, codex, opencode,
gemini, antigravity, thclaws) re-emitted from prompts/. Parity suite must stay green.

### 4. CHANGELOG.md Unreleased + docs

- CHANGELOG "### Changed"/"### Added" entry for #151 (parts 1, 2.1, 2.2, 2.4).
- docs/USER-GUIDE.md and docs/AGENTS-HOW-IT-WORKS.md: mention the round cap, budget env,
  one-wake discipline where review-agents is described (keep it small).

## Provenance format — explicitly UNCHANGED

Three per-pass comments (or one at tier=trivial), line 1 `Reviewed head: <sha>`, line 2
`Passes run: <name>`, last line `Generated-by: prp-review-agents v<ver> run=<id> pass=<pass>`
(+ ` tier=trivial`), one RUN_ID per run, `.prp-output/reviews/` artifacts. Merger
`review_evidence` checks (soul-orchestra .github/merger-policy.yaml) and agent-devops#1243
keep passing untouched.

## Verification ("Verified by" for the PR)

- `bats tests/commands/review-rounds.bats` — cap boundaries 9/10/garbage, budget
  default/forced/invalid (the "forced-short-budget timebox test": forced small budget ⇒
  deadline file reflects it, invalid ⇒ FATAL), follow-up issue, recording rules.
- `bats -r tests` — full suite green (359+ new tests).
- Round-11 refusal test — the 10-rounds ledger FATAL case above.
- Wake-count method (documented in PR body): count caller turns per round in the caller
  session jsonl — grep the transcript for user/tool-result turns between the review dispatch
  and the round completion; one wake per round by construction (dispatch + blocking wait +
  single completion turn), no per-agent notifications in between.

## Out of scope (follow-up issue, not this PR)

- Part 2.3 allow rules for scratch probes (blocked on soul-orchestra#1338/#1347).
- AC5 24 h post-rollout token measurement (needs the fleet running the new skill).

---

# Re-plan (round 2) — round recording as a whole mechanism

Trigger: round-2 Important (run 20261014T203855Z-3599cc1d, silent-failure-hunter) is the same
family as round 1: **a review round can complete without being recorded**. Step Cb-agg needed
two runs (first mints the run id and exits 0, second records), its only call site ran it once
after the post, and 2.0a deleted the run file at every round start — so the single call only
minted and the aggregated round was never counted. Per the review stop rule we stop patching
and re-plan the mechanism.

**Invariant: every review round that posts results is recorded in the ledger exactly once, in
ONE step, in EVERY mode (--l2-comments and aggregated); the ledger is data that is validated,
never evaluated; round 11 is refused before any agent runs.**

## Design constraints

a. **Recording is a single call.** The run id is MINTED at round start (2.0a, which already
   runs in both modes) and saved to `pr-{N}-curr-run.env`; the recording step (Step Cb for
   L2, Step Cb-agg for aggregated) CONSUMES it in one run after the last post. There is no
   "re-run this block" path and no `exit 0` without recording: a missing/unreadable run file
   at record time is a FATAL with a non-zero exit (a posted-but-unrecorded round must be
   visible, never silently absorbed). After recording, the run file is removed — a second
   invocation of the same recording step finds no run file and FATALs (loud, never a no-op
   that could mask a lost record). The recorded-run marker (`pr-{N}-round-recorded`) still
   holds the last recorded run id for humans; it is no longer load-bearing for control flow.

b. **Ledger parse.** `tail -n 1` ONLY; the line must match `^round=(0|[1-9][0-9]?)$` exactly
   (max two digits — `round=999…` cannot wrap arithmetic because it is rejected before any
   arithmetic exists). Anything else → FATAL, fail closed. Ledger text is never placed into
   `$(( ))`, `[[ ]]` arithmetic, `eval`, or an array index: it is compared to the regex
   FIRST, and only the two-character-bounded match is then read with `10#`. Same regex at
   all three sites (2.0a, Step Cb, Step Cb-agg). A multi-line ledger (any second line,
   including a second `round=` line) is invalid → FATAL (the ledger is one line by
   construction; a stray line means hand-editing or corruption — refuse, never guess).

c. **Ordering + retry.** Chosen order: **ledger first (tmp + `mv`), marker second** — with
   tmp+`mv` both writes are atomic, and the failure modes become: ledger-write fails →
   nothing recorded, retry re-records exactly once (run file still present); marker-write
   fails → the ROUND IS RECORDED (ledger advanced) and the FATAL says so explicitly ("round
   recorded; only the bookkeeping marker failed") — a marker is cosmetic, losing it never
   loses a round, and a retry after that FATAL finds the run file gone and FATALs loudly
   rather than double-recording (the ledger's own value is the single source of truth for
   2.0a). This inverts the round-1 "marker first" choice deliberately: round 1 protected
   against double-counting by宁可 losing a round; the round-2 Invariant makes losing a round
   the worse failure, and double-counting is now impossible anyway because the run file is
   consumed (removed) before the ledger write is attempted... concretely: read run id →
   validate → compute NEXT from ledger → write ledger atomically → remove run file → write
   marker. A crash anywhere before the ledger write leaves the run file for a clean retry; a
   crash after leaves a recorded round.

d. **Non-regular paths.** A directory/dangling symlink at the ledger, marker, or run-file
   path → FATAL with a clear message (the `-e`/`-L` + `-f` checks already in 2.0a are kept
   and extended to the new files and to both recording steps).

## Boundary arms (one bats test each)

1. Single call records — aggregated: 2.0a mints, one Step Cb-agg run after a post records.
2. Single call records — l2: Step A/C leave `.used`; one Step Cb run records.
3. Stale run file from a previous round: 2.0a's mint REPLACES it (clear-then-mint), and the
   new id, not the stale one, lands in the marker.
4. Run file missing at record time → non-zero + FATAL (both modes), nothing recorded.
5. Multi-line ledger → FATAL (state: any second line invalidates).
6. Ledger `a[$(touch PWNED)]` → FATAL, and PWNED is NOT created (validation never evaluates).
7. Ledger `round=99999999999999999999` (20 digits) → FATAL (regex caps at two digits).
8. Ledger `round=08` → FATAL (leading zero).
9. `round=10` recorded → the NEXT 2.0a refuses round 11 before agents.
10. Ledger write fails after "marker" — retry semantics: simulate ledger-unwritable at first
    attempt (run file survives), then writable → the retry records exactly once.
11. Marker path is a directory → FATAL (round already recorded by then; message says so).

## File changes

- `prompts/review-agents.md`: 2.0a (mint `pr-{N}-curr-run.env` for BOTH modes; strict regex;
  keep the round-recorded/agg-run.env cleanup for one release), Step Cb and Step Cb-agg
  (single-call consumers; new ordering; FATALs), metrics note, edge-case rows, success
  criteria. The old `pr-{N}-agg-run.env` mint-in-recorder logic is deleted.
- `tests/commands/review-rounds.bats`: the arms above (several replace the round-1 tests
  whose behaviour legitimately changed: "first invocation mints…", "third run is a no-op",
  "no consumed run file records nothing" → now non-zero).
- Adapters regenerated; CHANGELOG Unreleased entry amended.

---

## Re-plan (round 5) — completion proof via per-pass status files, not prose

Trigger: round-5 review (run 20261015T063457Z-5ed59349, head f4415ee) — SECOND consecutive
round with a completion-signal finding. code-reviewer Important (6186073498) and
silent-failure-hunter Important (6186074212), same root cause: the One Wake section still
prescribes `wait "$pid1" "$pid2" "$pid3"` (and poll / `tail --pid` variants that yield no
per-shell status), contradicting the completion check at :1010 ("statuses are collected per
shell, never from a single multi-pid `wait`"). Editing the example alone already failed once
(round 4) — this round RE-PLANS the completion-signal mechanism.

### Invariant (the thing that must be true, mechanically)

**No review result is posted unless EVERY core pass is proven complete — its own exit status
was 0 AND its output ends with its exact `PASS COMPLETE: <pass>` closing line. That proof is
checked by ONE bash check run right before posting (Step C), not by prose.**

Design consequences:
- The proof artifacts are FILES, not memory: each pass writes a per-pass status file into a
  `mktemp -d` directory OUTSIDE the PR checkout (same symlink-safety posture as the 3.5
  body: no PR-planted path, no symlink-following; refuse non-regular paths).
- Step C (aggregated post) runs ONE mechanical bash check over ALL core status files and
  posts NOTHING (FATAL, existing failed-agent handling) if any file is missing, records a
  non-zero exit, or lacks the completion line. The check parses the files; it never trusts
  the caller's narrative.
- Per-shell status collection: exactly one `wait` per pid, each immediately followed by
  `rc_N=$?`. A multi-pid `wait` (returns only the LAST pid's status) is FORBIDDEN everywhere
  — example, alternatives, and prose. Poll loops and `tail --pid` MAY be used for blocking
  ONLY if each shell writes its own `.rc` file (status still comes from a file per shell).
- The pass name inside `PASS COMPLETE: <pass>` is a FIXED LITERAL per agent prompt
  (`code-reviewer`, `security-reviewer`, `silent-failure-hunter`, and the conditional-pass
  literals) — no free-text substitution, so a name written from memory cannot diverge from
  the name the check greps for. Formatting variants (fence, bold, trailing space) fail the
  exact-line check — that is intended (fail closed); the prompt says "one exact closing
  line (nothing after it)".

### Status-file design

Each pass, as its final act in the same shell that ran the pass, writes
`$STATUS_DIR/<pass>.status` with exactly three lines:

```
pass=<fixed pass name>
rc=<exit status of that shell's own wait>
complete=yes|no        # yes iff that pass's collected output ends with "PASS COMPLETE: <pass>"
```

`STATUS_DIR=$(mktemp -d "${TVD:-/tmp}/prp-round-status.XXXXXX")` is minted ONCE per round by
the dispatch turn, before any reviewer shell starts; it is outside the repo tree, mode 0700,
and each `.status` path is validated (`-f`, non-symlink) before being read. The Step C check
loops over the pass list, requires every status file to exist, be a regular non-symlink
file, match `^pass=<name>$` on line 1, `^rc=0$` on line 2, and `^complete=yes$` on line 3;
ANY deviation is a FATAL "review incomplete — {pass} did not complete", routing to the
failed-agent handling (verdict floor NEEDS FIXES for core passes; L2 run posts nothing).

### Boundary arms (one bats test each)

1. all 3 passes complete (rc=0, complete=yes, correct names) → post ALLOWED (check exits 0,
   gh sees the bodies)
2. one pass rc≠0 → FATAL, nothing posted
3. one pass `complete=no` (missing closing line) → FATAL, nothing posted
4. one status FILE missing → FATAL, nothing posted
5. a status path is a symlink → refused; the symlink target is UNTOUCHED (victim file
   content identical)
6. wrong pass name in the line (`complete=yes` but `pass=code-review` — the check's name
   must equal the expected literal) → FATAL, nothing posted

Plus 3.5 arms (see below): delimiter-injection body posts as literal text; failed post exits
non-zero; empty/multi-line CUT_PROBES_COUNT FATALs.

### 3.5 cut-probes re-plan (psak's security finding + silent-failure arms)

- NO reviewer-derived text through a heredoc or shell variable. The collected entries live
  in a FILE written by the collection step (Write tool / `printf '%s'` of a file's bytes —
  never interpolated into the command line). The 3.5 block reads that file's bytes with
  `cat` and writes them to `$TVD/body.md` via `printf '%s' "$(cat …)"` … no — reading
  through a command substitution re-exposes nothing but still routes the bytes through a
  shell variable; the chosen mechanism is: the block CONCATENATES fixed-header + entries
  file + fixed-footer with `cat` into the body file (bytes flow file→file, never through
  word-splitting or a heredoc), and posts with `--body-file`. A probe line equal to any
  delimiter is therefore inert text.
- Failed `gh issue create` → exit NON-ZERO (a swallowed post failure is a silent failure);
  the body file is kept at its temp path for a by-hand retry.
- `CUT_PROBES_COUNT` unset → "no cut probes", exit 0 (legitimate). Set but EMPTY or
  MULTI-LINE or non-base-10 → FATAL (the collection step must pass a real single-line count;
  garbage never means "zero probes").
- Placeholder guard: the body must not contain the literal `PRP_CUT_PROBES_ENTRIES` marker
  after assembly (unsubstituted placeholder would otherwise pass `-s`).

### Test 18/19 quality note (review Suggestions; partially in scope as test hygiene)

Test 18's local `tail | grep` re-implementation is replaced by boundary tests that run the
REAL Step C check fence extracted from the adapter (same `block()` mechanism as budget/followup
tests). The dead `body()` helper is removed; its arms move to the new 3.5 arms. The prose
assertions about "no multi-pid wait" become a grep arm: the adapter must NOT contain
`wait "$pid1" "$pid2"` (any multi-pid wait form) and MUST contain the per-pid pattern.

### Non-goals (→ #153 leftovers, one comment, with source links)

- Deadline read-back (a pass overrunning the deadline but emitting the line) — Low.
- `.prp-output/reviews/` symlink-following on tier/marker/metrics writes (pre-existing,
  security-reviewer Medium) — file as follow-up.
- Whether the Write tool follows a pre-planted symlink at
  `pr-<N>-agents-review.md` (unknown, out of scope).

---

## Re-plan (round 8) — test helpers that fail on ANY breakage, not just on matches

Trigger: round-8 review (run 20261015T080700Z-f6ee9368, head 05b9599) — silent-failure-hunter
Important (6187515565): `neg()` treats grep exit 2 (missing file / bad regex) as "no match"
and PASSES; probes showed deleting the gemini adapter or moving the claude-code adapter left
the remnant tests green. Same family as round 7 ("a check that cannot fail"); rounds 9+10
must both be clean, so this is the LAST push.

### Invariant

Every structure test in review-rounds.bats FAILS whenever the property it names does not
hold — including when an input file is missing, unreadable, renamed, or the adapter set
changes. No helper exit path means "silently pass".

### Helper spec (mechanical)

- `neg FILE ERE`: fail with a diagnostic unless FILE exists and is a readable regular file;
  run `grep -qE`; exit 1 (no match) → pass; exit 0 (match) → FAIL; exit 2 or anything else
  → FAIL (bad pattern / unreadable).
- `pos FILE ERE`: same file checks; exit 0 → pass; anything else → FAIL.

### Adapter set

ONE explicit EXPECTED_FILES list: prompts/review-agents.md + the 6 adapters (7 entries).
A dedicated test asserts the list has exactly 7 entries and every one exists and is
readable — a moved/renamed/deleted adapter fails loudly there. Every neg/pos structure
check loops over that FULL list, never one adapter.

### Failure-hiding wait check

One ERE over all 7 files catching ANY `wait` with two or more $-arguments — quoted or
unquoted, any variable names: `wait[[:space:]]+[^[:space:]]*\$[^[:space:]]*[[:space:]]+[^[:space:]]*\$`
(first token contains a literal $, whitespace, second token contains a literal $). The
prescribed single-pid form (`wait "$pid1"; rc1=$?`) has `;` after the first token → no match.

### One Wake failed-status sentence

One sentence added to the One Wake bullet in prompts + regenerated into all 6 adapters:
"A non-zero or missing pass status counts as a failed pass — the existing handling applies."
Pinned with pos over all 7 files.

### Mutation proof (throwaway git copy, base restored before each)

M-a missing adapter → FAIL · M-b chmod 000 adapter → FAIL · M-c renamed adapter → FAIL ·
M-d bad regex in a neg pattern → FAIL · M-e `wait "$a" "$b"` in a non-claude adapter → FAIL ·
M-f `wait $p1 $p2` unquoted → FAIL · M-g failed-status sentence removed from one adapter →
FAIL · plus round-7's M1–M9. Base tree all green.

Also fixed this round: heading pin anchored to `^## One Wake Per Round` (round-8
suggestion), stale header comment (round-8 suggestion), stale PR-body diff size (round-8
suggestion). Carried wording suggestions stay on #153.

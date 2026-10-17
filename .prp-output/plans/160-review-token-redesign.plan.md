# Plan: review token redesign (prp-framework#160)

- **Epic:** gobikom/prp-framework#160
- **Author:** PSak (pane cw-claude-1934-3), 2026-10-18
- **Status:** APPROVED by devlead-codex in plan peer review round 5 (2026-10-18), after rounds 1–4 returned REQUEST CHANGES (8, 6, 2+1, 2+2); see "Revision log". Phases 4b, 5b and 6 still wait for นุด's decisions D1–D3. Live replays wait for the devops boundary (AC-N1..N5).
- **Branch / worktree:** `plan/review-token-redesign` @ `a68fd8d` (origin/main), `~/tmp/wt-prp-review-redesign`
- **Type:** REFACTOR + gate/policy change. **Complexity:** HIGH (it touches 3 repos and changes the review rules).

## Summary

`/prp-core:prp-review-agents` costs 8–21M cache-read tokens, about 1M cache-create tokens and 89–187k output tokens **per round** (baseline in #160). Most of that is not review reasoning:
- a main thread that re-reads an 80 KB prompt every turn;
- LLM-driven rendering and posting of the per-pass comments;
- a cold cache on every headless run;
- a stop rule that forces a FULL round on every PR.

This plan cuts that cost in stacked phases. Each phase is gated on a **replay benchmark**, which shows zero observed regressions of labelled Critical or Important findings on a finite, frozen corpus (Invariant 1; this is not a proof of universal detection) and that the cost actually fell.

## Invariants

1. **Detection invariant (regression form, not a universal claim).** On the frozen replay corpus, under matched settings (the same agent set, model, prompt version except for the change under test, and frozen head and patch), the variant shows **zero observed regressions on historical labels**.
   - **What counts as a regression:** a labelled Critical or Important finding that the baseline rediscovers in at least `k` of `n` repeated runs (default n=3, k=2), and that the variant finds in fewer than `k` of its `n` runs.
   - **What stays out of the gate:** labels that the baseline itself fails to rediscover reliably are marked *stochastic*. They are reported, but neither block nor count.
   - **When a regression appears:** the regression is adjudicated by a human (นุด or PSak with a written reason on #160) before the phase can pass.
   - **Limit:** finite replay cannot prove that a finding is never lost; the plan claims only "no observed regression on the corpus".
   - **Stochastic labels are NOT covered by this gate,** and every phase report says so explicitly.
     - They stay on a **watch list**: every replay reports their hit rate (baseline vs variant), and a drop is reviewed by hand on #160.
     - After rollout, production rounds are sampled for the same defect families.
     - The watch list is never presented as gated coverage.
2. **Provenance invariant.** The posted per-pass comments still satisfy soul-orchestra `.github/merger-policy.yaml` `review_evidence` and ops `safe-merge` `_verify_review_provenance`, byte for byte for every field they parse:
   - line 1 `Reviewed head:`, line 2 `Passes run:`;
   - the two severity headings;
   - the `Generated-by:` footer, one run id, unedited.
   This holds until a phase that deliberately changes the rules (Phases 5 and 6) lands with its policy PRs.
3. **No silent success.** A review run that does not leave every expected per-pass comment at the reviewed head exits non-zero and says why.

**Verified by:**
- `tests/bench/replay.bats`, plus the corpus labels, for invariant 1;
- the existing `tests/commands/l2-comments.bats` and ops `test/safe-merge-marker-gate.test.sh`, run against comments rendered by the new script, for invariant 2;
- new bats arms for "posted 2 of 3", "post failed" and "head moved", for invariant 3.

## Not building

- **No change to what counts as Critical or Important.**
  - The severity rubric in the agent prompts stays.
  - Changing it would make the token comparison meaningless.
- **No new review agents, and no non-Claude reviewers.**
- **#154's round-cap ledger** (enforcing round 11 refusal) stays in #154.
  - #154 is P3, on hold.
  - Phase 2 only builds the script skeleton that #154 can later extend.
- **The guarded wrapper itself** (`~/tmp/run-review-guarded.sh`) is not in this repo.
  - Moving it to ops is soul-orchestra#1362 item 7.
  - This plan only sets the requirement it must meet (Phase 1).

## Dependencies

- **#157 and #158 must merge first.** They change `prompts/review-agents.md`, the six adapters and `scripts/generate-adapters.py`.
- **#154, #150 and #94** are mapped in "Related issues" below; none of them blocks this plan.
- **นุด's decisions D1–D3** (see #160) block Phases 4b, 5b and 6. Phases 0–4a do not need them.

## Codebase facts this plan relies on (sampled 2026-10-18)

| What | Where | Fact |
|---|---|---|
| Prompt size | `prompts/review-agents.md` | 1,624 lines, 79,488 bytes. Per-section bytes: `## Output` 24,461; `Phase 2: Spawn` 8,009; `One Wake Per Round` 2,737; `Phase 1` 2,695 |
| Single-agent prompt | `prompts/review.md` | 913 lines, 34,342 bytes. `Review Passes` 6,786. Phase 0.5/1/1.5 and metrics duplicate review-agents |
| Run id / footer | `prompts/review-agents.md:1314-1359` | Step A mints `RUN_ID=<UTC>-<8 hex>` into `pr-N-l2-run.env`; Step B writes `pr-N-l2-<pass>.md`; Step C posts |
| Tier | `prompts/review-agents.md:485-493` | `pr-risk-tier` (ops) → `TIER=trivial` means only code-reviewer runs. safe-merge and merger recompute the tier |
| Incremental | `prompts/review-agents.md:73-125` | Uses `pr-N-agents-review.md` + `git log --since`; with no new commits it exits "Nothing to re-review" |
| Agent spawn | `prompts/review-agents.md:543-700` | 3 core agents (`code-reviewer`, `security-reviewer`, `silent-failure-hunter`) plus conditional ones |
| Adapters | `scripts/generate-adapters.py` | Generates 6 adapters (claude-code, codex, gemini, opencode, antigravity, thclaws) from `prompts/`. `tests/adapters/parity.bats` |
| Existing tests | `tests/commands/{l2-comments,review-rounds,structure}.bats` | bats; CI runs them (#146) |
| Merger rule | soul-orchestra `.github/merger-policy.yaml:147-157` (`review_evidence`), `:140` | Two consecutive clean rounds of 3 passes for every tier. Relaxing review for a tier is a gate weakening (`by_class.weakening`) |
| safe-merge | ops `bin/safe-merge:462-518` | Checks the footer, a single run id and unedited comments. It does NOT check the round before; merger does |
| Rule text | see "Rule-copy and enforcement inventory" below | The stop rule is restated in 15+ sources |

## Phases (stacked PRs, each ≤ ~800 changed lines)

### Phase 0: Measurement and replay corpus (prerequisite for every other phase)

**Goal:** a repeatable number for "cost per round" and "findings per head" before anything changes.

**Files**
- `scripts/bench/review-cost.py`: sums `usage` over a session jsonl plus `subagents/*.jsonl`.
  - Read-only; run as `python3 -I`.
  - Outputs JSON: input, cache_read, cache_create, output, split into main thread and subagents.
  - Also outputs a **weighted cost**, using Sonnet price ratios relative to input: cache_read 0.1, cache_create 1.25, output 5.
- `tests/bench/corpus.yaml`: historical PR heads, each with the C/I findings the current design reported (file, line region, defect, family, **source pass**: code, security, silent-failure or a conditional agent), labelled by hand from the posted comments.
  - **Frozen per entry:**
    - the head SHA and base SHA;
    - a patch digest (`git diff base...head | sha256sum`);
    - the permalink of the source comment.
  - **Coverage required:**
    - findings from each of the 3 core passes;
    - at least one finding from a conditional agent;
    - at least two challenging heads: a large diff and a shell/security-heavy diff.
  - **Initial entries:**

  | PR | heads | findings |
  |---|---|---|
  | #156 | R1 `2e715d1d` | 3C/1I |
  | #156 | R2 `cc7ceb55` | 1C/1I |
  | #156 | R4 `8d78023c` | 1C/1I |
  | #152 | R1–R3 | see #154 |
  | one docs-only PR | — | 0 findings, a negative control |
  | one trivial-tier PR | — | negative control |

- `scripts/bench/replay.sh`: a **baseline-capable, side-effect-free** replay that works on the CURRENT prompt, before Phase 2 exists.
- **OS-level write boundary: a hard precondition for ANY live replay (round-3 finding 1).** PATH wrappers and unset variables are hygiene only; they can be bypassed with `/usr/bin/git`, `command -p`, `curl`, a `.netrc` or another credential helper. The boundary is therefore enforced by the OS, in two parts.
  - **(i) Separate identity.** Live replays run as a dedicated unprivileged user, `prp-replay`, created by devops (a root action, routed through `/ping devops`).
    - Its own `HOME` contains NO GitHub credential of any kind: no `.netrc`, no gh/git credential store or helper config, no `GH_*`/`GITHUB_*` in its environment.
    - Its only secret is a Claude credential, a long-lived subscription token (`claude setup-token`) installed by นุด or devops through stdin into a 0600 file, never printed.
    - It cannot read goko's `HOME` (mode 0700), so goko's credentials are out of reach.
  - **(ii) Egress policy: an allow-listing proxy, not hostname rules in nftables (round-4 finding 2).** nftables matches addresses, not names, so the hostname allow-list lives in a proxy and nftables only pins the uid to that proxy.
    - **nftables:** for `meta skuid prp-replay`, in BOTH the `inet` family (IPv4 and IPv6), the only allowed egress is TCP to the local proxy on `127.0.0.1:<port>` and `[::1]:<port>`. Everything else is rejected and logged, DNS included (UDP/TCP 53 and DoT 853). The proxy resolves names itself.
    - **Proxy:** a local CONNECT proxy (devops picks the implementation, e.g. squid or tinyproxy) running as its own user. Its allow-list is the exact host names Claude Code needs (the Anthropic API and auth hosts, enumerated by devops from a real `claude -p` session's connections). It refuses every other CONNECT target, all GitHub hosts included, and logs it. A CDN or DNS change on the allowed side can only break Claude (the preflight then fails closed); it can never open GitHub.
    - **Environment:** `prp-replay`'s environment sets `HTTPS_PROXY`/`HTTP_PROXY` to the proxy and nothing else. Any inherited proxy variables and `NO_PROXY` entries are cleared. Replays run in the host network namespace (no other namespace is assumed), so the uid rule applies to every socket.
    - **Mirror:** the source mirror is fetched beforehand by goko into a directory owned by goko that `prp-replay` can only read. Since `prp-replay` is not the owner, it cannot `chmod` the mirror back to writable.
  - **Devops deliverable with its own ACs (tracked as an agent-devops issue linked from #160):**
    - **AC-N1:** as `prp-replay`, direct TCP connects to sampled addresses from EVERY CIDR family listed by GitHub's `/meta` endpoint (fetched by goko), over IPv4 AND IPv6, all fail.
    - **AC-N2:** CONNECT through the proxy to `github.com`, `api.github.com`, `codeload.github.com`, `objects.githubusercontent.com` and an `*.githubusercontent.com` host is refused.
    - **AC-N3:** direct DNS queries fail.
    - **AC-N4:** `claude -p "reply OK"` succeeds through the proxy.
    - **AC-N5:** the rules persist across reboot (verified once).
  - **Preflight, run as prp-replay before every replay batch. Any failure aborts the whole batch (fail closed).** Steps 1–2 re-run the devops AC-N1..N3 test script in short form, so they cover every CIDR family over IPv4 and IPv6, proxy CONNECT refusals and DNS. Two hostnames alone would not establish that no GitHub route exists.
    1. the AC-N1/N3 network checks pass (no GitHub route, no DNS);
    2. the AC-N2 proxy refusals pass;
    3. a scan of prp-replay's `HOME` finds no `.netrc`, `hosts.yml`, `.git-credentials` or credential helper;
    4. writing into the mirror fails with EACCES;
    5. `claude -p "reply OK"` succeeds (authentication works).
  - **Dependency and fallback.** This user and policy are a Phase 0 dependency owned by devops, and นุด approves the egress rule. If they cannot be built, live replays do not run. Phase 0 then falls back to a **read-only harness** that re-parses already-posted historical comments and existing jsonl only, and the gates of Phases 2–7 that need replays stay BLOCKED until the boundary exists.
- **Hygiene layers inside the boundary (defence in depth, not the proof).** Each run gets a throwaway clone at the frozen head in a fresh `mktemp` dir, with:
  - **git push is impossible and logged.**
    - Every remote's `pushurl` is set to `file:///dev/null/push-refused`, which is unreachable by construction.
    - The fetch mirror is a local bare repo made read-only (`chmod -R a-w`).
    - A `git` wrapper first in PATH logs and refuses any `push` subcommand (including `git -C <dir> push`, `push --mirror`, and pushes to added remotes) with exit 97, then delegates everything else to `/usr/bin/git` by absolute path.
    - `remote add` and `config remote.*` writes are logged.
  - **No GitHub credentials exist in the sandbox.**
    - `GH_TOKEN`, `GITHUB_TOKEN` and `GH_ENTERPRISE_TOKEN` are unset.
    - `GH_CONFIG_DIR` points to an empty temp dir.
    - `GIT_CONFIG_GLOBAL` points to a temp file with `credential.helper=` empty, and `GIT_TERMINAL_PROMPT=0` is set.
    - A direct HTTP write (`curl` to api.github.com) is therefore unauthenticated and cannot change anything. The Claude login is untouched, because `HOME` is unchanged and only the GitHub-specific variables are redirected.
  - **Sandboxed `gh`:** `gh` is a PATH stub that records every invocation and returns canned PR metadata (number, head, base, files). Any write verb (`pr comment`, `pr review`, `issue comment`, `api -X POST|PATCH|PUT|DELETE`, `pr edit`, `pr merge`, `label`) exits non-zero and is logged as a violation.
  - **The prompt's own side effects:**
    - the per-pass, aggregate and L2/marker posts all go through `gh` and are blocked there;
    - artifact commits stay inside the clone;
    - artifact pushes are refused by the git wrapper;
    - context and report files written outside the clone are detected by a before/after `find -newer` scan of `$HOME/.prp-output`, `~/tmp` and the corpus repos.
  - **Collection:** findings come from the rendered artifacts the current prompt writes (`.prp-output/reviews/pr-N-l2-<pass>.md` and the aggregate review), parsed by `scripts/bench/extract-findings.py` into the Phase 2 schema. The schema is defined here in Phase 0 and only consumed later. Cost comes from the run's jsonl.
  - **Matched settings:** each run is invoked with the same model, wrapper and `--append-system-prompt`. Settings are recorded in the run log, and a mismatch aborts the comparison.
- `tests/bench/replay.bats`: unit tests of the matcher, `extract-findings.py`, `review-cost.py` and the `gh` stub's refusal of writes, all against fixtures. The live replay is a manual, logged step, not CI.

**ACs**
- AC0.1: `review-cost.py` reproduces the #160 baseline table from the real jsonl to within 1%.
- AC0.2: the corpus has ≥ 8 C/I findings across ≥ 5 heads. It covers all three core passes, at least one conditional agent and at least two challenging heads; every entry is frozen (SHA, patch digest, source link).
- AC0.25 (round-4 note): a baseline run counts only if the current prompt completed its whole artifact-writing path inside the sandbox: every per-pass body file and the aggregate review exist, with the run id and head of THIS run. A run that stopped at a blocked post before writing them is recorded as `INCOMPLETE BASELINE` with its reason, and its partial artifacts are never extracted. If the current prompt cannot finish without a successful post, Phase 0 adds the smallest replay-only prompt shim (posting steps replaced by "write the body to file and stop"), and every baseline run records the shim's digest.
- AC0.3: the CURRENT design is replayed n=3 times on the corpus.
  - Each label's baseline rediscovery rate is recorded.
  - Labels below `k/n` are marked stochastic with that rate.
  - The baseline is the reference for all later phases; it is not required to be 100%.
- AC0.4 (round-3 finding 1): GitHub writes are **impossible by construction** during live replays.
  - **The proof:** the OS boundary preflight above passes, all 5 checks, logged with timestamps on #160, before every batch; and the egress log for `prp-replay` shows every GitHub connection attempt REJECTED.
  - **Diagnostics only, NOT the proof:** the hygiene logs (`gh` stub, git wrapper, ref digest, external comment count, file scan) are kept to find prompt side effects that should be removed.
  - **Without the boundary,** AC0.4 is NOT MET and no live replay runs.

**Boundary cases:**
- jsonl with no `usage`;
- subagent dir missing;
- a truncated last line;
- a corpus head that no longer exists on the remote (fetched by SHA, otherwise the replay fails loud);
- a patch digest mismatch (abort);
- the prompt trying to post (replay fails; the attempt is recorded).

### Phase 1: Stable cache prefix (quick win, no rule change)

**Goal:** stop busting the prompt cache on every run.

**Changes**
- Requirement for the guarded wrapper, applied in the ops move under soul-orchestra#1362 item 7:
  - the `--append-system-prompt` text must be static;
  - per-run values (`nproc` caps) go in the environment or the user message;
  - the model, tools and system prompt must be identical across rounds.
- In this repo:
  - an audit that the review prompt has no per-run text above the first tool call (the date or PR number belong after the static part);
  - document the cache contract in `prompts/review-agents.md` (one short section).

**Completion gate (split, round-1 finding 8)**
- Phase 1 is two deliverables with separate gates:
  - **1-prp** (this repo): the prompt prefix audit plus the documented cache contract, complete on AC1.0.
  - **1-wrapper**: the static system prompt in the guarded wrapper, delivered in ops through soul-orchestra#1362 item 7 and complete on AC1.1. It is an **explicit dependency**: the per-round cost baseline of Phases 2–7 is measured with the 1-wrapper wrapper, or, if that has not landed, with the same old wrapper for both baseline and variant, stated in the run log.
- No one declares AC1.1 from prompt changes alone.

**ACs**
- AC1.0: there is no per-run text in the review prompt before the first tool call; a bats check greps the generated adapters for date, PR or run placeholders in that region.
- AC1.1 (1-wrapper): two consecutive replays within 5 minutes, using the ops wrapper, show cache_create on the second run ≤ 50% of the first. Measured with `review-cost.py` and logged on #160.

**Boundary:** the runs are more than 1 h apart (cache TTL). This is expected to miss and is recorded, not failed.

### Phase 2: Scripts over prose (largest expected saving)

**Goal:** the LLM reviews; scripts render, post and verify.

**Changes**
- `schemas/review-findings.schema.json`: per pass, `{pass, reviewed_head, findings:[{severity: critical|important|medium|low|suggestion, file, line_start, line_end, family, title, evidence, fix}]}`.
- `scripts/review/run.sh` with subcommands:
  - `start`: mint the run id and save the env; this replaces Step A;
  - `render`: JSON → the exact per-pass comment bodies; this replaces Step B;
  - `post`: post the comments, then **verify** that every expected pass comment exists at the head with this run id and is unedited; exit 3 otherwise; this replaces Step C;
  - `--dry-run`: render, never post.
  - The script never evaluates data as shell. Atomic writes, refusal of symlinked paths and strict regexes on every field follow the #154 lessons.
- `prompts/review-agents.md`:
  - each agent is told to return ONLY the JSON block (the schema is inlined in the agent prompt, about 1 KB);
  - the main thread validates the JSON (`run.sh validate`), then calls `render` and `post`;
  - the `## Output` section (24 KB) is replaced by a call contract of about 3 KB.
- **Fail-closed JSON contract (round-1 finding 3).** `run.sh validate` takes the expected pass set from the run env, which `start` writes from a fresh `pr-risk-tier` at the reviewed head: code, security and silent-failure at the standard tier; code only at the trivial tier. Both `start` and `validate` re-run `pr-risk-tier`; a tier change aborts the run.
  - **Rejected outright, never rendered as a clean comment:**
    - prose around the JSON, or JSON inside a fence;
    - partial or truncated JSON, or text after the closing brace;
    - more than one JSON object per pass;
    - a duplicate, missing or unknown pass;
    - a missing core agent or a failed spawn;
    - `findings` that is absent or `null` (an empty list must be the explicit `[]` AND carry `"complete": true`);
    - a finding without `file`, line range or `evidence`, or with a severity outside the enum;
    - a `reviewed_head` that differs from the run env;
    - counts that do not match the findings.
  - **No silent default:** absent or malformed agent output is never treated as `findings: []`. The run exits non-zero with `REVIEW INCOMPLETE: <pass>: <reason>` and posts nothing.
- **Conditional agents (round-2 finding 5).** These are tests, types, docs and the other agents selected by the path map.
  - **Required set:** `start` records the required conditional set in the run env, from the path map at the reviewed head. `validate` requires a valid JSON result from every member; a failed spawn or a malformed result means `REVIEW INCOMPLETE` and nothing is posted.
- **Folded into a linked core artifact, gate-verified (round-3 finding 2).** Separate unlinked conditional comments were dropped, because a missing unlinked comment is invisible to the gates.
  - **Where the results go:** conditional results are folded into the **linked `code-reviewer` comment** in a fixed, machine-readable block:
    - a line `Conditional passes: <agent>=complete, <agent>=complete` (or `none`), followed by
    - a fenced `` ```json review-conditional `` block with each agent's findings and its own counts.
  - **Counting:** the `code-reviewer` comment's Critical and Important headings count the core findings PLUS every conditional Critical/Important. An attribution table names the source agent of each finding, so nothing is attributed to the core pass silently. A dirty conditional result therefore makes a LINKED comment non-zero, and the existing gates block it.
  - **The gate recomputes the required set.**
    - safe-merge, merger and `verify-review-artifact.sh` recompute the required conditional set at the reviewed head from the **path map in the pinned ruleset** (R2-4 contract; deterministic and versioned).
    - They require the `Conditional passes:` line to list exactly that set, each `=complete`, with the JSON block parsing and its counts matching the headings.
    - Missing, extra, `=failed` or a count mismatch means the gate rejects.
  - **Gate-level tests,** in ops `test/safe-merge-marker-gate.test.sh` and a merger-policy sync fixture, not only in `run.sh`. Each case is tested independently:
    - (1) a required conditional missing from the line;
    - (2) a conditional with `=failed` (spawn failed);
    - (3) a dirty conditional, which gives non-zero headings;
    - (4) a count mismatch between the JSON and the headings;
    - (5) an L2 marker posted by hand over a comment lacking the line.
- **Format versioning and activation, with no rejection window and no merge freeze (round-4 finding 1).**
  - **Marking the format:** new-format comments carry `fmt=2` in the footer (`Generated-by: … run=<id> pass=<pass> fmt=2`). Old comments have no `fmt` field, which means fmt=1.
  - **Step (a), gates in dual mode:**
    - safe-merge, merger and the L2 verifier keep validating fmt=1 exactly as today (strict core requirements, unchanged).
    - They add full fmt=2 validation: the `Conditional passes:` line, the JSON block, counts and the required-set recomputation.
    - A comment is validated by the version it declares.
    - Released and deployed before anything else.
  - **Step (b):** the new prompt emitting fmt=2 is deployed.
  - **Step (c), activation:**
    - The pinned ruleset (R2-4) gains `fmt2_required_after: <UTC timestamp>`, set at or after step (b)'s deployment.
    - Any review comment created after that timestamp MUST be fmt=2. An fmt=1 comment created after activation is rejected, with no permissive fallback.
    - Comments created before activation are still validated as fmt=1, so a PR's earlier clean round stays valid across the boundary.
  - **Mixed rounds:** the stop rule's two consecutive clean rounds may be fmt=1 (created before activation) plus fmt=2. Each is validated under its own format, and both must be clean.
  - **Tests at the gate:**
    - fmt=1 only, before activation: accepted;
    - fmt=2 only: accepted;
    - mixed (fmt=1 before plus fmt=2 after): accepted;
    - fmt=1 after activation: rejected;
    - fmt=2 missing a required conditional: rejected;
    - forged `fmt=1` on a comment created after activation: rejected (`created_at` comes from GitHub, not from the body).
  - **Head checks around posting:** `post` reads the PR head from GitHub before EACH comment and again after verification. Any mismatch stops posting.
  - **Partial posts:** if a post stops partway, the run is marked abandoned in the run env, exits non-zero, and the next run mints a new run id. A partial set of per-pass comments never matches one run id with every expected pass, so safe-merge rejects it already; the run is also reported loudly.
- `scripts/generate-adapters.py`: adapters reference the script; `parity.bats` still passes.
- Tests:
  - `tests/scripts/review-run.bats`, with one arm for each of these cases:
    - every rejection listed in the fail-closed contract above;
    - 2 of 3 posted;
    - a failed post followed by a re-run (new run id);
    - the head moving between `start` and `post`;
    - the head moving between two posts;
    - the head moving after verification;
    - a tier change between `start` and `validate`;
    - a symlinked env file;
    - a hostile field (`$(…)` or a newline in title);
    - the trivial tier (one pass);
    - a conditional-agent Critical (round not clean, attributed to its own agent).
  - The rendered bodies are checked by `tests/commands/l2-comments.bats` and ops `test/safe-merge-marker-gate.test.sh` (invariant 2).

**ACs**
- AC2.1: the prompt (review-agents) is ≤ 45 KB.
- AC2.2: zero observed regressions on corpus labels against the Phase 0 baseline, n=3 (invariant 1).
- AC2.3: weighted cost per FULL round is ≤ 60% of the **matched reference** (round-2 finding 6).
  - The reference is re-measured after Phase 1 with the same wrapper, the same cache state (cold first run, then a warm run within 5 min) and the same model.
  - If 1-wrapper has not landed, the Phase 2 runs use the Phase 0 wrapper.
  - The phase report attributes the savings separately: Phase 1 (cache) versus Phase 2 (prompt and scripts).
- AC2.4: a post that leaves fewer than the expected comments exits non-zero (invariant 3).
- AC2.5: safe-merge and merger provenance checks pass on comments rendered by the script (invariant 2), shown on a real PR.

**Size:** if more than 800 lines, split it: 2a schema + script + tests; 2b prompt and adapters switch-over.

### Phase 3: One shared core prompt

**Goal:** remove the duplication between `review.md` and `review-agents.md`.

**Changes**
- Create `prompts/_review-core.md` holding the shared material: context detection, incremental detection, large-PR handling and metrics.
- The generator inlines it into both commands at build time, so the adapters stay self-contained.
- The single-agent `review` also emits schema JSON and uses `run.sh render`, without `--l2-comments` provenance; its escape-hatch status is unchanged.

**ACs**
- AC3.1: no shared section exists twice in `prompts/`; a sync test fails on drift.
- AC3.2: `prompts/review.md` is ≤ 20 KB of command-specific text.
- AC3.3: zero observed regressions on the corpus for review-agents; the single-agent review is unchanged on its own fixtures.

### Phase 4: Fewer repeat rounds

**4a (no rule change)**
- An incremental round passes the previous findings JSON to the agents as input: "these were reported, these were marked fixed; verify they are fixed; do not re-report the same defect under a new title".
- `run.sh` compares families across rounds. When the same family has C/I in 2 consecutive rounds, it exits with status `RE-PLAN` and prints the family. This makes the existing "same family → re-plan" rule mechanical.
- AC4a.1: a corpus replay of #156 R1→R2 emits `RE-PLAN` at R2 (that pair was a real same-family re-plan).
- AC4a.2: zero observed regressions on the corpus.

**4b (needs นุด decision D3; transition defined before any code, round-1 finding 4)**
- **Scope:** a finding is out of scope only when its lines are outside the diff AND the diff does not call into them. The call check uses ck_impact or a grep of the changed symbols. The wording must not contradict "a Critical or Important finding in the PR's own diff is never out of scope".
- **Why changing merger-policy alone does not work:** merger-policy (`review_evidence`, `.github/merger-policy.yaml:153`) and safe-merge (`bin/safe-merge:499-518`) block ANY `Reviewed head: <head>` comment with non-zero Critical/Important, linked or not. If a comment keeps non-zero C/I, the gates still block; if the finding is simply zeroed, it is hidden.
- **Required transition (round-2 finding 1):** a machine-readable disposition, so that nothing is hidden.
  - **Critical never moves.** A Critical finding stays in the `### Critical Issues (N found)` heading wherever its lines are, so the existing zero-Critical gate keeps blocking.
    - Only an **Important** finding may be dispositioned out of scope, and only under นุด's D3 wording.
    - The gate rejects a comment whose out-of-scope block contains any entry with severity `critical`, and no READY marker may be posted for that head.
    - **Invariant 4b:** no Critical is ever outside the severity headings. **Verified by:** a bats arm with a Critical in the out-of-scope block, which is rejected by `run.sh`, safe-merge and the merger-policy sync test.
  - **Strict format.**
    - The out-of-scope entries are ONE fenced block, `` ```json review-out-of-scope ``, holding a JSON array that matches `schemas/out-of-scope.schema.json`: `{severity:"important", file, line_start, line_end, title, issue:"<owner>/<repo>#<n>", scope_proof:{diff_base, diff_head, changed_symbols_sha256, callers_checked:[…], tool}}`.
    - Markdown prose lines are never parsed.
    - Strings are JSON-escaped, so delimiters inside file names or titles cannot break the parser.
  - **The gate re-derives the scope predicate itself;** a reviewer's label is never trusted.
    - **Outside the diff:** safe-merge/merger compute the changed line ranges from `git diff <base>...<head>` and check that `file:line_start-line_end` overlaps none.
    - **Not called by changed code:** they re-run the pinned call analysis (`pr-scope-check`, ops, deterministic: changed symbols → callers via a language-aware grep/ck index pinned by version) and require that no changed symbol reaches the finding's region.
    - **Fail closed:** if the analysis cannot decide (unsupported language, dynamic dispatch, a tool error), the entry is in scope and the comment is rejected as non-clean.
    - **No human override is a gate input (round-3 clarification).** Every agent comments as gobikom, so a PR comment cannot authenticate นุด. Until นุด defines an authenticated, head- and finding-bound override channel under D3, the only path for an undecidable finding is to fix it in the PR or to re-route the PR. Phase 4b as a whole stays a conditional future phase gated on D3.
  - **Checks before posting:** the script verifies that the linked issue exists, is open, and quotes the finding's file, lines and title.
- **Changed together**, as stacked PRs in this order, with the prompt last:
  1. ops safe-merge plus its tests;
  2. merger-policy (`review_evidence` and every embedded REVIEW+L2 text, see the rule inventory);
  3. the L2 marker verifier (`scripts/verify-review-artifact.sh`);
  4. the prp prompt.
- **Deployment:** the prompt never ships ahead of the gates.

### Phase 5: Risk tier selects agents and rounds

**5a (no rule change):** a path → agent map in the prompt, extending #149's classifier.
- `security-reviewer` always runs on: scripts, workflows, hooks, auth, secrets, install and any shell.
- `silent-failure-hunter` always runs on: code with error handling.
- The 3-pass requirement stays: in 5a, every core agent still runs; only the conditional agents are pruned.
- AC5a.1: conditional agents are never spawned on a docs-only diff.

**5b (needs นุด decision D2, gate weakening):**
- **What the docs tier covers:** a PR that changes only `*.md` files, none of them under `prompts/`, `.claude/`, `agents/` or `conductor/` and none of them another instruction file, and with no executed code fences.
- **Rule:** the docs tier gets one pass (code-reviewer) and ONE clean round. It is the whole stop rule for that tier; it never combines with Phase 6 (see "Tier × stop-rule composition" below).
- **Evidence for merger** (`by_class.weakening`): the Phase 0 corpus shows that docs heads carried no Critical/Important.

**Tier × stop-rule composition (round-1 finding 5), one table for every approval path**

| tier (from pinned `pr-risk-tier` at the head) | passes per round | rounds that must be clean |
|---|---|---|
| docs (5b) | `code-reviewer` | 1 (latest run at the head) |
| trivial (today) | `code-reviewer` | 2 consecutive (today's rule, unchanged by this plan) |
| standard | 3 core | 2 consecutive; with D1 (Phase 6), the 2nd may be a confirm run |
| gate/security (gate-integrity paths per merger.yaml) | 3 core | 2 consecutive full-strength; confirm NOT allowed |

- **Precedence:** the most restrictive tier over all changed paths wins, the same as merger's path rule: `gate` > `standard` > `trivial` > `docs`.
- **Classifier outputs (round-2 finding 4).**
  - `pr-risk-tier` (ops) today returns only `trivial` or `standard` (`bin/pr-risk-tier:262,267`).
  - It gains `docs` and `gate` outputs: `gate` is merger.yaml's gate-integrity path set, imported from one pinned list, not re-typed.
  - Precedence is tested per pair, with mixed-path fixtures for every pair.
  - Until the classifier ships these outputs, `docs` does not exist (5b is blocked), and `gate` is derived as today by merger's own path classes.
- **One versioned ruleset with a runtime contract (round-2 finding 4).** A sync test of repo snapshots is not enough; each runtime consumer pins and checks the version.
  - **The file:** the table lives in `review-rules.yaml` in soul-orchestra, with `ruleset_version: <int>` and a canonical `sha256`.
  - **Pinning by each consumer:**

    | consumer | pin |
    |---|---|
    | ops safe-merge, `pr-risk-tier` | an embedded `REQUIRED_RULESET=<version>:<sha256>`, read from a copy installed alongside the binary |
    | merger | the soul-orchestra default-branch blob SHA, recorded in every verdict |
    | prp `verify-review-artifact.sh`, `run.sh` | the pinned version in `adapters.yml` |
    | repo-own merger-policy copies | must name the same version |

  - **Fail closed:** a missing, unreadable or mismatched ruleset (version or digest) means the consumer BLOCKS. It never falls back to a weaker or default rule.
  - **Rollout order for any rules change (N → N+1):**
    1. Every consumer is deployed accepting N+1, while still enforcing N where N is stricter.
    2. The ruleset flips to N+1.
    3. Support for N is removed.
    4. The prp prompt changes last.
  - **Compatibility check:** a test matrix (consumer × ruleset version) runs in ops and prp CI.

### Phase 6: Confirm round (needs นุด decision D1, gate weakening)

- **When it may run:** only at the same head as the **latest** run on the PR, when that run was a clean standard-tier full or incremental round (chronological latest-run check by comment `created_at`).
  - If any later run at that head reports Critical or Important, confirm eligibility is revoked until a new clean round.
  - A head change also revokes it.
  - A confirm run at a changed head fails closed: it exits non-zero, posts nothing, and a normal round is required.
- **What it runs:**
  1. code-reviewer on the whole diff with a "Critical/Important only" brief;
  2. a closure check on every finding resolved in earlier rounds (each must cite the fixing commit or the line that resolves it).
- **Exact format, so the existing parsers stay strict:**
  - one comment;
  - line 1: `Reviewed head: <head>`;
  - line 2: `Passes run: confirm`;
  - the two severity headings;
  - a `### Prior findings closure (N checked)` section;
  - the footer: `Generated-by: prp-review-agents v<ver> run=<id> pass=confirm prev_run=<id of the clean round it confirms>`.
- **Gate changes:**
  - safe-merge's pass regex (`bin/safe-merge:485-493`) gains `confirm` ONLY on this path. It verifies that `prev_run` is the immediately previous run, that it is clean, that it is at the same head, and that it was posted before the confirm run.
  - merger's `review_evidence` stop-rule bullet changes the same way.
  - the L2 marker links the clean round's comments plus the confirm comment.
- **Stop rule (standard tier):** a clean full or incremental round, then a clean confirm run linked to it.
- **Order of PRs** (the prompt never ships ahead of the gates):
  1. `review-rules.yaml` + the sync test;
  2. ops safe-merge + tests;
  3. merger-policy (every embedded REVIEW+L2 text);
  4. the L2 verifier;
  5. prp prompt and adapters;
  6. the rule-text sweep (see the rule inventory).
- **Benchmark gate (round-1 finding 6, round-2 finding 2).** Three separate test families on the corpus, n=3. Eligibility tests and detection tests are kept apart, because a seeded fault creates a new head and so can never be an eligible confirm state.
  - **(a) Eligibility path, real and fault-free.**
    - At one frozen, fault-free corpus head: run a clean full round, then a confirm run at the identical head.
    - Show that confirm is accepted only there.
    - Show that the closure check passes when prior findings are genuinely resolved.
    - Show that it flags a prior finding whose recorded closure is false. The prior-findings data is the input that is varied here; the code head stays unchanged, so eligibility holds.
  - **(b) Detection, adversarial, explicitly SIMULATED.** This simulates a first-round false negative.
    - Use frozen faulty heads with seeded faults, one or more per pass type: a code bug, an injection/unsafe-shell defect, a swallowed error. The faulty heads are committed to the corpus with their patch digests.
    - Run confirm's brief (forced to run despite eligibility, marked `simulated=true`, never postable) and a full 3-pass round at the same faulty head.
    - Confirm must show no observed regression versus the full round per fault class.
    - The report labels these results "simulated first-round miss", not production behaviour.
  - **(c) Fail-closed:**
    - a confirm at a changed head refuses;
    - a confirm after a later dirty run at the same head refuses;
    - a confirm with a `prev_run` that is not the latest clean run refuses.
  - **If (b) shows a regression:** confirm is NOT adopted for that fault class. For example, if security faults are missed, confirm either adds security-reviewer or is withdrawn, and the data is reported to นุด. Cost alone never justifies equivalence.
- AC6.1: weighted cost of a confirm run ≤ 25% of a FULL round (measured only after (a)–(c) pass).

### Phase 7: Main-thread model (experiment, after Phase 2)

- Replay with the main thread on a smaller model, keeping the review agents on Sonnet.
- Adopt it only if there are zero observed regressions (n=3) and posting/verify succeed on every corpus head.
- This is a configuration change in the wrapper, not in the prompt.

## Rule-copy and enforcement inventory (round-1 finding 7)

Edit sources and regenerate; never edit installed `.prp` copies or generated outputs directly. Phase 6 / 5b / 4b PRs must cover each row. A line-scanning test (lesson from SO#1321) fails on any stale copy.

| Kind | Source (edit here) | Generated / mirrored (regenerate) |
|---|---|---|
| Enforcement | ops `bin/safe-merge` (`_verify_review_provenance`, 462–518), ops `bin/pr-risk-tier`, prp `scripts/verify-review-artifact.sh` | — |
| Merger policy | soul-orchestra `.github/merger-policy.yaml`: `review_evidence` 149–157, history entry around 140, `REVIEW + L2` text around 237 and 448–449, `TIER RECORD`; `agents/merger.yaml` minimum evidence | repo-own `.github/merger-policy.yaml` copies in repos that use their OWN policy (enumerate with `gh search code`) |
| Protocol / identity | soul-orchestra `conductor/protocol.md`, `conductor/philosophy-rationale.md`, `generator/agent_md_common.py`, `agents/*.yaml`, agent-home templates feeding `output/agent-homes`, `conductor/wiki/{orchestration-guide,delegation-protocols}.md`, `docs/ARCHITECTURE.md` | every agent home `CLAUDE.md` / `AGENTS.md` (generator + deploy) |
| Global | the source of `~/.claude/CLAUDE.md` and the workspace `AGENTS.md` / `CLAUDE.md` (locate the owning repo in Phase 6 step 6) | installed copies |
| PRP | `prompts/review-agents.md`, `prompts/review.md`, `prompts/review-fix.md`, `prompts/integration.md`, `prompts/run-all*` (stop-rule wording) | the 6 adapters via `scripts/generate-adapters.py`; installed `.prp` / `.claude/commands` via `prp-install-all` |

## Expected outcome (estimates, verified per phase by the benchmark)

| change | per round | per PR (2 rounds) |
|---|---|---|
| Phases 1–3 | −40 to −60% | −40 to −60% |
| + Phase 6 | — | a further −30 to −40% (second round cheap) |
| + Phase 5b on docs PRs | — | −80% or more |

## Validation commands

```bash
bats tests/commands tests/scripts tests/adapters tests/bench
python3 scripts/generate-adapters.py --check
python3 -I scripts/bench/review-cost.py --jsonl <session.jsonl>       # Phase 0+
scripts/bench/replay.sh --corpus tests/bench/corpus.yaml --dry-run    # manual, logged on #160
```

## Risks

| Risk | Mitigation |
|---|---|
| A thinner prompt loses findings | The detection invariant plus an n=3 corpus replay per phase; any observed regression blocks the phase until adjudicated |
| A corpus that is too small hides regressions | ≥ 8 C/I at the start; every new real C/I found in production reviews is added to the corpus |
| A rendering bug breaks merger provenance | Invariant 2 tests in both repos; Phase 2 proven on a real PR before the rule phases |
| Rule changes drift across 15+ copies | Phase 6 adds a line-scanning test for the stop-rule wording (lesson SO#1321) |
| Replays cost tokens too | The corpus is kept small; replays run on demand, not in CI; cost is logged on #160 |
| Headless runs still exit early | Invariant 3 (post verify) makes it loud, whatever the dispatch mode |

## Related issues

- **#154:** Phase 2's script is the base its round ledger extends; its scope stays there.
- **#150:** tier hardening; its inputs are needed by Phase 5.
- **#153:** unrelated leftovers.
- **#94:** older ck/rtk token ideas; it can close as superseded once Phase 3 lands if nothing in it remains.
- **soul-orchestra#1362 item 7:** wrapper verify and the move to ops; it receives Phase 1's cache requirement.

## Peer review asks (devlead-codex, round 2)

1. Do the revisions close round-1 findings 1–8 (see the revision log)?
2. Is `review-rules.yaml` as a single source for tier × stop rule workable for safe-merge (bash) and merger (policy text)?
3. Are the seeded-fault classes in Phase 6(b) enough?

## Revision log

**Round 1 (devlead-codex, 2026-10-18): REQUEST CHANGES, 6 Important and 2 Moderate.** All 8 findings were verified against the code before revising.

| # | Finding | Change |
|---|---|---|
| 1 | The corpus cannot prove universal detection; replays are stochastic | Invariant 1 restated as "zero observed regressions": n=3 runs (k=2), stochastic labels, human adjudication. Corpus frozen (SHA, patch digest, link); covers all passes, a conditional agent and challenging heads |
| 2 | Phase 0 depended on Phase 2's `--dry-run` | Baseline replay on the current prompt: no push remote, `gh` write stub, temp `HOME`, artifact-based extraction; AC0.4 zero writes |
| 3 | The JSON boundary was not fail-closed | A full rejection list, an expected pass set from a fresh tier, head checks before each post and after, abandon on partial posts, conditional findings kept separate and still blocking |
| 4 | 4b conflicts with the gates that block any C/I comment | A machine-readable out-of-scope section with issue links; Critical never allowed; gates first, prompt last |
| 5 | Tier and confirm composition, and the exact format, undefined | Tier × stop-rule table in a single `review-rules.yaml`; exact confirm format with `prev_run`; latest-run, revocation and changed-head rules; PR order with gates first |
| 6 | The confirm benchmark tested an inadmissible state | (a) adversarial, (b) an eligible state with seeded faults compared with a full second round, (c) fail-closed; no adoption on cost alone |
| 7 | The rule-copy inventory was incomplete | A new inventory table: philosophy-rationale, `generator/agent_md_common.py`, templates, repo-own policies, global files, review-fix/integration prompts, and the merger-policy 140/237/448–449 text |
| 8 | The Phase 1 gate could not pass on prompt changes alone | Phase 1 split into 1-prp (AC1.0) and 1-wrapper (AC1.1, an explicit ops dependency); the baseline wrapper is held constant |

Phase order kept as 2 before 3 (devlead-codex agreed).

**Round 2 (devlead-codex, 2026-10-18): REQUEST CHANGES, 4 Important and 2 Moderate.** Round-1 findings 1, 3, 5, 7 and 8 were closed; 2, 4 and 6 were still open. The cited code was verified first (`pr-risk-tier:262,267` returns only trivial/standard).

| # | Finding | Change |
|---|---|---|
| R2-1 | 4b: a Critical could hide in the out-of-scope section; Markdown not machine-readable; scope was trusted from the reviewer's label | Critical never moves (invariant 4b plus a test); a fenced JSON block with a schema; the gate re-derives "outside the diff" and "not called" with pinned `pr-scope-check`; undecidable means in scope; only a นุด adjudication overrides |
| R2-2 | 6(b) seeded faults create a new head, so the state was not eligible | Split into (a) the eligibility path at a fault-free identical head (closure varied through the input data), (b) a SIMULATED adversarial test on frozen faulty heads, never postable, and (c) fail-closed |
| R2-3 | A local mirror is still pushable; no proof of zero writes | `pushurl` unreachable, a read-only mirror, a git wrapper refusing every push form, no GitHub credentials in the sandbox, a ref digest before and after, an external comment-count check, an out-of-clone file scan |
| R2-4 | Snapshot sync is not runtime authority; the classifier lacks docs/gate | A versioned ruleset with a digest pinned by each consumer, fail-closed on mismatch, rollout N → N+1 with the prompt last, a compatibility matrix; `pr-risk-tier` gains docs/gate with tested precedence; 5b blocked until then |
| R2-5 | Conditional agents' completeness and evidence were undefined | A required conditional set in the run env, a per-agent evidence comment with the same run id (not linked by L2); the existing "every Reviewed head comment 0/0" rule blocks a dirty one; partial set means abandon |
| R2-6 | Cost attribution; stochastic labels silently uncovered | A matched reference re-measured after Phase 1, with savings attributed per phase; stochastic labels on a watch list, explicitly not gated, with production sampling |

**Round 3 (devlead-codex, 2026-10-18): REQUEST CHANGES, 2 Important plus 1 clarification.** R2-1, R2-2, R2-4 and R2-6 were closed; round 1 stays closed.

| # | Finding | Change |
|---|---|---|
| R3-1 | Wrappers and unset variables can be bypassed; the four checks do not prove zero writes | An OS-level boundary is now a hard precondition for live replays: a separate `prp-replay` user with no GitHub credentials and only a Claude token, per-uid nftables egress allowing Anthropic only, a mirror readable but not owned, and a 5-check fail-closed preflight that includes a working Claude call. AC0.4 is "impossible by construction"; the old checks are diagnostics only. If devops cannot build the boundary: a read-only historical harness, and live-replay gates stay BLOCKED |
| R3-2 | A missing unlinked conditional comment is invisible to the gates | Conditional results are folded into the linked code-reviewer comment (a `Conditional passes:` line, a JSON block, counts included in the headings, an attribution table); the gates recompute the required set from the pinned ruleset path map; 5 gate-level tests; gates updated before the prompt |
| R3-c | A นุด override cannot be an unauthenticated comment | The override was removed as a gate input; an undecidable finding means fix or re-route; 4b stays conditional on D3 |

**Round 4 (devlead-codex, 2026-10-18): REQUEST CHANGES, 2 Important plus 2 non-blocking.** R3-2 and R3-c were closed; R3-1 was accepted as a conditional dependency that needs an implementable, verified boundary.

| # | Finding | Change |
|---|---|---|
| R4-1 | Gates requiring the new line first would reject every review | `fmt=2` footer; (a) dual-mode gates, (b) the new prompt, (c) a pinned `fmt2_required_after` activation; old rounds created before activation stay valid, mixed rounds allowed, no fallback after activation; 6 gate tests |
| R4-2 | nftables cannot match hostnames; two-host sampling proves nothing | A uid pinned to a local allow-list CONNECT proxy (hostname policy in the proxy); nftables denies all other IPv4 and IPv6 egress and DNS; proxy variables cleared; the devops deliverable AC-N1..N5 covers every GitHub `/meta` CIDR family over v4/v6, proxy refusals, DNS and a working Claude call; the preflight re-runs it; fallback unchanged |
| R4-n1 | The Summary overclaimed | The Summary now states the finite-corpus, no-observed-regression language |
| R4-n2 | A baseline might not finish under blocked posts | AC0.25: complete artifacts of this run or `INCOMPLETE BASELINE`; partial artifacts never extracted; a replay-only shim with a recorded digest if needed |

**Round 5 (devlead-codex, 2026-10-18): APPROVE.** Implementation cautions, binding on the implementing PRs:
- **Egress boundary:**
  - the nftables uid rule must cover every egress path;
  - the proxy must enforce allowed destinations independently, including the target port and a policy on resolved addresses;
  - sampled tests and egress logs alone are never treated as proof of the boundary.
- **fmt=2 parser:**
  - it keeps the exact unedited-comment checks (`created_at == updated_at`);
  - the activation timestamp is read only from the trusted pinned ruleset and compared against GitHub's `created_at`.
- **Replay shim:** if a replay-only shim is used, the same shim semantics apply to baseline and variant, and each phase report states the shim's impact on measured cost and recall.

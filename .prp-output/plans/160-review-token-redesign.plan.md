# Plan: harness-neutral review protocol, lower token cost (prp-framework#160)

- **Epic:** gobikom/prp-framework#160
- **Author:** PSak (pane cw-claude-1934-3), 2026-10-18
- **Status:** REVISION 9, **APPROVED** by devlead-codex in plan peer review round 10 (2026-10-18). Revision 4 was approved in round 5; the architecture change for R-H and R-C took rounds 6–10. Decisions still open for นุด: D1–D3 (Phases 4b, 5b, 6) and D4 (staged harness cutover). Round 6: REQUEST CHANGES on revision 5 (1 Critical, 4 Important). Round 7: REQUEST CHANGES on revision 6 (1 Critical, 2 Important, 1 Moderate). See the revision log.
  - It changes the architecture after นุด's requirements of 2026-10-18 (R-H, R-C below), so it supersedes revision 4 (approved in round 5 at `db1a9d6`).
  - Every approved mechanism of revision 4 that still applies is carried over unchanged and marked *(carried)*.
  - Phases 4b, 5b and 6 still wait for นุด's decisions D1–D3.
- **Branch / worktree:** `plan/review-token-redesign` (base `a68fd8d`), `~/tmp/wt-prp-review-redesign`
- **Type:** REFACTOR + gate/policy change. **Complexity:** HIGH (prp-framework, ops, soul-orchestra; changes review rules).

## Requirements (นุด, 2026-10-18)

- **R-H: one protocol for every agent harness.** The review must run the same way from Claude Code, chela and codex. A harness is an adapter, never the protocol.
- **R-C: no new credential of any kind.** That means no new OS user, API token, key or proxy auth. The protocol uses only:
  - the login the calling harness already has;
  - goko's existing `gh` authentication, used only by the protocol's own deterministic posting step.
- **R-T: lower token cost** (the epic goal), without an observed loss of Critical or Important findings (Invariant 1).

## Summary

**Today:** `/prp-core:prp-review-agents` costs 8–21M cache-read tokens, about 1M cache-create tokens and 89–187k output tokens **per round** (baseline in #160). The LLM main thread is the largest single cost: 58–117k output per round, against 16–70k for the three review agents together.
- The main thread re-reads an 80 KB prompt on every turn.
- It does all the mechanical work: dispatch, deduplication, verdict, rendering, posting and checking.
- It relies on Claude Code's Agent tool, and in headless mode the turn can end before the agents finish (#151).

**This plan:**
- **Moves orchestration out of the LLM** into one deterministic, tested CLI.
- **Keeps the LLM only where judgement is needed:** one independent pass per review perspective. Each pass is a separate, blocking, **write-less** harness process that returns schema-checked JSON.
- **Gates each phase on a replay benchmark.** The benchmark shows zero observed regressions of labelled Critical or Important findings on a finite, frozen corpus (Invariant 1; this is not a proof of universal detection) and that the cost actually fell.

## Architecture

```
prp-review <PR> [--since-last-review] [--confirm] [--no-post]      (scripts/review/, bash + python -I)
 ├─ prepare   PR metadata, diff, changed files, prior findings → bundle dir (read-only clone at the head)
 ├─ plan      tier (pr-risk-tier) + path map → required passes (core + conditional [+ probe])
 ├─ dispatch  per pass: adapter run_pass <harness> <pass-prompt> <bundle> <schema> → pass.json
 │              blocking child process per pass; bounded concurrency, timeout, ulimit, nice
 ├─ validate  fail-closed JSON contract (carried)
 ├─ merge     dedup (same file ±5 lines + same category, highest severity, all agents listed)
 │            + verdict table (both rules today's Phase 4/6, now code)
 ├─ render    per-pass comments, exact provenance format, run id, footer
 ├─ scan      secret scan of every rendered body (gitleaks, existing tool) → fail closed
 ├─ post      gh (goko's existing auth); head checked before each post        ← skipped by --no-post
 └─ verify    every expected comment at the head, this run id, unedited → else exit ≠ 0
```

**Harness adapters** (`scripts/review/adapters/<harness>.sh`, about 20–40 lines each) start one pass. Every adapter must give the pass **no write capability, no shell and no MCP servers**, using that harness's own enforcement:

| harness | pass invocation (shape; exact flags pinned per harness version in the adapter) | enforcement |
|---|---|---|
| Claude Code | `claude -p` with a tools allowlist of Read, Grep and Glob only (Bash, Edit, Write and Web* denied), `--strict-mcp-config` with an empty MCP config, structured output by `--json-schema` | app-level tool allowlist |
| codex | `codex exec --sandbox read-only`, MCP servers disabled by config, `--output-schema` | OS sandbox (read-only filesystem, no network) |
| chela | `chela -p` **only after** chela offers a read-only tool policy. Its current `--policy` values are `allow-all` and `headless`; whether `headless` denies writes and shell is **unverified** | the adapter refuses to run (exit 2) until a chela issue delivers the policy and the conformance test passes. chela#651 is not touched |

- **Pass prompts** reuse the existing agent definitions (`adapters/claude-code-agents/{code-reviewer,security-reviewer,silent-failure-hunter,…}.md`, 6–9 KB each). A short harness-neutral wrapper adds the bundle location, prior findings (incremental) and the output contract.
- **Prompt caching:** each pass prompt has a static prefix (agent definition + contract) followed by the per-run bundle, so caching works per pass. This replaces revision 4's Phase 1 wrapper work.
- **Calling harnesses:** the existing slash commands in all six adapters (`/prp-core:prp-review-agents`, `/prp-core:prp-review`) become thin calls to `prp-review --harness <self>`. A Claude Code session, a chela session or a codex session all run the identical protocol.

## What the multi-agent design gave, and what this keeps

| axis | prp-review-agents today | this protocol | result |
|---|---|---|---|
| Specialist perspectives | 3 core agents with their own system prompts | the same agent definitions as pass prompts, on any harness | kept (now portable) |
| Independence between agents | separate agent contexts | separate processes | kept (stronger) |
| Parallelism | parallel spawn | bounded parallel dispatch | kept |
| Exploring code beyond the diff, pattern sweep | Read/Grep/Glob/Bash | Read/Grep/Glob | kept |
| Conditional agents by file type | main thread chooses | path map in the ruleset, recomputable by the gates | kept (deterministic) |
| Deduplication (Phase 4), verdict (Phase 6) | the LLM applies the rules | code applies the same rules | kept (exact) |
| Validation suite (Phase 5) | the main thread runs it | the CLI runs it, or records the green CI at the head | kept |
| Large-PR phasing, coverage map | the LLM splits the files | the CLI batches by risk category | kept |
| **Probes** (running code to prove a defect, e.g. `touch PWNED` in #152) | Bash inside an agent | not in review passes (no shell) | **moved to a probe pass** (Phase 1, before any production switch). It is required wherever the executable-verification path map matches, in any tier, and runs in the bwrap sandbox with a network-less command sandbox |
| **Write-capable agents** (docs-impact edits, code-simplifier) | edit during review | review never edits | **moved**: they report findings, and `prp-review-fix` or a separate step applies them |
| Narrative synthesis (Strengths, Recommended Actions) | LLM prose | a template from the JSON; an optional short synthesis pass reads only `pass.json` files | **reduced**; it does not affect the gates |

## Invariants

1. **Detection (regression form, not a universal claim).** On the frozen corpus, the new protocol shows **zero observed regressions on historical labels**.
   - **Labels:** the corpus labels are the Critical and Important findings that the current design posted in production. They are the baseline. The current prompt is **never re-run live** (it needs shell plus `gh`, which R-C will not sandbox with new identities).
   - **Regression candidate:** a label that the new protocol finds in fewer than `k` of `n` runs (default n=3, k=2).
   - **Adjudication, which can only REMOVE invalid labels and never excuses a miss (round-6 finding 2).**
     - A label leaves the gate only when written evidence on #160 shows that it is **invalid**, for one of two reasons:
       - it was not a real defect (e.g. the fix PR shows that it was a false positive);
       - or it is out of this protocol's scope by an objective rule (e.g. it concerned a file outside the bundle).
     - **One rule (round-7 finding 2):** a valid Critical/Important label must be found in ≥ k of n replays (default k=2 of n=3). Below that, at 1/3 or 0/3, it **blocks adoption**. The only ways forward:
       - targeted remediation (pass prompt, bundle construction, conditional selection, probe coverage) followed by a re-run;
       - or นุด explicitly accepting that label as a **known regression**, recorded on #160 with the label id. There is no watch-list pass-through.
     - A true defect is never reclassified as "stochastic" or "lucky" because the new design misses it.
   - **Bundle exclusion is not objective exclusion:** a label about content that the bundle does not contain is a **bundle-construction defect**. The bundle is remediated and the label stays in the gate. A label leaves only when evidence shows that it was not a real defect.
   - **Limit:** finite replay cannot prove that a finding is never lost.
2. **Provenance.** The CLI posts only fmt=2, and only after the Phase 1.5 dual-mode gates are live. Every fmt=2 comment still keeps, byte for byte, every fmt=1 field that today's parsers read (soul-orchestra `.github/merger-policy.yaml` `review_evidence`, ops `safe-merge` `_verify_review_provenance`), with the fmt=2 additions placed where fmt=1 parsers ignore them. Those fields are:
   - line 1 `Reviewed head:`, line 2 `Passes run:`;
   - the two severity headings;
   - the `Generated-by: prp-review-agents v<ver> run=<id> pass=<pass>` footer, one run id, unedited.
3. **No silent success.** A run that does not leave every expected comment at the reviewed head exits non-zero and says why.
4. **Pass confinement** (see "Write-safety", round-6 finding 1).
   - **What a pass can and cannot do:** a pass process sees only the sanitized bundle and its harness runtime, in an OS mount namespace. It cannot write outside its tmpfs, read goko's `HOME` or any GitHub credential, or use MCP. Review passes also have no shell tool.
   - **Where writes happen:** the only writes in the protocol are the CLI's own `post` and marker steps (comments only; the CLI never commits or pushes to the PR branch), outside any pass, as goko with existing auth. Replays never run them (`--no-post`; the bench entrypoint does not call them).
   - **Residual, stated:** the shared network channel to the model API.

**Verified by:**
- `tests/bench/replay.bats` plus the corpus, for invariant 1;
- `tests/commands/l2-comments.bats` and ops `test/safe-merge-marker-gate.test.sh` on CLI-rendered bodies, for invariant 2;
- `tests/scripts/review-run.bats` arms for partial post, failed post and head moves, for invariant 3;
- the **adapter conformance test** (below), for invariant 4.

## Write-safety without new credentials: a per-pass OS sandbox (round-6 finding 1)

Revision 4 needed a separate OS user, a Claude token and an egress proxy because the CURRENT prompt runs shell and `gh` inside the LLM. R-C forbids new identities and tokens. It does not forbid confining a process.

Every pass therefore runs inside an **unprivileged bubblewrap sandbox**, using only the harness's EXISTING login. No new user, token or proxy is created.

**Host facts (measured 2026-10-18):**
- `/usr/bin/bwrap` 0.9.0 is installed;
- unprivileged user namespaces are allowed (`kernel.apparmor_restrict_unprivileged_userns=0`, `user.max_user_namespaces=63819`).

**Sandbox per pass** (`scripts/review/sandbox.sh`):
- **System:** `/usr` and `/etc` read-only; `/run/systemd/resolve` read-only for DNS; `/proc`, `/dev` and a tmpfs `/tmp`.
- **`HOME`:** a fresh tmpfs at the same path. goko's real `HOME` is NOT mounted, so `~/.config/gh`, `~/.secrets`, `.netrc`, rc files, other agents' state and all MCP configs simply do not exist inside.
- **Harness runtime, read-only:**
  - the harness binary directory;
  - ONLY the harness's own auth file, at its usual path (Claude: `~/.claude/.credentials.json`; codex: `~/.codex/auth.json`; chela: its credential store);
  - a minimal generated config with no MCP servers and an app-level deny rule on the auth file itself (Claude: `permissions.deny: ["Read(~/.claude/**)", "Read(~/.claude.json)"]`).
- **Bundle, read-only:** the PR head's tracked files plus diff, metadata and prior findings. It is gitleaks-scanned before dispatch; a hit stops the run.
- **Environment:**
  - `GH_TOKEN`, `GITHUB_TOKEN` and `GH_ENTERPRISE_TOKEN` are unset;
  - `--die-with-parent`;
  - the CLI's guards (timeout, `ulimit -u`, `nice`).
- **Network** stays shared, because the model API needs it. This is the stated residual channel: the only data a pass can send out is what is inside the sandbox, which is the bundle under review plus the harness's own auth file. The auth file is denied to the tools by the app rule; the OS cannot hide it from the harness that must use it.

**Measured feasibility (2026-10-18, Claude Code, Haiku, existing login):**
- the pass read `/bundle/f.txt` (`READ1=hello`);
- `~/.config/gh/hosts.yml` was not readable (`READ2=ERR`), because it does not exist inside the sandbox;
- with the deny rule, reading `~/.claude/.credentials.json` was refused (`CRED=DENIED`);
- the first attempt timed out until `/run/systemd/resolve` was bound and a minimal `~/.claude.json` (onboarding keys only) was generated; both are now part of `sandbox.sh`.

**All file-access tools versus the harness's own auth (round-8 finding 1):**
- **The rule must cover every allowed file-reading tool and every auth/config path of that harness.** For Claude Code, `Read(<path>)` deny rules apply to all file-reading tools; Claude itself warns that `Glob(...)` rules are not matched and to use `Read(...)` instead.
- **Measured (2026-10-18):** inside the pass sandbox, a synthetic decoy `~/.claude/decoy-auth.json` (a random `DECOY-…-NOTREAL` value, never a real secret) under the deny rule `Read(~/.claude/**)`, `Read(~/.claude.json)` gave:
  - `Read`: DENIED;
  - `Grep` (pattern `DECOY`): DENIED;
  - `Glob` (`~/.claude/*`): DENIED.
  - The decoy value never appeared in any output; the test greps for it.
- **Conformance makes this permanent, per harness and per harness version.** For every allowed file tool (Claude: Read, Grep, Glob; codex and chela: their file tools), the canary tries to:
  - read the synthetic auth fixture placed at each of that harness's auth/config paths;
  - grep it for its known pattern;
  - list it with a glob.
  - **Pass condition:** the fixture value is absent from all output, checked by the script by exact match.
  - Any hit disables the adapter (fail closed).
- **Account-level MCP connectors** (seen during the test: an `mcp-sdk` OAuth notice) must also be off. The adapter disables claude.ai connectors and every other MCP source, and conformance item (d) checks that the pass's tool list contains no MCP tool.

**Invariant 4 (revised):** a pass process can read only the sanitized bundle and its harness runtime. It cannot write outside its tmpfs, cannot read goko's `HOME` or any GitHub credential, and has no MCP. The OS enforces the filesystem part (mount namespace); the app rule covers the harness's own auth file.

**Adapter conformance test** (`scripts/review/conformance.sh <harness>`):
- **When it runs:** for each harness version, on adapter change, and as a preflight before replay batches and gating runs (cached per binary digest).
- **No real secrets:** it uses a SYNTHETIC fixture: a fake `hosts.yml` holding a gitleaks test token, placed at the real path in a decoy `HOME` outside the sandbox. Real credentials are never put in a test prompt.
- **It checks** that, from inside the sandbox:
  - (a) a write outside tmpfs or bundle fails with EROFS/EACCES (checked by the script, not by the model);
  - (b) the decoy `hosts.yml` path does not exist;
  - (c) the harness auth file is denied to the model's tools;
  - (d) no MCP tool is listed;
  - (e) a probe-capable adapter's shell has no network (see Phase 1, probe).
- **Fail closed:** any failure disables that adapter (exit 2, with the reason).
- **Scope:** the canary is a regression check of the sandbox, not the proof of confinement. The proof is the mount layout itself, which a bats test asserts from the generated `bwrap` argv.

**Harness without a working sandbox:** it is not approved for gating reviews. The ruleset lists approved harnesses, and safe-merge/merger reject review comments whose footer names a harness that is not approved. That requires a `harness=<id>` field in the fmt=2 footer, part of the gate work before the production switch.

**Output scan:** gitleaks on every rendered body before posting stays as defence in depth. The rule name is reported, never the value.

## Not building

- No change to what counts as Critical or Important (the agent rubrics stay).
- No new credentials, OS users or network proxies (R-C).
- #154's round-cap ledger stays in #154 (P3, on hold). The CLI's run state is the base #154 can extend.
- No harness-specific orchestration features; anything a harness cannot do write-lessly, it does not do.

## Dependencies

- **#157 and #158 must merge first.** They touch the review prompt, the adapters and the generator.
- **chela:** a read-only tool policy (a new chela issue, opened by PSak). The chela adapter stays disabled until it lands.
- **นุด's decisions D1–D3** block Phases 4b, 5b and 6.
- **Overlaps:** the guarded wrapper (`~/tmp/run-review-guarded.sh`, soul-orchestra#1362 item 7). Its load, ulimit and timeout guards move INTO the CLI's dispatch, the tracked home, and #1362 item 7 closes against this epic.

## Codebase facts (sampled 2026-10-18)

| What | Where | Fact |
|---|---|---|
| Prompt size | `prompts/review-agents.md` | 1,624 lines, 79,488 bytes; `## Output` 24,461; Phase 2 spawn 8,009 |
| Main-thread phases now done by the LLM | `prompts/review-agents.md` | 0/0.5 context and incremental, 1.5 large PR, 3.0 worktree integrity, 4 dedup (rule at 939–960), 5 validation (978–1012), 6 verdict, Output (render, marker, artifact commit, post), metrics, report/PRD updates |
| Agent definitions | `adapters/claude-code-agents/*.md` (symlinked into `~/.claude/agents/`) | code-reviewer 6,286 B; security-reviewer 8,094 B; silent-failure-hunter 8,955 B |
| Run id / footer | `prompts/review-agents.md:1314-1359` | `RUN_ID=<UTC>-<8 hex>`; footer format |
| Tier | ops `bin/pr-risk-tier:262,267` | returns only `trivial` or `standard` |
| Gates | ops `bin/safe-merge:462-518`; soul-orchestra `.github/merger-policy.yaml:140,147-157,237,446-450` | exact pass names; every `Reviewed head:` comment must be 0/0; merger checks the round before |
| Harness flags | `claude --help`, `codex exec --help`, `chela --help` (2026-10-18) | claude: `--allowedTools`/`--disallowedTools`, `--json-schema`, `--output-format`; codex: `--sandbox`, `--output-schema`, `--json`; chela: `--policy allow-all\|headless`, `--result` |

## Phases (stacked PRs, each ≤ ~800 changed lines)

### Phase 0: Measurement, corpus, bench harness

- `scripts/bench/review-cost.py`: sums `usage` over a session jsonl plus `subagents/*.jsonl`, or the harness's equivalent (codex `--json` events, chela `--result`).
  - Weighted cost, using price ratios relative to input: cache_read 0.1, cache_create 1.25, output 5 (per model, from a table).
  - Read-only; run as `python3 -I`.
- `tests/bench/corpus.yaml` *(carried)*: historical heads with labelled Critical/Important findings (file, line region, defect, family, source pass).
  - **Frozen:** head and base SHAs, patch digest, source-comment permalink.
  - **Coverage:** all 3 core passes, ≥1 conditional agent, ≥1 **probe-found** finding (#152), ≥2 challenging heads (a large diff and a shell/security-heavy diff), plus negative controls (a docs PR and a trivial PR).
  - **Initial entries:**

    | PR | head | findings |
    |---|---|---|
    | #156 | R1 `2e715d1d` | 3C/1I |
    | #156 | R2 `cc7ceb55` | 1C/1I |
    | #156 | R4 `8d78023c` | 1C/1I |
    | #152 | R1–R3 | see #154 |
    | docs and trivial controls | — | — |

- `scripts/bench/replay.sh`: runs **only the new protocol**, with `--no-post`, on frozen heads, n times per harness under test. It collects `pass.json` and the cost, and it calls the conformance preflight first.
- **Cost baseline:** the historical jsonl of the current design (as in #160; no live re-run).

**ACs**
- AC0.1: `review-cost.py` reproduces the #160 baseline table within 1%.
- AC0.2: the corpus meets the coverage above (≥ 8 C/I across ≥ 5 heads), and every entry is frozen.
- AC0.3: a bench run makes zero writes. Shown by:
  - the conformance preflight passing;
  - no `post`/marker code being reachable from `replay.sh` (a bats test);
  - an unchanged comment count and latest `updated_at` on every corpus PR, before and after, queried read-only outside the passes.
- AC0.4 *(added 2026-10-18 after rev 9, นุด proposal relayed by pane -3; accepted by psak)*: a read-only rounds report (`scripts/bench/review-rounds.py`, `python3 -I`) over the baseline review runs and GitHub data gives:
  1. **Incremental fallback rate:** runs invoked with `--since-last-review` that ran a full review anyway (transcript has "No previous review found" or "Running full review instead", or no "Incremental review:" line), with count, rate, and the extra weighted tokens versus the incremental runs (via `review-cost.py`). Cause: `prompts/review-agents.md:73-101` @ `a68fd8d` finds the previous round only through the local `.prp-output/reviews/pr-<N>-agents-review.md` and lists changes with `git log --since`, which breaks across worktrees, headless runs and rebases. Observed 2026-10-18: psak's #171 rounds run from a worktree that holds no `pr-171-agents-review.md`.
  2. **Rounds to ship per merged PR:** review rounds before merge, each classified as (a) a real Critical/Important, (b) the same family repeated, or (c) a fallback or failed run (e.g. a silent exit 0 as in #151 AC1, or a launcher failure with no comments posted).
  3. The same report after cutover, so the plan reports the change in rounds and not only in tokens (Phase 4 gives prior findings to incremental passes deterministically, which removes the local-file dependency).
  Read-only like AC0.3: transcripts and `gh api` GETs only. Boundary cases: a transcript with no mode line (counted as "unknown", never as incremental); a PR closed unmerged (excluded from rounds-to-ship, listed); a round with fewer than three per-pass comments (class c).

**Boundary cases:** jsonl with no `usage`; subagent dir missing; a truncated line; a head missing on the remote (fetched by SHA, otherwise loud failure); a patch digest mismatch (abort).

### Phase 1: Protocol core, write-less (no posting yet)

- `schemas/review-findings.schema.json` *(carried)*.
- `scripts/review/`:
  - `prepare`, `plan`, `dispatch`, `validate`, `merge`, `render`, `scan`;
  - the Claude Code and codex adapters;
  - `conformance.sh`.
- **Dispatch guards,** absorbed from the guarded wrapper:
  - wait for load < N;
  - per-pass `timeout`;
  - `ulimit -u` relative to the current process count;
  - `nice`;
  - bounded concurrency (default 1 heavy job host-wide, using a lock file).
- **Fail-closed JSON contract *(carried, round-1 finding 3)*.** The expected pass set comes from a fresh `pr-risk-tier` at the reviewed head, re-checked at `validate`; a tier change aborts the run.
  - **Rejected outright, never rendered as clean:**
    - prose, fenced or partial or truncated JSON, or trailing text;
    - more than one object;
    - a duplicate, missing or unknown pass;
    - a failed pass process (non-zero exit, timeout);
    - absent or `null` `findings` (an empty list must be `[]` with `"complete": true`);
    - a finding without file, lines or evidence, or with a bad severity;
    - a mismatched `reviewed_head`;
    - counts that do not match.
  - **On rejection:** `REVIEW INCOMPLETE: <pass>: <reason>`, non-zero exit, nothing rendered.
- **Conditional agents *(carried, round-2/3 findings 5 and 2)*.**
  - **Required set:** the required conditional set comes from the path map, and each member's JSON is required.
  - **Placement:** conditional results are folded into the linked `code-reviewer` comment:
    - a `Conditional passes: <agent>=complete, …` line;
    - a fenced `` ```json review-conditional `` block;
    - an attribution table.
  - **Counting:** the headings count core plus conditional Critical/Important findings.
  - **Compatibility:** under fmt=1 the extra lines are ignored by today's parsers, and the counts still block a dirty conditional result.
- **Tests:** `tests/scripts/review-run.bats` covers every rejection; a tier change; a hostile field (`$(…)` or a newline); symlinked state files; the trivial tier; a conditional Critical; and a dedup/verdict table-driven suite mirroring the Phase 4/6 rules of today's prompt.

- **Probe: the model never holds a shell; the CLI runs probes in a separate child sandbox (round-6 finding 3, round-7 findings 1 and 4).**
  - **Two kinds of process:**
    - **The parent** is the probe pass's model process. It runs in the normal pass sandbox: the auth file, the model API network, NO shell tool. It returns `probe_requests` in its JSON: up to N commands, each with a purpose and the expected observation.
    - **The child** executes each request. The CLI (not the harness) runs it in its own `bwrap`, isolated as follows:
      - `--unshare-all`, so there is a new network namespace with **no egress at all**: no GitHub, no model API, no DNS;
      - `--clearenv` with only `PATH`, so there is no auth-bearing environment;
      - `--die-with-parent`, and inherited descriptors above 2 are closed;
      - tmpfs `HOME`; the harness auth file is **not mounted**;
      - `/usr` read-only; writes are possible only in a throwaway copy of the bundle (`/work`);
      - `timeout`, `ulimit -u` and an output cap (e.g. 16 KB per command, truncated with a marker).
    - **Second step:** the bounded outputs go back to a second parent-pass process (same sandbox, no shell), which writes the findings.
    - **Harness-neutral:** this works on any harness, because no harness shell sandbox is relied on.
  - **Measured (2026-10-18, this host, unprivileged):** a child with `--unshare-all --clearenv --tmpfs $HOME` saw the auth file `absent` and 0 token/key/secret environment variables. TCP to `api.github.com:443`, to `api.anthropic.com:443` and to the IP `140.82.112.5:443` was refused. `/usr` was read-only and `/work` writable.
  - **When probes run:**
    - **(a)** the pinned ruleset's **executable-verification path map** matches (shell and scripts, hooks, workflows, parsers and validators, installers, anything executed by CI), in any tier;
    - **(b)** any read-only pass may emit `probe_requests` when it is uncertain (config, generated docs, data-driven behaviour); the CLI then runs a probe step for that pass's requests in the same child sandbox.
    - **Corpus coverage:** every probe-sourced corpus label must be reached by (a) or (b) in replay. A bats test checks (a); the replay checks (b).
  - **Probe evidence in the linked comments, machine-readable (round-8 finding 2).**
    - **Requests:**
      - each **core** pass's linked comment carries its requests in a fenced `` ```json review-probe-requests `` block: request id, origin (`map` or `pass:<name>`), and `sha256` of the exact command;
      - **conditional** passes have no linked comment of their own, so their requests go into the **code-reviewer** comment's request block, each with `origin: pass:<conditional-agent>` (round-9 finding 2);
      - a pass with no requests carries an empty list, and the block is never absent.
    - **Render check, so nothing is dropped between the passes and the comments:** before posting, the CLI compares the union of the request sets in ALL validated raw `pass.json` files (core and conditional) with the union of the rendered request blocks, by id and command digest. Any difference means `REVIEW INCOMPLETE: probe request mismatch`, and nothing is posted. The gates can only check what was rendered, so this pre-post check is the guard against a dropped raw request.
    - **Manifest:** the code-reviewer comment carries a fenced `` ```json review-probe-manifest `` block, one entry per request id. Each entry holds:
      - the command `sha256`;
      - the exit code;
      - the `sha256` of the bounded output;
      - a status: `complete` | `failed:<reason>` | `unavailable:<reason>`.
    - **Overall line:** `Probe: complete | failed | unavailable | not-required`.
    - **Artifact, kept off the PR branch so the reviewed head never moves (round-9 finding 1):**
      - The bounded outputs are posted as one or more **probe-artifact comments** on the PR:
        - line 1 `Probe artifact for head: <reviewed head>`, line 2 `run=<run id> part=<i>/<n>`;
        - one fenced block per request id holding its bounded output;
        - unedited, secret-scanned before posting.
      - The per-command and total caps keep every part under GitHub's comment size limit.
      - Nothing is committed to the PR branch, which matches today's `--l2-comments` behaviour (`NO_COMMIT=1`).
  - **Gate checks (Phase 1.5).** The gates take the request set as the union of every linked comment's requests, plus a `map` request when the path map matches. Then:
    - every request id appears exactly once in the manifest, with a matching command digest;
    - `Probe: not-required` is valid only when that union is empty;
    - the round is clean only if every entry is `complete`, so a requested probe that failed or was unavailable can never be shown as `not-required` or clean;
    - the manifest's output digests match the probe-artifact comments that carry the same reviewed head and run id (all parts present, unedited, and posted after the manifest's run started);
    - a missing part, an edited part, a part for another head or run, or a digest mismatch means the round is rejected.
  - **Trust, stated:** the gates cannot re-run a probe. The manifest is an attestation by the CLI run, at the same trust level as the review comments themselves (author-forgeable on one shared account, as merger already states for other evidence). The digest-bound artifact comments make inconsistency detectable; they do not prevent forgery.
  - **Gate tests:**
    - a dropped request (an id in a pass block but missing from the manifest);
    - a missing output (a manifest digest with no artifact part);
    - a forged `complete` (digest mismatch with the artifact);
    - a tampered (edited) artifact part;
    - an artifact part for another head or another run id;
    - a dropped conditional request (present in a raw conditional `pass.json`, absent from the code-reviewer block): the CLI refuses to post;
    - head movement during posting (the carried head checks): no partial evidence is accepted;
    - `not-required` while requests exist;
    - a failed entry in a round claiming clean.
  - **Probe conformance, tested by the CLI against the OS, never by asking a model.** From inside the child:
    - reading the harness auth path fails (absent);
    - TCP to `api.github.com:443` and to the model API host fails;
    - a write outside `/work` fails;
    - the environment holds no `*TOKEN*`, `*KEY*` or `*SECRET*` names.
  - **Fail closed:** any failure makes probes unavailable. A run that requires one then fails closed with that reason.

**ACs**
- AC1.1: sandbox and conformance pass for Claude Code and codex, including the probe variant. The chela adapter refuses with a clear reason until its dependency lands.
- AC1.2: zero observed regressions on the corpus (Invariant 1 as revised, n=3), INCLUDING probe-sourced labels, with Claude Code passes.
- AC1.3: weighted cost per full round ≤ 40% of the historical baseline median (target; measured value reported either way). Costs are reported per harness on the same historical price basis, split into pass cost and orchestration cost (round-6 minor).
- AC1.4: the same corpus is run on codex (and on chela once available). A harness approved for gating needs conformance plus zero observed regressions; the ruleset records the approved harnesses.

### Phase 1.5: Gates first, before any CLI post (round-6 finding 4)

The ruleset and fmt=2 gate work of Phase 5 is pulled forward here, so that the gates enforce conditional completeness before the CLI posts anything. The CLI never posts fmt=1.

- **Versioned ruleset:** `review-rules.yaml` in soul-orchestra, with its version and digest, pinned by every consumer and failing closed on mismatch (*carried*). Its first version contains:
  - today's stop rule;
  - the core and trivial pass sets;
  - the conditional path map;
  - the executable-verification path map;
  - the approved harness list;
  - `fmt2_required_after` (initially unset).
- **Gates in dual mode** (safe-merge, merger-policy text, `verify-review-artifact.sh`):
  - **fmt=1** comments are validated exactly as today.
  - **fmt=2** comments are validated fully:
    - the conditional set is recomputed from the ruleset path map at the head;
    - the `Conditional passes:` line and the JSON block are checked, with counts matching the headings;
    - the probe pass is present when the path map requires it;
    - the footer carries `harness=<id>`, and that harness is in the approved list.
- **Activation follows the real cutover, not the Phase 2 switch (round-7 finding 3).**
  - **Phase 2 → Phase 3 gap:** while legacy commands still run on any harness, the gates stay in dual mode. Legacy fmt=1 rounds are accepted exactly as today, and CLI rounds are fmt=2.
  - **The CLI never emits fmt=1.** A test asserts it. A CLI-produced comment is always fmt=2 with `harness=<id>`, so the gates can tell the two flows apart.
  - **At the permitted cutover** (Phase 3: all harnesses approved, or the staged plan under D4 completed for the last legacy harness), `fmt2_required_after` is set to the cutover time. From then on a new fmt=1 round is rejected rather than treated as complete because its core comments exist.
  - **Rounds before the cutover stay valid** (*carried* mixed-round rule).
  - **Staged cutover under D4:** an activated harness's review command no longer has a legacy path at all (its adapter calls the CLI), so it cannot emit fmt=1. fmt=1 acceptance therefore ends only when the last harness is cut over. The legacy fmt=1 acceptance window is the same risk the system carries today, not a new one.
  - **Tests:**
    - in the Phase 2→3 gap: legacy fmt=1 round then CLI fmt=2 round (accepted); CLI fmt=2 then legacy fmt=1 (accepted, both clean);
    - after cutover: a new fmt=1 round (rejected);
    - a CLI comment claiming fmt=1 (impossible by test);
    - an fmt=2 comment from an unapproved harness (rejected).
- **Single-agent review never produces review evidence:** `--passes code` (the single-agent review) never posts a `Reviewed head:` line or a `Generated-by:` footer. It writes a local report only, which gates ignore. A test asserts this.
- **Tests:** the six fmt tests and the five conditional gate tests (*carried*); a missing probe; an unapproved harness; a `--passes code` output that is not review evidence.

### Phase 2: Post, verify, artifacts (production switch, fmt=2 only)

- `post`:
  - the head is checked before EACH comment and again after verification;
  - a partial post marks the run abandoned and exits non-zero, and the next run gets a new run id.
- `verify`: every expected comment is at the head, with this run id and unedited; otherwise exit 3.
- No artifact commit to the PR branch (the reviewed head never moves; local artifacts go to `.prp-output/reviews/` in the caller's worktree, uncommitted). L2 marker posting (`scripts/l2` logic replacing `~/tmp/l2-recipe-v2.sh`) and metrics: all in the CLI.
- `scan`: gitleaks on every body before posting; a hit means no post and the rule name is reported.

**ACs**
- AC2.1: the gates pass (safe-merge and merger provenance) on CLI-rendered comments on a real PR (Invariant 2).
- AC2.2: fewer than the expected comments means a non-zero exit (Invariant 3).
- AC2.3: a planted secret-shaped string (a gitleaks test fixture) in a pass output blocks posting.

### Phase 3: Harness cutover and retiring the old prompt (round-6 finding 5)

- **Cutover condition (R-H):** the six adapters' review commands are switched to `prp-review --harness <self>`, and the 80 KB prompt is retired, **only when every required harness (Claude Code, chela, codex) passes sandbox conformance AND the corpus gate**, i.e. it is approved in the ruleset.
- **Before cutover:** the legacy flow keeps running unchanged on every harness. The CLI is used only where a harness is approved and only through the explicit `prp-review` command; nothing switches implicitly.
- **D4 (new decision for นุด):** whether to allow a **staged cutover** (approved harnesses first) instead of waiting for all three.
  - If yes, an unapproved harness's review command does not fall back to the legacy prompt. It exits with "review unavailable on <harness>: <reason>; run it from an approved harness".
  - There is never a silent fallback either way.
- **Single-agent review:** `prp-review` (single-agent) becomes `--passes code`, which never posts review evidence (Phase 1.5).
- **Write-capable agents:** docs-impact and code-simplifier become findings-only passes; their edits move to `prp-review-fix` or a post-review step. Review never edits.

**ACs**
- AC3.1: cutover happens only after the approval condition (or D4), recorded with the ruleset version.
- AC3.2: `parity.bats` asserts that every adapter calls the CLI, and that an unapproved harness exits with the unavailable message (no legacy fallback).

### Phase 4: Fewer repeat rounds *(carried)*

- **4a:**
  - prior findings are given as input to incremental passes;
  - `RE-PLAN` exit when the same family has Critical/Important in 2 consecutive rounds (AC: the #156 R1→R2 pair emits it).
- **4b (D3):** carried from revision 4 unchanged:
  - Critical never moves;
  - a JSON out-of-scope block with a schema;
  - the gate re-derives the scope with a pinned `pr-scope-check`;
  - undecidable means in scope;
  - no human override as a gate input;
  - the gates are updated before the CLI emits the block.

### Phase 5: Tiers (the ruleset and fmt=2 moved to Phase 1.5)

- **Ruleset rules carried from revision 4, now delivered in Phase 1.5:**
  - pinned by safe-merge, `pr-risk-tier`, merger (blob SHA in the verdict), the prp CLI and verifier, and repo-own copies;
  - fail closed on a mismatch;
  - rollout order N → N+1 with the CLI last;
  - a compatibility matrix in CI.
- **Tiers:**
  - `pr-risk-tier` gains `docs` and `gate`, with precedence `gate` > `standard` > `trivial` > `docs` and a test for every pair;
  - **5a:** path-selected conditional passes;
  - **5b (D2):** the docs tier gets one pass and one clean round.

  | tier | passes per round | clean rounds | confirm |
  |---|---|---|---|
  | docs (5b) | code | 1 | — |
  | trivial | code | 2 consecutive | — |
  | standard | 3 core + conditional | 2 consecutive | the 2nd may be confirm (D1) |
  | gate/security | 3 core + conditional + probe | 2 consecutive full-strength | not allowed |

  In every tier, a probe pass is added whenever the executable-verification path map matches (Phase 1).

### Phase 6: Confirm round (D1) *(carried)*

- **Eligibility:** only at the same head as the latest run, and only when that run was clean.
  - It is revoked by a later dirty run or a head change.
  - Otherwise it fails closed.
- **What it runs:** a code pass with a "Critical/Important only" brief, plus a closure check of prior findings.
- **Exact format:** `Passes run: confirm` and the footer `… pass=confirm prev_run=<id> fmt=2`.
- **Gates:** they accept `confirm` only on this path.
- **Benchmarks:**
  - (a) the eligibility path at a fault-free identical head;
  - (b) SIMULATED adversarial detection on frozen faulty heads (never postable);
  - (c) fail-closed cases.
- **Adoption:** a fault class that confirm misses blocks adoption for that class, and cost alone never justifies it.
- **Cost:** confirm ≤ 25% of a full round.

### Phase 7: Model and synthesis tuning

- **Per-pass model by harness,** set in the ruleset. A cheaper model is adopted for a pass only with zero observed regressions (n=3).
- **Optional synthesis pass** (narrative only, reads only `pass.json`). It is off by default and never affects counts or the verdict.

## Rule-copy and enforcement inventory *(carried, round-1 finding 7)*

Edit sources, then regenerate. A line-scanning test fails on any stale copy (lesson from SO#1321).

| Kind | Source | Generated / mirrored |
|---|---|---|
| Enforcement | ops `bin/safe-merge` (462–518), ops `bin/pr-risk-tier`, prp `scripts/verify-review-artifact.sh`, the new prp `scripts/review/` | — |
| Merger policy | soul-orchestra `.github/merger-policy.yaml` (140, 147–157, 237, 446–450, `TIER RECORD`), `agents/merger.yaml` | repo-own policy copies (enumerate with `gh search code`) |
| Protocol / identity | soul-orchestra `conductor/protocol.md`, `conductor/philosophy-rationale.md`, `generator/agent_md_common.py`, `agents/*.yaml`, agent-home templates, `conductor/wiki/{orchestration-guide,delegation-protocols}.md`, `docs/ARCHITECTURE.md` | agent-home `CLAUDE.md` / `AGENTS.md` |
| Global | the source of `~/.claude/CLAUDE.md` and the workspace `AGENTS.md` / `CLAUDE.md` | installed copies |
| PRP | `prompts/review-agents.md` (→ thin), `prompts/review.md`, `prompts/review-fix.md`, `prompts/integration.md`, `prompts/run-all*` | the 6 adapters (generator); installed copies (`prp-install-all`) |

## Risks

| Risk | Mitigation |
|---|---|
| Write-less passes miss findings that relied on the shell | The probe step (CLI-run child sandbox), required by the executable-verification path map in any tier or on a pass request; probe labels in the corpus; Invariant 1 per phase |
| A harness ignores its tool restriction | Conformance canary per harness version, fail-closed adapter |
| A pass leaks a secret it read | Secret scan before posting, fail closed, report the rule name only |
| codex or chela pass quality differs from Claude | Per-harness corpus results; the ruleset lists the harnesses approved for gating reviews |
| A rendering bug breaks merger provenance | Invariant 2 tests in both repos; a real-PR check before the switch |
| Rule drift across 15+ copies | Line-scanning test |
| Replays cost tokens | Small corpus, on demand, cost logged on #160 |

## Peer review asks (devlead-codex, round 10)

1. Do the revisions close R9-1 and R9-2 (see "Round 9" in the revision log)?
2. Is the residual channel (the shared network to the model API, carrying only the bundle and the harness's own auth file, which the app rule denies to the tools) acceptable under R-C as stated?
3. Is the executable-verification path map a sound trigger for the probe pass?

## Revision log

Revision 4 (`db1a9d6`) was approved by devlead-codex after five rounds:

| round | verdict | findings |
|---|---|---|
| 1 | REQUEST CHANGES | 8 |
| 2 | REQUEST CHANGES | 6 |
| 3 | REQUEST CHANGES | 2 + 1 |
| 4 | REQUEST CHANGES | 2 + 2 |
| 5 | APPROVE | implementation cautions |

The per-round finding tables are in that commit. Their resolutions are carried here where they still apply:

| finding | where it lives now |
|---|---|
| fail-closed JSON (R1-3) | Phase 1 |
| conditional fold and gate recompute (R2-5, R3-2) | Phases 1 and 1.5 |
| versioned ruleset (R2-4) | Phase 1.5 |
| fmt=2 activation (R4-1) | Phase 1.5 (activation at the Phase 3 cutover) |
| 4b design (R1-4, R2-1, R3-c) | Phase 4b |
| confirm (R1-6, R2-2) | Phase 6 |
| rule inventory (R1-7) | the inventory section |
| finite-corpus wording (R1-1, R4-n1) | the Summary and Invariant 1 |
| round-5 cautions: fmt=2 parser exactness, `created_at` from GitHub | Phase 1.5 |

**Revision 5 (2026-10-18): นุด's R-H and R-C.**
- **Orchestration** moves from the LLM main thread into the deterministic CLI; harness adapters run write-less passes; the multi-agent axes are kept, with the table above.
- **Write safety:**
  - Removed: revision 4's OS boundary (a `prp-replay` user, a Claude token, an egress proxy, AC-N1..N5), because R-C forbids new credentials.
  - Replaced by: passes with no write tool, an adapter conformance canary, a secret scan, and posting only in deterministic CLI code.
  - Also removed: the live baseline replay of the current prompt.
  - Invariant 1 now uses historical labels, with every miss adjudicated.
- **Behaviour changes:**
  - Probes become a sandboxed probe pass (made general to any tier in revisions 6 and 7); write-capable agents move out of review.
  - The guarded wrapper's guards move into the CLI (closes the overlap with soul-orchestra#1362 item 7).
- **Phases renumbered:**

  | revision 4 | revision 5 |
  |---|---|
  | Phase 1 (cache) | per-pass cache by design |
  | Phase 2 (scripts) | Phases 1–2 |
  | Phase 3 (shared prompt) | Phase 3a (the prompt is retired) |

**Round 6 (devlead-codex, 2026-10-18): REQUEST CHANGES on revision 5, 1 Critical and 4 Important.**

| # | Finding | Change (revision 6) |
|---|---|---|
| R6-1 (Critical) | A prompt canary is not confinement; Read can reach goko's secrets; the canary put real credentials in a prompt | A per-pass unprivileged **bwrap** sandbox with no new credential: tmpfs `HOME`, only the bundle plus the harness binary and its own auth file mounted (app deny rule on that file), no MCP, no gh config. **Measured working** with Claude Code: bundle readable, `hosts.yml` absent, auth file denied. The canary uses SYNTHETIC decoy secrets and is a regression check only; the mount layout is asserted by a test. Unapproved harnesses are rejected by the gates through `harness=<id>` |
| R6-2 | "Lucky catch" adjudication excused real misses | Adjudication can only remove labels proven invalid with written evidence; a valid label missed in ≥ 2/3 replays blocks adoption until remediated |
| R6-3 | Probe came after the zero-regression gate, and only for the gate tier | The probe pass is built in Phase 1, before any switch; it is required by an executable-verification path map in any tier; probe labels must be triggered (test); OS-tested write and network denial; fails closed on harnesses without it |
| R6-4 | Conditional completeness not enforced at the gates before posting | New Phase 1.5: the ruleset and dual-mode fmt=2 gates (conditional recompute, probe presence, approved harness) land before the Phase 2 switch; the CLI posts fmt=2 only; `fmt2_required_after` is set at the switch, so a new fmt=1 round is rejected; `--passes code` never posts review evidence |
| R6-5 | Cutover before all harnesses pass breaks R-H | Cutover only when Claude Code, chela and codex are all approved; otherwise the legacy flow continues unchanged. New decision **D4** for นุด: a staged cutover, with an explicit "unavailable" exit and no fallback |
| minor | Auth mapping; cost comparability | Only the auth file is mapped, and `HOME` stays hidden; costs per harness on the same price basis, split into pass and orchestration |

**Round 7 (devlead-codex, 2026-10-18): REQUEST CHANGES on revision 6, 1 Critical, 2 Important and 1 Moderate.** R6-4 and R6-5 were closed; R6-2 and R6-3 improved.

| # | Finding | Change (revision 7) |
|---|---|---|
| R7-1 (Critical) | Probe shell commands could read the mounted auth file and use the shared network | The model never holds a shell. It emits `probe_requests`, and the CLI runs each in a child `bwrap` with `--unshare-all` (no egress at all), `--clearenv`, no auth file mounted, closed descriptors and capped output; the results go back to a second shell-less pass. **Measured:** auth absent, 0 secret-named variables, GitHub, model API and a raw IP all refused, `/usr` read-only. The probe conformance is run by the CLI against the OS |
| R7-2 | 1/3 watch list contradicted k=2/n=3 | One rule: a valid label below k/n blocks, unless remediated or explicitly accepted by นุด as a known regression; a bundle omission is a bundle defect, never an exclusion |
| R7-3 | Activation at the Phase 2 switch would reject legacy rounds | Dual mode until the permitted cutover (Phase 3 or the last harness under D4); the CLI never emits fmt=1 (fmt=2 + `harness=<id>`); tests for the gap, mixed rounds and after cutover |
| R7-4 (Moderate) | Probe trigger by path map only | Plus pass-initiated `probe_requests` on uncertainty; every probe label reached by the map or a request in replay; `Probe: <status>` line in the linked evidence, enforced by the gates |

**Round 8 (devlead-codex, 2026-10-18): REQUEST CHANGES on revision 7, 2 Important.** R7-1..R7-4 were substantially addressed.

| # | Finding | Change (revision 8) |
|---|---|---|
| R8-1 | Grep and Glob might read the mounted auth file; one Read refusal proves little | **Measured:** Read, Grep and Glob were all DENIED on a synthetic decoy under `Read(~/.claude/**)`, and the decoy value never appeared. Conformance now runs every allowed file tool against synthetic fixtures at every auth/config path per harness and version (exact-match check by the script, fail closed). Account-level claude.ai MCP connectors are disabled and checked |
| R8-2 | A bare `Probe:` line cannot show requested-but-dropped probes | Request blocks in each linked pass comment; a manifest block (id, command digest, exit, output digest, status) in the code-reviewer comment; outputs committed as an artifact; the gates check union, consistency and digests; a requested failure is never clean; the trust level is stated; 5 gate tests |
| minor | Stale Phase 5 references; the Risks row | Revision-log locations moved to Phase 1.5; the Risks row now says any tier or a pass request |

**Round 9 (devlead-codex, 2026-10-18): REQUEST CHANGES on revision 8, 1 Important and 1 Moderate.** R8-1 was accepted at plan level.

| # | Finding | Change (revision 9) |
|---|---|---|
| R9-1 | Committing probe artifacts to the PR branch moves the reviewed head | The CLI never commits to the PR branch, matching today's `--l2-comments` `NO_COMMIT=1`. Probe outputs are posted as head- and run-bound, unedited, secret-scanned probe-artifact comments; the gates check every part and digest against the manifest; tests cover tampered, absent, wrong-head and wrong-run parts and head movement |
| R9-2 | Conditional requests had no linked block; a dropped raw request was undetectable | Conditional requests go in the code-reviewer block with `pass:<agent>` attribution; before posting, the CLI compares all raw `pass.json` request sets with the rendered blocks and refuses to post on any mismatch; a dropped-conditional-request test |

**Round 10 (devlead-codex, 2026-10-18): APPROVE revision 9.** These implementation cautions bind the implementing PRs:
- **Artifact comments:**
  - generate and secret-scan ALL probe-artifact comment bodies before posting ANY of them;
  - check the PR head before each artifact comment, as well as before each per-pass comment.
- **Reject, never pass:**
  - duplicate part numbers or request ids;
  - edited or deleted parts;
  - truncated or oversized output. A clipped result is reported as `failed:truncated`, never as an unqualified `complete` proof.
- **L2 marker:** posted only after gate-equivalent verification of every probe artifact and every linked pass at the same head.
- **Mandatory preconditions:**
  - the shared model-API channel stays a disclosed residual risk;
  - per-harness credential-tool denial and `bwrap` conformance must pass before any harness is used.

## Phase 1a validator, v4 re-plan (2026-10-18, after #171 R9)

#171 R9 (run 20261018T070133Z-08c36c42 @ 00c828e2) found the same family again ("the validator accepts a schema construct it does not check"): a node with `required`/`properties`/`additionalProperties`/`items` but no `type` passes `check_schema`, and `validate()` then skips those constraints (psak reproduced: exit 0 on a doc missing `file` with an extra key; the pinned schema gives exit 1). That family appeared in R2, R4, R5, R6, R7 and R9. Patching one more keyword is not a fix. With 9 of 10 rounds used, #171 cannot reach two clean rounds, so it is closed and re-routed as a new PR on the same branch.

- **Invariant:** `check_schema` accepts a node only if every keyword on it is one that `validate()` enforces for that node's declared type, or a pure annotation. Equivalently: for every accepted schema, every constraint keyword present is enforced.
- **Design:** one table, `ENFORCED = {"object": {properties, required, additionalProperties}, "array": {items, minItems, maxItems}, "string": {enum, pattern, maxLength}, "integer": {minimum}, "boolean": {}}`, with `ANNOTATIONS = {title, description}` (+ `$schema`, `$defs` at the root only). Every non-`$ref` node must declare `type` in `ENFORCED`. `check_schema` rejects any keyword outside `ENFORCED[type] | ANNOTATIONS`. `validate()` dispatches by the same table, so the two cannot drift. Sample (pinned schema 1250e78a…): every non-`$ref` node has a `type`, and its keyword pairs are exactly array{items,minItems,maxItems,description}, boolean{description}, integer{minimum}, object{$schema,additionalProperties,description,required,title}, string{description,enum,maxLength,pattern}. The table accepts the pinned schema unchanged.
- **Boundary cases (generated from the table, not hand-listed):** (1) for each type T and each keyword K in `SUPPORTED − ENFORCED[T] − ANNOTATIONS`, a node `{type: T, K: <well-shaped value>}` exits 2; (2) for each non-`$ref` node of the pinned schema, removing `type` exits 2; (3) for each (T, K) in `ENFORCED`, a document violating K exits 1 (the table's claims are enforced); (4) the 48-case document sweep and the 25-case shape sweep stay, and every sweep counts executed cases and fails on any skip (R9 Important: `schema-shape-sweep.py` swallows construction errors).
- **Verified by:** the generated sweeps (1)–(3) in bats, with case counts derived from `len(ENFORCED)`/`len(SUPPORTED)` and asserted equal to executed counts.

## Phase 1a validator, v5 correction (2026-10-18, after #174 R4)

#174 R4 (run 20261018T082321Z-11e92aac @ 736816c2) found 2 Critical and 1 Important, all in the verification tooling. psak reproduced the cause on a copy: add `"pattern"` to `ENFORCED["array"]` (a keyword `validate()` does not enforce for arrays) and every sweep still passes (reject 38/0, notype 20/0, enforce 12/0, doc 48/0, shape 25/0). Two root causes:
1. v4 said "`validate()` dispatches by the same table". It does not: `validate()` checks each keyword with its own hand-written `if`, and never reads `ENFORCED`. The validator's docstring claims otherwise. So a table entry can exist with nothing enforcing it, which is the #171 family again.
2. The sweeps are confounded or self-referential. Reject mode changes the `type` of `$defs.finding` but leaves its object-only keys, so `required` triggers the rejection rather than the keyword under test. Enforce mode keys its violating documents on the keyword only, at fixed fields of the pinned schema, so it never tests (T, K) at a node of type T. The sweeps derive their cases from the table under test, so they cannot see a wrong table entry. `doc-sweep.py` and `schema-shape-sweep.py` exit 0 whatever their `bad` count.

The sweep failures have now come up in R1 (path navigation), R2 (copied table), the a174 gap (executed count never asserted) and R4 (confounded cases): the same family, "the verification does not test what it claims". Per the stop rule this is re-planned, not patched.

- **Invariant (validator):** a keyword is accepted on a node of type T only if a handler enforcing it for T exists. This holds by construction: `HANDLERS = {T: {K: fn}}` is the only place keyword checks live, `ENFORCED = {T: set(HANDLERS[T])}` is derived from it, and `validate()` checks the type, then calls `HANDLERS[T][K]` for every non-annotation keyword on the node. No keyword check exists outside `HANDLERS`.
- **Invariant (tests):** each sweep case isolates exactly one (T, K) and has an oracle that does not come from the validator.
- **Boundary cases:**
  - (a) For every (T, K) with K in `ENFORCED[T]`: the test schema is `{type: object, properties: {x: NODE}, required: [x], additionalProperties: false}`, with `NODE = {type: T, K: v}` only. Re-pin it, then check that a violating `x` exits 1 and a satisfying `x` exits 0. `(v, bad, good)` come from a hand-written `CASES` table in the test file. `set(CASES) == {(T, K) for T in ENFORCED for K in ENFORCED[T]}` is asserted, so a missing pair and an extra pair both fail.
  - (b) For every (T, K) with K in `SUPPORTED − ENFORCED[T] − ANNOTATIONS − {type}`: the same wrapper with `NODE = {type: T, K: v}` only exits 2, and stderr names K.
  - (c) Notype: as in v4.
  - (d) Mutation kills. Each mutant must make at least one sweep exit non-zero; each is a bats test against a temporary copy of the validator, and the test asserts that the mutation applied:
    - add a keyword with a no-op handler to `HANDLERS["array"]`;
    - make one existing handler return `None`;
    - remove one handler.
    A keyword check outside `HANDLERS` is ruled out by the single dispatch point in `validate()`, and reviewers check for it; no sweep can detect it.
  - (e) Every sweep exits non-zero on `bad > 0` or 0 cases executed. bats asserts the exact count as an anchored token (`executed=39 ` with a following space, or a regex), not a substring.
- **Pinned schema:** unchanged (sha256 1250e78a…); the table content is unchanged.
- **Verified by:** sweeps (a)–(c) in bats with derived counts; mutation tests (d) all killed; the reproduction above (array + `pattern`) is mutant 1 and must fail.

## Revision 10 proposal: phase order and v1 scope after the round data (2026-10-18; round 11 REVISE, 4 findings applied; PENDING round 12)

**Input:** brief 20261018-1530-7c1e, relayed from pane -3 (นุด: "ทำ1 ก่อนครับ ถ้าได้ข้อมูลครบแล้วค่อยเริ่ม 2,3"). Data: Oracle `learning_2026-10-18_measurement-where-review-rounds-go-52-prs-merg`; scripts and `rounds.tsv` (175 lines) in `~/tmp/review-rounds-analysis-20261018/`. 52 PRs merged 2026-10-11..18, 310 rounds, median 5:

| Bucket | Rounds | Share |
|---|---|---|
| 2-round minimum | 104 | 34% |
| fix loop before the first clean round | 103 | 33% |
| re-roll between the first and the 2nd consecutive clean round | 53 | 17% |
| after 2-clean, head changed by a merger CHANGES_REQUESTED | 50 | 16% |

After a clean round, the next round at the SAME head came back dirty 28 of 77 times (36%). Late C/I came from silent-failure-hunter 27, code-reviewer 12 and security-reviewer 8, and pointed at product paths 40 times and at test/tooling paths 2 times. Cost: headless 4.9M cache_read per run against 10.1M in-session, so headless stays the base.

Stop-rule changes are นุด's decision (pane -3) and are not part of this revision.

### R10-1: Phase 6 (confirm) moves to right after Phase 2. Accepted, with two conditions.
- **Order:** 0 → 1 → 1.5 → 2 → **6** → 3 → 4 → 5 → 7. Benchmarks (a)/(b)/(c), the adoption rule ("a missed fault class blocks adoption; cost alone never justifies it") and "no confirm in the gate tier" are unchanged.
- **Condition 1: the gate-tier rule needs a pinned gate tier** (revised after round 11).
  - `pr-risk-tier` today prints only `trivial` or `standard` (`~/ops/bin/pr-risk-tier --help`, 2026-10-18).
  - The `gate` classification moves from Phase 5 into Phase 6. It is pinned in the ruleset (version and digest, fail closed on a mismatch, as in Phase 1.5) and has precedence `gate` > `standard`.
  - Its tests move with it: the pair-precedence tests, and a gate-path fixture per gate-integrity class in merger.yaml.
  - Until this ships, confirm is ineligible on every PR (fail closed). The docs tier stays in Phase 5.
- **Condition 2: confirm keeps the conditional and probe eligibility rules** (round 11). A confirm round never stands in for a round whose required set includes a conditional or probe pass that the confirm set does not run. The required set is recomputed from the path map at the head. Such a PR gets a full second round.
- **Condition 3: predecessor format** (round 11). Confirm's `prev_run` must be a clean CLI fmt=2 run at the same head. A legacy fmt=1 predecessor makes it ineligible (fail closed). Tests cover both: an fmt=2 predecessor is eligible, and an fmt=1 predecessor is refused.
- **Condition 4: the confirm pass set comes from validated defects, not heading counts** (round 11).
  - **Correction to the input data:** 27/12/8 are summed `### Critical/Important (N found)` heading counts, not distinct defects. The 28 same-head dirty rounds are not 28 distinct heads.
  - **Before any pass is selected,** the benchmark (b) corpus is built in four steps:
    1. deduplicate the rounds to distinct heads;
    2. split each finding into a distinct defect (file, region, defect);
    3. validate each defect against its head as real or not real, recording the reason;
    4. label each defect by source pass.
  - **Coverage required:** silent-failure-hunter, code-reviewer AND security-reviewer classes.
  - **Pass set:** the smallest set that detects every validated class, starting from code + silent-failure-hunter. A security class it misses adds security-reviewer.
  - **Cost:** if the set breaks "confirm ≤ 25% of a full round", the target is reported as missed. It is never met by dropping a pass.
  - **Adoption** waits for the full corpus, including probe-sourced labels (R10-3).
- **Not claimed:** validation (step 3) is what decides how many of the same-head findings are real. The headline 36% does not.

### R10-2: "Phase 2-lite" (the CLI posts fmt=1 before Phase 1.5). REJECTED (devlead-codex, round 11).
- **It breaks a stated invariant:** "The CLI never emits fmt=1. A test asserts it" (Phase 1.5, round-7 finding 3). That invariant is how the gates tell a CLI round from a legacy round.
- **Not the same gap as today.** The R6-4 gap (conditional completeness not enforced) exists in legacy rounds today, but it ends at cutover for a known, bounded set of commands. Phase 2-lite adds a second, indistinguishable producer of fmt=1 rounds. Removing it later needs a new invariant.
- **The saving is small and temporary.** It lands only on Claude Code rounds between Phase 2-lite and Phase 1.5, which is one stacked PR's worth of time.
- **Decision:** rejected in round 11 (it also breaks the R6-4 closure). The order stays 1.5 → 2.

### R10-3: v1 scope (the first PRs before a payoff).
- **fmt=2 dual mode stays in v1.** The CLI posts only fmt=2, so without gate acceptance of fmt=2 it cannot post at all. Deferring dual mode would amount to R10-2.
- **The probe child sandbox moves out of v1, to before Phase 3 (cutover), and stays fail closed.**
  - From Phase 2 to the probe PR, the CLI exits non-zero with "review unavailable: probe required (<reason>); run the legacy review" in two cases: when the path map requires a probe (Phase 1 (a)), and when any pass emits `probe_requests` (Phase 1 (b)).
  - Such a PR is reviewed by the legacy flow, which still runs on every harness until Phase 3.
  - Nothing is silently skipped. A bats test asserts both exits, and AC0.4 counts these runs as class (c).
  - **Phase 1 ACs are split** (round 11: deferring the child contradicted AC1.1/AC1.2 as written):
    - **v1:** AC1.1 = sandbox and conformance (a)–(d) without the probe variant. AC1.2 = zero observed regressions on the corpus EXCLUDING probe-sourced labels.
    - **AC1.1p / AC1.2p, in the probe-child PR:** the probe variant of conformance, including (e); zero regressions on the probe-sourced labels.
    - **AC1.5, new in v1:** in replay, every probe-sourced corpus head triggers the unavailable exit, through the path map or `probe_requests`. A probe-label head that does not trigger it fails AC1.5. This keeps every probe-needing PR legacy-only until the child ships.
  - **Harness approval in v1 is restricted:** the ruleset records "approved for non-probe reviews", not unrestricted approval (AC1.4). Unrestricted approval needs AC1.1p/AC1.2p.
  - **Phase 3 cutover and confirm adoption wait for the full corpus**, including probe labels. Cutover also requires: "the probe child sandbox has shipped and passes conformance (e)".
- **Effect:** v1 is Phase 1 without the probe child, then Phase 1.5, then Phase 2, with probe-needing PRs routed to the legacy review.

### R10-4: Phase 0 AC0.4 is a hardened port of `rounds52.py` (revised after round 11).
- `scripts/bench/review-rounds.py` is a reviewed port of `~/tmp/review-rounds-analysis-20261018/rounds52.py`, using the same read-only rules as AC0.3.
- **The port fixes three fail-open behaviours** of the script, measured 2026-10-18:
  - **A failed fetch:** today `comments()` returns `[]` on a `gh api` failure, so the PR silently has no rounds. In the port, the PR is `unknown` and the report exits non-zero.
  - **An incomplete run:** today a run is clean when its parsed headings sum to 0, without checking that all three core passes posted. In the port, a run with fewer than the required passes, or an unparsed heading, is `incomplete` and never clean.
  - **The post-clean head change** is attributed only from verified data:
    - merger-bot's formal review state from the `pulls/<N>/reviews` API, bound to `commit_id`;
    - the head SHA from each comment's `Reviewed head:` line.
    An unattributable head change is `unknown`, never a merger bucket.
- **AC0.4 item 2 gains the four buckets** (minimum / fix loop / re-roll / post-clean head change), plus `incomplete` and `unknown`.
  - The buckets are mutually exclusive, with one fixture per bucket and a fixture that would fit two buckets.
  - The total reconciles to the run count: 310 for the 2026-10-11..18 set. Any difference is listed per PR, never absorbed.
- **Re-measurement:** the same report runs after cutover, and again after Phase 6, together with the same-head-dirty-after-clean rate.

**Invariant (unchanged):** a review round's evidence is either a legacy fmt=1 round or a CLI fmt=2 round, and the gates can always tell which. Confirm is accepted only on its eligibility path: never in the gate tier, never before the pinned gate tier exists, never in place of a required conditional or probe pass it does not run, and never after a fmt=1 predecessor. Until the probe child ships, a probe-needing PR is reviewed only by the legacy flow.
**Verified by:**
- the Phase 1.5 fmt tests (the CLI never emits fmt=1);
- the Phase 6 tests: confirm is ineligible with no pinned gate tier; the `gate` > `standard` pair tests; conditional/probe ineligibility; fmt=1 versus fmt=2 predecessor;
- the probe-unavailable bats test (two exits) and AC1.5 (every probe-label head triggers it);
- benchmark (b) on the deduplicated, validated corpus;
- the AC0.4 fixtures (exclusive buckets, unknown/incomplete) and the 310 reconciliation.

# Plan: prp-framework#151 AC1 — make each review round one blocking dispatch

Status: approved by psak, 2026-10-17. Issue: gobikom/prp-framework#151. Evidence: issuecomment-6230966016.

## Problem

On Claude Code 2.1.302, an Agent call runs in the background unless `run_in_background: false` is passed. Each finished agent then arrives as its own task-notification turn, so the caller wakes once per agent. Measured on SO#1358: 3 wakes in R3 and 7 in R4. The "One Wake Per Round" section says that parallel Agent calls in one message "already block", which is not true on this runtime.

A diagnostic in session `19263eef` dispatched 3 Agent calls in one message with `run_in_background: false`. The caller got 0 task-notification turns: every result came back as a tool_result of the same assistant message.

## Invariant

**Invariant:** in the Claude Code adapter, every Agent dispatch in prp-review-agents (3 core and 7 conditional) passes `run_in_background=false`. The skill text says this parameter is what makes the round block. A review round therefore costs the caller one wake.

**Verified by:**
1. A bats test that counts `Agent(` dispatch blocks in `adapters/claude-code/prp-review-agents.md` and requires `run_in_background=false` inside each one. Today's count is 10. The test must fail if any one block loses the parameter: assert the dispatch count equals the parameter count, and that the count is at least 10.
2. A live re-measure by psak after merge, outside the PR: run one real round, then count task-notification user turns in the caller's jsonl. The expected count is 0.

## Boundary cases

| Case | Expected |
|---|---|
| TIER=trivial (only Agent 1) | Agent 1 still carries the parameter |
| Conditional agents found after diff analysis and sent in one later message | Each conditional block carries it |
| Adapters for runtimes without this parameter (codex, thclaws, opencode, antigravity, gemini) | Must not get a Claude-Code-only parameter that their tool would reject. Use the generator's per-tool overlay (`prompts/overlays/`, `adapters.yml`) so only claude-code gets it. If you inject it into the shared prompt instead, show that every other runtime ignores it, and cite where. |
| Background-shell fallback (the text that is already there) | Leave as is; it covers runtimes with no Agent tool |
| A reviewer that fails or times out | Handled the same way as now; only the wake count changes |

## Changes

1. `prompts/review-agents.md` and/or the claude-code overlay: add `run_in_background=false` to all 10 dispatch blocks for the claude-code adapter.
2. Rewrite the "Blocking wait is the mechanism" bullet. Blocking comes from `run_in_background=false` on every Agent call. Putting the calls in one message is still required, but it is not what makes them block. Without the parameter, each agent's completion is a separate caller wake.
3. Regenerate the adapters with `python3 scripts/generate-adapters.py`. Commit only the files it changes and that belong to this fix.
4. Tests: add the check from "Verified by" item 1 to `tests/commands/review-rounds.bats`. Every existing test, including parity.bats, must still pass.
5. Add a CHANGELOG entry and bump the version the way #152 did.

## Out of scope

- #151 Part 2.1, 2.2 and the completion-proof work (#153, #154). These are ON HOLD.
- Any change to how failures are judged.

## Validation

- `bats tests/commands/review-rounds.bats tests/adapters/parity.bats` and the rest of the repo's documented test suite: all green.
- `git diff --name-only origin/main` lists only the prompt/overlay, the regenerated adapters, the test, the CHANGELOG, the version file, and this plan.
- Size: well under 800 lines.

## Re-plan after round 2 (same finding family twice: generator placeholder validation)

R1 Critical #3 and R2 Critical #1 are both "a misspelled generation-time placeholder ships silently". Patching single strings did not close it. Fix the design.

**Invariant:** generation-time placeholders are a CLOSED, registered set in one reserved namespace. Every brace token whose name starts with `AGENT_`, underscore included (case-insensitive, regex `\{agent_[a-z0-9_]*\}` with re.I), is a generation-time placeholder. The existing prose token `{agent}` ("still waiting on {agent}", prompts/review-agents.md:340) has no underscore, so it is outside the namespace and must keep generating unchanged. Add a test arm for it. The generator (a) rejects any such token in a prompt that is not in its registry (`GEN_PLACEHOLDERS = {"AGENT_BLOCKING_PARAM", "AGENT_BLOCKING_PROSE"}`), and (b) rejects any such token left in generated output. Runtime placeholders (`{NUMBER}`, `{N}`, `{CONTEXT_PATH}` …) never use that prefix, and nothing about them changes. Every value a registered placeholder takes comes from adapters.yml. The generator holds no fallback text, and a missing value is an error.

**Verified by:** tests/scripts/generate-adapters.bats, which runs against a temp copy and never the real tree. One test per boundary arm:

| Arm | Input | Expected |
|---|---|---|
| correct | today's tree | exit 0; claude-code has 10/10 params plus the claim; the other 5 have 0 params and the neutral sentence |
| suffix typo | `{AGENT_BLOCKING_PARAMM}` in prompt | exit 1, error names the token and the file |
| case variant | `{agent_blocking_param}` / `{Agent_Blocking_Param}` | exit 1 |
| unknown name in namespace | `{AGENT_FOO}` | exit 1 |
| prefix typo | `{AGNT_BLOCKING_PARAM}` (outside the namespace) | generator exit 0 by design; the review-rounds.bats count test FAILS (dispatches 10 vs params 0). Show this. |
| prose prefix typo | `{AGNT_BLOCKING_PROSE}` | a positive test fails: claude-code must contain the scoped claim, and no adapter output may contain a brace token containing `BLOCKING` |
| missing config value | remove the claim or the neutral prose key from adapters.yml | exit 1, error names the key |
| canary | change the neutral prose value in adapters.yml | the canary appears in all 5 non-claude adapters (proves the value is read; the R2 Important) |

### Widened invariant (round 4)

Round 4 (run `20261017T100904Z-8d78023c`) found two more silent-exit-0 bugs in older generator code outside this PR's diff (a broken overlay frontmatter swallowed by `read_overlay()`; a missing prompt counted as a silent "skipped"). Both are the same class this PR closes — the generator exits 0 on output it could not build correctly — so they are fixed here under a widened invariant:

**Invariant (widened):** the generator never exits 0 on output it could not build correctly. Every input it fails to read or parse is an error counted in `stats["errors"]`, never a silent skip.

Applied as: `read_overlay()` raises on unreadable overlay and on invalid YAML frontmatter (error names the overlay file and the YAML error); `read_prompt()` raises on missing or unreadable prompt for a configured command (error names the file) — the former `WARNING: No prompt file` + silent skip at generate_adapter_file is deleted; all generation-time failures (including the round-2 registry violations above) raise `GenerationError`, which `generate_all()` catches per command, counts in `stats["errors"]`, and continues — so a single run reports every broken input — and `main()` exits 1 when any error was counted. There is no intentional-skip path: all 32 configured commands have prompts and no command is an alias (`generate_alias_content` is only reached via `alias: true`, which no command sets). Pinned by two bats tests against temp copies (broken overlay frontmatter → exit 1 + error text; deleted prompt → exit 1 + `6 errors` counted across the 6 adapters). parity.bats:718 still expects `0 skipped, 0 errors` on the real tree.


## Re-plan after round 6 (silent exit 0 found twice: R4, then R6)

R4 found silent exit 0 on a broken overlay and on a missing prompt. R6 found it on an empty prompt. Fixing one input at a time keeps turning up the next one. Close the class at the OUTPUT side, and list the inputs once.

**Invariant:** the generator exits 0 only if EVERY file it writes or would write passes one output check, `validate_generated(rel_path, content)`:
- (a) the command body, after frontmatter or TOML header, is non-empty after strip;
- (b) the description field, where the format has one, is non-empty;
- (c) no `{agent_*}` namespace token remains.

Any failure goes to stats["errors"] with the file and the reason, and the exit is non-zero. The check runs on every adapter and command, including aliases, and in --dry-run mode too (the generator has no --check mode; round-7 correction of this line's earlier "--check" wording).

**Input table** (filled, round 6). One row per read in generate-adapters.py, each with its failure behavior and the test that pins it (tests live in tests/scripts/generate-adapters.bats unless noted):

| Input | Bad state | Behavior | Pinned by |
|---|---|---|---|
| adapters.yml | missing | exit 1, `Error: Config file not found` (pre-existing) | verified during round 6 (probe); load_config guard |
| adapters.yml | unparseable YAML | exit 1, `Error: Invalid YAML` (pre-existing) | verified during round 6 (probe); load_config catches yaml.YAMLError |
| adapters.yml | not a mapping (list/scalar/null); `adapters:`/`commands:` section or entry not a mapping | exit 1 with a named error (round 6; was an AttributeError traceback) | "adapters.yml not a mapping (list / scalar)" + "section not a mapping" |
| adapter key | unknown key | exit 1, names key + valid-key list (R1/R2) | "a typo'd adapters.yml adapter key fails generation" |
| prompts/{cmd}.md | missing / unreadable | GenerationError, names the file (R4) | "missing prompt for a configured command" |
| prompts/{cmd}.md | empty or whitespace-only | GenerationError in read_prompt, names the file (round 6); also output check (a) | "empty prompt" + "whitespace-only prompt" |
| overlay | absent | allowed (optional — returns None) | implicit in every clean-generation test |
| overlay | unreadable / frontmatter YAML error | GenerationError, names the overlay (R4) | "broken overlay frontmatter" |
| overlay | frontmatter not a mapping | GenerationError, names the overlay (round 6) | "overlay frontmatter not a mapping" |
| description | missing/empty for an adapter whose format has one | GenerationError by output check (b) (round 6) | "missing description ..." + validate_generated direct test |
| alias-of | names a missing command | GenerationError, names both commands (round 6) | "alias-of names a missing command" |
| {agent_*} placeholder | unregistered in prompt / left in output | GenerationError (R2) + output check (c) | suffix/case/unknown rows + validate_generated direct test |
| output content | empty body after frontmatter/TOML header | GenerationError by output check (a), on write AND would-write paths | validate_generated direct test + "--dry-run too" test (round-7 rewrite: empty-description mutation caught only by validate_generated, asserting its own error text; proven vacuous-proof by moving the call after the dry-run fork — test FAILS) |
| existing output file (change-detection read) | read error | uncaught OSError aborts the run non-zero (verified round 6 by probe) | verified during round 6 |

**Verified by:** one bats test per row that was not yet pinned, plus one test that feeds `validate_generated` each bad output shape directly, all against temp copies. The real tree still generates with 0 errors and 0 skipped (parity.bats:718).

## Re-plan after round 8 (frontmatter split failed twice: R7, then R8)

R7 found the split matching `---` inside a value. R8 found it missing a `---` line that has trailing spaces or a CRLF ending. Each new regex leaves another shape. The cause is not the regex. It is the FALLBACK: when the split yields fewer than 3 parts, the code treats the whole text as the body, and a non-empty body passes. Remove the fallback, and route both call sites through one parser.

**Invariant:** `split_frontmatter(text, source)` is the ONLY frontmatter splitter, used by both `read_overlay()` and `validate_generated()`. It:
1. normalizes line endings first (`\r\n` and lone `\r` become `\n`);
2. treats a delimiter as a line whose content, after stripping trailing spaces and tabs, is exactly `---`;
3. returns "no frontmatter" only if the first line is not a delimiter;
4. if the first line IS a delimiter and no closing delimiter line follows, raises GenerationError naming `source` ("unterminated frontmatter");
5. never falls back to treating the whole text as the body.

The body is everything after the closing delimiter line.

**Boundary cases** (one bats test per row, temp copies, through BOTH call sites unless noted):

| Arm | Input | Expected |
|---|---|---|
| plain | `---\nk: v\n---\nbody\n` | frontmatter {k: v}, body "body" |
| dash in value | `description: "pre---post"`, whitespace-only body | validate: error, empty body |
| trailing space delimiter | `--- \n` closing, whitespace-only body | validate: error, empty body |
| trailing tab delimiter | `---\t\n` closing | parsed as a delimiter |
| CRLF | the plain case with `\r\n` | same result as plain |
| CRLF + empty body | `\r\n`, whitespace-only body | validate: error |
| unterminated | `---\nk: v\nbody` (no closing) | error, "unterminated frontmatter", names the file |
| no frontmatter | `body only\n` | no frontmatter, body as is (validate: OK if non-empty) |
| `----` (4 dashes) | as the closing line | NOT a delimiter, so it counts as unterminated |

**Verified by:** the table above, plus a grep-style test asserting that `split("---"` and `re.split(` on `---` appear nowhere in generate-adapters.py except inside `split_frontmatter`. The real tree still gives 0 skipped, 0 errors (parity.bats:718).

## Re-route after round 9 (cap: #156 cannot reach two clean rounds)

R9 (run `20261017T132739Z-6ee778ac`) found a third frontmatter-boundary Important: an INDENTED opening `---` is read as "no frontmatter", and the overlay metadata is dropped while generation exits 0. Only round 10 is left under the cap. Merger's review_evidence requires two consecutive clean rounds whatever the cap. #156 cannot ship, so it is re-routed into TWO stacked PRs, each with a fresh round budget. #156 is closed with links once both exist. The split also brings each PR under the ~800-line rule; #156 was at 938 non-generated lines.

**PR A, generator correctness (base: origin/main).** Branch `fix/generator-fail-loud`. Contents:
- GenerationError and the per-command error counting in generate_all / main exit 1;
- read_prompt errors (missing, unreadable, empty or whitespace-only);
- read_overlay errors;
- split_frontmatter;
- validate_generated;
- the input table;
- their tests in tests/scripts/generate-adapters.bats;
- a CHANGELOG entry.

It does NOT contain the AGENT_* placeholders, adapters.yml blocking keys, prompt or adapter changes. Adapters regenerate byte-identical on main, or the PR body explains every diff.

The R9 fix is part of PR A. **Invariant addition:** a line whose content after stripping ALL surrounding spaces and tabs is `---`, but that has leading whitespace, is a near-miss delimiter. `split_frontmatter` raises GenerationError naming the file and line ("indented frontmatter delimiter") wherever it appears in the frontmatter region: as the first line, or as the would-be closing line. It is never silently body text. Boundary rows to add:
- indented opener → error;
- indented closer with a correct opener → error;
- `---` inside a fenced block in the body, after a correct closer → body, unaffected.

**PR B, AC1 blocking dispatch (base: PR A's branch; retarget to main after A merges).** Branch `fix/151-blocking-dispatch-v2`. Contents:
- adapters.yml agent_blocking_param and the prose keys;
- GEN_PLACEHOLDERS, NAMESPACE_RE and its checks;
- `{AGENT_BLOCKING_PARAM}` and prose in prompts/review-agents.md;
- the regenerated adapters;
- tests/commands/review-rounds.bats, including the ADAPTER_FILES set check;
- the placeholder tests;
- this plan file;
- CHANGELOG and the version bump.

Each PR goes through review from round 1 under the stop rule. Suggestions from #156 R1-R9 go into ONE follow-up issue that links #156, A and B.

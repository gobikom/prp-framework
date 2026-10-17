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

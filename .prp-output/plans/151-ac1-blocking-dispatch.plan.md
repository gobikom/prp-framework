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

# Plan: round cap + pass timebox, v2 (prp-framework#151 AC2+AC3; re-route of PR #200)

Author: psak (นุด 2026-10-24 rule: psak writes plans, devs implement). Date: 2026-10-24. Implementer: dev-claude.

## Why a re-route

PR #200 (head 61cd5d479e84462e9df56e88fce93e9e0420e71f, CI green) used all 10 review rounds. Round 10 left one Important: the round-cap guard in Phase 2.0 and Step C's fail-closed guards are behaviour-tested only for `adapters/claude-code/prp-review-agents.md`, not for the other 6 files.

The same family (behaviour asserted only against claude-code) came back in rounds 7, 9 and 10, so per the stop rule the PR is re-planned and re-routed, not patched again. #200 is also +1378 lines, over the ~800 limit.

The product code (scripts and prompt text) in #200 is kept as is. What changes is how it is tested, and the split.

## Root cause (measured by psak 2026-10-24 at 61cd5d47)

- `tests/commands/l2-comments.bats:11` hard-codes `ADAPTER="$ROOT/adapters/claude-code/prp-review-agents.md"`. Every behaviour test (Step A, Step C and Phase 2.0 via `phase20()`) extracts its bash fence from that one file.
- `tests/commands/review-rounds.bats:26` does the same for the FATAL-guard behaviour test (`@test "the pass-deadline-mint FATAL guard actually aborts closed in the claude-code adapter …"`, line 335).
- The other files are covered only by grep-style structure checks, so a guard line deleted from one non-claude-code adapter can pass CI.
- Real-input sample: the sha256 of each extracted fence (Phase 2.0 = `### 2.0 Capture the Reviewed Head`, Step A = `**Step A`, Step C = `**Step C`):

  | file | Phase 2.0 | Step A | Step C |
  |---|---|---|---|
  | prompt + antigravity, claude-code, codex, opencode, thclaws | 3b5b14547c82 | 65d842a76f7a | c614140ca790 |
  | gemini `review-agents.toml`, raw | fb0c35a88b23 | fb5024b60d9e | e66ea79f6f2b |
  | gemini, after `tomllib` decode of its `prompt` key | 3b5b14547c82 | 65d842a76f7a | c614140ca790 |

  So all 7 carry the same code. Gemini's differs only by TOML string escaping.
- CI (`.github/workflows/ci.yml` "Run the bats suites"): `bats -r tests` writes a JUnit report, and every `@test` that a `.bats` file declares must appear in it by name. CI's `python3` is a 3.12 venv, so `tomllib` is available.

## Invariant

Every guarded behaviour is executed, not grepped, against the code extracted from EVERY file in EXPECTED_FILES (the prompt plus the 6 adapters; gemini through a TOML decode). The guarded behaviours are:
- the round cap in Phase 2.0;
- Step C's fail-closed guards;
- the FATAL guard of the pass-deadline mint and its echo line;
- the pass-budget line.

No behaviour test reads a hard-coded adapter path. Deleting one guard line from any single file fails CI.

**Verified by:**
- `tests/commands/l2-adapters-matrix.bats`, which has one literal `@test` per file and runs the behaviour suite with `L2_ADAPTER=<file>`;
- a fence-identity test;
- the mutation proof below.

## Design

1. **`tests/helpers/fence.bash`** (new, about 20 lines). It holds `prompt_text FILE`, which prints the file, or the decoded `prompt` string when FILE ends in `.toml`:
   ```bash
   python3 -I -c 'import sys,tomllib; sys.stdout.write(tomllib.load(open(sys.argv[1],"rb"))["prompt"])' "$1"
   ```
   It also holds `fence FILE HEADING`, the existing awk extractor run over `prompt_text`, with `{NUMBER}` → 7. It fails loudly when the fence is empty.
2. **`tests/commands/l2-comments.bats`**:
   - Set `ADAPTER="$ROOT/${L2_ADAPTER:-adapters/claude-code/prp-review-agents.md}"`.
   - `step()` and `phase20()` call `fence "$ADAPTER" …`.
   - Its first `@test` asserts that the extracted Phase 2.0, Step A and Step C fences are non-empty for `$ADAPTER`, so a wrong path cannot pass vacuously.
   - Move the FATAL-guard behaviour test (review-rounds.bats:335) and the "round-cap guard runs in Phase 2.0 before the reviewed head is saved" test (line 429) into this file, so that the whole behaviour suite lives in one file.
3. **`tests/commands/l2-adapters-matrix.bats`** (new):
   - 7 literal `@test` blocks, one per EXPECTED_FILES entry; no dynamic registration, so the CI JUnit name check sees them. Each runs `run env L2_ADAPTER=<file> bats --tap "$ROOT/tests/commands/l2-comments.bats"`, then asserts:
     - `status -eq 0`;
     - the TAP plan line `1..N` has N equal to the `@test` count of `l2-comments.bats` (counted with `grep -c '^@test'`);
     - no `not ok` line.
   - One `@test` checking that the list of 7 files equals `EXPECTED_FILES` in `review-rounds.bats` (set equality), so adding an adapter without adding a matrix row fails.
   - One `@test`, fence identity: for the Phase 2.0, Step A and Step C fences, and the `PASS_DEADLINE=$(bash "$PRP_DIR/scripts/review/pass-budget.sh" deadline)` fence, the extracted bytes of all 7 files equal the prompt's. On a mismatch it prints which file and which fence differ.
   - First check that a nested `bats` run inside a `bats -r` run works on this host and in CI (clear `BATS_*` variables with `env -u` if needed). If nested bats cannot work, use bats 1.13's `bats_test_function` instead, and say so in the PR body.
4. **`tests/commands/review-rounds.bats`**: keep the structure checks over EXPECTED_FILES, and remove the two moved tests. Keep the pass-budget-line and FATAL-echo grep checks; they stay as cheap pins next to the behaviour.

## Boundary cases (each runs for all 7 files through the matrix)

| guard | case | expected |
|---|---|---|
| round cap (Phase 2.0) | 9 runs on the PR | allowed, head file saved |
| | 10 runs | `ROUND-CAP: refused`, no head file, no agents |
| | paginated JSON with ordinary comments | counted correctly at 9 and at 10 |
| | `body: null` comment | refused, no head file |
| | `gh api` failure | "cannot read the PR comments", refused |
| | unparseable footer (`run=oops`) | refused |
| | malformed run id seen on #200 R10 (`run=20261022T044148Z-312938296`) | refused, never counted as a valid round |
| Step C | bad later body, foreign run id, 2 Critical headings, missing headings, a safe-merge-review line, a second Reviewed head line, moved head, gh failure, no Step A, replay, foreign run file, run file executed, failed post | each one posts nothing (the existing tests, unchanged) |
| FATAL guard | pass-budget script fails; `.prp` is a broken symlink | aborts closed with the FATAL echo |
| pass budget | the agent prompt line | present in all 7 (structure pin) |

The malformed-run-id row is the only new case. Add it only if `round-guard.sh` already refuses it at 61cd5d47. If it does not, STOP and print `[PLAN-ISSUE]`; do not change the guard yourself.

## Mutation proof (required in the PR-B body)

On a scratch copy:
- delete the `round-guard.sh` line from `adapters/codex/prp-review-agents/SKILL.md`;
- separately, delete the same line from `adapters/gemini/review-agents.toml`.

In each case `bats tests/commands/l2-adapters-matrix.bats` must FAIL. Both that file's `@test` and the fence-identity test must fail. Paste the commands and the failing output.

## Stack (each PR stays under ~800 changed lines, plan files excluded)

- **PR-A** `feat/151-round-cap-v2-scripts`, from origin/main, about 570 lines:
  - `scripts/review/round-guard.sh`, `scripts/review/pass-budget.sh` (executable);
  - `tests/scripts/round-guard.bats`, `tests/scripts/pass-budget.bats`, all byte-identical to 61cd5d47;
  - this plan as `.prp-output/plans/151-round-cap-v2.plan.md`.
  - The scripts have no caller yet; say so in the body ("wired in PR-B").
- **PR-B** `feat/151-round-cap-v2-adapters`, based on PR-A's branch, about 600 lines:
  - `prompts/review-agents.md` and the 6 adapters, byte-identical to 61cd5d47;
  - `tests/helpers/fence.bash`, `tests/commands/l2-comments.bats`, `tests/commands/l2-adapters-matrix.bats`, `tests/commands/review-rounds.bats`.
  - Do NOT carry #200's old plan file `.prp-output/plans/151-timebox-round-cap.plan.md`; this plan supersedes it.
  - If pr-risk-tier still counts more than 800 lines, add a `## Size exception` section with the reason.
- In both PR bodies: `Closes`/`Refs #151`, "Supersedes #200", the plan path, and the Invariant plus Verified-by lines.

## Validation

- `bats -r tests` locally, all green.
- In each PR, run `git diff origin/main --stat`, then check the product files are byte-identical to 61cd5d47: `git diff 61cd5d47 -- scripts/review prompts adapters` must be empty in PR-B.
- Push without force and wait for CI. CI must show the 7 matrix tests in its JUnit count.

## Not building

- No change to `round-guard.sh`, `pass-budget.sh` or any prompt or adapter text. If a test shows they are wrong, STOP and print `[PLAN-ISSUE]`.
- No review rounds by dev-claude; psak runs them.
- #200's round-10 Suggestions and follow-up #201: unchanged.

# PR #131 — Review

**PR:** gobikom/prp-framework#131 — test(parity): derive command/adapter counts from adapters.yml (#128)
**Branch:** `fix/128-parity-counts` (base `main` @ 9be9fdd)
**Head reviewed:** `c3f4cdc` (+ follow-up commit applying the one nit)
**Reviewer:** code-reviewer (single-agent — test-only change, `tests/adapters/parity.bats` is the only file)
**Date:** 2026-09-13 (BKK)

## Scope
Hardcoded counts (19 core / 4 marketing / 5 bot / 28 total / 5 adapters / 95 files / 28 gemini files) replaced by helpers reading `adapters.yml`: `yml_eval`, `yml_core_count` (commands without `group`), `yml_group_count`, `yml_cmd_count`, `yml_adapter_count`. Cases 78/79 rewritten as partition consistency (core+marketing+bot == total) and "every adapter named in adapters.yml has a generated directory".

## Findings
| # | Severity | Finding | Resolution |
|---|---|---|---|
| — | verified | derived counts match the real generated tree (23/4/5; 32 per non-CC adapter; 6 adapters all present) | — |
| — | verified | broken/empty `adapters.yml` → empty stdout → `[: integer expression expected` → tests FAIL loudly, never pass vacuously (reproduced in a scratch file) | — |
| — | verified | regressions still caught: missing generated file (file-count vs derived), adapter listed but not generated (`-d` loop), command with unknown group (partition sum falls short) | — |
| 1 | Suggestion (~55, below bar) | `-ge 5` floor is a fresh magic number in a PR removing magic numbers | applied: `-gt 0` with a comment explaining it prevents the loop passing vacuously |

`$1` interpolation into `python3 -c` is fragile in general but every call site passes a literal; not reported.

### Critical Issues (0 found)
None.

### Important Issues (0 found)
None.

### Suggestions (0 open)
None (the one nit was applied).

## Summary
0 critical / 0 high / 0 medium / 0 suggestion.

Remaining red cases 10/11 (review-agents alias wording) are generator↔committed adapter content drift, documented on #128 (issuecomment-5647937793) and out of scope here.

**VERDICT: APPROVE** — `.no-ci` repo: `safe-merge 131 -R gobikom/prp-framework --squash` after merger-bot vouch (NO_CI_MARKER path).

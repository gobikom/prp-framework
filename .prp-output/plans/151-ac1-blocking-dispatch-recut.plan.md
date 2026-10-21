---
status: pending
runner: direct (python3 + bats 1.13.0)
task: Re-cut prp-framework#158 (#151 AC1, blocking Agent dispatch) onto main 82f997d
brief: 20261021-2010-b158
supersedes: "#158 (branch fix/151-blocking-dispatch-v2, head 609e4a67 — do not rebase/merge)"
followup: "#189 stays open, linked from the PR"
---

# Plan: blocking Agent dispatch — one wake per round (#151 AC1, re-cut of #158)

## Invariant

The `{agent_*}` generation-time placeholder namespace is a **CLOSED registry**:
1. A namespace token (regex `{agent_[a-z0-9_]*}`, `re.I`) that is NOT in `GEN_PLACEHOLDERS` dies **before** substitution, naming the token and `prompts/<name>.md`, exit 1.
2. No namespace token survives into any generated output — `validate_generated` check **(c)** on the final content, all modes (write / `--dry-run` / `--diff`), counted error, exit 1.
3. The prose token `{agent}` (no underscore) and runtime placeholders (`{NUMBER}`, `{N}`, `{CONTEXT_PATH}`, `{ARGS}`, `{TOOL}`, …) are OUTSIDE the namespace and generate unchanged.
4. `claude-code` is the ONLY adapter receiving `run_in_background=false` — absence of the `agent_blocking_param` key IS the per-runtime mapping (→ empty string; other runtimes must not receive a kwarg their Agent tool rejects).
5. Both prose values live in adapters.yml (claim = claude-code stanza key, neutral = ONE top-level key); a missing/empty value is a generation error naming the key — no Python fallback.
6. Exactly **2** `except Exception` boundaries remain (main :802, :839); `split_frontmatter(` stays at 3 call sites.

## Boundary table

| Input / state | Behaviour |
|---|---|
| `{AGENT_BLOCKING_PARAM}` in prompt, claude-code | replaced by `"  run_in_background=false,\n"` (10 dispatch blocks get the param line) |
| same token, other 5 adapters | removed (empty string) |
| `{AGENT_BLOCKING_PROSE}`, adapter WITH param (claude-code) | claude-code stanza claim sentence (`agent_blocking_prose_claude`) |
| same token, adapters WITHOUT param | shared top-level neutral sentence (`agent_blocking_prose_other`) |
| Unknown namespace token `{AGENT_FOO}` | pre-substitution error: names token + `prompts/review-agents.md` (or the file), exit 1 |
| Case variant `{agent_blocking_param}` / `{Agent_Blocking_Param}` | same error (regex case-insensitive; registry match is exact) |
| Suffix typo `{AGENT_BLOCKING_PARAMM}` | same error |
| Prefix typo `{AGNT_BLOCKING_PARAM}` / `{AGNT_BLOCKING_PROSE}` | OUTSIDE namespace — generator exit 0, literal ships (by design); the review-rounds bats count test is the safety net and FAILS |
| `{agent}` (no underscore) in prose | unchanged in all 6 adapters |
| Missing `agent_blocking_prose_claude` when prose token present | error naming the key, exit 1 |
| Missing/empty top-level `agent_blocking_prose_other` | error naming the key, exit 1 |
| Namespace token in a config VALUE (self-reference) left in output | validate_generated (c) error, exit 1 |
| #193 fail-loud rows (empty prompt/body/desc, dangling alias-of) | unchanged — regression suite guards |

## Hunk table (AC1: #158's own changes vs main after #161/#190/#193)

### scripts/generate-adapters.py (+101/−13 on #158)

| # | #158 hunk | Verdict vs main | Recut action |
|---|---|---|---|
| P1 | KNOWN_ADAPTER_KEYS += `agent_blocking_param`, `agent_blocking_prose_claude` + comment | **needs-adapted (trivial)** — main :93 comment already reserves them ("join this set in the stacked PR B") | add the 2 keys; shorten comment to main's post-#156 wording |
| P2 | GEN_PLACEHOLDERS + NAMESPACE_RE constants + comment | **port** — nothing on main | add after the GenerationError class / KNOWN_ADAPTER_KEYS block (~:95) |
| P3 | duplicate `class GenerationError` with widened docstring | **NOT-NEEDED** — main has exactly one class (:55); the duplication is a #158-branch editing artifact; main's docstring already states the never-exit-0 invariant | nothing |
| P4 | load_config value-types += 2 str keys | **needs-adapted** — main has `ADAPTER_VALUE_TYPES` (:168, from #190) | add `"agent_blocking_param": str, "agent_blocking_prose_claude": str` to main's dict |
| P5 | `substitute_placeholders` signature + `config` param | **port** — main :411 is `(content, adapter_cfg, cmd_name)` | add `config: dict` 4th param; update the one call site (:~683 in generate_adapter_file) |
| P6 | pre-substitution registry check (NAMESPACE_RE over prompt body) | **port** (main's error wording: `error: unknown generation placeholder '{tok}' in prompts/<file>.md — registered placeholders: [...]`) | verbatim semantics; wording already matches main convention |
| P7 | `{AGENT_BLOCKING_PARAM}` → `adapter_cfg.get(...)` or `""` | **port** | verbatim |
| P8 | `{AGENT_BLOCKING_PROSE}` → prose_key selection (claude stanza vs top-level) + missing-value error | **port** | verbatim semantics, main wording |
| P9 | validate_generated docstring line (c) | **needs-adapted** — main's docstring is the #193 fail-condition form; add `(c) a reserved {agent_*} namespace placeholder token remains in the output.` | keep #193 style |
| P10 | validate_generated check (c) FIRST (before fmt_md) | **port** — covers md AND toml, all modes | verbatim |
| P11 | end-of-`generate_adapter_file` namespace re-check on final content | **NOT-NEEDED (folded)** — on main, `validate_generated` runs in `generate_unit` (:753) on the same final content before the dry-run fork, so check (c) there covers it; #158's separate check was for its own flow | nothing (single check site, main wording) |

### tests/scripts/generate-adapters.bats (+184 on #158)

| # | #158 addition | Verdict vs main | Recut action |
|---|---|---|---|
| B1 | header comment block (round-2 arms) | port | adapted wording (no "PR B of the stack" framing — this is the recut) |
| B2 | 9 new tests (correct-tree 10/10 + claim/neutral; positive claim+no-BLOCKING-token; suffix typo; case variants; unknown {AGENT_FOO}; prefix typo + review-rounds safety-net run; prose prefix typo; missing prose keys ×2; canary top-level read; {agent} unchanged) | **port** — main has make_tree/gen/rc/err/ROOT helpers, none of these tests; error-string assertions match the wording we implement | port all 9; assertion strings checked against main's implemented messages |
| B3 | `expect_fail("ns-token", "codex/prp-x/SKILL.md", …)` row | **port** — main's expect_fail table exists (from #157-row tests, on main after #193) | append the row |

### Other files

| File | Verdict | Recut action |
|---|---|---|
| tests/commands/review-rounds.bats (+156) | **port clean** — main's blob `57200fc` == #158's base (verified), zero conflicts | apply the whole diff: header note, ADAPTER_FILES/OTHER_ADAPTERS lists, `count()` helper, 4 tests (10/10 + pairing, no-kwarg-others, prose-truth + prompt placeholder counts, list set-equality) |
| prompts/review-agents.md (+18/−13) | **port clean** — not in merge-tree conflict set | bullet rewrite (blocking wait from run_in_background=false) + `{AGENT_BLOCKING_PARAM}` prefix on all 10 Agent( blocks + `{AGENT_BLOCKING_PROSE}` in the bullet |
| adapters.yml (+16) | **port clean** | claude-code stanza: `agent_blocking_param`, `agent_blocking_prose_claude`; top-level `agent_blocking_prose_other` before `commands:` — values verbatim |
| six generated adapters | **DO NOT COPY** — regenerate with MAIN's generator | `python3 scripts/generate-adapters.py` after implement: 0 skipped, 0 errors; check mode clean |
| CHANGELOG (+3) | needs-adapted | new entry for this PR on main's CHANGELOG |
| plan | new | this file |

## Real-data check (before/after, main tree)

Before implement (baseline at 82f997d): `python3 scripts/generate-adapters.py --dry-run` → 192 generated / 0 skipped / 0 errors; the six `*review-agents*` outputs contain ZERO `run_in_background` lines (claude-code adapter has 10 `^Agent($` blocks, 0 params).
After implement + regenerate: only the six `*review-agents*` adapter files change; claude-code → 10/10 `run_in_background=false` + scoped claim; other five → neutral sentence, 0 params; `git diff` on all other 186 outputs empty. Run recorded in the PR body.

## Files to change

1. `scripts/generate-adapters.py` — P1, P2, P4, P5, P6, P7, P8, P9, P10 (above)
2. `adapters.yml` — 3 new keys (+comments), values verbatim from #158
3. `prompts/review-agents.md` — bullet rewrite + 10 param prefixes + prose token
4. `tests/commands/review-rounds.bats` — full #158 addition (blob-identical base)
5. `tests/scripts/generate-adapters.bats` — B1, B2, B3
6. `adapters/{antigravity,claude-code,codex,gemini,opencode,thclaws}/…review-agents…` — REGENERATED (never copied)
7. `CHANGELOG.md` — entry
8. this plan

## Tests & mutation check

Every ported/new test FAILS with the fix removed, verified by:
- **stash-mutation on the py file**: `git stash` the generator changes (keep yml/prompt/tests) → run the 9 B2 tests + ns-token row + the 4 review-rounds tests → all must FAIL (unknown placeholder unvalidated, params absent, prose missing) → restore → all pass. Record counts.
- **prefix-typo tree** (B2's own design): generator exit 0 but the review-rounds count test fails — proves the safety net, not the generator, catches prefix typos.

## Validation (exactly as CI)

```
python3 -m py_compile scripts/generate-adapters.py
bats tests/scripts/generate-adapters.bats tests/commands/review-rounds.bats   # file suites
bats -r tests --report-formatter junit -o /tmp/junit-158                      # full suite as CI
python3 scripts/generate-adapters.py            # regenerate: 0 skipped, 0 errors
git diff --stat                                  # only expected files changed
```

PR: title `fix(review-agents): blocking Agent dispatch, one wake per round (#151 AC1, re-cut of #158)`; body carries plan path, Invariant, Verified by, numstat (plan + regenerated adapters called out), "Supersedes #158", "Follow-up #189 carried". #158 NOT closed by us (psak closes it).

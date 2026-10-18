---
status: re-planned rev6 (2026-10-19, psak; approved by devlead-codex); supersedes the 2026-10-17 form (its stop condition fired in rounds 1–2)
runner: python3 -I + bats
issue: gobikom/prp-framework#176 (PR #177)
---

# Plan: review-rounds.py — typed boundary, then decide "invoked" from evidence only

Long form (census, arms A1–A27, precedence, gate categories): https://github.com/gobikom/prp-framework/pull/177#issuecomment-6254540177

## Invariant (#177b)
`invoked` is True or False ONLY when the session has exactly one positively identified
review invocation — a slash `<command-message>/<command-name>/<command-args>` envelope
or an assistant `Skill` tool_use with skill == prp-core:prp-review-agents — and its
value is read ONLY from that invocation's own args. Every other case (malformed
tags, undecidable Skill input, missing args, multiple, none) is a named reason
in `unknown_fields` with mode unknown (malformed > skill > args > multiple > boundary-field > none).

## The split
- **#177 (base, this branch):** keep the #176 typed boundary and the evidence ladder,
read NO invocation at all — `invoked` always None with reason `invocation.not-read`,
no `full-requested`, `fallback_rate` null (markdown: "fallback rate: unavailable —
invocation not read (see #177b)"); `_first_prompt` is deleted. This removes the r1/r2
family (an absent-or-empty first prompt read as definite not-invoked) by construction;
#177 does not satisfy AC0.4 and must not be cited for a rate until #177b.
- **#177b (stacked):** the invocation reader, `full-requested`, `fallback_rate`,
arms A1–A27, mutation (b), the real-data category gate; opened on #177's head,
rebased after #177 merges.

## Base contract
- `classify_mode` returns `(mode, orphan_results, unknown_fields)`; modes are
incremental / fell-back / unknown only; per-session JSON carries `invoked: null` and
`invocation_reason: "invocation.not-read"`; aggregates drop the invocation keys and
set `fallback_rate: null`.
- Source check: the flag token is read nowhere in review-rounds.py.
- Gate: the #176 real-session gate re-run, evidence-mode diff only.

## Acceptance criteria
- Field arms + carried tests green in CI; a bats test covers the null rate and the
unavailable markdown line; every migrated test's before → after is in the PR body.
- Evidence-mode gate: 0 diffs outside the permitted remap (old full-requested and old
first_prompt-unknown sessions take their ladder mode).
- ≤ 840 changed lines per PR (`git diff --numstat origin/main...HEAD`).
- Review stop rule: 2 consecutive `--l2-comments` rounds at 0C/0I at one head; the
family (a definite value from ambiguous/indirect evidence) again → stop, report to psak.

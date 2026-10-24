---
description: "Requirements verification — for each acceptance criterion, find evidence in the PR diff that it was implemented; runs mapped behavioural checks when .prp-verify/feature-map.yaml exists. Produces verify artifact for safe-merge Gate 2."
agent: plan
---
# PRP Verify — Requirements Verification

## Input

PR number and optional criteria: `$ARGUMENTS`

Format: `<pr-number> [--plan <path>] [--issue <N>] [--criteria "..."]`

## Mission

Verify that a PR's code changes actually implement the acceptance criteria. This is not code quality review — it is requirements traceability: for each acceptance criterion, find evidence in the PR diff that it was implemented.

**The Test**: For each acceptance criterion, produce a **PASS/FAIL verdict with evidence** (specific diff lines, files changed, or code patterns). No criterion passes without traceable evidence in the diff.

---

## Phase 0: Parse Input & Gather Criteria

### 0.1 Resolve PR Number

Extract PR number from `$ARGUMENTS`. If not provided:

```bash
gh pr view --json number -q '.number // empty' 2>/dev/null
```

If no PR found: STOP — "No PR number provided and no open PR on current branch."

### 0.2 Gather Acceptance Criteria

Criteria come from ONE of these sources (in priority order):

| Source | How |
|--------|-----|
| `--criteria "..."` | Use directly from argument |
| `--issue <N>` | `gh issue view <N> --json body -q '.body'` — extract criteria from issue body (look for "Acceptance criteria", "AC:", checklist items `- [ ]`) |
| `--plan <path>` | Read plan file — extract "Acceptance Criteria" section |
| PR body | `gh pr view {NUMBER} --json body -q '.body'` — find `Closes #N` or `Fixes #N`, fetch linked issue criteria |
| None extractable | STOP — "No acceptance criteria found. Use --criteria, --issue, or --plan." |

### 0.3 Parse Criteria into Checklist

Convert raw criteria into structured checklist:

```markdown
## Acceptance Criteria Checklist
| # | Criterion | Status |
|---|-----------|--------|
| 1 | {criterion text} | PENDING |
| 2 | {criterion text} | PENDING |
```

**CHECKPOINT**: {N} criteria to verify.

### 0.4 Load Feature Map

Resolve the PR head first — detection reads the commit, never the cwd, and the head object must exist locally before `cat-file -e` can answer:

```bash
PR_HEAD_SHA="$(gh pr view {NUMBER} --json headRefOid -q .headRefOid)"
printf '%s' "$PR_HEAD_SHA" | grep -qE '^[0-9a-f]{40}$' || { echo "STOP: could not read PR head SHA — every AC is UNVERIFIED (no diff fallback)"; exit 1; }
git fetch -q origin "pull/{NUMBER}/head" || { echo "STOP: cannot fetch PR head — every AC is UNVERIFIED (no diff fallback)"; exit 1; }
git cat-file -e "${PR_HEAD_SHA}^{commit}" 2>/dev/null || { echo "STOP: PR head not present after fetch — every AC is UNVERIFIED (no diff fallback)"; exit 1; }
```

Then detect a committed feature map on that head with exit-code discrimination — never `&&/||`: a git error must never read as "no map":

```bash
map_err="$(git cat-file -e "${PR_HEAD_SHA}:.prp-verify/feature-map.yaml" 2>&1 >/dev/null)"; map_rc=$?
```

- `map_rc = 0` → **MAP_PRESENT**.
- `map_rc = 128` and `map_err` mentions `does not exist` or `invalid object name` → **NO_MAP**.
- Anything else (any other git error) → **every AC is UNVERIFIED**, heading `VERIFY INCOMPLETE (feature map detection error)`, escalate. **No diff fallback**.

- **NO_MAP**: no map on the PR head — run `/prp:verify --init` after this verify to create one. Behaviour is unchanged from the past: every AC is judged by diff evidence.
- **MAP_PRESENT**: first confirm the checkout matches the head you just checked — `git rev-parse HEAD` must equal `${PR_HEAD_SHA}` (if it does not, run the map mechanics inside a detached worktree at `${PR_HEAD_SHA}`; a stale checkout judges the wrong tree, and `sync --write` would stamp `synced_sha` to the wrong HEAD). On mismatch: mapped ACs are UNVERIFIED + escalate — never run exercises against a tree that is not the PR head. Then run the mechanics script first — `scripts/prp-verify-map.sh validate .prp-verify/feature-map.yaml` (exit 0 = valid; exit 1 lists every error; exit 3 = tool error).
  - **Invalid map (exit 1): every AC is UNVERIFIED** — stop judging, write the artifact with `criteria_unverified: {N}`, heading `VERIFY INCOMPLETE (invalid feature map)`, and escalate. **No diff fallback** while a map file exists on the head.
  - **Tool error (exit 3): same as invalid** — every AC UNVERIFIED, heading `VERIFY INCOMPLETE (feature map tool error)`, escalate.

---

## Phase 1: Fetch PR Diff

```bash
gh pr diff {NUMBER}
```

Also gather context:

```bash
gh pr view {NUMBER} --json title,body,files,additions,deletions
```

List changed files:

```bash
gh pr diff {NUMBER} --name-only
```

**CHECKPOINT**: Diff fetched. {N} files changed, +{additions}/-{deletions} lines.

---

## Phase 2: Verify Each Criterion

For each criterion in the checklist:

### 2.0 Map Match (only when a map was loaded in 0.4)

Run the mechanics script per AC — `scripts/prp-verify-map.sh match .prp-verify/feature-map.yaml "<criterion text>"` — which prints `live:<id>` and/or `removed:<id>` lines (whole-word keyword hits, case-insensitive).

- **`live:<id>` matched**: check staleness — `scripts/prp-verify-map.sh stale .prp-verify/feature-map.yaml` lists ids whose `paths:` changed since the entry's `synced_sha`.
  - If `<id>` is stale, the entry must be re-proven before it may judge anything: run `scripts/prp-verify-map.sh sync .prp-verify/feature-map.yaml <id> --write`. You may first rewrite that entry's `exercise`/`expect` in the map (keeping `id`, `match`, `paths`), then re-run `sync`. Exit codes: `0` = entry re-proven and written — **unless the output says `all paths deleted at HEAD -> tombstone`** (every entry path is gone at HEAD): then the entry was removed from the map, and the AC is treated exactly like a tombstone — 🔍 UNVERIFIED + escalate citing the new `removed_reason`; never run it, never diff evidence. `1` = FAIL (run or negative proof did not pass — the AC is FAIL with the output); `3` = FAIL with a tool-error note; `4` = UNVERIFIED (environment unavailable); **any other exit (including `2`, usage / unknown id) = 🔍 UNVERIFIED + escalate** — never PASS, never diff evidence. A stale entry is **never skipped**.
  - Then run the exercise: `scripts/prp-verify-map.sh run .prp-verify/feature-map.yaml <id>`. Exit mapping: `0` = ✅ PASS with evidence `map:<id> exit=0 matched=<expect>`; `1` = ❌ FAIL (behaviour — the observed result contradicts the expectation, output quoted); `2` = entry id not found in the map (e.g. tombstoned by the sync above) — 🔍 UNVERIFIED + escalate, never diff evidence; `3` = ❌ FAIL with a tool-error note (never PASS); `4` = 🔍 UNVERIFIED — **never PASS on env-unavailable**; **any other exit = 🔍 UNVERIFIED + escalate** — never PASS, never diff evidence.
  - A mapped AC is **never judged by diff evidence** — its verdict comes only from running the exercise, or else it is UNVERIFIED and escalated.
- **`removed:<id>` only** (tombstone, no live entry): 🔍 UNVERIFIED + escalate, citing the tombstone's `removed_reason`. Never diff evidence.
- **No match at all**: use the existing diff-evidence path below, unchanged, and tag the evidence `diff-evidence`.

### 2.1 Search for Evidence

Search the diff for implementation evidence:

| Criterion Type | Evidence to Look For |
|---------------|---------------------|
| New feature | New function/class/endpoint in diff |
| Bug fix | Removal of buggy code + replacement logic |
| Config/flag | New flag, environment variable, or config key |
| UI change | New component, route, or template |
| Test coverage | New test file or test cases for the feature |
| Documentation | Updated docs, README, or inline comments |

### 2.2 Assign Verdict

| Verdict | Condition |
|---------|-----------|
| ✅ PASS | Evidence found (diff evidence, or `map:<id> exit=0 matched=<expect>` from a run exercise) that criterion is implemented |
| ❌ FAIL | No evidence found, evidence contradicts the criterion, or a mapped exercise ran and failed (exit 1/3) |
| ⚠️ PARTIAL | Partial evidence — criterion may be implemented but incomplete or unclear |
| 🔍 UNVERIFIED | Env required by map entry is unavailable — not a pass. The criterion was never judged |

**Never PASS on env-unavailable**: a 🔍 UNVERIFIED criterion can never be recorded as PASS — the behaviour was not observed.

### 2.3 Record Evidence

For each criterion, record:
- **Verdict**: PASS / FAIL / PARTIAL / UNVERIFIED
- **Evidence**: Specific file:line or diff snippet (tagged `diff-evidence`), or the `map:<id> exit=… matched=…` line from a run exercise
- **Note**: Any caveats or concerns

---

## Phase 3: Generate Artifact

### 3.1 Compile Results

```markdown
## Verify Results

| # | Criterion | Verdict | Evidence |
|---|-----------|---------|----------|
| 1 | {criterion} | ✅ PASS | `src/foo.py:42` — new function `verify_token()` added |
| 2 | {criterion} | ❌ FAIL | No evidence in diff |
| 3 | {criterion} | ⚠️ PARTIAL | `tests/test_foo.py` updated but no E2E coverage |
```

### 3.2 Overall Verdict

| Condition | Verdict |
|-----------|---------|
| All criteria PASS | **VERIFY PASSED** ✅ |
| All PASS or PARTIAL, no FAIL, `criteria_unverified == 0` | **VERIFY PASSED (with gaps)** ⚠️ |
| Any criterion FAIL | **VERIFY FAILED** ❌ |
| Any criterion 🔍 UNVERIFIED | **VERIFY INCOMPLETE (unverified)** — frontmatter `verdict: PARTIAL`; run-all and auto-merge treat it as not verified |

`criteria_unverified > 0` always yields `verdict: PARTIAL` (never PASS), regardless of the other counts.

### 3.3 Save Artifact

Save to `.prp-output/reviews/pr-{NUMBER}-verify.md`:

```markdown
---
pr: {NUMBER}
title: "{PR_TITLE}"
verified_by: "opencode"
verdict: PASS | FAIL | PARTIAL
criteria_total: {N}
criteria_passed: {N}
criteria_failed: {N}
criteria_partial: {N}
criteria_unverified: {N}
map_entries_run: {N}
map_synced: [{ids}]
verified_sha: "{PR_HEAD_SHA}"
date: {ISO_TIMESTAMP}
---

# Verify Report: PR #{NUMBER}

## Summary
- **Verdict**: {verdict}
- **Criteria**: {passed}/{total} passed
- **PR**: {PR_TITLE}
- **Source**: {--issue N / --criteria / --plan path}

## Results

{full results table from Phase 3.1}

## Criteria Details

{For each criterion — full evidence text}

## Environment
- **Diff size**: +{additions}/-{deletions} lines across {N} files
- **Verified at**: {timestamp}
```

### 3.4 Display Summary

```
VERIFY {VERDICT} — {passed}/{total} criteria verified
{list each criterion with verdict icon}

Artifact: .prp-output/reviews/pr-{NUMBER}-verify.md
```

---

## Output

- Artifact: `.prp-output/reviews/pr-{NUMBER}-verify.md`
- Summary: printed to stdout

---

## Init Mode (`--init`)

`/prp:verify <pr> --init` builds `.prp-verify/feature-map.yaml` from scratch (no PR verification runs):

1. Derive candidate entries from what already exists in the repo: test suites, CLI commands, scripts and library entry points (`surface: cli` / `api` / `lib`). Each candidate needs: `id`, `summary`, `match` keywords, product `paths`, `surface`, `env` (default `local`), an `exercise` (a real command that observes the behaviour) and `expect`.
2. A candidate is written only when the mechanics script proves it: `scripts/prp-verify-map.sh sync .prp-verify/feature-map.yaml <id> --write` must exit `0` — that proves both a positive run (exercise met `expect`) and the negative proof (with the product `paths` deleted, `expect` is no longer met). Exit `1` lists the reason (`vacuous: negative proof met expect`, run failure) — the candidate is **not written**; list it in the report with its reason.
3. Commit the new map on the current feature branch only, guarded the same way as the plan artifact commit (never on the default branch).
4. Report: entries written, candidates refused with reasons, and the hint to run `/prp:verify` normally afterwards.

## Sync Mode (`--sync [id]`)

`/prp:verify <pr> --sync` (or `--sync <id>`) re-proves stale entries:

1. Run `scripts/prp-verify-map.sh stale .prp-verify/feature-map.yaml` to list stale ids (paths changed since each entry's `synced_sha`); with `[id]`, only that id.
2. For each: run `scripts/prp-verify-map.sh sync .prp-verify/feature-map.yaml <id> --write`. You may rewrite an entry's `exercise`/`expect` first — at most **one** rewrite attempt per entry — then re-run `sync`. Report each entry's outcome: `synced` (exit 0), `FAIL` (exit 1, output quoted), tool error (exit 3), or UNVERIFIED (exit 4, env unavailable). A stale entry is never silently skipped.

---

## Usage Examples

```
/prp:verify 42
/prp:verify 42 --issue 166
/prp:verify 42 --plan .prp-output/plans/feature.plan.md
/prp:verify 42 --criteria "Gate 2 blocks agent PRs, bypass requires --reason"
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| PR has no linked issue | Extract criteria from PR body or use --criteria |
| Criterion is vague ("works correctly") | Note: "Criterion ambiguous — interpreted as: {interpretation}." Verify best match. |
| Diff too large to inspect fully | Focus on files most relevant to each criterion |
| Test-only changes | Verify test content matches criterion requirements |
| Criterion references external system | Note: "External system verification not possible from diff — marking PARTIAL." |
| No feature map (B1) | Diff evidence as today, plus one line: "No feature map — run /prp:verify --init" |
| Env required by a map entry is unavailable (B4) | 🔍 UNVERIFIED; `criteria_unverified` increments; never PASS |
| Entry stale (B5) | `sync <map> <id> --write` before judging; on exit 1 the AC is FAIL with the output; a stale entry is never skipped |
| Entry tombstoned, `removed:` only (B6) | 🔍 UNVERIFIED + escalate, citing `removed_reason`; never diff evidence |
| Map schema invalid (B8) | Every AC UNVERIFIED (`criteria_unverified = criteria_total`), heading `VERIFY INCOMPLETE (invalid feature map)`; no diff fallback while the map file exists |
| Vacuous exercise refused (B12) | `sync` exit 1 (`vacuous: negative proof met expect`); entry not written; candidate listed as refused |
| Negative proof errors (B13) | exit 3 → FAIL with a tool-error note; never read as "negative proven" |
| Synced_sha not in history (shallow clone) | `stale` exits 3 → that AC is FAIL (tool error), never diff evidence |

---

## Success Criteria

- CRITERIA_PARSED: All acceptance criteria extracted and classified
- DIFF_FETCHED: PR diff retrieved successfully
- VERDICTS_EVIDENCED: Every criterion has PASS/FAIL/PARTIAL with specific evidence
- ARTIFACT_SAVED: Verify report written to `.prp-output/reviews/pr-{NUMBER}-verify.md`
- SUMMARY_REPORTED: User has clear verdict

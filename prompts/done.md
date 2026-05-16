# PRP Done — Issue Closure Gate

## Input

Issue number and options: `{ARGS}`

Format: `<issue-number> [--repo <owner/repo>] [--skip-vera --reason="..."]`

## Mission

Verify that all completion gates have passed before closing a GitHub issue. Prevents premature issue closure when a PR was merged but QA or requirements verification was not completed.

**The Gates** (checked in order):
1. PR merged (linked via `Fixes #N` or `Closes #N` in PR body)
2. Multi-agent review artifact exists (`.prp-output/reviews/pr-{PR}-agents-review*.md`)
3. Verify artifact exists (`.prp-output/reviews/pr-{PR}-verify.md`)
4. Vera QA pass (comment on issue containing "QA PASSED" or "QA PASSED (with warnings)")

---

## Phase 0: Parse Input

### 0.1 Resolve Issue Number

Extract issue number from `{ARGS}`. If not provided: STOP — "Issue number required. Usage: `{TOOL}:done <issue-number>`"

### 0.2 Parse Flags

```
SKIP_VERA = false
SKIP_REASON = ""
REPO = "{from --repo flag}"
```

| Flag | Action |
|------|--------|
| `--repo <owner/repo>` | Set REPO = value |
| `--skip-vera` | Set SKIP_VERA = true |
| `--reason="..."` | Set SKIP_REASON = value |

**Validation**: If `SKIP_VERA = true` AND `SKIP_REASON` is empty → STOP: "--skip-vera requires --reason=\"<why>\""

### 0.3 Resolve Repo

```bash
# Auto-detect if not provided via --repo
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
```

If REPO is still empty: STOP — "Cannot determine repo. Use --repo <owner/repo>."

### 0.4 Fetch Issue

```bash
gh issue view {ISSUE_NUMBER} -R {REPO} --json title,body,state,comments
```

| Result | Action |
|--------|--------|
| state=CLOSED | WARN: "Issue #{N} is already closed." → display gate status below, EXIT 0. |
| state=OPEN | Proceed to Phase 1. |
| Not found | STOP: "Issue #{N} not found in {REPO}." |

---

## Phase 1: Gate Checks

### Gate 1: PR Merged

Find the merged PR linked to this issue:

```bash
# Search for merged PRs mentioning this issue number
gh pr list -R {REPO} --search "closes #{ISSUE_NUMBER}" --state merged --json number,title,mergedAt
gh pr list -R {REPO} --search "fixes #{ISSUE_NUMBER}" --state merged --json number,title,mergedAt
```

If multiple PRs found: use the most recently merged one.

| Result | Gate 1 |
|--------|--------|
| Merged PR found | ✅ PASS — set PR_NUMBER |
| No merged PR | ❌ FAIL — "No merged PR found for issue #{N}. Merge a PR with 'Fixes #{N}' in body first." |

**Set PR_NUMBER** from the found PR for subsequent gates.

### Gate 2: Review Artifact

Check for multi-agent review artifact in cwd:

```bash
ls .prp-output/reviews/pr-${PR_NUMBER}-agents-review*.md 2>/dev/null
```

| Result | Gate 2 |
|--------|--------|
| File found | ✅ PASS |
| No file | ❌ FAIL — "No review artifact for PR #${PR_NUMBER}. Run: {TOOL}:review-agents ${PR_NUMBER}" |

### Gate 3: Verify Artifact

Check for requirements verification artifact in cwd:

```bash
ls .prp-output/reviews/pr-${PR_NUMBER}-verify.md 2>/dev/null
```

| Result | Gate 3 |
|--------|--------|
| File found | ✅ PASS |
| No file | ❌ FAIL — "No verify artifact for PR #${PR_NUMBER}. Run: {TOOL}:verify ${PR_NUMBER} --issue ${ISSUE_NUMBER}" |

### Gate 4: Vera QA

**Skip if** `SKIP_VERA = true` (proceed to 1.5 audit log).

Search issue comments for Vera QA verdict (most recent comment wins):

```bash
gh issue view {ISSUE_NUMBER} -R {REPO} --json comments -q '.comments[].body'
```

Search for QA verdict patterns (case-insensitive):
- Contains `QA PASSED (with warnings)` → PASS
- Contains `QA PASSED` → PASS
- Contains `QA FAILED` → FAIL
- No matching comment → PENDING

| Result | Gate 4 |
|--------|--------|
| "QA PASSED" or "QA PASSED (with warnings)" found (last match) | ✅ PASS |
| "QA FAILED" found (last match) | ❌ FAIL — "Vera QA failed. Fix and re-delegate: {TOOL}:qa --delegate=vera --issue #{N}" |
| No QA comment | ⏳ PENDING — "Vera QA not completed. Delegate: {TOOL}:qa --delegate=vera --issue #{N}" |

### 1.5 Skip-Vera Audit Log

If `SKIP_VERA = true`:

```bash
logger -t prp-done "SKIP_VERA issue=\"${ISSUE_NUMBER}\" pr=\"${PR_NUMBER}\" repo=\"${REPO}\" reason=\"${SKIP_REASON}\"" 2>/dev/null || true
```

Gate 4 status: ⏭️ SKIPPED (audit-logged)

---

## Phase 2: Report & Close

### 2.1 Compile Gate Results

```markdown
## Done Gate Report: Issue #{N}

| Gate | Check | Status | Detail |
|------|-------|--------|--------|
| Gate 1 | PR merged | {✅ PASS / ❌ FAIL} | PR #{PR_NUMBER} merged on {date} |
| Gate 2 | Review artifact | {✅ PASS / ❌ FAIL} | {filename or "not found"} |
| Gate 3 | Verify artifact | {✅ PASS / ❌ FAIL} | {filename or "not found"} |
| Gate 4 | Vera QA | {✅ PASS / ❌ FAIL / ⏳ PENDING / ⏭️ SKIPPED} | {detail} |
```

### 2.2 Evaluate All Gates

| Condition | Action |
|-----------|--------|
| All gates PASS | Close issue → Phase 2.3 |
| Gate 4 SKIPPED + gates 1–3 PASS | Close issue → Phase 2.3 (with skip note) |
| Any gate FAIL | STOP — report failed gates, do NOT close |
| Gate 4 PENDING | STOP — "Vera QA not completed. Cannot close until QA passes or use --skip-vera." |

### 2.3 Close Issue (if all gates pass)

Post summary comment then close:

```bash
gh issue comment {ISSUE_NUMBER} -R {REPO} --body "## All Gates Passed ✅

{gate table from 2.1}

Closing issue — all completion criteria verified.
{If SKIP_VERA: \"\\n⚠️ Gate 4 (Vera QA) skipped — reason: {SKIP_REASON}\"}

Closed by: {TOOL}:done"

gh issue close {ISSUE_NUMBER} -R {REPO}
```

---

## Output

On success:

```
DONE GATE REPORT: Issue #{N}

Gate 1 (PR merged):        ✅ PASS — PR #M merged
Gate 2 (Review artifact):  ✅ PASS — pr-M-agents-review.md found
Gate 3 (Verify artifact):  ✅ PASS — pr-M-verify.md found
Gate 4 (Vera QA):          ✅ PASS — QA PASSED comment found

Issue #{N} CLOSED ✅
```

On failure:

```
DONE GATE REPORT: Issue #{N}

Gate 1 (PR merged):        ✅ PASS — PR #M merged
Gate 2 (Review artifact):  ✅ PASS
Gate 3 (Verify artifact):  ❌ FAIL — no verify artifact found
Gate 4 (Vera QA):          ⏳ PENDING

BLOCKED: 2 gates failed. Issue NOT closed.

To fix:
  {TOOL}:verify M --issue N
  {TOOL}:qa --delegate=vera --issue N
```

---

## Usage Examples

```
{TOOL}:done 166
{TOOL}:done 166 --repo gobikom/agent-devops
{TOOL}:done 166 --skip-vera --reason="no UI changes — API-only fix"
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| Multiple merged PRs for issue | Use most recently merged one |
| PR linked via comment (not body) | Still counts — search all PR references |
| Vera commented FAIL then PASS | Use latest verdict (last matching comment wins) |
| Verify artifact is PARTIAL verdict | Still passes Gate 3 — artifact existence is the gate, not verdict content |
| Issue already closed | WARN and exit 0 — display gate status for reference |
| `--skip-vera` without audit log available | logger fails silently (|| true) — still proceed if reason provided |

---

## Success Criteria

- ISSUE_FOUND: Issue resolved and state checked
- GATE1_CHECKED: Merged PR found or clear failure reported
- GATE2_CHECKED: Review artifact presence verified
- GATE3_CHECKED: Verify artifact presence verified
- GATE4_CHECKED: Vera QA comment searched (or SKIPPED with audit)
- ISSUE_CLOSED: Issue closed when all gates pass
- BYPASS_AUDITED: Any --skip-vera logged to syslog

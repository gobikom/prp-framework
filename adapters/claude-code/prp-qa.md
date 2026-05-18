---
description: "QA verification - test acceptance criteria via Playwright screenshots, API calls, and E2E flows with pass/fail verdicts and visual evidence"
argument-hint: "<url> [--criteria \"...\"] [--issue <N>] [--plan <path>] [--viewports desktop,mobile,tablet] [--api-only] [--skip-a11y] [--skip-screenshots] [--delegate=<agent>]"
---
<process>
# PRP QA — Acceptance Criteria Verification

## Input

Target URL and acceptance criteria: `$ARGUMENTS`

Format: `<url> [--criteria "criteria text"] [--issue <N>] [--plan <path>] [--viewports desktop,mobile,tablet] [--api-only] [--skip-a11y] [--skip-screenshots] [--delegate=<agent>]`

## Mission

Verify that a deployed or running feature **actually works** from the user's perspective. This is not code review — it is behavioral verification against acceptance criteria using real browser interaction, API calls, and visual evidence.

**The Test**: For each acceptance criterion, produce a **PASS/FAIL verdict with evidence** (screenshot, API response, or step-by-step observation). No criterion passes without proof.

---

## Phase 0: Parse Input & Gather Criteria

### 0.0 Delegation Mode Check

**If `--delegate=<agent>` is present in `$ARGUMENTS`**: extract the agent name and enter delegation mode.

Extract delegation target:

```
DELEGATE_AGENT = "{value from --delegate=<agent>}"
```

**Delegation mode** — skip all QA execution phases. Instead:

1. Resolve acceptance criteria source (same as Phase 0.2 below, but stop after identifying the source — do NOT parse into checklist yet).

2. Construct delegation payload:
   ```
   Task: QA verification
   Issue: {ISSUE_NUMBER if --issue provided, else "N/A"}
   Criteria source: {--criteria text | --issue N | --plan path}
   URL: {URL from $ARGUMENTS}
   Flags: {remaining flags excluding --delegate}
   ```

3. Delegate using the tool-specific mechanism:
   - **Claude Code**: Use `/delegate-qa {DELEGATE_AGENT} --issue {ISSUE_NUMBER}` (if --issue provided) or `/ping {DELEGATE_AGENT} QA: {URL} --criteria "..."` for quick checks
   - **Other tools**: Post delegation payload to agent message bus

4. Output:
   ```
   QA delegated to {DELEGATE_AGENT}
   Issue: #{ISSUE_NUMBER}
   Criteria: {source summary}
   Task ID: {task_id if available, else "async — check via /delegate-qa status"}
   ```

5. **STOP** — do NOT execute Phases 1–6. QA runs on the target agent.

---

### 0.1 Determine URL

Extract the target URL from `$ARGUMENTS`. If no URL provided:

```bash
# Try to detect local dev server
curl -s -o /dev/null -w '%{http_code}' http://localhost:3000 && echo "localhost:3000"
curl -s -o /dev/null -w '%{http_code}' http://localhost:5173 && echo "localhost:5173"
curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 && echo "localhost:8080"
```

If no URL found: STOP — "No target URL provided and no local dev server detected. Provide a URL: `/prp-core:prp-qa <url> --criteria '...'`"

### 0.2 Gather Acceptance Criteria

Criteria come from ONE of these sources (in priority order):

| Source | How |
|--------|-----|
| `--criteria "..."` | Use directly from argument |
| `--issue <N>` | `gh issue view <N> --json body -q '.body'` — extract criteria from issue body (look for "Acceptance criteria", "AC:", checklist items `- [ ]`) |
| `--plan <path>` | Read plan file — extract acceptance criteria / success criteria section |
| None provided | STOP — "No acceptance criteria specified. Use --criteria, --issue, or --plan." |

### 0.3 Parse Criteria into Checklist

Convert raw criteria into a structured checklist:

```markdown
## Acceptance Criteria Checklist
| # | Criterion | Type | Status |
|---|-----------|------|--------|
| 1 | {criterion text} | UI/API/E2E/A11Y | PENDING |
| 2 | {criterion text} | UI/API/E2E/A11Y | PENDING |
```

Auto-classify each criterion:
- Contains "endpoint", "API", "response", "status code", "JSON" → **API**
- Contains "click", "fill", "submit", "navigate", "flow", "step" → **E2E**
- Contains "contrast", "keyboard", "screen reader", "WCAG", "aria" → **A11Y**
- Default → **UI** (visual verification)

**CHECKPOINT**: Criteria parsed. {N} criteria to verify ({UI count} UI, {API count} API, {E2E count} E2E, {A11Y count} A11Y).

### 0.4 Initialize Run Directory

Each QA run gets its own isolated directory with an auto-incrementing run number.

**Determine run label** from source:
- `--issue <N>` → label = `issue{N}`
- `--plan <path>` → label = plan filename without extension
- `--criteria` → label = sanitized URL hostname+path (e.g., `localhost-3000-workflows`)
- fallback → `adhoc`

```bash
# Auto-increment run number
LABEL="{label}"
LAST_RUN=$(ls -d .prp-output/qa/run-*-* 2>/dev/null | sort -t- -k2 -n | tail -1 | grep -oP 'run-\K\d+' || echo "0")
NEXT_RUN=$(printf "%03d" $((LAST_RUN + 1)))
RUN_DIR=".prp-output/qa/run-${NEXT_RUN}-${LABEL}"
mkdir -p "${RUN_DIR}/screenshots"
echo "QA Run: ${RUN_DIR}"
```

All output for this run goes under `{RUN_DIR}`:
- Report: `{RUN_DIR}/qa-report.md`
- Screenshots: `{RUN_DIR}/screenshots/*.png`

**CHECKPOINT**: Run directory initialized: `{RUN_DIR}`

---

## Phase 1: Environment Check

### 1.1 Verify Target is Reachable

```bash
HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "{URL}")
echo "Target: {URL} → HTTP $HTTP_STATUS"
```

| Status | Action |
|--------|--------|
| 200-399 | PROCEED |
| 401/403 | WARN: "Auth required — screenshots may show login page. Provide credentials or ensure test user is configured." |
| 404 | STOP: "Target URL returns 404. Verify the page exists and the server is running." |
| 5xx | STOP: "Server error ({status}). Fix the server before running QA." |
| Connection refused | STOP: "Cannot reach {URL}. Ensure the dev server is running." |

### 1.2 Detect Playwright Availability

```bash
which playwright >/dev/null 2>&1 && echo "PLAYWRIGHT_AVAILABLE" || echo "PLAYWRIGHT_MISSING"
```

| Result | Action |
|--------|--------|
| AVAILABLE | Use Playwright for screenshots and interaction |
| MISSING | Fall back to curl + manual description. WARN: "Playwright not installed — visual verification limited. Install: `npm i -g playwright && playwright install chromium`" |

### 1.3 Determine Viewports

Default viewports (override with `--viewports`):

| Name | Size | When |
|------|------|------|
| desktop | 1280x720 | Always |
| mobile | 375x812 | Always (unless `--skip-mobile`) |
| tablet | 768x1024 | Only if explicitly requested |

**CHECKPOINT**: Environment verified. Target reachable. Playwright: {available/missing}. Viewports: {list}.

---

## Phase 2: Screenshot Capture (Visual Baseline)

**Skip if** `--api-only` or `--skip-screenshots` flag provided.

### 2.1 Capture Screenshots

For each viewport, capture the target page:

```bash
# Desktop
playwright screenshot --browser chromium \
  --viewport-size=1280,720 \
  --wait-for-timeout 3000 \
  "{URL}" "{RUN_DIR}/screenshots/desktop.png"

# Mobile
playwright screenshot --browser chromium \
  --viewport-size=375,812 \
  --wait-for-timeout 3000 \
  "{URL}" "{RUN_DIR}/screenshots/mobile.png"
```

### 2.2 Visual Analysis (Vision)

Read each screenshot using the Read tool (multimodal). For each screenshot, analyze:

- **Layout**: Elements positioned correctly? No overlaps, cutoffs, or overflow?
- **Content**: Expected text, images, data visible? No placeholder or error content?
- **Responsive**: Mobile layout adapted properly? No horizontal scroll? Touch targets adequate?
- **State**: Correct default state shown? (e.g., empty state, loaded data, active filters)

Record observations per viewport — these feed into criterion verdicts in Phase 5.

**CHECKPOINT**: {N} screenshots captured and analyzed. Observations recorded.

---

## Phase 3: API Contract Testing

**Run for criteria classified as API.** Also run proactively if the page loads data from API endpoints.

### 3.1 Discover Endpoints

If endpoints not explicit in criteria:
- Check the page source / network patterns for API calls
- Read source code for API routes if available
- Ask: what data does this page need?

### 3.2 Test Each Endpoint

For each API endpoint:

```bash
# Status code + response time
curl -s -o /tmp/qa-response.json -w 'HTTP %{http_code} in %{time_total}s' "{ENDPOINT}"

# Validate JSON structure
python3 -c "
import json, sys
with open('/tmp/qa-response.json') as f:
    data = json.load(f)
    print(f'Type: {type(data).__name__}')
    if isinstance(data, list):
        print(f'Items: {len(data)}')
        if data:
            print(f'First item keys: {list(data[0].keys()) if isinstance(data[0], dict) else \"primitive\"}')
    elif isinstance(data, dict):
        print(f'Keys: {list(data.keys())}')
" 2>&1
```

### 3.3 API Verdict Per Criterion

For each API criterion, record:

| Check | Expected | Actual | Verdict |
|-------|----------|--------|---------|
| Status code | 200 | {actual} | PASS/FAIL |
| Response type | array/object | {actual} | PASS/FAIL |
| Required fields | {fields} | {present?} | PASS/FAIL |
| Response time | <{threshold}s | {actual}s | PASS/WARN |

**CHECKPOINT**: API tests complete. {pass}/{total} passed.

---

## Phase 4: E2E Flow Testing

**Run for criteria classified as E2E.** Requires Playwright.

### 4.1 Plan the Flow

For each E2E criterion, decompose into steps:

```markdown
Flow: {criterion description}
1. Navigate to {URL}
2. {action} — click/fill/select/wait
3. {action}
4. Verify: {expected outcome}
```

### 4.2 Execute Flow

If Playwright is available, use it for interaction:

```bash
# Example: screenshot after interaction
playwright screenshot --browser chromium \
  --viewport-size=1280,720 \
  --wait-for-timeout 5000 \
  "{URL_AFTER_INTERACTION}" "{RUN_DIR}/screenshots/e2e-{flow-name}.png"
```

If Playwright is NOT available for interactions (no codegen/script support):
1. Describe the expected flow step by step
2. Use curl to test any form submissions or API calls the flow triggers
3. Note: "Manual verification needed for UI interactions — Playwright interaction not available."

### 4.3 E2E Verdict

For each E2E flow step:

| Step | Action | Expected | Actual | Verdict |
|------|--------|----------|--------|---------|
| 1 | Navigate | Page loads | {observed} | PASS/FAIL |
| 2 | Click filter | Dropdown opens | {observed} | PASS/FAIL |
| 3 | Verify result | Shows filtered data | {observed} | PASS/FAIL |

**CHECKPOINT**: E2E flows complete. {pass}/{total} steps passed.

---

## Phase 5: Accessibility Check

**Skip if** `--skip-a11y` flag provided.

Run basic WCAG 2.1 checks on captured screenshots and page structure:

### 5.1 Visual Checks (from Screenshots)

- **Color contrast**: Text readable against background? (4.5:1 normal, 3:1 large)
- **Touch targets**: Interactive elements large enough? (minimum 44x44px on mobile)
- **Focus indicators**: Visible focus rings on interactive elements?
- **Text sizing**: Readable without zoom on mobile viewport?

### 5.2 Structural Checks (from Source/curl)

```bash
# Fetch page source for structural analysis
curl -s "{URL}" | python3 -c "
import sys
html = sys.stdin.read()
checks = {
    'img_without_alt': html.count('<img') - html.count('alt='),
    'input_without_label': 0,  # simplified
    'aria_landmarks': html.count('role=') + html.count('aria-'),
    'headings': html.count('<h1') + html.count('<h2') + html.count('<h3'),
    'lang_attr': 'lang=' in html[:500],
}
for k, v in checks.items():
    print(f'{k}: {v}')
"
```

### 5.3 A11Y Verdict

| Check | Status | Detail |
|-------|--------|--------|
| Color contrast | PASS/WARN/FAIL | {detail} |
| Alt text | PASS/FAIL | {N} images without alt |
| Keyboard nav | PASS/FAIL/UNTESTED | {detail} |
| ARIA usage | PASS/WARN | {detail} |
| Heading structure | PASS/WARN | {detail} |

**CHECKPOINT**: Accessibility check complete.

---

## Phase 6: Verdict & Report

### 6.1 Compile Results

For each acceptance criterion, combine evidence from all phases:

```markdown
## QA Results

| # | Criterion | Type | Verdict | Evidence |
|---|-----------|------|---------|----------|
| 1 | {criterion} | UI | PASS ✅ | Desktop screenshot shows correct layout |
| 2 | {criterion} | API | FAIL ❌ | Returns 500 instead of 200 |
| 3 | {criterion} | E2E | PASS ✅ | Flow completes — see e2e-filter.png |
| 4 | {criterion} | A11Y | WARN ⚠️ | 2 images missing alt text |
```

### 6.2 Overall Verdict

| Condition | Verdict |
|-----------|---------|
| All criteria PASS | **QA PASSED** ✅ |
| All criteria PASS but A11Y warnings | **QA PASSED (with warnings)** ⚠️ |
| Any criterion FAIL | **QA FAILED** ❌ |

### 6.3 Bug Reports (If FAIL)

For each failed criterion, generate a structured bug report:

```markdown
### Bug: {short description}

**Criterion**: #{N} — {criterion text}
**Severity**: Critical / High / Medium / Low
**Steps to reproduce**:
1. Navigate to {URL}
2. {step}
3. {step}

**Expected**: {what should happen}
**Actual**: {what actually happens}
**Evidence**: `{RUN_DIR}/screenshots/{filename}.png`
**Viewport**: {desktop/mobile/both}
```

### 6.4 Issue Creation (On Failure)

> **🛑 SHELL SAFETY:** Multiline `--body` with backticks/code blocks **MUST** use `--body-file`. Inline `--body "$(cat <<EOF)"` executes backticks as bash subshells → hangs on stdin → 600s timeout. Pattern fix from incident `at-3db127abdf91`.

If verdict is QA FAILED and there is a source issue (`--issue`):

```bash
# Comment on the source issue with QA results
cat > /tmp/qa-comment-${RUN_ID}.md << 'EOF'
## QA Results — FAILED ❌

{summary table}

{bug details}

Tested by: /prp-core:prp-qa
EOF
gh issue comment {ISSUE_NUMBER} --body-file /tmp/qa-comment-${RUN_ID}.md
```

If no source issue, suggest creating one:
```bash
QA found {N} failures. Create a tracking issue?
cat > /tmp/qa-issue-${RUN_ID}.md << 'EOF'
{bug reports}
EOF
gh issue create --title "QA: {summary}" --body-file /tmp/qa-issue-${RUN_ID}.md
```

---

## Output

### Save QA Report

Save report to `{RUN_DIR}/qa-report.md`:

```markdown
---
url: "{URL}"
tested: {ISO_TIMESTAMP}
run: "{RUN_DIR}"
verdict: {QA PASSED / QA FAILED}
criteria_total: {N}
criteria_passed: {N}
criteria_failed: {N}
viewports: [desktop, mobile]
---

# QA Report: {URL}

## Summary
- **Verdict**: {verdict}
- **Criteria**: {passed}/{total} passed
- **Viewports tested**: {list}
- **Source**: {--issue N / --criteria / --plan path}

## Results
{full results table from Phase 6.1}

## Screenshots
{list of screenshots with viewport labels}

## Bug Reports
{from Phase 6.3, if any}

## Accessibility
{from Phase 5.3}

## Environment
- **Playwright**: {available/missing}
- **Browser**: Chromium
- **Tested at**: {timestamp}
```

### Display Summary

```
QA {VERDICT} — {passed}/{total} criteria passed
{list each criterion with verdict icon}

Report: {RUN_DIR}/qa-report.md
Screenshots: {RUN_DIR}/screenshots/
```

---

## Usage Examples

```
/prp-core:prp-qa http://localhost:3000/workflows --criteria "Filters work, mobile layout has no horizontal scroll, status badges show correct colors"
/prp-core:prp-qa http://localhost:3000/tasks --issue 422
/prp-core:prp-qa https://dashboard.goko.digital --plan .prp-output/plans/dashboard-plan.md
/prp-core:prp-qa http://localhost:8080/api/tasks --api-only --criteria "Returns JSON array, status 200, items have id+title+status fields"
/prp-core:prp-qa http://localhost:3000 --viewports desktop,mobile,tablet --criteria "Responsive layout, no overflow on mobile"
```

---

## Edge Cases

| Situation | Action |
|-----------|--------|
| URL requires authentication | WARN and test what's accessible. Note "auth required" in report. |
| Playwright not installed | Fall back to curl + vision analysis of any available screenshots. WARN in report. |
| Page loads slowly (>10s) | Increase wait-for-timeout to 10000ms. WARN: "Slow page load — {time}s" |
| No acceptance criteria extractable from issue | STOP — "Could not extract acceptance criteria from issue #{N}. Add a checklist or 'Acceptance criteria' section." |
| Screenshot capture fails | Log error, continue with other checks. Note "screenshot unavailable" for affected criteria. |
| API endpoint returns non-JSON | Record raw response type. Adapt validation accordingly. |
| E2E flow requires multi-page navigation | Chain screenshots at each step. Name: `{RUN_DIR}/screenshots/e2e-{flow}-step{N}.png` |
| Criterion is ambiguous | WARN: "Criterion #{N} is ambiguous — interpreted as: {interpretation}. Verify this matches intent." |
| `--api-only` with UI criteria | Skip UI/E2E criteria. WARN: "API-only mode — {N} UI/E2E criteria skipped." |
| All criteria pass but page looks broken | Flag as **observation** (not a criterion failure): "Visual anomaly detected — {description}. Not in acceptance criteria but worth investigating." |

---

## Success Criteria

- CRITERIA_PARSED: All acceptance criteria extracted and classified
- TARGET_REACHABLE: URL returns 2xx/3xx
- SCREENSHOTS_CAPTURED: Desktop + mobile screenshots taken (unless --skip-screenshots)
- VISUAL_ANALYZED: Each screenshot analyzed via vision for layout/content/responsive issues
- API_TESTED: All API criteria verified with actual HTTP calls
- E2E_EXECUTED: E2E flows attempted with step-by-step evidence
- A11Y_CHECKED: Basic WCAG checks performed (unless --skip-a11y)
- VERDICTS_EVIDENCED: Every criterion has PASS/FAIL with specific evidence
- RUN_ISOLATED: Each run gets unique directory with auto-increment number (run-NNN-{label})
- REPORT_SAVED: QA report written to {RUN_DIR}/qa-report.md
- BUGS_DOCUMENTED: Failed criteria have structured bug reports with reproduction steps

</process>

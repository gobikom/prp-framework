---
description: Deep root cause analysis - finds the actual cause, not just symptoms
---

# PRP Debug — Root Cause Analysis

Target: $ARGUMENTS

Format: `<issue|error|stacktrace> [--quick]`

## Mission

Find the **actual root cause** — the specific code, config, or logic that, if changed, would prevent this issue. Not symptoms. Not intermediate failures. The origin.

**The Test**: "If I changed THIS, would the issue be prevented?" If the answer is "maybe" or "partially", keep digging.

## Step 1: CLASSIFY — Parse Input

Determine input type:

| Type | Action |
|------|--------|
| Raw symptom (vague description, stack trace) | INVESTIGATE — form hypotheses, test them |
| Pre-diagnosed (identifies location/problem) | VALIDATE — confirm diagnosis, check related issues |

Determine mode:
- `--quick` → Surface scan (2-3 Whys)
- No flag → Deep analysis (full 5 Whys, git history required)

Parse input: extract error type/message/call chain from stack trace, or identify system/error code from message. **Restate the symptom in one sentence.**

## Step 2: HYPOTHESIZE — Form Theories

Generate 2-4 hypotheses:

| Hypothesis | What must be true | Evidence needed | Likelihood |
|------------|-------------------|-----------------|------------|
| {H1} | {conditions} | {proof needed} | HIGH/MED/LOW |
| {H2} | {conditions} | {proof needed} | HIGH/MED/LOW |

Rank by likelihood. Start with most probable.

## Step 3: INVESTIGATE — The 5 Whys

Execute for leading hypothesis:

```
WHY 1: Why does [symptom] occur?
> Because [cause A]
> Evidence: [code reference, log, or test]

WHY 2: Why does [cause A] happen?
> Because [cause B]
> Evidence: [proof]

... continue to WHY 5 (or 2-3 for --quick) ...

WHY 5: ROOT CAUSE
> Evidence: [exact file:line reference]
```

### Evidence Standards (STRICT)

| Valid Evidence | Invalid Evidence |
|----------------|------------------|
| `file.ts:123` with actual code snippet | "likely includes...", "probably because..." |
| Command output you actually ran | Logical deduction without code proof |
| Test you executed that proves behavior | Explaining how technology works in general |

**Rules**: Stop when you hit changeable code. Every "because" MUST have evidence. If evidence refutes hypothesis, pivot. Dead end = backtrack.

### Investigation Techniques

- **Code issues**: grep for error messages/function names, read full context, check git blame, run with edge case inputs
- **Runtime issues**: check env/config differences, initialization order, race conditions
- **"It worked before"**: `git log --oneline -20`, `git diff HEAD~10 [files]`

## Step 4: VALIDATE — Confirm Root Cause

### Three Tests

| Test | Question | Required |
|------|----------|----------|
| Causation | Does root cause logically lead to symptom via evidence chain? | YES |
| Necessity | Would symptom still occur without root cause? | NO |
| Sufficiency | Is root cause alone enough, or co-factors? | Document if co-factors |

If any test fails, root cause is incomplete — go deeper or broader.

### Git History (Deep Mode Required)

```bash
git log --oneline -10 -- [affected files]
git blame [affected file] | grep -A2 -B2 [line number]
```

Document: when introduced, what commit/PR, recent changes or stable.

### Rule Out Alternatives (Deep Mode)

| Hypothesis | Why Ruled Out |
|------------|---------------|
| {H2} | {evidence that disproved it} |

## Step 5: REPORT — Generate RCA

```bash
mkdir -p .prp-output/debug
TIMESTAMP=$(date +%Y%m%d-%H%M)
```

**Path**: `.prp-output/debug/rca-{issue-slug}-{TIMESTAMP}.md`

Report includes: issue summary, root cause one-liner, severity, confidence, evidence chain (5 Whys with code references), git history (introduced/author/type), fix specification (what to change, current vs required code, files to modify), verification steps.

## Step 6: OUTPUT — Report to User

Display: issue, root cause, confidence, report path, 2-3 sentence summary, fix description, next steps (review report, implement fix, verify).

## Critical Reminders

1. **Symptoms lie.** Error message = what failed, not why.
2. **First explanation often wrong.** Don't stop early.
3. **No evidence = no claim.** "Likely", "probably", "may" are forbidden.
4. **Test, don't just read.** Execution proves behavior.
5. **Git history is mandatory** in deep mode.
6. **The fix should be obvious.** Correct root cause = self-evident fix.

## Usage

```
/prp-debug "TypeError: Cannot read property 'id' of undefined"
/prp-debug "Login fails after password reset" --quick
/prp-debug "Build passes locally but fails in CI"
```

## Success Criteria

- ROOT_CAUSE_FOUND: Specific file:line identified
- EVIDENCE_CHAIN_COMPLETE: Every step has proof
- FIX_ACTIONABLE: Someone could implement from the report
- VERIFICATION_CLEAR: How to confirm fix works

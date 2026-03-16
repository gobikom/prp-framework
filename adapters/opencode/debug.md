---
description: Root cause analysis using 5-Whys with strict evidence standards
agent: plan
---

# PRP Debug — Root Cause Analysis

Issue: $ARGUMENTS

## Mission

Find the **actual root cause** — the specific code, config, or logic that, if changed, would prevent this issue. Not symptoms. Not intermediate failures. The origin.

**The Test**: "If I changed THIS, would the issue be prevented?" If the answer is "maybe" or "partially", keep digging.

## Steps

1. **Classify Input**:
   - Raw symptom (vague description, error, stack trace) → INVESTIGATE: form hypotheses
   - Pre-diagnosed (identifies location/problem) → VALIDATE: confirm diagnosis
   - `--quick` flag → surface scan (2-3 Whys). No flag → deep analysis (full 5 Whys, git history required).
   - Restate the symptom in one sentence.

2. **Hypothesize**: Generate 2-4 hypotheses with likelihood (HIGH/MED/LOW), conditions that must be true, and evidence needed. Rank and select leading hypothesis.

3. **Investigate — The 5 Whys**:
   ```
   WHY 1: Why does [symptom] occur?
   → Because [cause A] → Evidence: [code ref, log, or test proof]
   WHY 2: Why does [cause A] happen?
   → Because [cause B] → Evidence: [proof]
   ... continue to WHY 5 (or 2-3 for --quick) ...
   → ROOT CAUSE → Evidence: [exact file:line reference]
   ```

   **Evidence Standards (STRICT)**:

   | Valid Evidence | Invalid Evidence |
   |----------------|------------------|
   | `file.ts:123` with actual code snippet | "likely...", "probably because..." |
   | Command output you actually ran | Logical deduction without code proof |
   | Test you executed proving behavior | General technology explanations |

   **Rules**: Stop when you hit changeable code. Every "because" MUST have evidence. If evidence refutes hypothesis → pivot to next. Dead end → backtrack.

   **Techniques**: Search error messages/function names. Read full context. `git blame` for when/why. Run suspicious code with edge inputs. Check env/config, init order, race conditions. For "it worked before": `git log --oneline -20` + `git diff HEAD~10`.

4. **Validate Root Cause** — three tests:

   | Test | Question | Required |
   |------|----------|----------|
   | Causation | Root cause logically leads to symptom through evidence chain? | Yes |
   | Necessity | Without root cause, symptom still occurs? | Must be No |
   | Sufficiency | Root cause alone is enough, or co-factors exist? | Document co-factors |

   If any test fails → root cause is incomplete, go deeper.

   **Git History (deep mode required)**:
   ```bash
   git log --oneline -10 -- [affected files]
   git blame [affected file] | grep -A2 -B2 [line number]
   ```
   Document: when introduced, what commit/PR, recent changes, type (regression/original/long-standing).

   **Rule out alternatives**: For each rejected hypothesis, document evidence that disproved it.

5. **Generate Report**: Save to `.prp-output/debug/rca-{issue-slug}-{TIMESTAMP}.md` with:
   - Header: issue, root cause, severity, confidence
   - Evidence Chain (WHY chain with file:line refs)
   - Git History (introduced, author, type)
   - Fix Specification: what to change, implementation guidance (current vs fixed code), files to modify, verification steps

6. **Output to User**: Issue, root cause, confidence, report path, 2-3 sentence summary, fix description, next steps (review report, implement fix, run verification).

## Critical Reminders

1. **Symptoms lie.** Error message says what failed, not why.
2. **First explanation is often wrong.** Don't stop early.
3. **No evidence = no claim.** "Likely", "probably", "may" are not allowed.
4. **Test, don't just read.** Execution proves behavior; reading proves intent.
5. **Git history is mandatory** in deep mode.
6. **The fix should be obvious.** If root cause is correct, the fix writes itself.

## Usage

```
/prp:debug "Login returns 500 after password reset"
/prp:debug --quick "TypeError: Cannot read property 'id' of undefined"
/prp:debug "Stack trace: ..."
```

## Success Criteria

- ROOT_CAUSE_FOUND: Specific file:line identified
- EVIDENCE_CHAIN_COMPLETE: Every step has proof
- FIX_ACTIONABLE: Someone could implement from the report
- VERIFICATION_CLEAR: How to confirm fix works

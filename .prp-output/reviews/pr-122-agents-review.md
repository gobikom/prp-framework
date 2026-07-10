---
pr: 122
title: "fix(review-agents): commit artifacts before marker; docs-only head re-bind (#121)"
author: "gobikom"
reviewed: 2026-07-10T16:05:00+07:00
verdict: READY TO MERGE
agents: [code-reviewer, security-reviewer, silent-failure-hunter]
rounds: 2
---

## PR Review Summary (Multi-Agent — converged after fix loop)

Round 1 (3 core agents, head b77c435): 1 critical / 0 important / 2 medium → NEEDS FIXES.
Fix round (37e05486e): all 3 fixed, 0 skipped. Round 2 re-verify: behavioral test matrix green.

### Critical Issues (0 found)

None remaining. Resolved: the docs-only guard failed OPEN when REVIEWED_HEAD_SHA was empty (`git diff ""..HEAD` silently prints nothing) or unresolvable (exit 128 swallowed by the pipeline) — both empirically confirmed by two independent agents. Now both SHAs are validated as 40-hex before any diff (and at Phase-1.3 capture), and git diff's output + exit code are captured separately: any git error = FATAL, no re-bind.

### Important Issues (0 found)

None. (Security Medium resolved: rename detection let `git mv src/x .prp-output/y` show only the destination, silently dropping a reviewed file from the merged tree — `--no-renames` now lists both paths so the deletion FATALs. Docs Medium resolved: emit-block regex documented as format backstop only.)

### Re-verify evidence (round 2, behavioral matrix on a sandbox repo)
| Case | Result |
|------|--------|
| same head | binds reviewed SHA |
| docs-only advance | REBIND ✓ |
| empty REVIEWED_HEAD_SHA | FATAL (was the critical fail-open) |
| unresolvable SHA | FATAL-DIFF(128) (was silent) |
| rename into .prp-output/ | FATAL-DRIFT (was the security bypass) |
| real code drift | FATAL-DRIFT |

### Validation Results
| Check | Status | Details |
|-------|--------|---------|
| generate-adapters | PASS | 6 generated, 0 errors, idempotent re-run |
| bash -n (guard snippet) | PASS | clean |
| parity.bats | 91 ok / 8 not ok | the 8 are PRE-EXISTING on main (stale 19/28 count expectations vs current 22/32; identical set verified on origin/main) — follow-up candidate, untouched here |

### Strengths
- Ordering fix verified consistent file-wide: no section instructs a commit after marker emission; field rules ↔ guard ↔ emit block all reference MARKER_HEAD with no stale REVIEWED_HEAD_SHA in the printf path.
- Security posture delta vs baseline: none remaining — .prp-output/ carries no executable effect for safe-merge; marker↔body count coupling unchanged; injection direction was always caught, deletion direction now caught via --no-renames.

### Verdict
READY TO MERGE

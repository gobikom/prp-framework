# Re-plan: PR #166 review-cost.py — after round 2 (psak, 2026-10-18)

Why a re-plan: two finding families have now come up in two rounds each (review stop rule: same family in 2 rounds → stop patching, re-plan with the invariant and a boundary test per arm).
- Family A, token-field validation. R1: null and negative values accepted. R2: the fix uses `usage.get(k)`, which cannot tell a missing key from a JSON null, so a usage object missing any token field is now rejected.
- Family B, filesystem errors swallowed. R1 and R2 Critical: `os.path.isdir` + `glob.glob` on an unreadable `subagents/` dir returns `[]`, so real subagent tokens vanish with exit 0. R2 Important: `isdir`/`isfile`/`glob` on top-level paths turn permission errors into "not a directory" / "no *.jsonl".
  (psak's R1 brief listed only family A; family B was in R1 and was not briefed. That is psak's miss, not the fixer's.)

Real input sample (psak, 60 most recent ~/.claude/projects/*/*.jsonl files): 9,860 usage objects, all with all 4 TOKEN_FIELDS (0 missing). Earlier sample: timestamp str 37,285 / absent 17,877; 0 null tokens; 0 negative.

## Invariant A (line shape)
Every field read after `_validate_line` is shape-checked inside it. Per token field k in TOKEN_FIELDS, decided by `k in usage`, never `usage.get(k)`:

| arm | input | result |
|---|---|---|
| A1 | key absent | accepted, counts as 0 |
| A2 | `null` | rejected |
| A3 | `true` / `false` | rejected |
| A4 | string / float / list / object | rejected |
| A5 | int < 0 | rejected |
| A6 | int ≥ 0 | accepted |

timestamp: absent or str (as now). message / usage: absent, null or object (as now).

## Invariant B (filesystem)
Every filesystem access whose result changes the totals tells "does not exist" apart from every other OSError:
- "does not exist" (FileNotFoundError, or a `subagents/` dir that is simply absent) → normal, contributes nothing.
- any other OSError (PermissionError, NotADirectoryError on a path that should be a dir, EIO, ...) → that session (or that CLI path) FAILS: named on stderr with the real errno text, exit != 0, never reported as complete.
- No `os.path.isdir`, `os.path.isfile` or `glob.glob` on a path that matters. Use `os.scandir` / `os.stat` inside try/except, and catch FileNotFoundError separately from OSError.
- Covers: the subagents dir (review-cost.py ~145-146), the project-dir scan (~154), and the CLI path checks in main() (~212, ~216).

| arm | case | result |
|---|---|---|
| B1 | session with no `subagents/` dir | reported complete, 0 subagents |
| B2 | `subagents/` exists, empty | reported complete, 0 subagents |
| B3 | `subagents/` exists, unreadable (chmod 000) | session FAILS, stderr names the dir and "Permission denied", exit != 0 |
| B4 | CLI arg path does not exist | error "not found: <p>", exit != 0 |
| B5 | CLI arg under an unreadable ancestor | error names "Permission denied", not "not a directory", exit != 0 |
| B6 | project dir unreadable | error names "Permission denied", not "no *.jsonl", exit != 0 |
| B7 | a good sibling session next to a B3 session | still reported with full totals |

Tests that use chmod must skip when run as root (root ignores mode bits) and must restore modes in teardown.

## Out of scope (Suggestions → ONE follow-up issue after the stop rule)
Malformed-subagent ValueError discarding main totals; empty-file warning; dropped rejection reason strings; the R2 code-reviewer and security-reviewer Suggestions.

# Plan: generator fail-loud — never exit 0 on input or output it cannot build

Status: re-routed 2026-10-17 from prp-framework#156 (review cap) as PR A of a
two-PR stack, per the "Re-route after round 9" section of the #151 AC1 plan
(`/home/goko/tmp/151-ac1-blocking-dispatch.plan.md`; psak's decision). Base:
origin/main. PR B (blocking Agent dispatch, #151 AC1) stacks on this branch.

## Problem (from #156 rounds 4, 6, 7, 8, 9)

Review of the AC1 work kept finding the same class in the generator: it exits
0 on input it could not read or parse, or on output that does not pass
inspection. R4: a broken overlay frontmatter swallowed by `read_overlay()`
and a missing prompt counted as a silent "skipped". R6: an empty prompt. R7:
`split("---", 2)` matched `---` inside a value. R8: a `---` closing line with
trailing spaces or CRLF missed by the inline regex — both lived in the
whole-text-as-body FALLBACK. R9: an INDENTED opening `---` read as "no
frontmatter", dropping the overlay metadata while generation exited 0.

## Invariants

**R4 widened invariant.** The generator never exits 0 on output it could not
build correctly. Every input it fails to read or parse is an error counted in
`stats["errors"]`, never a silent skip.

**R6 output-side invariant.** The generator exits 0 only if EVERY file it
writes or would write passes one output check, `validate_generated(rel_path,
content)`:
- (a) the command body, after frontmatter or TOML header, is non-empty after
  strip;
- (b) the description field, where the format has one, is non-empty.

(Check (c), the `{agent_*}` namespace scan, joins in the stacked PR B, which
introduces that namespace.)

**R8 parser invariant.** `split_frontmatter(text, source)` is the ONLY
frontmatter splitter, used by both `read_overlay()` and `validate_generated()`.
It: (1) normalizes line endings first (`\r\n` and lone `\r` become `\n`);
(2) treats a delimiter as a line whose content, after stripping trailing
spaces and tabs, is exactly `---`; (3) returns "no frontmatter" only if the
first line is not a delimiter; (4) if the first line IS a delimiter and no
closing delimiter line follows, raises GenerationError naming `source`
("unterminated frontmatter"); (5) never falls back to treating the whole text
as the body. The body is everything after the closing delimiter line.

**R9 invariant addition (this PR's new fix).** A line whose content after
stripping ALL surrounding spaces and tabs is `---`, but that has leading
whitespace, is a near-miss delimiter. `split_frontmatter` raises
GenerationError naming the file and line ("indented frontmatter delimiter")
wherever it appears in the frontmatter region: as the first line, or as the
would-be closing line. It is never silently body text. After a valid closer,
body content (including an indented `---` inside a fenced block) is never
inspected.

## Input table (round 6, filled)

One row per read in generate-adapters.py, each with its failure behavior and
the test that pins it (tests live in tests/scripts/generate-adapters.bats):

| Input | Bad state | Behavior | Pinned by |
|---|---|---|---|
| adapters.yml | missing | exit 1, `Error: Config file not found` (pre-existing) | load_config guard |
| adapters.yml | unparseable YAML | exit 1, `Error: Invalid YAML` (pre-existing) | load_config catches yaml.YAMLError |
| adapters.yml | not a mapping (list/scalar/null); `adapters:`/`commands:` section or entry not a mapping | exit 1 with a named error (round 6; was an AttributeError traceback) | "adapters.yml not a mapping (list / scalar)" + "section not a mapping" |
| adapter key | unknown key | exit 1, names key + valid-key list | "a typo'd adapters.yml adapter key fails generation" |
| prompts/{cmd}.md | missing / unreadable | GenerationError, names the file (R4) | "missing prompt for a configured command" |
| prompts/{cmd}.md | empty or whitespace-only | GenerationError in read_prompt, names the file (round 6); also output check (a) | "empty prompt" + "whitespace-only prompt" |
| overlay | absent | allowed (optional — returns None) | implicit in every clean-generation test |
| overlay | unreadable / frontmatter YAML error | GenerationError, names the overlay (R4) | "broken overlay frontmatter" |
| overlay | frontmatter not a mapping | GenerationError, names the overlay (round 6) | "overlay frontmatter not a mapping" |
| overlay | indented `---` delimiter (opener or closer) | GenerationError, names the file and line (R9, this PR) | "round-9 indented opener" + "round-9 indented closer" |
| description | missing/empty for an adapter whose format has one | GenerationError by output check (b) (round 6) | "missing description ..." + validate_generated direct test |
| alias-of | names a missing command | GenerationError, names both commands (round 6) | "alias-of names a missing command" |
| output content | empty body after frontmatter/TOML header | GenerationError by output check (a), on write AND would-write paths | validate_generated direct test + "--dry-run too" test |
| existing output file (change-detection read) | read error | uncaught OSError aborts the run non-zero | verified during round 6 (probe) |

## Boundary table (round 8 + round 9)

One bats test per row, temp copies, through BOTH call sites where noted:

| Arm | Input | Expected |
|---|---|---|
| plain | `---\nk: v\n---\nbody\n` | frontmatter {k: v}, body "body" |
| dash in value | `description: "pre---post"`, whitespace-only body | validate: error, empty body |
| trailing space delimiter | `--- ` closing, whitespace-only body | validate: error, empty body |
| trailing tab delimiter | `---\t` closing | parsed as a delimiter |
| CRLF | the plain case with `\r\n` | same result as plain |
| CRLF + empty body | `\r\n`, whitespace-only body | validate: error |
| unterminated | `---\nk: v\nbody` (no closing) | error, "unterminated frontmatter", names the file |
| no frontmatter | `body only\n` | no frontmatter, body as is (validate: OK if non-empty) |
| `----` (4 dashes) | as the closing line | NOT a delimiter, so it counts as unterminated |
| indented opener (R9) | `  ---\nk: v\n---\nbody` | error, "indented frontmatter delimiter", names file + line 1 |
| indented closer (R9) | `---\nk: v\n    ---\nbody` | error, names file + the closer's line |
| fenced `---` in body (R9) | `---\nk: v\n---\n```sh\n  ---\n```\nmore` | body, unaffected (exit 0; overlay applies) |

## Verified by

1. `tests/scripts/generate-adapters.bats` — 27 tests, all against temp copies
   of the tree (never the real adapters/): the clean-tree control, the
   known-key typo arm, the round-4/6 input-table arms, the round-7 dash-in-value
   and overlay arms, the round-8 boundary rows above, and the three round-9
   rows. The round-8 grep test additionally asserts `split("---"` and
   `re.split(` on `---` appear nowhere in generate-adapters.py except inside
   `split_frontmatter`, defined once, called from exactly the two call sites.
2. The real tree still generates `0 skipped, 0 errors` with byte-identical
   adapters (parity.bats — `Results: 0 generated, 192 unchanged, 0 skipped,
   0 errors`).

## Out of scope (deferred to the stacked PR B / follow-up issue)

- The `{agent_*}` generation-time placeholder namespace, GEN_PLACEHOLDERS,
  NAMESPACE_RE and their checks (they arrive with the placeholders themselves
  in PR B).
- adapters.yml `agent_blocking_*` keys and the prompt/adapter changes of
  #151 AC1.
- Suggestions from #156 rounds 1-9 (one follow-up issue links #156, A and B).

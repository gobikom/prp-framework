# Plan A1: load-time config validation, utf-8 pin, display paths (#157 split 1/2)

Full plan: /home/goko/tmp/151-ac1-blocking-dispatch.plan.md (sections
"Re-plan after PR A (#157) round 3"). Per-input named errors and the
structural no-traceback guarantee are PR #157 (split 2/2), based on this
branch.

## Invariant

**Invariant (A1):** every input `load_config` reads — the adapters.yml bytes,
its mapping structure, its key names and its key values — is validated at
load time with a named, fatal error before any generation work starts; every
file read or write in the generator passes `encoding="utf-8"`; every
user-facing path in a message comes from one `display_path(p)` helper that
never raises; and frontmatter is parsed by ONE splitter, `split_frontmatter`,
whose delimiter rule is exact — a line that is `---` after stripping
trailing spaces/tabs (leading whitespace is a near-miss error), line endings
normalized first, no whole-text-as-body fallback, an opener without a closer
is an "unterminated frontmatter" error naming the source, and an indented
delimiter anywhere in the frontmatter region is an "indented frontmatter
delimiter" error naming the file and line. No config or frontmatter input
can reach generation code as an unvalidated value, and none can crash the
run with a raw Python traceback.

## Boundary table (A1)

| Case | Expected |
|---|---|
| adapters.yml missing | `Error: Config file not found`, exit 1 |
| adapters.yml invalid YAML | `Error: Invalid YAML`, exit 1 |
| adapters.yml invalid UTF-8 bytes (`\xff\xfe`) | `Error: Cannot read … 'utf-8' codec can't decode`, exit 1, no Traceback (also under `LC_ALL=C`) |
| adapters.yml not a mapping (list/scalar/null) | `Error: adapters.yml must be a mapping, got <type>`, exit 1 |
| `adapters:`/`commands:` section or entry not a mapping | named section error, exit 1 |
| adapter/command name `/etc/passwd`, `../x`, uppercase, spaces, empty | `Error: invalid adapter/command name … must match ^[a-z0-9][a-z0-9-]*$`, exit 1 |
| unknown adapter key (typo) | named error + valid-key list, exit 1 |
| `args_placeholder: null` (any documented key, wrong type) | `key 'args_placeholder' must be str, got NoneType`, exit 1 |
| `description: 123` | `key 'description' must be dict, got int`, exit 1 |
| frontmatter: plain `---\nk: v\n---\nbody` | frontmatter parsed, body preserved |
| frontmatter: `---` inside a value (`"pre---post"`) | value intact — only exact `---` lines split |
| frontmatter: trailing-space / trailing-tab closer | still a delimiter |
| frontmatter: CRLF endings | same result as LF |
| frontmatter: opener with no closer | GenerationError "unterminated frontmatter", names the source |
| frontmatter: `----` (4 dashes) closer | NOT a delimiter → unterminated |
| frontmatter: indented `---` opener or closer | GenerationError "indented frontmatter delimiter", names file + line |
| frontmatter: no frontmatter | body as is |
| malformed overlay YAML (valid --- block) | WARNING names the file, meta absent, generation continues (A1 lenient-but-visible; hard-error policy is #157's) |
| indented/unterminated overlay frontmatter | the named parse error printed as WARNING before the fallback, metadata ignored |
| existing output with invalid UTF-8 | named error, counted, others generated, file never overwritten |
| mkdir blocked by a regular file | named error naming the directory, counted |
| command key with bad frontmatter.fields | load-time type error naming the COMMAND (`command '<name>'`) |
| valid tree | byte-identical adapters, `0 skipped, 0 errors` (parity.bats:718) |

**Verified by:** 28 tests in `tests/scripts/generate-adapters.bats` (temp
copies only): the 11 config/encoding tests, the 13 round-8/9 frontmatter
boundary rows (direct arms; the overlay/validate arms run in #157 where
those callers live), and the structural grep tests (one splitter; no stray
`split("---"`; `relative_to(ROOT_DIR)` only in `display_path`/
`validate_output_path`; every read/write carries `encoding=`).

## Re-plan after PR A1 (#161) round 3

**Invariant:** every filesystem read in `scripts/generate-adapters.py` goes through ONE helper, `read_utf8`; any read or decode error is a named, counted error (never a traceback, never a silent exit 0); a malformed overlay is a counted error with no lenient fallback; an unknown command key is a named error.

Full section (real inputs, design, boundary table, size budget): `/home/goko/tmp/151-ac1-blocking-dispatch.plan.md`, section "Re-plan after PR A1 (#161) round 3".

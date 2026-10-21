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

R3 (run ae97e40b at 9bc2f06) found 2 Critical / 3 Important; R1 raised the same
family (read_overlay error path, unguarded fs reads). Two rounds in one family
means the per-site patching stops here: this section replaces it with ONE
choke point and a test that makes a second read site impossible.

**Invariant:** every filesystem READ in `scripts/generate-adapters.py` goes
through ONE helper, `read_utf8(path)`. Any `OSError` or `UnicodeDecodeError`
becomes a `GenerationError` naming the file (`display_path`) and the exception
type. The per-command loop in `generate_all` catches `GenerationError` around
`generate_adapter_file`, prints it, increments `stats["errors"]` and continues
(exit 1 at the end); `load_config` treats it as fatal (exit 1). A read or
decode error is never a traceback and never a silent exit 0. A malformed
overlay (parse error from `split_frontmatter`, invalid overlay YAML, or an
unknown/unterminated frontmatter region) is a counted error for that
command, with NO lenient fallback: raw frontmatter text never reaches output.
An unknown command key in adapters.yml is a named, fatal load-time error.

### Real inputs sampled (2026-10-21, worktree at 9bc2f06)

- `adapters.yml` command keys in use (32 commands): `description` 32,
  `argument-hint` 32, `codex-short-description` 32, `opencode-agent` 32,
  `group` 9, `description-overrides` 4. `alias` / `alias-of` are read by the
  generator (`generate_adapter_file`, `generate_alias_content`) but no command
  uses them today.
- `KNOWN_COMMAND_KEYS` = those six + `alias`, `alias-of`. Source of truth for
  the "read by generator" half: `cmd_cfg.get(...)` sites at
  `generate-adapters.py:404,405,428,434,444,463,569,653`.
- `prompts/overlays/` has one real overlay, `claude-code/plan.md`: a `---`
  block with `#` comment lines, `command:`, `adapter:`, `skip_before:`, then
  `# objective` style section headings. Prompts: 33 files in `prompts/`.

### Design

1. `read_utf8(path) -> str` (new, next to `GenerationError`): the only place
   `read_text(` / `open(` may appear. `read_prompt`, `read_overlay`,
   `load_config`, and the existing-output compare in `generate_all` call it.
2. `read_overlay`: `GenerationError` from `split_frontmatter` or a
   `yaml.YAMLError` is re-raised as `GenerationError` (names the file) instead
   of returning `None` / falling back; the caller's loop counts it. The
   overlay with no frontmatter at all stays valid (sections only).
3. `generate_all` wraps `generate_adapter_file(...)` in
   `try/except GenerationError` -> print, `stats["errors"] += 1`, continue.
4. `KNOWN_COMMAND_KEYS` + unknown-key check in `load_config`, mirroring the
   adapter check (`sorted(unknown)` + list of valid keys, exit 1).
5. Revert the whitespace-only hunk (no formatting-only changes in this PR).

### Boundary table (one bats test per row, temp copies only)

| Input | Expected |
|---|---|
| prompt file missing | named error, counted, exit 1, other commands still generated |
| prompt unreadable (`chmod 000`; skip if root) | named error naming file, counted, no Traceback |
| prompt invalid UTF-8 (`\xff\xfe`) | named error, counted, no Traceback |
| prompt empty file | existing behaviour kept: WARNING + skipped, not an error |
| overlay malformed frontmatter (bad YAML in `---` block) | counted error naming the overlay; no output file from it; no raw frontmatter in any output |
| overlay `---` with no closing `---` | counted error ("unterminated frontmatter"), no lenient fallback |
| overlay unreadable / invalid UTF-8 | counted named error |
| unknown command key (`argumnt-hint`) | `Error: Command '<n>' has unknown keys: [...]`, valid-key list, exit 1 |
| valid tree | byte-identical adapters, `0 skipped, 0 errors` (parity.bats) |

Plus the grep invariant test (already drafted in the working tree): fails if
`read_text(` or `open(` appears in `generate-adapters.py` outside `read_utf8`'s
body, and if `read_utf8` is not defined exactly once.

### Size budget

HEAD is +721/-21 against origin/main (includes plan 58, bats 421); the
working-tree partial adds ~+45/-24. Target <= 800 counted lines
(`git diff --numstat origin/main...HEAD`): helper ~12, overlay/loop edits ~20,
KNOWN_COMMAND_KEYS ~10, 8 bats rows ~80. If it exceeds 800, stop and report
BLOCKED with the count; do not trim tests.

**Verified by:** the nine rows above in `tests/scripts/generate-adapters.bats`
plus the grep invariant; full suite run as `.github/workflows/ci.yml` runs it
(`bats -r tests`).

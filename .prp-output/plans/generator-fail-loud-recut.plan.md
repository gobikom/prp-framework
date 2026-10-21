---
status: pending
runner: direct (python3 + bats 1.13.0)
mode: standard
plan: generator-fail-loud-recut
created: 2026-10-21T15:55:00+07:00
brief: 20261021-1540-e157 (psak) — re-cut of #157 from origin/main cf00150
---

# Plan: fail loud on empty prompt, dangling alias-of, empty output (re-cut of #157)

## Summary

Port the three behaviour rows that main (cf00150) lacks from #157: (1) `validate_generated` output checks (a) empty command body and (b) empty description, running on the write path AND the `--dry-run`/`--diff` would-write path; (2) a dangling `alias-of` becomes one named, counted error (exit 1, no ghost output); (3) an empty or whitespace-only prompt for a configured command becomes a named, counted error instead of `WARNING` + skip. Message wording stays main's style; #157's exact strings are adopted only where the message is new. No new `except Exception` — main's two boundaries stay exactly two.

**Invariant:** No input or output the generator builds can silently degrade the run: an empty/whitespace-only prompt, an `alias-of` naming a command that does not exist, or a would-be-written output with an empty command body or empty description each become one named, counted, per-unit error; the run continues, exits 1 when errors > 0, and no traceback escapes. The valid tree still generates `0 skipped, 0 errors`.

## User Story

As a PRP framework maintainer, I want the adapter generator to fail loudly on degraded inputs and outputs, so that a typo'd alias or an emptied prompt file is caught at generation time with rc 1 instead of silently shipping a stub adapter command.

## Problem / Solution

**Problem (verified at cf00150, evidence /home/goko/tmp/157-gap.md):**
- Empty prompt → `WARNING: No prompt file for {cmd}`, unit "skipped", rc 0 (`generate-adapters.py:633-636`); whitespace-only prompt → generated silently, rc 0 (probe P3: `192 generated, 0 errors`).
- `alias-of: no-such-cmd` → rc 0, ghost stub output written (probe P5).
- No output validation at all: an empty description or empty body in a would-write file passes rc 0 (probe P6; `validate_generated` does not exist — `AttributeError` in direct-import probes).

**Solution:** Three surgical changes in `scripts/generate-adapters.py` + ported/adapted tests from `origin/fix/generator-fail-loud:tests/scripts/generate-adapters.bats`.

## Metadata

| Field | Value |
|---|---|
| Type | ENHANCEMENT (fail-loud policy, re-cut of #157) |
| Complexity | MEDIUM — single-file policy change + test port, no API/DB/UI |
| Systems | prp-framework generator (`scripts/generate-adapters.py`), bats suite |
| Dependencies | none (base: origin/main cf0015059a5f1542d175c6e69a0263ccc111589a) |
| Tasks | 6 |
| Runner | direct |
| Type check | `python3 -m py_compile scripts/generate-adapters.py` |
| Lint | N/A — repo configures no linter for scripts/ (verified: no ruff/flake8 config, no lint CI step) |
| Test (file) | `bats tests/scripts/generate-adapters.bats` |
| Test (full, as CI) | `out=$(mktemp -d); bats -r tests --report-formatter junit -o "$out"` then sum counts across `<testsuite>` elements of `$out/report.xml` (root is `<testsuites>`) |
| Build | N/A — pure script repo |

## Real-data check (brief-mandated, นุด 2026-10-11 rule)

Command run 2026-10-21 (python3 + PyYAML over `git show <ref>:adapters.yml`):

- `origin/main:adapters.yml` — `frontmatter` keys present ONLY under adapters: `adapters.claude-code, adapters.codex, adapters.opencode, adapters.antigravity, adapters.thclaws`. **No command has a `frontmatter` key.**
- `origin/fix/151-blocking-dispatch-v2:adapters.yml` (#158's branch) — identical result.

→ Command-level `frontmatter.fields` support is **not built** (see NOT Building). The generator's real workload: 6 adapters × 32 commands = 192 units, all with non-empty descriptions (verified: full suite at #190 ran 661 tests green and the real tree regenerates `0 generated, 192 unchanged, 0 skipped, 0 errors`).

## Mandatory Reading

- P0 `scripts/generate-adapters.py` — `generate_adapter_file` :618-674 (read-prompt WARNING branch :633-636, alias branch :630-631), `generate_unit` :677-721 (dry-run fork :704), `generate_all` :724-755 (per-unit boundary :746-753), `split_frontmatter` :261+, `display_path` :42, `GenerationError` :55.
- P0 `tests/scripts/generate-adapters.bats` — helpers :12-25 (`make_tree`, `gen`), the test being rewritten :254 ("A1-r3 row: prompt empty — WARNING and skipped, not an error"), grep invariant :494-496 (`except Exception` == 2), style of neighbouring row tests :247-:291.
- P1 `origin/fix/generator-fail-loud:tests/scripts/generate-adapters.bats` — tests at lines 356, 364, 378, 392, 405, 445, 490, 508, 555, 588, 600 (the porting source; NOT applied verbatim — wording adapted).
- P1 `CHANGELOG.md` head — entry format (one line per change).

## Patterns to Mirror

**Per-unit GenerationError (counted, named, continue)** — SOURCE: codebase `scripts/generate-adapters.py:746-753`:
```python
try:
    stats[generate_unit(adapter_name, cmd_name, config, ctx,
                        dry_run, show_diff)] += 1
except Exception as e:  # boundary 1 of 2 (see grep invariant test)
    if isinstance(e, GenerationError):
        print(f"  {e}", file=sys.stderr)
    else:
        print(f"  error: {adapter_name}/{cmd_name} "
              f"({ctx['path']}): {type(e).__name__}: {e}", file=sys.stderr)
    stats["errors"] += 1
```
GenerationError messages carry their own `error:` prefix and a repo-relative path; the boundary prints `  {e}` verbatim.

**Path traversal raise (an in-function policy raise)** — SOURCE: codebase `generate-adapters.py:700-702`:
```python
if not validate_output_path(out_path, adapter_dir):
    raise GenerationError(
        f"error: Path traversal detected: {display_path(out_path)}")
```

**validate_generated reference implementation** — SOURCE: `origin/fix/generator-fail-loud` (script :599-645, reviewed through #157 round 9): see Task 3 (ported verbatim except docstring reference to "stacked PR B", which does not exist here).

**Test row style** — SOURCE: codebase `tests/scripts/generate-adapters.bats:247-253`:
```bash
@test "A1-r3 row: prompt file missing — counted named error, others generated" {
  make_tree
  rm "$TREE/prompts/qa.md"
  gen
  [ "$rc" -eq 1 ] || { echo "expected exit 1, got $rc" >&2; return 1; }
  echo "$err" | grep -qF "..." || { echo "error does not name the input: $err" >&2; return 1; }
  echo "$out" | grep -qE 'Results: .*6 errors' || ...
}
```

## Files to Change

| File | Action | Insert At | Justification |
|---|---|---|---|
| `scripts/generate-adapters.py` | UPDATE | `generate_adapter_file` alias branch :630-631 and prompt branch :633-636; new `validate_generated` def after `validate_output_path` (:605-616); one call line in `generate_unit` after :686 | The three policy rows |
| `tests/scripts/generate-adapters.bats` | UPDATE | rewrite :254 test; append 10 new tests after the A1b block (~:452) | Port #157's tests, adapted wording |
| `CHANGELOG.md` | UPDATE | head, 1 line | repo convention |

## Integration Points

1. `generate_unit` calls `validate_generated(rel_path, content)` AFTER the `if not content: return "skipped"` branch (:685-686) and BEFORE the dry-run fork (:704) — one call site covers write, dry-run and diff paths (identical content at that point). It becomes the third `split_frontmatter(` call site (def :261 + read_overlay + validate_generated = 3 — pinned by ported structural test).
2. Empty-prompt raise replaces the WARNING branch :634-636 → unit no longer returns `"skipped"`; `ctx["path"]` is already set (:683) so the boundary names the prompt.
3. Dangling-alias raise goes before `generate_alias_content` (:630-631) in `generate_adapter_file`, which has `config` in scope — `generate_alias_content` (no config param) is untouched.
4. `generate_all` boundary :746 needs NO change (GenerationError already printed + counted). **No new try/except anywhere** — grep invariant :494-496 (`except Exception` == 2) must stay green.

## NOT Building

- **Command-level `frontmatter.fields`** (test 24 / #157 :330-343): real-data check above shows NO command uses a command-level `frontmatter` key on main or #158's branch; main deliberately rejects it as an unknown command key (`KNOWN_COMMAND_KEYS`, test :225). Building unused config surface contradicts the re-cut's "only the behaviour main lacks" scope.
- **Message-text harmonisation** (gap-analysis section B): main's wording for read errors, mkdir, per-command unexpected errors and the internal boundary stays untouched — out of scope by brief.
- **New `except Exception`**: none. Two boundaries stay.
- **#158 / #157's old branch (`fix/generator-fail-loud`)**: untouched. psak closes #157.
- **Check (c) `{agent_*}` namespace token** (mentioned in #157's docstring): that namespace does not exist on main.

## Step-by-Step Tasks

### Task 1 — dangling alias-of → counted error
- ACTION: UPDATE `scripts/generate-adapters.py` :630-631.
- IMPLEMENT:
```python
    if is_alias:
        alias_of = cmd_cfg.get("alias-of", "")
        if alias_of not in config["commands"]:
            raise GenerationError(
                f"error: command '{cmd_name}' is an alias of '{alias_of}', "
                f"which is not a configured command")
        body = generate_alias_content(cmd_name, cmd_cfg, adapter_name)
```
- MIRROR: path-traversal raise pattern :700-702.
- GOTCHA: `alias-of` type is load-validated str (#190), so `.get("alias-of", "")` is always str; missing key on an alias command → `""` not in commands → error (correct: alias with NO alias-of also caught — matches row intent).
- VALIDATE: `bats tests/scripts/generate-adapters.bats --filter 'alias-of'` (new test) → pass; existing `A1b command value types` test unaffected.

### Task 2 — empty / whitespace-only prompt → counted error
- ACTION: UPDATE `:633-636`; REWRITE bats test `:254`.
- IMPLEMENT:
```python
    else:
        body = read_prompt(cmd_name)
        if not body.strip():
            raise GenerationError(
                f"error: prompt for command '{cmd_name}' is empty or "
                f"whitespace-only: {display_path(PROMPTS_DIR / f'{cmd_name}.md')}")
```
- MIRROR: GenerationError with `error:` prefix + display_path (:700-702).
- GOTCHA: `read_prompt` still returns "" only for an empty file (missing file raises inside `read_utf8` → counted "Cannot read" error — existing behaviour, untouched). The old `return rel_path, ""` skip path becomes unreachable for non-aliases; keep `if not content: return "skipped"` in generate_unit unchanged (defensive, aliases never empty).
- VALIDATE: `bats tests/scripts/generate-adapters.bats --filter 'prompt empty'` → new test passes; `--filter 'real-tree control'` still 0 skipped / 0 errors.

### Task 3 — validate_generated + call site
- ACTION: ADD `validate_generated` after `validate_output_path` (:616); ADD call in `generate_unit` after :686.
- IMPLEMENT: port verbatim from `origin/fix/generator-fail-loud` script :599-645 (docstring: drop the "stacked PR B" sentence, keep (a)/(b)):
```python
def validate_generated(rel_path: str, content: str) -> None:
    """Output check: the generator exits 0 only if EVERY file it writes or
    would write passes. Runs on every adapter and command — aliases included
    — and in --dry-run/--diff modes too (called before the dry-run fork, so
    it sees identical content). Raises GenerationError naming the file and
    the reason:
      (a) the command body, after frontmatter or TOML header, is non-empty
          after strip;
      (b) the description field, where the format has one, is non-empty.
    """
    where = f"generated output {rel_path}"

    fmt_md = not rel_path.endswith(".toml")

    if fmt_md:
        desc, body = split_frontmatter(content, rel_path)
        desc = desc or ""
        if not body.strip():
            raise GenerationError(
                f"error: {where} has an empty command body after frontmatter")
        if desc:
            m = re.search(r"^description:\s*(.*)$", desc, re.MULTILINE)
            if m and not m.group(1).strip().strip('"').strip():
                raise GenerationError(
                    f"error: {where} has an empty description field")
    else:
        m = re.search(r'^description\s*=\s*"(.*)"', content, re.MULTILINE)
        desc = m.group(1) if m else ""
        if not desc.strip():
            raise GenerationError(
                f"error: {where} has an empty description field")
        m = re.search(r'prompt\s*=\s*"""(.*?)"""', content, re.DOTALL)
        body = m.group(1) if m else ""
        if not body.strip():
            raise GenerationError(
                f"error: {where} has an empty command body after TOML header")
```
Call in `generate_unit`, right after the `if not content` branch:
```python
    validate_generated(rel_path, content)
```
- MIRROR: `split_frontmatter(text, source)` signature :261 (returns `(fm_text_or_None, body)`).
- GOTCHA: (1) `re` is already imported at module top — verify, do not re-import. (2) `rel_path` (not absolute) is the right name — error text stays repo-relative like `generated output claude-code/prp-qa.md`. (3) `split_frontmatter` on md WITHOUT frontmatter returns `(None, content)` → body check still applies (test 41). (4) TOML files exist only for gemini (`format: toml`); real tree's 32 gemini units must pass — full-suite + real-tree dry-run validate. (5) This is the THIRD `split_frontmatter(` call site — update/port the structural grep expectation to 3.
- VALIDATE: `bats tests/scripts/generate-adapters.bats --filter 'A1c'` → pass; `--filter 'structural'` both greps pass.

### Task 4 — port tests (adapted wording), rewrite :254
- ACTION: UPDATE `tests/scripts/generate-adapters.bats`. Rewrite test at :254 as the empty-prompt ERROR row; append after the A1b block (~:452), prefix `A1c row:`:
  1. **prompt empty** (port bats-line 356, rewrite of main :254): `: > qa.md`; rc 1; stderr `error: prompt for command 'qa' is empty or whitespace-only: prompts/qa.md`; `Results: .*6 errors`; no Traceback.
  2. **prompt whitespace-only** (port 364): `printf ' \n\t\n  \n' > qa.md`; same assertions.
  3. **alias-of dangling** (port 378): add `ghost-alias` via yaml hook (same HOOK as #157 :380-387); rc 1; stderr `error: command 'ghost-alias' is an alias of 'no-such-cmd', which is not a configured command`; `Results: .*6 errors`; `[ ! -e "$TREE/adapters/claude-code/prp-ghost-alias.md" ]`.
  4. **empty description → output check (b)** (port 392): `description: {default: ""}`; rc 1; stderr `generated output claude-code/prp-qa.md has an empty description field`; `Results: .*6 errors`.
  5. **dry-run output check** (port 445): same mutation + `--dry-run`; rc 1; same message; `[ ! -e "$TREE/adapters/claude-code/prp-qa.md" ]` (fired before any write).
  6. **validate_generated direct shapes** (port 405): expect_fail for md-empty-body / md-ws-body / md-empty-desc / toml-empty-desc / toml-empty-body / dash-desc-ws-body, + 3 good cases (dash-desc-real-body, plain md, toml with body, no-frontmatter body) — adapted: identical to #157 (module import pattern `spec_from_file_location("ga", ...)` already used by main test :177).
  7. **dash in value, ws body** (port 490): direct — split keeps `pre---post` value, validate errors on ws body.
  8. **trailing-space delimiter + validate** (port 508): direct — `split_frontmatter("---\nk: v\n--- \nbody\n")` → `("k: v", "body\n")`; validate errors on ws body under a trailing-space closer.
  9. **CRLF + empty body** (port 555): direct — validate errors on `---\r\n...\r\n\r\n`.
  10. **no frontmatter: body as-is, validate OK** (port 588): direct — `(None, "body only\n")`; `validate_generated("opencode/prp-x.md", "# just a body\n")` passes.
  11. **structural grep** (port 600, adapted): no `split("---"` / `re.split` on `---` anywhere (already true); `grep -c 'split_frontmatter('` == **3** (def + read_overlay + validate_generated).
- MIRROR: row-test style :247-291; direct-import style :177-210.
- GOTCHA: every new assertion string must match the IMPLEMENTED message exactly (Task 1-3 strings). `Results: .*6 errors` assumes 6 adapters × 1 bad unit — same shape as existing tests. Ghost file name comes from real `file_pattern` (`prp-{name}.md` for claude-code) — assert via the pattern actually configured, not a guess: check `adapters.yml` claude-code `file_pattern` first.
- VALIDATE: `bats tests/scripts/generate-adapters.bats` → all pass (34 @test total: 33 + 10 new − 1 rewritten).

### Task 5 — mutation check (brief step 3: each new test FAILS with the fix removed)
- ACTION: VERIFY. `git stash push -- scripts/generate-adapters.py` → run `bats tests/scripts/generate-adapters.bats --filter 'A1c|prompt empty'` → **all 11 must FAIL** (script reverts to WARNING/skip/silent) → `git stash pop` → re-run → all pass. Record per-test fail/pass in the PR body ("Verified by:").
- VALIDATE: the two runs' summaries captured in the PR body.

### Task 6 — full suite + real-tree proof + CHANGELOG
- ACTION: full suite exactly as CI: `out=$(mktemp -d); bats -r tests --report-formatter junit -o "$out"`; sum `<testsuite>` counts (expect 671 = 661 + 10). Real tree: `python3 scripts/generate-adapters.py --dry-run` in a pristine checkout copy → expect `Results: 192 generated … 0 skipped, 0 errors` (proves all 192 real units pass validate). `python3 -m py_compile scripts/generate-adapters.py`. CHANGELOG 1-line entry.
- VALIDATE: junit 0 failures; dry-run rc 0 with 0 errors; py_compile clean.

## Testing Strategy

| Layer | What | Where |
|---|---|---|
| Unit (direct) | validate_generated all shapes (a)/(b), md+toml, delimiter variants | bats tests 6-10 |
| Integration (gen) | each row through the real CLI: rc / message / Results count / side-effect-free | bats tests 1-5 |
| Structural | split_frontmatter call-site count; no new except (existing :494 test stays) | bats test 11 |
| Regression | full suite 661→671 green; real-tree dry-run 192/0/0 | Task 6 |
| Mutation | new tests fail on unpatched script | Task 5 |

Edge cases: whitespace-only vs empty; alias-of empty string; md without frontmatter; toml without description match; description `""` vs `""""` quoting; CRLF; trailing-space/tab delimiters; dash inside a frontmatter value; dry-run writes nothing.

## Docs Impact

N/A — enumerated: no `packages/web` pages, no `/api` routes, no schema/entities, no flags/billing in this repo; CHANGELOG.md (repo's user-facing log) IS updated (Task 6). No other docs exist for the generator beyond CHANGELOG and test docs.

## Gate Compliance

Gate Compliance: N/A — genuinely internal-only, enumerated: (1) no user-facing product surface — `scripts/generate-adapters.py` is a dev-time generator run by CI/maintainers; (2) no endpoint, schema, entity, flag, or billing change; (3) CI observability unchanged in shape — the same bats suite runs, count grows 661→671; (4) no workflow/cron/systemd/score change; (5) rollback = revert the single commit. Checked against new_feature/epic_kickoff/post_ship checklists — no item applies to a script-repo policy fix.

## Validation Commands

| Level | Command |
|---|---|
| Static analysis | `python3 -m py_compile scripts/generate-adapters.py` |
| Unit tests (file) | `bats tests/scripts/generate-adapters.bats` |
| Full suite (as CI) | `out=$(mktemp -d) && bats -r tests --report-formatter junit -o "$out" && python3 -c "import xml.etree.ElementTree as ET,sys; r=ET.parse('$out/report.xml').getroot(); print(sum(int(t.get('tests',0)) for t in r.iter('testsuite')),'tests',sum(int(t.get('failures',0))+int(t.get('errors',0)) for t in r.iter('testsuite')),'failed')"` |
| Mutation | `git stash push -- scripts/generate-adapters.py && bats tests/scripts/generate-adapters.bats --filter 'A1c|prompt empty'; git stash pop` |
| Database | N/A |
| Browser | N/A |
| Manual (real tree) | `python3 scripts/generate-adapters.py --dry-run` in pristine copy → `0 skipped, 0 errors`, rc 0 |

## Confidence Score

9/10 — Patterns 2 (all patterns quoted from this exact head) + Gotchas 2 (five concrete, incl. the :254 rewrite and grep-invariant interplay) + Integration 2 (call-site positions pinned to line) + Validation 2 (every command pre-filled, mutation protocol defined) + Testing 1.5 (ported tests reviewed through #157's 9 rounds; real-tree dry-run covers the 192-unit risk).

## Acceptance Criteria

- [ ] All three rows raise named counted errors, exit 1, run continues, no traceback — pinned by tests 1-5.
- [ ] validate_generated direct shapes pinned by tests 6-10; third split_frontmatter call site pinned by test 11.
- [ ] `except Exception` count still exactly 2 (existing grep test green, untouched).
- [ ] Full suite green as CI runs it (JUnit, 0 failures); real-tree dry-run `0 skipped, 0 errors`.
- [ ] Mutation check: every new test fails with the script change removed (documented in PR body).
- [ ] PR ≤ ~800 counted lines (target ≈ 260: script +45, tests +200, CHANGELOG +1).
- [ ] PR body carries: plan path, `Invariant:`, `Verified by:` (mutation + junit counts), "Supersedes #157", "Closes the alias-of and S12 items of #192" (sentence only — no GitHub auto-close of #157/#192).

## Completion Checklist

- [ ] py_compile clean
- [ ] file bats suite green
- [ ] full junit suite green (0 failures)
- [ ] real-tree dry-run 0/0, rc 0
- [ ] mutation check recorded
- [ ] CHANGELOG entry
- [ ] PR opened vs main, CI green, [FIX-DONE] printed
- [ ] review loop to stop rule, [READY] printed

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A real tree unit fails validate (empty desc/body in real config) | low | CI red at Task 6 | Real-tree dry-run in Task 6 BEFORE pushing; if it fires, the finding is real data — surface to psak, do not relax the check |
| Ported test wording mismatch vs implemented messages | medium | test red | Messages pinned verbatim in Tasks 1-3; tests copy those exact strings |
| Existing tests pin old behaviour beyond :254 | low | suite red | grep bats file for `WARNING: No prompt file` / `skipped` assertions before finalizing (only :254 expected) |
| Structural grep count 3 breaks a future refactor | low | test-only | Comment in test names the three sites explicitly |

# Plan #157: per-input named errors + no-traceback structure (split 2/2)

Full plan: /home/goko/tmp/151-ac1-blocking-dispatch.plan.md. Base: PR A1
(fix/generator-config-validation); this PR calls its parser and helpers.

**Invariant:** no input the generator reads can end the run with a Python
traceback. Every per-command failure is a named, counted error and the run
CONTINUES. Anything outside the loop exits 1 with one named "internal error"
line; exit is 1 whenever errors > 0.

| Case | Expected |
|---|---|
| prompt missing / unreadable / empty / invalid UTF-8 | GenerationError naming the file, counted per command |
| overlay unreadable / broken frontmatter / not a mapping / unterminated / indented delimiter | GenerationError naming the overlay (+ line) |
| invalid UTF-8 existing output | named, counted, run continues, file never overwritten |
| two bad prompts in one run | both reported, errors = 2 per adapter |
| empty body / empty description (write or would-write, --dry-run too) | validate_generated error (a)/(b) |
| alias-of naming a missing command | GenerationError naming both |
| unexpected exception inside one command | `error: {adapter}/{cmd}: unexpected {type}: {e}`, counted, continue |
| anything escaping the loop | `error: internal: {type}: {e}`, exit 1, no traceback |
| bad prompt under LC_ALL=C | same named decode error (valid tree: parity.bats:718) |

**Verified by:** 29 tests (temp copies) on top of A1's 23, incl. the
forced-RuntimeError monkeypatch and the full structural grep.

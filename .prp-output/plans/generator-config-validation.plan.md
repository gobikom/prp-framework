# Plan A1: load-time config validation, utf-8 pin, display paths (#157 split 1/2)

Full plan: /home/goko/tmp/151-ac1-blocking-dispatch.plan.md (sections
"Re-plan after PR A (#157) round 3"). Per-input named errors and the
structural no-traceback guarantee are PR #157 (split 2/2), based on this
branch.

## Invariant

**Invariant (A1):** every input `load_config` reads — the adapters.yml bytes,
its mapping structure, its key names and its key values — is validated at
load time with a named, fatal error before any generation work starts; every
file read or write in the generator passes `encoding="utf-8"`; and every
user-facing path in a message comes from one `display_path(p)` helper that
never raises. No config input can reach generation code as an unvalidated
value, and none can crash the run with a raw Python traceback.

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
| valid tree | byte-identical adapters, `0 skipped, 0 errors` (parity.bats:718) |

**Verified by:** 11 tests in `tests/scripts/generate-adapters.bats` (temp
copies only) plus the structural grep test (`relative_to(ROOT_DIR)` only in
`display_path`/`validate_output_path`; every `open`/`read_text`/`write_text`
carries `encoding=`).

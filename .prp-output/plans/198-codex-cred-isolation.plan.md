# Plan: #198 Codex review-pass credential isolation

**Decision draft, not implementation.** PR #170 remains draft pending นุด's choice; #199 tracks deferred Medium/Low adapter findings. No code or PR in this branch.

## Problem and invariant

The review pass consumes an untrusted PR bundle. `codex exec --sandbox read-only` limits writes, **not reads**. `scripts/review/sandbox.sh:81-83` mounts `--auth-file` read-only; the draft #170 Codex adapter supplies `$HOME/.codex/auth.json`. A prompt-injected pass can read it and send the value to raw events, stderr, pass.json, a file, or a public review comment. #170's R2 JSON-escaped and R3 15-character chunk evasions demonstrate why output scanners are not the boundary.

**Invariant:** a Codex review pass, including its tools and child processes, cannot read the auth credential. The credential is absent from **every path that the pass process can open**: filesystem (including symlink, `..`, and bind aliases), environment, procfs, inherited file descriptors, and accessible IPC. No credential in the pass home, config, prompt, argv or bundle. The trusted host broker may hold it *outside* the pass process tree/boundary. Filtering pass output cannot establish this invariant. A throwaway `CODEX_HOME` containing copied real auth still violates it.

## Real-input evidence — names and shapes only (2026-10-24)

Read issues #198, #170, #199, source code, and CLI help; **never read, cat, grep or print credential content**. `codex` executable is at `/home/goko/.npm-global/bin/codex`. `codex exec --help` reports:

| Flag | Reported shape / constraint |
|---|---|
| `-s, --sandbox <SANDBOX_MODE>` | `read-only`, `workspace-write`, `danger-full-access`; sandbox controls model-generated shell commands, not a deny-read list |
| `--ignore-user-config` | does not load `$CODEX_HOME/config.toml`; help explicitly says auth still uses `CODEX_HOME` |
| `--ephemeral` | no session files persisted |
| `--output-schema <FILE>`, `--json` | structured response and JSONL events |
| `--cd <DIR>`, `--skip-git-repo-check`, `-c/--config <key=value>`, `-p/--profile` | working root, repo-check override, config/profile injection surfaces |

There is no CLI read-deny flag in the help. Directory-name/mode-only observation with `ls -la "${CODEX_HOME:-$HOME/.codex}"`: `.` and `..` both `drwx------`, and only child name `tmp` (`drwx------`), all owned by `goko`; **no auth file name at this home in this session**. The draft #170 adapter expects the filename `$HOME/.codex/auth.json`, but no claim is made that this session is authenticated, or that a different home lacks credentials. Nothing under that home was opened. If a proof needs a real secret value, stop and ask for an authorized synthetic fixture instead.

Existing wiring: `scripts/review/sandbox.sh:43-64` gives review child read-only `/usr`, `/dev`, `/proc`, tmpfs `/tmp` and `$HOME`, selected `/etc`, `/bundle`, cleared env, network still open; `:68-91` mounts harness package root and binary directory, optional auth file and extra bind paths; `:97-99` launches child. Draft #170 adapter checks local auth-file existence and passes `--auth-file` to sandbox, then scans stderr/raw JSONL/pass.json. **Removing just that bind is insufficient** until all other mounts, symlink resolutions, env, FDs and proc views are proven credential-free.

## Candidate designs and choice

| Design | Benefit | Residual risk / disposition |
|---|---|---|
| A. Per-pass empty `CODEX_HOME` | Temp 0700 home, minimal non-secret config, cleared env and no auth mount. | Alone cannot authenticate if Codex insists on auth in home; copying `auth.json`, API key, or scoped bearer into home defeats strict invariant. Useful only with a credential-free transport; fail closed on CLI incompatibility. |
| B. Host-side auth broker/proxy + A **(conditional recommendation)** | Trusted process outside pass boundary holds auth; pass calls broker through restricted channel, which adds auth upstream. Codex sees only non-secret endpoint config. | Bare loopback proxy with open network is an unbounded credential-bearing API capability to pass/other local clients. Need OS peer identity or isolated network+socket, request method/path allowlist, time/spend limits and redacted errors. CLI compatibility with *empty* home remains unproven. If Codex requires a pass-visible bearer or exposes upstream auth headers, stop. |
| C. Separate user / mount, PID and network namespaces | OS access control prevents pass from opening host credentials, broker memory, other users' env and sockets; strengthens B. | Separate UID alone fails if auth is mounted readable or accessible via proc/network; bwrap availability and namespace policy vary by host. Broker still needs safe authentication/authorization. |
| D. Provider-issued per-run short-lived scoped token | Limits damage and lifetime if supported. | **Does not meet invariant**: a pass-visible token is still a credential it can leak. นุด could accept a different, weaker policy explicitly; no claim of #198 resolution. |

**Choose B + A + C as the design to prototype**, subject to explicit นุด decision and fake-credential end-to-end proof. Until a protected broker transport compatible with Codex is demonstrated, #170 remains parked. Do not replace failed proof with an output scanner or an env-borne bearer token.

## Proposed work AFTER decision (not in this branch)

1. Prove Codex CLI can use a credential-free endpoint with synthetic upstream and broker. Check version and flags without touching real auth. Define broker methods/path allowlist, network/peer authorization, lifetime/quotas and redacted errors. Reject if Codex requires auth in its process. Validation: fake-upstream permitted/forbidden methods and missing-broker tests.
2. Modify `scripts/review/sandbox.sh` with a distinct Codex path: no auth bind; isolated home, PID/proc, filesystem and network/FD view; resolve and reject unsafe `--extra-ro-bind` paths. Preserve Claude path. Validation: synthetic host auth sentinel inaccessible under actual child mount namespace (including harness package-root and binary-directory mounts).
3. After #170 ownership/rebase, modify draft `scripts/review/adapters/codex.sh`: remove the local auth-file check/bind; explicitly check broker readiness and Codex compatibility; create/clean per-pass isolated home and fail nonzero before publishing on auth absence or isolation failure. Validation: stub CLI assertions for argv/env, no fallback, no pass.json on failure.
4. Add adversarial boundary tests under `tests/scripts/sandbox.bats` and `tests/scripts/review-codex-adapter.bats` using **only synthetic credentials**. Check actual child tool context and exported outputs. Scanner may remain defense-in-depth but is never the proof.

## Boundary cases (expected outcome)

All probes run **inside the actual review child/tool context** with a fabricated host credential outside it. Each attempted read must fail and the fabricated sentinel must not appear in raw events, stderr, pass.json, events-out or review-comment input. Unsupported probes are **UNVERIFIED**, not green; report check names/status only, never secret values.

| Hostile operation | Expected result |
|---|---|
| Prompt injection asks tool `cat` conventional auth path and synthetic host-auth realpath | Both inaccessible; a legitimate fake broker model request still works. |
| Agent's file-read tool directly reads those paths (not shell) | Denied; alternate tool route must not escape. |
| `env`, including `CODEX_HOME`, endpoint, `OPENAI_API_KEY`, inherited descriptors | Home contains no auth; endpoint is not a bearer credential; no inherited secret env/fd. |
| `/proc/self/environ`, `/proc/<parent>/environ`, `/proc/<broker>/environ`, child env and `/proc/*/fd` | No credential bytes; parent/broker invisible. `/proc` without effective PID isolation fails the gate. |
| Bundle/isolated-home symlink, absolute bind-path alias and `..` traversal to host auth | Cannot resolve to auth; unsafe bind refused before launch. |
| `/proc/self/root`, `/proc/self/fd`, binary-directory symlink and parent traversal | No escape to auth or broker FDs. |
| Whole, JSON-escaped, base64/hex, reversed, 15-character chunks or file-written synthetic sentinel | Cannot derive it from any pass-visible source; never exported. This is an isolation check, not reliance on output filtering. |
| Credential missing, broker down, CLI unable to authenticate without home token, namespace/mount failure | **Fail closed**: clear error class, nonzero, no pass.json/comment, no host-auth or direct-network fallback. |
| Direct upstream/unrelated loopback access or arbitrary broker request | Denied by network/peer policy and broker allowlist; pass cannot turn broker into general API oracle. |

## Decision and release gates

นุด must decide if broker-mediated model spending is acceptable residual capability, approve deployment/OS/network constraints, or explicitly accept a weaker alternative (short-lived token, trusted-only reviews). This plan is **not** that acceptance. PSak reviews plan; implementation only after decision. Before enabling #170, inspect the process tree's effective mounts, symlinks, env, FDs, PID/proc and network transport; demonstrate fake-upstream end-to-end success and fail-closed arms with synthetic credentials, exact Codex version and reproducible results. If any proof requires reading a real credential, stop rather than opening it.

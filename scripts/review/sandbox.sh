#!/usr/bin/env bash
# Per-pass bwrap sandbox for the review protocol (prp-framework#160).
#
# Invariant 4: a pass process sees only the sanitized bundle and its harness
# runtime. It cannot write outside its tmpfs, read goko's HOME or any GitHub
# credential, and has no MCP.
#
# Usage:
#   sandbox.sh --harness claude-code --bundle DIR --auth-file PATH -- CMD [ARGS...]
#   sandbox.sh --probe --bundle DIR -- CMD [ARGS...]
#
# Review pass: model API network stays (residual channel); auth file mounted
#   read-only with app-level deny rule; no MCP; no shell tool.
# Probe child: --unshare-all (no network at all); no auth file; clearenv;
#   writable /work copy of the bundle.
set -euo pipefail

HARNESS=""
BUNDLE=""
AUTH_FILE=""
PROBE=false
TIMEOUT=300
NICE=10
ULIMIT_NPROC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --harness)      HARNESS="$2"; shift 2 ;;
    --bundle)       BUNDLE="$2"; shift 2 ;;
    --auth-file)    AUTH_FILE="$2"; shift 2 ;;
    --probe)        PROBE=true; shift ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;;
    --nice)         NICE="$2"; shift 2 ;;
    --ulimit-nproc) ULIMIT_NPROC="$2"; shift 2 ;;
    --)             shift; break ;;
    *)              echo "error: unknown flag $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$BUNDLE" || ! -d "$BUNDLE" ]]; then
  echo "error: --bundle must be an existing directory" >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  echo "error: no command given after --" >&2
  exit 1
fi

BUNDLE="$(cd "$BUNDLE" && pwd)"
bwrap_args=()

if $PROBE; then
  bwrap_args+=(
    --unshare-all
    --clearenv
    --setenv PATH "/usr/bin:/usr/local/bin"
    --die-with-parent
    --ro-bind /usr /usr
    --symlink /usr/bin /bin
    --symlink /usr/lib /lib
  )
  [[ -d /usr/lib64 ]] && bwrap_args+=(--symlink /usr/lib64 /lib64)
  bwrap_args+=(
    --dev /dev
    --proc /proc
    --tmpfs /tmp
    --tmpfs "$HOME"
    --bind "$BUNDLE" /work
  )
else
  if [[ -z "$HARNESS" ]]; then
    echo "error: --harness required for review passes" >&2
    exit 1
  fi
  bwrap_args+=(
    --die-with-parent
    --ro-bind /usr /usr
    --symlink /usr/bin /bin
    --symlink /usr/lib /lib
  )
  [[ -d /usr/lib64 ]] && bwrap_args+=(--symlink /usr/lib64 /lib64)
  bwrap_args+=(
    --ro-bind /etc /etc
    --ro-bind /run/systemd/resolve /run/systemd/resolve
    --dev /dev
    --proc /proc
    --tmpfs /tmp
    --tmpfs "$HOME"
    --ro-bind "$BUNDLE" /bundle
  )

  case "$HARNESS" in
    claude-code)
      CLAUDE_BIN="$(command -v claude 2>/dev/null || echo "/usr/local/bin/claude")"
      bwrap_args+=(--ro-bind "$(dirname "$CLAUDE_BIN")" "$(dirname "$CLAUDE_BIN")")
      [[ -n "$AUTH_FILE" && -f "$AUTH_FILE" ]] && bwrap_args+=(--ro-bind "$AUTH_FILE" "$AUTH_FILE")
      ;;
    codex)
      CODEX_BIN="$(command -v codex 2>/dev/null || echo "/usr/local/bin/codex")"
      bwrap_args+=(--ro-bind "$(dirname "$CODEX_BIN")" "$(dirname "$CODEX_BIN")")
      [[ -n "$AUTH_FILE" && -f "$AUTH_FILE" ]] && bwrap_args+=(--ro-bind "$AUTH_FILE" "$AUTH_FILE")
      ;;
    chela)
      echo "error: chela adapter not approved yet (waiting for chela#747)" >&2
      exit 2
      ;;
    *)
      echo "error: unknown harness: $HARNESS" >&2
      exit 1
      ;;
  esac

  bwrap_args+=(
    --unsetenv GH_TOKEN
    --unsetenv GITHUB_TOKEN
    --unsetenv GH_ENTERPRISE_TOKEN
  )
fi

cmd_prefix=()
if [[ -n "$ULIMIT_NPROC" ]]; then
  cmd_prefix+=(bash -c "ulimit -u $ULIMIT_NPROC; exec \"\$@\"" --)
fi

exec nice -n "$NICE" timeout "$TIMEOUT" \
  bwrap "${bwrap_args[@]}" -- \
  "${cmd_prefix[@]}" "$@"

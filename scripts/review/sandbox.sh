#!/usr/bin/env bash
# Per-pass bwrap sandbox for the review protocol (prp-framework#160).
#
# Invariant 4: a pass process sees only the sanitized bundle and its harness runtime.
#
# Residual (review pass): network is OPEN — model API, internet, and host loopback are
# reachable. Loopback services (psak-soul-mcp :8000, oracle-v3 :47778, task-server :8086)
# are token-gated (401 without auth). The pass holds no token (I4a clearenv + I4b deny).
#
# Probe child: --unshare-all (no network at all); no auth file; clearenv; writable /work.
set -euo pipefail

HARNESS="" BUNDLE="" AUTH_FILE="" PROBE=false TIMEOUT=300 NICE=10
DEFAULT_NPROC=256
ULIMIT_NPROC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --harness)      HARNESS="$2"; shift 2 ;; --bundle) BUNDLE="$2"; shift 2 ;;
    --auth-file)    AUTH_FILE="$2"; shift 2 ;; --probe) PROBE=true; shift ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;; --nice) NICE="$2"; shift 2 ;;
    --ulimit-nproc) ULIMIT_NPROC="$2"; shift 2 ;; --) shift; break ;;
    *) echo "error: unknown flag $1" >&2; exit 1 ;;
  esac
done

[[ -z "$BUNDLE" || ! -d "$BUNDLE" ]] && { echo "error: --bundle must be an existing directory" >&2; exit 1; }
[[ $# -eq 0 ]] && { echo "error: no command given after --" >&2; exit 1; }
command -v bwrap >/dev/null 2>&1 || { echo "error: bwrap not found" >&2; exit 1; }

BUNDLE="$(cd "$BUNDLE" && pwd)"
ULIMIT_NPROC="${ULIMIT_NPROC:-$DEFAULT_NPROC}"
bwrap_args=()

_common_mounts() {
  bwrap_args+=(--die-with-parent --ro-bind /usr /usr --symlink /usr/bin /bin --symlink /usr/lib /lib)
  [[ -d /usr/lib64 ]] && bwrap_args+=(--symlink /usr/lib64 /lib64)
  bwrap_args+=(--dev /dev --proc /proc --tmpfs /tmp --tmpfs "$HOME")
}

if $PROBE; then
  bwrap_args+=(--unshare-all --clearenv --setenv PATH "/usr/bin:/usr/local/bin")
  _common_mounts
  bwrap_args+=(--bind "$BUNDLE" /work)
else
  [[ -z "$HARNESS" ]] && { echo "error: --harness required for review passes" >&2; exit 1; }

  bwrap_args+=(--clearenv --setenv PATH "/usr/bin:/usr/local/bin" --setenv HOME "$HOME")
  _common_mounts
  # /etc: only what the harness needs (DNS, TLS, NSS)
  for p in /etc/resolv.conf /etc/nsswitch.conf /etc/hosts /etc/ssl; do
    [[ -e "$p" ]] && bwrap_args+=(--ro-bind "$p" "$p")
  done
  [[ -d /run/systemd/resolve ]] && bwrap_args+=(--ro-bind /run/systemd/resolve /run/systemd/resolve)
  bwrap_args+=(--ro-bind "$BUNDLE" /bundle)

  _mount_harness() {
    local cmd="$1"
    local bin_path resolved bin_dir pkg_root
    bin_path="$(command -v "$cmd" 2>/dev/null)" || { echo "error: $cmd not found" >&2; exit 1; }
    [[ -x "$bin_path" ]] || { echo "error: $cmd not executable: $bin_path" >&2; exit 1; }
    resolved="$(readlink -f "$bin_path")"
    bin_dir="$(dirname "$bin_path")"
    # Mount the whole npm prefix (bin + lib) so symlinks resolve
    pkg_root="$(cd "$bin_dir/.." && pwd)"
    bwrap_args+=(--ro-bind "$pkg_root" "$pkg_root")
    bwrap_args+=(--setenv PATH "$bin_dir:/usr/bin:/usr/local/bin")
    if [[ -n "$AUTH_FILE" ]] && [[ -f "$AUTH_FILE" ]]; then
      bwrap_args+=(--ro-bind "$AUTH_FILE" "$AUTH_FILE")
    fi
  }

  case "$HARNESS" in
    claude-code) _mount_harness claude ;;
    codex) _mount_harness codex ;;
    chela) echo "error: chela adapter not approved yet (waiting for chela#747)" >&2; exit 2 ;;
    *) echo "error: unknown harness: $HARNESS" >&2; exit 1 ;;
  esac
fi

exec nice -n "$NICE" timeout "$TIMEOUT" \
  bwrap "${bwrap_args[@]}" -- \
  bash -c "ulimit -u $ULIMIT_NPROC || { echo 'error: ulimit -u $ULIMIT_NPROC failed' >&2; exit 1; }; exec \"\$@\"" -- "$@"

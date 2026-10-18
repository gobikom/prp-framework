#!/usr/bin/env bash
# Shared credential-pattern scan. Source this, then call _scan_cred <file>.
# Fails closed: a pattern match (rc=0) AND a scan error (rc>1) both return 1 —
# an unreadable file must never scan as clean.
_scan_cred() {
  local f="$1" rc
  grep -qE 'sk-ant-' "$f"; rc=$?
  if [ "$rc" -eq 0 ]; then echo "error: credential pattern: sk-ant" >&2; return 1; fi
  if [ "$rc" -gt 1 ]; then echo "error: credential scan failed (rc=$rc): $f" >&2; return 1; fi
  grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.' "$f"; rc=$?
  if [ "$rc" -eq 0 ]; then echo "error: credential pattern: jwt" >&2; return 1; fi
  if [ "$rc" -gt 1 ]; then echo "error: credential scan failed (rc=$rc): $f" >&2; return 1; fi
  grep -qE 'ghp_|gho_|github_pat_' "$f"; rc=$?
  if [ "$rc" -eq 0 ]; then echo "error: credential pattern: github-token" >&2; return 1; fi
  if [ "$rc" -gt 1 ]; then echo "error: credential scan failed (rc=$rc): $f" >&2; return 1; fi
  return 0
}

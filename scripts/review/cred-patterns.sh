#!/usr/bin/env bash
# Shared credential-pattern scan. Source this, then call _scan_cred <file>.
_scan_cred() {
  local f="$1"
  if grep -qE 'sk-ant-' "$f"; then echo "error: credential pattern: sk-ant" >&2; return 1; fi
  if grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.' "$f"; then echo "error: credential pattern: jwt" >&2; return 1; fi
  if grep -qE 'ghp_|gho_|github_pat_' "$f"; then echo "error: credential pattern: github-token" >&2; return 1; fi
  return 0
}

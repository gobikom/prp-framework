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
  grep -qE '(^|[^A-Za-z0-9]|\\[nrt])sk-(proj-)?[A-Za-z0-9_-]{20,}' "$f"; rc=$?
  if [ "$rc" -eq 0 ]; then echo "error: credential pattern: openai-key" >&2; return 1; fi
  if [ "$rc" -gt 1 ]; then echo "error: credential scan failed (rc=$rc): $f" >&2; return 1; fi
  grep -qE 'refresh_token[^A-Za-z0-9]{1,8}[A-Za-z0-9_.~+/=-]{10,}' "$f"; rc=$?
  if [ "$rc" -eq 0 ]; then echo "error: credential pattern: refresh-token" >&2; return 1; fi
  if [ "$rc" -gt 1 ]; then echo "error: credential scan failed (rc=$rc): $f" >&2; return 1; fi
  return 0
}

# Value-based scan: refuse any output containing a string value from the auth file, plain or
# JSON-escaped (raw-output.jsonl / pass.json are JSON-serialised, so quotes, newlines and slashes
# are escaped there). Shape patterns cannot see a bare token a model-run `cat`/`jq` printed;
# this can. Values are matched in memory and never printed (the label names only the count).
# Usage: _scan_auth_values <auth-file> <file>... ; fails closed on any error.
_scan_auth_values() {
  local auth="$1"; shift
  python3 -I -c '
import json, sys
try:
    vals = []
    def walk(o):
        if isinstance(o, dict):
            for v in o.values(): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
        elif isinstance(o, str) and len(o) >= 16:
            vals.append(o)
    walk(json.load(open(sys.argv[1])))
    needles = set()
    for v in vals:
        for form in (v, json.dumps(v)[1:-1], json.dumps(v, ensure_ascii=False)[1:-1], v.replace("/", "\\/")):
            needles.add(form)
            needles.add(form[:16]); needles.add(form[-16:])
    for f in sys.argv[2:]:
        data = open(f, encoding="utf-8", errors="replace").read()
        if any(n and n in data for n in needles):
            print("error: credential value from auth file found in output", file=sys.stderr)
            sys.exit(1)
except SystemExit:
    raise
except Exception as e:
    print("error: auth-value scan failed (%s)" % type(e).__name__, file=sys.stderr)
    sys.exit(2)
' "$auth" "$@" || return 1
}

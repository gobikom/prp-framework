#!/bin/bash
# PRP Verify Feature Map — mechanics for .prp-verify/feature-map.yaml (#202 PR-B).
#
# Inert until PR-C wires it into {TOOL}:verify. Subcommands:
#
#   validate <map>              schema-check the map, print every error
#   stale <map> [--head <ref>]  print ids whose paths changed since synced_sha
#   match <map> "<ac text>"     print live:<id> / removed:<id> keyword hits
#   run <map> <id>              run the entry's exercise, judge expect
#   prove-negative <map> <id>   rerun the exercise with product paths deleted;
#                              exit 0 = negative held (expect NOT met)
#   sync <map> <id> [--write]   positive run + negative proof -> advance
#                              synced_sha; all paths gone -> tombstone
#
# Exit contract (every subcommand):
#   0  met / succeeded          1  not met (FAIL, includes vacuous entries)
#   2  usage error              3  tool or internal error — never PASS,
#                                 and never counted as a proven negative
#   4  environment unavailable (UNVERIFIED)
#
# GOTCHAS (plan B2): never `eval` in the parent shell; never echo env var
# values (creds: is checked by name with ${!name+x}); paths globs are python
# fnmatch with ** support, not bash globbing; the prove-negative worktree is
# removed in a trap; exit 3 is never read as proven.
set -u
LC_ALL=C
export LC_ALL

usage() {
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

[ $# -ge 1 ] || usage
CMD="$1"
shift

# --- shared python helper ---------------------------------------------------
# One embedded program; bash owns process orchestration (exercise runs,
# worktrees, traps), python owns YAML/regex/glob logic.
PY_HELPER="$(cat <<'PYEOF'
import fnmatch
import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not available (CI venv provides it)", file=sys.stderr)
    sys.exit(3)


def internal(msg):
    print(f"ERROR: internal error: {msg}", file=sys.stderr)
    sys.exit(3)


def load_map(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except (OSError, yaml.YAMLError) as e:
        internal(f"cannot read map {path}: {e!r}")
    if not isinstance(data, dict):
        internal(f"map {path} is not a mapping")
    return data


def find_entry(data, entry_id):
    for e in data.get("features") or []:
        if isinstance(e, dict) and e.get("id") == entry_id:
            return e
    return None


def glob_to_re(pat):
    # fnmatch with ** support: ** crosses slashes, * and ? do not
    out, i = [], 0
    while i < len(pat):
        if pat.startswith("**", i):
            out.append(".*")
            i += 2
        elif pat[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pat[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pat[i]))
            i += 1
    return re.compile("".join(out) + r"\Z")


def path_matches(patterns, path):
    return any(glob_to_re(p).match(path) for p in patterns)


def head_files(root):
    proc = subprocess.run(
        ["git", "-C", root, "ls-files", "-z"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        internal(f"git ls-files failed: {proc.stderr.decode(errors='replace').strip()}")
    return [p.decode(errors="surrogateescape")
            for p in proc.stdout.split(b"\0") if p]


ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
ENV_RE = re.compile(r"^(local|uat|staging|browser|creds:[A-Z0-9_]+)$")
EXPECT_KEYS = {"exit", "stdout_regex", "http_status", "json_path"}


def cmd_validate(path):
    errors = []
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"invalid YAML: {e!r}")
        return 1
    except OSError as e:
        print(f"cannot read map: {e}")
        return 3
    if not isinstance(data, dict):
        print("map must be a mapping")
        return 1
    if data.get("version") != 1:
        errors.append("version must be 1")
    unknown_root = set(data) - {"version", "features", "removed"}
    if unknown_root:
        errors.append(f"unknown top-level keys {sorted(unknown_root)}")
    feats = data.get("features")
    if not isinstance(feats, list):
        errors.append("features must be a list")
        feats = []
    seen = set()
    req = ["id", "summary", "match", "paths", "surface", "env",
           "exercise", "expect", "synced_sha", "negative_proof"]
    for n, e in enumerate(feats, 1):
        where = f"features[{n}]"
        if not isinstance(e, dict):
            errors.append(f"{where}: not a mapping")
            continue
        for k in req:
            if k not in e:
                errors.append(f"{where}: missing required key '{k}'")
        unknown = set(e) - set(req) - {"timeout"}
        if unknown:
            errors.append(f"{where}: unknown keys {sorted(unknown)}")
        fid = e.get("id")
        if not isinstance(fid, str) or not ID_RE.match(fid) or len(fid) > 64:
            errors.append(f"{where}: bad id {fid!r}")
        elif fid in seen:
            errors.append(f"{where}: duplicate id '{fid}'")
        seen.add(fid)
        if not isinstance(e.get("summary"), str) or not (1 <= len(e["summary"]) <= 200):
            errors.append(f"{where}: summary must be 1-200 chars")
        m = e.get("match")
        if not isinstance(m, list) or not m or not all(
                isinstance(x, str) and 1 <= len(x) <= 80 for x in m):
            errors.append(f"{where}: match must be a non-empty string list")
        p = e.get("paths")
        if not isinstance(p, list) or not p or not all(
                isinstance(x, str) and 1 <= len(x) <= 200 for x in p):
            errors.append(f"{where}: paths must be a non-empty string list")
        if e.get("surface") not in ("cli", "api", "ui", "lib"):
            errors.append(f"{where}: surface must be cli|api|ui|lib")
        env = e.get("env")
        if not isinstance(env, str) or not ENV_RE.match(env):
            errors.append(f"{where}: bad env {env!r}")
        elif env.startswith("creds:") and not env[6:]:
            errors.append(f"{where}: creds: needs a variable name")
        if not isinstance(e.get("exercise"), str) or not (1 <= len(e["exercise"]) <= 2000):
            errors.append(f"{where}: exercise must be 1-2000 chars")
        t = e.get("timeout", 120)
        if not isinstance(t, int) or isinstance(t, bool) or not (1 <= t <= 3600):
            errors.append(f"{where}: timeout must be an integer 1-3600")
        sha = e.get("synced_sha")
        if not isinstance(sha, str) or not SHA_RE.match(sha):
            errors.append(f"{where}: synced_sha must be a 40-hex sha")
        np = e.get("negative_proof")
        if not isinstance(np, dict):
            errors.append(f"{where}: negative_proof must be a mapping")
        else:
            unknown_np = set(np) - {"sha", "exit"}
            if unknown_np:
                errors.append(f"{where}: unknown negative_proof keys {sorted(unknown_np)}")
            if not isinstance(np.get("sha"), str) or not SHA_RE.match(np.get("sha", "")):
                errors.append(f"{where}: negative_proof.sha must be a 40-hex sha")
            nx = np.get("exit")
            if not isinstance(nx, int) or isinstance(nx, bool) or nx == 0:
                errors.append(f"{where}: negative_proof.exit must be a non-zero integer")
        ex = e.get("expect")
        if not isinstance(ex, dict):
            errors.append(f"{where}: expect must be a mapping")
        else:
            unknown_e = set(ex) - EXPECT_KEYS
            if unknown_e:
                errors.append(f"{where}: unknown expect keys {sorted(unknown_e)}")
            if not ex:
                errors.append(f"{where}: expect must have at least one key")
            if "exit" in ex and (not isinstance(ex["exit"], int) or isinstance(ex["exit"], bool)):
                errors.append(f"{where}: expect.exit must be an integer")
            for k in ("stdout_regex", "json_path"):
                if k in ex and (not isinstance(ex[k], str) or not (1 <= len(ex[k]) <= 256)):
                    errors.append(f"{where}: expect.{k} must be 1-256 chars")
            hs = ex.get("http_status")
            if "http_status" in ex and (
                    not isinstance(hs, int) or isinstance(hs, bool) or not (100 <= hs <= 599)):
                errors.append(f"{where}: expect.http_status must be 100-599")
    rem = data.get("removed", [])
    if not isinstance(rem, list):
        errors.append("removed must be a list")
        rem = []
    for n, e in enumerate(rem, 1):
        where = f"removed[{n}]"
        if not isinstance(e, dict):
            errors.append(f"{where}: not a mapping")
            continue
        _rid = e.get("id")
        if not isinstance(_rid, str) or not ID_RE.match(_rid) or len(_rid) > 64:
            errors.append(f"{where}: bad id")
        elif _rid in seen:
            errors.append(f"{where}: duplicate id '{_rid}'")
        seen.add(_rid)
        reason = e.get("removed_reason")
        if not isinstance(reason, str) or len(reason) < 10:
            errors.append(f"{where}: removed_reason must be at least 10 chars")
        if not isinstance(e.get("removed_sha"), str) or not SHA_RE.match(e.get("removed_sha", "")):
            errors.append(f"{where}: removed_sha must be a 40-hex sha")
    for err in errors:
        print(err)
    return 1 if errors else 0


def cmd_stale(path, head):
    data = load_map(path)
    for e in data.get("features") or []:
        sha = e.get("synced_sha")
        if not isinstance(sha, str) or not SHA_RE.match(sha):
            internal(f"entry '{e.get('id')}' has a bad synced_sha")
        probe = subprocess.run(["git", "cat-file", "-e", sha + "^{commit}"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if probe.returncode != 0:
            internal(f"entry '{e.get('id')}': synced_sha {sha} not found in repo")
        diff = subprocess.run(
            ["git", "diff", "--name-only", f"{sha}..{head}"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if diff.returncode != 0:
            internal(f"git diff {sha}..{head} failed: {diff.stderr.decode(errors='replace').strip()}")
        changed = diff.stdout.decode(errors="surrogateescape").splitlines()
        if any(path_matches(e.get("paths") or [], c) for c in changed):
            print(e["id"])
    return 0


def cmd_match(path, text):
    data = load_map(path)

    def hits(keywords):
        for kw in keywords or []:
            if re.search(r"(?<![A-Za-z0-9])" + re.escape(kw) + r"(?![A-Za-z0-9])", text, re.I):
                return True
        return False

    for e in data.get("features") or []:
        if hits(e.get("match")):
            print(f"live:{e['id']}")
    for e in data.get("removed") or []:
        if hits(e.get("match")):
            print(f"removed:{e['id']}")
    return 0


def cmd_extract(path, entry_id):
    e = find_entry(load_map(path), entry_id)
    if e is None:
        print(f"ERROR: unknown entry id '{entry_id}'", file=sys.stderr)
        sys.exit(2)
    out = e["exercise"].encode()
    for v in (e.get("timeout", 120), e["env"], json.dumps(e["expect"])):
        out += b"\0" + str(v).encode()
    sys.stdout.buffer.write(out + b"\0")
    return 0


def cmd_files(path, entry_id, root):
    e = find_entry(load_map(path), entry_id)
    if e is None:
        print(f"ERROR: unknown entry id '{entry_id}'", file=sys.stderr)
        sys.exit(2)
    for f in head_files(root):
        if path_matches(e.get("paths") or [], f):
            sys.stdout.buffer.write(f.encode(errors="surrogateescape") + b"\0")
    return 0


def cmd_overlap(path, entry_id):
    e = find_entry(load_map(path), entry_id)
    if e is None:
        print(f"ERROR: unknown entry id '{entry_id}'", file=sys.stderr)
        sys.exit(2)
    for word in e["exercise"].split():
        if path_matches(e.get("paths") or [], word):
            print(f"paths include the exercise ({word})")
            return 1
    return 0


DENY_RE = re.compile(r"^\s*(true|:|exit 0|echo\b.*)?\s*$")


def cmd_denycheck(exercise):
    lines = [ln for ln in exercise.splitlines() if ln.strip()]
    if not lines or all(DENY_RE.match(ln) for ln in lines):
        print("vacuous: trivial exercise")
        return 1
    return 0


def cmd_met(rc, outfile, expect_json):
    try:
        return _met_judge(rc, outfile, expect_json)
    except Exception as e:
        print(f"judge error: {e!r}", file=sys.stderr)
        return 3


def _met_judge(rc, outfile, expect_json):
    expect = json.loads(expect_json)
    reasons = []
    if "exit" in expect and rc != expect["exit"]:
        reasons.append(f"exit {rc} != expected {expect['exit']}")
    if "stdout_regex" in expect:
        with open(outfile, "rb") as f:
            content = f.read().decode(errors="replace")
        if not re.search(expect["stdout_regex"], content):
            reasons.append(f"stdout does not match /{expect['stdout_regex']}/")
    for k in ("http_status", "json_path"):
        if k in expect:
            reasons.append(f"{k} not supported by this runner (tool limit)")
    if reasons:
        print("; ".join(reasons))
        return 1
    print("matched=" + json.dumps(expect, sort_keys=True, separators=(",", ":")))
    return 0


def cmd_sync_write(path, entry_id, mode, head_sha, neg_exit, write):
    data = load_map(path)
    feats = data.get("features") or []
    idx = next(i for i, e in enumerate(feats) if e.get("id") == entry_id)
    if mode == "tombstone":
        entry = feats.pop(idx)
        tomb = {
            "id": entry_id,
            "removed_reason": f"paths deleted at {head_sha}",
            "removed_sha": head_sha,
        }
        if isinstance(entry.get("match"), list) and entry["match"]:
            tomb["match"] = entry["match"]
        data["removed"] = (data.get("removed") or []) + [tomb]
        action = f"removed:{entry_id}"
    else:
        feats[idx]["synced_sha"] = head_sha
        feats[idx]["negative_proof"] = {"sha": head_sha, "exit": neg_exit}
        action = f"synced:{entry_id} sha={head_sha}"
    data["version"] = 1
    if not write:
        print(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
        print(action)
        return 0
    tmp = path + ".sync-tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)
    os.replace(tmp, path)
    print(action)
    return 0


args = sys.argv[1:]
cmd = args[0] if args else ""
if cmd == "validate":
    sys.exit(cmd_validate(args[1]))
if cmd == "stale":
    sys.exit(cmd_stale(args[1], args[2]))
if cmd == "match":
    sys.exit(cmd_match(args[1], args[2]))
if cmd == "extract":
    sys.exit(cmd_extract(args[1], args[2]))
if cmd == "files":
    sys.exit(cmd_files(args[1], args[2], args[3]))
if cmd == "overlap":
    sys.exit(cmd_overlap(args[1], args[2]))
if cmd == "denycheck":
    sys.exit(cmd_denycheck(args[1]))
if cmd == "met":
    sys.exit(cmd_met(int(args[1]), args[2], args[3]))
if cmd == "sync_write":
    sys.exit(cmd_sync_write(args[1], args[2], args[3], args[4],
                            int(args[5]), args[6] == "write"))
internal(f"unknown python subcommand '{cmd}'")
PYEOF
)"

py() { python3 -c "$PY_HELPER" "$@"; }

die3() { echo "ERROR: internal error: $1" >&2; exit 3; }
die4() { echo "UNVERIFIED: $1" >&2; exit 4; }

command -v python3 >/dev/null 2>&1 || die3 "python3 not found in PATH"
command -v git >/dev/null 2>&1 || die3 "git not found in PATH"
python3 -c "import yaml" 2>/dev/null || die3 "PyYAML not available"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die3 "not inside a git repository"

# env_available <env> — name-based checks only, never prints values
env_available() {
    case "$1" in
        local) return 0 ;;
        uat|staging)
            VARN="PRP_VERIFY_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')_URL"
            if [ -z "${!VARN+x}" ]; then
                echo "UNVERIFIED: env '$1' unavailable ($VARN not set)" >&2
                return 1
            fi
            if ! curl -fsS -m 10 "${!VARN}" >/dev/null 2>&1; then
                echo "UNVERIFIED: env '$1' unavailable ($VARN did not answer curl -fsS -m 10)" >&2
                return 1
            fi ;;
        browser)
            if ! command -v npx >/dev/null 2>&1 || ! npx playwright --version >/dev/null 2>&1; then
                echo "UNVERIFIED: env 'browser' unavailable (npx playwright not runnable)" >&2
                return 1
            fi ;;
        creds:*)
            NAME="${1#creds:}"
            if [ -z "${!NAME+x}" ]; then
                echo "UNVERIFIED: env '$1' unavailable (variable $NAME not set)" >&2
                return 1
            fi ;;
        *) die3 "unknown env kind '$1'" ;;
    esac
    return 0
}

# run_entry <map> <id> — executes the exercise and judges expect.
# Prints "map:<id> exit=<rc> matched=<expect>" on success; the reason plus
# truncated stdout evidence on failure. Returns the contract exit code.
run_entry() {
    _MAP="$1"; _ID="$2"
    # NUL-separated fields cannot survive $(...) — extract straight to a file
    _TMP_FIELDS="$(mktemp)" || die3 "mktemp failed"
    py extract "$_MAP" "$_ID" > "$_TMP_FIELDS"
    _RC=$?
    if [ "$_RC" -ne 0 ]; then rm -f "$_TMP_FIELDS"; return "$_RC"; fi
    # NUL-safe re-read: fields are exercise\0timeout\0env\0expect
    {
        IFS= read -r -d '' EXERCISE
        IFS= read -r -d '' TIMEOUT
        IFS= read -r -d '' ENVK
        IFS= read -r -d '' EXPECT
    } < "$_TMP_FIELDS"
    rm -f "$_TMP_FIELDS"
    [ -n "${TIMEOUT:-}" ] || die3 "empty extract"
    env_available "$ENVK" || return 4
    BEFORE="$(git -C "$REPO_ROOT" status --porcelain)" || die3 "git status failed"
    OUT="$(mktemp)" || die3 "mktemp failed"
    ( cd "$REPO_ROOT" && timeout "$TIMEOUT" nice -n 10 bash -c "$EXERCISE" ) >"$OUT" 2>&1
    RC=$?
    if [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; then
        echo "FAIL map:$_ID: timeout after ${TIMEOUT}s"
        return 1
    fi
    MET_OUT="$(py met "$RC" "$OUT" "$EXPECT")"
    MET_RC=$?
    if [ "$MET_RC" -ne 0 ] && [ "$MET_RC" -ne 1 ]; then
        echo "ERROR: judge failed for map:$_ID (exit $MET_RC)" >&2
        return 3
    fi
    if [ "$MET_RC" -ne 0 ]; then
        echo "FAIL map:$_ID: $MET_OUT"
        echo "--- exercise output (first 4KB) ---"
        head -c 4096 "$OUT"
        return 1
    fi
    AFTER="$(git -C "$REPO_ROOT" status --porcelain)" || die3 "git status failed"
    if [ "$BEFORE" != "$AFTER" ]; then
        echo "FAIL map:$_ID: exercise mutated worktree"
        return 1
    fi
    echo "map:$_ID exit=$RC $MET_OUT"
    return 0
}

# prove_negative <map> <id> — 0 = negative held, 1 = vacuous, 3 = tool error
prove_negative() {
    _MAP="$1"; _ID="$2"
    # NUL-separated fields cannot survive $(...) — extract straight to a file
    _TMP_FIELDS="$(mktemp)" || die3 "mktemp failed"
    py extract "$_MAP" "$_ID" > "$_TMP_FIELDS"
    _RC=$?
    if [ "$_RC" -ne 0 ]; then rm -f "$_TMP_FIELDS"; return "$_RC"; fi
    {
        IFS= read -r -d '' EXERCISE
        IFS= read -r -d '' TIMEOUT
        IFS= read -r -d '' ENVK
        IFS= read -r -d '' EXPECT
    } < "$_TMP_FIELDS"
    rm -f "$_TMP_FIELDS"
    [ -n "${TIMEOUT:-}" ] || die3 "empty extract"
    env_available "$ENVK" || return 4
    DENY_OUT="$(py denycheck "$EXERCISE")"
    [ $? -eq 0 ] || { echo "$DENY_OUT"; return 1; }
    OVERLAP_OUT="$(py overlap "$_MAP" "$_ID")"
    [ $? -eq 0 ] || { echo "$OVERLAP_OUT"; return 1; }
    TMPD="$(mktemp -d)" || die3 "mktemp failed"
    NEGTREE="$TMPD/neg"
    cleanup() {
        git -C "$REPO_ROOT" worktree remove --force "$NEGTREE" >/dev/null 2>&1
        rm -rf "$TMPD"
    }
    trap cleanup EXIT
    git -C "$REPO_ROOT" worktree add --detach "$NEGTREE" HEAD >/dev/null 2>&1 \
        || { cleanup; die3 "worktree add failed"; }
    _RMFILE="$TMPD/files.nul"
    py files "$_MAP" "$_ID" "$NEGTREE" > "$_RMFILE" || { cleanup; rm -f "$_RMFILE"; return 3; }
    mapfile -d '' -t RM_PATHS < "$_RMFILE"
    rm -f "$_RMFILE"
    if [ "${#RM_PATHS[@]}" -gt 0 ]; then
        git -C "$NEGTREE" rm -q -f -- "${RM_PATHS[@]}" >/dev/null 2>&1 \
            || { cleanup; die3 "git rm of product paths failed"; }
    fi
    NEG_OUT="$(mktemp)" || { cleanup; die3 "mktemp failed"; }
    # the exercise must run inside the stripped tree, or the deletion has no effect
    ( cd "$NEGTREE" && timeout "$TIMEOUT" nice -n 10 bash -c "$EXERCISE" ) >"$NEG_OUT" 2>&1
    NRC=$?
    cleanup
    trap - EXIT
    if [ "$NRC" -eq 124 ] || [ "$NRC" -eq 137 ]; then
        echo "negative held exit=124 (exercise timed out at ${TIMEOUT}s)"
        return 0
    fi
    MET_OUT="$(py met "$NRC" "$NEG_OUT" "$EXPECT")"
    MET_RC=$?
    if [ "$MET_RC" -eq 0 ]; then
        echo "vacuous: negative proof met expect"
        return 1
    fi
    if [ "$MET_RC" -ne 1 ]; then
        echo "ERROR: judge failed during negative proof (exit $MET_RC)" >&2
        return 3
    fi
    echo "negative held exit=$NRC: $MET_OUT"
    return 0
}

case "$CMD" in
    validate)
        [ $# -eq 1 ] || usage
        [ -f "$1" ] || { echo "ERROR: map not found: $1" >&2; exit 3; }
        py validate "$1"
        ;;
    stale)
        { [ $# -eq 1 ] || { [ $# -eq 3 ] && [ "$2" = "--head" ]; } } || usage
        HEAD_REF="HEAD"
        [ $# -eq 3 ] && HEAD_REF="$3"
        py stale "$1" "$HEAD_REF"
        ;;
    match)
        [ $# -eq 2 ] || usage
        py match "$1" "$2"
        ;;
    run)
        [ $# -eq 2 ] || usage
        run_entry "$1" "$2"
        ;;
    prove-negative)
        [ $# -eq 2 ] || usage
        prove_negative "$1" "$2"
        ;;
    sync)
        { [ $# -eq 2 ] || { [ $# -eq 3 ] && [ "$3" = "--write" ]; } } || usage
        MAPF="$1"; SID="$2"; WRITE="dry"
        [ $# -eq 3 ] && WRITE="write"
        HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)" || die3 "git rev-parse HEAD failed"
        _CNTFILE="$(mktemp)" || die3 "mktemp failed"
        py files "$MAPF" "$SID" "$REPO_ROOT" > "$_CNTFILE"
        _FRC=$?
        if [ "$_FRC" -ne 0 ]; then rm -f "$_CNTFILE"; exit "$_FRC"; fi
        mapfile -d '' -t M_PATHS < "$_CNTFILE"
        rm -f "$_CNTFILE"
        if [ "${#M_PATHS[@]}" -eq 0 ]; then
            echo "all paths deleted at HEAD -> tombstone"
            py sync_write "$MAPF" "$SID" tombstone "$HEAD_SHA" 0 "$WRITE"
            exit $?
        fi
        RUN_OUT="$(run_entry "$MAPF" "$SID")"
        RUN_RC=$?
        if [ "$RUN_RC" -ne 0 ]; then
            echo "$RUN_OUT" >&2
            if [ "$RUN_RC" -eq 3 ] || [ "$RUN_RC" -eq 4 ]; then exit "$RUN_RC"; fi
            echo "sync $SID: run did not pass (exit $RUN_RC); map unchanged" >&2
            exit 1
        fi
        PN_OUT="$(prove_negative "$MAPF" "$SID")"
        PN_RC=$?
        if [ "$PN_RC" -ne 0 ]; then
            echo "$PN_OUT" >&2
            if [ "$PN_RC" -eq 3 ]; then exit 3; fi
            echo "sync $SID: negative proof failed (exit $PN_RC); map unchanged" >&2
            exit 1
        fi
        NEG_EXIT="$(printf '%s' "$PN_OUT" | sed -n 's/^negative held exit=\([0-9]*\).*/\1/p' | head -1)"
        case "$NEG_EXIT" in
            ''|*[!0-9]*|0)
                echo "sync $SID: could not determine negative exit; map unchanged" >&2
                exit 3
                ;;
        esac
        py sync_write "$MAPF" "$SID" advance "$HEAD_SHA" "$NEG_EXIT" "$WRITE"
        exit $?
        ;;
    *)
        usage
        ;;
esac

#!/usr/bin/env python3
"""Read-only review rounds report for prp-framework#160 AC0.4.
Never writes: local transcript reads and gh api GETs only.

Fallback classifier (tool-event based): a run whose first prompt carries
--since-last-review is 'invoked'; any other run is 'full-requested' and is
excluded from the fallback rate. For an invoked run, a tool event that
reads pr-N-incremental.diff or runs a two-SHA `git diff A B` / `A...B` makes
it 'incremental'; otherwise a tool result for the previous review file that
reports not-found makes it 'fell-back'; anything else is 'unknown'.

Family heuristic (rounds): only inside a Critical/Important section with
count>0 (up to the next ### heading), each top-level bullet (`- **T**`,
`* **T**` or `1. **T**`, not indented) gives a title T, and so does each
findings-table row (first sentence of its second column). Normalised: lower,
strip leading file:line, strip punctuation. Same normalised title in
consecutive rounds → class b (repeated family).

Errors are never reported as data, and one bad unit never stops the batch:
- rounds: a gh api failure other than 404, a missing or non-JSON fixture, or
  a malformed comment gives that PR status 'error'; the other PRs are still
  reported.
- fallback: an unreadable transcript (missing, a directory, non-UTF-8) is
  listed under 'errors' and excluded from the counts; a line that is not a
  JSON object counts as a skipped line.
Exit codes: 0 = all units read, 2 = at least one unit errored, 1 = usage.

Usage:
  python3 -I scripts/bench/review-rounds.py fallback <session.jsonl ...>
  python3 -I scripts/bench/review-rounds.py rounds --repo OWNER/REPO --prs N,N,...
  Add --json for JSON output. Set REVIEW_ROUNDS_GH_FIXTURES=<dir> for offline tests.
"""
import json, os, re, subprocess, sys, traceback

def _read_jsonl(path):
    lines, skipped = [], 0
    with open(path, encoding="utf-8") as fh:
        raw_lines = fh.readlines()
    for line in raw_lines:
        line = line.strip()
        if not line: continue
        try: obj = json.loads(line)
        except json.JSONDecodeError: skipped += 1; continue
        if isinstance(obj, dict): lines.append(_normalise_event(obj))
        else: skipped += 1  # valid JSON but not an event object
    return lines, skipped

def _str(x):
    return x if isinstance(x, str) else ""

def _text_of(x):
    """Any JSON value as searchable text: a string as is, None as "", else str()."""
    if isinstance(x, str): return x
    if x is None: return ""
    return str(x)

def _normalise_event(obj):
    """Raw transcript JSON object -> a fixed shape. The ONLY place raw event JSON is read.

    {"type": str, "text": str, "blocks": [{"type": str, "text": str, "command": str, "content": str}]}
    Any field of the wrong type becomes "" / [] here, so the classifier never sees raw JSON.
    """
    msg = obj.get("message")
    msg = msg if isinstance(msg, dict) else {}
    content = msg.get("content")
    blocks = []
    if isinstance(content, list):
        for b in content:
            if not isinstance(b, dict): continue
            inp = b.get("input")
            cmd = inp.get("command") if isinstance(inp, dict) else None
            command = cmd if isinstance(cmd, str) and cmd else _text_of(inp)
            blocks.append({"type": _str(b.get("type")), "text": _str(b.get("text")),
                           "command": command, "content": _text_of(b.get("content"))})
    return {"type": _str(obj.get("type")), "text": _str(content), "blocks": blocks}

def _first_prompt(events):
    for e in events:
        if e["type"] not in ("human", "user"): continue
        if e["text"]: return e["text"]
        for block in e["blocks"]:
            if block["type"] == "text":
                return block["text"]
    return ""

REVIEW_FILE_PAT = re.compile(r"pr-\d+-agents-review\.md")
INCR_DIFF_PAT = re.compile(r"pr-\d+-incremental\.diff")
TWO_SHA_PAT = re.compile(r"git diff [0-9a-f]{7,40}[\s.]+[0-9a-f]{7,40}")
NOT_FOUND_PAT = re.compile(r"NOT_FOUND|No such file|not found|cannot access", re.I)

def _extract_tool_events(events):
    """Extract tool_use commands and tool_result content from normalised events."""
    tools = []
    for e in events:
        for block in e["blocks"]:
            if block["type"] == "tool_use": tools.append(("use", block["command"]))
            if block["type"] == "tool_result": tools.append(("result", block["content"]))
    return tools

def classify_mode(events):
    prompt = _first_prompt(events)
    invoked = "--since-last-review" in prompt
    if not invoked: return "full-requested", invoked
    tools = _extract_tool_events(events)
    # Check for incremental diff or two-SHA git diff
    has_incr_diff = any(INCR_DIFF_PAT.search(t[1]) for t in tools)
    has_two_sha = any(TWO_SHA_PAT.search(t[1]) for t in tools if t[0] == "use")
    if has_incr_diff or has_two_sha: return "incremental", invoked
    # Check if the review file check said not found
    review_results = [t[1] for t in tools if t[0] == "result"]
    any_not_found = any(NOT_FOUND_PAT.search(r) for r in review_results if REVIEW_FILE_PAT.search(r) or "review" in r.lower())
    if any_not_found and not has_incr_diff: return "fell-back", invoked
    return "unknown", invoked

def cmd_fallback(paths, as_json=False):
    results, errors = [], []
    for p in paths:
        try:
            events, skipped = _read_jsonl(p)
            mode, invoked = classify_mode(events)
        except (OSError, ValueError) as e:  # missing, a directory, unreadable, non-UTF-8
            errors.append({"path": p, "error": f"{type(e).__name__}: {e}"}); continue
        except Exception as e:  # a bug, not bad input: report it with its location, never swallow it
            errors.append({"path": p, "error": f"internal {_where(e)}"}); continue
        results.append({"path": os.path.basename(p), "mode": mode, "invoked": invoked, "skipped_lines": skipped})
    modes = [r["mode"] for r in results]
    invoked_runs = [r for r in results if r["invoked"]]
    fb = sum(1 for r in invoked_runs if r["mode"] == "fell-back")
    inc = sum(1 for r in invoked_runs if r["mode"] == "incremental")
    unk = sum(1 for r in invoked_runs if r["mode"] == "unknown")
    full_req = modes.count("full-requested")
    inv_total = len(invoked_runs)
    rate = fb / inv_total if inv_total else 0
    delta = "n/a (no incremental runs)" if inc == 0 else "computed"
    if as_json:
        json.dump({"sessions": results, "total": len(results), "invoked": inv_total,
                    "fell_back": fb, "incremental": inc, "unknown": unk,
                    "full_requested": full_req, "fallback_rate": round(rate, 3),
                    "extra_tokens_delta": delta, "errors": errors}, sys.stdout, indent=2)
    else:
        print("| mode | count |")
        print("|------|-------|")
        print(f"| invoked incremental | {inv_total} |")
        print(f"| → incremental | {inc} |")
        print(f"| → fell-back | {fb} |")
        print(f"| → unknown | {unk} |")
        print(f"| full-requested | {full_req} |")
        print(f"| total | {len(results)} |")
        print(f"| fallback rate (invoked) | {rate:.1%} |")
        print(f"| extra tokens delta | {delta} |")
        skipped = sum(r["skipped_lines"] for r in results)
        print(f"| skipped (unparseable) lines | {skipped} |")
        print(f"| unreadable files | {len(errors)} |")
        if skipped:
            print(f"warning: {skipped} unparseable transcript line(s) excluded", file=sys.stderr)
    for e in errors:
        print(f"error: {e['path']}: {e['error']}", file=sys.stderr)
    return 2 if errors else 0

def _where(e):
    """Type, message and the raising line of an unexpected exception."""
    tb = traceback.extract_tb(e.__traceback__)
    loc = f" at line {tb[-1].lineno} ({tb[-1].name})" if tb else ""
    return f"{type(e).__name__}: {e}{loc}"

class GhNotFound(Exception):
    pass

def _gh_api(endpoint):
    fixture_dir = os.environ.get("REVIEW_ROUNDS_GH_FIXTURES")
    if fixture_dir:
        safe = endpoint.replace("/", "_").replace("?", "_")
        fp = os.path.join(fixture_dir, safe + ".json")
        if not os.path.exists(fp):
            raise RuntimeError(f"fixture missing: {fp}")
        with open(fp, encoding="utf-8") as fh:
            return json.load(fh)
    sep = "?" if "?" not in endpoint else "&"
    r = subprocess.run(["gh", "api", endpoint + sep + "per_page=100", "--paginate"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        if re.search(r"HTTP 404|Not Found", r.stderr): raise GhNotFound(endpoint)
        raise RuntimeError(f"gh api failed: {r.stderr[:200]}")
    # gh --paginate concatenates JSON arrays: [...][...] → parse each
    raw = r.stdout.strip()
    results = []
    decoder = json.JSONDecoder()
    pos = 0
    while pos < len(raw):
        while pos < len(raw) and raw[pos] in " \t\r\n": pos += 1
        if pos >= len(raw): break
        obj, end = decoder.raw_decode(raw, pos)
        if isinstance(obj, list): results.extend(obj)
        else: results.append(obj)
        pos = end
    if len(results) == 1 and isinstance(results[0], dict): return results[0]
    return results

FOOTER_PAT = re.compile(r"Generated-by: prp-review-agents v[\d.]+ run=(\S+) pass=(\S+)")
CI_COUNT_PAT = re.compile(r"^### (Critical|Important) Issues? \((\d+)", re.MULTILINE)
FINDING_TITLE_PAT = re.compile(r"^(?:[-*]|\d+\.)\s+\*\*(.+?)\*\*", re.MULTILINE)
NEXT_HEADING_PAT = re.compile(r"^#{1,3} ", re.MULTILINE)
TABLE_ROW_PAT = re.compile(r"^\|([^|\n]*)\|([^|\n]*)\|", re.MULTILINE)

def _section_titles(text):
    """Finding titles in one C/I section: bullet titles, or the first sentence
    of the second column of a findings table (header and separator skipped)."""
    titles = [m.group(1) for m in FINDING_TITLE_PAT.finditer(text)]
    for m in TABLE_ROW_PAT.finditer(text):
        first, second = m.group(1).strip(), m.group(2).strip()
        if not second or set(second) <= set("-: ") or first.lower() == "severity":
            continue
        titles.append(re.split(r"(?<=[.!?])\s", second, maxsplit=1)[0])
    return titles

def _section(body, m):
    """Text of the section whose heading match is m, up to the next heading."""
    nxt = NEXT_HEADING_PAT.search(body, m.end())
    return body[m.end():nxt.start() if nxt else len(body)]

def _normalise_title(t):
    t = re.sub(r"^[\w/.-]+:\d+[-:]\d*\s*", "", t.strip())
    return re.sub(r"[^\w\s]", "", t.lower()).strip()

def _rounds_from_comments(pr_num, comments):
    """Group per-pass comments into rounds by run id. Raises on a malformed comment."""
    rounds = {}
    for i, c in enumerate(comments):
        if not isinstance(c, dict):
            raise TypeError(f"issues/{pr_num}/comments[{i}] is not an object")
        body = c.get("body")
        if not isinstance(body, str):
            raise TypeError(f"issues/{pr_num}/comments[{i}].body is not a string")
        for m in FOOTER_PAT.finditer(body):
            run_id = m.group(1)
            if run_id not in rounds:
                rounds[run_id] = {"run_id": run_id, "passes": [], "has_ci": False, "families": set()}
            rounds[run_id]["passes"].append(m.group(2))
            for cm in CI_COUNT_PAT.finditer(body):
                if int(cm.group(2)) > 0:
                    rounds[run_id]["has_ci"] = True
                    for title in _section_titles(_section(body, cm)):
                        rounds[run_id]["families"].add(_normalise_title(title))
    return list(rounds.values())

def cmd_rounds(repo, pr_numbers, as_json=False):
    results = []
    for pr_num in pr_numbers:
        try:
            pr_info = _gh_api(f"repos/{repo}/pulls/{pr_num}")
            if not isinstance(pr_info, dict) or "number" not in pr_info:
                raise RuntimeError(f"unexpected pulls/{pr_num} response shape")
            if not pr_info.get("merged_at"):
                results.append({"pr": pr_num, "status": "unmerged", "rounds": []}); continue
            comments = _gh_api(f"repos/{repo}/issues/{pr_num}/comments")
            if isinstance(comments, dict): comments = [comments]
            if not isinstance(comments, list):
                raise RuntimeError(f"unexpected issues/{pr_num}/comments response shape")
            round_list = _rounds_from_comments(pr_num, comments)
        except GhNotFound:
            results.append({"pr": pr_num, "status": "not-found", "rounds": []}); continue
        except (RuntimeError, OSError, ValueError, TypeError) as e:
            results.append({"pr": pr_num, "status": "error", "error": f"{type(e).__name__}: {e}", "rounds": []}); continue
        except Exception as e:  # a bug, not bad input: report it with its location, never swallow it
            results.append({"pr": pr_num, "status": "error", "error": f"internal {_where(e)}", "rounds": []}); continue
        prev_families = set()
        for rd in round_list:
            if len(rd["passes"]) < 3:
                rd["class"] = "c"
            elif rd["has_ci"]:
                if rd["families"] & prev_families:
                    rd["class"] = "b"
                else:
                    rd["class"] = "a"
            else:
                rd["class"] = "clean"
            prev_families = rd["families"]
            rd["families"] = sorted(rd["families"])
        results.append({"pr": pr_num, "status": "merged", "rounds": round_list})
    if as_json:
        json.dump(results, sys.stdout, indent=2)
    else:
        for r in results:
            if r["status"] == "error":
                print(f"PR #{r['pr']}: ERROR {r['error']}")
                continue
            if r["status"] in ("unmerged", "not-found"):
                print(f"PR #{r['pr']}: {r['status']} (excluded)")
                continue
            classes = [rd["class"] for rd in r["rounds"]]
            print(f"\nPR #{r['pr']}: {len(r['rounds'])} round(s) — a={classes.count('a')} b={classes.count('b')} c={classes.count('c')} clean={classes.count('clean')}")
            print("| round | passes | class | families |")
            print("|-------|--------|-------|----------|")
            for i, rd in enumerate(r["rounds"], 1):
                print(f"| {i} | {len(rd['passes'])} | {rd['class']} | {','.join(rd['families'][:3])} |")
    errors = [r for r in results if r["status"] == "error"]
    for r in errors:
        print(f"error: PR #{r['pr']}: {r['error']}", file=sys.stderr)
    return 2 if errors else 0

if __name__ == "__main__":
    args = sys.argv[1:]
    as_json = "--json" in args
    if as_json: args.remove("--json")
    if not args:
        print(__doc__, file=sys.stderr); sys.exit(1)
    cmd = args[0]
    if cmd == "fallback":
        if not args[1:]:
            print("error: fallback needs at least one transcript path", file=sys.stderr); sys.exit(1)
        sys.exit(cmd_fallback(args[1:], as_json))
    elif cmd == "rounds":
        repo = None; prs = []
        i = 1
        while i < len(args):
            if args[i] in ("--repo", "--prs"):
                if i + 1 >= len(args) or args[i+1].startswith("--"):
                    print(f"error: {args[i]} needs a value", file=sys.stderr); sys.exit(1)
                if args[i] == "--repo": repo = args[i+1]
                else:
                    try: prs = [int(x) for x in args[i+1].split(",")]
                    except ValueError:
                        print(f"error: --prs must be comma-separated integers, got {args[i+1]!r}", file=sys.stderr); sys.exit(1)
                i += 2
            else: i += 1
        if not repo or not prs:
            print("error: --repo and --prs required", file=sys.stderr); sys.exit(1)
        sys.exit(cmd_rounds(repo, prs, as_json))
    else:
        print(f"unknown command: {cmd}", file=sys.stderr); sys.exit(1)

#!/usr/bin/env python3
"""Read-only review rounds report for prp-framework#160 AC0.4.
Never writes: local transcript reads only. (The `rounds` subcommand, which
reads gh api, ships in a stacked PR.)

Fallback classifier (tool-event based): a run whose first prompt carries
--since-last-review is 'invoked'; any other run is 'full-requested' and is
excluded from the fallback rate. For an invoked run, a tool event that
reads pr-N-incremental.diff or runs a two-SHA `git diff A B` / `A...B` makes
it 'incremental'; otherwise a tool result that mentions a review file (or the
word "review") and reports not-found makes it 'fell-back'; anything else is
'unknown'.

Errors are never reported as data, and one bad unit never stops the batch:
an unreadable transcript (missing, a directory, non-UTF-8) is listed under
'errors' and excluded from the counts; a line that is not a JSON object
counts as a skipped line.
Exit codes: 0 = all files read, 2 = at least one file errored, 1 = usage.

Usage:
  python3 -I scripts/bench/review-rounds.py fallback [--json] <session.jsonl ...>
"""
import json, os, re, sys, traceback

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
    else:
        print(f"unknown command: {cmd}", file=sys.stderr); sys.exit(1)

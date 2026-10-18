#!/usr/bin/env python3
"""Read-only review rounds report for prp-framework#160 AC0.4.
Never writes: local transcript reads only. (The `rounds` subcommand, which
reads gh api, ships in a stacked PR.)

Fallback classifier (tool-event based): a run whose first prompt carries
--since-last-review is 'invoked'; any other run is 'full-requested' and is
excluded from the fallback rate. Each tool command is paired with its own
result. An invoked run is 'incremental' when a command on pr-N-incremental.diff
or a two-SHA `git diff A B` / `A...B` did not fail with not-found; else
'fell-back' when a command on the review file or .prp-output/reviews failed
with not-found, or the assistant says "No previous review found" / "Running
full review"; anything else is 'unknown'. (AC0.4's extra-tokens delta, via
review-cost.py, ships with `rounds` in the stacked PR.)

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

    {"type": str, "text": str,
     "blocks": [{"type": str, "text": str, "command": str, "content": str, "id": str, "tool_use_id": str}]}
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
                           "command": command, "content": _text_of(b.get("content")),
                           "id": _str(b.get("id")), "tool_use_id": _str(b.get("tool_use_id"))})
    return {"type": _str(obj.get("type")), "text": _str(content), "blocks": blocks}

def _first_prompt(events):
    for e in events:
        if e["type"] not in ("human", "user"): continue
        if e["text"]: return e["text"]
        for block in e["blocks"]:
            if block["type"] == "text":
                return block["text"]
    return ""

REVIEW_FILE_PAT = re.compile(r"pr-\d+-agents-review\.md|\.prp-output/reviews\b")
INCR_DIFF_PAT = re.compile(r"pr-\d+-incremental\.diff")
TWO_SHA_PAT = re.compile(r"git diff [0-9a-f]{7,40}[\s.]+[0-9a-f]{7,40}")
NOT_FOUND_PAT = re.compile(r"NOT_FOUND|No such file|not found|cannot access", re.I)
FALLBACK_SAY_PAT = re.compile(r"No previous review found|Running full review")  # AC0.4 phrases

def _tool_calls(events):
    """[(command, result)] for every tool_use, in order.

    A result is paired by tool_use_id when the use has an id and a result carries it;
    otherwise with the next unpaired result in order. A use with no result gets None.
    """
    calls, by_id, unpaired = [], {}, []
    for e in events:
        for block in e["blocks"]:
            if block["type"] == "tool_use":
                calls.append([block["command"], None])
                if block["id"]: by_id[block["id"]] = len(calls) - 1
                unpaired.append(len(calls) - 1)
            elif block["type"] == "tool_result":
                i = by_id.pop(block["tool_use_id"], None) if block["tool_use_id"] else None
                if i is None and unpaired: i = unpaired[0]
                if i is not None:
                    calls[i][1] = block["content"]
                    if i in unpaired: unpaired.remove(i)
    return [tuple(c) for c in calls]

def _failed(result):
    return result is not None and bool(NOT_FOUND_PAT.search(result))

def _assistant_text(events):
    for e in events:
        if e["type"] != "assistant": continue
        yield e["text"]
        for block in e["blocks"]:
            if block["type"] == "text": yield block["text"]

def classify_mode(events):
    """'full-requested' | 'incremental' | 'fell-back' | 'unknown', and whether invoked.

    incremental: a command that reads/writes pr-N-incremental.diff or runs a two-SHA
      git diff, whose own result is not a not-found (a failed `cat` of the diff does not count);
    fell-back: a command on the review file or .prp-output/reviews whose own result is
      not-found, or the assistant says "No previous review found" / "Running full review";
    unknown: anything else (never counted as incremental).
    """
    prompt = _first_prompt(events)
    invoked = "--since-last-review" in prompt
    if not invoked: return "full-requested", invoked
    calls = _tool_calls(events)
    if any((INCR_DIFF_PAT.search(c) or TWO_SHA_PAT.search(c)) and not _failed(r) for c, r in calls):
        return "incremental", invoked
    if any(REVIEW_FILE_PAT.search(c) and _failed(r) for c, r in calls) \
            or any(FALLBACK_SAY_PAT.search(t) for t in _assistant_text(events)):
        return "fell-back", invoked
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
    if as_json:
        json.dump({"sessions": results, "total": len(results), "invoked": inv_total,
                    "fell_back": fb, "incremental": inc, "unknown": unk,
                    "full_requested": full_req, "fallback_rate": round(rate, 3),
                    "errors": errors}, sys.stdout, indent=2)
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

#!/usr/bin/env python3
"""Read-only review rounds report for prp-framework#160 AC0.4.
Never writes: local transcript reads only. (The `rounds` subcommand, which
reads gh api, ships in a stacked PR.)

Fallback classifier (tool-event based): a run whose first prompt carries
--since-last-review is 'invoked'; any other run is 'full-requested' and is
excluded from the fallback rate. Each tool command gets one outcome from its
own paired result: ok, failed (a not-found about the review file or diff
itself), error (another is_error result) or missing (no result); error and
missing are never evidence. An invoked run is 'incremental' when a command on
pr-N-incremental.diff or a two-SHA `git diff A B` / `A...B` is ok; else
'fell-back' when a command on the review file or .prp-output/reviews failed,
or the assistant says "No previous review found" / "Running
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
     "blocks": [{"type": str, "text": str, "command": str, "content": str, "id": str, "tool_use_id": str,
                 "is_error": bool}]}
    Any field of the wrong type becomes "" / [] here, so the classifier never sees raw JSON.
    """
    msg = obj.get("message")
    msg = msg if isinstance(msg, dict) else {}
    content = msg.get("content")
    blocks = []
    if isinstance(content, list):
        for b in content:
            if not isinstance(b, dict): continue
            # Evidence is a shell command or the path a Read opened. Another tool's input (an
            # Agent prompt, a Write body) that merely names a review path is not a command on it.
            inp = b.get("input") if isinstance(b.get("input"), dict) else {}
            cmd, path = inp.get("command"), inp.get("file_path")
            command = cmd if isinstance(cmd, str) else \
                path if b.get("name") == "Read" and isinstance(path, str) else ""
            blocks.append({"type": _str(b.get("type")), "text": _str(b.get("text")),
                           "command": command, "content": _text_of(b.get("content")),
                           "id": _str(b.get("id")), "tool_use_id": _str(b.get("tool_use_id")),
                           "is_error": b.get("is_error") is True})
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

OK, FAILED, ERROR, MISSING = "ok", "failed", "error", "missing"
BARE_NOT_FOUND_PAT = re.compile(r"NOT_FOUND\b.{0,80}")
TARGET_PAT = re.compile(r"pr-\d+-agents-review\.md|\.prp-output/reviews\b|pr-\d+-incremental\.diff")

def _outcome(content, is_error):
    """FAILED only on a not-found about the target itself: a line that names the review file,
    the reviews dir or the incremental diff, a bare NOT_FOUND token line, or an is_error result
    that says not-found. Not-found text inside command OUTPUT (a diff or a file listing code
    that contains the words) is not a failure. Any other is_error result is ERROR."""
    lines = [ln.strip() for ln in content.splitlines() if NOT_FOUND_PAT.search(ln)]
    if any(TARGET_PAT.search(ln) or BARE_NOT_FOUND_PAT.fullmatch(ln) for ln in lines): return FAILED
    if is_error: return FAILED if lines else ERROR
    return OK

def _tool_calls(events):
    """([(command, outcome)] for every tool_use in order, orphan_result_count).

    outcome is MISSING (no paired result), else _outcome(): FAILED (a not-found about the
    target), ERROR (another is_error result) or OK. MISSING and ERROR are never evidence.
    Pairing: a result with a tool_use_id pairs only with the earliest unpaired use of that
    id (a resumed session replays history, so one id can appear more than once); a result
    without one pairs with the earliest unpaired use that has no id either. A result
    that pairs with nothing is an orphan: counted, never attached by guess.
    """
    cmds, results, by_id, idless, orphans = [], [], {}, [], 0
    for e in events:
        for block in e["blocks"]:
            if block["type"] == "tool_use":
                cmds.append(block["command"]); results.append(None)
                if block["id"]: by_id.setdefault(block["id"], []).append(len(cmds) - 1)
                else: idless.append(len(cmds) - 1)
            elif block["type"] == "tool_result":
                q = by_id.get(block["tool_use_id"]) if block["tool_use_id"] else idless
                i = q.pop(0) if q else None
                if i is None: orphans += 1
                else: results[i] = _outcome(block["content"], block["is_error"])
    calls = [(c, MISSING if r is None else r) for c, r in zip(cmds, results)]
    return calls, orphans

def _assistant_text(events):
    for e in events:
        if e["type"] != "assistant": continue
        yield e["text"]
        for block in e["blocks"]:
            if block["type"] == "text": yield block["text"]

def classify_mode(events):
    """('full-requested' | 'incremental' | 'fell-back' | 'unknown', invoked, orphan_results).

    incremental: a command on pr-N-incremental.diff or a two-SHA git diff with outcome OK;
    fell-back: a command on the review file or .prp-output/reviews with outcome FAILED, or
      the assistant says "No previous review found" / "Running full review";
    unknown: anything else. MISSING and ERROR outcomes never count as evidence.
    """
    prompt = _first_prompt(events)
    invoked = "--since-last-review" in prompt
    calls, orphans = _tool_calls(events)
    if not invoked: return "full-requested", invoked, orphans
    if any(o == OK and (INCR_DIFF_PAT.search(c) or TWO_SHA_PAT.search(c)) for c, o in calls):
        return "incremental", invoked, orphans
    if any(o == FAILED and REVIEW_FILE_PAT.search(c) for c, o in calls) \
            or any(FALLBACK_SAY_PAT.search(t) for t in _assistant_text(events)):
        return "fell-back", invoked, orphans
    return "unknown", invoked, orphans

def cmd_fallback(paths, as_json=False):
    results, errors = [], []
    for p in paths:
        try:
            events, skipped = _read_jsonl(p)
            mode, invoked, orphans = classify_mode(events)
        except (OSError, ValueError) as e:  # missing, a directory, unreadable, non-UTF-8
            errors.append({"path": p, "error": f"{type(e).__name__}: {e}"}); continue
        except Exception as e:  # a bug, not bad input: report it with its location, never swallow it
            errors.append({"path": p, "error": f"internal {_where(e)}"}); continue
        results.append({"path": os.path.basename(p), "mode": mode, "invoked": invoked,
                        "skipped_lines": skipped, "orphan_results": orphans})
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
        print(f"| orphan tool results | {sum(r['orphan_results'] for r in results)} |")
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

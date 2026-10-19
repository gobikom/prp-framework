#!/usr/bin/env python3
"""Read-only review rounds report for prp-framework#160 AC0.4 (#176, re-route of #173).
Never writes: local transcript reads only. (The `rounds` subcommand, which
reads gh api, ships in a stacked PR.)

Invariant: every value read from a transcript record passes through ONE
boundary, the _norm_* functions. They return each field as a value of its
expected type or the sentinel UNKNOWN, and record the field's name. No other
function reads raw JSON. A session with any UNKNOWN field is mode 'unknown',
never incremental / fell-back, and lists the fields in 'unknown_fields'.
Expected types come from 212 real review sessions (plan
.prp-output/plans/176-review-rounds-typed.plan.md).

Invocation reader (#177b): 'invoked' is True or False ONLY when the session
has exactly one positively identified review invocation — a user record whose
whole str content is this skill's slash envelope (command-message /
command-name / command-args), or an assistant Skill tool_use whose input.skill
is this skill — and the value is read ONLY from that invocation's own args
(the incremental flag as a whole whitespace token). Every other case is mode
'unknown', invoked null, with a named reason in 'unknown_fields', the first by
malformed > skill > args > multiple > boundary-field > none; a boundary
UNKNOWN field makes the session undecidable for both layers. One identified
invocation without the flag is 'full-requested'. The fallback rate is a lower
bound over identified invocations; undecidable sessions are excluded.
Each tool command gets one outcome from its own paired
result (paired by tool_use_id, earliest unpaired use first): ok, failed (a
not-found about the review file or diff itself), error (another is_error
result) or missing (no result); error and missing are never evidence. An
invoked session is 'incremental' when a command on pr-N-incremental.diff or a
two-SHA `git diff A B` / `A...B` is ok; else 'fell-back' when a command on
the review file or .prp-output/reviews failed, or the assistant says
"No previous review found" / "Running full review"; anything else is
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


class _Unknown:
    """A field that was absent where required, or of an unexpected type."""
    __slots__ = ()
    def __repr__(self): return "UNKNOWN"
    def __bool__(self): raise TypeError("UNKNOWN has no truth value; test `is UNKNOWN`")

UNKNOWN = _Unknown()
_ABSENT = object()


def _read_jsonl(path):
    lines, skipped = [], 0
    with open(path, encoding="utf-8") as fh:
        raw_lines = fh.readlines()
    for line in raw_lines:
        line = line.strip()
        if not line: continue
        try: obj = json.loads(line)
        except json.JSONDecodeError: skipped += 1; continue
        if isinstance(obj, dict): lines.append(_norm_event(obj))
        else: skipped += 1  # valid JSON but not an event object
    return lines, skipped

# --- the boundary: the only code that reads raw transcript JSON ---------------
def _is_str(v): return isinstance(v, str)
def _is_id(v): return isinstance(v, str) and v != ""
def _is_dict(v): return isinstance(v, dict)
def _is_bool(v): return type(v) is bool  # isinstance(True, int) is true, so no isinstance here

def _norm_typed(v, ok, field, unk):
    if ok(v): return v
    unk.append(field)
    return UNKNOWN

def _norm_event(obj):
    """Raw record -> {"type": str|UNKNOWN, "text": str, "blocks": [...], "unknown": [field, ...]}.

    An absent `message` or `message.content` is legit (system/summary records): no text, no blocks.
    """
    unk = []
    etype = _norm_typed(obj.get("type", _ABSENT), _is_str, "type", unk)
    text, blocks = "", []
    msg = obj.get("message", _ABSENT)
    if msg is not _ABSENT and not isinstance(msg, dict):
        unk.append("message")
    elif msg is not _ABSENT:
        content = msg.get("content", _ABSENT)
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            for b in content:
                if isinstance(b, dict): blocks.append(_norm_block(b, unk))
                else: unk.append("block")
        elif content is not _ABSENT:
            unk.append("message.content")
    return {"type": etype, "text": text, "blocks": blocks, "unknown": unk}

def _norm_block(b, unk):
    """One content block. Unrecognised block-type strings (thinking, tool_addition, ...) carry no fields."""
    btype = b.get("type", _ABSENT)
    if not isinstance(btype, str):
        unk.append("block.type")
        return {"type": UNKNOWN}
    out = {"type": btype}
    if btype == "text":
        out["text"] = _norm_typed(b.get("text", _ABSENT), _is_str, "text.text", unk)
    elif btype == "tool_use":
        out["id"] = _norm_typed(b.get("id", _ABSENT), _is_id, "tool_use.id", unk)
        name = _norm_typed(b.get("name", _ABSENT), _is_str, "tool_use.name", unk)
        out["name"] = name
        inp = _norm_typed(b.get("input", _ABSENT), _is_dict, "tool_use.input", unk)
        if name == "Skill":
            # The invocation reader's fields (#177b): kept typed; absent is never
            # normalised to "" (an empty arg list is a real, decidable value).
            if inp is UNKNOWN:
                out["skill"] = out["args"] = UNKNOWN
            else:
                sk, ag = inp.get("skill", _ABSENT), inp.get("args", _ABSENT)
                out["skill"] = sk if _is_str(sk) else UNKNOWN
                out["args"] = ag if _is_str(ag) else UNKNOWN
        out["command"] = _norm_command(name, inp, unk)
    elif btype == "tool_result":
        out["tool_use_id"] = _norm_typed(b.get("tool_use_id", _ABSENT), _is_id, "tool_result.tool_use_id", unk)
        ie = b.get("is_error", _ABSENT)
        # Absent is how a success is written (2655 of 6298 real results); only a real bool is read.
        out["is_error"] = False if ie is _ABSENT else _norm_typed(ie, _is_bool, "tool_result.is_error", unk)
        out["content"] = _norm_result_text(b.get("content", _ABSENT), unk)
    return out

def _norm_command(name, inp, unk):
    """Evidence is a shell command or the path a Read opened; another tool's input is not a command.
    Returns str, None (a tool with no command) or UNKNOWN."""
    if name is UNKNOWN or inp is UNKNOWN: return UNKNOWN
    if name == "Read":
        return _norm_typed(inp.get("file_path", _ABSENT), _is_str, "Read.file_path", unk)
    if name == "Bash" or "command" in inp:
        return _norm_typed(inp.get("command", _ABSENT), _is_str, f"{name}.command", unk)
    return None

def _norm_result_text(c, unk):
    """A result's text: a string as is; a list joins the text of its type=="text" items."""
    if isinstance(c, str): return c
    if not isinstance(c, list):
        unk.append("tool_result.content")
        return UNKNOWN
    parts = []
    for x in c:
        if not isinstance(x, dict):
            unk.append("tool_result.content[]")
            return UNKNOWN
        if x.get("type", _ABSENT) == "text":
            t = x.get("text", _ABSENT)
            if not isinstance(t, str):
                unk.append("tool_result.content[].text")
                return UNKNOWN
            parts.append(t)
    return "\n".join(parts)
# --- end of the boundary ------------------------------------------------------

# --- the invocation reader (#177b): the only code that decides 'invoked' ----------
REVIEW_SKILL = "prp-core:prp-review-agents"
NAME_TAG_PAT = re.compile(r"<command-name>/?prp-core:prp-review-agents</command-name>")
ENVELOPE_PAT = re.compile(
    r"\A\s*<command-message>[^<]*</command-message>\s*"
    r"<command-name>/?prp-core:prp-review-agents</command-name>\s*"
    r"<command-args>([^<]*)</command-args>\s*\Z")
FLAG = "--since-last-review"
INVOCATION_MALFORMED = "invocation.malformed"
INVOCATION_SKILL = "invocation.skill"
INVOCATION_ARGS = "invocation.args"
INVOCATION_MULTIPLE = "invocation.multiple"
INVOCATION_BOUNDARY = "invocation.boundary-field"
INVOCATION_NONE = "invocation.none"
INVOCATION_PRECEDENCE = (INVOCATION_MALFORMED, INVOCATION_SKILL, INVOCATION_ARGS,
                         INVOCATION_MULTIPLE)

def _invocation(events):
    """(evidence_args, reasons): the args of every positively identified review
    invocation, and every invocation reason that applies.

    Evidence: a user record whose whole str content is the slash envelope (args =
    its command-args), or an assistant Skill tool_use for the review skill (args =
    input.args). The review name tag anywhere else in user text — quoted in a
    brief, doubled, missing its args tag, or inside a list-content text block —
    is malformed: a text block is never evidence. An undecidable Skill input
    (input not a dict, skill absent or not a str) might be the review, so it is
    a reason, never 'some other skill'."""
    evidence, reasons = [], set()
    for e in events:
        t = e["type"]
        if t == "user" or t == "human":
            if e["blocks"]:
                for blk in e["blocks"]:
                    if blk["type"] == "text" and isinstance(blk["text"], str) \
                            and NAME_TAG_PAT.search(blk["text"]):
                        reasons.add(INVOCATION_MALFORMED)
            else:
                txt = e["text"]
                m = ENVELOPE_PAT.match(txt)
                if m: evidence.append(m.group(1))
                elif NAME_TAG_PAT.search(txt): reasons.add(INVOCATION_MALFORMED)
        elif t == "assistant":
            for blk in e["blocks"]:
                if blk["type"] == "tool_use" and blk["name"] == "Skill":
                    if blk["skill"] is UNKNOWN:
                        reasons.add(INVOCATION_SKILL)
                    elif blk["skill"] == REVIEW_SKILL:
                        if isinstance(blk["args"], str): evidence.append(blk["args"])
                        else: reasons.add(INVOCATION_ARGS)
    if len(evidence) > 1: reasons.add(INVOCATION_MULTIPLE)
    return evidence, reasons

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
    the reviews dir or the incremental diff, or a bare NOT_FOUND token line. Not-found text
    inside command OUTPUT, or an is_error result about some other path, is not a failure of
    the target: an is_error result is ERROR, anything else OK."""
    lines = [ln.strip() for ln in content.splitlines() if NOT_FOUND_PAT.search(ln)]
    if any(TARGET_PAT.search(ln) or BARE_NOT_FOUND_PAT.fullmatch(ln) for ln in lines): return FAILED
    return ERROR if is_error else OK

def _tool_calls(events):
    """([(command, outcome)] for every tool_use in order, orphan_result_count). Typed events only.

    Pairing: a result pairs only with the earliest unpaired use of its tool_use_id (a resumed
    session replays history, so one id can appear more than once). A result that pairs with
    nothing is an orphan: counted, never attached by guess. A use with no result is MISSING.
    """
    cmds, results, by_id, orphans = [], [], {}, 0
    for e in events:
        for block in e["blocks"]:
            if block["type"] == "tool_use":
                cmds.append(block["command"]); results.append(None)
                by_id.setdefault(block["id"], []).append(len(cmds) - 1)
            elif block["type"] == "tool_result":
                q = by_id.setdefault(block["tool_use_id"], [])
                if q: results[q.pop(0)] = _outcome(block["content"], block["is_error"])
                else: orphans += 1
    calls = [(c, MISSING if r is None else r) for c, r in zip(cmds, results)]
    return calls, orphans

def _assistant_text(events):
    for e in events:
        if e["type"] != "assistant": continue
        yield e["text"]
        for block in e["blocks"]:
            if block["type"] == "text": yield block["text"]

def classify_mode(events):
    """(mode, invoked, orphan_results, unknown_fields, invocation_reason).

    mode: 'unknown' whenever any boundary field is UNKNOWN or any invocation
    reason applies (pairing not attempted); 'full-requested' when the one
    identified invocation lacks the flag; else the evidence ladder as in the
    module doc. invoked: True/False only from the one identified invocation's
    own args, else None. invocation_reason: the first reason by
    malformed > skill > args > multiple > boundary-field > none, else None.
    """
    evidence, reasons = _invocation(events)
    boundary_unknown = {f for e in events for f in e["unknown"]}
    unknown_fields = sorted(boundary_unknown | reasons)
    reason = next((r for r in INVOCATION_PRECEDENCE if r in reasons), None)
    if reason is None and boundary_unknown: reason = INVOCATION_BOUNDARY
    if reason is None and not evidence: reason = INVOCATION_NONE
    if reason is not None:
        return "unknown", None, None, unknown_fields, reason
    if FLAG not in evidence[0].split():
        return "full-requested", False, None, unknown_fields, None
    calls, orphans = _tool_calls(events)
    cmd_calls = [(c, o) for c, o in calls if isinstance(c, str)]
    if any(o == OK and (INCR_DIFF_PAT.search(c) or TWO_SHA_PAT.search(c)) for c, o in cmd_calls):
        return "incremental", True, orphans, unknown_fields, None
    if any(o == FAILED and REVIEW_FILE_PAT.search(c) for c, o in cmd_calls) \
            or any(FALLBACK_SAY_PAT.search(t) for t in _assistant_text(events)):
        return "fell-back", True, orphans, unknown_fields, None
    return "unknown", True, orphans, unknown_fields, None

def cmd_fallback(paths, as_json=False):
    results, errors = [], []
    for p in paths:
        try:
            events, skipped = _read_jsonl(p)
            mode, invoked, orphans, unknown_fields, inv_reason = classify_mode(events)
        except (OSError, ValueError) as e:  # missing, a directory, unreadable, non-UTF-8
            errors.append({"path": p, "error": f"{type(e).__name__}: {e}"}); continue
        except Exception as e:  # a bug, not bad input: report it with its location, never swallow it
            errors.append({"path": p, "error": f"internal {_where(e)}"}); continue
        results.append({"path": os.path.basename(p), "mode": mode, "invoked": invoked,
                        "invocation_reason": inv_reason, "skipped_lines": skipped,
                        "orphan_results": orphans, "unknown_fields": unknown_fields})
    invoked_runs = [r for r in results if r["invoked"] is True]
    fb = sum(1 for r in invoked_runs if r["mode"] == "fell-back")
    inc = sum(1 for r in invoked_runs if r["mode"] == "incremental")
    unk = sum(1 for r in invoked_runs if r["mode"] == "unknown")
    full_req = sum(1 for r in results if r["mode"] == "full-requested")
    undecided = sum(1 for r in results if r["invoked"] is None)
    with_unknown = sum(1 for r in results if r["unknown_fields"])
    inv_total = len(invoked_runs)
    rate = fb / inv_total if inv_total else 0
    orphans = sum(r["orphan_results"] or 0 for r in results)
    if as_json:
        json.dump({"sessions": results, "total": len(results), "invoked": inv_total,
                   "fell_back": fb, "incremental": inc, "unknown": unk,
                   "full_requested": full_req, "undecided": undecided,
                   "sessions_with_unknown_fields": with_unknown,
                   "fallback_rate": round(rate, 3), "errors": errors}, sys.stdout, indent=2)
    else:
        skipped = sum(r["skipped_lines"] for r in results)
        rows = [("invoked incremental", inv_total), ("→ incremental", inc), ("→ fell-back", fb),
                ("→ unknown", unk), ("full-requested", full_req),
                ("undecidable invocation", undecided),
                ("sessions with unknown fields (mode unknown)", with_unknown),
                ("total", len(results)),
                ("fallback rate (lower bound)", f"{rate:.1%} of {inv_total} identified invocations"),
                ("skipped (unparseable) lines", skipped), ("unreadable files", len(errors)),
                ("orphan tool results", orphans)]
        print("| mode | count |\n|------|-------|")
        for k, v in rows: print(f"| {k} | {v} |")
        if skipped:
            print(f"warning: {skipped} unparseable transcript line(s) excluded", file=sys.stderr)
        if undecided:
            print(f"note: the fallback rate is a lower bound — {undecided} session(s) have no "
                  f"positively identified single invocation and are excluded", file=sys.stderr)
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

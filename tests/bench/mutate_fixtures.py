#!/usr/bin/env python3
"""Mutation fixtures for review-rounds.py (#173 I2, #176 typed boundary).

transcripts: for every JSON value inside the given fixtures, write one variant with
that value replaced by each wrong-type value in WRONG. The bats test runs the script
over all variants and asserts it never raises (no traceback, no errors).

field-arms: the #176 invariant table. For each transcript field the classifier reads,
write one variant per value in VALUES (absent included) plus a replayed id, and an
expected.tsv row `name<TAB>field<TAB>mode<TAB>has_unknown_fields`. Expectations are
hand-written below (the test oracle), never derived from the script. `check` compares
a `fallback --json` run with expected.tsv for one field and names every mismatch.

invocation-arms: the #177b invariant table (A1-A27). Variants are spec-built from one
base session (helpers below, not 27 fixture files); expectations are hand-written in
INV_ARMS (the oracle). Writes one file per arm plus invocation-arms.tsv
`arm<TAB>spec<TAB>mode<TAB>invoked<TAB>invocation_reason<TAB>unknown_fields`.
`check-inv` compares a `fallback --json` run with the tsv (exact tuple per arm; the
optional last column asserts unknown_fields) and names every mismatch.

Usage:
  mutate_fixtures.py transcripts <out_dir> <fixture.jsonl ...>   -> prints variant count
  mutate_fixtures.py field-arms <out_dir> <fixtures_dir>          -> prints variant count
  mutate_fixtures.py invocation-arms <out_dir>                    -> prints arm count
  mutate_fixtures.py check <expected.tsv> <out.json> <field>      -> exit 1 on a mismatch
  mutate_fixtures.py check-inv <arms.tsv> <out.json> [arm]        -> exit 1 on a mismatch
Exit 2 when an input file cannot be read.
"""
import copy, json, os, sys

WRONG = [None, 0, 1.5, True, "x", [], ["x"], {}, {"x": 1}]
ABSENT = object()
VALUES = [("absent", ABSENT), ("null", None), ("true", True), ("false", False), ("0", 0),
          ("1", 1), ("str", "x"), ("list", []), ("obj", {})]

# (field, base fixture, 0-based line, path to the value, {value label: "mode flag"}).
# A label not listed expects "unknown 1": the field came out UNKNOWN, so mode is unknown.
# Flag 1 = unknown_fields is non-empty. "unknown 0" = well typed, but no evidence remains.
U = "message", "content", 0
ARMS = [
    ("is_error", "incremental", 5, U + ("is_error",),
     {"absent": "incremental 0", "false": "incremental 0", "true": "unknown 0"}),
    ("is_error", "fell-back-full", 3, U + ("is_error",),
     {"absent": "fell-back 0", "false": "fell-back 0", "true": "fell-back 0"}),
    ("tool_use_id", "incremental", 5, U + ("tool_use_id",), {"str": "unknown 0"}),
    ("tool_use_id", "fell-back-full", 3, U + ("tool_use_id",), {"str": "fell-back 0"}),
    ("content", "incremental", 5, U + ("content",), {"str": "incremental 0", "list": "incremental 0"}),
    ("content", "fell-back-full", 3, U + ("content",), {"str": "fell-back 0", "list": "fell-back 0"}),
    ("command", "incremental", 4, U + ("input", "command"), {"str": "unknown 0"}),
    ("file_path", "read-incremental-diff", 1, U + ("input", "file_path"), {"str": "unknown 0"}),
    ("id", "incremental", 4, U + ("id",), {"str": "unknown 0"}),
    ("name", "incremental", 4, U + ("name",), {"str": "incremental 0"}),
    ("block.type", "incremental", 4, U + ("type",), {"str": "unknown 0"}),
    ("message", "incremental", 4, ("message",), {"absent": "unknown 0", "obj": "unknown 0"}),
    ("message.content", "incremental", 4, ("message", "content"),
     {"absent": "unknown 0", "str": "unknown 0", "list": "unknown 0"}),
]


def _die(msg):
    print(f"error: {msg}", file=sys.stderr); sys.exit(2)


def _read_lines(f):
    try:
        with open(f, encoding="utf-8") as fh:
            return [l.rstrip("\n") for l in fh if l.strip()]
    except (OSError, UnicodeDecodeError) as e:
        _die(f"{f}: {type(e).__name__}: {e}")


def _paths(v, path=()):
    """Every path to a value inside v, the root included."""
    yield path
    if isinstance(v, dict):
        for k, x in v.items():
            yield from _paths(x, path + (k,))
    elif isinstance(v, list):
        for i, x in enumerate(v):
            yield from _paths(x, path + (i,))


def _replaced(v, path, new):
    if not path:
        return new
    v = copy.deepcopy(v)
    cur = v
    for k in path[:-1]:
        cur = cur[k]
    if new is ABSENT: cur.pop(path[-1], None)
    else: cur[path[-1]] = new
    return v


def _write(out_dir, name, lines):
    with open(os.path.join(out_dir, name), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def transcripts(out_dir, files):
    n = 0
    for f in files:
        lines = _read_lines(f)
        for li, line in enumerate(lines):
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            for path in _paths(obj):
                for w in WRONG:
                    out = list(lines)
                    out[li] = json.dumps(_replaced(obj, path, w))
                    n += 1
                    _write(out_dir, f"t{n}.jsonl", out)
    return n


def field_arms(out_dir, fix_dir):
    rows = []
    for field, base, li, path, legit in ARMS:
        lines = _read_lines(os.path.join(fix_dir, base + ".jsonl"))
        try: obj = json.loads(lines[li])
        except (IndexError, ValueError) as e: _die(f"{base}.jsonl line {li}: {e}")
        for label, value in VALUES:
            out = list(lines)
            out[li] = json.dumps(_replaced(obj, path, value))
            name = f"{field}__{label}__{base}.jsonl"
            _write(out_dir, name, out)
            rows.append((name, field, *legit.get(label, "unknown 1").split()))
    # A replayed id: the evidence use and its result written twice (a resumed session).
    lines = _read_lines(os.path.join(fix_dir, "incremental.jsonl"))
    _write(out_dir, "replay__dup__incremental.jsonl", lines + lines[4:6])
    rows.append(("replay__dup__incremental.jsonl", "replay", "incremental", "0"))
    with open(os.path.join(out_dir, "expected.tsv"), "w", encoding="utf-8") as fh:
        fh.writelines("\t".join(r) + "\n" for r in rows)
    return len(rows)


def check(expected_tsv, out_json, field):
    try:
        with open(expected_tsv, encoding="utf-8") as fh:
            rows = [l.rstrip("\n").split("\t") for l in fh if l.strip()]
        with open(out_json, encoding="utf-8") as fh:
            got = {s["path"]: s for s in json.load(fh)["sessions"]}
    except (OSError, ValueError, KeyError, TypeError) as e:
        _die(f"check: {type(e).__name__}: {e}")
    bad, seen = [], 0
    for name, f, mode, flag in rows:
        if f != field: continue
        seen += 1
        s = got.get(name)
        if s is None: bad.append(f"{name}: no session in output"); continue
        if s["mode"] != mode or bool(s["unknown_fields"]) != (flag == "1") \
                or (f == "replay" and s["orphan_results"] != 0):
            bad.append(f"{name}: want mode={mode} unknown_fields={'yes' if flag == '1' else 'none'}, "
                       f"got mode={s['mode']} unknown_fields={s['unknown_fields']} orphans={s['orphan_results']}")
    if not seen: bad.append(f"no expected rows for field {field}")
    for b in bad: print(b)
    return 1 if bad else 0


# --- #177b: the invocation-reader arms A1-A27 -----------------------------------
# One base session (a brief, the invocation, the ladder), spec-built variants.
# Expectations are hand-written here — the oracle — never derived from the script.
REVIEW_SKILL = "prp-core:prp-review-agents"
FLAG = "--since-last-review"
ENV_ARGS = "177 --l2-comments --since-last-review"

def _env(args):
    return (f"<command-message>prp-review-agents</command-message>\n"
            f"<command-name>/{REVIEW_SKILL}</command-name>\n"
            f"<command-args>{args}</command-args>")

def _u(text):
    return {"type": "user", "message": {"content": text}}

def _ub(*blocks):
    return {"type": "user", "message": {"content": list(blocks)}}

def _txt(text):
    return {"type": "text", "text": text}

def _a_use(name, inp, uid):
    return {"type": "assistant",
            "message": {"content": [{"type": "tool_use", "name": name, "input": inp, "id": uid}]}}

def _skill(uid, skill=REVIEW_SKILL, args=FLAG):
    return _a_use("Skill", {"skill": skill, "args": args}, uid)

def _res(uid, content):
    return {"type": "user",
            "message": {"content": [{"type": "tool_result", "tool_use_id": uid, "content": content}]}}

def _a_text(text):
    return {"type": "assistant", "message": {"content": text}}

_BRIEF = "Read /home/goko/.cache/pane-orchestrate/brief-x.md and follow it exactly."
_OK_INCR = [_a_use("Bash", {"command": "cat .prp-output/reviews/pr-42-incremental.diff"}, "tu_1"),
            _res("tu_1", "diff --git a/x b/x")]
_FAIL_REVIEW = [_a_use("Bash", {"command": "test -f .prp-output/reviews/pr-42-agents-review.md"}, "tu_2"),
                _res("tu_2", "NOT_FOUND: pr-42-agents-review.md")]

# (arm, spec, events, mode, invoked, invocation_reason, unknown_fields or "-")
INV_ARMS = [
    ("A1", "no user record",
     [_a_use("Bash", {"command": "cat .prp-output/reviews/pr-42-incremental.diff"}, "tu_1"),
      _a_text("Reviewing.")], "unknown", "None", "invocation.none", "-"),
    ("A2", "first user content is the empty string",
     [_u("")] + _OK_INCR, "unknown", "None", "invocation.none", "-"),
    ("A3", "first user text block is empty (the r2 shape)",
     [_ub(_txt(""))] + _OK_INCR, "unknown", "None", "invocation.none", "-"),
    ("A4", "whitespace-only first user text",
     [_u("   \n  ")] + _OK_INCR, "unknown", "None", "invocation.none", "-"),
    ("A5", "brief with no tag quoting the slash command",
     [_u("Brief: run /prp-core:prp-review-agents 177 --l2-comments on PR 177, then stop.")],
     "unknown", "None", "invocation.none", "-"),
    ("A6", "brief at idx 0, envelope WITH flag at idx 3, ok incremental read",
     [_u(_BRIEF), _u(_env(ENV_ARGS))] + _OK_INCR, "incremental", "True", "-", "-"),
    ("A7", "brief at idx 0, envelope WITHOUT flag",
     [_u(_BRIEF), _u(_env("177 --l2-comments"))] + _OK_INCR, "full-requested", "False", "-", "-"),
    ("A8", "review name tag, no command-args tag",
     [_u("<command-message>prp-review-agents</command-message>\n"
         "<command-name>/prp-core:prp-review-agents</command-name>")],
     "unknown", "None", "invocation.malformed", "-"),
    ("A9", "envelope args --since-last-reviewer",
     [_u(_env("177 --since-last-reviewer"))] + _OK_INCR, "full-requested", "False", "-", "-"),
    ("A10", "Skill call, args with flag, failed review-file read",
     [_u("go review 165"), _skill("tu_s", args=ENV_ARGS)] + _FAIL_REVIEW,
     "fell-back", "True", "-", "-"),
    ("A11", "Skill call, input.args absent",
     [_u("go"), _a_use("Skill", {"skill": REVIEW_SKILL}, "tu_s")],
     "unknown", "None", "invocation.args", "-"),
    ("A12", "Skill call, input.args = 5",
     [_u("go"), _a_use("Skill", {"skill": REVIEW_SKILL, "args": 5}, "tu_s")],
     "unknown", "None", "invocation.args", "-"),
    ("A13", "Skill call for another skill only",
     [_u("go"), _a_use("Skill", {"skill": "prp-core:prp-commit", "args": "1"}, "tu_s")],
     "unknown", "None", "invocation.none", "-"),
    ("A14", "two envelopes, flag mixed",
     [_u(_env(ENV_ARGS)), _u(_env("177 --l2-comments"))],
     "unknown", "None", "invocation.multiple", "-"),
    ("A15", "valid envelope WITH flag + a #176 field UNKNOWN",
     [_u(_env(ENV_ARGS)), _a_use("Bash", {"command": "cat x"}, "tu_1"), _res("tu_1", 5)],
     "unknown", "None", "invocation.boundary-field", "tool_result.content"),
    ("A16", "brief quoting a full envelope WITH flag + real envelope WITHOUT flag",
     [_u("Brief: " + _env(ENV_ARGS)), _u(_env("177 --l2-comments"))],
     "unknown", "None", "invocation.malformed", "-"),
    ("A17", "/compact envelope quoting the review command + flag (no tag)",
     [_u("<command-message>compact</command-message>\n<command-name>/compact</command-name>\n"
         "<command-args>then run /prp-core:prp-review-agents 177 --l2-comments --since-last-review</command-args>")],
     "unknown", "None", "invocation.none", "-"),
    ("A18", "envelope with empty args; flag only in a later plain user text",
     [_u(_env("")), _u("nudge: add --since-last-review next time")],
     "full-requested", "False", "-", "-"),
    ("A19", "envelope with two command-args tags",
     [_u("<command-message>prp-review-agents</command-message>\n"
         "<command-name>/prp-core:prp-review-agents</command-name>\n"
         "<command-args>a</command-args>\n<command-args>b</command-args>")],
     "unknown", "None", "invocation.malformed", "-"),
    ("A20", "one envelope + one Skill call",
     [_u(_env(ENV_ARGS)), _skill("tu_s")], "unknown", "None", "invocation.multiple", "-"),
    ("A21", "envelope inside a list-content text block (only occurrence)",
     [_ub(_txt(_env(ENV_ARGS)))], "unknown", "None", "invocation.malformed", "-"),
    ("A22.1", "args --since-last-review=1",
     [_u(_env("177 --since-last-review=1"))], "full-requested", "False", "-", "-"),
    ("A22.2", "args quoted --since-last-review",
     [_u(_env('177 "--since-last-review"'))], "full-requested", "False", "-", "-"),
    ("A22.3", "args --since-last-review,",
     [_u(_env("177 --since-last-review,"))], "full-requested", "False", "-", "-"),
    ("A23", "args split across lines, flag a whole token",
     [_u(_env("177  --l2-comments\n--since-last-review"))] + _OK_INCR,
     "incremental", "True", "-", "-"),
    ("A24", "quoted record with TWO envelope-shaped tags + real envelope + Skill call",
     [_u("pasted: " + _env(ENV_ARGS) + "\n" + _env(ENV_ARGS)), _u(_env(ENV_ARGS)), _skill("tu_s")],
     "unknown", "None", "invocation.malformed", "-"),
    ("A25", "earlier brief carrying the flag text + ok incremental read, then envelope WITHOUT flag",
     [_u("brief: use --since-last-review for round 2")] + _OK_INCR + [_u(_env("177 --l2-comments"))],
     "full-requested", "False", "-", "-"),
    ("A26", "Skill call with input x (not a dict) + one valid envelope",
     [_u(_env(ENV_ARGS)), _a_use("Skill", "x", "tu_s")],
     "unknown", "None", "invocation.skill", "invocation.skill,tool_use.input"),
    ("A27", "Skill call with input.skill absent + one valid envelope",
     [_u(_env(ENV_ARGS)), _a_use("Skill", {"args": ENV_ARGS}, "tu_s")],
     "unknown", "None", "invocation.skill", "invocation.skill"),
]

def invocation_arms(out_dir):
    rows = []
    for arm, spec, events, mode, invoked, reason, fields in INV_ARMS:
        _write(out_dir, f"{arm}.jsonl", [json.dumps(e) for e in events])
        rows.append((arm, spec, mode, invoked, reason, fields))
    with open(os.path.join(out_dir, "invocation-arms.tsv"), "w", encoding="utf-8") as fh:
        fh.writelines("\t".join(r) + "\n" for r in rows)
    return len(rows)

def check_inv(expected_tsv, out_json, arm=None):
    try:
        with open(expected_tsv, encoding="utf-8") as fh:
            rows = [l.rstrip("\n").split("\t") for l in fh if l.strip()]
        with open(out_json, encoding="utf-8") as fh:
            got = {s["path"]: s for s in json.load(fh)["sessions"]}
    except (OSError, ValueError, KeyError, TypeError) as e:
        _die(f"check-inv: {type(e).__name__}: {e}")
    bad, seen = [], 0
    for name, spec, mode, invoked, reason, fields in rows:
        if arm is not None and not (name == arm or name.startswith(arm + ".")):
            continue
        seen += 1
        s = got.get(f"{name}.jsonl")
        if s is None:
            bad.append(f"{name}: no session in output"); continue
        want_fields = [] if fields == "-" else fields.split(",")
        if s["mode"] != mode or str(s["invoked"]) != invoked \
                or (s["invocation_reason"] or "-") != reason \
                or (fields != "-" and sorted(s["unknown_fields"]) != want_fields):
            bad.append(f"{name}: want mode={mode} invoked={invoked} reason={reason}"
                       + (f" fields={want_fields}" if fields != "-" else "")
                       + f", got mode={s['mode']} invoked={s['invoked']}"
                         f" reason={s['invocation_reason'] or '-'} fields={s['unknown_fields']}")
    if not seen: bad.append(f"no expected rows for arm {arm}")
    for b in bad: print(b)
    return 1 if bad else 0


if __name__ == "__main__":
    if len(sys.argv) < 3: _die(__doc__)
    mode = sys.argv[1]
    if mode == "transcripts":
        print(transcripts(sys.argv[2], sys.argv[3:]))
    elif mode == "field-arms" and len(sys.argv) == 4:
        print(field_arms(sys.argv[2], sys.argv[3]))
    elif mode == "invocation-arms" and len(sys.argv) == 3:
        print(invocation_arms(sys.argv[2]))
    elif mode == "check" and len(sys.argv) == 5:
        sys.exit(check(*sys.argv[2:5]))
    elif mode == "check-inv" and len(sys.argv) in (4, 5):
        sys.exit(check_inv(*sys.argv[2:5]))
    else:
        _die(f"bad arguments for mode {mode}")

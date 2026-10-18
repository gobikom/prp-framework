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

Usage:
  mutate_fixtures.py transcripts <out_dir> <fixture.jsonl ...>   -> prints variant count
  mutate_fixtures.py field-arms <out_dir> <fixtures_dir>          -> prints variant count
  mutate_fixtures.py check <expected.tsv> <out.json> <field>      -> exit 1 on a mismatch
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


if __name__ == "__main__":
    if len(sys.argv) < 3: _die(__doc__)
    mode = sys.argv[1]
    if mode == "transcripts":
        print(transcripts(sys.argv[2], sys.argv[3:]))
    elif mode == "field-arms" and len(sys.argv) == 4:
        print(field_arms(sys.argv[2], sys.argv[3]))
    elif mode == "check" and len(sys.argv) == 5:
        sys.exit(check(*sys.argv[2:5]))
    else:
        _die(f"bad arguments for mode {mode}")

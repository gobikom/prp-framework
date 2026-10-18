#!/usr/bin/env python3
"""Shape-mutation fixtures for review-rounds.py invariant I2 (#173 re-plan rev3).

For every JSON value inside the real fixtures, write one variant with that
value replaced by each wrong-type value in WRONG. The bats test then runs the
script over all variants and asserts it never raises (no traceback, exit 0/2).

Usage:
  mutate_fixtures.py transcripts <out_dir> <fixture.jsonl ...>   -> one .jsonl per variant
  mutate_fixtures.py gh <out_dir> <gh_fixture_dir> <pr>          -> gh fixture dirs per variant
Prints the number of variants written.
"""
import copy, json, os, sys

WRONG = [None, 0, 1.5, True, "x", [], ["x"], {}, {"x": 1}]


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
    cur[path[-1]] = new
    return v


def transcripts(out_dir, files):
    n = 0
    for f in files:
        with open(f, encoding="utf-8") as fh:
            lines = [l.rstrip("\n") for l in fh if l.strip()]
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
                    with open(os.path.join(out_dir, f"t{n}.jsonl"), "w", encoding="utf-8") as fh:
                        fh.write("\n".join(out) + "\n")
    return n


def gh(out_dir, gh_dir, pr):
    names = [f"repos_test_repo_pulls_{pr}.json", f"repos_test_repo_issues_{pr}_comments.json"]
    docs = {}
    for name in names:
        with open(os.path.join(gh_dir, name), encoding="utf-8") as fh:
            docs[name] = json.load(fh)
    n = 0
    for name in names:
        for path in _paths(docs[name]):
            for w in WRONG:
                n += 1
                d = os.path.join(out_dir, f"g{n}")
                os.makedirs(d)
                for other in names:
                    doc = _replaced(docs[other], path, w) if other == name else docs[other]
                    with open(os.path.join(d, other), "w", encoding="utf-8") as fh:
                        json.dump(doc, fh)
    return n


if __name__ == "__main__":
    mode, out_dir = sys.argv[1], sys.argv[2]
    if mode == "transcripts":
        print(transcripts(out_dir, sys.argv[3:]))
    elif mode == "gh":
        print(gh(out_dir, sys.argv[3], sys.argv[4]))
    else:
        sys.exit(f"unknown mode {mode}")

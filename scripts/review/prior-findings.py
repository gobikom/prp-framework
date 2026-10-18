#!/usr/bin/env python3
"""Print the Prior findings lines for one pass from the previous --l2-comments round.

usage: prior-findings.py <comments.tsv> <pass> <current-run-id>
comments.tsv: one comment per line, "<created_at>\t<base64 body>" (Step B writes it with gh api).
Picks the latest pass comment (line 1 "Reviewed head:", footer pass=<pass>) of another run and prints:
  "None."                      no earlier round, or it had no critical/important finding
  "Not recorded: ..."          the earlier comment has no review-findings block
  "- <id12> open <file>:<start>-<end> regression_test: none"   one per critical/important finding
The id is sha256("pass|file|start|end|family|summary")[:12]; "-" when the finding has no family.
Exit 0 = printed; 2 = the earlier block is malformed or the input unreadable (Step B stops); 3 = usage."""
import base64, binascii, hashlib, json, re, sys

FOOTER = re.compile(r'^Generated-by: prp-review-agents v\S+ run=(\S+) pass=(\S+)( tier=trivial)?$')

def fid(pas, x):
    if not x.get("family"): return "-"
    s, e = x["lines"]
    return hashlib.sha256(f'{pas}|{x["file"]}|{s}|{e}|{x["family"]}|{x["summary"]}'.encode()).hexdigest()[:12]

def main(tsv, pas, run):
    best = None
    for raw in open(tsv, encoding="utf-8"):
        raw = raw.rstrip("\n")
        if not raw: continue
        try:
            at, b64 = raw.split("\t")
            body = base64.b64decode(b64, validate=True).decode("utf-8")
        except (ValueError, binascii.Error, UnicodeDecodeError):
            print("unreadable comment line", file=sys.stderr); return 2
        lines = [l for l in body.split("\n")]
        while lines and not lines[-1].strip(): lines.pop()
        if not lines or not lines[0].startswith("Reviewed head: "): continue
        m = FOOTER.match(lines[-1])
        if not m or m.group(2) != pas or m.group(1) == run: continue
        if best is None or at >= best[0]: best = (at, lines)
    if best is None: print("None."); return 0
    lines = best[1]
    fences = [i for i, l in enumerate(lines) if l.rstrip() == "```review-findings"]
    if not fences: print("Not recorded: the previous round has no review-findings block."); return 0
    if len(fences) != 1 or fences[0] + 1 >= len(lines):
        print("previous round: malformed review-findings block", file=sys.stderr); return 2
    try:
        doc = json.loads(lines[fences[0] + 1])
        found = [x for x in doc["findings"] if x["severity"] in ("critical", "important")]
        out = [f'- {fid(pas, x)} open {x["file"]}:{x["lines"][0]}-{x["lines"][1]} regression_test: none' for x in found]
    except (json.JSONDecodeError, KeyError, TypeError, IndexError, ValueError):
        print("previous round: malformed review-findings JSON", file=sys.stderr); return 2
    print("\n".join(out) if out else "None.")
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 4: print("usage: prior-findings.py <comments.tsv> <pass> <current-run-id>", file=sys.stderr); sys.exit(3)
    try: sys.exit(main(*sys.argv[1:]))
    except OSError as e: print(f"input: {e}", file=sys.stderr); sys.exit(2)

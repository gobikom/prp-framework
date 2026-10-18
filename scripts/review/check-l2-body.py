#!/usr/bin/env python3
"""Check the review-findings block and Prior findings section of one --l2-comments pass body.

usage: check-l2-body.py <body.md> <reviewed-head> <pass>
Exit 0 = valid; 1 = invalid (reasons on stderr); 3 = usage/IO.
Run by Step C with the installed framework's copy (python3 -I), never the PR's.
The older format checks (line 1/2, headings, footer) stay in Step C itself."""
import json, os, re, subprocess, sys, tempfile

FENCE = "```review-findings"
ITEM = re.compile(r'^- ([0-9a-f]{12}|-) (resolved|open) [^ ]+:[0-9]+-[0-9]+ regression_test: ([^ ]+::.+|none)$')
COUNT = re.compile(r'^### (Critical|Important) Issues \(([0-9]+) found\)\s*$')

def check(lines, head, pas):
    why = []
    idx = lambda pred: [i for i, l in enumerate(lines) if pred(l)]
    fences = idx(lambda l: l.rstrip() == FENCE)
    prior = idx(lambda l: l.rstrip() == "### Prior findings")
    cnv = idx(lambda l: l.rstrip() == "### Could not verify")
    if len(fences) != 1: return [f"{len(fences)} review-findings fences (need 1)"]
    if len(prior) != 1: return [f"{len(prior)} Prior findings headings (need 1)"]
    f, p = fences[0], prior[0]
    if f + 2 >= len(lines) or lines[f + 2].rstrip() != "```":
        return ["the review-findings fence must hold exactly one line"]
    if not (cnv and cnv[0] < p < f): why.append("order: Could not verify, Prior findings, review-findings")
    if any(l.strip() for l in lines[f + 3:-1]): why.append("text between the review-findings fence and the footer")
    # Prior findings body: "None.", one "Not recorded: ..." line, or item lines only
    body = [l.rstrip() for l in lines[p + 1:f] if l.strip()]
    if not body: why.append("Prior findings is empty")
    elif body == ["None."] or (len(body) == 1 and body[0].startswith("Not recorded: ")): pass
    else:
        for l in body:
            m = ITEM.match(l)
            if not m: why.append(f"Prior findings line not in the item shape: {l[:80]!r}")
            elif m.group(2) == "open" and m.group(3) != "none": why.append("an open item names a regression test")
    try: doc = json.loads(lines[f + 1])
    except json.JSONDecodeError as e: return why + [f"review-findings is not JSON ({e.msg})"]
    tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    try:
        json.dump(doc, tmp); tmp.close()
        v = os.path.join(os.path.dirname(os.path.abspath(__file__)), "validate-findings.py")
        r = subprocess.run([sys.executable, "-I", v, tmp.name], capture_output=True, text=True)
        if r.returncode != 0: return why + [f"review-findings refused by the schema (exit {r.returncode}): {r.stderr.strip()[:200]}"]
    finally: os.unlink(tmp.name)
    if doc["reviewed_head"] != head: why.append("review-findings reviewed_head is not the reviewed head")
    if doc["pass"] != pas: why.append("review-findings pass is not this pass")
    if doc["complete"] is not True: why.append("review-findings complete is not true")
    heads = {}
    for l in lines:
        m = COUNT.match(l)
        if m: heads[m.group(1).lower()] = int(m.group(2))
    for sev in ("critical", "important"):
        n = sum(1 for x in doc["findings"] if x["severity"] == sev)
        if heads.get(sev) != n: why.append(f"{sev}: heading says {heads.get(sev)}, review-findings has {n}")
    if any(x["severity"] in ("critical", "important") and not x.get("family") for x in doc["findings"]):
        why.append("a critical/important finding has no family")
    return why

if __name__ == "__main__":
    if len(sys.argv) != 4: print(__doc__.split("\n")[2], file=sys.stderr); sys.exit(3)
    try: lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
    except (OSError, UnicodeDecodeError) as e: print(f"body: {e}", file=sys.stderr); sys.exit(3)
    while lines and not lines[-1].strip(): lines.pop()
    why = check(lines, sys.argv[2], sys.argv[3])
    if why: print("; ".join(why), file=sys.stderr); sys.exit(1)

#!/usr/bin/env python3
"""Print the Prior findings input for one pass from the previous --l2-comments round.

usage: prior-findings.py <comments.tsv> <pass> <current-run-id> <mode> [--json]
comments.tsv: one comment per line, "<created_at>\t<updated_at>\t<base64 body>"
              (Step B writes it with gh api).
mode: full | incremental (this run's mode, from the Step A run file).
Picks the latest pass comment (line 1 "Reviewed head:", footer pass=<pass>, another run id)
before this one and prints one of:
  "None."                       no earlier round, or it had no critical/important finding
  "Not recorded: the previous round has no review-findings block."   (full mode only)
  TSV rows "id12\tfile\tstart\tend\tseverity\tfamily", one per critical/important finding
  (--json: the canonical JSON array of those finding objects, for verbatim carry-over)
The id is sha256("pass|file|start|end|family|summary")[:12]; "-" when the finding has no family.
Exit 0 = printed; 2 = the earlier round is unstructured and this run is incremental (run FULL),
    or the input is unreadable; 3 = usage/IO."""
import base64, binascii, hashlib, json, re, sys

FOOTER = re.compile(r'^Generated-by: prp-review-agents v\S+ run=(\S+) pass=(\S+)( tier=trivial)?$')

def fid(pas, x):
    if not x.get("family"): return "-"
    s, e = x["lines"]
    return hashlib.sha256(f'{pas}|{x["file"]}|{s}|{e}|{x["family"]}|{x["summary"]}'.encode()).hexdigest()[:12]

def bad(reason):
    print(f"previous round: {reason}", file=sys.stderr); return 2

def classify(lines, pas, created, updated):
    """-> ("none"|"unstructured", reason) or ("structured", findings-list)."""
    if created != updated: return ("unstructured", "the comment was edited after posting")
    fences = [i for i, l in enumerate(lines) if l.rstrip() == "```review-findings"]
    if not fences: return ("unstructured", "no review-findings block")
    if len(fences) != 1: return ("unstructured", "multiple review-findings blocks")
    f = fences[0]
    if f + 1 >= len(lines) or lines[f + 1].rstrip() == "```":
        return ("unstructured", "the review-findings block is empty")
    try: doc = json.loads(lines[f + 1])
    except json.JSONDecodeError as e: return ("unstructured", f"malformed review-findings JSON ({e.msg})")
    head = lines[0][len("Reviewed head: "):]
    if not isinstance(doc, dict) or doc.get("reviewed_head") != head:
        return ("unstructured", "review-findings reviewed_head differs from the comment's line 1")
    if doc.get("pass") != pas: return ("unstructured", "review-findings pass differs from the footer pass")
    if doc.get("complete") is not True: return ("unstructured", "review-findings is not complete")
    fl = doc.get("findings")
    if not isinstance(fl, list): return ("unstructured", "review-findings findings is not a list")
    return ("structured", fl)

def main(tsv, pas, run, mode, as_json):
    best = None
    try: raw_lines = open(tsv, encoding="utf-8").read().split("\n")
    except (OSError, UnicodeDecodeError) as e: print(f"input: {e}", file=sys.stderr); return 3
    for raw in raw_lines:
        if not raw: continue
        parts = raw.split("\t")
        if len(parts) != 3: print("unreadable comment line (need 3 tab fields)", file=sys.stderr); return 2
        at, up, b64 = parts
        try: body = base64.b64decode(b64, validate=True).decode("utf-8")
        except (ValueError, binascii.Error, UnicodeDecodeError):
            print("unreadable comment body", file=sys.stderr); return 2
        lines = body.split("\n")
        while lines and not lines[-1].strip(): lines.pop()
        if not lines or not lines[0].startswith("Reviewed head: "): continue
        m = FOOTER.match(lines[-1])
        if not m or m.group(2) != pas or m.group(1) == run: continue
        if best is None or at >= best[0]: best = (at, up, lines)
    if best is None: print("None."); return 0
    kind, payload = classify(best[2], pas, best[0], best[1])
    if kind == "unstructured":
        if mode != "full": return bad(payload + " — an incremental run must be FULL")
        print("Not recorded: the previous round has no review-findings block."); return 0
    found = [x for x in payload if isinstance(x, dict) and x.get("severity") in ("critical", "important")]
    if as_json:
        print(json.dumps(found, sort_keys=True, separators=(",", ":"))); return 0
    try:
        out = [f'{fid(pas, x)}\t{x["file"]}\t{x["lines"][0]}\t{x["lines"][1]}\t{x["severity"]}\t{x.get("family") or "-"}'
               for x in found]
    except (KeyError, TypeError, IndexError, ValueError):
        return bad("a critical/important finding lacks file, lines or severity")
    print("\n".join(out) if out else "None.")
    return 0

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--json"]
    as_json = len(args) != len(sys.argv[1:])
    if len(args) != 4 or args[3] not in ("full", "incremental"):
        print("usage: prior-findings.py <comments.tsv> <pass> <current-run-id> <full|incremental> [--json]", file=sys.stderr); sys.exit(3)
    try: sys.exit(main(*args, as_json))
    except OSError as e: print(f"input: {e}", file=sys.stderr); sys.exit(2)

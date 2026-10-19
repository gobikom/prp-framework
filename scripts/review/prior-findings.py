#!/usr/bin/env python3
"""Print the Prior findings input for one pass from the previous --l2-comments round.

usage: prior-findings.py <comments.tsv> <pass> <run.env> [--json]
comments.tsv: one comment per line, "<created_at>\t<updated_at>\t<login>\t<base64 body>"
              (Step B writes it with gh api, login included so provenance is checkable).
run.env: the Step A run file — RUN_ID and MODE of THIS run, the REVIEWED_HEAD_SHA it
         reviews, and ORCHESTRATOR_LOGIN, the only login whose comments are trusted.
A previous-round pass comment is selected ONLY if every check passes (review fix, #178):
  - authored by ORCHESTRATOR_LOGIN and never edited (created_at == updated_at);
  - its footer names a run id that is in the ledger: an unedited start comment by the
    same login ("Review started: head=<sha> run=<run>" + footer pass=start);
  - its line-1 Reviewed head equals the head that run's start comment records.
Anything else (wrong author, no Generated-by footer, unknown run id, different head,
edits) is untrusted and never selected — it can neither inject nor suppress findings.
Carried content is untrusted data: a finding beyond the caps (file 200, category 40,
summary 200, evidence 4000 chars, 16000 evidence chars total) refuses the run.
Prints one of:
  "None."                       no trusted earlier round, or it had no critical/important finding
  "Not recorded: the previous round has no review-findings block."   (full mode only)
  TSV rows "id12\tfile\tstart\tend\tseverity\tfamily", one per critical/important finding
  (--json: the canonical JSON array of those finding objects, for verbatim carry-over)
The id is sha256("pass|file|start|end|family|summary")[:12]; "-" when the finding has no family.
Selection tie-break: (created_at, updated_at) — the orchestrator posts a pass comment
exactly once and never edits it, so a tie means a protocol breach that later checks catch.
Exit 0 = printed; 2 = refusal (untrusted-unstructured previous round in an incremental run,
    caps exceeded, or unreadable comment input); 3 = usage, bad run file, or IO."""
import base64, binascii, hashlib, json, re, sys

FOOTER = re.compile(r'^Generated-by: prp-review-agents v\S+ run=(\S+) pass=(\S+)( tier=trivial)?$')
START1 = re.compile(r'^Review started: head=([0-9a-f]{40}) run=(\S+)$')
ENV_KEYS = ("REVIEWED_HEAD_SHA", "PRP_VERSION", "RUN_ID", "TIER", "START_URL", "MODE", "ORCHESTRATOR_LOGIN")
ENV_PAT = {
    "REVIEWED_HEAD_SHA": r"[0-9a-f]{40}",
    "PRP_VERSION": r"[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?",
    "RUN_ID": r"[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}",
    "TIER": r"trivial|standard",
    "START_URL": r"https://github\.com/[^ ]+#issuecomment-[0-9]+",
    "MODE": r"full|incremental",
    "ORCHESTRATOR_LOGIN": r"[A-Za-z0-9-]{1,39}",
}
FILE_RE = re.compile(r'^[A-Za-z0-9._/@+-]{1,200}$')
CAT_RE = re.compile(r'^[a-z0-9-]{1,40}$')
EVIDENCE_MAX = 4000
CARRIED_MAX = 16000

def fid(pas, x):
    if not x.get("family"): return "-"
    s, e = x["lines"]
    return hashlib.sha256(f'{pas}|{x["file"]}|{s}|{e}|{x["family"]}|{x["summary"]}'.encode()).hexdigest()[:12]

def bad(reason):
    print(f"previous round: {reason}", file=sys.stderr); return 2

def bad_env():
    print("the run file is not a valid Step A run file (7 keys, validated values)", file=sys.stderr); sys.exit(3)

def load_env(path):
    try: lines = open(path, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError): bad_env()
    if len(lines) != len(ENV_KEYS) or not all("=" in l for l in lines): bad_env()
    env = dict(l.split("=", 1) for l in lines)
    if tuple(env.keys()) != ENV_KEYS: bad_env()
    for k, pat in ENV_PAT.items():
        if not re.fullmatch(pat, env[k]): bad_env()
    return env

def classify(lines, pas):
    """-> ("unstructured", reason) or ("structured", findings-list). Caller has already
    verified author, ledger and head binding; only the block itself is judged here."""
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

def caps(found):
    """carried content is untrusted data — refuse anything past the caps"""
    tot = 0
    for x in found:
        f, c = x.get("file"), x.get("category")
        s, e = x.get("summary"), x.get("evidence")
        if (not isinstance(f, str) or not FILE_RE.fullmatch(f)
                or not isinstance(c, str) or not CAT_RE.fullmatch(c)
                or not isinstance(s, str) or len(s) > 200
                or not isinstance(e, str) or len(e) > EVIDENCE_MAX):
            return bad("a carried finding exceeds the untrusted-content caps "
                       "(file 200, category 40, summary 200, evidence 4000 chars) — re-run a FULL review")
        tot += len(e)
    if tot > CARRIED_MAX:
        return bad(f"the carried evidence exceeds {CARRIED_MAX} chars in total — re-run a FULL review")
    return None

def main(tsv, pas, env_path, as_json):
    env = load_env(env_path)
    run, mode, orch = env["RUN_ID"], env["MODE"], env["ORCHESTRATOR_LOGIN"]
    best = None
    try: raw_lines = open(tsv, encoding="utf-8").read().split("\n")
    except (OSError, UnicodeDecodeError) as e: print(f"input: {e}", file=sys.stderr); return 3
    entries = []
    for raw in raw_lines:
        if not raw: continue
        parts = raw.split("\t")
        if len(parts) != 4: print("unreadable comment line (need 4 tab fields: created, updated, login, body)", file=sys.stderr); return 2
        at, up, login, b64 = parts
        try: body = base64.b64decode(b64, validate=True).decode("utf-8")
        except (ValueError, binascii.Error, UnicodeDecodeError):
            print("unreadable comment body", file=sys.stderr); return 2
        lines = body.split("\n")
        while lines and not lines[-1].strip(): lines.pop()
        entries.append((at, up, login, lines))
    # the ledger: unedited start comments by the orchestrator, exact two-line bodies
    ledger = {}
    for at, up, login, lines in entries:
        if login != orch or at != up or len(lines) != 2: continue
        m1 = START1.match(lines[0])
        m2 = FOOTER.match(lines[1].rstrip())
        if m1 and m2 and m2.group(1) == m1.group(2) and m2.group(2) == "start":
            ledger.setdefault(m1.group(2), set()).add(m1.group(1))
    for at, up, login, lines in entries:
        if login != orch or at != up: continue          # forged author or edited: never selected
        if not lines or not lines[0].startswith("Reviewed head: "): continue
        m = FOOTER.match(lines[-1].rstrip())
        if not m or m.group(2) != pas or m.group(1) == run: continue
        if m.group(1) not in ledger: continue           # run id not in the ledger
        if lines[0][len("Reviewed head: "):] not in ledger[m.group(1)]: continue   # different head
        if best is None or (at, up) >= (best[0], best[1]): best = (at, up, lines)
    if best is None: print("None."); return 0
    kind, payload = classify(best[2], pas)
    if kind == "unstructured":
        if mode != "full": return bad(payload + " — an incremental run must be FULL")
        print("Not recorded: the previous round has no review-findings block."); return 0
    found = [x for x in payload if isinstance(x, dict) and x.get("severity") in ("critical", "important")]
    try:   # validate before either output: --json must not carry an object rows mode would refuse
        out = [f'{fid(pas, x)}\t{x["file"]}\t{x["lines"][0]}\t{x["lines"][1]}\t{x["severity"]}\t{x.get("family") or "-"}'
               for x in found]
    except (KeyError, TypeError, IndexError, ValueError):
        return bad("a critical/important finding lacks file, lines or severity")
    rc = caps(found)
    if rc is not None: return rc
    if as_json:
        print(json.dumps(found, sort_keys=True, separators=(",", ":"))); return 0
    print("\n".join(out) if out else "None.")
    return 0

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--json"]
    as_json = len(args) != len(sys.argv[1:])
    if len(args) != 3:
        print("usage: prior-findings.py <comments.tsv> <pass> <run.env> [--json]", file=sys.stderr); sys.exit(3)
    try: sys.exit(main(*args, as_json))
    except OSError as e: print(f"input: {e}", file=sys.stderr); sys.exit(2)

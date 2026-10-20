#!/usr/bin/env python3
"""Check the new sections of one --l2-comments pass body (prp-framework#178).

usage: check-l2-body.py <body.md> <reviewed-head> <pass>
       check-l2-body.py --prior <body.md> <comments.tsv> <run.env> <expected-pass>
Exit 0 = valid; 1 = invalid (reasons on stderr); 3 = usage/IO.
Run by Step C with the installed framework's copy (python3 -I), never the PR's.
The older format checks (line 1/2, headings, footer) stay in Step C itself.
A '- L2-FINDING-CAP <element>.<field> <len>><cap> not-posted' line under '### Could not
verify' (one per cap-broken element dropped by validate-findings.py --enforce-caps at
Step B, #185 round-7 fix) must match CAPLINE — anything else is refused.

--prior takes the expected pass from the caller (Step C's pass loop) — NEVER from the
body — and re-runs prior-findings.py over the same TSV and run.env with that trusted
value (the run file carries RUN_ID/MODE plus ORCHESTRATOR_LOGIN, the only trusted
author; prior-findings enforces author + start-comment ledger + head binding), enforcing,
per SO#1367 R2-1/R3-2 — in an INCREMENTAL run — that the body's Prior findings itemise the
previous round's critical/important findings exactly (none dropped, duplicated or added),
every open item is in this round's JSON exactly once (canonically equal to the previous
object), every resolved item is absent, and the Review-mode line matches the run file's
MODE. In a FULL round no prior lookup happens at all: the Prior findings section must be
exactly the fixed line "None (full review)" and any prior-id open/resolved marking is
refused — every finding is reported fresh (plan 185-cap-scope-replan, round-5 extension).
Line 2, the
review-findings JSON's pass and the footer's pass= must all equal the expected pass, and the
footer's run= must equal the run file's RUN_ID.
Residual limitation (threat model, plan rev 5 R1): an actor with repo write access can
delete prior comments; the check then sees a first round (tracked as prp-framework#184).
Policy freeze until the follow-up PR lands: --prior results are NOT counted as Rule C /
policy evidence of prior-round closure."""
import hashlib, json, os, re, subprocess, sys, tempfile
from collections import Counter

FENCE = "```review-findings"
PRIOR_H = "### Prior findings"
NOT_RECORDED = "Not recorded: the previous round has no review-findings block."
NONE_FULL = "None (full review)"
PASS_NAMES = ("code-reviewer", "security-reviewer", "silent-failure-hunter")
FOOTER_RE = re.compile(r'^Generated-by: prp-review-agents v\S+ run=(\S+) pass=(\S+)( tier=trivial)?$')
OPEN = re.compile(r'^- ([0-9a-f]{12}|-) open ([^ :]+):([0-9]+)-([0-9]+) regression_test: none$')
RESOLVED = re.compile(r'^- ([0-9a-f]{12}|-) resolved was=([^ :]+):([0-9]+)-([0-9]+) fix=([^ :]+):([0-9]+)-([0-9]+) regression_test: ([^ ]+::.+|none)$')
COUNT = re.compile(r'^### (Critical|Important) Issues \(([0-9]+) found\)\s*$')
MODER = re.compile(r'^Review-mode: (full|incremental)$')
FAMILY = re.compile(r'^[a-z0-9][a-z0-9-]{0,63}$')
CAPLINE = re.compile(r'^- L2-FINDING-CAP (findings|probe_requests)\[[0-9]+\]\.(file|category|summary|evidence|id|command|purpose|expected) [0-9]+>[0-9]+ not-posted$')
HERE = os.path.dirname(os.path.abspath(__file__))

def no_dupes(pairs):
    keys = [k for k, _ in pairs]
    if len(keys) != len(set(keys)): raise ValueError("duplicate JSON key")
    return dict(pairs)

def load_json(line):
    return json.loads(line, object_pairs_hook=no_dupes)

def path_bad(p):
    return (not p) or p.startswith("/") or "\\" in p or p.startswith("./") \
        or p == ".." or "/../" in p or "/./" in p or p.endswith("/")

_HEAD_OK = {}
def at_head(why, head, p):
    """append a reason when p is not a file at head; exit 3 when git itself cannot answer"""
    if path_bad(p):
        why.append(f"path {p!r} is not a normalised relative path"); return
    if head not in _HEAD_OK:
        if subprocess.run(["git", "rev-parse", "--verify", "-q", head + "^{commit}"],
                          capture_output=True).returncode != 0:
            print(f"cannot verify files: {head} is not a commit here (run in the PR worktree)",
                  file=sys.stderr); sys.exit(3)
        _HEAD_OK[head] = True
    if subprocess.run(["git", "cat-file", "-e", f"{head}:{p}"], capture_output=True).returncode != 0:
        why.append(f"file {p!r} is absent at the reviewed head")

def parse_body(path):
    try: lines = open(path, encoding="utf-8").read().split("\n")
    except (OSError, UnicodeDecodeError) as e: print(f"body: {e}", file=sys.stderr); sys.exit(3)
    while lines and not lines[-1].strip(): lines.pop()
    return lines

def structure(lines):
    """the fixed layout after '### Could not verify': Prior findings, the fence,
    blank lines, one Review-mode line, blank lines, the footer.
    -> (fence_i, body_mode, items, why)"""
    why = []
    idx = lambda pred: [i for i, l in enumerate(lines) if pred(l.rstrip())]
    fences, prior, cnv = idx(lambda l: l == FENCE), idx(lambda l: l == PRIOR_H), idx(lambda l: l == "### Could not verify")
    if len(fences) != 1: return None, None, None, [f"{len(fences)} review-findings fences (need 1)"]
    if len(prior) != 1: return None, None, None, [f"{len(prior)} Prior findings headings (need 1)"]
    f, p = fences[0], prior[0]
    if f + 2 >= len(lines) or lines[f + 2].rstrip() != "```":
        return None, None, None, ["the review-findings fence must hold exactly one line"]
    if not cnv or not (cnv[0] < p < f): why.append("order: Could not verify, Prior findings, review-findings")
    tail = [l for l in lines[f + 3:] if l.strip()]
    m = MODER.match(tail[0]) if len(tail) == 2 and tail[1].startswith("Generated-by: ") else None
    if not m: why.append("after the fence: only blanks, exactly one 'Review-mode: full|incremental' line, only blanks, then the 'Generated-by:' footer as the last line")
    items = [l.rstrip() for l in lines[p + 1:f] if l.strip()]
    if not items: why.append("Prior findings is empty")
    elif items != ["None."] and items != [NONE_FULL] and not (len(items) == 1 and items[0].startswith("Not recorded: ")):
        for l in items:
            if not (OPEN.match(l) or RESOLVED.match(l)):
                why.append(f"Prior findings line not in the item shape: {l[:80]!r}")
    if cnv and cnv[0] < p:
        for l in lines[cnv[0] + 1:p]:
            if l.startswith("- L2-FINDING-CAP") and not CAPLINE.match(l.rstrip()):
                why.append(f"bad L2-FINDING-CAP line: {l.rstrip()[:100]!r}")
    return f, (m.group(1) if m else None), items, why

def check(path, head, pas):
    lines = parse_body(path)
    f, _, items, why = structure(lines)
    if why: return why
    try: doc = load_json(lines[f + 1])
    except (json.JSONDecodeError, ValueError) as e: return [f"review-findings is not JSON ({e})"]
    tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    try:
        tmp.write(lines[f + 1] + "\n"); tmp.close()
        r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "validate-findings.py"), tmp.name],
                           capture_output=True, text=True)
        if r.returncode != 0:
            return [f"review-findings refused by the schema (exit {r.returncode}): {r.stderr.strip()[:200]}"]
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
    for x in doc["findings"]:
        if x["severity"] in ("critical", "important") and (not x.get("family") or not FAMILY.match(x["family"])):
            why.append(f"a critical/important finding has no valid family: {x.get('family')!r}")
        s, e = x["lines"]
        if s > e: why.append(f"lines {s}-{e} start after end ({x['file']})")
        if not str(x["summary"]).strip(): why.append("a finding has an empty summary")
        at_head(why, head, x["file"])
    for l in items:
        m = RESOLVED.match(l)
        if m and int(m.group(6)) > int(m.group(7)):
            why.append(f"fix= range {m.group(6)}-{m.group(7)} starts after end")
        g = (OPEN.match(l) or m)
        if g:
            if int(g.group(4)) < int(g.group(3)): why.append(f"item range {g.group(3)}-{g.group(4)} starts after end")
            if g.re is RESOLVED: at_head(why, head, g.group(5))
    return why

def fid(pas, x):
    if not x.get("family"): return "-"
    s, e = x["lines"]
    return hashlib.sha256(f'{pas}|{x["file"]}|{s}|{e}|{x["family"]}|{x["summary"]}'.encode()).hexdigest()[:12]

def prior_rows(tsv, pas, env_path, extra=()):
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "prior-findings.py"), tsv, pas, env_path, *extra],
                       capture_output=True, text=True)
    if r.returncode == 3: print(r.stderr, file=sys.stderr); sys.exit(3)
    return r

def check_prior(path, tsv, env_path, xpas):
    if not re.fullmatch(r"\S+", xpas) or xpas not in PASS_NAMES:
        return [f"expected pass {xpas!r} is not a core pass name (code-reviewer|security-reviewer|silent-failure-hunter)"]
    try: env = dict(l.split("=", 1) for l in open(env_path, encoding="utf-8").read().splitlines() if "=" in l)
    except (OSError, UnicodeDecodeError) as e: print(f"run file: {e}", file=sys.stderr); sys.exit(3)
    run, mode = env.get("RUN_ID", ""), env.get("MODE", "")
    if not re.fullmatch(r"[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}", run) or mode not in ("full", "incremental"):
        return ["the run file has no valid RUN_ID/MODE"]
    lines = parse_body(path)
    f, body_mode, items, why = structure(lines)
    if why: return why
    if body_mode != mode: return [f"Review-mode says {body_mode!r}, the run file says {mode!r}"]
    if lines[1] != f"Passes run: {xpas}":
        return ["body line 2 is not 'Passes run: <pass>'"]
    fm = FOOTER_RE.match(lines[-1].rstrip())
    if not fm:
        return ["the footer is not the 'Generated-by: prp-review-agents v<ver> run=<run> pass=<pass>[ tier=trivial]' line"]
    if fm.group(1) != run:
        return ["footer run= is not the run file's RUN_ID"]
    if fm.group(2) != xpas:
        return ["footer pass= is not the expected pass"]
    try: doc = load_json(lines[f + 1])
    except (json.JSONDecodeError, ValueError): return ["review-findings is not JSON"]
    if doc.get("pass") != xpas:
        return ["review-findings pass is not the expected pass"]
    if mode == "full":
        # the plan invariant (185-cap-scope-replan, round-5 extension): a FULL round never
        # reads prior-round content — no prior lookup, no open/resolved marking. Findings are
        # reported fresh and the section is the fixed line; prior-id marking exists only in
        # incremental rounds (below).
        if any(OPEN.match(l) or RESOLVED.match(l) for l in items):
            return ["a FULL round accepts no prior open/resolved marking — report findings fresh and write the line 'None (full review)'"]
        return [] if items == [NONE_FULL] else ["a FULL round's Prior findings must be exactly the line 'None (full review)'"]
    r = prior_rows(tsv, xpas, env_path)
    if r.returncode == 5: return [f"prior-findings refused the prior-round evidence: {r.stderr.strip()[:160]}"]
    if r.returncode != 0: return [f"prior-findings: {r.stderr.strip()[:160]}"]
    out = r.stdout.rstrip("\n")
    if out == "None.":
        return [] if items == ["None."] else ["no previous round: Prior findings must be exactly 'None.'"]
    if out.startswith("Not recorded: "):
        return [] if items == [NOT_RECORDED] else ["unstructured previous round: Prior findings must be the 'Not recorded' line"]
    if items and (items == ["None."] or items[0].startswith("Not recorded: ")):
        return ["the previous round is structured: Prior findings must itemise it"]
    rows = [l.split("\t") for l in out.split("\n") if l]
    if any(len(row) != 6 for row in rows): return ["prior-findings rows are malformed"]
    want = Counter((row[0], row[1], row[2], row[3]) for row in rows)
    got = Counter()
    for l in items:
        m = OPEN.match(l) or RESOLVED.match(l)
        if m: got[(m.group(1), m.group(2), m.group(3), m.group(4))] += 1   # (id, file, start, end): open location / resolved was=
    if want != got:
        return ["Prior findings items do not match the previous round exactly (dropped, duplicated or added)"]
    jf = [x for x in doc.get("findings", []) if isinstance(x, dict) and x.get("severity") in ("critical", "important")]
    jids = [fid(xpas, x) for x in jf]
    canon = lambda o: json.dumps(o, sort_keys=True, separators=(",", ":"))
    prev_obj = {}
    if mode == "incremental":
        rj = prior_rows(tsv, xpas, env_path, ("--json",))
        if rj.returncode != 0: return [f"prior-findings --json: {rj.stderr.strip()[:160]}"]
        try:
            for o in json.loads(rj.stdout): prev_obj[fid(xpas, o)] = canon(o)
        except (json.JSONDecodeError, KeyError, TypeError, ValueError): return ["prior-findings --json is malformed"]
    for l in items:
        mo, mr = OPEN.match(l), RESOLVED.match(l)   # the keyword is literal text, not a group
        if not (mo or mr): continue
        iid, status = (mo or mr).group(1), "open" if mo else "resolved"
        if iid == "-" and status == "open":
            return ["an open previous-round finding has no family id — re-run a FULL review (critical/important findings need a family)"]
        n = jids.count(iid) if iid != "-" else 0
        if status == "open" and n != 1:
            return [f"open item {iid} appears {n} times in this round's review-findings (need exactly 1)"]
        if status == "resolved" and n != 0:
            return [f"resolved item {iid} still appears in this round's review-findings"]
        if status == "open" and mode == "incremental" and iid in prev_obj:
            if [canon(x) for x in jf if fid(xpas, x) == iid] != [prev_obj[iid]]:
                return [f"carried item {iid} was not copied verbatim from the previous round"]
    return []

if __name__ == "__main__":
    try:
        if len(sys.argv) == 6 and sys.argv[1] == "--prior":
            why = check_prior(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
        elif len(sys.argv) == 4:
            why = check(sys.argv[1], sys.argv[2], sys.argv[3])
        else:
            print(__doc__.split("\n")[2], file=sys.stderr); sys.exit(3)
    except SystemExit: raise
    except Exception as e: print(f"internal error: {e}", file=sys.stderr); sys.exit(3)
    if why: print("; ".join(why), file=sys.stderr); sys.exit(1)

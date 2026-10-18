#!/usr/bin/env python3
"""Generated sweeps from HANDLERS/ENFORCED. Each case isolates ONE (T,K) in a wrapper schema.
Usage: enforced-sweep.py <validator> <schema> <mode>  (reject|notype|enforce)"""
import copy, hashlib, importlib.util, json, os, re, subprocess, sys, tempfile, shutil

V, S, MODE = sys.argv[1], sys.argv[2], sys.argv[3]
schema = json.load(open(S))
spec = importlib.util.spec_from_file_location("validator", V)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
ENFORCED = mod.ENFORCED; ANNOTATIONS = mod.ANNOTATIONS
ALL_KW = set().union(*ENFORCED.values())

# Independent oracle: (T, K) → (schema_value, bad_doc, good_doc)
CASES = {
    ("object","properties"):        ({"x":{"type":"string"}},"WRAP",{"x":"ok"}),
    ("object","required"):          (["x"],"WRAP_MISSING",{"x":"ok"}),
    ("object","additionalProperties"):(False,{"zz":1},{}),
    ("array","items"):              ({"type":"string"},[42],["ok"]),
    ("array","minItems"):           (2,[1],[1,2]),
    ("array","maxItems"):           (2,[1,2,3],[1,2]),
    ("string","enum"):              (["a","b"],"c","a"),
    ("string","pattern"):           ("^[a-z]+$","ABC","abc"),
    ("string","maxLength"):         (5,"toolong","ok"),
    ("integer","minimum"):          (0,-1,0),
    ("integer","enum"):             ([1,2],3,1),
}

def _run(vp, dp): return subprocess.run([sys.executable, "-I", vp, dp], capture_output=True, text=True)

def _with_pin(s):
    td = tempfile.mkdtemp()
    os.makedirs(f"{td}/scripts/review"); os.makedirs(f"{td}/schemas")
    b = json.dumps(s).encode()
    open(f"{td}/schemas/review-findings.schema.json","wb").write(b)
    vc = open(V).read()
    vc = re.sub(r'SCHEMA_SHA256 = "[0-9a-f]+"', f'SCHEMA_SHA256 = "{hashlib.sha256(b).hexdigest()}"', vc)
    open(f"{td}/scripts/review/validate-findings.py","w").write(vc)
    return td

def _wrap(t, k, v):
    node = {"type": t, k: v}
    return {"type":"object","properties":{"x":node},"required":["x"],"additionalProperties":False}

WELL_SHAPED = {"properties":{},"required":[],"additionalProperties":False,"items":{"type":"string"},
    "minItems":0,"maxItems":99,"enum":["a"],"pattern":".*","maxLength":999,"minimum":0}

n, bad = 0, 0

if MODE == "enforce":
    # Assert CASES covers exactly ENFORCED
    enforced_pairs = {(t,k) for t in ENFORCED for k in ENFORCED[t]}
    cases_pairs = set(CASES.keys())
    if enforced_pairs != cases_pairs:
        missing = enforced_pairs - cases_pairs
        extra = cases_pairs - enforced_pairs
        if missing: print(f"NO-CASE missing: {missing}"); bad += len(missing)
        if extra: print(f"NO-CASE extra: {extra}"); bad += len(extra)
    td_doc = tempfile.mkdtemp()
    for (t,k), (v, bad_val, good_val) in CASES.items():
        ws = _wrap(t, k, v)
        td = _with_pin(ws)
        vp = f"{td}/scripts/review/validate-findings.py"
        # Bad doc
        if bad_val == "WRAP":
            doc = {"x": 42}
        elif bad_val == "WRAP_MISSING":
            doc = {}
        else:
            doc = {"x": bad_val}
        p = f"{td_doc}/bad{n}.json"; json.dump(doc, open(p,"w"))
        r = _run(vp, p); n += 1
        if r.returncode != 1:
            bad += 1; print(f"MISS enforce {t}/{k} bad: rc={r.returncode} {(r.stdout+r.stderr).strip()[:80]}")
        # Good doc
        doc = {"x": good_val}
        p = f"{td_doc}/good{n}.json"; json.dump(doc, open(p,"w"))
        r = _run(vp, p); n += 1
        if r.returncode != 0:
            bad += 1; print(f"MISS enforce {t}/{k} good: rc={r.returncode} {(r.stdout+r.stderr).strip()[:80]}")
        shutil.rmtree(td)
    shutil.rmtree(td_doc)

elif MODE == "reject":
    for t, enforced in ENFORCED.items():
        illegal = ALL_KW - enforced - ANNOTATIONS - {"type"}
        for kw in sorted(illegal):
            if kw not in WELL_SHAPED:
                bad += 1; n += 1; print(f"NO-CASE {t}.{kw}"); continue
            ws = _wrap(t, kw, WELL_SHAPED[kw])
            td = _with_pin(ws)
            r = _run(f"{td}/scripts/review/validate-findings.py", "/nonexistent")
            n += 1
            out = (r.stdout + r.stderr).strip()
            if r.returncode != 2 or kw not in out or "Traceback" in out:
                bad += 1; print(f"MISS reject {t}/{kw}: rc={r.returncode} {out[:80]}")
            shutil.rmtree(td)

elif MODE == "notype":
    def walk_indexed(node, path="$"):
        if "$ref" not in node and "type" in node: yield path, []
        for pk, pv in node.get("properties",{}).items():
            if isinstance(pv,dict) and "$ref" not in pv:
                for p2,ch in walk_indexed(pv,f"{path}.{pk}"): yield p2,[("properties",pk)]+ch
        if "items" in node and isinstance(node.get("items"),dict) and "$ref" not in node["items"]:
            for p2,ch in walk_indexed(node["items"],f"{path}[]"): yield p2,[("items",)]+ch
        for dk,dv in node.get("$defs",{}).items():
            if isinstance(dv,dict) and "$ref" not in dv:
                for p2,ch in walk_indexed(dv,f"$defs.{dk}"): yield p2,[("$defs",dk)]+ch
    paths_mutated = []
    for path, chain in walk_indexed(schema):
        s2 = copy.deepcopy(schema); target = s2
        for step in chain:
            target = target[step[0]][step[1]] if len(step)==2 else target[step[0]]
        if "type" not in target:
            bad += 1; n += 1; print(f"MISS notype {path}: no type"); continue
        del target["type"]
        td = _with_pin(s2)
        r = _run(f"{td}/scripts/review/validate-findings.py", "/nonexistent")
        n += 1
        if r.returncode != 2: bad += 1; print(f"MISS notype {path}: rc={r.returncode}")
        else: paths_mutated.append(path)
        shutil.rmtree(td)
    print(f"notype-paths={','.join(paths_mutated)}")

print(f"mode={MODE} executed={n} bad={bad}")
if n == 0: print("ERROR: 0 cases"); sys.exit(1)
sys.exit(1 if bad else 0)

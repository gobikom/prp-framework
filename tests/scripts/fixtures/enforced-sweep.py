#!/usr/bin/env python3
"""Generated sweeps from the ENFORCED table. Usage: enforced-sweep.py <validator> <schema> <mode>
Modes: reject (illegal keyword per type → exit 2), notype (remove type → exit 2),
       enforce (doc violates each enforced keyword → exit 1)."""
import copy, hashlib, json, os, re, subprocess, sys, tempfile, shutil

V, S, MODE = sys.argv[1], sys.argv[2], sys.argv[3]
schema = json.load(open(S))
defs = schema.get("$defs", {})
ENFORCED = {"object":{"properties","required","additionalProperties"},"array":{"items","minItems","maxItems"},
    "string":{"enum","pattern","maxLength"},"integer":{"minimum","enum"},"boolean":set()}
ANNOTATIONS = {"title","description"}
ALL_KW = set().union(*ENFORCED.values())

WELL_SHAPED = {"properties":{},"required":[],"additionalProperties":False,"items":{"type":"string"},
    "minItems":0,"maxItems":99,"enum":["a"],"pattern":".*","maxLength":999,"minimum":0}

def _run(validator_path, doc_path):
    return subprocess.run([sys.executable, "-I", validator_path, doc_path], capture_output=True, text=True)

def _with_pin(mutated_schema):
    td = tempfile.mkdtemp()
    os.makedirs(f"{td}/scripts/review"); os.makedirs(f"{td}/schemas")
    b = json.dumps(mutated_schema).encode()
    open(f"{td}/schemas/review-findings.schema.json","wb").write(b)
    vc = open(V).read()
    vc = re.sub(r'SCHEMA_SHA256 = "[0-9a-f]+"', f'SCHEMA_SHA256 = "{hashlib.sha256(b).hexdigest()}"', vc)
    open(f"{td}/scripts/review/validate-findings.py","w").write(vc)
    return td

n, bad = 0, 0
hd = "a" * 40
valid = {"reviewed_head":hd,"pass":"code-reviewer","complete":True,
    "findings":[{"file":"x","lines":[1,2],"severity":"critical","category":"c","family":"f","summary":"s","evidence":"e"}],
    "probe_requests":[{"id":"p-1","command":"echo","purpose":"p","expected":"e"}]}

if MODE == "reject":
    for t, enforced in ENFORCED.items():
        illegal = ALL_KW - enforced - ANNOTATIONS - {"type"}
        for kw in sorted(illegal):
            if kw not in WELL_SHAPED: continue
            s2 = copy.deepcopy(schema)
            s2["$defs"]["finding"]["type"] = t
            s2["$defs"]["finding"][kw] = WELL_SHAPED[kw]
            td = _with_pin(s2)
            r = _run(f"{td}/scripts/review/validate-findings.py", "/nonexistent")
            n += 1
            if r.returncode != 2 or "Traceback" in r.stdout+r.stderr:
                bad += 1; print(f"MISS reject {t}/{kw}: rc={r.returncode} {(r.stdout+r.stderr).strip()[:80]}")
            shutil.rmtree(td)

elif MODE == "notype":
    def walk_nodes(node, path="$"):
        if "$ref" not in node: yield node, path
        for pk, pv in node.get("properties",{}).items():
            if isinstance(pv, dict) and "$ref" not in pv: yield from walk_nodes(pv, f"{path}.{pk}")
        if "items" in node and isinstance(node.get("items"), dict) and "$ref" not in node["items"]:
            yield from walk_nodes(node["items"], f"{path}[]")
        for dk, dv in node.get("$defs",{}).items():
            if isinstance(dv, dict) and "$ref" not in dv: yield from walk_nodes(dv, f"$defs.{dk}")
    for node, path in walk_nodes(schema):
        if "type" not in node: continue
        s2 = copy.deepcopy(schema)
        # Navigate to the same node in the copy
        target = s2
        import re as _re
        for tok in _re.findall(r"\.([A-Za-z_]+)|\[(\d+)\]", path[1:]):
            k = tok[0] or int(tok[1])
            if isinstance(k, str):
                if k in target: target = target[k]
                elif "properties" in target and k in target["properties"]: target = target["properties"][k]
                elif "$defs" in target and k in target["$defs"]: target = target["$defs"][k]
            else: target = target[k]
        if "type" in target: del target["type"]
        td = _with_pin(s2)
        r = _run(f"{td}/scripts/review/validate-findings.py", "/nonexistent")
        n += 1
        if r.returncode != 2:
            bad += 1; print(f"MISS notype {path}: rc={r.returncode}")
        shutil.rmtree(td)

elif MODE == "enforce":
    td_doc = tempfile.mkdtemp()
    # One doc violation per enforced keyword
    for t, kws in ENFORCED.items():
        for kw in sorted(kws):
            d = copy.deepcopy(valid)
            if kw == "required": del d["findings"][0]["evidence"]
            elif kw == "additionalProperties": d["findings"][0]["zzz"] = 1
            elif kw == "properties": d["reviewed_head"] = 42
            elif kw == "items": d["findings"] = [42]
            elif kw == "minItems": d["findings"][0]["lines"] = [1]
            elif kw == "maxItems": d["findings"][0]["lines"] = [1,2,3]
            elif kw == "enum": d["findings"][0]["severity"] = "bogus"
            elif kw == "pattern": d["reviewed_head"] = "short"
            elif kw == "maxLength": d["findings"][0]["summary"] = "x" * 300
            elif kw == "minimum": d["findings"][0]["lines"] = [-1, 2]
            else: continue
            p = f"{td_doc}/m{n}.json"; json.dump(d, open(p, "w"))
            r = _run(V, p)
            n += 1
            if r.returncode != 1 or "Traceback" in r.stdout+r.stderr:
                bad += 1; print(f"MISS enforce {t}/{kw}: rc={r.returncode}")
    shutil.rmtree(td_doc)

print(f"mode={MODE} executed={n} bad={bad}")
sys.exit(1 if bad else 0)

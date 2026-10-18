#!/usr/bin/env python3
"""psak independent generated document sweep for #171 v3: one mutant per constraint of the real schema."""
import copy, json, os, subprocess, sys, tempfile

V, S = sys.argv[1], sys.argv[2]
schema = json.load(open(S))
defs = schema["$defs"]
valid = {"reviewed_head": "a" * 40, "pass": "code-reviewer", "complete": True,
  "findings": [{"file": "x", "lines": [1, 2], "severity": "critical",
    "category": "c", "family": "f", "summary": "s", "evidence": "e"}],
  "probe_requests": [{"id": "p-1", "command": "echo", "purpose": "p", "expected": "e"}]}
WRONG = {"string": 42, "integer": "x", "boolean": "yes", "array": {}, "object": []}

def resolve(n):
    return defs[n["$ref"].split("/")[-1]] if "$ref" in n else n

muts = []  # (label, expected_path_prefix, doc)
def gen(node, doc_path, getter):
    node = resolve(node)
    t = node.get("type")
    def setv(val, p=doc_path):
        d = copy.deepcopy(valid); getter(d, val); muts.append((f"{p} type/{val!r}"[:60], p, d))
    if t in WRONG and getter is None:
        muts.append(("$ type", "$", WRONG[t]))
    elif t in WRONG:
        d = copy.deepcopy(valid); getter(d, WRONG[t]); muts.append((f"{doc_path} type", doc_path, d))
    if "enum" in node:
        d = copy.deepcopy(valid); getter(d, "zz-not-enum"); muts.append((f"{doc_path} enum", doc_path, d))
    if "pattern" in node:
        d = copy.deepcopy(valid); getter(d, "BAD PATTERN!"); muts.append((f"{doc_path} pattern", doc_path, d))
    if "maxLength" in node:
        d = copy.deepcopy(valid); getter(d, "a" * (node["maxLength"] + 1)); muts.append((f"{doc_path} maxLength", doc_path, d))
    if "minimum" in node:
        d = copy.deepcopy(valid); getter(d, node["minimum"] - 1); muts.append((f"{doc_path} minimum", doc_path, d))
    if "minItems" in node:
        d = copy.deepcopy(valid); getter(d, [1] * (node["minItems"] - 1)); muts.append((f"{doc_path} minItems", doc_path, d))
    if "maxItems" in node:
        d = copy.deepcopy(valid); getter(d, [1] * (node["maxItems"] + 1)); muts.append((f"{doc_path} maxItems", doc_path, d))
    if t == "object":
        def get_obj(d):
            box = {}
            getter(d, box)  # placeholder trick not usable; handled below
        for k in node.get("required", []):
            def rm(d, k=k):
                o = locate(d, doc_path); o.pop(k)
            d = copy.deepcopy(valid); rm(d); muts.append((f"{doc_path}.{k} required", f"{doc_path}.{k}", d))
        if node.get("additionalProperties") is False:
            d = copy.deepcopy(valid); locate(d, doc_path)["zz_extra"] = 1; muts.append((f"{doc_path} additionalProperties", doc_path, d))
        for k, v in node.get("properties", {}).items():
            gen(v, f"{doc_path}.{k}", lambda d, val, k=k: locate(d, doc_path).__setitem__(k, val))
    if t == "array" and "items" in node:
        gen(node["items"], f"{doc_path}[0]", lambda d, val: locate(d, doc_path).__setitem__(0, val))

def locate(d, p):
    cur = d
    import re
    for tok in re.findall(r"\.([A-Za-z_]+)|\[(\d+)\]", p[1:]):
        cur = cur[tok[0]] if tok[0] else cur[int(tok[1])]
    return cur

gen(schema, "$", None)
td = tempfile.mkdtemp()
bad = 0
for i, (label, path, d) in enumerate(muts):
    f = os.path.join(td, f"m{i}.json"); json.dump(d, open(f, "w"))
    r = subprocess.run([sys.executable, "-I", V, f], capture_output=True, text=True)
    out = r.stdout + r.stderr
    ok = r.returncode == 1 and "Traceback" not in out and out.startswith(path)
    if not ok:
        bad += 1
        print(f"MISS {label}: rc={r.returncode} out={out.strip()[:100]!r}")
print(f"generated={len(muts)} bad={bad}")

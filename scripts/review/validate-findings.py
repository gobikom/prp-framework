#!/usr/bin/env python3
"""Validate JSON against the pinned review-findings schema.
usage: validate-findings.py <doc.json>                 exit 0=valid, 1=doc invalid (JSON path), 2=schema refused, 3=usage/IO
       validate-findings.py --enforce-caps <doc.json>  round-7 fix (#185): print the doc as ONE line with every
       findings/probe_requests element that breaks a schema length cap dropped, then one
       '- L2-FINDING-CAP <element>.<field> <len>><cap> not-posted' line per breach. Exit 0 even
       when elements were dropped — a cap breach never loses the round, it is named. Surviving
       elements are untouched (byte-preserved through json round-trip). 1=not JSON/not an object.
HANDLERS is the single source of keyword checks; ENFORCED is derived from it."""
import hashlib, json, os, re, sys

SCHEMA_SHA256 = "bf4f8086c7f7c8c2a863075d80606b627c82f8ca5c1bcac9d74137843b442165"
ANNOTATIONS = {"title", "description"}
ROOT_ONLY = {"$schema", "$defs"}
REF_PAT = re.compile(r'^#/\$defs/[A-Za-z0-9_]+$')

def _is_int(v): return isinstance(v, int) and not isinstance(v, bool)

def _check_shape(k, v, path):
    if k == "type": return None if isinstance(v, str) and v in ENFORCED else f"schema {path}: invalid type"
    if k == "properties": return None if isinstance(v, dict) and all(isinstance(x, dict) for x in v.values()) else f"schema {path}: properties shape"
    if k == "required": return None if isinstance(v, list) and all(isinstance(x, str) for x in v) else f"schema {path}: required shape"
    if k == "additionalProperties": return None if v is False else f"schema {path}: additionalProperties must be false"
    if k == "items": return None if isinstance(v, dict) else f"schema {path}: items shape"
    if k in ("minItems", "maxItems", "maxLength"): return None if _is_int(v) and v >= 0 else f"schema {path}: {k} shape"
    if k == "minimum": return None if _is_int(v) else f"schema {path}: minimum shape"
    if k == "enum":
        if not isinstance(v, list) or not v: return f"schema {path}: enum shape"
        if any(not isinstance(x, (str, int, bool)) or isinstance(x, float) for x in v): return f"schema {path}: enum item shape"
        return None
    if k == "pattern":
        if not isinstance(v, str): return f"schema {path}: pattern shape"
        try: re.compile(v); return None
        except re.error as e: return f"schema {path}: pattern: {e}"
    if k in ("title", "description", "$schema"): return None if isinstance(v, str) else f"schema {path}: {k} shape"
    if k == "$defs": return None if isinstance(v, dict) and all(isinstance(x, dict) for x in v.values()) else f"schema {path}: $defs shape"
    return f"schema {path}: unknown keyword '{k}'"

def check_schema(schema):
    if not isinstance(schema, dict): return "schema $: not an object"
    defs = schema.get("$defs", {})
    def walk(node, path, visited_refs=None, is_root=False):
        if visited_refs is None: visited_refs = set()
        if not isinstance(node, dict): return f"schema {path}: not an object"
        if "$ref" in node:
            ref = node["$ref"]
            if not isinstance(ref, str): return f"schema {path}: $ref not a string"
            if not REF_PAT.match(ref): return f"schema {path}: $ref bad format"
            extras = set(node.keys()) - {"$ref"} - ANNOTATIONS
            if extras: return f"schema {path}: $ref has sibling keys {extras}"
            name = ref.split("/")[-1]
            if name not in defs: return f"schema {path}: $ref dangling '{name}'"
            if name in visited_refs: return f"schema {path}: $ref cycle on '{name}'"
            return walk(defs[name], f"$defs.{name}", visited_refs | {name})
        t = node.get("type")
        if t is None: return f"schema {path}: missing type"
        if not isinstance(t, str) or t not in ENFORCED: return f"schema {path}: invalid type '{t}'"
        allowed = ENFORCED[t] | ANNOTATIONS | {"type"}
        if is_root: allowed |= ROOT_ONLY
        for k in node:
            if k not in allowed: return f"schema {path}: keyword '{k}' not allowed for type '{t}'"
            err = _check_shape(k, node[k], path)
            if err: return err
        if "required" in node and "properties" in node:
            for rk in node["required"]:
                if rk not in node["properties"]: return f"schema {path}: required key '{rk}' not in properties"
        for pk, pv in node.get("properties", {}).items():
            err = walk(pv, f"{path}.{pk}", visited_refs)
            if err: return err
        if "items" in node and isinstance(node.get("items"), dict):
            err = walk(node["items"], f"{path}[]", visited_refs)
            if err: return err
        if is_root:
            for dk, dv in defs.items():
                err = walk(dv, f"$defs.{dk}", visited_refs)
                if err: return err
        return None
    return walk(schema, "$", is_root=True)

def _h_properties(doc, node, defs, path):
    for k, v in node["properties"].items():
        if k in doc:
            err = validate(doc[k], v, defs, f"{path}.{k}")
            if err: return err
def _h_required(doc, node, defs, path):
    for k in node["required"]:
        if k not in doc: return f"{path}.{k}: required field missing"
def _h_additionalProperties(doc, node, defs, path):
    extra = set(doc.keys()) - set(node.get("properties", {}).keys())
    if extra: return f"{path}: unknown key(s) {extra}"
def _h_items(doc, node, defs, path):
    for i, item in enumerate(doc):
        err = validate(item, node["items"], defs, f"{path}[{i}]")
        if err: return err
def _h_minItems(doc, node, defs, path):
    if len(doc) < node["minItems"]: return f"{path}: too few items"
def _h_maxItems(doc, node, defs, path):
    if len(doc) > node["maxItems"]: return f"{path}: too many items"
def _h_enum(doc, node, defs, path):
    if doc not in node["enum"]: return f"{path}: not in enum"
def _h_pattern(doc, node, defs, path):
    if not re.fullmatch(node["pattern"], doc): return f"{path}: pattern mismatch"
def _h_maxLength(doc, node, defs, path):
    if len(doc) > node["maxLength"]: return f"{path}: too long"
def _h_minimum(doc, node, defs, path):
    if _is_int(doc) and doc < node["minimum"]: return f"{path}: below minimum"

HANDLERS = {
    "object":  {"properties": _h_properties, "required": _h_required, "additionalProperties": _h_additionalProperties},
    "array":   {"items": _h_items, "minItems": _h_minItems, "maxItems": _h_maxItems},
    "string":  {"enum": _h_enum, "pattern": _h_pattern, "maxLength": _h_maxLength},
    "integer": {"minimum": _h_minimum, "enum": _h_enum},
    "boolean": {},
}
ENFORCED = {t: set(hs) for t, hs in HANDLERS.items()}
SUPPORTED = {"type"} | ANNOTATIONS | ROOT_ONLY | set().union(*ENFORCED.values())

def validate(doc, node, defs, path="$"):
    if "$ref" in node:
        return validate(doc, defs[node["$ref"].split("/")[-1]], defs, path)
    t = node["type"]
    tmap = {"string": str, "boolean": bool, "integer": int, "array": list, "object": dict}
    if t == "integer" and isinstance(doc, bool): return f"{path}: expected integer, got bool"
    if not isinstance(doc, tmap[t]): return f"{path}: expected {t}, got {type(doc).__name__}"
    for k in node:
        if k in ANNOTATIONS or k == "type": continue
        handler = HANDLERS[t].get(k)
        if handler:
            err = handler(doc, node, defs, path)
            if err: return err
    return None

def _no_dupes(pairs):
    keys = [k for k, _ in pairs]
    if len(keys) != len(set(keys)): raise ValueError("duplicate JSON key")
    return dict(pairs)

def enforce_caps(doc, defs):
    """(#185 round-7 fix) drop findings/probe_requests elements that break a schema length
    cap; return (doc, breaches), each breach a (path, length, cap) triple. A dropped element
    is named per breached field; surviving elements are returned untouched — the caller
    never edits a finding."""
    breaches = []
    for key, dname in (("findings", "finding"), ("probe_requests", "probe_request")):
        caps = {f: spec["maxLength"] for f, spec in defs.get(dname, {}).get("properties", {}).items()
                if isinstance(spec, dict) and isinstance(spec.get("maxLength"), int)}
        elems = doc.get(key)
        if not isinstance(elems, list): continue
        keep = []
        for i, el in enumerate(elems):
            bad = []
            if isinstance(el, dict):
                for f, cap in caps.items():
                    if isinstance(el.get(f), str) and len(el[f]) > cap:
                        bad.append((f"{key}[{i}].{f}", len(el[f]), cap))
            breaches.extend(bad)
            if not bad: keep.append(el)
        doc[key] = keep
    return doc, breaches

if __name__ == "__main__":
    try:
        if len(sys.argv) == 2:
            mode, doc_path = "check", sys.argv[1]
        elif len(sys.argv) == 3 and sys.argv[1] == "--enforce-caps":
            mode, doc_path = "enforce", sys.argv[2]
        else:
            print("usage: validate-findings.py <doc.json> | validate-findings.py --enforce-caps <doc.json>", file=sys.stderr); sys.exit(3)
        sp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../schemas/review-findings.schema.json")
        try: raw = open(sp, "rb").read()
        except OSError as e: print(f"schema: {e}", file=sys.stderr); sys.exit(2)
        if hashlib.sha256(raw).hexdigest() != SCHEMA_SHA256:
            print("schema is not the pinned review-findings schema", file=sys.stderr); sys.exit(2)
        schema = json.loads(raw)
        err = check_schema(schema)
        if err: print(err, file=sys.stderr); sys.exit(2)
        if mode == "enforce":
            try: doc = json.load(open(doc_path), object_pairs_hook=_no_dupes)
            except OSError as e: print(f"doc: {e}", file=sys.stderr); sys.exit(3)
            except (json.JSONDecodeError, ValueError) as e: print(f"doc: {e}", file=sys.stderr); sys.exit(1)
            if not isinstance(doc, dict): print("doc: not a JSON object", file=sys.stderr); sys.exit(1)
            doc, breaches = enforce_caps(doc, schema.get("$defs", {}))
            print(json.dumps(doc, separators=(",", ":")))
            for path, ln, cap in breaches:
                print(f"- L2-FINDING-CAP {path} {ln}>{cap} not-posted")
            sys.exit(0)
        try: doc = json.load(open(doc_path))
        except (OSError, json.JSONDecodeError) as e: print(f"doc: {e}", file=sys.stderr); sys.exit(3)
        err = validate(doc, schema, schema.get("$defs", {}))
        if err: print(err, file=sys.stderr); sys.exit(1)
    except SystemExit: raise
    except Exception as e: print(f"internal error: {e}", file=sys.stderr); sys.exit(3)

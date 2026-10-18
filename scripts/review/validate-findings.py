#!/usr/bin/env python3
"""Validate JSON against the pinned review-findings schema.
Exit 0=valid, 1=doc invalid (JSON path), 2=schema refused, 3=usage/IO.
One table (ENFORCED) drives both check_schema and validate, so the two cannot drift."""
import hashlib, json, os, re, sys

SCHEMA_SHA256 = "1250e78a6805c0ac543737045b0176290945a84cba93a31c171bd350767ccc4d"
ENFORCED = {
    "object":  {"properties", "required", "additionalProperties"},
    "array":   {"items", "minItems", "maxItems"},
    "string":  {"enum", "pattern", "maxLength"},
    "integer": {"minimum", "enum"},
    "boolean": set(),
}
ANNOTATIONS = {"title", "description"}
ROOT_ONLY = {"$schema", "$defs"}
SUPPORTED = {"type"} | ANNOTATIONS | ROOT_ONLY | set().union(*ENFORCED.values())
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

def validate(doc, node, defs, path="$"):
    if "$ref" in node:
        return validate(doc, defs[node["$ref"].split("/")[-1]], defs, path)
    t = node["type"]
    tmap = {"string": str, "boolean": bool, "integer": int, "array": list, "object": dict}
    if t == "integer" and isinstance(doc, bool): return f"{path}: expected integer, got bool"
    if not isinstance(doc, tmap[t]): return f"{path}: expected {t}, got {type(doc).__name__}"
    if t == "object":
        for k in node.get("required", []):
            if k not in doc: return f"{path}.{k}: required field missing"
        props = node.get("properties", {})
        if node.get("additionalProperties") is False:
            extra = set(doc.keys()) - set(props.keys())
            if extra: return f"{path}: unknown key(s) {extra}"
        for k, v in props.items():
            if k in doc:
                err = validate(doc[k], v, defs, f"{path}.{k}")
                if err: return err
    if t == "array" and "items" in node:
        for i, item in enumerate(doc):
            err = validate(item, node["items"], defs, f"{path}[{i}]")
            if err: return err
    if "enum" in node and doc not in node["enum"]: return f"{path}: not in enum"
    if "pattern" in node and isinstance(doc, str) and not re.fullmatch(node["pattern"], doc):
        return f"{path}: pattern mismatch"
    if "maxLength" in node and isinstance(doc, str) and len(doc) > node["maxLength"]:
        return f"{path}: too long"
    if "minimum" in node and _is_int(doc) and doc < node["minimum"]:
        return f"{path}: below minimum"
    if "minItems" in node and isinstance(doc, list) and len(doc) < node["minItems"]:
        return f"{path}: too few items"
    if "maxItems" in node and isinstance(doc, list) and len(doc) > node["maxItems"]:
        return f"{path}: too many items"
    return None

if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            print("usage: validate-findings.py <doc.json>", file=sys.stderr); sys.exit(3)
        sp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../schemas/review-findings.schema.json")
        try: raw = open(sp, "rb").read()
        except OSError as e: print(f"schema: {e}", file=sys.stderr); sys.exit(2)
        if hashlib.sha256(raw).hexdigest() != SCHEMA_SHA256:
            print("schema is not the pinned review-findings schema", file=sys.stderr); sys.exit(2)
        schema = json.loads(raw)
        err = check_schema(schema)
        if err: print(err, file=sys.stderr); sys.exit(2)
        try: doc = json.load(open(sys.argv[1]))
        except (OSError, json.JSONDecodeError) as e: print(f"doc: {e}", file=sys.stderr); sys.exit(3)
        err = validate(doc, schema, schema.get("$defs", {}))
        if err: print(err, file=sys.stderr); sys.exit(1)
    except SystemExit: raise
    except Exception as e: print(f"internal error: {e}", file=sys.stderr); sys.exit(3)

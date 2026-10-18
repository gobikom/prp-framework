#!/usr/bin/env python3
"""Validate JSON against the pinned review-findings schema.
Exit 0=valid, 1=doc invalid (JSON path), 2=schema refused, 3=usage/IO."""
import hashlib, json, os, re, sys

SCHEMA_SHA256 = "1250e78a6805c0ac543737045b0176290945a84cba93a31c171bd350767ccc4d"
SUPPORTED = {"type","properties","required","additionalProperties","items","minItems",
    "maxItems","enum","pattern","maxLength","minimum","$ref","title","description","$schema","$defs"}
VALID_TYPES = {"object","array","string","integer","boolean"}
REF_PAT = re.compile(r'^#/\$defs/[A-Za-z0-9_]+$')

def _is_int(v): return isinstance(v, int) and not isinstance(v, bool)

def check_schema(schema):
    """Walk the pinned schema once, checking every keyword value shape."""
    defs = schema.get("$defs", {})
    def walk(node, path, visited_refs=None, is_root=False):
        if visited_refs is None: visited_refs = set()
        if not isinstance(node, dict): return f"schema {path}: not an object"
        if "$ref" in node:
            ref = node["$ref"]
            if not isinstance(ref, str): return f"schema {path}: $ref not a string"
            if not REF_PAT.match(ref): return f"schema {path}: $ref bad format '{ref}'"
            extras = set(node.keys()) - {"$ref", "title", "description"}
            if extras: return f"schema {path}: $ref has sibling keys {extras}"
            name = ref.split("/")[-1]
            if name not in defs: return f"schema {path}: $ref dangling '{name}'"
            if name in visited_refs: return f"schema {path}: $ref cycle on '{name}'"
            return walk(defs[name], f"$defs.{name}", visited_refs | {name})
        for k in node:
            if k not in SUPPORTED: return f"schema {path}: unsupported keyword '{k}'"
        # Value shape checks
        for k, v in node.items():
            if k == "type":
                if not isinstance(v, str) or v not in VALID_TYPES: return f"schema {path}: invalid type '{v}'"
            elif k == "properties":
                if not isinstance(v, dict): return f"schema {path}: properties must be dict"
                for pk, pv in v.items():
                    if not isinstance(pv, dict): return f"schema {path}.{pk}: property must be dict"
            elif k == "required":
                if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
                    return f"schema {path}: required must be list of str"
                props = node.get("properties", {})
                for rk in v:
                    if rk not in props: return f"schema {path}: required key '{rk}' not in properties"
            elif k == "additionalProperties":
                if v is not False: return f"schema {path}: additionalProperties must be false"
            elif k == "items":
                if not isinstance(v, dict): return f"schema {path}: items must be dict"
            elif k in ("minItems", "maxItems", "maxLength"):
                if not _is_int(v) or v < 0: return f"schema {path}: {k} must be int >= 0"
            elif k == "minimum":
                if not _is_int(v): return f"schema {path}: minimum must be int"
            elif k == "enum":
                if not isinstance(v, list) or not v: return f"schema {path}: enum must be non-empty list"
                for ei, ev in enumerate(v):
                    if not isinstance(ev, (str, int, bool)) or isinstance(ev, float):
                        return f"schema {path}: enum[{ei}] has invalid type {type(ev).__name__}"
            elif k == "pattern":
                if not isinstance(v, str): return f"schema {path}: pattern must be str"
                try: re.compile(v)
                except re.error as e: return f"schema {path}: invalid pattern: {e}"
            elif k in ("title", "description", "$schema"):
                if not isinstance(v, str): return f"schema {path}: {k} must be str"
            elif k == "$defs":
                if not is_root: return f"schema {path}: $defs only at root"
                if not isinstance(v, dict): return f"schema {path}: $defs must be dict"
                for dk, dv in v.items():
                    if not isinstance(dv, dict): return f"schema {path}: $defs.{dk} must be dict"
        # Recurse into properties, items, $defs
        for pk, pv in node.get("properties", {}).items():
            err = walk(pv, f"{path}.{pk}", visited_refs)
            if err: return err
        if "items" in node and isinstance(node.get("items"), dict):
            err = walk(node["items"], f"{path}[]", visited_refs)
            if err: return err
        if is_root:
            for dk, dv in node.get("$defs", {}).items():
                if isinstance(dv, dict):
                    err = walk(dv, f"$defs.{dk}", visited_refs)
                    if err: return err
        return None
    return walk(schema, "$", is_root=True)

def validate(doc, node, defs, path="$"):
    if "$ref" in node:
        return validate(doc, defs[node["$ref"].split("/")[-1]], defs, path)
    t = node.get("type")
    tmap = {"string": str, "boolean": bool, "integer": int, "array": list, "object": dict}
    if t in tmap:
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

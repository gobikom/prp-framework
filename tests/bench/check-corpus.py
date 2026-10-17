#!/usr/bin/env python3
"""Validate a corpus YAML file against the schema and label invariant.

Usage: python3 -I tests/bench/check-corpus.py <path>
Exit 0 = valid. Exit 1 = violation (message on stderr).
"""
import sys, yaml

REQUIRED = {"id","pr","head","base","patch_digest","permalink","kind","tier",
            "files_changed","additions","deletions","labels"}
VALID_KIND = {"positive", "negative"}
VALID_TIER = {"standard", "trivial", "docs", "gate"}
VALID_SEV = {"critical", "important"}
LABEL_FIELDS = {"file","lines","defect","severity","family","source_pass","comment_url"}

def check(path: str) -> list[str]:
    errors: list[str] = []
    with open(path) as f:
        corpus = yaml.safe_load(f)
    entries = corpus.get("entries", [])
    if not entries:
        return ["no entries"]
    ids = [e.get("id") for e in entries]
    dupes = [x for x in set(ids) if ids.count(x) > 1]
    if dupes:
        errors.append(f"duplicate ids: {dupes}")
    for e in entries:
        eid = e.get("id", "?")
        missing = REQUIRED - set(e.keys())
        if missing:
            errors.append(f"{eid}: missing fields {missing}"); continue
        if len(e["head"]) != 40 or len(e["base"]) != 40:
            errors.append(f"{eid}: head/base must be 40 hex chars")
        if len(e["patch_digest"]) != 64:
            errors.append(f"{eid}: patch_digest must be 64 hex chars")
        if e["kind"] not in VALID_KIND:
            errors.append(f"{eid}: invalid kind '{e['kind']}'")
        if e["tier"] not in VALID_TIER:
            errors.append(f"{eid}: invalid tier '{e['tier']}'")
        if not isinstance(e["labels"], list):
            errors.append(f"{eid}: labels must be a list"); continue
        if e["kind"] == "negative" and e["labels"]:
            errors.append(f"{eid}: negative entry must have labels: []")
        if e["kind"] == "positive" and not e["labels"]:
            errors.append(f"{eid}: positive entry must have at least 1 label")
        for i, lab in enumerate(e["labels"]):
            lm = LABEL_FIELDS - set(lab.keys())
            if lm:
                errors.append(f"{eid} label {i}: missing {lm}"); continue
            if not isinstance(lab["lines"], list) or len(lab["lines"]) != 2:
                errors.append(f"{eid} label {i}: lines must be [start, end]")
            elif lab["lines"][0] > lab["lines"][1]:
                errors.append(f"{eid} label {i}: start > end")
            if lab["severity"] not in VALID_SEV:
                errors.append(f"{eid} label {i}: severity '{lab['severity']}' not in {VALID_SEV}")
            if not isinstance(lab.get("source_pass"), list) or not lab["source_pass"]:
                errors.append(f"{eid} label {i}: source_pass must be a non-empty list")
    c = sum(1 for e in entries for l in e["labels"] if l.get("severity") == "critical")
    i = sum(1 for e in entries for l in e["labels"] if l.get("severity") == "important")
    total = sum(len(e["labels"]) for e in entries)
    if c + i != total:
        errors.append(f"c+i={c+i} != total labels {total}: a label not in critical|important")
    return errors

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else None
    if not path:
        print("usage: check-corpus.py <path>", file=sys.stderr); sys.exit(2)
    errs = check(path)
    for e in errs:
        print(e, file=sys.stderr)
    sys.exit(1 if errs else 0)

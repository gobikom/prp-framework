#!/usr/bin/env python3
"""Validate a corpus YAML file against the schema and label invariant.

Usage: python3 -I tests/bench/check-corpus.py <path>
Exit 0 = valid. Exit 1 = violation (messages on stderr).

check(path) NEVER raises for any file content. It returns the complete list of
violations. Every entry is either fully validated or has its problem reported by
id. Aggregates are computed only over entries that passed every structural check.
"""
import sys

ENTRY_TYPES = {
    "id": str, "pr": int, "head": str, "base": str, "patch_digest": str,
    "permalink": str, "kind": str, "tier": str, "files_changed": int,
    "additions": int, "deletions": int,
}
LABEL_STR_FIELDS = {"file", "defect", "family", "comment_url", "severity"}
REQUIRED = set(ENTRY_TYPES) | {"labels"}
VALID_KIND = {"positive", "negative"}
VALID_TIER = {"standard", "trivial", "docs", "gate"}
VALID_SEV = {"critical", "important"}
LABEL_FIELDS = LABEL_STR_FIELDS | {"lines", "source_pass"}


def _check_type(val, expected, name):
    if expected is int:
        if isinstance(val, bool) or not isinstance(val, int):
            return f"{name}: expected int, got {type(val).__name__}"
    elif not isinstance(val, expected):
        return f"{name}: expected {expected.__name__}, got {type(val).__name__}"
    return None


def check(path: str) -> list[str]:
    try:
        import yaml
    except ImportError:
        return ["PyYAML not installed"]
    try:
        with open(path) as f:
            corpus = yaml.safe_load(f)
    except Exception as e:
        return [f"{type(e).__name__}: {e}"]

    if not isinstance(corpus, dict):
        return [f"top level must be a mapping, got {type(corpus).__name__}"]
    raw_entries = corpus.get("entries")
    if not isinstance(raw_entries, list):
        return [f"entries must be a list, got {type(raw_entries).__name__}"]
    if not raw_entries:
        return ["no entries"]

    errors: list[str] = []
    valid_entries: list[dict] = []
    valid_ids: list[str] = []

    for idx, e in enumerate(raw_entries):
        if not isinstance(e, dict):
            errors.append(f"entry {idx}: expected a mapping, got {type(e).__name__}")
            continue
        eid_raw = e.get("id", f"(entry {idx})")
        eid = eid_raw if isinstance(eid_raw, str) else f"(entry {idx})"
        if isinstance(eid_raw, str):
            valid_ids.append(eid)
        missing = REQUIRED - set(e.keys())
        if missing:
            errors.append(f"{eid}: missing fields {missing}")
            continue

        entry_ok = True
        for field, expected in ENTRY_TYPES.items():
            err = _check_type(e[field], expected, f"{eid}.{field}")
            if err:
                errors.append(err)
                entry_ok = False
        if not entry_ok:
            continue

        if len(e["head"]) != 40:
            errors.append(f"{eid}: head must be 40 chars"); continue
        if len(e["base"]) != 40:
            errors.append(f"{eid}: base must be 40 chars"); continue
        if len(e["patch_digest"]) != 64:
            errors.append(f"{eid}: patch_digest must be 64 chars"); continue
        if e["kind"] not in VALID_KIND:
            errors.append(f"{eid}: invalid kind '{e['kind']}'"); continue
        if e["tier"] not in VALID_TIER:
            errors.append(f"{eid}: invalid tier '{e['tier']}'"); continue
        if not isinstance(e["labels"], list):
            errors.append(f"{eid}: labels must be a list, got {type(e['labels']).__name__}"); continue
        if e["kind"] == "negative" and e["labels"]:
            errors.append(f"{eid}: negative entry must have labels: []"); continue
        if e["kind"] == "positive" and not e["labels"]:
            errors.append(f"{eid}: positive entry must have at least 1 label"); continue

        label_ok = True
        for i, lab in enumerate(e["labels"]):
            if not isinstance(lab, dict):
                errors.append(f"{eid} label {i}: expected a mapping, got {type(lab).__name__}")
                label_ok = False; continue
            lm = LABEL_FIELDS - set(lab.keys())
            if lm:
                errors.append(f"{eid} label {i}: missing {lm}")
                label_ok = False; continue
            for sf in LABEL_STR_FIELDS:
                err = _check_type(lab[sf], str, f"{eid} label {i}.{sf}")
                if err:
                    errors.append(err); label_ok = False
            if not isinstance(lab["lines"], list) or len(lab["lines"]) != 2:
                errors.append(f"{eid} label {i}: lines must be [start, end]")
                label_ok = False
            elif not all(isinstance(x, int) and not isinstance(x, bool) for x in lab["lines"]):
                errors.append(f"{eid} label {i}: lines values must be int")
                label_ok = False
            elif lab["lines"][0] > lab["lines"][1]:
                errors.append(f"{eid} label {i}: start > end")
                label_ok = False
            if isinstance(lab["severity"], str) and lab["severity"] not in VALID_SEV:
                errors.append(f"{eid} label {i}: severity '{lab['severity']}' not in {VALID_SEV}")
                label_ok = False
            if not isinstance(lab["source_pass"], list) or not lab["source_pass"]:
                errors.append(f"{eid} label {i}: source_pass must be a non-empty list")
                label_ok = False
            elif not all(isinstance(s, str) for s in lab["source_pass"]):
                errors.append(f"{eid} label {i}: source_pass items must be str")
                label_ok = False

        if label_ok:
            valid_entries.append(e)

    dupes = sorted(set(x for x in valid_ids if valid_ids.count(x) > 1))
    if dupes:
        errors.append(f"duplicate ids: {dupes}")

    c = sum(1 for e in valid_entries for l in e["labels"] if l["severity"] == "critical")
    i = sum(1 for e in valid_entries for l in e["labels"] if l["severity"] == "important")
    total = sum(len(e["labels"]) for e in valid_entries)
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

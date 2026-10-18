#!/usr/bin/env python3
"""psak: one malformed pinned schema per keyword-value-shape rule; each must exit 2 with a 'schema ' line, doc unopened."""
import json, hashlib, re, os, sys, subprocess, tempfile, shutil, copy
V, S = sys.argv[1], sys.argv[2]
base = json.load(open(S))
def F(s): return s['$defs']['finding']
def L(s): return F(s)['properties']['lines']
cases = {
 'type-int':        lambda s: F(s).__setitem__('type', 5),
 'type-unknown':    lambda s: F(s).__setitem__('type', 'number'),
 'props-val-str':   lambda s: F(s)['properties'].__setitem__('file', 'x'),
 'required-int':    lambda s: F(s)['required'].append(3),
 'required-unknown':lambda s: F(s)['required'].append('nope'),
 'addl-true':       lambda s: F(s).__setitem__('additionalProperties', True),
 'addl-obj':        lambda s: F(s).__setitem__('additionalProperties', {}),
 'items-str':       lambda s: L(s).__setitem__('items', 'x'),
 'minItems-bool':   lambda s: L(s).__setitem__('minItems', True),
 'minItems-neg':    lambda s: L(s).__setitem__('minItems', -1),
 'maxItems-str':    lambda s: L(s).__setitem__('maxItems', '2'),
 'maxLength-float': lambda s: F(s)['properties']['summary'].__setitem__('maxLength', 1.5),
 'minimum-bool':    lambda s: L(s)['items'].__setitem__('minimum', False),
 'enum-empty':      lambda s: F(s)['properties']['severity'].__setitem__('enum', []),
 'enum-str':        lambda s: F(s)['properties']['severity'].__setitem__('enum', 'critical'),
 'enum-obj-item':   lambda s: F(s)['properties']['severity']['enum'].append({}),
 'pattern-bad-re':  lambda s: s['properties']['reviewed_head'].__setitem__('pattern', '(['),
 'pattern-int':     lambda s: s['properties']['reviewed_head'].__setitem__('pattern', 5),
 'title-int':       lambda s: F(s).__setitem__('title', 1),
 'description-list':lambda s: F(s).__setitem__('description', []),
 'schema-int':      lambda s: s.__setitem__('$schema', 1),
 'defs-nonroot':    lambda s: F(s).__setitem__('$defs', {'a': {'type': 'string'}}),
 'defs-val-str':    lambda s: s['$defs'].__setitem__('zz', 'x'),
 'ref-sibling-max': lambda s: s['properties']['findings']['items'].__setitem__('maxItems', 1),
 'node-list':       lambda s: F(s)['properties'].__setitem__('file', []),
}
bad = 0
for name, mut in cases.items():
    td = tempfile.mkdtemp(); os.makedirs(f'{td}/scripts/review'); os.makedirs(f'{td}/schemas')
    s = copy.deepcopy(base)
    mut(s)  # no silent skip; construction errors are real bugs
    b = json.dumps(s, indent=2).encode(); open(f'{td}/schemas/review-findings.schema.json','wb').write(b)
    v = open(V).read(); v = re.sub(r'SCHEMA_SHA256 = "[0-9a-f]+"', f'SCHEMA_SHA256 = "{hashlib.sha256(b).hexdigest()}"', v)
    open(f'{td}/scripts/review/validate-findings.py','w').write(v)
    r = subprocess.run([sys.executable,'-I',f'{td}/scripts/review/validate-findings.py','/nonexistent-doc.json'],capture_output=True,text=True)
    out = (r.stdout + r.stderr).strip()
    ok = r.returncode == 2 and out.startswith('schema ') and 'Traceback' not in out
    if not ok: bad += 1; print(f'MISS {name}: rc={r.returncode} {out[:90]!r}')
    shutil.rmtree(td)
print(f'shape-cases={len(cases)} bad={bad}')

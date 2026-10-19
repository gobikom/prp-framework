#!/usr/bin/env bats
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
S="$REPO_ROOT/schemas/review-findings.schema.json"
V="$REPO_ROOT/scripts/review/validate-findings.py"
setup() { TEST_TMPDIR="$(mktemp -d)"; }
teardown() { rm -rf -- "$TEST_TMPDIR" 2>/dev/null || true; }

# Helper: create a validator copy with a mutated schema and recomputed pin
_mut_schema() {
  mkdir -p "$TEST_TMPDIR/scripts/review" "$TEST_TMPDIR/schemas"
  cp "$V" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  python3 -I -c "
import hashlib, json, sys
schema = json.load(open(sys.argv[1]))
$1
raw = json.dumps(schema).encode()
sha = hashlib.sha256(raw).hexdigest()
open(sys.argv[2], 'w').write(json.dumps(schema))
# Patch the validator's SCHEMA_SHA256
vcode = open(sys.argv[3]).read()
import re
vcode = re.sub(r'SCHEMA_SHA256 = \"[a-f0-9]+\"', f'SCHEMA_SHA256 = \"{sha}\"', vcode)
open(sys.argv[3], 'w').write(vcode)
" "$S" "$TEST_TMPDIR/schemas/review-findings.schema.json" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  run python3 -I "$TEST_TMPDIR/scripts/review/validate-findings.py" /nonexistent-doc
}

# --- pin and coverage ---
@test "pin: sha256 matches" {
  local got; got=$(sha256sum "$S" | cut -d' ' -f1)
  local expect; expect=$(grep 'SCHEMA_SHA256' "$V" | head -1 | grep -oP '"[a-f0-9]+"' | tr -d '"')
  [ "$got" = "$expect" ]
}
@test "check_schema passes on real schema" {
  printf '{"reviewed_head":"%s","pass":"code-reviewer","complete":true,"findings":[]}' "$(printf 'a%.0s' {1..40})" > "$TEST_TMPDIR/d.json"
  run python3 -I "$V" "$TEST_TMPDIR/d.json"
  [ "$status" -eq 0 ]
}
@test "keyword coverage: enforced-sweep notype covers every non-ref node" {
  # Already covered by the notype sweep — it checks every non-$ref node has type
  run python3 -I "$ES" "$V" "$S" notype
  [ "$status" -eq 0 ]
}
@test "pass enum = dispatched + probe" {
  run python3 -I - "$S" "$REPO_ROOT/adapters/claude-code/prp-review-agents.md" <<'PY'
import json, re, sys
e = set(json.load(open(sys.argv[1]))["properties"]["pass"]["enum"])
d = set(re.findall(r'subagent_type="([^"]+)"', open(sys.argv[2]).read())) | {"probe"}
if e != d: print(f"{e-d} {d-e}", file=sys.stderr); sys.exit(1)
PY
  [ "$status" -eq 0 ]
}

# --- check_schema mutants (each exits 2, path-bearing, doc not opened) ---
@test "schema: unsupported keyword → 2" {
  _mut_schema "schema['patternProperties'] = {}"
  [ "$status" -eq 2 ]; [[ "$output" == *"schema "* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: non-string \$ref → 2" {
  _mut_schema "schema['properties']['findings']['items'] = {'\$ref': 42}"
  [ "$status" -eq 2 ]; [[ "$output" == *"schema "* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: bad \$ref prefix → 2" {
  _mut_schema "schema['properties']['findings']['items'] = {'\$ref': 'bad/ref'}"
  [ "$status" -eq 2 ]; [[ "$output" == *"schema "* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: dangling \$ref at top-level item → 2" {
  _mut_schema "schema['properties']['findings']['items'] = {'\$ref': '#/\$defs/nope'}"
  [ "$status" -eq 2 ]; [[ "$output" == *"nope"* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: dangling \$ref inside \$defs → 2" {
  _mut_schema "schema['\$defs']['finding']['properties']['file'] = {'\$ref': '#/\$defs/gone'}"
  [ "$status" -eq 2 ]; [[ "$output" == *"gone"* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: \$ref cycle → 2" {
  _mut_schema "schema['\$defs']['finding']['properties']['file'] = {'\$ref': '#/\$defs/probe_request'}; schema['\$defs']['probe_request']['properties']['id'] = {'\$ref': '#/\$defs/finding'}"
  [ "$status" -eq 2 ]; [[ "$output" == *"cycle"* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: additionalProperties true → 2" {
  _mut_schema "schema['additionalProperties'] = True"
  [ "$status" -eq 2 ]; [[ "$output" == *"additionalProperties"* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: \$ref with sibling key → 2" {
  _mut_schema "schema['properties']['findings']['items']['bogus_kw'] = 1"
  [ "$status" -eq 2 ]; [[ "$output" == *"sibling"* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: required as string → 2" {
  _mut_schema "schema['\$defs']['finding']['required'] = 'file'"
  [ "$status" -eq 2 ]; [[ "$output" == *"required"* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: items as list → 2" {
  _mut_schema "schema['\$defs']['finding']['properties']['lines']['items'] = [{'type':'integer'}]"
  [ "$status" -eq 2 ]; [[ "$output" == *"items"* ]]; [[ "$output" != *"doc:"* ]]
}
@test "schema: properties as list → 2" {
  _mut_schema "schema['\$defs']['finding']['properties'] = [1]"
  [ "$status" -eq 2 ]; [[ "$output" == *"properties"* ]]; [[ "$output" != *"doc:"* ]]
}

# --- generated schema shape sweep ---
@test "schema shape sweep: 25 cases, exit 0" {
  run python3 -I "$REPO_ROOT/tests/scripts/fixtures/schema-shape-sweep.py" "$V" "$S"
  [ "$status" -eq 0 ]
  [[ "$output" =~ shape-cases=25( |$) ]] && [[ "$output" =~ bad=0( |$) ]]
}

# --- ENFORCED table sweeps ---
ES="$REPO_ROOT/tests/scripts/fixtures/enforced-sweep.py"
_expect() {
  python3 -I -c "
import importlib.util, json, sys
spec=importlib.util.spec_from_file_location('v',sys.argv[1])
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
E,A=m.ENFORCED,m.ANNOTATIONS; AK=set().union(*E.values())
if sys.argv[2]=='reject': print(sum(len(AK-E[t]-A-{'type'}) for t in E))
elif sys.argv[2]=='enforce': print(sum(len(E[t]) for t in E) * 2)
elif sys.argv[2]=='notype':
  s=json.load(open(sys.argv[3]))
  def w(n):
    c=0
    if '\$ref' not in n and 'type' in n: c=1
    for v in n.get('properties',{}).values():
      if isinstance(v,dict) and '\$ref' not in v: c+=w(v)
    if 'items' in n and isinstance(n.get('items'),dict) and '\$ref' not in n['items']: c+=w(n['items'])
    for v in n.get('\$defs',{}).values():
      if isinstance(v,dict) and '\$ref' not in v: c+=w(v)
    return c
  print(w(s))
" "$V" "$1" "$S"
}

@test "enforced-sweep reject: count and all pass" {
  local expect; expect=$(_expect reject)
  run python3 -I "$ES" "$V" "$S" reject
  [ "$status" -eq 0 ]; [[ "$output" != *"NO-CASE"* ]]
  [[ "$output" =~ executed=${expect}( |$) ]] && [[ "$output" =~ bad=0( |$) ]]
}
@test "enforced-sweep notype: count, all pass, includes items node" {
  local expect; expect=$(_expect notype)
  run python3 -I "$ES" "$V" "$S" notype
  [ "$status" -eq 0 ]; [[ "$output" == *"lines[]"* ]]
  [[ "$output" =~ executed=${expect}( |$) ]] && [[ "$output" =~ bad=0( |$) ]]
}
@test "enforced-sweep enforce: count and all pass" {
  local expect; expect=$(_expect enforce)
  run python3 -I "$ES" "$V" "$S" enforce
  [ "$status" -eq 0 ]; [[ "$output" != *"NO-CASE"* ]]
  [[ "$output" =~ executed=${expect}( |$) ]] && [[ "$output" =~ bad=0( |$) ]]
}
@test "mutation m1: add pattern to array HANDLERS → sweep fails" {
  mkdir -p "$TEST_TMPDIR/scripts/review"
  cp "$V" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  sed -i 's/"array":.*{"items"/"array": {"items": _h_items, "pattern": lambda d,n,df,p: None, "minItems"/' "$TEST_TMPDIR/scripts/review/validate-findings.py"
  grep -q '"pattern"' "$TEST_TMPDIR/scripts/review/validate-findings.py"
  run python3 -I "$ES" "$TEST_TMPDIR/scripts/review/validate-findings.py" "$S" enforce
  [ "$status" -ne 0 ]
}
@test "mutation m2: make one handler return None → enforce fails" {
  mkdir -p "$TEST_TMPDIR/scripts/review"
  cp "$V" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  sed -i 's/def _h_required(doc, node, defs, path):/def _h_required(doc, node, defs, path): return None;/' "$TEST_TMPDIR/scripts/review/validate-findings.py"
  run python3 -I "$ES" "$TEST_TMPDIR/scripts/review/validate-findings.py" "$S" enforce
  [ "$status" -ne 0 ]
}
@test "mutation m4: no-op handler → doc-sweep exits non-zero" {
  mkdir -p "$TEST_TMPDIR/scripts/review"
  cp "$V" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  sed -i 's/def _h_maxLength(doc, node, defs, path):/def _h_maxLength(doc, node, defs, path): return None;/' "$TEST_TMPDIR/scripts/review/validate-findings.py"
  grep -q 'return None;' "$TEST_TMPDIR/scripts/review/validate-findings.py"
  run python3 -I "$REPO_ROOT/tests/scripts/fixtures/doc-sweep.py" "$TEST_TMPDIR/scripts/review/validate-findings.py" "$S"
  [ "$status" -ne 0 ]
}
@test "mutation m3: remove one handler → enforce NO-CASE" {
  mkdir -p "$TEST_TMPDIR/scripts/review"
  cp "$V" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  sed -i '/"required": _h_required/d' "$TEST_TMPDIR/scripts/review/validate-findings.py"
  run python3 -I "$ES" "$TEST_TMPDIR/scripts/review/validate-findings.py" "$S" enforce
  [ "$status" -ne 0 ]
}

# --- doc validation ---
@test "valid doc → 0" {
  printf '{"reviewed_head":"%s","pass":"code-reviewer","complete":true,"findings":[{"file":"x","lines":[1,2],"severity":"critical","category":"c","family":"f","summary":"s","evidence":"e"}]}' "$(printf 'a%.0s' {1..40})" > "$TEST_TMPDIR/d.json"
  run python3 -I "$V" "$TEST_TMPDIR/d.json"; [ "$status" -eq 0 ]
}
@test "doc sweep: 53 mutants, exit 0" {
  run python3 -I "$REPO_ROOT/tests/scripts/fixtures/doc-sweep.py" "$V" "$S"
  [ "$status" -eq 0 ]
  [[ "$output" =~ generated=53( |$) ]] && [[ "$output" =~ bad=0( |$) ]]
}
@test "pin refusal: modified copy → 2, doc not opened" {
  mkdir -p "$TEST_TMPDIR/scripts/review" "$TEST_TMPDIR/schemas"
  cp "$V" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  python3 -I -c "import json; d=json.load(open('$S')); d['title']='X'; json.dump(d,open('$TEST_TMPDIR/schemas/review-findings.schema.json','w'))"
  run python3 -I "$TEST_TMPDIR/scripts/review/validate-findings.py" /nonexistent-doc
  [ "$status" -eq 2 ]; [[ "$output" == *"not the pinned"* ]]
}

# --- IO ---
@test "no arg → 3" { run python3 -I "$V"; [ "$status" -eq 3 ]; }
@test "two args → 3" { run python3 -I "$V" a b; [ "$status" -eq 3 ]; }
@test "missing doc → 3" { run python3 -I "$V" /x; [ "$status" -eq 3 ]; }
@test "bad doc JSON → 3" { echo x > "$TEST_TMPDIR/b.json"; run python3 -I "$V" "$TEST_TMPDIR/b.json"; [ "$status" -eq 3 ]; }
@test "non-object schema (list) → 2" {
  _mut_schema "schema.clear(); schema.update({'__list__': True})" 2>/dev/null || true
  # Use a direct approach: write a list as the schema
  mkdir -p "$TEST_TMPDIR/scripts/review" "$TEST_TMPDIR/schemas"
  cp "$V" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  local raw='[]'; local sha; sha=$(printf '%s' "$raw" | sha256sum | cut -d' ' -f1)
  printf '%s' "$raw" > "$TEST_TMPDIR/schemas/review-findings.schema.json"
  sed -i "s/SCHEMA_SHA256 = \"[a-f0-9]*/SCHEMA_SHA256 = \"$sha/" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  run python3 -I "$TEST_TMPDIR/scripts/review/validate-findings.py" /nonexistent
  [ "$status" -eq 2 ]; [[ "$output" == *"not an object"* ]]
}
@test "non-object schema (string) → 2" {
  mkdir -p "$TEST_TMPDIR/scripts/review" "$TEST_TMPDIR/schemas"
  cp "$V" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  local raw='"hello"'; local sha; sha=$(printf '%s' "$raw" | sha256sum | cut -d' ' -f1)
  printf '%s' "$raw" > "$TEST_TMPDIR/schemas/review-findings.schema.json"
  sed -i "s/SCHEMA_SHA256 = \"[a-f0-9]*/SCHEMA_SHA256 = \"$sha/" "$TEST_TMPDIR/scripts/review/validate-findings.py"
  run python3 -I "$TEST_TMPDIR/scripts/review/validate-findings.py" /nonexistent
  [ "$status" -eq 2 ]; [[ "$output" == *"not an object"* ]]
}

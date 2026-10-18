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
@test "keyword coverage" {
  run python3 -I - "$S" "$V" <<'PY'
import json, sys, ast, re
m = re.search(r'SUPPORTED\s*=\s*(\{[^}]+\})', open(sys.argv[2]).read(), re.DOTALL)
supported = ast.literal_eval(m.group(1))
def walk(d):
    if not isinstance(d, dict): return
    for k in d:
        assert k in supported, f"unsupported: {k}"
        if k == "properties": [walk(v) for v in d[k].values()]
        elif k == "items" and isinstance(d[k], dict): walk(d[k])
        elif k == "$defs": [walk(v) for v in d[k].values()]
walk(json.load(open(sys.argv[1])))
PY
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
@test "schema shape sweep: all cases exit 2" {
  run python3 -I "$REPO_ROOT/tests/scripts/fixtures/schema-shape-sweep.py" "$V" "$S"
  [ "$status" -eq 0 ]; [[ "$output" == *"bad=0"* ]]
  local n; n=$(echo "$output" | grep -oP 'shape-cases=\K\d+'); [[ "$n" -ge 25 ]]
}

# --- doc validation ---
@test "valid doc → 0" {
  printf '{"reviewed_head":"%s","pass":"code-reviewer","complete":true,"findings":[{"file":"x","lines":[1,2],"severity":"critical","category":"c","family":"f","summary":"s","evidence":"e"}]}' "$(printf 'a%.0s' {1..40})" > "$TEST_TMPDIR/d.json"
  run python3 -I "$V" "$TEST_TMPDIR/d.json"; [ "$status" -eq 0 ]
}
@test "doc sweep" {
  run python3 -I "$REPO_ROOT/tests/scripts/fixtures/doc-sweep.py" "$V" "$S"
  [ "$status" -eq 0 ]; [[ "$output" == *"bad=0"* ]]
  local n; n=$(echo "$output" | grep -oP 'generated=\K\d+'); [[ "$n" -ge 40 ]]
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

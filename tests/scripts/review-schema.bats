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

# --- length caps: prompt parity, boundary, --enforce-caps (#185 round-7 fix) ---
PROMPT="$REPO_ROOT/prompts/review-agents.md"
_capdoc() { # _capdoc <file> <summary-len> [extra-findings-json]
  python3 -I -c "
import json, sys
f = {'file':'src/a.py','lines':[1,2],'severity':'low','category':'x-y','summary':'a'*int(sys.argv[2]),'evidence':'e'}
extra = json.loads(sys.argv[3]) if len(sys.argv) > 3 else []
json.dump({'reviewed_head':'a'*40,'pass':'code-reviewer','complete':True,'findings':[f]+extra}, open(sys.argv[1],'w'))" "$1" "$2" "${3:-[]}"
}
@test "caps: the prompt states exactly the schema's length caps (no drift)" {
  run python3 -I - "$S" "$PROMPT" <<'PY'
import json, re, sys
schema = json.load(open(sys.argv[1]))
want = set()
for d in ("finding", "probe_request"):
    for f, spec in schema["$defs"][d]["properties"].items():
        if "maxLength" in spec: want.add(f"{d}.{f}<={spec['maxLength']}")
got = set(re.findall(r"[a-z_]+\.[a-z_]+<=[0-9]+", open(sys.argv[2]).read()))
assert got == want, f"prompt caps != schema caps: missing={sorted(want-got)} stale={sorted(got-want)}"
PY
  [ "$status" -eq 0 ]
}
@test "caps: every regenerated adapter carries the prompt's cap tokens" {
  local f tok
  for f in "$REPO_ROOT"/adapters/claude-code/prp-review-agents.md "$REPO_ROOT"/adapters/codex/prp-review-agents/SKILL.md \
           "$REPO_ROOT"/adapters/opencode/review-agents.md "$REPO_ROOT"/adapters/gemini/review-agents.toml \
           "$REPO_ROOT"/adapters/antigravity/prp-review-agents.md "$REPO_ROOT"/adapters/thclaws/prp-review-agents/SKILL.md; do
    for tok in 'finding.file<=200' 'finding.category<=40' 'finding.summary<=200' 'finding.evidence<=4000' \
               'probe_request.command<=4096' 'probe_request.purpose<=200' 'probe_request.expected<=200'; do
      grep -q -- "$tok" "$f" || { echo "missing $tok in $f"; return 1; }
    done
  done
}
@test "boundary: summary at 200 chars validates; 201 is refused as too long" {
  _capdoc "$TEST_TMPDIR/b200.json" 200
  _capdoc "$TEST_TMPDIR/b201.json" 201
  run python3 -I "$V" "$TEST_TMPDIR/b200.json"
  [ "$status" -eq 0 ]
  run python3 -I "$V" "$TEST_TMPDIR/b201.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *'$.findings[0].summary: too long'* ]]
}
@test "enforce-caps: a 201-char summary drops only that finding — the others still post, the breach named" {
  _capdoc "$TEST_TMPDIR/cap.json" 201 '[{"category":"c","evidence":"e","file":"src/b.py","lines":[1,2],"severity":"low","summary":"ok"}]'
  python3 -I "$V" --enforce-caps "$TEST_TMPDIR/cap.json" > "$TEST_TMPDIR/cap.ok"
  run python3 -I -c "
import json, sys
ls = open(sys.argv[1]).read().splitlines()
d = json.loads(ls[0])
assert len(ls) == 2, ls
assert len(d['findings']) == 1 and d['findings'][0]['summary'] == 'ok' and d['findings'][0]['file'] == 'src/b.py', d['findings']
assert ls[1] == '- L2-FINDING-CAP findings[0].summary 201>200 not-posted', ls[1]" "$TEST_TMPDIR/cap.ok"
  [ "$status" -eq 0 ]
}
@test "enforce-caps: no breach — output is the doc line alone (200-char boundary stays)" {
  _capdoc "$TEST_TMPDIR/b200.json" 200
  python3 -I "$V" --enforce-caps "$TEST_TMPDIR/b200.json" > "$TEST_TMPDIR/b200.ok"
  run python3 -I -c "
import json, sys
ls = open(sys.argv[1]).read().splitlines()
d = json.loads(ls[0])
assert len(ls) == 1 and len(d['findings']) == 1 and len(d['findings'][0]['summary']) == 200, ls" "$TEST_TMPDIR/b200.ok"
  [ "$status" -eq 0 ]
}
@test "enforce-caps: an over-cap probe_request is dropped and named; a non-object doc is refused" {
  python3 -I -c "
import json, sys
doc = {'reviewed_head':'a'*40,'pass':'probe','complete':True,'findings':[],
       'probe_requests':[{'id':'p','command':'x'*5000,'purpose':'p','expected':'e'}]}
json.dump(doc, open(sys.argv[1],'w'))" "$TEST_TMPDIR/probe.json"
  python3 -I "$V" --enforce-caps "$TEST_TMPDIR/probe.json" > "$TEST_TMPDIR/probe.ok"
  run python3 -I -c "
import json, sys
ls = open(sys.argv[1]).read().splitlines()
d = json.loads(ls[0])
assert len(ls) == 2 and d['probe_requests'] == [], ls
assert ls[1] == '- L2-FINDING-CAP probe_requests[0].command 5000>4096 not-posted', ls[1]" "$TEST_TMPDIR/probe.ok"
  [ "$status" -eq 0 ]
  printf '[]' > "$TEST_TMPDIR/arr.json"
  run python3 -I "$V" --enforce-caps "$TEST_TMPDIR/arr.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a JSON object"* ]]
}

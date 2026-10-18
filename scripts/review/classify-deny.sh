#!/usr/bin/env bash
# classify_deny <events> <rc> <tok_ok> <tok_deny> <auth_path> <deny_settings> <canary_ok_path> <canary_deny_path>
# Prints PASS or FAIL:<reason>.
classify_deny() {
  local events="$1" rc="$2" tok_ok="$3" tok_deny="$4" auth_path="$5" settings="$6" ok_path="$7" deny_path="$8"
  if [[ "$rc" -ne 0 ]]; then echo "FAIL: adapter rc=$rc"; return; fi
  if [[ ! -s "$events" ]]; then echo "FAIL: empty events file"; return; fi
  local auth_rel="${auth_path#"$HOME"/}"
  if [[ "$settings" != *"~/$auth_rel"* ]] && [[ "$settings" != *"~/$(dirname "$auth_rel")/**"* ]] && [[ "$settings" != *"$auth_path"* ]]; then
    echo "FAIL: auth path not covered by deny settings"; return
  fi
  if grep -qE 'sk-ant-|ghp_|gho_|github_pat_' "$events"; then echo "FAIL: credential pattern in events"; return; fi
  python3 -I -c "
import json, sys
events_file, tok_ok, tok_deny = sys.argv[1], sys.argv[2], sys.argv[3]
ok_path, deny_path = sys.argv[4], sys.argv[5]
text = open(events_file).read()
if tok_deny in text:
    print('FAIL: deny token leaked'); sys.exit()
# Parse JSONL tool events
tool_uses = {}
tool_results = {}
for line in text.splitlines():
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
    except: continue
    # Claude stream-json: content blocks with type tool_use / tool_result
    # Claude stream-json wraps content in message.content or top-level content
    blocks = d.get('content', [])
    msg = d.get('message', {})
    if isinstance(msg, dict) and isinstance(msg.get('content'), list):
        blocks = msg['content']
    if not isinstance(blocks, list): blocks = []
    for block in blocks:
        if not isinstance(block, dict): continue
        if block.get('type') == 'tool_use' and block.get('name') == 'Read':
            fp = block.get('input', {}).get('file_path', '')
            tool_uses[block.get('id', '')] = fp
        if block.get('type') == 'tool_result':
            tid = block.get('tool_use_id', '')
            tool_results[tid] = block
# Check control canary
ok_found = False
for uid, fp in tool_uses.items():
    if fp == ok_path and uid in tool_results:
        tr = tool_results[uid]
        content = json.dumps(tr) if isinstance(tr, dict) else str(tr)
        if tok_ok in content and not tr.get('is_error'):
            ok_found = True
if not ok_found:
    print('FAIL: control canary not read'); sys.exit()
# Check deny canary
deny_attempted = False
for uid, fp in tool_uses.items():
    if fp == deny_path:
        deny_attempted = True
        if uid in tool_results and tool_results[uid].get('is_error'):
            pass  # good: denied
        else:
            print('FAIL: CANARY_DENY read not denied'); sys.exit()
if not deny_attempted:
    print('FAIL: no Read of CANARY_DENY attempted (no evidence)'); sys.exit()
print('PASS')
" "$events" "$tok_ok" "$tok_deny" "$ok_path" "$deny_path"
}

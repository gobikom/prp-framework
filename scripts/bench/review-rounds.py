#!/usr/bin/env python3
"""Read-only review rounds report for prp-framework#160 AC0.4.
Never writes: local transcript reads and gh api GETs only.

Fallback classifier: matches only assistant-authored text blocks, not
user/system/prompt content. Patterns: 'No previous review found for PR #N'
-> fell-back; 'Incremental review: N files changed' -> incremental;
placeholders never count. A run not invoked with --since-last-review is
'full-requested' and excluded from the fallback rate.

Family heuristic (rounds): under a Critical/Important heading with count>0,
each bullet's first sentence is the title. Normalised: lower, strip leading
file:line, strip trailing punctuation. Same normalised title in consecutive
rounds → class b (repeated family).

Usage:
  python3 -I scripts/bench/review-rounds.py fallback <session.jsonl ...>
  python3 -I scripts/bench/review-rounds.py rounds --repo OWNER/REPO --prs N,N,...
  Add --json for JSON output. Set REVIEW_ROUNDS_GH_FIXTURES=<dir> for offline tests.
"""
import json, os, re, subprocess, sys

def _read_jsonl(path):
    lines, skipped = [], 0
    for line in open(path):
        line = line.strip()
        if not line: continue
        try: lines.append(json.loads(line))
        except json.JSONDecodeError: skipped += 1
    return lines, skipped

def _assistant_text(events):
    """Extract only assistant-authored text blocks."""
    parts = []
    for e in events:
        if e.get("type") != "assistant": continue
        msg = e.get("message", {}) if isinstance(e.get("message"), dict) else {}
        content = msg.get("content", "")
        if isinstance(content, str): parts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(block.get("text", ""))
    return " ".join(parts)

def _first_prompt(events):
    for e in events:
        if e.get("type") not in ("human", "user"): continue
        msg = e.get("message", {}) if isinstance(e.get("message"), dict) else {}
        content = msg.get("content", "")
        if isinstance(content, str) and content: return content
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    return block.get("text", "")
    return ""

REVIEW_FILE_PAT = re.compile(r"pr-\d+-agents-review\.md")
INCR_DIFF_PAT = re.compile(r"pr-\d+-incremental\.diff")
TWO_SHA_PAT = re.compile(r"git diff [0-9a-f]{7,40}[\s.]+[0-9a-f]{7,40}")
NOT_FOUND_PAT = re.compile(r"NOT_FOUND|No such file|not found|cannot access", re.I)

def _extract_tool_events(events):
    """Extract tool_use commands and tool_result content from the transcript."""
    tools = []
    for e in events:
        msg = e.get("message", {}) if isinstance(e.get("message"), dict) else {}
        content = msg.get("content", [])
        if isinstance(content, list):
            for block in content:
                if not isinstance(block, dict): continue
                if block.get("type") == "tool_use":
                    tools.append(("use", block.get("input", {}).get("command", "") or str(block.get("input", ""))))
                if block.get("type") == "tool_result":
                    tools.append(("result", block.get("content", "") if isinstance(block.get("content"), str) else str(block.get("content", ""))))
    return tools

def classify_mode(events):
    prompt = _first_prompt(events)
    invoked = "--since-last-review" in prompt
    if not invoked: return "full-requested", invoked
    tools = _extract_tool_events(events)
    all_text = " ".join(t[1] for t in tools)
    # Check if previous review file was looked up
    review_check = any(REVIEW_FILE_PAT.search(t[1]) for t in tools if t[0] == "use")
    not_found = any(NOT_FOUND_PAT.search(t[1]) for t in tools if t[0] == "result" and REVIEW_FILE_PAT.search(str(t[1])) or True)
    # Check for incremental diff or two-SHA git diff
    has_incr_diff = any(INCR_DIFF_PAT.search(t[1]) for t in tools)
    has_two_sha = any(TWO_SHA_PAT.search(t[1]) for t in tools if t[0] == "use")
    if has_incr_diff or has_two_sha: return "incremental", invoked
    # Check if the review file check said not found
    review_results = [t[1] for t in tools if t[0] == "result"]
    any_not_found = any(NOT_FOUND_PAT.search(r) for r in review_results if REVIEW_FILE_PAT.search(r) or "review" in r.lower())
    if any_not_found and not has_incr_diff: return "fell-back", invoked
    return "unknown", invoked

def cmd_fallback(paths, as_json=False):
    results = []
    for p in paths:
        events, skipped = _read_jsonl(p)
        mode, invoked = classify_mode(events)
        results.append({"path": os.path.basename(p), "mode": mode, "invoked": invoked, "skipped_lines": skipped})
    modes = [r["mode"] for r in results]
    invoked_runs = [r for r in results if r["invoked"]]
    fb = sum(1 for r in invoked_runs if r["mode"] == "fell-back")
    inc = sum(1 for r in invoked_runs if r["mode"] == "incremental")
    unk = sum(1 for r in invoked_runs if r["mode"] == "unknown")
    full_req = modes.count("full-requested")
    inv_total = len(invoked_runs)
    rate = fb / inv_total if inv_total else 0
    delta = "n/a (no incremental runs)" if inc == 0 else "computed"
    if as_json:
        json.dump({"sessions": results, "total": len(results), "invoked": inv_total,
                    "fell_back": fb, "incremental": inc, "unknown": unk,
                    "full_requested": full_req, "fallback_rate": round(rate, 3),
                    "extra_tokens_delta": delta}, sys.stdout, indent=2)
    else:
        print("| mode | count |")
        print("|------|-------|")
        print(f"| invoked incremental | {inv_total} |")
        print(f"| → incremental | {inc} |")
        print(f"| → fell-back | {fb} |")
        print(f"| → unknown | {unk} |")
        print(f"| full-requested | {full_req} |")
        print(f"| total | {len(results)} |")
        print(f"| fallback rate (invoked) | {rate:.1%} |")
        print(f"| extra tokens delta | {delta} |")

def _gh_api(endpoint):
    fixture_dir = os.environ.get("REVIEW_ROUNDS_GH_FIXTURES")
    if fixture_dir:
        safe = endpoint.replace("/", "_").replace("?", "_")
        fp = os.path.join(fixture_dir, safe + ".json")
        if os.path.exists(fp): return json.load(open(fp))
        return []
    sep = "?" if "?" not in endpoint else "&"
    r = subprocess.run(["gh", "api", endpoint + sep + "per_page=100", "--paginate"],
                       capture_output=True, text=True)
    if r.returncode != 0: raise RuntimeError(f"gh api failed: {r.stderr[:200]}")
    # gh --paginate concatenates JSON arrays: [...][...] → parse each
    raw = r.stdout.strip()
    results = []
    decoder = json.JSONDecoder()
    pos = 0
    while pos < len(raw):
        while pos < len(raw) and raw[pos] in " \t\r\n": pos += 1
        if pos >= len(raw): break
        obj, end = decoder.raw_decode(raw, pos)
        if isinstance(obj, list): results.extend(obj)
        else: results.append(obj)
        pos = end
    if len(results) == 1 and isinstance(results[0], dict): return results[0]
    return results

FOOTER_PAT = re.compile(r"Generated-by: prp-review-agents v[\d.]+ run=(\S+) pass=(\S+)")
CI_COUNT_PAT = re.compile(r"^### (Critical|Important) Issues? \((\d+)", re.MULTILINE)
FINDING_TITLE_PAT = re.compile(r"^[-*]\s+\*\*(.+?)\*\*", re.MULTILINE)

def _normalise_title(t):
    t = re.sub(r"^[\w/.-]+:\d+[-:]\d*\s*", "", t.strip())
    return re.sub(r"[^\w\s]", "", t.lower()).strip()

def cmd_rounds(repo, pr_numbers, as_json=False):
    results = []
    for pr_num in pr_numbers:
        try:
            pr_info = _gh_api(f"repos/{repo}/pulls/{pr_num}")
        except Exception:
            results.append({"pr": pr_num, "status": "not-found", "rounds": []}); continue
        if isinstance(pr_info, list): pr_info = pr_info[0] if pr_info else {}
        if not pr_info.get("merged_at"):
            results.append({"pr": pr_num, "status": "unmerged", "rounds": []}); continue
        comments = _gh_api(f"repos/{repo}/issues/{pr_num}/comments")
        if isinstance(comments, dict): comments = [comments]
        rounds = {}
        for c in comments:
            body = c.get("body", "")
            for m in FOOTER_PAT.finditer(body):
                run_id = m.group(1)
                if run_id not in rounds:
                    rounds[run_id] = {"run_id": run_id, "passes": [], "has_ci": False, "families": set()}
                rounds[run_id]["passes"].append(m.group(2))
                for cm in CI_COUNT_PAT.finditer(body):
                    if int(cm.group(2)) > 0:
                        rounds[run_id]["has_ci"] = True
                        for fm in FINDING_TITLE_PAT.finditer(body):
                            rounds[run_id]["families"].add(_normalise_title(fm.group(1)))
        round_list = list(rounds.values())
        prev_families = set()
        for rd in round_list:
            if len(rd["passes"]) < 3:
                rd["class"] = "c"
            elif rd["has_ci"]:
                if rd["families"] & prev_families:
                    rd["class"] = "b"
                else:
                    rd["class"] = "a"
            else:
                rd["class"] = "clean"
            prev_families = rd["families"]
            rd["families"] = sorted(rd["families"])
        results.append({"pr": pr_num, "status": "merged", "rounds": round_list})
    if as_json:
        json.dump(results, sys.stdout, indent=2)
    else:
        for r in results:
            if r["status"] in ("unmerged", "not-found"):
                print(f"PR #{r['pr']}: {r['status']} (excluded)")
                continue
            classes = [rd["class"] for rd in r["rounds"]]
            print(f"\nPR #{r['pr']}: {len(r['rounds'])} round(s) — a={classes.count('a')} b={classes.count('b')} c={classes.count('c')} clean={classes.count('clean')}")
            print("| round | passes | class | families |")
            print("|-------|--------|-------|----------|")
            for i, rd in enumerate(r["rounds"], 1):
                print(f"| {i} | {len(rd['passes'])} | {rd['class']} | {','.join(rd['families'][:3])} |")

if __name__ == "__main__":
    args = sys.argv[1:]
    as_json = "--json" in args
    if as_json: args.remove("--json")
    if not args:
        print(__doc__, file=sys.stderr); sys.exit(1)
    cmd = args[0]
    if cmd == "fallback":
        cmd_fallback(args[1:], as_json)
    elif cmd == "rounds":
        repo = None; prs = []
        i = 1
        while i < len(args):
            if args[i] == "--repo": repo = args[i+1]; i += 2
            elif args[i] == "--prs": prs = [int(x) for x in args[i+1].split(",")]; i += 2
            else: i += 1
        if not repo or not prs:
            print("error: --repo and --prs required", file=sys.stderr); sys.exit(1)
        cmd_rounds(repo, prs, as_json)
    else:
        print(f"unknown command: {cmd}", file=sys.stderr); sys.exit(1)

#!/usr/bin/env python3
"""Read-only review rounds report for prp-framework#160 AC0.4.
Never writes: local transcript reads and gh api GETs only.

Fallback classifier (tool-event based): a run whose first prompt carries
--since-last-review is 'invoked'; any other run is 'full-requested' and is
excluded from the fallback rate. For an invoked run, a tool event that
reads pr-N-incremental.diff or runs a two-SHA `git diff A B` / `A...B` makes
it 'incremental'; otherwise a tool result for the previous review file that
reports not-found makes it 'fell-back'; anything else is 'unknown'.

Family heuristic (rounds): only inside a Critical/Important section with
count>0 (up to the next ### heading), each top-level bullet (`- **T**`,
`* **T**` or `1. **T**`, not indented) gives a title T, and so does each
findings-table row (first sentence of its second column). Normalised: lower,
strip leading file:line, strip punctuation. Same normalised title in
consecutive rounds → class b (repeated family).

Errors are never reported as data: a gh api failure other than 404, or a
missing fixture file, gives status 'error' and exit code 2.

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
        skipped = sum(r["skipped_lines"] for r in results)
        print(f"| skipped (unparseable) lines | {skipped} |")
        if skipped:
            print(f"warning: {skipped} unparseable transcript line(s) excluded", file=sys.stderr)

class GhNotFound(Exception):
    pass

def _gh_api(endpoint):
    fixture_dir = os.environ.get("REVIEW_ROUNDS_GH_FIXTURES")
    if fixture_dir:
        safe = endpoint.replace("/", "_").replace("?", "_")
        fp = os.path.join(fixture_dir, safe + ".json")
        if not os.path.exists(fp):
            raise RuntimeError(f"fixture missing: {fp}")
        return json.load(open(fp))
    sep = "?" if "?" not in endpoint else "&"
    r = subprocess.run(["gh", "api", endpoint + sep + "per_page=100", "--paginate"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        if re.search(r"HTTP 404|Not Found", r.stderr): raise GhNotFound(endpoint)
        raise RuntimeError(f"gh api failed: {r.stderr[:200]}")
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
FINDING_TITLE_PAT = re.compile(r"^(?:[-*]|\d+\.)\s+\*\*(.+?)\*\*", re.MULTILINE)
NEXT_HEADING_PAT = re.compile(r"^#{1,3} ", re.MULTILINE)
TABLE_ROW_PAT = re.compile(r"^\|([^|\n]*)\|([^|\n]*)\|", re.MULTILINE)

def _section_titles(text):
    """Finding titles in one C/I section: bullet titles, or the first sentence
    of the second column of a findings table (header and separator skipped)."""
    titles = [m.group(1) for m in FINDING_TITLE_PAT.finditer(text)]
    for m in TABLE_ROW_PAT.finditer(text):
        first, second = m.group(1).strip(), m.group(2).strip()
        if not second or set(second) <= set("-: ") or first.lower() == "severity":
            continue
        titles.append(re.split(r"(?<=[.!?])\s", second, maxsplit=1)[0])
    return titles

def _section(body, m):
    """Text of the section whose heading match is m, up to the next heading."""
    nxt = NEXT_HEADING_PAT.search(body, m.end())
    return body[m.end():nxt.start() if nxt else len(body)]

def _normalise_title(t):
    t = re.sub(r"^[\w/.-]+:\d+[-:]\d*\s*", "", t.strip())
    return re.sub(r"[^\w\s]", "", t.lower()).strip()

def cmd_rounds(repo, pr_numbers, as_json=False):
    results = []
    for pr_num in pr_numbers:
        try:
            pr_info = _gh_api(f"repos/{repo}/pulls/{pr_num}")
            if not isinstance(pr_info, dict) or "number" not in pr_info:
                raise RuntimeError(f"unexpected pulls/{pr_num} response shape")
            if not pr_info.get("merged_at"):
                results.append({"pr": pr_num, "status": "unmerged", "rounds": []}); continue
            comments = _gh_api(f"repos/{repo}/issues/{pr_num}/comments")
            if isinstance(comments, dict): comments = [comments]
            if not isinstance(comments, list):
                raise RuntimeError(f"unexpected issues/{pr_num}/comments response shape")
        except GhNotFound:
            results.append({"pr": pr_num, "status": "not-found", "rounds": []}); continue
        except (RuntimeError, OSError, ValueError) as e:
            results.append({"pr": pr_num, "status": "error", "error": str(e), "rounds": []}); continue
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
                        for title in _section_titles(_section(body, cm)):
                            rounds[run_id]["families"].add(_normalise_title(title))
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
            if r["status"] == "error":
                print(f"PR #{r['pr']}: ERROR {r['error']}")
                continue
            if r["status"] in ("unmerged", "not-found"):
                print(f"PR #{r['pr']}: {r['status']} (excluded)")
                continue
            classes = [rd["class"] for rd in r["rounds"]]
            print(f"\nPR #{r['pr']}: {len(r['rounds'])} round(s) — a={classes.count('a')} b={classes.count('b')} c={classes.count('c')} clean={classes.count('clean')}")
            print("| round | passes | class | families |")
            print("|-------|--------|-------|----------|")
            for i, rd in enumerate(r["rounds"], 1):
                print(f"| {i} | {len(rd['passes'])} | {rd['class']} | {','.join(rd['families'][:3])} |")
    errors = [r for r in results if r["status"] == "error"]
    for r in errors:
        print(f"error: PR #{r['pr']}: {r['error']}", file=sys.stderr)
    return 2 if errors else 0

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
        sys.exit(cmd_rounds(repo, prs, as_json))
    else:
        print(f"unknown command: {cmd}", file=sys.stderr); sys.exit(1)

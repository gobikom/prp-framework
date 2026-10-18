#!/usr/bin/env python3
"""Sum usage tokens from Claude Code review session jsonl + subagents/*.jsonl.
Read-only; run as python3 -I. Accepts a project DIR or individual .jsonl files.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import stat
import sys
from dataclasses import dataclass, field

PRICE_RATIOS: dict[str, dict[str, float]] = {
    "default": {
        "input": 1.0,
        "cache_read": 0.1,
        "cache_create": 1.25,
        "output": 5.0,
    },
}

TOKEN_FIELDS = ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens")


@dataclass
class UsageTotals:
    input_tokens: int = 0
    cache_read_input_tokens: int = 0
    cache_creation_input_tokens: int = 0
    output_tokens: int = 0

    def add(self, usage: dict) -> None:
        for k in TOKEN_FIELDS:
            if k in usage:
                setattr(self, k, getattr(self, k) + usage[k])

    def weighted_cost(self, ratios: dict[str, float] | None = None) -> float:
        r = ratios or PRICE_RATIOS["default"]
        return (
            self.input_tokens * r["input"]
            + self.cache_read_input_tokens * r["cache_read"]
            + self.cache_creation_input_tokens * r["cache_create"]
            + self.output_tokens * r["output"]
        )


@dataclass
class SessionCost:
    path: str
    timestamp: str = ""
    main: UsageTotals = field(default_factory=UsageTotals)
    subagents: dict[str, UsageTotals] = field(default_factory=dict)

    @property
    def total(self) -> UsageTotals:
        t = UsageTotals(self.main.input_tokens, self.main.cache_read_input_tokens,
                        self.main.cache_creation_input_tokens, self.main.output_tokens)
        for s in self.subagents.values():
            for k in TOKEN_FIELDS:
                setattr(t, k, getattr(t, k) + getattr(s, k))
        return t

    @property
    def agents_output(self) -> int:
        return sum(s.output_tokens for s in self.subagents.values())


def _validate_line(raw: str) -> tuple[dict | None, str | None]:
    """Validate a single jsonl line's shape. Returns (parsed, None) or (None, reason).

    Every field read after this function is shape-checked here.
    Accepted (from 49,179 real lines, 60 session files; 9,860 usage objects all with 4 keys):
      - JSON object
      - timestamp: absent or str
      - message: absent, null, or object
      - usage (inside message): absent, null, or object
      - token fields: decided by `k in usage` (absent=0, null/bool/str/neg rejected, int>=0 accepted)
    """
    try:
        d = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return None, "not valid JSON"
    if not isinstance(d, dict):
        return None, f"not an object (got {type(d).__name__})"
    if "timestamp" in d:
        ts = d["timestamp"]
        if not isinstance(ts, str):
            return None, f"timestamp is {type(ts).__name__}, expected str or absent"
    msg = d.get("message")
    if msg is not None and not isinstance(msg, dict):
        return None, f"message is {type(msg).__name__}, expected object or null"
    if isinstance(msg, dict):
        usage = msg.get("usage")
        if usage is not None and not isinstance(usage, dict):
            return None, f"usage is {type(usage).__name__}, expected object or null"
        if isinstance(usage, dict):
            for k in TOKEN_FIELDS:
                if k not in usage:
                    continue
                v = usage[k]
                if v is None:
                    return None, f"usage.{k} is null"
                if isinstance(v, bool) or not isinstance(v, int):
                    return None, f"usage.{k} is {type(v).__name__}, expected int"
                if v < 0:
                    return None, f"usage.{k} is negative ({v})"
    return d, None


def _sum_jsonl(path: str) -> tuple[UsageTotals, str]:
    """Sum usage from a jsonl file. Raises ValueError on the first malformed line."""
    totals = UsageTotals()
    first_ts = ""
    with open(path) as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            d, reason = _validate_line(line)
            if d is None:
                raise ValueError(f"{path}: line {lineno}: {reason}")
            if not first_ts and "timestamp" in d:
                first_ts = d["timestamp"]
            msg = d.get("message")
            if isinstance(msg, dict):
                usage = msg.get("usage")
                if isinstance(usage, dict):
                    totals.add(usage)
    return totals, first_ts


def _scan_jsonl(directory: str) -> list[str]:
    """List *.jsonl in directory. FileNotFoundError = absent (empty list). Other OSError = real error (raised)."""
    try:
        entries = list(os.scandir(directory))
    except FileNotFoundError:
        return []
    return sorted(e.path for e in entries if e.name.endswith(".jsonl") and e.is_file())


def load_session_jsonl(main_jsonl: str) -> SessionCost:
    session_id = pathlib.Path(main_jsonl).stem
    parent = str(pathlib.Path(main_jsonl).parent)
    main_totals, ts = _sum_jsonl(main_jsonl)
    sub_dir = os.path.join(parent, session_id, "subagents")
    subagents: dict[str, UsageTotals] = {}
    for sub_file in _scan_jsonl(sub_dir):
        name = pathlib.Path(sub_file).stem
        sub_totals, _ = _sum_jsonl(sub_file)
        subagents[name] = sub_totals
    return SessionCost(path=main_jsonl, timestamp=ts, main=main_totals, subagents=subagents)


def load_project_dir(project_dir: str) -> tuple[list[SessionCost], list[str]]:
    jsonl_files = _scan_jsonl(project_dir)
    if not jsonl_files:
        raise FileNotFoundError(f"no *.jsonl in {project_dir}")
    sessions: list[SessionCost] = []
    failed: list[str] = []
    for f in jsonl_files:
        try:
            sessions.append(load_session_jsonl(f))
        except (ValueError, OSError) as e:
            print(f"error: {e}", file=sys.stderr)
            failed.append(f)
    return sessions, failed


def _fmt(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(n)


def print_table(sessions: list[SessionCost], file=sys.stdout) -> None:
    print("run (UTC)\tcache read\tcache create\toutput\tmain-thread output\tagent output\tweighted cost", file=file)
    for s in sessions:
        t = s.total
        ts = s.timestamp[:16].replace("T", " ") if s.timestamp else s.path
        print(f"{ts}\t{_fmt(t.cache_read_input_tokens)}\t{_fmt(t.cache_creation_input_tokens)}"
              f"\t{_fmt(t.output_tokens)}\t{_fmt(s.main.output_tokens)}\t{_fmt(s.agents_output)}"
              f"\t{s.total.weighted_cost():.0f}", file=file)


def to_json(sessions: list[SessionCost]) -> list[dict]:
    out = []
    for s in sessions:
        t = s.total
        out.append({
            "path": s.path, "timestamp": s.timestamp,
            "cache_read": t.cache_read_input_tokens, "cache_create": t.cache_creation_input_tokens,
            "output": t.output_tokens, "main_output": s.main.output_tokens,
            "agent_output": s.agents_output, "weighted_cost": round(s.total.weighted_cost(), 2),
            "subagents": {name: {"cache_read": sub.cache_read_input_tokens,
                                 "cache_create": sub.cache_creation_input_tokens,
                                 "output": sub.output_tokens} for name, sub in s.subagents.items()},
        })
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="project dirs or session .jsonl files")
    parser.add_argument("--json", action="store_true", help="output JSON instead of TSV")
    args = parser.parse_args()

    sessions: list[SessionCost] = []
    errors = 0
    for p in args.paths:
        try:
            st = os.stat(p)
        except FileNotFoundError:
            print(f"error: not found: {p}", file=sys.stderr)
            errors += 1
            continue
        except OSError as e:
            print(f"error: {e}", file=sys.stderr)
            errors += 1
            continue
        try:
            if stat.S_ISDIR(st.st_mode):
                good, failed = load_project_dir(p)
                sessions.extend(good)
                errors += len(failed)
            elif p.endswith(".jsonl") and stat.S_ISREG(st.st_mode):
                sessions.append(load_session_jsonl(p))
            else:
                print(f"error: not a directory or .jsonl file: {p}", file=sys.stderr)
                errors += 1
        except (FileNotFoundError, ValueError, OSError) as e:
            print(f"error: {e}", file=sys.stderr)
            errors += 1

    if not sessions and errors:
        return 1
    if not sessions:
        print("error: no sessions found", file=sys.stderr)
        return 1

    sessions.sort(key=lambda s: s.timestamp or s.path)

    if args.json:
        json.dump(to_json(sessions), sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print_table(sessions)

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

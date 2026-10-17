#!/usr/bin/env python3
"""Sum usage tokens from Claude Code review session jsonl + subagents/*.jsonl.

Read-only; run as python3 -I.

Usage:
    python3 -I scripts/bench/review-cost.py DIR            (all sessions in DIR)
    python3 -I scripts/bench/review-cost.py FILE.jsonl ...  (specific session files)

A DIR is a Claude Code project directory containing <id>.jsonl files with
matching <id>/subagents/*.jsonl directories.  A FILE.jsonl is a single session's
main-thread jsonl whose subagents/ sibling dir is found automatically.

Output: a TSV table and an optional --json summary.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import pathlib
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


@dataclass
class UsageTotals:
    input_tokens: int = 0
    cache_read_input_tokens: int = 0
    cache_creation_input_tokens: int = 0
    output_tokens: int = 0

    def add(self, usage: dict) -> None:
        self.input_tokens += usage.get("input_tokens", 0)
        self.cache_read_input_tokens += usage.get("cache_read_input_tokens", 0)
        self.cache_creation_input_tokens += usage.get("cache_creation_input_tokens", 0)
        self.output_tokens += usage.get("output_tokens", 0)

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
        t = UsageTotals(
            self.main.input_tokens,
            self.main.cache_read_input_tokens,
            self.main.cache_creation_input_tokens,
            self.main.output_tokens,
        )
        for s in self.subagents.values():
            t.input_tokens += s.input_tokens
            t.cache_read_input_tokens += s.cache_read_input_tokens
            t.cache_creation_input_tokens += s.cache_creation_input_tokens
            t.output_tokens += s.output_tokens
        return t

    @property
    def agents_output(self) -> int:
        return sum(s.output_tokens for s in self.subagents.values())


def _sum_jsonl(path: str) -> tuple[UsageTotals, str]:
    totals = UsageTotals()
    first_ts = ""
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not first_ts and "timestamp" in d:
                first_ts = d["timestamp"]
            usage = d.get("message", {}).get("usage") if isinstance(d.get("message"), dict) else None
            if isinstance(usage, dict):
                totals.add(usage)
    return totals, first_ts


def load_session_jsonl(main_jsonl: str) -> SessionCost:
    """Load one session from its main-thread jsonl file.

    Subagents are found at <same-dir>/<session-id>/subagents/*.jsonl.
    """
    session_id = pathlib.Path(main_jsonl).stem
    parent = str(pathlib.Path(main_jsonl).parent)

    main_totals, ts = _sum_jsonl(main_jsonl)

    sub_dir = os.path.join(parent, session_id, "subagents")
    subagents: dict[str, UsageTotals] = {}
    if os.path.isdir(sub_dir):
        for sub_file in sorted(glob.glob(os.path.join(sub_dir, "*.jsonl"))):
            name = pathlib.Path(sub_file).stem
            sub_totals, _ = _sum_jsonl(sub_file)
            subagents[name] = sub_totals

    return SessionCost(path=main_jsonl, timestamp=ts, main=main_totals, subagents=subagents)


def load_project_dir(project_dir: str) -> list[SessionCost]:
    """Load all sessions from a Claude Code project directory."""
    jsonl_files = sorted(glob.glob(os.path.join(project_dir, "*.jsonl")))
    if not jsonl_files:
        raise FileNotFoundError(f"no *.jsonl in {project_dir}")
    return [load_session_jsonl(f) for f in jsonl_files]


def _fmt(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(n)


def print_table(sessions: list[SessionCost], file=sys.stdout) -> None:
    print(
        "run (UTC)\tcache read\tcache create\toutput\tmain-thread output\tagent output\tweighted cost",
        file=file,
    )
    for s in sessions:
        t = s.total
        ts = s.timestamp[:16].replace("T", " ") if s.timestamp else s.path
        print(
            f"{ts}\t{_fmt(t.cache_read_input_tokens)}\t{_fmt(t.cache_creation_input_tokens)}"
            f"\t{_fmt(t.output_tokens)}\t{_fmt(s.main.output_tokens)}\t{_fmt(s.agents_output)}"
            f"\t{s.total.weighted_cost():.0f}",
            file=file,
        )


def to_json(sessions: list[SessionCost]) -> list[dict]:
    out = []
    for s in sessions:
        t = s.total
        out.append({
            "path": s.path,
            "timestamp": s.timestamp,
            "cache_read": t.cache_read_input_tokens,
            "cache_create": t.cache_creation_input_tokens,
            "output": t.output_tokens,
            "main_output": s.main.output_tokens,
            "agent_output": s.agents_output,
            "weighted_cost": round(s.total.weighted_cost(), 2),
            "subagents": {
                name: {
                    "cache_read": sub.cache_read_input_tokens,
                    "cache_create": sub.cache_creation_input_tokens,
                    "output": sub.output_tokens,
                }
                for name, sub in s.subagents.items()
            },
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
            if os.path.isdir(p):
                sessions.extend(load_project_dir(p))
            elif p.endswith(".jsonl") and os.path.isfile(p):
                sessions.append(load_session_jsonl(p))
            else:
                print(f"error: not a directory or .jsonl file: {p}", file=sys.stderr)
                errors += 1
        except (FileNotFoundError, ValueError) as e:
            print(f"error: {e}", file=sys.stderr)
            errors += 1

    if not sessions:
        print("error: no sessions loaded", file=sys.stderr)
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

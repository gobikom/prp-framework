# Ralph Stop Hook Tests

Tests for `adapters/claude-code-hooks/prp-ralph-stop.sh`.

## Requirements

```bash
brew install bats-core   # macOS
# or
apt-get install bats     # Ubuntu/Debian
```

## Run Tests

```bash
# From project root
bats tests/ralph/ralph-stop.bats

# Verbose output
bats --verbose-run tests/ralph/ralph-stop.bats

# TAP output (for CI)
bats --formatter tap tests/ralph/ralph-stop.bats
```

## Test Coverage

| Case | Tests |
|------|-------|
| No state file → allow exit | 2 |
| COMPLETE promise on own line → exit + delete state | 3 |
| No COMPLETE → block + increment iteration | 4 |
| Max iterations reached → exit + delete state | 3 |
| False positive (indented promise) → block | 2 |
| Corrupt state file → exit + delete state | 3 |
| Transcript not found → exit + delete state | 2 |
| No assistant message → block | 1 |
| Block JSON output format | 3 |

## Fixtures

| File | Description |
|------|-------------|
| `transcript-complete.jsonl` | Assistant output with `<promise>COMPLETE</promise>` on own line |
| `transcript-incomplete.jsonl` | Assistant output without completion promise |
| `transcript-false-positive.jsonl` | Promise inside indented code block (should NOT trigger) |
| `transcript-empty.jsonl` | Only user message, no assistant output |

## Known Limitation

The false positive protection (requiring promise on its own line with no indentation)
prevents most accidental triggers. However, if Claude outputs the promise inside a
markdown bold/italic span on its own line (e.g., `**<promise>COMPLETE</promise>**`),
it would still not trigger (correct behavior). The `^...$` regex anchor ensures
the line contains ONLY the promise token.

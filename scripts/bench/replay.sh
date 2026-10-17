#!/usr/bin/env bash
# Replay benchmark: run the new review protocol on frozen corpus heads.
#
# ALWAYS runs with --no-post: no comments are posted, no markers are written.
# Collects pass.json and cost data per head per harness.
#
# Usage: replay.sh [--harness HARNESS] [--runs N] [--entry ID] [--corpus PATH]
#
# Exits 0 only when every requested replay succeeds.
# Exits 1 on usage error or corpus parse failure.
# Exits 2 on conformance preflight failure (blocks all runs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORPUS="${REPO_ROOT}/tests/bench/corpus.yaml"
HARNESS="claude-code"
RUNS=1
ENTRY_FILTER=""
OUT_DIR=""

usage() {
  echo "Usage: replay.sh [--harness H] [--runs N] [--entry ID] [--corpus PATH] [--out DIR]"
  echo "  --harness   Harness to use (default: claude-code)"
  echo "  --runs      Number of runs per entry (default: 1)"
  echo "  --entry     Only replay this entry id"
  echo "  --corpus    Path to corpus.yaml (default: tests/bench/corpus.yaml)"
  echo "  --out       Output directory (default: .prp-output/bench/<timestamp>)"
  echo "  --no-post is always implied; this script never posts."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --harness) HARNESS="$2"; shift 2 ;;
    --runs)    RUNS="$2"; shift 2 ;;
    --entry)   ENTRY_FILTER="$2"; shift 2 ;;
    --corpus)  CORPUS="$2"; shift 2 ;;
    --out)     OUT_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "error: unknown flag $1" >&2; usage ;;
  esac
done

if [[ ! -f "$CORPUS" ]]; then
  echo "error: corpus not found: $CORPUS" >&2
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="${REPO_ROOT}/.prp-output/bench/$(date -u +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUT_DIR"

# --- Conformance preflight ---
# The conformance test must pass before any replay runs.
# Phase 1 delivers conformance.sh; until then, this is a placeholder check.
CONFORMANCE="${REPO_ROOT}/scripts/review/conformance.sh"
if [[ -x "$CONFORMANCE" ]]; then
  echo "Running conformance preflight for $HARNESS..."
  if ! "$CONFORMANCE" "$HARNESS"; then
    echo "error: conformance preflight failed for $HARNESS" >&2
    exit 2
  fi
  echo "Conformance preflight passed."
else
  echo "warning: conformance.sh not found; skipping preflight (Phase 1 not yet delivered)" >&2
fi

# --- Parse corpus ---
# Minimal YAML parsing: extract entries using python3 -I (read-only, no pip deps).
entries_json=$(python3 -I - "$CORPUS" "$ENTRY_FILTER" <<'PY'
import json, sys
try:
    import yaml
except ImportError:
    print("error: PyYAML not installed; install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

corpus_path = sys.argv[1]
entry_filter = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None

with open(corpus_path) as f:
    corpus = yaml.safe_load(f)

entries = corpus.get("entries", [])
if entry_filter:
    entries = [e for e in entries if e.get("id") == entry_filter]

if not entries:
    print("error: no matching entries in corpus", file=sys.stderr)
    sys.exit(1)

json.dump(entries, sys.stdout)
PY
) || exit 1

entry_count=$(echo "$entries_json" | python3 -I -c "import json,sys; print(len(json.load(sys.stdin)))")
echo "Corpus: $entry_count entries, $RUNS run(s) each, harness=$HARNESS"
echo "Output: $OUT_DIR"
echo ""

# --- Replay loop ---
# For each entry, for each run:
#   1. Check that head and base are reachable
#   2. Verify patch digest matches
#   3. Run the protocol with --no-post
#   4. Collect pass.json and cost
#
# Phase 1 delivers the actual protocol CLI (scripts/review/prp-review).
# Until then, this skeleton validates the corpus and reports what it would run.

REVIEW_CLI="${REPO_ROOT}/scripts/review/prp-review"
failures=0

echo "$entries_json" | python3 -I -c "
import json, sys
for e in json.load(sys.stdin):
    print(f'{e[\"id\"]}|{e[\"pr\"]}|{e[\"head\"]}|{e[\"base\"]}|{e[\"patch_digest\"]}|{e[\"kind\"]}')
" | while IFS='|' read -r eid pr head base digest kind; do
  echo "--- Entry: $eid (PR #$pr, head ${head:0:8}, $kind) ---"

  # Verify head and base are reachable
  for sha in "$head" "$base"; do
    if ! git -C "$REPO_ROOT" cat-file -e "$sha" 2>/dev/null; then
      echo "  Fetching $sha..."
      if ! git -C "$REPO_ROOT" fetch origin "$sha" --quiet 2>/dev/null; then
        echo "  error: cannot resolve $sha" >&2
        failures=$((failures + 1))
        continue 2
      fi
    fi
  done

  # Verify patch digest
  actual_digest=$(git -C "$REPO_ROOT" diff "$base".."$head" | sha256sum | cut -d' ' -f1)
  if [[ "$actual_digest" != "$digest" ]]; then
    echo "  error: patch digest mismatch for $eid" >&2
    echo "    expected: $digest" >&2
    echo "    actual:   $actual_digest" >&2
    failures=$((failures + 1))
    continue
  fi
  echo "  Patch digest verified."

  for run_n in $(seq 1 "$RUNS"); do
    run_dir="$OUT_DIR/$eid/run-$run_n"
    mkdir -p "$run_dir"

    if [[ -x "$REVIEW_CLI" ]]; then
      echo "  Run $run_n/$RUNS: invoking review CLI (--no-post)..."
      "$REVIEW_CLI" --no-post --harness "$HARNESS" \
        --head "$head" --base "$base" --pr "$pr" \
        --out "$run_dir" \
        2>"$run_dir/stderr.log" || {
          echo "  error: review CLI failed (exit $?)" >&2
          failures=$((failures + 1))
        }
    else
      echo "  Run $run_n/$RUNS: review CLI not delivered yet; validating corpus only."
    fi

    # Record what we know
    cat > "$run_dir/meta.json" <<METAEOF
{"entry_id": "$eid", "pr": $pr, "head": "$head", "base": "$base", "harness": "$HARNESS", "run": $run_n, "digest_verified": true}
METAEOF
  done
  echo ""
done

if [[ "$failures" -gt 0 ]]; then
  echo "FAIL: $failures error(s)" >&2
  exit 1
fi

echo "Replay complete: $entry_count entries, $RUNS run(s) each."
echo "Results in $OUT_DIR"

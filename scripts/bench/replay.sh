#!/usr/bin/env bash
# Replay benchmark: run the review protocol with --no-post on frozen corpus heads.
# Exits 0 only when every entry is enumerated AND processed successfully.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CORPUS="${REPO_ROOT}/tests/bench/corpus.yaml"
HARNESS="claude-code"; RUNS=1; ENTRY_FILTER=""; OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --harness) HARNESS="$2"; shift 2 ;; --runs) RUNS="$2"; shift 2 ;;
    --entry) ENTRY_FILTER="$2"; shift 2 ;; --corpus) CORPUS="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    *) echo "Usage: replay.sh [--harness H] [--runs N] [--entry ID] [--corpus PATH] [--out DIR]" >&2; exit 1 ;;
  esac
done

[[ -f "$CORPUS" ]] || { echo "error: corpus not found: $CORPUS" >&2; exit 1; }
[[ -z "$OUT_DIR" ]] && OUT_DIR="${REPO_ROOT}/.prp-output/bench/$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

CONFORMANCE="${REPO_ROOT}/scripts/review/conformance.sh"
if [[ -x "$CONFORMANCE" ]]; then
  "$CONFORMANCE" "$HARNESS" || { echo "error: conformance preflight failed" >&2; exit 2; }
fi

entries_json=$(python3 -I - "$CORPUS" "$ENTRY_FILTER" <<'PY'
import json, sys
try:
    import yaml
except ImportError:
    print("error: PyYAML required", file=sys.stderr); sys.exit(1)
corpus_path = sys.argv[1]
entry_filter = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
with open(corpus_path) as f:
    corpus = yaml.safe_load(f)
entries = corpus.get("entries", [])
if entry_filter:
    entries = [e for e in entries if e.get("id") == entry_filter]
if not entries:
    print("error: no matching entries in corpus", file=sys.stderr); sys.exit(1)
print(len(entries))
json.dump(entries, sys.stdout)
PY
) || exit 1

entry_count="${entries_json%%$'\n'*}"
entries_json="${entries_json#*$'\n'}"
echo "Corpus: $entry_count entries, $RUNS run(s) each, harness=$HARNESS"

REVIEW_CLI="${REPO_ROOT}/scripts/review/prp-review"
failures=0

entries_lines=$(echo "$entries_json" | python3 -I -c "
import json, sys
for e in json.load(sys.stdin):
    print(f'{e[\"id\"]}|{e[\"pr\"]}|{e[\"head\"]}|{e[\"base\"]}|{e[\"patch_digest\"]}|{e[\"kind\"]}')
") || { echo "error: cannot enumerate corpus entries" >&2; exit 1; }

line_count=$(echo "$entries_lines" | grep -c .)
if [[ "$line_count" -ne "$entry_count" ]]; then
  echo "error: enumerated $line_count of $entry_count entries" >&2; exit 1
fi

while IFS='|' read -r eid pr head base digest kind; do
  echo "--- Entry: $eid (PR #$pr, head ${head:0:8}, $kind) ---"
  for sha in "$head" "$base"; do
    if ! git -C "$REPO_ROOT" cat-file -e "$sha" 2>/dev/null; then
      if ! git -C "$REPO_ROOT" fetch origin "$sha" --quiet 2>/dev/null; then
        echo "  error: cannot resolve $sha" >&2; failures=$((failures + 1)); continue 2
      fi
    fi
  done
  actual_digest=$(git -C "$REPO_ROOT" diff "$base".."$head" | sha256sum | cut -d' ' -f1)
  if [[ "$actual_digest" != "$digest" ]]; then
    echo "  error: patch digest mismatch for $eid" >&2
    echo "    expected: $digest" >&2; echo "    actual:   $actual_digest" >&2
    failures=$((failures + 1)); continue
  fi
  echo "  Patch digest verified."
  for run_n in $(seq 1 "$RUNS"); do
    run_dir="$OUT_DIR/$eid/run-$run_n"; mkdir -p "$run_dir"
    if [[ -x "$REVIEW_CLI" ]]; then
      "$REVIEW_CLI" --no-post --harness "$HARNESS" \
        --head "$head" --base "$base" --pr "$pr" \
        --out "$run_dir" </dev/null 2>"$run_dir/stderr.log" || {
          echo "  error: review CLI failed (exit $?)" >&2; failures=$((failures + 1))
        }
    fi
    cat > "$run_dir/meta.json" <<METAEOF
{"entry_id": "$eid", "pr": $pr, "head": "$head", "base": "$base", "harness": "$HARNESS", "run": $run_n, "digest_verified": true}
METAEOF
  done
done <<< "$entries_lines"

if [[ "$failures" -gt 0 ]]; then echo "FAIL: $failures error(s)" >&2; exit 1; fi
echo "Replay complete: $entry_count entries, $RUNS run(s) each."

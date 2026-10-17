#!/usr/bin/env bash
# Compute frozen metadata for a corpus entry: patch digest and file count.
# patch_digest = sha256 of `git diff BASE..HEAD` after command substitution (trailing newlines stripped), then printf '%s'.
# files_changed/additions/deletions from `git diff --numstat`. A binary file (-\t-\tpath) counts as 1 file, 0 lines (defined rule).
# Usage: freeze-head.sh REPO HEAD_SHA BASE_SHA
set -euo pipefail

repo="${1:?usage: freeze-head.sh REPO HEAD_SHA BASE_SHA}"
head="${2:?missing HEAD_SHA}"
base="${3:?missing BASE_SHA}"

cd "$repo"

for sha in "$head" "$base"; do
  if ! git cat-file -e "$sha" 2>/dev/null; then
    git fetch origin "$sha" --quiet 2>/dev/null || {
      echo "error: cannot resolve $sha in $repo" >&2
      exit 1
    }
  fi
done

diff_output=$(LC_ALL=C git diff "$base".."$head")
if [ -z "$diff_output" ]; then
  echo "error: empty diff between $base and $head" >&2
  exit 1
fi

digest=$(printf '%s' "$diff_output" | sha256sum | cut -d' ' -f1)

numstat=$(LC_ALL=C git diff --numstat "$base".."$head")

files_changed=0
additions=0
deletions=0

while IFS=$'\t' read -r add del path; do
  [ -z "$add" ] && [ -z "$del" ] && [ -z "$path" ] && continue
  if [ -z "$path" ]; then
    echo "error: unparseable numstat line: ${add}${del:+	$del}" >&2
    exit 1
  fi
  files_changed=$((files_changed + 1))
  if [ "$add" = "-" ] && [ "$del" = "-" ]; then
    continue
  fi
  if ! [[ "$add" =~ ^[0-9]+$ ]] || ! [[ "$del" =~ ^[0-9]+$ ]]; then
    echo "error: unparseable numstat line: ${add}	${del}	${path}" >&2
    exit 1
  fi
  additions=$((additions + add))
  deletions=$((deletions + del))
done <<< "$numstat"

if [ "$files_changed" -lt 1 ]; then
  echo "error: numstat reported no files for a non-empty diff" >&2
  exit 1
fi

cat <<EOF
patch_digest: "$digest"
files_changed: $files_changed
additions: $additions
deletions: $deletions
EOF

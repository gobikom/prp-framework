#!/usr/bin/env bash
# Compute frozen metadata for a corpus entry: patch digest and file count.
# patch_digest = sha256 of `git diff BASE..HEAD` after command substitution (trailing newlines stripped), then printf '%s'.
# Usage: freeze-head.sh REPO HEAD_SHA BASE_SHA
# Output: YAML fragment (patch_digest, files_changed, additions, deletions)
set -euo pipefail

repo="${1:?usage: freeze-head.sh REPO HEAD_SHA BASE_SHA}"
head="${2:?missing HEAD_SHA}"
base="${3:?missing BASE_SHA}"

cd "$repo"

# Fetch both SHAs if not local
for sha in "$head" "$base"; do
  if ! git cat-file -e "$sha" 2>/dev/null; then
    git fetch origin "$sha" --quiet 2>/dev/null || {
      echo "error: cannot resolve $sha in $repo" >&2
      exit 1
    }
  fi
done

diff_output=$(git diff "$base".."$head")
if [ -z "$diff_output" ]; then
  echo "error: empty diff between $base and $head" >&2
  exit 1
fi

digest=$(printf '%s' "$diff_output" | sha256sum | cut -d' ' -f1)
stat_line=$(git diff --stat "$base".."$head" | tail -1)
files_changed=$(echo "$stat_line" | grep -oP '\d+ file' | grep -oP '\d+' || echo 0)
additions=$(echo "$stat_line" | grep -oP '\d+ insertion' | grep -oP '\d+' || echo 0)
deletions=$(echo "$stat_line" | grep -oP '\d+ deletion' | grep -oP '\d+' || echo 0)

cat <<EOF
patch_digest: "$digest"
files_changed: $files_changed
additions: $additions
deletions: $deletions
EOF

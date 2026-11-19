#!/usr/bin/env bash
# Read the trusted producer footers only after verifying the unfiltered listing.
set -euo pipefail

repo=$1
number=$2
login=$3
[[ -n "$login" ]] || { echo "missing trusted review identity" >&2; exit 1; }

pr="repos/$repo/issues/$number"
total=$(gh api "$pr" --jq .comments)
[[ "$total" =~ ^[0-9]+$ ]] || { echo "invalid PR comment count" >&2; exit 1; }
pages=$(gh api "$pr/comments" --paginate --slurp)
printf '%s\n' "$pages" | jq -er --arg login "$login" --argjson total "$total" '
  if type != "array" or length == 0 or any(.[]; type != "array") then
    error("invalid PR comment pages")
  else add end
  | if length != $total or any(.[]; (.id | type) != "number" or (.body | type) != "string")
       or ([.[].id] | unique | length) != $total then
      error("PR comment listing incomplete or invalid")
    else . end
  | [.[] | select(.user.login == $login) | .body | rtrimstr("\n") | split("\n") | last]
  | join("\n")
'

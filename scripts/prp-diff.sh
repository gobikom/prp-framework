#!/usr/bin/env bash
set -euo pipefail

# prp-diff — structural diff summary for review
# Produces a semantic summary of what changed (functions, classes, files)
# instead of raw line-by-line diff.
# Usage: prp-diff.sh <pr-number> [--compact|--full] [-R OWNER/REPO]

PR_NUMBER="${1:?Usage: prp-diff.sh <pr-number> [--compact|--full] [-R OWNER/REPO]}"
shift
MODE="--compact"
REPO_FLAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --compact|--full) MODE="$1"; shift ;;
        -R) REPO_FLAG="-R $2"; shift 2 ;;
        *) shift ;;
    esac
done

# Get PR metadata
META=$(gh pr view $PR_NUMBER $REPO_FLAG --json additions,deletions,changedFiles,title \
  --jq '"\(.additions) \(.deletions) \(.changedFiles) \(.title)"' 2>/dev/null)
read -r ADDITIONS DELETIONS CHANGED_FILES TITLE <<< "$META"

# Get file list
FILES=$(gh pr diff $PR_NUMBER $REPO_FLAG --name-only 2>/dev/null)
if [ -z "$FILES" ]; then
    echo "No changes found in PR #${PR_NUMBER}"
    exit 0
fi

# Get full diff for analysis
DIFF=$(gh pr diff $PR_NUMBER $REPO_FLAG 2>/dev/null)

echo "## PR #${PR_NUMBER} — Structural Diff (${CHANGED_FILES} files, +${ADDITIONS}/-${DELETIONS})"
echo ""

# Categorize files
declare -a NEW_FILES=() MOD_FILES=() DEL_FILES=()

while IFS= read -r file; do
    [ -z "$file" ] && continue
    file_header=$(echo "$DIFF" | grep -A2 "^diff.*${file//./\\.}" | head -3)
    if echo "$file_header" | grep -q "new file mode"; then
        NEW_FILES+=("$file")
    elif echo "$file_header" | grep -q "deleted file mode"; then
        DEL_FILES+=("$file")
    else
        MOD_FILES+=("$file")
    fi
done <<< "$FILES"

# Modified files — show hunk context (function/class names)
if [ ${#MOD_FILES[@]} -gt 0 ]; then
    echo "### Modified (${#MOD_FILES[@]} files)"
    for file in "${MOD_FILES[@]}"; do
        # Count per-file changes
        escaped_file="${file//\//\\/}"
        file_adds=$(echo "$DIFF" | sed -n "/^diff.*${escaped_file}/,/^diff --git/p" | grep -c "^+" 2>/dev/null || echo "?")
        file_dels=$(echo "$DIFF" | sed -n "/^diff.*${escaped_file}/,/^diff --git/p" | grep -c "^-" 2>/dev/null || echo "?")
        echo "- \`$file\` (+$file_adds/-$file_dels)"
        # Extract hunk headers (contain function/class context)
        echo "$DIFF" | sed -n "/^diff.*${escaped_file}/,/^diff --git/p" | grep "^@@" | sed 's/.*@@ /  - /' | head -5
    done
    echo ""
fi

# New files — show size
if [ ${#NEW_FILES[@]} -gt 0 ]; then
    echo "### Created (${#NEW_FILES[@]} files)"
    for file in "${NEW_FILES[@]}"; do
        escaped_file="${file//\//\\/}"
        lines=$(echo "$DIFF" | sed -n "/^diff.*${escaped_file}/,/^diff --git/p" | grep -c "^+" 2>/dev/null || echo "?")
        echo "- \`$file\` (${lines} lines)"
    done
    echo ""
fi

# Deleted files
if [ ${#DEL_FILES[@]} -gt 0 ]; then
    echo "### Deleted (${#DEL_FILES[@]} files)"
    for file in "${DEL_FILES[@]}"; do
        echo "- \`$file\`"
    done
    echo ""
fi

# In --full mode, append raw diff
if [ "$MODE" = "--full" ]; then
    echo "---"
    echo ""
    echo "### Full Diff"
    echo '```diff'
    echo "$DIFF"
    echo '```'
fi

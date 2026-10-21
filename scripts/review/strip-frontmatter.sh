#!/usr/bin/env bash
# Strip YAML frontmatter from an .md file. Only the leading block (line 1 = ---).
# Usage: strip_frontmatter <file>  (prints to stdout)
strip_frontmatter() {
  awk 'NR==1 && /^---$/ { skip=1; next } skip && /^---$/ { skip=0; next } !skip' "$1"
}

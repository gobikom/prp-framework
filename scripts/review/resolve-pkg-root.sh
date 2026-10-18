#!/usr/bin/env bash
# Resolve the npm package root from a binary's resolved directory.
# Usage: source resolve-pkg-root.sh; resolve_pkg_root <dir>
# Prints the package root on success, returns non-zero on failure.
resolve_pkg_root() {
  (cd "$1" || exit 1
   while [[ "$PWD" == */node_modules/* ]]; do cd .. || exit 1; done
   [[ -d "$PWD" ]] && echo "$PWD" || exit 1)
}

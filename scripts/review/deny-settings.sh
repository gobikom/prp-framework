#!/usr/bin/env bash
# Build Claude deny-rule settings JSON. Used by adapters and conformance.
# Usage: source deny-settings.sh; build_deny_settings [extra-paths...]
# Outputs the --settings JSON string.
build_deny_settings() {
  local paths=("~/.claude/**" "~/.claude.json")
  for p in "$@"; do paths+=("$p"); done
  local rules=""
  for p in "${paths[@]}"; do
    [[ -n "$rules" ]] && rules+=","
    rules+="\"Read($p)\",\"Grep($p)\",\"Glob($p)\""
  done
  printf '{"permissions":{"deny":[%s]}}' "$rules"
}

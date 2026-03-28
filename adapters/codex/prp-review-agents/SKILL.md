---
name: prp-review-agents
description: Multi-pass PR review — alias for prp-review which already includes all 11 review passes with equivalent quality.
metadata:
  short-description: Multi-pass PR review (alias)
---

# PRP Review Agents — Multi-Pass PR Review

> **This command is an alias for `$prp-review`.**
>
> In Claude Code, `review-agents` dispatches multiple specialist agents in parallel via Task tool.
> In Codex, the standard `$prp-review` command already runs all 11 review passes sequentially
> with equivalent quality — including conditional dispatch, dedup, metrics, and incremental review.
>
> **Use `$prp-review` directly.** This alias exists for cross-tool workflow compatibility.

## Usage

```
$prp-review-agents 163                        # Same as: $prp-review 163
$prp-review-agents 163 security deps          # Same as: $prp-review 163 security deps
$prp-review-agents 163 --since-last-review    # Same as: $prp-review 163 --since-last-review
$prp-review-agents --metrics                  # Same as: $prp-review --metrics
```

## Why This Alias Exists

| Adapter | `review` | `review-agents` |
|---------|----------|-----------------|
| Claude Code | Single-agent review | Multi-agent dispatch (Task tool) |
| Codex | **11-pass multi-pass** (equivalent quality) | This alias → `$prp-review` |
| OpenCode | **11-pass multi-pass** | Alias |
| Gemini | **11-pass multi-pass** | Alias |
| Antigravity | **11-pass multi-pass** | Alias |

Since v2.1.0, all adapters' `review` command includes the same 11 passes, conditional dispatch,
result deduplication, metrics collection, and incremental review that `review-agents` provides
in Claude Code — just executed sequentially instead of in parallel.

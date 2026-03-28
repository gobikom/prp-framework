---
name: prp-feature-review-agents
description: Multi-pass feature review — alias for prp-feature-review which already includes comprehensive quality, security, performance, and product analysis.
metadata:
  short-description: Multi-pass feature review (alias)
---

# PRP Feature Review Agents — Multi-Pass Feature Review

> **This command is an alias for `$prp-feature-review`.**
>
> In Claude Code, `feature-review-agents` dispatches multiple specialist agents in parallel.
> In Codex, the standard `$prp-feature-review` command already runs all review passes
> with equivalent quality — including code quality, security, performance, and product analysis.
>
> **Use `$prp-feature-review` directly.** This alias exists for cross-tool workflow compatibility.

## Usage

```
$prp-feature-review-agents src/features/auth     # Same as: $prp-feature-review src/features/auth
$prp-feature-review-agents src/ --focus security  # Same as: $prp-feature-review src/ --focus security
```

## Why This Alias Exists

Since v2.1.0, all adapters' `feature-review` command includes comprehensive analysis
(code quality, product ideas, performance, security, accessibility) that `feature-review-agents`
provides in Claude Code — just executed sequentially instead of via parallel agent dispatch.

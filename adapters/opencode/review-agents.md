---
description: Multi-pass PR review — alias for review which already includes all 11 review passes with equivalent quality.
agent: plan
---

# PRP Review Agents — Multi-Pass PR Review

> **This command is an alias for `/prp:review`.**
>
> In Claude Code, `review-agents` dispatches multiple specialist agents in parallel via Task tool.
> In OpenCode, the standard `/prp:review` command already runs all 11 review passes sequentially
> with equivalent quality — including conditional dispatch, dedup, metrics, and incremental review.
>
> **Use `/prp:review` directly.** This alias exists for cross-tool workflow compatibility.

## Usage

```
/prp:review-agents 163                        # Same as: /prp:review 163
/prp:review-agents 163 security deps          # Same as: /prp:review 163 security deps
/prp:review-agents 163 --since-last-review    # Same as: /prp:review 163 --since-last-review
/prp:review-agents --metrics                  # Same as: /prp:review --metrics
```

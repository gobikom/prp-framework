---
name: prp-core-runner
description: Orchestrate complete PRP workflow from feature request to pull request. Run branch, plan, implement, commit, PR, review with fix loop, and summary in sequence. Use when implementing features using PRP methodology or when user requests full PRP workflow.
---

# PRP Core Workflow Runner

## Instructions

When the user requests to implement a feature using the PRP workflow or wants end-to-end automation from idea to PR, use the SlashCommand tool to invoke `/prp-core:prp-run-all` with the user's feature description as the argument.

**Step-by-step execution:**

1. **Invoke the workflow**: Use SlashCommand tool with `/prp-core:prp-run-all {feature-description}`
2. **Monitor progress**: The workflow will execute these steps in sequence:
   - Fetch issue context (if `--issue` provided) with smart plan detection
   - Create a conventional git branch
   - Generate implementation plan (or skip for small issues)
   - Execute the implementation (or ralph loop with `--ralph` flag)
   - Create atomic git commit
   - Create pull request (skip with `--no-pr`)
   - Run multi-agent review with fix loop until 0 issues (skip with `--skip-review`)
   - Generate summary report
   - Merge + cleanup (if `--merge` and review passes)
3. **Handle failures**: If any step fails:
   - Report which step failed and why
   - Do NOT proceed to subsequent steps
   - Provide actionable guidance for fixing the issue
4. **Report completion**: When all steps succeed, confirm the workflow completed and provide the PR URL

**Supported flags:**

| Flag | Effect |
|------|--------|
| `--issue <N>` | Fetch GitHub issue #N, use as feature context. Smart plan detection. |
| `--merge` | Auto squash-merge PR after review passes (0 issues). Runs cleanup. |
| `--max-review-rounds <N>` | Override max review-fix cycles (default: 5) |
| `--prp-path <path>` | Skip plan creation, use existing plan |
| `--skip-plan` | Select from available plans instead of creating new one |
| `--fast` | Fast-track plan (lighter codebase analysis) |
| `--ralph` | Use autonomous ralph loop for implementation |
| `--ralph-max-iter N` | Set max ralph iterations (default: 10) |
| `--skip-review` | Skip review step |
| `--no-pr` | Skip PR and review steps |
| `--resume` | Resume from last failed step |
| `--fix-severity <levels>` | Override review-fix severity (default: critical,high,medium,suggestion) |
| `--no-interact` | Never ask user questions — use best judgment, pick defaults |
| `--dry-run` | Preview all steps without executing. Show estimated token cost. |

**Error Handling:**

- Stop execution immediately if any validation fails
- Report the specific error clearly
- Guide the user on how to resolve the issue
- Do not attempt to auto-fix complex validation failures

## Examples

**Example 1: Issue-driven full lifecycle**
```
User: "Implement issue #87 and merge when done"
Assistant: I'll run the full PRP workflow from issue to merge.
[Invokes: /prp-core:prp-run-all --issue 87 --merge]
```

**Example 2: Feature request**
```
User: "I need to add a search API with Elasticsearch integration using PRP"
Assistant: I'll run the full PRP workflow to implement the search API with Elasticsearch.
[Invokes: /prp-core:prp-run-all Add search API with Elasticsearch integration]
```

**Example 3: Fully autonomous**
```
User: "Implement issue #42, don't ask questions, merge when ready"
Assistant: I'll run the full autonomous PRP lifecycle.
[Invokes: /prp-core:prp-run-all --issue 42 --merge --no-interact]
```

**Example 4: Using ralph mode**
```
User: "Implement payment processing with PRP, use ralph mode"
Assistant: I'll run the full PRP workflow with ralph mode for autonomous implementation.
[Invokes: /prp-core:prp-run-all Implement payment processing --ralph]
```

**Example 5: Resuming interrupted workflow**
```
User: "Resume the PRP workflow that was interrupted"
Assistant: I'll resume the PRP workflow from where it left off.
[Invokes: /prp-core:prp-run-all --resume]
```

**Example 6: Dry run preview**
```
User: "Show me what PRP would do for adding dark mode"
Assistant: I'll preview the PRP workflow without executing.
[Invokes: /prp-core:prp-run-all Add dark mode support --dry-run]
```

## When to Use

Use this skill when:
- User explicitly requests to "implement a feature using PRP"
- User asks to "run the full PRP workflow"
- User wants end-to-end automation from feature idea to pull request
- User mentions both "PRP" and a feature to implement
- User requests a complete workflow including branch, implementation, and PR
- User wants to resume an interrupted PRP workflow
- User asks to implement a GitHub issue with `--issue`

Do NOT use this skill when:
- User only wants to run a single PRP command (e.g., just create a PRP)
- User is asking about PRP methodology (provide information instead)
- User wants to implement something without mentioning PRP workflow

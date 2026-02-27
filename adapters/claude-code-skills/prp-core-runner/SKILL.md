---
name: prp-core-runner
description: Orchestrate complete PRP workflow from feature request to pull request. Run branch, plan, implement, commit, PR, review with fix loop, and summary in sequence. Use when implementing features using PRP methodology or when user requests full PRP workflow.
---

# PRP Core Workflow Runner

## Instructions

When the user requests to implement a feature using the PRP workflow or wants end-to-end automation from idea to PR, use the SlashCommand tool to invoke `/prp-run-all` with the user's feature description as the argument.

**Step-by-step execution:**

1. **Invoke the workflow**: Use SlashCommand tool with `/prp-run-all {feature-description}`
2. **Monitor progress**: The workflow will execute 7 steps in sequence:
   - Create a conventional git branch
   - Generate comprehensive implementation plan
   - Execute the implementation (or ralph loop with `--ralph` flag)
   - Create atomic git commit
   - Create pull request (skip with `--no-pr`)
   - Run multi-agent review with fix loop (skip with `--skip-review`)
   - Generate summary report with artifacts and next steps
3. **Handle failures**: If any step fails:
   - Report which step failed and why
   - Do NOT proceed to subsequent steps
   - Provide actionable guidance for fixing the issue
4. **Report completion**: When all steps succeed, confirm the workflow completed and provide the PR URL

**Supported flags:**

| Flag | Effect |
|------|--------|
| `--prp-path <path>` | Skip plan creation, use existing plan |
| `--ralph` | Use autonomous ralph loop for implementation |
| `--ralph-max-iter N` | Set max ralph iterations (default: 10) |
| `--skip-review` | Skip review step |
| `--no-pr` | Skip PR and review steps |
| `--resume` | Resume from last failed step |
| `--fix-severity <levels>` | Override review-fix severity (default: critical,high) |
| `--no-interact` | Never ask user questions — use best judgment, pick defaults |

**Error Handling:**

- Stop execution immediately if any validation fails
- Report the specific error clearly
- Guide the user on how to resolve the issue
- Do not attempt to auto-fix complex validation failures

## Examples

**Example 1: Autonomous invocation**
```
User: "Can you implement user authentication using JWT with the PRP workflow?"
Assistant: I'll use the prp-core-runner skill to execute the complete PRP workflow for implementing JWT authentication.
[Invokes: /prp-run-all Implement user authentication using JWT]
```

**Example 2: Feature request**
```
User: "I need to add a search API with Elasticsearch integration using PRP"
Assistant: I'll run the full PRP workflow to implement the search API with Elasticsearch.
[Invokes: /prp-run-all Add search API with Elasticsearch integration]
```

**Example 3: Refactoring with PRP**
```
User: "Use the PRP methodology to refactor the database layer for better performance"
Assistant: I'll execute the PRP workflow for refactoring the database layer.
[Invokes: /prp-run-all Refactor database layer for better performance]
```

**Example 4: Using ralph mode**
```
User: "Implement payment processing with PRP, use ralph mode"
Assistant: I'll run the full PRP workflow with ralph mode for autonomous implementation.
[Invokes: /prp-run-all Implement payment processing --ralph]
```

**Example 5: Resuming interrupted workflow**
```
User: "Resume the PRP workflow that was interrupted"
Assistant: I'll resume the PRP workflow from where it left off.
[Invokes: /prp-run-all --resume]
```

**Example 6: Skip review**
```
User: "Run PRP for adding dark mode but skip the review"
Assistant: I'll run the PRP workflow without the review step.
[Invokes: /prp-run-all Add dark mode support --skip-review]
```

## When to Use

Use this skill when:
- User explicitly requests to "implement a feature using PRP"
- User asks to "run the full PRP workflow"
- User wants end-to-end automation from feature idea to pull request
- User mentions both "PRP" and a feature to implement
- User requests a complete workflow including branch, implementation, and PR
- User wants to resume an interrupted PRP workflow

Do NOT use this skill when:
- User only wants to run a single PRP command (e.g., just create a PRP)
- User is asking about PRP methodology (provide information instead)
- User wants to implement something without mentioning PRP workflow

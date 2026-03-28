# Adapter Overlays

Overlay files add tool-specific content that doesn't belong in the canonical `prompts/` files. They're merged by `scripts/generate-adapters.py` during adapter generation.

## When to Use Overlays

Most commands **don't need overlays** — they're generated directly from `prompts/` with placeholder substitution and frontmatter. Only use overlays when a specific adapter needs:

- XML section wrapping (e.g., `<objective>`, `<context>`, `<process>`)
- Tool-specific agent strategies or instructions
- Content restructuring (skip/reorder sections from the base prompt)

## File Format

```markdown
---
command: plan
adapter: claude-code
skip_before: "## Phase 0"   # Optional: skip prompt content before this line
---

# objective
Content for <objective> XML section...

# context
Content for <context> XML section...

# output
Content for <output> XML section...

# verification
Content for <verification> XML section...

# success_criteria
Content for <success_criteria> XML section...
```

### Section Names

| Section | Purpose | XML Tag |
|---------|---------|---------|
| `objective` | What the AI should achieve | `<objective>` |
| `context` | Background info, project rules | `<context>` |
| `wrap_before` | Prepend to `<process>` body | — |
| `wrap_after` | Append to `<process>` body | — |
| `output` | Output format and reporting | `<output>` |
| `verification` | Checklists before saving | `<verification>` |
| `success_criteria` | Success conditions | `<success_criteria>` |

### Frontmatter Options

| Field | Purpose |
|-------|---------|
| `command` | Which prompt this overlays |
| `adapter` | Which adapter this is for |
| `skip_before` | Skip content in prompt before this marker (useful when overlay replaces header sections) |

## Directory Structure

```
prompts/overlays/
└── claude-code/
    └── plan.md     # Only plan needs XML wrapping currently
```

## Adding a New Overlay

1. Create `prompts/overlays/{adapter}/{command}.md`
2. Add frontmatter with command and adapter
3. Add sections using `# section_name` headers
4. Run `python3 scripts/generate-adapters.py`
5. Verify with `npx bats tests/adapters/parity.bats`

# Pipeline Manifest Schema

## Overview

Pipeline manifests track exact artifact paths for a branch, enabling precise cleanup without glob-based discovery.

## Location

```
.prp-output/manifests/{BRANCH}.json
```

Example: `.prp-output/manifests/feature-auth.json`

## Schema

```json
{
  "branch": "feature/auth",
  "pr_number": 42,
  "created": "2026-03-28T10:30:00Z",
  "artifacts": {
    "plan": ".prp-output/plans/completed/auth-20260328-1030.plan.md",
    "report": ".prp-output/reports/auth-report-20260328-1130.md",
    "context": ".prp-output/reviews/pr-context-feature-auth.md",
    "reviews": [
      ".prp-output/reviews/pr-42-review-codex.md"
    ],
    "fixes": [
      ".prp-output/reviews/pr-42-fix-summary-20260328-1200.md"
    ]
  }
}
```

## Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `branch` | string | Branch name |
| `pr_number` | number | Associated PR number (0 if no PR yet) |
| `created` | string | ISO 8601 timestamp |
| `artifacts` | object | Artifact paths |

## Artifact Fields (all optional)

| Field | Type | Description |
|-------|------|-------------|
| `artifacts.plan` | string | Path to completed plan |
| `artifacts.report` | string | Path to implementation report |
| `artifacts.context` | string | Path to PR review context |
| `artifacts.reviews` | string[] | Paths to review artifacts |
| `artifacts.fixes` | string[] | Paths to fix summary artifacts |

## Validation Rules

1. **File must be valid JSON** — malformed manifests should be ignored (fallback to glob)
2. **`branch` field must exist** — used to match with cleanup target
3. **`artifacts` field must be an object** — even if empty
4. **Paths are relative to project root** — not absolute paths
5. **Missing artifact paths are OK** — cleanup skips entries that don't exist on disk

## Usage in Commands

### `cleanup` (Phase 3.2)

```
1. Check .prp-output/manifests/{BRANCH}.json
2. If valid JSON with artifacts → use exact paths
3. If invalid/missing → fallback to glob discovery
4. After archiving → rm -f .prp-output/manifests/{BRANCH}.json
```

### `implement` / `run-all`

After generating artifacts, optionally write manifest:

```bash
mkdir -p .prp-output/manifests
cat > ".prp-output/manifests/${BRANCH}.json" << EOF
{
  "branch": "${BRANCH}",
  "pr_number": 0,
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "artifacts": {
    "plan": "${PLAN_PATH}",
    "report": "${REPORT_PATH}",
    "context": "${CONTEXT_PATH}"
  }
}
EOF
```

#!/usr/bin/env bash
# gen-ai-context.sh — Validate and auto-update PROJECT.md for AI + human consumption
#
# Modes:
#   --check   Validate only (exit 0 if fresh, 1 if stale/missing)
#   --update  Update AUTO-GEN sections in existing PROJECT.md
#   --init    Create PROJECT.md from template (if not exists)
#
# Usage:
#   gen-ai-context.sh [--check | --update | --init] [--quiet]
#
# Installed by prp-framework. Source: scripts/gen-ai-context.sh

set -euo pipefail

# Find project root (look for .git, fallback to cwd)
find_project_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        [ -d "$dir/.git" ] && echo "$dir" && return
        dir=$(dirname "$dir")
    done
    echo "$PWD"
}

PROJECT_DIR=$(find_project_root)
cd "$PROJECT_DIR"

# Parse flags (position-independent)
MODE="--check"
QUIET=false
for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=true ;;
        --check|--update|--init) MODE="$arg" ;;
    esac
done

PROJECT_NAME=$(basename "$PROJECT_DIR")
PROJECT_MD="$PROJECT_DIR/PROJECT.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { $QUIET || echo -e "$@"; }
log_ok() { log "  ${GREEN}✓${NC} $1"; }
log_warn() { log "  ${YELLOW}⚠${NC} $1"; }
log_err() { log "  ${RED}✗${NC} $1"; }

# ─────────────────────────────────────────────────
# Auto-detect: Stack
# ─────────────────────────────────────────────────
detect_stack() {
    local stack=()
    # Common exclude dirs for recursive grep (avoid scanning vendored/generated code)
    local EXCL="--exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=venv --exclude-dir=dist --exclude-dir=build --exclude-dir=__pycache__"

    [ -f "package.json" ] && stack+=("Node.js $(jq -r '.engines.node // ""' package.json 2>/dev/null | head -1)")
    if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ] || ls requirements*.txt 1>/dev/null 2>&1; then
        stack+=("Python")
    fi
    if [ -f "go.mod" ]; then
        local go_ver
        go_ver=$(grep -E '^go [0-9.]+' go.mod 2>/dev/null | head -1 | grep -oE '[0-9.]+' || true)
        stack+=("Go${go_ver:+ $go_ver}")
    fi
    [ -f "Cargo.toml" ] && stack+=("Rust")
    [ -f "pom.xml" ] || [ -f "build.gradle" ] && stack+=("Java/Kotlin")

    # Frameworks
    [ -f "package.json" ] && grep -q '"react"' package.json 2>/dev/null && stack+=("React")
    [ -f "package.json" ] && grep -q '"next"' package.json 2>/dev/null && stack+=("Next.js")
    [ -f "package.json" ] && grep -q '"vue"' package.json 2>/dev/null && stack+=("Vue")
    [ -f "package.json" ] && grep -q '"fastify"' package.json 2>/dev/null && stack+=("Fastify")
    [ -f "package.json" ] && grep -q '"express"' package.json 2>/dev/null && stack+=("Express")
    grep -rql $EXCL "from fastapi" . --include="*.py" -m1 2>/dev/null && stack+=("FastAPI")
    grep -rql $EXCL "from flask" . --include="*.py" -m1 2>/dev/null && stack+=("Flask")
    grep -rql $EXCL "from django" . --include="*.py" -m1 2>/dev/null && stack+=("Django")

    # Build tools
    [ -f "package.json" ] && grep -q '"vite"' package.json 2>/dev/null && stack+=("Vite")
    [ -f "tailwind.config" ] || [ -f "tailwind.config.js" ] || [ -f "tailwind.config.ts" ] && stack+=("Tailwind")

    # DB
    [ -d "prisma" ] && stack+=("Prisma")
    grep -rql $EXCL "chromadb\|from chromadb" . --include="*.py" -m1 2>/dev/null && stack+=("ChromaDB")
    grep -rql $EXCL "sqlite3\|aiosqlite" . --include="*.py" -m1 2>/dev/null && stack+=("SQLite")

    # Clean up empty entries and join
    local result=""
    for s in "${stack[@]}"; do
        s=$(echo "$s" | xargs)  # trim
        [ -n "$s" ] && result="${result:+$result, }$s"
    done
    echo "${result:-Unknown}"
}

# ─────────────────────────────────────────────────
# Auto-detect: Entry points
# ─────────────────────────────────────────────────
detect_entry_points() {
    local entries=()
    [ -f "package.json" ] && {
        local main=$(jq -r '.main // ""' package.json 2>/dev/null)
        [ -n "$main" ] && entries+=("$main")
        local start=$(jq -r '.scripts.start // ""' package.json 2>/dev/null)
        [ -n "$start" ] && entries+=("npm start → $start")
    }
    [ -f "main.py" ] && entries+=("main.py")
    [ -f "app.py" ] && entries+=("app.py")
    [ -f "server.py" ] && entries+=("server.py")
    [ -f "src/index.ts" ] && entries+=("src/index.ts")
    [ -f "src/index.js" ] && entries+=("src/index.js")
    [ -f "src/main.py" ] && entries+=("src/main.py")
    [ -d "bin" ] && {
        for f in bin/*; do
            [ -x "$f" ] && entries+=("$f")
        done
    }

    local result=""
    for e in "${entries[@]}"; do
        result="${result:+$result, }$e"
    done
    echo "${result:-(none detected)}"
}

# ─────────────────────────────────────────────────
# Auto-detect: Context Map
# ─────────────────────────────────────────────────
generate_context_map() {
    echo "| Task Type | Read These First |"
    echo "|-----------|-----------------|"

    # Common directory patterns → task types (use if/then to avoid operator precedence issues)
    if [ -d "src/routes" ] || [ -d "src/api" ] || [ -d "routes" ]; then
        echo "| API/endpoints | \`$(ls -d src/routes src/api routes 2>/dev/null | head -1)/\` |"
    fi
    if [ -d "src/components" ] || [ -d "components" ]; then
        echo "| Frontend components | \`$(ls -d src/components components 2>/dev/null | head -1)/\` |"
    fi
    if [ -d "src/services" ] || [ -d "services" ]; then
        echo "| Business logic | \`$(ls -d src/services services 2>/dev/null | head -1)/\` |"
    fi
    if [ -d "src/models" ] || [ -d "models" ]; then
        echo "| Data models | \`$(ls -d src/models models 2>/dev/null | head -1)/\` |"
    fi
    if [ -d "src/middleware" ] || [ -d "middleware" ]; then
        echo "| Middleware | \`$(ls -d src/middleware middleware 2>/dev/null | head -1)/\` |"
    fi
    [ -d "prisma" ] && echo "| Database schema | \`prisma/\` |"
    if [ -d "src/db" ] || [ -d "db" ]; then
        echo "| Database | \`$(ls -d src/db db 2>/dev/null | head -1)/\` |"
    fi
    if [ -d "test" ] || [ -d "tests" ] || [ -d "__tests__" ]; then
        echo "| Tests | \`$(ls -d test tests __tests__ 2>/dev/null | head -1)/\` |"
    fi
    [ -d "docs" ] && echo "| Documentation | \`docs/\` |"
    [ -d "scripts" ] && echo "| Scripts/CLI | \`scripts/\` |"
    [ -d "bin" ] && echo "| CLI entry | \`bin/\` |"
    if [ -d "deploy" ] || [ -d ".github/workflows" ]; then
        echo "| Deploy/CI | \`$(ls -d deploy .github/workflows 2>/dev/null | head -1)/\` |"
    fi
    if [ -d "config" ] || [ -d "conf" ]; then
        echo "| Configuration | \`$(ls -d config conf 2>/dev/null | head -1)/\` |"
    fi

    # Fallback: if src/ exists but no known sub-patterns matched, add generic src/ entry
    if [ -d "src" ]; then
        local src_in_map=false
        for subdir in routes api components services models middleware db; do
            if [ -d "src/$subdir" ]; then
                src_in_map=true
                break
            fi
        done
        if [ "$src_in_map" = false ]; then
            echo "| Source code | \`src/\` |"
        fi
    fi

    # Project-specific directories (any top-level dir with code)
    for dir in */; do
        dir="${dir%/}"
        # Skip common non-code dirs
        case "$dir" in
            node_modules|.git|.prp|.prp-output|.claude|.codex|.opencode|.gemini|.agents|dist|build|__pycache__|.venv|venv|.env|coverage|.nyc_output|logs|output|tmp|temp|backup) continue ;;
            src|test|tests|docs|scripts|bin|deploy|config|conf|prisma|public|static|assets) continue ;;  # already handled above
            *.backup|*.backup.*|*.bak|*.old|*.orig|*~|*-backup) continue ;;  # backup/stale dir conventions (#72)
        esac
        # Only include if it has code files
        if find "$dir" -maxdepth 2 \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.yaml" -o -name "*.yml" -o -name "*.sh" \) -print -quit 2>/dev/null | grep -q .; then
            echo "| ${dir} | \`${dir}/\` |"
        fi
    done
}

# ─────────────────────────────────────────────────
# Auto-detect: Exports (API endpoints, CLI commands)
# ─────────────────────────────────────────────────
detect_exports() {
    local found=false
    local EXCL="--exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=venv --exclude-dir=dist --exclude-dir=build --exclude-dir=__pycache__"

    # FastAPI routes
    local fastapi_routes
    fastapi_routes=$(grep -rn $EXCL '@app\.\(get\|post\|put\|delete\|patch\)\|@router\.\(get\|post\|put\|delete\|patch\)' --include="*.py" . 2>/dev/null | head -20)
    if [ -n "$fastapi_routes" ]; then
        echo "### API Endpoints"
        echo ""
        echo '```'
        echo "$fastapi_routes" | sed 's|^\./||' | while IFS= read -r line; do
            echo "$line"
        done
        echo '```'
        echo ""
        found=true
    fi

    # Express routes
    local express_routes
    express_routes=$(grep -rn $EXCL 'app\.\(get\|post\|put\|delete\|patch\)\|router\.\(get\|post\|put\|delete\|patch\)' --include="*.ts" --include="*.js" . 2>/dev/null | head -20)
    if [ -n "$express_routes" ] && [ "$found" = false ]; then
        echo "### API Endpoints"
        echo ""
        echo '```'
        echo "$express_routes" | sed 's|^\./||'
        echo '```'
        echo ""
        found=true
    fi

    # CLI commands (from bin/)
    if [ -d "bin" ]; then
        echo "### CLI Commands"
        echo ""
        for f in bin/*; do
            [ -x "$f" ] && echo "- \`$(basename "$f")\`"
        done
        echo ""
        found=true
    fi

    # Package.json scripts
    if [ -f "package.json" ]; then
        local scripts
        scripts=$(jq -r '.scripts // {} | to_entries[] | "- `npm run \(.key)` → \(.value)"' package.json 2>/dev/null | head -10)
        if [ -n "$scripts" ]; then
            echo "### npm Scripts"
            echo ""
            echo "$scripts"
            echo ""
            found=true
        fi
    fi

    $found || echo "(no exports detected — add manually)"
}

# ─────────────────────────────────────────────────
# Mode: --init
# ─────────────────────────────────────────────────
do_init() {
    if [ -f "$PROJECT_MD" ]; then
        log "${YELLOW}PROJECT.md already exists. Use --update to refresh AUTO-GEN sections.${NC}"
        exit 0
    fi

    # Find template
    local tmpl=""
    [ -f "$PROJECT_DIR/.prp/templates/PROJECT.md.tmpl" ] && tmpl="$PROJECT_DIR/.prp/templates/PROJECT.md.tmpl"
    [ -f "$PROJECT_DIR/templates/PROJECT.md.tmpl" ] && tmpl="$PROJECT_DIR/templates/PROJECT.md.tmpl"

    if [ -z "$tmpl" ]; then
        log "${RED}Template not found. Expected .prp/templates/PROJECT.md.tmpl${NC}"
        exit 1
    fi

    # Copy template and replace project name (escape sed metacharacters in name)
    local safe_name
    safe_name=$(printf '%s\n' "$PROJECT_NAME" | sed 's/[&/\\]/\\&/g')
    sed "s/{PROJECT_NAME}/$safe_name/g" "$tmpl" > "$PROJECT_MD" || {
        log "${RED}Failed to create PROJECT.md from template${NC}"
        exit 1
    }

    # Now update AUTO-GEN sections
    do_update

    log ""
    log "${GREEN}✅ Created PROJECT.md for $PROJECT_NAME${NC}"
    log "   Review and edit the {TODO} sections (What & Why, Problem, Requirements, Key Decisions)"
}

# ─────────────────────────────────────────────────
# Mode: --update
# ─────────────────────────────────────────────────
do_update() {
    if [ ! -f "$PROJECT_MD" ]; then
        log "${RED}PROJECT.md not found. Use --init to create it first.${NC}"
        exit 1
    fi

    # Check markers exist before attempting update
    if ! grep -q "AUTO-GEN:BEGIN" "$PROJECT_MD"; then
        log "${YELLOW}No AUTO-GEN markers found in PROJECT.md. Skipping update.${NC}"
        exit 0
    fi

    if ! grep -q "AUTO-GEN:END" "$PROJECT_MD"; then
        log "${RED}AUTO-GEN:BEGIN found but AUTO-GEN:END missing — refusing to update (would lose content)${NC}"
        exit 1
    fi

    # Extract content before and after AUTO-GEN markers
    local before after
    before=$(sed '/<!-- AUTO-GEN:BEGIN/,$d' "$PROJECT_MD")
    after=$(sed -n '/<!-- AUTO-GEN:END -->/,$p' "$PROJECT_MD" | tail -n +2)

    # Generate new AUTO-GEN content
    local stack entry_points context_map exports
    stack=$(detect_stack)
    entry_points=$(detect_entry_points)
    context_map=$(generate_context_map)
    exports=$(detect_exports)

    # Rebuild PROJECT.md atomically (write to temp, then move)
    local tmp_md
    tmp_md=$(mktemp "${PROJECT_MD}.tmp.XXXXXX")
    {
        echo "$before"
        echo "<!-- AUTO-GEN:BEGIN — Do not edit manually. Run: gen-ai-context.sh --update -->"
        echo "## Architecture (Brief)"
        echo ""
        echo "- **Stack:** $stack"
        echo "- **Entry points:** $entry_points"
        echo ""
        echo "## Context Map"
        echo ""
        echo "$context_map"
        echo ""
        echo "## Exports"
        echo ""
        echo "$exports"
        echo "<!-- AUTO-GEN:END -->"
        echo "$after"
    } > "$tmp_md" && mv "$tmp_md" "$PROJECT_MD" || {
        log "${RED}Failed to write PROJECT.md — original preserved${NC}"
        rm -f "$tmp_md"
        exit 1
    }

    log "${GREEN}✅ Updated AUTO-GEN sections in PROJECT.md${NC}"
}

# ─────────────────────────────────────────────────
# Mode: --check
# ─────────────────────────────────────────────────
do_check() {
    local stale=0
    local issues=0

    log "=== PROJECT.md Health Check: $PROJECT_NAME ==="
    log ""

    # 1. Check PROJECT.md exists
    if [ ! -f "$PROJECT_MD" ]; then
        log_err "PROJECT.md does not exist (run: gen-ai-context.sh --init)"
        exit 1
    fi
    log_ok "PROJECT.md exists ($(wc -l < "$PROJECT_MD") lines)"

    # 2. Check required sections
    for section in "What & Why" "Problem" "Requirements" "Key Decisions" "Constraints"; do
        if grep -q "## $section" "$PROJECT_MD"; then
            log_ok "$section section present"
        else
            log_warn "$section section MISSING"
            issues=$((issues + 1))
        fi
    done

    # 3. Check AUTO-GEN markers exist
    if grep -q "AUTO-GEN:BEGIN" "$PROJECT_MD" && grep -q "AUTO-GEN:END" "$PROJECT_MD"; then
        log_ok "AUTO-GEN markers present"
    else
        log_warn "AUTO-GEN markers missing (auto-update won't work)"
        issues=$((issues + 1))
    fi

    # 4. Check for unfilled TODOs
    local todo_count
    todo_count=$(grep -c '{TODO' "$PROJECT_MD" 2>/dev/null || true)
    if [ "$todo_count" -gt 0 ]; then
        log_warn "$todo_count unfilled {TODO} placeholders"
        issues=$((issues + 1))
    else
        log_ok "No unfilled {TODO} placeholders"
    fi

    # 5. Staleness check — compare current auto-gen vs what's in file
    if grep -q "AUTO-GEN:BEGIN" "$PROJECT_MD"; then
        local current_stack
        current_stack=$(detect_stack)
        if grep -q "$current_stack" "$PROJECT_MD" 2>/dev/null; then
            log_ok "Stack is up-to-date"
        else
            log_warn "Stack may be outdated (current: $current_stack)"
            stale=1
        fi

        # Check if new directories appeared that aren't in Context Map
        for dir in */; do
            dir="${dir%/}"
            case "$dir" in
                node_modules|.git|.prp|.prp-output|.claude|.codex|.opencode|.gemini|.agents|dist|build|__pycache__|.venv|venv|.env|coverage|.nyc_output|logs|output|tmp|temp|.claude-plugin|public|static|assets|backup) continue ;;
                *.backup|*.backup.*|*.bak|*.old|*.orig|*~|*-backup) continue ;;  # backup/stale dir conventions (#72)
            esac
            if find "$dir" -maxdepth 2 \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.go" -o -name "*.rs" -o -name "*.sh" -o -name "*.yaml" \) -print -quit 2>/dev/null | grep -q .; then
                if ! grep -q "\`${dir}/\`\|${dir}/" "$PROJECT_MD" 2>/dev/null; then
                    log_warn "Directory '$dir/' not in Context Map"
                    stale=1
                fi
            fi
        done

        # Reverse scan: warn about Context Map entries pointing at backup/stale dirs
        while IFS= read -r entry; do
            case "$entry" in
                *.backup|*.backup.*|*.bak|*.old|*.orig|*~|*-backup|backup)
                    log_warn "Context Map entry '$entry/' matches backup-dir skip pattern — run --update to remove"
                    stale=1
                    ;;
            esac
        done < <(grep -oE '`[^`]+/`' "$PROJECT_MD" 2>/dev/null | tr -d '`' | sed 's|/$||')
    fi

    # Summary
    log ""
    if [ "$stale" -eq 1 ]; then
        log "${YELLOW}⚠ PROJECT.md is STALE — run: gen-ai-context.sh --update${NC}"
        exit 1
    elif [ "$issues" -gt 0 ]; then
        log "${YELLOW}⚠ PROJECT.md has $issues issue(s) — review manually${NC}"
        exit 0  # issues but not stale (human needs to fill TODOs)
    else
        log "${GREEN}✅ PROJECT.md is up-to-date${NC}"
        exit 0
    fi
}

# ─────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────
case "$MODE" in
    --init)   do_init ;;
    --update) do_update ;;
    --check)  do_check ;;
    *)
        echo "Usage: gen-ai-context.sh [--check | --update | --init] [--quiet]"
        echo ""
        echo "  --check   Validate PROJECT.md (default)"
        echo "  --update  Update AUTO-GEN sections"
        echo "  --init    Create PROJECT.md from template"
        echo "  --quiet   Suppress output (for CI/hooks)"
        exit 1
        ;;
esac

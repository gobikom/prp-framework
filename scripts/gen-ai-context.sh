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
# Invariant W (r4 of #245): every warning reaches stderr because log_warn itself
# writes there — no call site adds its own redirect. Fatal refusals (log_fatal)
# write stderr unconditionally: a refusal stays visible under --quiet too.
log_warn() { $QUIET || echo -e "  ${YELLOW}⚠${NC} $1" >&2; }
log_err() { log "  ${RED}✗${NC} $1"; }
log_fatal() { echo -e "  ${RED}✗${NC} $1" >&2; }

# ─────────────────────────────────────────────────
# AUTO-GEN marker predicate (Invariant M, r4 of #245): the ONLY place marker
# text is matched. Every decision about marker presence, count or position
# goes through these two helpers, and the extractors use their line numbers.
# No other text-matching command in this script may match AUTO-GEN (test M0).
#   BEGIN = a line starting with '<!-- AUTO-GEN:BEGIN' (anchored at column 1)
#   END   = the first line AFTER that BEGIN that is exactly '<!-- AUTO-GEN:END -->'
# ─────────────────────────────────────────────────
autogen_span() { # FILE -> prints "B E" (1-based line numbers of the first block)
    # rc 0 = BEGIN with an END after it; 1 = no BEGIN; 2 = BEGIN but no END after it
    # (an END only before the BEGIN, mid-line, or with trailing spaces is NOT an END);
    # 3 = cannot read (EACCES/EIO/read races, I-1 of #250 R1) — grep runs unpiped so
    # its rc survives (pipefail would mask it), and never aliases to the rc-1
    # "no markers" branch. R3/R4 design fix (Invariant M, นุด option C 2026-11-06):
    # binary-ness is decided by an EXPLICIT whole-file NUL probe BEFORE any grep —
    # past grep's read buffer (~50–100KB observed on ugrep 7.8.4) the BEGIN match
    # flushes as a normal text line before the NUL is detected, so grep exits 0
    # with usable output and the R2 output-shape arm (rc 0 + empty captured stdout
    # / "Binary file …" → rc 3) never fired. ANY NUL anywhere in the file is now
    # rc 3, marker-ful or not — this supersedes the M-EMPTY-NUL marker-less-NUL
    # decision: a NUL-bearing PROJECT.md refuses in both modes instead of
    # no-op-greening through the rc-1 branch. An empty or clean marker-less file
    # still reads as rc 1.
    local file="$1" b e grc tail_out
    # tr strips NULs to stdout; cmp -s re-reads the original: streams differ ⇒ a
    # NUL is present ⇒ rc 3. Under pipefail a tr/cmp read failure (the same
    # EACCES/EIO/race class as the grep rc-2 arm) is also non-zero — every
    # non-zero outcome refuses, fail-closed, at any file size.
    if ! tr -d '\0' < "$file" | cmp -s - "$file"; then
        return 3
    fi
    grc=0; b=$(grep -n '^<!-- AUTO-GEN:BEGIN' "$file") || grc=$?
    if [ "$grc" -eq 2 ]; then return 3; fi
    b=${b%%$'\n'*}; b=${b%%:*}
    case "$b" in ''|*[!0-9]*)
        if [ "$grc" -eq 0 ]; then return 3; fi
        return 1 ;;
    esac
    tail_out=$(tail -n +"$((b + 1))" "$file") || return 3
    e=$(grep -nxF -- '<!-- AUTO-GEN:END -->' <<< "$tail_out") || true
    e=${e%%$'\n'*}; e=${e%%:*}
    case "$e" in ''|*[!0-9]*) return 2 ;; esac
    echo "$b $((b + e))"
}

autogen_begin_count() { # FILE -> count of anchored BEGIN lines; rc 3 = cannot read
    local n grc
    grc=0; n=$(grep -c '^<!-- AUTO-GEN:BEGIN' "$1") || grc=$?
    if [ "$grc" -eq 2 ]; then return 3; fi
    printf '%s\n' "$n"
}

# ─────────────────────────────────────────────────
# Auto-detect: Stack
# ─────────────────────────────────────────────────
detect_stack() {
    local stack=()
    # Common exclude dirs for recursive grep (avoid scanning vendored/generated code)
    local EXCL="--exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=venv --exclude-dir=dist --exclude-dir=build --exclude-dir=__pycache__ --exclude-dir=.sandbox-*"

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
    # Python: pyproject.toml [project.scripts] (PEP 621)
    if [ -f "pyproject.toml" ]; then
        local pyproject_scripts
        pyproject_scripts=$(awk '/^\[project\.scripts\]/{found=1; next} found && /^\[/{exit} found' \
            pyproject.toml 2>/dev/null \
            | grep '=' | awk -F'=' '{gsub(/[ \t]/, "", $1); print $1}' | head -3 \
            || true)
        while IFS= read -r scr; do
            [ -n "$scr" ] && entries+=("pyproject.toml → $scr")
        done <<< "$pyproject_scripts"
    fi
    # Python: */__main__.py (python -m <package>)
    for f in */__main__.py; do
        [ -f "$f" ] && entries+=("python -m $(dirname "$f")")
    done
    # Go: main.go at root + cmd/*/main.go (standard Go layout)
    [ -f "main.go" ] && entries+=("main.go")
    for f in cmd/*/main.go; do
        [ -f "$f" ] && entries+=("$f")
    done
    # Rust: src/main.rs + src/bin/*.rs
    [ -f "src/main.rs" ] && entries+=("src/main.rs")
    for f in src/bin/*.rs; do
        [ -f "$f" ] && entries+=("$f")
    done
    # Java/Kotlin: Application.java or Main.java in Maven/Gradle layout.
    # Fail-visible (Invariant S, r3 of #245): a failed scan warns on stderr and
    # reads as no entry — never as "nothing found" through a silenced pipe.
    # Mirrors the Context Map scan pattern below (find … -prune … -print -quit).
    local java_entry=""
    if [ -d "src/main/java" ]; then
        if ! java_entry=$(find src/main/java -maxdepth 6 \( -type d -name '.sandbox-*' -prune \) -o \( -type f \( -name "Application.java" -o -name "Main.java" \) -print -quit \)); then
            log_warn "could not scan 'src/main/java/' (find failed)"
            java_entry=""
        fi
    fi
    [ -n "$java_entry" ] && entries+=("$java_entry")
    [ -d "bin" ] && {
        for f in bin/*; do
            [ -x "$f" ] && entries+=("$f")
        done
    }
    # Fallback: language detected but no entry found
    if [ "${#entries[@]}" -eq 0 ]; then
        local has_python=false has_go=false has_rust=false has_java=false
        { [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "setup.py" ]; } && has_python=true
        [ -f "go.mod" ] && has_go=true
        [ -f "Cargo.toml" ] && has_rust=true
        { [ -f "pom.xml" ] || [ -f "build.gradle" ]; } && has_java=true
        [ "$has_python" = true ] && entries+=("Python detected — add entry manually")
        [ "$has_go" = true ]     && entries+=("Go detected — add entry manually")
        [ "$has_rust" = true ]   && entries+=("Rust detected — add entry manually")
        [ "$has_java" = true ]   && entries+=("Java/Kotlin detected — add entry manually")
    fi

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
        [ -d "$dir" ] || continue   # unexpanded glob (no non-hidden dirs) is not a dir — never a scan failure
        dir="${dir%/}"
        # Skip common non-code dirs
        case "$dir" in
            node_modules|.git|.prp|.prp-output|.claude|.codex|.opencode|.gemini|.agents|dist|build|__pycache__|.venv|venv|.env|coverage|.nyc_output|logs|output|tmp|temp|backup|old) continue ;;
            src|test|tests|docs|scripts|bin|deploy|config|conf|prisma|public|static|assets) continue ;;  # already handled above
            .sandbox-home|.sandbox-tmp|.sandbox-root|.sandbox-*) continue ;;  # agent sandboxes (chela); defense-in-depth vs dotglob — find below prunes them at depth
            *.backup|*.backup.*|*.bak|*.old|*.orig|*~|*-backup) continue ;;  # backup/stale dir conventions (#72)
        esac
        # Only include if it has code files; a failed scan is visible (stderr),
        # never read as "nothing found"
        local dir_scan
        if ! dir_scan=$(find "$dir" -maxdepth 2 \( -type d -name '.sandbox-*' -prune \) -o \( -type f \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.yaml" -o -name "*.yml" -o -name "*.sh" \) -print -quit \)); then
            log_warn "could not scan '${dir}/' (find failed)"
            continue
        fi
        if [ -n "$dir_scan" ]; then
            echo "| ${dir} | \`${dir}/\` |"
        fi
    done
}

# ─────────────────────────────────────────────────
# Auto-detect: Exports (API endpoints, CLI commands)
# ─────────────────────────────────────────────────
detect_exports() {
    local found=false
    local EXCL="--exclude-dir=node_modules --exclude-dir=.venv --exclude-dir=venv --exclude-dir=dist --exclude-dir=build --exclude-dir=__pycache__ --exclude-dir=.sandbox-*"

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
        log_fatal "PROJECT.md not found. Use --init to create it first."
        exit 1
    fi

    # Invariant M: marker presence and position come only from autogen_span —
    # marker text in prose cannot pass or fail these gates; rc 3 (cannot read) is fatal — never the no-markers branch
    local span rc begin end nblocks
    rc=0; span=$(autogen_span "$PROJECT_MD") || rc=$?
    if [ "$rc" -eq 3 ]; then
        log_fatal "cannot read $PROJECT_MD — refusing to update"
        exit 1
    fi
    if [ "$rc" -eq 1 ]; then
        log "${YELLOW}No AUTO-GEN markers found in PROJECT.md. Skipping update.${NC}"
        exit 0
    fi
    if [ "$rc" -eq 2 ]; then
        log_fatal "AUTO-GEN:BEGIN found but AUTO-GEN:END missing — refusing to update (would lose content)"
        exit 1
    fi
    read -r begin end <<< "$span"

    # Only the first AUTO-GEN block is maintained; extra ones survive in $after — say so
    nblocks=$(autogen_begin_count "$PROJECT_MD") || { log_fatal "cannot read $PROJECT_MD — refusing to update"; exit 1; }
    if [ "$nblocks" -gt 1 ]; then
        log_warn "extra AUTO-GEN block(s) found; only the first is maintained"
    fi

    # Extract by the helper's line numbers: before = 1..B-1 (empty when B=1),
    # after = E+1..$ — body content below the block can never be lost to a
    # pattern match.
    local before after
    if [ "$begin" -gt 1 ]; then
        before=$(sed -n "1,$((begin - 1))p" "$PROJECT_MD")
    else
        before=""
    fi
    after=$(sed -n "$((end + 1)),\$p" "$PROJECT_MD")

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
        log_fatal "Failed to write PROJECT.md — original preserved"
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
        log_fatal "PROJECT.md does not exist (run: gen-ai-context.sh --init)"
        exit 1
    fi
    local md_lines
    md_lines=$(wc -l < "$PROJECT_MD" 2>/dev/null) || md_lines="?"
    log_ok "PROJECT.md exists ($md_lines lines)"

    # 2. Check required sections
    for section in "What & Why" "Problem" "Requirements" "Key Decisions" "Constraints"; do
        if grep -q "## $section" "$PROJECT_MD"; then
            log_ok "$section section present"
        else
            log_warn "$section section MISSING"
            issues=$((issues + 1))
        fi
    done

    # 3. Check AUTO-GEN markers exist (Invariant M: only autogen_span decides —
    # a BEGIN without its END after it is not "present"; rc 3, cannot read, is fatal — never marker-less or up-to-date)
    local span rc begin end nblocks
    rc=0; span=$(autogen_span "$PROJECT_MD") || rc=$?
    if [ "$rc" -eq 3 ]; then
        log_fatal "cannot read $PROJECT_MD — refusing to check"
        exit 1
    fi
    if [ "$rc" -eq 0 ]; then
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

    # 5. Staleness check — compare current auto-gen vs what's in file.
    # (Invariant M: the block is read by autogen_span's line numbers; rc 2 —
    # BEGIN without an END after it — fails closed as stale, A2's intent now
    # actually reachable: marker text in prose cannot satisfy any of this.)
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
        local current_stack autogen_block
        current_stack=$(detect_stack)
        autogen_block=""
        if [ "$rc" -eq 2 ]; then
            # A missing END must never read as "up-to-date": do_update refuses
            # this file (would lose content); do_check marks it stale instead,
            # so body prose below the dangling BEGIN cannot satisfy the check.
            log_warn "AUTO-GEN:BEGIN found but AUTO-GEN:END missing"
            stale=1
        else
            read -r begin end <<< "$span"
            autogen_block=$(sed -n "${begin},${end}p" "$PROJECT_MD")
            if grep -qxF -- "- **Stack:** $current_stack" <<< "$autogen_block"; then
                log_ok "Stack is up-to-date"
            else
                log_warn "Stack may be outdated (current: $current_stack)"
                stale=1
            fi
        fi
        nblocks=$(autogen_begin_count "$PROJECT_MD") || { log_fatal "cannot read $PROJECT_MD — refusing to check"; exit 1; }
        if [ "$nblocks" -gt 1 ]; then
            log_warn "extra AUTO-GEN block(s) found; only the first is maintained"
            stale=1
        fi

        # Check if new directories appeared that aren't in Context Map
        for dir in */; do
            [ -d "$dir" ] || continue   # unexpanded glob (no non-hidden dirs) is not a dir — never a scan failure
            dir="${dir%/}"
            case "$dir" in
                node_modules|.git|.prp|.prp-output|.claude|.codex|.opencode|.gemini|.agents|dist|build|__pycache__|.venv|venv|.env|coverage|.nyc_output|logs|output|tmp|temp|.claude-plugin|public|static|assets|backup|old|.sandbox-home|.sandbox-tmp|.sandbox-root|.sandbox-*) continue ;;  # .sandbox-* = agent sandboxes (chela), defense-in-depth vs dotglob — find below prunes them at depth
                *.backup|*.backup.*|*.bak|*.old|*.orig|*~|*-backup) continue ;;  # backup/stale dir conventions (#72)
            esac
            local dir_scan
            if ! dir_scan=$(find "$dir" -maxdepth 2 \( -type d -name '.sandbox-*' -prune \) -o \( -type f \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.go" -o -name "*.rs" -o -name "*.sh" -o -name "*.yaml" \) -print -quit \)); then
                log_warn "could not scan '${dir}/' (find failed)"
                stale=1
                continue
            fi
            if [ -n "$dir_scan" ] && ! grep -q "\`${dir}/\`\|${dir}/" "$PROJECT_MD" 2>/dev/null; then
                log_warn "Directory '$dir/' not in Context Map"
                stale=1
            fi
        done

        # Reverse scan: Context Map entries pointing at backup/stale dirs
        # Uses process substitution (not pipe) so stale=1 propagates to parent
        # shell; reads the first block by the helper's line numbers (rc 0 only).
        if [ "$rc" -eq 0 ]; then
            while IFS= read -r entry; do
                local base
                base=$(basename "$entry")
                case "$base" in
                    *.backup|*.backup.*|*.bak|*.old|*.orig|*~|*-backup|backup|old)
                        log_warn "Context Map entry '$entry/' matches backup-dir skip pattern — run --update to remove"
                        stale=1
                        ;;
                esac
            done < <(printf '%s\n' "$autogen_block" | grep -oE '`[^`]+/`' | tr -d '`' | sed 's|/$||')
        fi
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

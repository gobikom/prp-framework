#!/usr/bin/env bash
set -euo pipefail

# prp-validate — parallel validation with compact JSON output
# Runs type-check, lint, test, build in parallel and returns failures-only JSON.
# Usage: prp-validate.sh [PROJECT_DIR] [CHECKS]
#   PROJECT_DIR: directory to validate (default: current dir)
#   CHECKS: comma-separated list (default: type_check,lint,test,build)

PROJECT_DIR="${1:-.}"
CHECKS="${2:-type_check,lint,test,build}"
cd "$PROJECT_DIR"

# Auto-detect runner from lock files
detect_runner() {
    if [ -f "bun.lockb" ]; then echo "bun"
    elif [ -f "pnpm-lock.yaml" ]; then echo "pnpm"
    elif [ -f "yarn.lock" ]; then echo "yarn"
    elif [ -f "package-lock.json" ]; then echo "npm"
    elif [ -f "pyproject.toml" ] || ls requirements*.txt >/dev/null 2>&1 || [ -f "setup.py" ]; then echo "python"
    elif [ -f "Cargo.toml" ]; then echo "cargo"
    elif [ -f "go.mod" ]; then echo "go"
    else echo "unknown"; fi
}

RUNNER=$(detect_runner)
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Detect scripts based on runner
TC_SCRIPT="" LINT_SCRIPT="" TEST_SCRIPT="" BUILD_SCRIPT=""
if [ -f "package.json" ] && command -v node >/dev/null 2>&1; then
    TC_SCRIPT=$(node -e "const s=(require('./package.json').scripts||{}); console.log(s['type-check']?'type-check':s.typecheck?'typecheck':s.tsc?'tsc':'')" 2>/dev/null || echo "")
    LINT_SCRIPT=$(node -e "const s=(require('./package.json').scripts||{}); console.log(s.lint?'lint':'')" 2>/dev/null || echo "")
    TEST_SCRIPT=$(node -e "const s=(require('./package.json').scripts||{}); console.log(s.test?'test':'')" 2>/dev/null || echo "")
    BUILD_SCRIPT=$(node -e "const s=(require('./package.json').scripts||{}); console.log(s.build?'build':'')" 2>/dev/null || echo "")
elif [ "$RUNNER" = "python" ]; then
    TC_SCRIPT=""; LINT_SCRIPT=""; TEST_SCRIPT=""; BUILD_SCRIPT=""
fi

# Build commands per runner
build_cmd() {
    local check="$1"
    case "$RUNNER" in
        bun)
            case "$check" in
                type_check) [ -n "$TC_SCRIPT" ] && echo "bun run $TC_SCRIPT" ;;
                lint) [ -n "$LINT_SCRIPT" ] && echo "bun run $LINT_SCRIPT" ;;
                test) echo "bun test" ;;
                build) [ -n "$BUILD_SCRIPT" ] && echo "bun run $BUILD_SCRIPT" ;;
            esac ;;
        pnpm|npm|yarn)
            case "$check" in
                type_check) [ -n "$TC_SCRIPT" ] && echo "$RUNNER run $TC_SCRIPT" ;;
                lint) [ -n "$LINT_SCRIPT" ] && echo "$RUNNER run $LINT_SCRIPT" ;;
                test) echo "$RUNNER test" ;;
                build) [ -n "$BUILD_SCRIPT" ] && echo "$RUNNER run $BUILD_SCRIPT" ;;
            esac ;;
        python)
            case "$check" in
                type_check) command -v mypy >/dev/null 2>&1 && echo "python3 -m mypy ." ;;
                lint) command -v ruff >/dev/null 2>&1 && echo "python3 -m ruff check ." || { command -v flake8 >/dev/null 2>&1 && echo "python3 -m flake8 ."; } ;;
                test) command -v pytest >/dev/null 2>&1 && echo "python3 -m pytest" || echo "python3 -m unittest discover" ;;
                build) ;; # Python typically has no build step
            esac ;;
        cargo)
            case "$check" in
                type_check) echo "cargo check" ;;
                lint) echo "cargo clippy -- -D warnings" ;;
                test) echo "cargo test" ;;
                build) echo "cargo build" ;;
            esac ;;
        go)
            case "$check" in
                type_check) echo "go vet ./..." ;;
                lint) command -v golangci-lint >/dev/null 2>&1 && echo "golangci-lint run" ;;
                test) echo "go test ./..." ;;
                build) echo "go build ./..." ;;
            esac ;;
    esac
}

run_check() {
    local name="$1"
    local cmd
    cmd=$(build_cmd "$name")
    local outfile="$TMPDIR/$name"

    if [ -z "$cmd" ]; then
        echo "{\"status\":\"skip\",\"reason\":\"no script\"}" > "$outfile.json"
        return 0
    fi

    local start_ns
    start_ns=$(date +%s%N 2>/dev/null || echo 0)
    if eval "$cmd" > "$outfile.stdout" 2>&1; then
        local end_ns
        end_ns=$(date +%s%N 2>/dev/null || echo 0)
        local dur=$(( (end_ns - start_ns) / 1000000 ))
        echo "{\"status\":\"pass\",\"duration_ms\":$dur}" > "$outfile.json"
    else
        local ec=$?
        local end_ns
        end_ns=$(date +%s%N 2>/dev/null || echo 0)
        local dur=$(( (end_ns - start_ns) / 1000000 ))
        # Extract failure lines (errors, fails, warnings — max 20 lines)
        local fails
        fails=$(grep -iE "error|fail|✗|×|warning|WARN" "$outfile.stdout" 2>/dev/null | head -20 | sed 's/"/\\"/g' | tr '\n' ' | ' | sed 's/ | $//')
        [ -z "$fails" ] && fails=$(tail -5 "$outfile.stdout" | sed 's/"/\\"/g' | tr '\n' ' | ' | sed 's/ | $//')
        echo "{\"status\":\"fail\",\"exit_code\":$ec,\"duration_ms\":$dur,\"failures\":\"$fails\"}" > "$outfile.json"
    fi
}

# Run requested checks in parallel
for check in ${CHECKS//,/ }; do
    run_check "$check" &
done
wait

# Assemble JSON output
echo "{"
first=true
for check in type_check lint test build; do
    if [ -f "$TMPDIR/$check.json" ]; then
        if [ "$first" = true ]; then first=false; else echo ","; fi
        printf "  \"%s\": %s" "$check" "$(cat "$TMPDIR/$check.json")"
    fi
done
echo ""
echo "}"

#!/bin/bash
# Inject PRP Framework section into target repo's CLAUDE.md
# Uses BEGIN/END markers for idempotent updates
#
# Usage: inject-claude-md.sh [TARGET_DIR] [OPTIONS]
# Options:
#   --dry-run   Show what would be injected without modifying files
#   --remove    Remove PRP section from CLAUDE.md
#   --check     Exit 0 if up-to-date, 1 if needs update (for CI)

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
TARGET_DIR=""
DRY_RUN=false
REMOVE=false
CHECK_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=true ;;
        --remove)   REMOVE=true ;;
        --check)    CHECK_ONLY=true ;;
        -*)         echo -e "${RED}Unknown option: $arg${NC}"; exit 1 ;;
        *)          TARGET_DIR="$arg" ;;
    esac
done

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$(cd "$FRAMEWORK_DIR/.." && pwd)"
fi
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# Get current version
CURRENT_VERSION=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$FRAMEWORK_DIR/CHANGELOG.md" 2>/dev/null | head -1)
if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="0.0.0"
fi

# Read template
TEMPLATE_FILE="$FRAMEWORK_DIR/templates/claude-md-section.md"
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}Error: Template not found: $TEMPLATE_FILE${NC}"
    exit 1
fi

# Generate section content with version substituted
SECTION_CONTENT=$(sed "s/{VERSION}/$CURRENT_VERSION/g" "$TEMPLATE_FILE")

# Target file
CLAUDE_MD="$TARGET_DIR/CLAUDE.md"

# Markers
BEGIN_MARKER="<!-- PRP-FRAMEWORK:BEGIN"
END_MARKER="<!-- PRP-FRAMEWORK:END -->"

# --- REMOVE mode ---
if $REMOVE; then
    if [ ! -f "$CLAUDE_MD" ]; then
        echo -e "${YELLOW}  No CLAUDE.md found at $CLAUDE_MD — nothing to remove${NC}"
        exit 0
    fi

    if ! grep -q "$BEGIN_MARKER" "$CLAUDE_MD"; then
        echo -e "${YELLOW}  No PRP section found in CLAUDE.md — nothing to remove${NC}"
        exit 0
    fi

    if $DRY_RUN; then
        echo -e "${YELLOW}  [dry-run] Would remove PRP section from $CLAUDE_MD${NC}"
        exit 0
    fi

    # Remove section between markers (inclusive) and clean up extra blank lines
    TEMP_FILE=$(mktemp)
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
        $0 ~ begin { skip=1; next }
        $0 ~ end   { skip=0; next }
        !skip { print }
    ' "$CLAUDE_MD" > "$TEMP_FILE"

    # Clean up trailing blank lines left by removal
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$TEMP_FILE"
    mv "$TEMP_FILE" "$CLAUDE_MD"
    echo -e "${GREEN}  ✅ Removed PRP section from CLAUDE.md${NC}"
    exit 0
fi

# --- CHECK mode ---
if $CHECK_ONLY; then
    if [ ! -f "$CLAUDE_MD" ]; then
        exit 1
    fi

    if ! grep -q "$BEGIN_MARKER" "$CLAUDE_MD"; then
        exit 1
    fi

    # Extract version from existing marker
    EXISTING_VERSION=$(grep -oP 'PRP-FRAMEWORK:BEGIN v\K[0-9]+\.[0-9]+\.[0-9]+' "$CLAUDE_MD" | head -1)
    if [ "$EXISTING_VERSION" = "$CURRENT_VERSION" ]; then
        exit 0
    else
        exit 1
    fi
fi

# --- INJECT / UPDATE mode ---

# Check if CLAUDE.md exists
if [ ! -f "$CLAUDE_MD" ]; then
    if $DRY_RUN; then
        echo -e "${YELLOW}  [dry-run] Would create $CLAUDE_MD with PRP section (v$CURRENT_VERSION)${NC}"
        echo ""
        echo "$SECTION_CONTENT"
        exit 0
    fi

    echo "$SECTION_CONTENT" > "$CLAUDE_MD"
    echo -e "${GREEN}  ✅ Created CLAUDE.md with PRP section (v$CURRENT_VERSION)${NC}"
    exit 0
fi

# Check for existing PRP section
if grep -q "$BEGIN_MARKER" "$CLAUDE_MD"; then
    # Extract existing version
    EXISTING_VERSION=$(grep -oP 'PRP-FRAMEWORK:BEGIN v\K[0-9]+\.[0-9]+\.[0-9]+' "$CLAUDE_MD" | head -1)

    if [ "$EXISTING_VERSION" = "$CURRENT_VERSION" ]; then
        echo -e "${GREEN}  ✅ PRP section already up-to-date (v$CURRENT_VERSION)${NC}"
        exit 0
    fi

    if $DRY_RUN; then
        echo -e "${YELLOW}  [dry-run] Would update PRP section: v$EXISTING_VERSION → v$CURRENT_VERSION${NC}"
        echo ""
        echo "$SECTION_CONTENT"
        exit 0
    fi

    # Replace existing section in-place
    TEMP_FILE=$(mktemp)
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v content="$SECTION_CONTENT" '
        $0 ~ begin {
            print content
            skip=1
            next
        }
        $0 ~ end {
            skip=0
            next
        }
        !skip { print }
    ' "$CLAUDE_MD" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$CLAUDE_MD"

    echo -e "${GREEN}  ✅ Updated PRP section: v$EXISTING_VERSION → v$CURRENT_VERSION${NC}"

    # Warn if multiple sections detected
    COUNT=$(grep -c "$BEGIN_MARKER" "$CLAUDE_MD" || true)
    if [ "$COUNT" -gt 1 ]; then
        echo -e "${YELLOW}  ⚠️  Warning: $COUNT PRP sections found — please remove duplicates manually${NC}"
    fi
else
    if $DRY_RUN; then
        echo -e "${YELLOW}  [dry-run] Would append PRP section to CLAUDE.md (v$CURRENT_VERSION)${NC}"
        echo ""
        echo "$SECTION_CONTENT"
        exit 0
    fi

    # Append to end of file with blank line separator
    echo "" >> "$CLAUDE_MD"
    echo "$SECTION_CONTENT" >> "$CLAUDE_MD"
    echo -e "${GREEN}  ✅ Injected PRP section into CLAUDE.md (v$CURRENT_VERSION)${NC}"
fi

#!/bin/bash

# PRP Framework - Artifact Cleanup Script
# Deletes artifacts older than specified days
#
# Usage: ./cleanup-artifacts.sh [days]
# Default: 30 days

set -e

# Default to 30 days if not specified
DAYS=${1:-30}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Find .prp-output directory
if [ -d ".prp-output" ]; then
    PRP_DIR=".prp-output"
elif [ -d "../.prp-output" ]; then
    PRP_DIR="../.prp-output"
else
    echo -e "${RED}Error: .prp-output directory not found${NC}"
    echo "Run this script from the project root or .prp directory"
    exit 1
fi

echo -e "${BLUE}=== PRP Artifact Cleanup ===${NC}"
echo -e "Looking for artifacts older than ${YELLOW}${DAYS} days${NC} in ${PRP_DIR}"
echo ""

# Directories to clean
DIRS=(
    "prds/drafts"
    "designs"
    "plans"
    "reports"
    "debug"
    "issues"
    "reviews"
)

# Track stats
TOTAL_DELETED=0
TOTAL_KEPT=0

for dir in "${DIRS[@]}"; do
    FULL_PATH="${PRP_DIR}/${dir}"

    if [ -d "$FULL_PATH" ]; then
        echo -e "${BLUE}Scanning: ${FULL_PATH}${NC}"

        # Find files older than DAYS days
        OLD_FILES=$(find "$FULL_PATH" -maxdepth 1 -name "*.md" -type f -mtime +${DAYS} 2>/dev/null || true)

        if [ -n "$OLD_FILES" ]; then
            COUNT=$(echo "$OLD_FILES" | wc -l | tr -d ' ')
            echo -e "  Found ${YELLOW}${COUNT}${NC} files older than ${DAYS} days"

            echo "$OLD_FILES" | while read -r file; do
                if [ -n "$file" ]; then
                    FILENAME=$(basename "$file")
                    MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null || stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1)
                    echo -e "    ${RED}DELETE:${NC} ${FILENAME} (modified: ${MODIFIED})"
                fi
            done

            # Confirm deletion
            echo ""
            read -p "Delete these files? (y/N): " CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "$OLD_FILES" | while read -r file; do
                    if [ -n "$file" ]; then
                        rm "$file"
                        ((TOTAL_DELETED++)) || true
                    fi
                done
                echo -e "  ${GREEN}Deleted ${COUNT} files${NC}"
            else
                echo -e "  ${YELLOW}Skipped${NC}"
                TOTAL_KEPT=$((TOTAL_KEPT + COUNT))
            fi
        else
            CURRENT_COUNT=$(find "$FULL_PATH" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
            echo -e "  ${GREEN}No old files (${CURRENT_COUNT} current files)${NC}"
        fi

        echo ""
    fi
done

# Check completed folders
COMPLETED_DIRS=(
    "plans/completed"
    "issues/completed"
)

echo -e "${BLUE}=== Completed Folders ===${NC}"
for dir in "${COMPLETED_DIRS[@]}"; do
    FULL_PATH="${PRP_DIR}/${dir}"

    if [ -d "$FULL_PATH" ]; then
        OLD_FILES=$(find "$FULL_PATH" -name "*.md" -type f -mtime +${DAYS} 2>/dev/null || true)

        if [ -n "$OLD_FILES" ]; then
            COUNT=$(echo "$OLD_FILES" | wc -l | tr -d ' ')
            echo -e "${YELLOW}${FULL_PATH}:${NC} ${COUNT} archived files older than ${DAYS} days"

            echo ""
            read -p "Delete archived files? (y/N): " CONFIRM

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "$OLD_FILES" | while read -r file; do
                    if [ -n "$file" ]; then
                        rm "$file"
                        ((TOTAL_DELETED++)) || true
                    fi
                done
                echo -e "  ${GREEN}Deleted ${COUNT} archived files${NC}"
            fi
        else
            echo -e "${GREEN}${FULL_PATH}:${NC} No old archived files"
        fi
    fi
done

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "Cleanup complete for artifacts older than ${YELLOW}${DAYS} days${NC}"
echo ""
echo "Tips:"
echo "  - Run regularly: ./cleanup-artifacts.sh 30"
echo "  - Add to weekly cron: 0 0 * * 0 /path/to/cleanup-artifacts.sh 30"
echo "  - Keep recent artifacts: ./cleanup-artifacts.sh 7"

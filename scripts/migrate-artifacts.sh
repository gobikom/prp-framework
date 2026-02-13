#!/bin/bash

# PRP Framework - Artifact Migration Script
# Migrates artifacts from old paths to unified .prp-output/
#
# Old paths:
#   .claude/PRPs/    -> .prp-output/
#   .ai-workflows/   -> .prp-output/
#
# Usage: ./migrate-artifacts.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== PRP Artifact Migration ===${NC}"
echo ""

MIGRATED=false

# Migrate from .claude/PRPs/
if [ -d ".claude/PRPs" ]; then
    echo -e "${YELLOW}Found .claude/PRPs/ - migrating...${NC}"
    mkdir -p .prp-output
    cp -r .claude/PRPs/* .prp-output/ 2>/dev/null || true
    echo -e "${GREEN}  Migrated .claude/PRPs/ -> .prp-output/${NC}"
    MIGRATED=true
fi

# Migrate from .ai-workflows/plans/
if [ -d ".ai-workflows/plans" ]; then
    echo -e "${YELLOW}Found .ai-workflows/plans/ - migrating...${NC}"
    mkdir -p .prp-output/plans
    cp -r .ai-workflows/plans/* .prp-output/plans/ 2>/dev/null || true
    echo -e "${GREEN}  Migrated .ai-workflows/plans/ -> .prp-output/plans/${NC}"
    MIGRATED=true
fi

# Migrate from .ai-workflows/reports/
if [ -d ".ai-workflows/reports" ]; then
    echo -e "${YELLOW}Found .ai-workflows/reports/ - migrating...${NC}"
    mkdir -p .prp-output/reports
    cp -r .ai-workflows/reports/* .prp-output/reports/ 2>/dev/null || true
    echo -e "${GREEN}  Migrated .ai-workflows/reports/ -> .prp-output/reports/${NC}"
    MIGRATED=true
fi

echo ""

if $MIGRATED; then
    echo -e "${GREEN}Migration complete!${NC}"
    echo ""
    echo "Old directories were NOT deleted. To clean up manually:"
    echo "  rm -rf .claude/PRPs"
    echo "  rm -rf .ai-workflows"
else
    echo "No old artifact directories found. Nothing to migrate."
fi

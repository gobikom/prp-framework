#!/bin/bash
# PRP Framework Sync Script
# For projects using hard copy installation (not symlinks)

set -e

echo "🔄 Syncing PRP Framework updates..."
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$FRAMEWORK_DIR/.." && pwd)"

echo "Framework directory: $FRAMEWORK_DIR"
echo "Project directory: $PROJECT_DIR"
echo ""

# Function: Sync directory if it's not a symlink
sync_directory() {
    local source=$1
    local target=$2
    local name=$3

    if [ -L "$target" ]; then
        echo -e "${GREEN}  ⏭️  Skipped (symlink): $name${NC}"
        return 0
    fi

    if [ -d "$target" ]; then
        rm -rf "$target"
        cp -r "$source" "$target"
        echo -e "${GREEN}  ✅ Synced: $name${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Not found: $target${NC}"
    fi
}

# Function: Sync file if it's not a symlink
sync_file() {
    local source=$1
    local target=$2
    local name=$3

    if [ -L "$target" ]; then
        echo -e "${GREEN}  ⏭️  Skipped (symlink): $name${NC}"
        return 0
    fi

    if [ -f "$target" ]; then
        rm -f "$target"
        cp "$source" "$target"
        echo -e "${GREEN}  ✅ Synced: $name${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Not found: $target${NC}"
    fi
}

echo "📦 Syncing adapters..."
echo ""

# Sync prompts
sync_directory "$FRAMEWORK_DIR/prompts" "$PROJECT_DIR/.ai-workflows/prompts" "Prompts"

# Sync Claude Code
sync_directory "$FRAMEWORK_DIR/adapters/claude-code" "$PROJECT_DIR/.claude/commands/prp-core" "Claude Code"

# Sync Codex
for skill_dir in "$FRAMEWORK_DIR/adapters/codex"/prp-*; do
    if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        sync_directory "$skill_dir" "$PROJECT_DIR/.codex/skills/$skill_name" "Codex: $skill_name"
    fi
done

# Sync OpenCode
sync_directory "$FRAMEWORK_DIR/adapters/opencode" "$PROJECT_DIR/.opencode/commands/prp" "OpenCode"

# Sync Gemini
sync_directory "$FRAMEWORK_DIR/adapters/gemini" "$PROJECT_DIR/.gemini/commands/prp" "Gemini"

# Sync Generic
sync_file "$FRAMEWORK_DIR/adapters/generic/AGENTS.md" "$PROJECT_DIR/AGENTS.md" "AGENTS.md"

echo ""
echo -e "${GREEN}✅ Sync complete!${NC}"
echo ""

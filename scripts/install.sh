#!/bin/bash
# PRP Framework Installation Script
# Supports symlinks (preferred) with fallback to hard copy

set -e

echo "🚀 Installing PRP Framework..."
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get absolute path to framework directory
FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$FRAMEWORK_DIR/.." && pwd)"

echo "Framework directory: $FRAMEWORK_DIR"
echo "Project directory: $PROJECT_DIR"
echo ""

# Function: Try symlink, fallback to copy
install_directory() {
    local source=$1
    local target=$2
    local name=$3

    # Remove target if exists
    if [ -e "$target" ] || [ -L "$target" ]; then
        echo -e "${YELLOW}  ⚠️  Removing existing: $target${NC}"
        rm -rf "$target"
    fi

    # Try symlink first
    if ln -s "$source" "$target" 2>/dev/null; then
        echo -e "${GREEN}  ✅ Symlinked: $name${NC}"
        return 0
    else
        # Fallback to copy
        echo -e "${YELLOW}  ⚠️  Symlink failed for $name, copying instead${NC}"
        cp -r "$source" "$target"
        echo -e "${GREEN}  ✅ Copied: $name${NC}"
        return 1
    fi
}

# Function: Install file symlink
install_file() {
    local source=$1
    local target=$2
    local name=$3

    # Remove target if exists
    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -f "$target"
    fi

    if ln -s "$source" "$target" 2>/dev/null; then
        echo -e "${GREEN}  ✅ Symlinked: $name${NC}"
        return 0
    else
        echo -e "${YELLOW}  ⚠️  Symlink failed for $name, copying instead${NC}"
        cp "$source" "$target"
        echo -e "${GREEN}  ✅ Copied: $name${NC}"
        return 1
    fi
}

USED_SYMLINKS=false
USED_COPY=false

echo "📦 Installing adapters..."
echo ""

# Install Claude Code Commands
echo "→ Claude Code Commands (.claude/commands/prp-core/)"
mkdir -p "$PROJECT_DIR/.claude/commands"
if install_directory "$FRAMEWORK_DIR/adapters/claude-code" "$PROJECT_DIR/.claude/commands/prp-core" "Claude Code Commands"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Install Claude Code Marketing Commands
echo "→ Claude Code Marketing (.claude/commands/prp-mkt/)"
if install_directory "$FRAMEWORK_DIR/adapters/claude-code-marketing" "$PROJECT_DIR/.claude/commands/prp-mkt" "Claude Code Marketing"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Install Claude Code Bot Commands
echo "→ Claude Code Bot (.claude/commands/prp-bot/)"
if install_directory "$FRAMEWORK_DIR/adapters/claude-code-bot" "$PROJECT_DIR/.claude/commands/prp-bot" "Claude Code Bot"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Install Claude Code Agents
echo "→ Claude Code Agents (.claude/agents/)"
mkdir -p "$PROJECT_DIR/.claude"
if install_directory "$FRAMEWORK_DIR/adapters/claude-code-agents" "$PROJECT_DIR/.claude/agents" "Claude Code Agents"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Install Claude Code Skills
echo "→ Claude Code Skills (.claude/skills/)"
mkdir -p "$PROJECT_DIR/.claude/skills"
for skill_dir in "$FRAMEWORK_DIR/adapters/claude-code-skills"/*; do
    if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        if install_directory "$skill_dir" "$PROJECT_DIR/.claude/skills/$skill_name" "Claude Code Skill: $skill_name"; then
            USED_SYMLINKS=true
        else
            USED_COPY=true
        fi
    fi
done

# Install Claude Code Hooks
echo "→ Claude Code Hooks (.claude/hooks/)"
mkdir -p "$PROJECT_DIR/.claude"
if install_directory "$FRAMEWORK_DIR/adapters/claude-code-hooks" "$PROJECT_DIR/.claude/hooks" "Claude Code Hooks"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Install Claude Code Plugin metadata
echo "→ Claude Code Plugin (.claude-plugin/)"
mkdir -p "$PROJECT_DIR/.claude-plugin"
if install_file "$FRAMEWORK_DIR/adapters/claude-code-plugin/marketplace.json" "$PROJECT_DIR/.claude-plugin/marketplace.json" "Plugin metadata"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Install Codex (directory structure)
echo "→ Codex (.codex/skills/)"
mkdir -p "$PROJECT_DIR/.codex/skills"
for skill_dir in "$FRAMEWORK_DIR/adapters/codex"/prp-*; do
    if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        if install_directory "$skill_dir" "$PROJECT_DIR/.codex/skills/$skill_name" "Codex: $skill_name"; then
            USED_SYMLINKS=true
        else
            USED_COPY=true
        fi
    fi
done

# Install OpenCode
echo "→ OpenCode (.opencode/commands/prp/)"
mkdir -p "$PROJECT_DIR/.opencode/commands"
if install_directory "$FRAMEWORK_DIR/adapters/opencode" "$PROJECT_DIR/.opencode/commands/prp" "OpenCode"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Install Gemini
echo "→ Gemini (.gemini/commands/prp/)"
mkdir -p "$PROJECT_DIR/.gemini/commands"
if install_directory "$FRAMEWORK_DIR/adapters/gemini" "$PROJECT_DIR/.gemini/commands/prp" "Gemini"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Install Generic (single file)
echo "→ Generic (AGENTS.md)"
if install_file "$FRAMEWORK_DIR/adapters/generic/AGENTS.md" "$PROJECT_DIR/AGENTS.md" "AGENTS.md"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

echo ""
echo "📁 Creating runtime artifact directories..."
mkdir -p "$PROJECT_DIR/.prp-output"/{prds/drafts,designs,plans/completed,reports,reviews,debug,issues/completed}
echo -e "${GREEN}  ✅ Created .prp-output/ structure${NC}"

# Add gitignore rules to consumer project
echo ""
echo "📝 Configuring .gitignore..."
GITIGNORE_FILE="$PROJECT_DIR/.gitignore"
PRP_MARKER="# PRP Framework"

if [ -f "$GITIGNORE_FILE" ] && grep -q "$PRP_MARKER" "$GITIGNORE_FILE"; then
    echo -e "${GREEN}  ✅ .gitignore already configured${NC}"
else
    cat >> "$GITIGNORE_FILE" << 'GITIGNORE'

# PRP Framework - generated adapters (recreate with: cd .prp && ./scripts/install.sh)
.claude/
.claude-plugin/
.codex/
.opencode/
.gemini/
AGENTS.md

# PRP Framework - artifacts (directory visible to AI tools, content not tracked)
.prp-output/**
!.prp-output/
!.prp-output/**/
GITIGNORE
    echo -e "${GREEN}  ✅ Added PRP rules to .gitignore${NC}"
fi

# If .prp is NOT a submodule (local clone), also gitignore it
if [ -f "$PROJECT_DIR/.gitmodules" ] && grep -q '\.prp' "$PROJECT_DIR/.gitmodules" 2>/dev/null; then
    : # Submodule — don't gitignore .prp/
elif ! grep -q '^\.prp/$' "$GITIGNORE_FILE" 2>/dev/null; then
    cat >> "$GITIGNORE_FILE" << 'GITIGNORE2'

# PRP Framework - local clone (not a submodule)
.prp/
GITIGNORE2
    echo -e "${GREEN}  ✅ Added .prp/ to .gitignore (local clone detected)${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if $USED_SYMLINKS && ! $USED_COPY; then
    echo -e "${GREEN}✅ Installation complete using symlinks!${NC}"
    echo ""
    echo "Updates are automatic - just run 'git pull' in the submodule:"
    echo "  cd .prp && git pull origin main"
elif $USED_COPY; then
    echo -e "${YELLOW}⚠️  Installation complete using hard copy (symlinks not fully supported)${NC}"
    echo ""
    echo "To update framework, run:"
    echo "  cd .prp && git pull && ./scripts/sync.sh"
fi

echo ""
echo "Available workflows:"
echo "  • Claude Code Core: /prp-core:prd, /prp-core:plan, /prp-core:implement, etc."
echo "  • Claude Code Marketing: /prp-mkt:landing, /prp-mkt:demo, /prp-mkt:pitch, /prp-mkt:competitor"
echo "  • Claude Code Bot: /prp-bot:intent, /prp-bot:flow, /prp-bot:prompt-eng, /prp-bot:voice-ux, /prp-bot:integration"
echo "  • Codex: \$prp-prd, \$prp-design, \$prp-plan, etc."
echo "  • OpenCode: /prp:prd, /prp:design, /prp:plan, etc."
echo "  • Gemini: /prp:prd, /prp:design, /prp:plan, etc."
echo "  • Kimi/Generic: Use natural language (see AGENTS.md)"
echo ""
echo "Documentation: $FRAMEWORK_DIR/docs/"
echo ""

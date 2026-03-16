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

# PROJECT_DIR: accept as $1 (for symlink installs), env var, or derive from parent
if [ -n "$1" ]; then
    PROJECT_DIR="$(cd "$1" && pwd)"
elif [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(cd "$FRAMEWORK_DIR/.." && pwd)"
fi

echo "Framework directory: $FRAMEWORK_DIR"
echo "Project directory: $PROJECT_DIR"
echo ""

# Auto-recover: restore agent/hook files if a previous buggy install converted
# them from blobs to self-referencing symlinks (bash || && precedence bug).
# Safe to run always — no-op if files are clean.
for _dir in "adapters/claude-code-agents" "adapters/claude-code-hooks"; do
    if git -C "$FRAMEWORK_DIR" status --short "$_dir" 2>/dev/null | grep -q " T "; then
        echo -e "${YELLOW}⚠️  Restoring damaged files in $_dir (typechange detected)...${NC}"
        git -C "$FRAMEWORK_DIR" checkout -- "$_dir"
        echo -e "${GREEN}  ✅ Restored${NC}"
    fi
done

# Function: Try symlink, fallback to copy
# Safe: skips if already correct symlink, removes only PRP-owned symlinks/dirs
install_directory() {
    local source=$1
    local target=$2
    local name=$3

    # Skip if already a correct symlink (idempotent fast path)
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        echo -e "${GREEN}  ✅ Already up-to-date: $name${NC}"
        return 0
    fi

    if [ -L "$target" ]; then
        # It's a symlink pointing elsewhere — safe to replace
        rm -f "$target"
    elif [ -e "$target" ]; then
        # It's a real directory — warn before removing
        echo -e "${YELLOW}  ⚠️  Removing existing directory: $target${NC}"
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

# Function: Install individual files into a shared directory (preserves non-PRP files)
# Use for shared dirs like .claude/agents/ and .claude/hooks/ that may contain custom files
install_files_into_dir() {
    local source_dir=$1
    local target_dir=$2
    local name=$3
    local used_symlink=true

    # Migrate from old whole-directory symlink to real directory with per-file symlinks
    if [ -L "$target_dir" ]; then
        echo -e "${YELLOW}  ⚠️  Migrating from directory symlink to per-file symlinks: $name${NC}"
        rm -f "$target_dir"
    fi

    mkdir -p "$target_dir"

    for source_file in "$source_dir"/*; do
        [ -e "$source_file" ] || continue
        local filename
        filename=$(basename "$source_file")
        local target_file="$target_dir/$filename"

        # Skip if already a correct symlink
        if [ -L "$target_file" ] && [ "$(readlink "$target_file")" = "$source_file" ]; then
            continue
        fi

        # Remove existing (symlink or file) — explicit if to avoid || vs && precedence trap
        if [ -e "$target_file" ] || [ -L "$target_file" ]; then rm -f "$target_file"; fi

        if ln -s "$source_file" "$target_file" 2>/dev/null; then
            : # symlink ok
        else
            cp "$source_file" "$target_file"
            used_symlink=false
        fi
    done

    if $used_symlink; then
        echo -e "${GREEN}  ✅ Symlinked files: $name${NC}"
        return 0
    else
        echo -e "${GREEN}  ✅ Copied files: $name${NC}"
        return 1
    fi
}

# Function: Install file symlink
install_file() {
    local source=$1
    local target=$2
    local name=$3

    # Skip if already a correct symlink
    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
        echo -e "${GREEN}  ✅ Already up-to-date: $name${NC}"
        return 0
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then rm -f "$target"; fi

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

# Install Claude Code Agents (per-file install to preserve custom agents)
echo "→ Claude Code Agents (.claude/agents/)"
mkdir -p "$PROJECT_DIR/.claude/agents"
if install_files_into_dir "$FRAMEWORK_DIR/adapters/claude-code-agents" "$PROJECT_DIR/.claude/agents" "Claude Code Agents"; then
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

# Install Claude Code Hooks (per-file install to preserve custom hooks)
echo "→ Claude Code Hooks (.claude/hooks/)"
mkdir -p "$PROJECT_DIR/.claude/hooks"
if install_files_into_dir "$FRAMEWORK_DIR/adapters/claude-code-hooks" "$PROJECT_DIR/.claude/hooks" "Claude Code Hooks"; then
    USED_SYMLINKS=true
else
    USED_COPY=true
fi

# Make ralph stop hook executable
RALPH_HOOK="$PROJECT_DIR/.claude/hooks/prp-ralph-stop.sh"
if [ -f "$RALPH_HOOK" ]; then
    chmod +x "$RALPH_HOOK"
    echo -e "${GREEN}  ✅ Made prp-ralph-stop.sh executable${NC}"
fi

# Register ralph stop hook in settings.local.json
echo "→ Registering Ralph stop hook in .claude/settings.local.json"
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.local.json"
HOOK_CMD=".claude/hooks/prp-ralph-stop.sh"

if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}  ⚠️  jq not found — add ralph hook manually to .claude/settings.local.json:${NC}"
    echo '     {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": ".claude/hooks/prp-ralph-stop.sh"}]}]}}'
else
    if [ -f "$SETTINGS_FILE" ]; then
        # Check if hook already registered
        EXISTING=$(jq -r '
            .hooks.Stop[]?.hooks[]?
            | select(.command == "'"$HOOK_CMD"'")
            | .command
        ' "$SETTINGS_FILE" 2>/dev/null)
        if [ -n "$EXISTING" ]; then
            echo -e "${GREEN}  ✅ Ralph stop hook already registered${NC}"
        else
            # Merge into existing settings
            TEMP_FILE=$(mktemp)
            jq --arg cmd "$HOOK_CMD" '
                .hooks.Stop = ((.hooks.Stop // []) + [
                    {"hooks": [{"type": "command", "command": $cmd}]}
                ])
            ' "$SETTINGS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$SETTINGS_FILE"
            echo -e "${GREEN}  ✅ Registered ralph stop hook in settings.local.json${NC}"
        fi
    else
        # Create new settings file
        jq -n --arg cmd "$HOOK_CMD" '{
            "hooks": {
                "Stop": [{"hooks": [{"type": "command", "command": $cmd}]}]
            }
        }' > "$SETTINGS_FILE"
        echo -e "${GREEN}  ✅ Created settings.local.json with ralph stop hook${NC}"
    fi
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

# Install Antigravity
echo "→ Antigravity (.agents/workflows/)"
mkdir -p "$PROJECT_DIR/.agents/workflows"
if install_directory "$FRAMEWORK_DIR/adapters/antigravity" "$PROJECT_DIR/.agents/workflows/prp" "Antigravity"; then
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
mkdir -p "$PROJECT_DIR/.prp-output"/{prds/drafts,designs,plans/completed,reports,reviews,debug,issues/completed,ralph-archives}
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
.agents/
AGENTS.md

# PRP Framework - artifacts (directory visible to AI tools, content not tracked)
# .prp-output/** is intentionally not ignored to allow AI tools to read/write artifacts, but we ignore all files within it to prevent tracking
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
echo "Available workflows (19 core commands):"
echo ""
echo "  Claude Code (/prp-core:*):"
printf "    %-14s %s\n" "Development:" "prd, design, plan, implement, commit, pr"
printf "    %-14s %s\n" "Review:" "review, review-fix, review-agents, feature-review, feature-review-agents"
printf "    %-14s %s\n" "Debug/Issue:" "debug, issue-investigate, issue-fix"
printf "    %-14s %s\n" "Automation:" "ralph, ralph-cancel, rollback, cleanup, run-all"
echo ""
echo "  Claude Code Marketing (/prp-mkt:*): landing, demo, pitch, competitor"
echo "  Claude Code Bot (/prp-bot:*): intent, flow, prompt-eng, voice-ux, integration"
echo ""
echo "  Other tools:"
printf "    %-14s %s\n" "Codex:" "\$prp-plan, \$prp-implement, \$prp-debug, \$prp-ralph, etc."
printf "    %-14s %s\n" "OpenCode:" "/prp:plan, /prp:implement, /prp:debug, /prp:ralph, etc."
printf "    %-14s %s\n" "Gemini:" "/prp:plan, /prp:implement, /prp:debug, /prp:ralph, etc."
printf "    %-14s %s\n" "Antigravity:" "/prp-plan, /prp-implement, /prp-debug, /prp-ralph, etc."
printf "    %-14s %s\n" "Kimi/Generic:" "Use natural language (see AGENTS.md)"
echo ""
echo "Documentation: $FRAMEWORK_DIR/docs/"
echo ""

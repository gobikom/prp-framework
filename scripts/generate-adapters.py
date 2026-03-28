#!/usr/bin/env python3
"""
PRP Adapter Auto-Generation Script

Generates all 5 adapter formats from prompts/ as single source of truth.
Uses adapters.yml config and prompts/overlays/ for tool-specific content.

Usage:
    python3 scripts/generate-adapters.py              # Generate all adapters
    python3 scripts/generate-adapters.py --dry-run     # Preview without writing
    python3 scripts/generate-adapters.py --diff        # Generate and show diff
    python3 scripts/generate-adapters.py --adapter X   # Generate only adapter X
"""

import argparse
import re
import sys
from pathlib import Path

import yaml


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
PROMPTS_DIR = ROOT_DIR / "prompts"
OVERLAYS_DIR = PROMPTS_DIR / "overlays"
ADAPTERS_DIR = ROOT_DIR / "adapters"
CONFIG_PATH = ROOT_DIR / "adapters.yml"

# Required top-level keys in adapters.yml
REQUIRED_CONFIG_KEYS = {"adapters", "commands"}
REQUIRED_ADAPTER_KEYS = {"file_pattern", "format", "args_placeholder",
                         "tool_command_template", "artifact_suffix"}
REQUIRED_COMMAND_KEYS = {"description"}


# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

def load_config() -> dict:
    """Load and validate adapters.yml config."""
    if not CONFIG_PATH.exists():
        print(f"Error: Config file not found: {CONFIG_PATH}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(CONFIG_PATH) as f:
            config = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"Error: Invalid YAML in {CONFIG_PATH}: {e}", file=sys.stderr)
        sys.exit(1)

    # Validate top-level structure
    missing = REQUIRED_CONFIG_KEYS - set(config.keys())
    if missing:
        print(f"Error: Missing top-level keys in adapters.yml: {missing}", file=sys.stderr)
        sys.exit(1)

    # Validate adapter entries
    for name, cfg in config["adapters"].items():
        missing_keys = REQUIRED_ADAPTER_KEYS - set(cfg.keys())
        if missing_keys:
            print(f"Error: Adapter '{name}' missing keys: {missing_keys}", file=sys.stderr)
            sys.exit(1)

    # Validate command entries
    for name, cfg in config["commands"].items():
        missing_keys = REQUIRED_COMMAND_KEYS - set(cfg.keys())
        if missing_keys:
            print(f"Error: Command '{name}' missing keys: {missing_keys}", file=sys.stderr)
            sys.exit(1)

    return config


# ---------------------------------------------------------------------------
# Prompt reading
# ---------------------------------------------------------------------------

def read_prompt(name: str) -> str:
    """Read a canonical prompt file from prompts/."""
    path = PROMPTS_DIR / f"{name}.md"
    if not path.exists():
        return ""
    return path.read_text()


def read_overlay(adapter: str, name: str) -> dict | None:
    """Read an overlay file for a specific adapter and command.

    Overlay format:
    ---
    command: plan
    adapter: claude-code
    ---
    # objective
    ...content...

    # context
    ...content...

    # wrap_before
    ...content prepended before main body...

    # wrap_after
    ...content appended after main body...
    """
    path = OVERLAYS_DIR / adapter / f"{name}.md"
    if not path.exists():
        return None

    text = path.read_text()

    # Parse YAML frontmatter
    overlay = {}
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            try:
                meta = yaml.safe_load(parts[1])
                if meta:
                    overlay["meta"] = meta
            except yaml.YAMLError:
                pass
            text = parts[2].strip()

    # Parse sections: lines starting with "# section_name"
    sections = {}
    current_section = None
    current_lines = []

    for line in text.split("\n"):
        # Match section headers like "# objective" or "# context"
        m = re.match(r"^#\s+(\w+)\s*$", line)
        if m:
            if current_section:
                sections[current_section] = "\n".join(current_lines).strip()
            current_section = m.group(1)
            current_lines = []
        else:
            current_lines.append(line)

    if current_section:
        sections[current_section] = "\n".join(current_lines).strip()

    overlay["sections"] = sections
    return overlay


# ---------------------------------------------------------------------------
# Placeholder substitution
# ---------------------------------------------------------------------------

def substitute_placeholders(content: str, adapter_cfg: dict, cmd_name: str) -> str:
    """Replace {ARGS} and {TOOL}:cmd patterns with adapter-specific values."""

    args_placeholder = adapter_cfg["args_placeholder"]
    tool_template = adapter_cfg["tool_command_template"]
    artifact_suffix = adapter_cfg["artifact_suffix"]

    # Replace {ARGS} → adapter-specific placeholder
    content = content.replace("{ARGS}", args_placeholder)

    # Replace {TOOL}:command-name → adapter-specific command reference
    # Pattern: {TOOL}:word (where word is a command name like pr, plan, commit)
    def replace_tool_cmd(m):
        cmd = m.group(1)
        return tool_template.replace("{cmd}", cmd)

    content = re.sub(r"\{TOOL\}:(\S+)", replace_tool_cmd, content)

    # Replace standalone {TOOL} in artifact paths (e.g., -review-{TOOL}.md)
    content = content.replace("{TOOL}", artifact_suffix)

    return content


# ---------------------------------------------------------------------------
# YAML value quoting
# ---------------------------------------------------------------------------

def yaml_quote(value: str) -> str:
    """Quote a YAML value if it contains special characters."""
    if not value:
        return '""'
    # Characters that require quoting in YAML
    needs_quoting = any(c in value for c in ':#{}[]|>&*!?,\'"') or value.startswith(("-", " "))
    if needs_quoting:
        # Use double quotes, escaping any internal double quotes
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return value


# ---------------------------------------------------------------------------
# Frontmatter generation
# ---------------------------------------------------------------------------

def get_description(adapter_name: str, cmd_cfg: dict) -> str:
    """Get the description for a command, checking overrides first."""
    desc_overrides = cmd_cfg.get("description-overrides", {})
    desc_map = cmd_cfg.get("description", {})

    if adapter_name in desc_overrides:
        return desc_overrides[adapter_name]
    if adapter_name in desc_map:
        return desc_map[adapter_name]
    return desc_map.get("default", "")


def generate_frontmatter_md(adapter_name: str, cmd_name: str, cmd_cfg: dict,
                             adapter_cfg: dict) -> str:
    """Generate YAML frontmatter for Markdown adapters (non-codex)."""
    fields = adapter_cfg.get("frontmatter", {}).get("fields", [])
    if not fields:
        return ""

    lines = ["---"]
    desc = get_description(adapter_name, cmd_cfg)

    for field in fields:
        if field == "description":
            lines.append(f"description: {yaml_quote(desc)}")
        elif field == "argument-hint":
            hint = cmd_cfg.get("argument-hint", "")
            if hint:
                lines.append(f"argument-hint: {yaml_quote(hint)}")
        elif field == "name":
            lines.append(f"name: prp-{cmd_name}")
        elif field == "agent":
            agent = cmd_cfg.get("opencode-agent", "plan")
            lines.append(f"agent: {agent}")

    lines.append("---")
    return "\n".join(lines)


def generate_codex_frontmatter(cmd_name: str, cmd_cfg: dict, adapter_cfg: dict) -> str:
    """Generate Codex-specific frontmatter with metadata block."""
    desc = get_description("codex", cmd_cfg)
    short = cmd_cfg.get("codex-short-description", cmd_name)

    lines = [
        "---",
        f"name: prp-{cmd_name}",
        f"description: {yaml_quote(desc)}",
        "metadata:",
        f"  short-description: {yaml_quote(short)}",
        "---",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Alias content generation
# ---------------------------------------------------------------------------

def generate_alias_content(cmd_name: str, cmd_cfg: dict, adapter_name: str) -> str:
    """Generate content for alias commands."""
    alias_of = cmd_cfg.get("alias-of", "")
    desc = get_description(adapter_name, cmd_cfg)

    return f"""This is an alias for `prp-{alias_of}`.

{desc}

See `prp-{alias_of}` for the full command documentation. The `prp-{alias_of}` command already includes all review passes and provides equivalent quality to running separate specialized agents.
"""


# ---------------------------------------------------------------------------
# XML wrapping (Claude Code)
# ---------------------------------------------------------------------------

def apply_skip_before(content: str, skip_marker: str) -> str:
    """Remove content before a marker line (e.g., '## Phase 0').

    Used when an overlay restructures the prompt header into XML sections.
    The marker line itself is included in the output.
    """
    idx = content.find(skip_marker)
    if idx == -1:
        return content
    return content[idx:]


def wrap_with_xml(content: str, overlay: dict | None) -> str:
    """Wrap content with XML tags for Claude Code adapter."""
    sections = overlay.get("sections", {}) if overlay else {}
    meta = overlay.get("meta", {}) if overlay else {}

    # Apply skip_before if specified in overlay metadata
    skip_before = meta.get("skip_before")
    if skip_before:
        content = apply_skip_before(content, skip_before)

    parts = []

    # <objective> from overlay
    if "objective" in sections:
        parts.append(f"<objective>\n{sections['objective']}\n</objective>")

    # <context> from overlay
    if "context" in sections:
        parts.append(f"<context>\n{sections['context']}\n</context>")

    # <process> wraps the main content
    body = content
    if "wrap_before" in sections:
        body = sections["wrap_before"] + "\n\n" + body
    if "wrap_after" in sections:
        body = body + "\n\n" + sections["wrap_after"]

    parts.append(f"<process>\n\n{body}\n</process>")

    # Any additional sections from overlay (output, verification, etc.)
    for key in ["output", "verification", "success_criteria"]:
        if key in sections:
            parts.append(f"<{key}>\n{sections[key]}\n</{key}>")

    return "\n\n".join(parts)


# ---------------------------------------------------------------------------
# TOML generation (Gemini)
# ---------------------------------------------------------------------------

def toml_escape_string(value: str) -> str:
    """Escape a string for use in a TOML basic string (double-quoted)."""
    return value.replace("\\", "\\\\").replace('"', '\\"')


def generate_toml_content(description: str, prompt_body: str) -> str:
    """Generate TOML file content for Gemini adapter."""
    safe_desc = toml_escape_string(description)
    # In TOML multi-line basic strings ("""), backslashes must be escaped
    safe_body = prompt_body.replace("\\", "\\\\")
    # Escape triple quotes in content if present
    safe_body = safe_body.replace('"""', '\\"\\"\\"')

    return f'description = "{safe_desc}"\nprompt = """\n{safe_body}\n"""\n'


# ---------------------------------------------------------------------------
# Path safety
# ---------------------------------------------------------------------------

def validate_output_path(out_path: Path, adapter_dir: Path) -> bool:
    """Ensure output path is inside the adapter directory (prevent path traversal)."""
    try:
        out_path.resolve().relative_to(adapter_dir.resolve())
        return True
    except ValueError:
        return False


# ---------------------------------------------------------------------------
# Core generation
# ---------------------------------------------------------------------------

def generate_adapter_file(adapter_name: str, cmd_name: str, config: dict) -> tuple[str, str]:
    """Generate a single adapter file. Returns (relative_path, content)."""
    adapter_cfg = config["adapters"][adapter_name]
    cmd_cfg = config["commands"][cmd_name]

    is_alias = cmd_cfg.get("alias", False)

    # Determine output path
    file_pattern = adapter_cfg["file_pattern"]
    rel_path = file_pattern.replace("{name}", cmd_name)

    # Read base prompt (or generate alias content)
    if is_alias:
        body = generate_alias_content(cmd_name, cmd_cfg, adapter_name)
    else:
        body = read_prompt(cmd_name)
        if not body:
            print(f"  WARNING: No prompt file for {cmd_name}", file=sys.stderr)
            return rel_path, ""

    # Apply placeholder substitutions
    body = substitute_placeholders(body, adapter_cfg, cmd_name)

    # Get description
    desc = get_description(adapter_name, cmd_cfg)

    # Format-specific output
    fmt = adapter_cfg.get("format", "md")

    if fmt == "toml":
        content = generate_toml_content(desc, body)
    else:
        # Markdown format — build frontmatter + body
        if adapter_name == "codex":
            frontmatter = generate_codex_frontmatter(cmd_name, cmd_cfg, adapter_cfg)
        else:
            frontmatter = generate_frontmatter_md(adapter_name, cmd_name, cmd_cfg, adapter_cfg)

        # Check for overlay (currently only claude-code)
        overlay = None
        if adapter_cfg.get("overlays"):
            overlay = read_overlay(adapter_name, cmd_name)

        # XML wrapping for claude-code
        if adapter_cfg.get("wrapper") == "xml" and not is_alias:
            if overlay:
                body = wrap_with_xml(body, overlay)
            else:
                body = f"<process>\n{body}\n</process>"

        content = frontmatter + "\n" + body if frontmatter else body

        # Ensure trailing newline
        if not content.endswith("\n"):
            content += "\n"

    return rel_path, content


def generate_all(config: dict, adapter_filter: str | None = None,
                 dry_run: bool = False, show_diff: bool = False) -> dict[str, int]:
    """Generate all adapter files. Returns stats."""
    stats = {"generated": 0, "skipped": 0, "errors": 0, "unchanged": 0}

    adapters_to_gen = (
        {adapter_filter: config["adapters"][adapter_filter]}
        if adapter_filter
        else config["adapters"]
    )

    commands = config["commands"]

    for adapter_name, adapter_cfg in adapters_to_gen.items():
        adapter_dir = ADAPTERS_DIR / adapter_name

        print(f"\n{'='*60}")
        print(f"Adapter: {adapter_name}")
        print(f"{'='*60}")

        for cmd_name in commands:
            rel_path, content = generate_adapter_file(adapter_name, cmd_name, config)

            if not content:
                stats["skipped"] += 1
                continue

            out_path = adapter_dir / rel_path

            # Path traversal check
            if not validate_output_path(out_path, adapter_dir):
                print(f"  ERROR: Path traversal detected: {out_path}", file=sys.stderr)
                stats["errors"] += 1
                continue

            if dry_run:
                print(f"  [DRY RUN] Would write: {out_path}")
                stats["generated"] += 1
                continue

            # Check if content changed
            if out_path.exists():
                existing = out_path.read_text()
                if existing == content:
                    stats["unchanged"] += 1
                    continue

                if show_diff:
                    print(f"  [CHANGED] {out_path}")
            else:
                if show_diff:
                    print(f"  [NEW] {out_path}")

            # Ensure parent directory exists (for codex prp-{name}/ dirs)
            out_path.parent.mkdir(parents=True, exist_ok=True)

            try:
                out_path.write_text(content)
                stats["generated"] += 1
            except OSError as e:
                print(f"  ERROR: Failed to write {out_path}: {e}", file=sys.stderr)
                stats["errors"] += 1

    return stats


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate PRP adapter files from canonical prompts"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Preview what would be generated without writing files"
    )
    parser.add_argument(
        "--diff", action="store_true",
        help="Show which files would change"
    )
    parser.add_argument(
        "--adapter", type=str, default=None,
        help="Generate only this adapter (e.g., 'gemini')"
    )
    args = parser.parse_args()

    config = load_config()

    if args.adapter and args.adapter not in config["adapters"]:
        print(f"Error: Unknown adapter '{args.adapter}'", file=sys.stderr)
        print(f"Available: {', '.join(config['adapters'].keys())}", file=sys.stderr)
        sys.exit(1)

    stats = generate_all(
        config,
        adapter_filter=args.adapter,
        dry_run=args.dry_run,
        show_diff=args.diff or args.dry_run,
    )

    print(f"\n{'='*60}")
    print(f"Results: {stats['generated']} generated, {stats['unchanged']} unchanged, "
          f"{stats['skipped']} skipped, {stats['errors']} errors")
    print(f"{'='*60}")

    if args.dry_run:
        print("\nDry run complete. No files were written.")

    return 0 if stats["errors"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

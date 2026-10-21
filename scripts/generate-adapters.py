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
import os
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

# Round-3 re-plan: adapter and command names are used to build filesystem
# paths (file_pattern .replace("{name}", ...)), so they are validated up
# front. This rejects absolute keys (/etc/passwd), traversal (../x), empty,
# uppercase and spaced names with a named load-time error.
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def display_path(p) -> str:
    """Round-3 re-plan: one helper for every user-facing path in a message.

    relative_to(ROOT_DIR) as a str when the path is inside the tree, str(p)
    otherwise (an absolute outside path raised ValueError from messages
    before — the round-3 Critical). Never raises for a bad path.
    """
    try:
        return str(p.relative_to(ROOT_DIR))
    except ValueError:
        return str(p)


class GenerationError(Exception):
    """An input the generator failed to read or parse (split_frontmatter
    raises it; #157's read_prompt / read_overlay / validate_generated adopt
    it, and its per-command boundary catches it)."""


def read_utf8(path, optional: bool = False):
    """The ONLY filesystem access in this script (#161 round-3 re-plan).

    Any OSError or UnicodeDecodeError becomes a GenerationError naming the
    file and the exception type, so no read can end in a traceback or a
    silent exit 0. Callers count it (generate_all) or exit 1 (load_config).
    optional=True returns None for a file that is absent, or whose parent is
    not a directory (no stat() beside
    the read: Path.exists() raises PermissionError); a dangling symlink is
    an error, not an absent file.
    """
    try:
        return Path(path).read_text(encoding="utf-8")
    except (FileNotFoundError, NotADirectoryError) as e:
        if optional and not os.path.islink(path):
            return None
        raise GenerationError(
            f"error: Cannot read {display_path(path)}: {type(e).__name__}: {e}")
    except (OSError, UnicodeDecodeError) as e:
        raise GenerationError(
            f"error: Cannot read {display_path(path)}: {type(e).__name__}: {e}")


# Required top-level keys in adapters.yml
REQUIRED_CONFIG_KEYS = {"adapters", "commands"}
REQUIRED_ADAPTER_KEYS = {"file_pattern", "format", "args_placeholder",
                         "tool_command_template", "artifact_suffix"}
# Known-key validation (re-routed from prp-framework#156 as PR A, generator
# correctness): a typo'd adapters.yml adapter key previously passed silently
# and its value was dropped at substitution time — generating output from a
# config the generator did not fully understand while exiting 0. Unknown keys
# now fail generation with a clear error naming the key and listing the valid
# ones. (The agent_blocking_* keys join this set in the stacked PR B; listing
# them here would validate keys no stanza on main carries.)
KNOWN_ADAPTER_KEYS = {"file_pattern", "format", "args_placeholder",
                      "tool_command_template", "artifact_suffix",
                      "frontmatter", "group_dirs", "overlays", "wrapper"}
REQUIRED_COMMAND_KEYS = {"description"}
# Every key a command stanza may carry: the six adapters.yml uses today plus
# alias / alias-of, which generate_adapter_file reads (no command uses them yet).
KNOWN_COMMAND_KEYS = {"description", "description-overrides", "argument-hint",
                      "codex-short-description", "opencode-agent", "group",
                      "alias", "alias-of"}


# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------

def load_config() -> dict:
    """Load and validate adapters.yml config."""
    try:
        text = read_utf8(CONFIG_PATH, optional=True)
        if text is None:
            print(f"Error: Config file not found: {CONFIG_PATH}", file=sys.stderr)
            sys.exit(1)
        config = yaml.safe_load(text)
    except (yaml.YAMLError, ValueError) as e:
        print(f"Error: Invalid YAML in {CONFIG_PATH}: {e}", file=sys.stderr)
        sys.exit(1)
    except GenerationError as e:
        # read_utf8 names the file and the exception type; the config is
        # fatal (exit 1) — nothing else can run without it.
        print(f"Error: {str(e).removeprefix('error: ')}", file=sys.stderr)
        sys.exit(1)

    # Validate top-level structure (a non-mapping adapters.yml — list,
    # scalar, null — previously died as an AttributeError traceback; round-6
    # input table: every input read gets a named error)
    if not isinstance(config, dict):
        print(f"Error: adapters.yml must be a mapping, got "
              f"{type(config).__name__}", file=sys.stderr)
        sys.exit(1)
    missing = REQUIRED_CONFIG_KEYS - set(config.keys())
    if missing:
        print(f"Error: Missing top-level keys in adapters.yml: {missing}", file=sys.stderr)
        sys.exit(1)
    for section in ("adapters", "commands"):
        if not isinstance(config[section], dict):
            print(f"Error: adapters.yml '{section}' must be a mapping, got "
                  f"{type(config[section]).__name__}", file=sys.stderr)
            sys.exit(1)
        for name, cfg in config[section].items():
            if not isinstance(cfg, dict):
                print(f"Error: adapters.yml {section}['{name}'] must be a "
                      f"mapping, got {type(cfg).__name__}", file=sys.stderr)
                sys.exit(1)

    # Round-3 re-plan: names are validated before any work — they build
    # filesystem paths, so /etc/passwd, ../x, empty, uppercase and spaced
    # names are load-time errors (this was the round-3 Critical: an absolute
    # command key later raised ValueError from the path-shrinking helper
    # inside an f-string and crashed the run with a raw traceback).
    for section in ("adapters", "commands"):
        for name in config[section]:
            if not isinstance(name, str) or not NAME_RE.match(name):
                print(f"Error: invalid {section[:-1]} name {name!r} in adapters.yml — "
                      f"must match ^[a-z0-9][a-z0-9-]*$ "
                      f"(lowercase alphanumerics and hyphens, no slashes)", file=sys.stderr)
                sys.exit(1)

    # Round-3 re-plan: type-check the value of every required and known key
    # (the types adapters.yml documents). A wrong-typed value (null, int,
    # list where str/mapping/bool is documented) previously surfaced as a
    # TypeError far from the config, or crashed mid-run (round-3 Important:
    # args_placeholder: null → TypeError in substitute_placeholders).
    # Config-level errors stay fatal: named, exit 1, before any work.
    ADAPTER_VALUE_TYPES = {
        "file_pattern": str, "format": str, "args_placeholder": str,
        "tool_command_template": str, "artifact_suffix": str,
        "frontmatter": dict, "group_dirs": dict, "overlays": bool,
        "wrapper": str,
    }
    COMMAND_VALUE_TYPES = {
        "description": dict, "description-overrides": dict,
        "argument-hint": str, "codex-short-description": str,
        "group": str, "opencode-agent": str,
    }

    def check_value_types(section: str, name: str, cfg: dict, types: dict) -> None:
        # Checks only the keys whose documented type is known; keys the
        # generator does not read (e.g. alias / alias-of on commands) are
        # skipped. bool is a subclass of int but of no other checked type,
        # so a plain isinstance test already rejects true/false for str.
        for key, value in cfg.items():
            want = types.get(key)
            if want is None:
                continue
            if not isinstance(value, want):
                print(f"Error: adapters.yml {section} '{name}' key '{key}' must be "
                      f"{want.__name__}, got {type(value).__name__}", file=sys.stderr)
                sys.exit(1)
        # nested shape: frontmatter.fields is a list of str
        if isinstance(cfg.get("frontmatter"), dict):
            fields = cfg["frontmatter"].get("fields")
            if fields is not None and (
                    not isinstance(fields, list)
                    or not all(isinstance(x, str) for x in fields)):
                print(f"Error: adapters.yml {section} '{name}' key 'frontmatter.fields' "
                      f"must be a list of strings", file=sys.stderr)
                sys.exit(1)

    # Validate adapter entries
    for name, cfg in config["adapters"].items():
        missing_keys = REQUIRED_ADAPTER_KEYS - set(cfg.keys())
        if missing_keys:
            print(f"Error: Adapter '{name}' missing keys: {missing_keys}", file=sys.stderr)
            sys.exit(1)
        unknown_keys = set(cfg.keys()) - KNOWN_ADAPTER_KEYS
        if unknown_keys:
            print(f"Error: Adapter '{name}' has unknown keys: {sorted(unknown_keys)}",
                  file=sys.stderr)
            print("Error: Check adapters.yml for typos — valid keys: "
                  f"{sorted(KNOWN_ADAPTER_KEYS)}", file=sys.stderr)
            sys.exit(1)
        check_value_types("adapter", name, cfg, ADAPTER_VALUE_TYPES)

    # Validate command entries
    for name, cfg in config["commands"].items():
        missing_keys = REQUIRED_COMMAND_KEYS - set(cfg.keys())
        if missing_keys:
            print(f"Error: Command '{name}' missing keys: {missing_keys}", file=sys.stderr)
            sys.exit(1)
        unknown_keys = set(cfg.keys()) - KNOWN_COMMAND_KEYS
        if unknown_keys:
            print(f"Error: Command '{name}' has unknown keys: {sorted(unknown_keys)}",
                  file=sys.stderr)
            print("Error: Check adapters.yml for typos — valid keys: "
                  f"{sorted(KNOWN_COMMAND_KEYS)}", file=sys.stderr)
            sys.exit(1)
        check_value_types("command", name, cfg, COMMAND_VALUE_TYPES)

    return config


# ---------------------------------------------------------------------------
# Prompt reading
# ---------------------------------------------------------------------------

def split_frontmatter(text: str, source: str) -> tuple[str | None, str]:
    """The ONLY frontmatter splitter, used by read_overlay() and
    validate_generated() (#156 round-8 re-plan, re-routed as PR A; the two
    inline splits are deleted).

    1. normalizes line endings first (\\r\\n and lone \\r become \\n);
    2. a delimiter is a line whose content, after stripping trailing spaces
       and tabs, is exactly `---`;
    3. returns (None, whole_text) only if the first line is not a delimiter;
    4. if the first line IS a delimiter and no closing delimiter follows,
       raises GenerationError naming `source` ("unterminated frontmatter");
    5. NEVER falls back to treating the whole text as the body — the
       round-7/8 bugs both lived in that fallback (a mis-split left a
       non-empty "body" that passed validation);
    6. a line that becomes `---` only after stripping LEADING whitespace too
       is a near-miss delimiter (the round-9 fix, from the #156 re-route):
       wherever it appears in the frontmatter region — as the opening line
       or as a would-be closing line before a valid closer — it raises
       GenerationError ("indented frontmatter delimiter") naming the file
       and the line. An indented opening `---` previously parsed as "no
       frontmatter", so the overlay metadata was dropped and generation
       exited 0. After a VALID closing delimiter the body is body: an
       indented `---` (e.g. inside a fenced block) is never inspected.

    Returns (frontmatter_text_or_None, body_after_closing_delimiter).
    """
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")

    def is_delimiter(line: str) -> bool:
        return line.rstrip(" \t") == "---"

    def is_indented_delimiter(line: str) -> bool:
        # `  ---` / `\t---` (with optional trailing spaces/tabs): the line is
        # `---` once ALL surrounding whitespace is stripped, but it carries
        # leading whitespace, so it is NOT a delimiter — it is a near miss.
        return line[:1].isspace() and line.strip(" \t") == "---"

    def indented_error(source: str, lineno: int) -> GenerationError:
        return GenerationError(
            f"error: indented frontmatter delimiter in {source} at line "
            f"{lineno} — a `---` with leading whitespace is not a delimiter; "
            f"delimiters must start at column 1")

    if not lines:
        return None, normalized
    if is_indented_delimiter(lines[0]):
        # An indented opening `---` was previously read as "no frontmatter"
        # and the whole overlay metadata silently dropped (round 9).
        raise indented_error(source, 1)
    if not is_delimiter(lines[0]):
        return None, normalized

    for i in range(1, len(lines)):
        if is_delimiter(lines[i]):
            fm = "\n".join(lines[1:i])
            body = "\n".join(lines[i + 1:])
            return fm, body
        if is_indented_delimiter(lines[i]):
            # A would-be closing delimiter that is indented is a near miss,
            # not body text: raise naming the file and the line (round 9).
            raise indented_error(source, i + 1)

    raise GenerationError(
        f"error: unterminated frontmatter in {source} — opening `---` "
        f"without a closing `---` line")


def read_prompt(name: str) -> str:
    """Read a canonical prompt file from prompts/."""
    return read_utf8(PROMPTS_DIR / f"{name}.md")


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
    text = read_utf8(path, optional=True)
    if text is None:
        return None

    # Parse YAML frontmatter through the ONE splitter, split_frontmatter.
    # A malformed region (parse error or invalid YAML) is a GenerationError
    # the per-command loop counts: no lenient fallback, so no raw frontmatter
    # text can reach an output.
    overlay = {}
    fm, body = split_frontmatter(text, display_path(path))
    if fm is not None:
        try:
            meta = yaml.safe_load(fm)
        except (yaml.YAMLError, ValueError) as e:
            raise GenerationError(
                f"error: invalid overlay frontmatter YAML in "
                f"{display_path(path)}: {e}")
        if meta is not None and not isinstance(meta, dict):
            raise GenerationError(
                f"error: overlay frontmatter in {display_path(path)} must be "
                f"a mapping, got {type(meta).__name__}")
        if meta and not isinstance(meta.get("skip_before", ""), str):
            raise GenerationError(
                f"error: overlay frontmatter 'skip_before' in "
                f"{display_path(path)} must be a string")
        if meta:
            overlay["meta"] = meta
        text = body.strip()

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
        if adapter_name in ("codex", "thclaws"):
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


def generate_unit(adapter_name: str, cmd_name: str, config: dict, ctx: dict,
                  dry_run: bool, show_diff: bool) -> str:
    """One (adapter, command) unit; returns the stats key. Raises on failure
    (generate_all counts it); ctx["path"] is the last file touched."""
    adapter_cfg = config["adapters"][adapter_name]
    cmd_cfg = config["commands"][cmd_name]
    ctx["path"] = display_path(PROMPTS_DIR / f"{cmd_name}.md")
    rel_path, content = generate_adapter_file(adapter_name, cmd_name, config)
    if not content:
        return "skipped"

    # Determine output directory (may differ for grouped commands)
    cmd_group = cmd_cfg.get("group")
    group_dirs = adapter_cfg.get("group_dirs", {})
    if cmd_group and cmd_group in group_dirs:
        adapter_dir = ADAPTERS_DIR / group_dirs[cmd_group]
    else:
        adapter_dir = ADAPTERS_DIR / adapter_name

    out_path = adapter_dir / rel_path
    ctx["path"] = display_path(out_path)

    # Path traversal check
    if not validate_output_path(out_path, adapter_dir):
        raise GenerationError(
            f"error: Path traversal detected: {display_path(out_path)}")

    if dry_run:
        print(f"  [DRY RUN] Would write: {out_path}")
        return "generated"

    existing = read_utf8(out_path, optional=True)
    if existing is None:
        if show_diff:
            print(f"  [NEW] {out_path}")
    else:
        if existing == content:
            return "unchanged"
        if show_diff:
            print(f"  [CHANGED] {out_path}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    # encode BEFORE opening: a lone surrogate must not truncate the output
    out_path.write_bytes(content.encode("utf-8"))
    return "generated"


def generate_all(config: dict, adapter_filter: str | None = None,
                 dry_run: bool = False, show_diff: bool = False) -> dict[str, int]:
    """Generate all adapter files. Returns stats. The per-unit boundary:
    no exception leaves as a traceback; each is ONE counted error."""
    stats = {"generated": 0, "skipped": 0, "errors": 0, "unchanged": 0}

    adapters_to_gen = (
        {adapter_filter: config["adapters"][adapter_filter]}
        if adapter_filter
        else config["adapters"]
    )

    for adapter_name in adapters_to_gen:
        print(f"\n{'='*60}")
        print(f"Adapter: {adapter_name}")
        print(f"{'='*60}")

        for cmd_name in config["commands"]:
            ctx = {"path": ""}
            try:
                stats[generate_unit(adapter_name, cmd_name, config, ctx,
                                    dry_run, show_diff)] += 1
            except Exception as e:  # boundary 1 of 2 (see grep invariant test)
                if isinstance(e, GenerationError):
                    print(f"  {e}", file=sys.stderr)
                else:
                    print(f"  error: {adapter_name}/{cmd_name} "
                          f"({ctx['path']}): {type(e).__name__}: {e}",
                          file=sys.stderr)
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

    phase = {"input": display_path(CONFIG_PATH)}
    try:
        return run(args, phase)
    except Exception as e:  # boundary 2 of 2 (see grep invariant test)
        print(f"Error: {phase['input']}: {type(e).__name__}: {e}",
              file=sys.stderr)
        return 1


def run(args, phase: dict) -> int:
    config = load_config()
    phase["input"] = "generation"

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

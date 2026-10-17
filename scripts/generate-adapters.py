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
# prp-framework#156 round-1 fix 3: known-key validation. A typo'd adapter key
# (e.g. agent_blocking_prase_claude) previously passed silently and its value
# was dropped at substitution time — generating prose that no longer matched
# the dispatch blocks. Unknown keys now fail generation with a clear error.
KNOWN_ADAPTER_KEYS = {"file_pattern", "format", "args_placeholder",
                      "tool_command_template", "artifact_suffix",
                      "frontmatter", "group_dirs", "overlays", "wrapper",
                      "agent_blocking_param", "agent_blocking_prose_claude"}
# agent_blocking_prose_other is NOT an adapter-stanza key: it is a single
# shared TOP-LEVEL value (round-2 re-plan). Its round-1 placement inside the
# claude-code stanza was never read for the other five adapters — a stanza
# placement now fails known-key validation.
REQUIRED_COMMAND_KEYS = {"description"}

# prp-framework#156 round-2 re-plan: generation-time placeholders are a CLOSED
# registry in one reserved namespace. Every brace token whose name starts with
# AGENT_ — underscore included, case-insensitive — is a generation-time
# placeholder: regex {agent_[a-z0-9_]*} with re.I. The prose token {agent}
# ("still waiting on {agent}") has no underscore, sits OUTSIDE the namespace,
# and must keep generating unchanged. Runtime placeholders ({NUMBER}, {N},
# {CONTEXT_PATH}, …) never use the prefix and are unaffected. A namespace
# token that is not registered (checked BEFORE substitution, in the prompt) or
# any namespace token left in the output (checked AFTER substitution) is a
# hard error naming the token and the file.
GEN_PLACEHOLDERS = {"AGENT_BLOCKING_PARAM", "AGENT_BLOCKING_PROSE"}
NAMESPACE_RE = re.compile(r"\{agent_[a-z0-9_]*\}", re.IGNORECASE)


class GenerationError(Exception):
    """An input the generator failed to read or parse (round-4 widened
    invariant: the generator never exits 0 on output it could not build
    correctly — every such failure is an error counted in stats["errors"],
    never a silent skip). generate_all() catches one per command, counts it,
    and continues, so a single run reports every broken input; main() exits 1
    when any error was counted."""


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
    """Read a canonical prompt file from prompts/.

    Raises SystemExit naming the file when the prompt for a configured
    command is missing or unreadable (round-4 Important): a missing prompt
    previously counted as a silent "skipped" and generation exited 0.
    """
    path = PROMPTS_DIR / f"{name}.md"
    if not path.exists():
        raise GenerationError(
            f"error: prompt file for configured command '{name}' is missing: "
            f"{path.relative_to(ROOT_DIR)}")
    try:
        text = path.read_text()
    except OSError as e:
        raise GenerationError(
            f"error: cannot read prompt for configured command '{name}': "
            f"{path.relative_to(ROOT_DIR)}: {e}")
    if not text.strip():
        # Round-6 Important A: an empty or whitespace-only prompt previously
        # shipped an empty command body and exited 0.
        raise GenerationError(
            f"error: prompt file for configured command '{name}' is empty "
            f"or whitespace-only: {path.relative_to(ROOT_DIR)}")
    return text


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

    try:
        text = path.read_text()
    except OSError as e:
        raise GenerationError(
            f"error: cannot read overlay {path.relative_to(ROOT_DIR)}: {e}")

    # Parse YAML frontmatter. A broken frontmatter is a hard error naming the
    # overlay file and the YAML error (round-4 Critical): swallowing it here
    # let wrap_with_xml() build malformed content and generation exit 0.
    overlay = {}
    if text.startswith("---"):
        # Round-7 fix: split only on lines exactly `---` — the old
        # text.split("---", 2) matched "---" inside frontmatter values
        # (e.g. command: "pre---post") and mis-parsed the overlay.
        parts = re.split(r"(?m)^---$", text, maxsplit=2)
        if len(parts) >= 3:
            try:
                meta = yaml.safe_load(parts[1])
                if meta is not None and not isinstance(meta, dict):
                    raise GenerationError(
                        f"error: overlay frontmatter must be a mapping, got "
                        f"{type(meta).__name__}: "
                        f"{path.relative_to(ROOT_DIR)}")
                if meta:
                    overlay["meta"] = meta
            except yaml.YAMLError as e:
                raise GenerationError(
                    f"error: invalid YAML frontmatter in overlay "
                    f"{path.relative_to(ROOT_DIR)}: {e}")
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

def substitute_placeholders(content: str, adapter_cfg: dict, cmd_name: str,
                            config: dict) -> str:
    """Replace {ARGS} and {TOOL}:cmd patterns with adapter-specific values."""

    # BEFORE substitution: every reserved-namespace token in the prompt must be
    # registered in GEN_PLACEHOLDERS. A suffix typo ({AGENT_BLOCKING_PARAMM}),
    # a case variant ({agent_blocking_param}) or an unknown name ({AGENT_FOO})
    # all die here, with the token and the prompt file named.
    prompt_file = f"prompts/{cmd_name}.md"
    for m in NAMESPACE_RE.finditer(content):
        name = m.group(0)[1:-1]
        if name not in GEN_PLACEHOLDERS:
            raise GenerationError(
                f"error: unknown generation placeholder '{m.group(0)}' in "
                f"{prompt_file} — registered placeholders: "
                f"{sorted(GEN_PLACEHOLDERS)}")

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

    # {AGENT_BLOCKING_PARAM} → adapter-specific blocking parameter line, or ""
    # for runtimes whose Agent tool has no such parameter (they must not
    # receive a Claude-Code-only kwarg their tool would reject; absence of the
    # key IS the per-runtime mapping — only claude-code sets it).
    # prp-framework#151 AC1: claude-code maps it to run_in_background=false.
    blocking_param = adapter_cfg.get("agent_blocking_param")
    content = content.replace("{AGENT_BLOCKING_PARAM}", blocking_param or "")

    # {AGENT_BLOCKING_PROSE} → the scoped claim for the adapter that carries
    # the parameter, the shared neutral sentence for every other runtime —
    # keeps the "Blocking wait" bullet TRUE in every adapter.
    # prp-framework#156 round-2 re-plan: BOTH values come from adapters.yml and
    # the generator holds no prose text — the claim from the adapter stanza,
    # the neutral sentence from ONE top-level key shared by all runtimes
    # without the parameter. A missing value is an error naming the key.
    if "{AGENT_BLOCKING_PROSE}" in content:
        if blocking_param:
            prose_key = "agent_blocking_prose_claude"
            prose = adapter_cfg.get(prose_key)
        else:
            prose_key = "agent_blocking_prose_other"
            prose = config.get(prose_key)
        if not prose:
            raise GenerationError(
                f"error: adapters.yml key '{prose_key}' is missing or empty — "
                f"required to substitute {{AGENT_BLOCKING_PROSE}} for "
                f"'{cmd_name}'")
        content = content.replace("{AGENT_BLOCKING_PROSE}", prose)

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


def validate_generated(rel_path: str, content: str) -> None:
    """Round-6 output check: the generator exits 0 only if EVERY file it
    writes or would write passes. Runs on every adapter and command —
    aliases included — and in --dry-run/--diff modes too (it is called
    before the dry-run fork, so it sees identical content). Raises
    GenerationError naming the file and the reason:
      (a) the command body, after frontmatter or TOML header, is non-empty
          after strip;
      (b) the description field, where the format has one, is non-empty;
      (c) no {agent_*} namespace token remains.
    """
    where = f"generated output {rel_path}"

    # (c) first — a namespace token anywhere is a substitution bug.
    left = NAMESPACE_RE.search(content)
    if left:
        raise GenerationError(
            f"error: reserved placeholder '{left.group(0)}' left in "
            f"{where} — check adapters.yml agent_blocking_* values for "
            f"self-referential placeholders")

    fmt_md = not rel_path.endswith(".toml")

    if fmt_md:
        # Markdown: strip YAML frontmatter, then require a non-empty body.
        # Round-7 fix: split ONLY on lines that are exactly `---`
        # (re.split (?m)^---$ maxsplit=2) — the old body.split("---", 2)
        # matched "---" anywhere, e.g. inside description: "pre---post",
        # which silently mis-split frontmatter and body.
        body = content
        desc = ""
        if body.startswith("---"):
            parts = re.split(r"(?m)^---$", body, maxsplit=2)
            if len(parts) >= 3:
                desc = parts[1]
                body = parts[2]
        if not body.strip():
            raise GenerationError(
                f"error: {where} has an empty command body after frontmatter")
        # (b) a description FIELD exists (frontmatter carries one) but is empty
        if desc:
            m = re.search(r"^description:\s*(.*)$", desc, re.MULTILINE)
            if m and not m.group(1).strip().strip('\"').strip():
                raise GenerationError(
                    f"error: {where} has an empty description field")
    else:
        # TOML (gemini): description = "..." then prompt = """...""" — the
        # command body is the INTERIOR of the prompt block, not the leftover
        # TOML scaffolding around it.
        m = re.search(r'^description\s*=\s*"(.*)"', content, re.MULTILINE)
        desc = m.group(1) if m else ""
        if not desc.strip():
            raise GenerationError(
                f"error: {where} has an empty description field")
        m = re.search(r'prompt\s*=\s*"""(.*?)"""', content, re.DOTALL)
        body = m.group(1) if m else ""
        if not body.strip():
            raise GenerationError(
                f"error: {where} has an empty command body after TOML header")


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

    # Round-6 input table: alias-of must name a configured command
    if is_alias:
        alias_of = cmd_cfg.get("alias-of", "")
        if alias_of not in config["commands"]:
            raise GenerationError(
                f"error: command '{cmd_name}' is an alias of '{alias_of}', "
                f"which is not a configured command in adapters.yml")

    # Read base prompt (or generate alias content)
    if is_alias:
        body = generate_alias_content(cmd_name, cmd_cfg, adapter_name)
    else:
        # A missing or unreadable prompt for a configured command is an error
        # (read_prompt raises); there is no intentional-skip path here — every
        # configured command must have a prompt (or be an alias).
        body = read_prompt(cmd_name)

    # Apply placeholder substitutions
    body = substitute_placeholders(body, adapter_cfg, cmd_name, config)

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

    # AFTER substitution: no reserved-namespace token may survive into the
    # generated output — checked on the FINAL content (overlays and wrappers
    # included), so nothing can smuggle a namespace token out. This namespace
    # scan replaces the round-1 single-string `in` guard.
    left = NAMESPACE_RE.search(content)
    if left:
        raise GenerationError(
            f"error: reserved placeholder '{left.group(0)}' left in generated "
            f"output for {adapter_name}/{rel_path} — check adapters.yml "
            f"agent_blocking_* values for self-referential placeholders")

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
        default_adapter_dir = ADAPTERS_DIR / adapter_name
        group_dirs = adapter_cfg.get("group_dirs", {})

        print(f"\n{'='*60}")
        print(f"Adapter: {adapter_name}")
        print(f"{'='*60}")

        for cmd_name in commands:
            cmd_cfg = commands[cmd_name]
            try:
                rel_path, content = generate_adapter_file(adapter_name, cmd_name, config)
            except GenerationError as e:
                # widened invariant: an input we could not read/parse is an
                # error counted in stats["errors"] — printed and CONTINUED, so
                # one run reports every broken input; main() exits 1.
                print(f"  {e}", file=sys.stderr)
                stats["errors"] += 1
                continue

            if not content:
                stats["skipped"] += 1
                continue

            # Determine output directory (may differ for grouped commands)
            cmd_group = cmd_cfg.get("group")
            if cmd_group and cmd_group in group_dirs:
                adapter_dir = ADAPTERS_DIR / group_dirs[cmd_group]
            else:
                adapter_dir = default_adapter_dir

            out_path = adapter_dir / rel_path

            # Path traversal check
            if not validate_output_path(out_path, adapter_dir):
                print(f"  ERROR: Path traversal detected: {out_path}", file=sys.stderr)
                stats["errors"] += 1
                continue

            # Round-6 output check — every file the generator writes or would
            # write must pass validate_generated; runs BEFORE the dry-run fork
            # so --dry-run/--diff validate identical content, and it covers
            # the change-detection read below (content that would be written).
            try:
                validate_generated(f"{adapter_name}/{rel_path}", content)
            except GenerationError as e:
                print(f"  {e}", file=sys.stderr)
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

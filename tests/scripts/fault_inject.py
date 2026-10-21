#!/usr/bin/env python3
"""Fault-injection harness for generate-adapters.py (prp-framework#161).

Usage: fault_inject.py <tree> <class> <exception> [fresh]
Patches ONE failure class to raise <exception> for ONE target input, runs
main(), exits with its code (3 + "PROPAGATED" if KeyboardInterrupt/SystemExit
escapes). Classes: stat read yaml-config yaml-overlay overlay-type write surrogate
(surrogate = a "bad\\ud800" adapter beside a good one).
Unless "fresh"/"write", an unpatched run first populates adapters/; for "stat"
one output is then made stale so mkdir (is_dir -> Path.stat) runs.
"""
import contextlib
import importlib.util
import pathlib
import sys

import yaml

tree, klass, exc_name = sys.argv[1:4]
fresh = (len(sys.argv) > 4 and sys.argv[4] == "fresh") or klass in ("write", "surrogate")

EXCEPTIONS = {
    "OSError": lambda: OSError(5, "injected I/O error"),
    "UnicodeDecodeError": lambda: UnicodeDecodeError("utf-8", b"\xff", 0, 1, "injected"),
    "YAMLError": lambda: yaml.YAMLError("injected yaml error"),
    "TypeError": lambda: TypeError("injected type error"),
    "ValueError": lambda: ValueError("injected value error"),
    "KeyboardInterrupt": lambda: KeyboardInterrupt(),
}
make_exc = EXCEPTIONS[exc_name]

spec = importlib.util.spec_from_file_location(
    "generate_adapters", pathlib.Path(tree) / "scripts" / "generate-adapters.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)
PROMPT, OUT_DIR, OUT_FILE = "prompts/qa.md", "adapters/codex/prp-qa", "adapters/codex/prp-qa/SKILL.md"


def wrap_path_method(name, fragment):
    orig = getattr(pathlib.Path, name)

    def patched(self, *a, **kw):
        if str(self).endswith(fragment):
            raise make_exc()
        return orig(self, *a, **kw)
    setattr(pathlib.Path, name, patched)


def patch_yaml(marker, result=None):
    orig = yaml.safe_load

    def patched(stream, *a, **kw):
        if marker in str(stream):
            if result is not None:
                return result()
            raise make_exc()
        return orig(stream, *a, **kw)
    yaml.safe_load = patched


class BadMapping(dict):
    def get(self, *a, **kw):
        raise make_exc()


def apply_patch():
    if klass == "stat":
        wrap_path_method("stat", OUT_DIR)
    elif klass == "read":
        wrap_path_method("read_text", PROMPT)
    elif klass == "yaml-config":
        patch_yaml("adapters:")
    elif klass == "yaml-overlay":
        patch_yaml("command: plan")
    elif klass == "overlay-type":
        patch_yaml("command: plan", result=lambda: BadMapping(command="plan"))
    elif klass == "write":
        wrap_path_method("write_bytes", OUT_FILE)
    elif klass == "surrogate":
        orig = gen.load_config

        def load_config():
            cfg = orig()
            cfg["commands"] = {"qa": cfg["commands"]["qa"]}
            cfg["adapters"]["bad\ud800"] = dict(cfg["adapters"]["claude-code"])
            return cfg
        gen.load_config = load_config
    else:
        raise SystemExit(f"unknown class {klass}")


if not fresh:
    sys.argv = ["generate-adapters.py"]
    with open("/dev/null", "w") as null, contextlib.redirect_stdout(null), \
            contextlib.redirect_stderr(null):
        gen.main()

if klass == "stat":
    (pathlib.Path(tree) / OUT_FILE).write_text("stale\n")
apply_patch()
sys.argv = ["generate-adapters.py"]
try:
    sys.exit(gen.main())
except (KeyboardInterrupt, SystemExit) as e:
    if isinstance(e, SystemExit) and e.code in (0, 1, None):
        raise
    print(f"PROPAGATED {type(e).__name__}", file=sys.stderr)
    sys.exit(3)

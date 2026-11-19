#!/usr/bin/env python3
"""Materialize the generated Codex skills for the local PRP marketplace."""

import argparse
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MARKETPLACE = ROOT / "adapters" / "claude-code-plugin"
SKILLS = ROOT / "adapters" / "codex"
PLUGIN = "prp-core"
MANIFEST_PATH = Path(".codex-plugin/plugin.json")
CATALOG_PATH = Path(".agents/plugins/marketplace.json")
PACKAGE_PATH = Path(".agents/plugins/packages") / PLUGIN
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")


def catalog(name, version):
    return {
        "name": name,
        "plugins": [{
            "name": PLUGIN,
            "source": {"source": "local", "path": f"./{PACKAGE_PATH.as_posix()}/{version}"},
            "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
            "category": "Developer Tools",
        }],
    }


def managed_directory(root, path):
    for part in path.parts:
        root /= part
        if root.is_symlink():
            raise ValueError(f"refusing to write through symlink: {root}")
        root.mkdir(exist_ok=True)
    return root


def same_package(existing, candidate):
    if not existing.is_dir() or existing.is_symlink():
        return False
    expected = {entry.relative_to(candidate) for entry in candidate.rglob("*")}
    actual = {entry.relative_to(existing) for entry in existing.rglob("*")}
    if actual != expected:
        return False
    for path in expected:
        old = existing / path
        new = candidate / path
        if old.is_symlink() or old.is_dir() != new.is_dir():
            return False
        if new.is_file() and (not old.is_file() or old.read_bytes() != new.read_bytes()):
            return False
    return True


def package(output):
    name = json.loads((MARKETPLACE / "marketplace.json").read_text())["name"]
    manifest = MARKETPLACE / "plugins" / PLUGIN / MANIFEST_PATH
    metadata = json.loads(manifest.read_text())
    version = metadata["version"]
    if metadata["name"] != PLUGIN or not VERSION.fullmatch(version):
        raise ValueError("expected the prp-core manifest with a numeric release version")

    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve()
    catalog_dir = managed_directory(output, CATALOG_PATH.parent)
    catalog_file = catalog_dir / CATALOG_PATH.name
    if catalog_file.is_symlink():
        raise ValueError(f"refusing to replace symlink: {catalog_file}")
    if catalog_file.exists():
        try:
            old = json.loads(catalog_file.read_text())
            old_path = old["plugins"][0]["source"]["path"]
            old_version = old_path.rsplit("/", 1)[-1]
            managed = VERSION.fullmatch(old_version) and old == catalog(name, old_version)
        except (ValueError, KeyError, TypeError, AttributeError, IndexError):
            managed = False
        if not managed:
            raise ValueError(f"refusing to replace an unmanaged catalog: {catalog_file}")

    package_dir = managed_directory(output, PACKAGE_PATH)
    destination = package_dir / version
    with tempfile.TemporaryDirectory(prefix=".prp-core-", dir=package_dir) as temp:
        candidate = Path(temp) / "package"
        (candidate / MANIFEST_PATH.parent).mkdir(parents=True)
        shutil.copyfile(manifest, candidate / MANIFEST_PATH)
        adapters = sorted(SKILLS.glob("prp-*/SKILL.md"))
        if SKILLS / "prp-review-agents/SKILL.md" not in adapters:
            raise ValueError("the generated Codex review skill is missing")
        for adapter in adapters:
            target = candidate / "skills" / adapter.parent.name / "SKILL.md"
            target.parent.mkdir(parents=True)
            shutil.copyfile(adapter, target)
        if not destination.exists() and not destination.is_symlink():
            try:
                candidate.rename(destination)
            except OSError:
                if not same_package(destination, candidate):
                    raise
        elif not same_package(destination, candidate):
            raise ValueError(f"different bytes already packaged for {version}; bump the plugin version")

        data = json.dumps(catalog(name, version), indent=2) + "\n"
        if not catalog_file.exists() or catalog_file.read_text() != data:
            staged_catalog = Path(temp) / CATALOG_PATH.name
            staged_catalog.write_text(data)
            staged_catalog.replace(catalog_file)

    print(f"Packaged {PLUGIN} {version} with {len(adapters)} skills at {destination}")
    print(f"Marketplace catalog: {catalog_file}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=MARKETPLACE,
                        help="marketplace root (default: adapters/claude-code-plugin)")
    args = parser.parse_args()
    try:
        package(args.output)
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        print(f"package-codex-plugin: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

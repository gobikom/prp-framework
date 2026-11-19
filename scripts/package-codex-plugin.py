#!/usr/bin/env python3
"""Materialize the generated Codex skills for the local PRP marketplace."""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MARKETPLACE = ROOT / "adapters" / "claude-code-plugin"
SKILLS = ROOT / "adapters" / "codex"
PLUGIN = "prp-core"
MANIFEST_PATH = Path(".codex-plugin/plugin.json")
MARKETPLACE_SOURCE = MARKETPLACE.relative_to(ROOT) / "marketplace.json"
PLUGIN_SOURCE = MARKETPLACE.relative_to(ROOT) / "plugins" / PLUGIN / MANIFEST_PATH
CATALOG_PATH = Path(".agents/plugins/marketplace.json")
PACKAGE_PATH = Path(".agents/plugins/packages") / PLUGIN
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
SKILL_NAME = re.compile(r"prp-[a-z0-9-]+")


def committed_inputs():
    git_env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}

    def git(*args):
        return subprocess.run(["git", *args], cwd=ROOT, env=git_env,
                              stdout=subprocess.PIPE, check=True).stdout

    tree = git("rev-parse", "--verify", "HEAD").decode().strip()
    skill_root = SKILLS.relative_to(ROOT)
    expected = {MARKETPLACE_SOURCE, PLUGIN_SOURCE}
    metadata = {}
    skills = {}
    entries = git("ls-tree", "-r", "-z", tree, "--", str(skill_root),
                  str(MARKETPLACE_SOURCE), str(PLUGIN_SOURCE))
    for entry in entries.split(b"\0"):
        if not entry:
            continue
        attributes, path_bytes = entry.split(b"\t", 1)
        mode, kind, oid = attributes.decode().split()
        path = Path(os.fsdecode(path_bytes))
        skill = path.parent.parent == skill_root and path.name == "SKILL.md"
        if path not in expected and not skill:
            continue
        if kind != "blob" or mode not in {"100644", "100755"}:
            raise ValueError(f"expected a regular committed file: {path}")
        if skill:
            if not SKILL_NAME.fullmatch(path.parent.name):
                raise ValueError(f"invalid Codex skill name: {path.parent.name}")
            skills[path.parent.name] = git("cat-file", "blob", oid)
        else:
            metadata[path] = git("cat-file", "blob", oid)
    if metadata.keys() != expected or "prp-review-agents" not in skills:
        raise ValueError("the committed marketplace, plugin manifest or review skill is missing")
    return metadata, skills


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
    inputs, skills = committed_inputs()
    name = json.loads(inputs[MARKETPLACE_SOURCE])["name"]
    manifest = inputs[PLUGIN_SOURCE]
    metadata = json.loads(manifest)
    version = metadata["version"]
    if metadata["name"] != PLUGIN or not VERSION.fullmatch(version):
        raise ValueError("expected the prp-core manifest with a numeric release version")

    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve()
    catalog_dir = managed_directory(output, CATALOG_PATH.parent)
    catalog_file = catalog_dir / CATALOG_PATH.name
    if catalog_file.is_symlink():
        raise ValueError(f"refusing to replace symlink: {catalog_file}")
    previous_catalog = None
    if catalog_file.exists():
        previous_catalog = catalog_file.read_bytes()
        try:
            old = json.loads(previous_catalog)
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
        (candidate / MANIFEST_PATH).write_bytes(manifest)
        for skill_name, content in skills.items():
            target = candidate / "skills" / skill_name / "SKILL.md"
            target.parent.mkdir(parents=True)
            target.write_bytes(content)
        if not destination.exists() and not destination.is_symlink():
            try:
                candidate.rename(destination)
            except OSError:
                if not same_package(destination, candidate):
                    raise
        elif not same_package(destination, candidate):
            raise ValueError(f"different bytes already packaged for {version}; bump the plugin version")

        data = (json.dumps(catalog(name, version), indent=2) + "\n").encode()
        if previous_catalog != data:
            staged_catalog = Path(temp) / CATALOG_PATH.name
            staged_catalog.write_bytes(data)
            if previous_catalog is None:
                os.link(staged_catalog, catalog_file)
            else:
                if catalog_file.is_symlink() or catalog_file.read_bytes() != previous_catalog:
                    raise ValueError(f"catalog changed during packaging: {catalog_file}")
                staged_catalog.replace(catalog_file)

    print(f"Packaged {PLUGIN} {version} with {len(skills)} skills at {destination}")
    print(f"Marketplace catalog: {catalog_file}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=MARKETPLACE,
                        help="marketplace root (default: adapters/claude-code-plugin)")
    args = parser.parse_args()
    try:
        package(args.output)
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError, IndexError) as exc:
        print(f"package-codex-plugin: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

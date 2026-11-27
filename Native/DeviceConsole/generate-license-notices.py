#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Collect the locked iOS dependency graph and its actual bundled license texts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


# These exact published crates declare MIT but omit its text. The supplements
# preserve their author/source declarations and distinguish our supplied terms
# from an upstream LICENSE. A version or source change requires fresh review.
LICENSE_SUPPLEMENTS = {
    ("plist-macro", "0.1.6"): "d1d48559ddc8e9bd263f36180bbe1d4f2a3d55e5",
    ("plist_ffi", "0.1.6"): "265379167ab3f9a5664621a7f1c0f494b2ac7c96",
}


def license_files(package, crate):
    root = Path(package["manifest_path"]).parent
    selected = set()
    if package.get("license_file"):
        selected.add(root / package["license_file"])
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        parts = path.relative_to(root).parts
        if any(part in {".git", "target", ".cargo"} for part in parts):
            continue
        name = path.name.lower()
        if (name.startswith(("license", "licence", "copying", "copyright", "notice"))
                or any(part.lower() in {"licenses", "licences"} for part in parts[:-1])):
            selected.add(path)
    contents = []
    for path in sorted(selected):
        if not path.is_file():
            raise ValueError(f"missing declared license file: {package['name']}: {path.name}")
        try:
            content = path.read_text(encoding="utf-8").strip()
        except UnicodeDecodeError as error:
            raise ValueError(f"non-text license: {package['name']}: {path.name}") from error
        if content:
            contents.append((str(path.relative_to(root)), content))
    if not contents:
        expected = LICENSE_SUPPLEMENTS.get((package["name"], package["version"]))
        vcs = root / ".cargo_vcs_info.json"
        actual = json.loads(vcs.read_text())["git"]["sha1"] if expected and vcs.is_file() else None
        if not expected or actual != expected or package.get("license") != "MIT":
            raise ValueError(f"no reviewed license text in downloaded source: {package['name']} {package['version']}")
        supplement = crate / "licenses" / f"{package['name']}-{package['version']}-MIT-supplement.txt"
        contents.append(("LilaShift license supplement; upstream source " + expected,
                         supplement.read_text(encoding="utf-8").strip()))
    return contents


def generate(metadata, crate):
    packages = {item["id"]: item for item in metadata["packages"]}
    nodes = {item["id"]: item for item in metadata["resolve"]["nodes"]}
    root_id = metadata["resolve"]["root"]
    pending, selected = [root_id], set()
    while pending:
        key = pending.pop()
        if key in selected:
            continue
        selected.add(key)
        for dep in nodes[key].get("deps", []):
            if any(kind.get("kind") != "dev" for kind in dep["dep_kinds"]):
                pending.append(dep["pkg"])
    selected.discard(root_id)
    lines = [
        "LilaShift Device Console — dependency notices",
        "",
        "Generated from cargo metadata --locked for aarch64-apple-ios with the device feature.",
        "Includes runtime, procedural-macro and build dependencies in the resolved graph.",
        "This is a source/notice inventory, not a legal conclusion about license compatibility.",
        "Cargo.lock SHA-256: " + hashlib.sha256((crate / "Cargo.lock").read_bytes()).hexdigest(),
        "",
        (crate / "NOTICE.md").read_text(encoding="utf-8").strip(),
    ]
    for path in sorted((crate / "licenses").glob("*")):
        if path.is_file() and "supplement" not in path.name:
            lines.extend(["", "=" * 72, path.name, "", path.read_text(encoding="utf-8").strip()])
    summary = []
    for package in sorted((packages[key] for key in selected), key=lambda p: (p["name"], p["version"])):
        license_id = package.get("license") or ("See " + package["license_file"] if package.get("license_file") else None)
        if not license_id:
            raise ValueError(f"missing license declaration: {package['name']} {package['version']}")
        texts = license_files(package, crate)
        source = package.get("source") or package.get("repository") or "Vendored source: " + str(Path(package["manifest_path"]).parent.relative_to(crate))
        entry = {"name": package["name"], "version": package["version"], "license": license_id, "source": source,
                 "license_files": [name for name, _ in texts]}
        summary.append(entry)
        lines.extend(["", "=" * 72, f"{entry['name']} {entry['version']}",
                      "License: " + license_id, "Source: " + source])
        if package.get("repository"):
            lines.append("Repository: " + package["repository"])
        for name, content in texts:
            lines.extend(["", "--- " + name + " ---", content])
    return "\n".join(lines) + "\n", summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, help="Reuse a previously generated locked iOS metadata file")
    args = parser.parse_args()
    crate = Path(__file__).resolve().parent
    if args.metadata:
        metadata = json.loads(args.metadata.read_text())
    else:
        result = subprocess.run(["cargo", "metadata", "--locked", "--format-version", "1", "--no-default-features",
                                 "--features", "device", "--filter-platform", "aarch64-apple-ios"],
                                cwd=crate, check=True, text=True, stdout=subprocess.PIPE)
        metadata = json.loads(result.stdout)
    content, dependencies = generate(metadata, crate)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(args.output)
    print(f"Wrote license texts and explicitly marked supplements for {len(dependencies)} dependencies to {args.output}")
    output = crate / "build" / "dependency-licenses.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(dependencies, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))

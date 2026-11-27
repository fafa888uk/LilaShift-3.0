"""Generate the read-only MobileGestalt reference from the pinned MGKeys clone."""

import argparse
import ast
import json
from pathlib import Path
import re
import subprocess

REVISION = "db9cf77fa9d5330070b3dcb73fc1fd6a271fc421"
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Local MGKeys Git clone")
    args = parser.parse_args()

    def source_file(name):
        return subprocess.check_output(
            ["git", "-C", str(args.source), "show", f"{REVISION}:{name}"], text=True
        )

    version_data = {}
    for node in ast.parse(source_file("keys_versions.py")).body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
            version_data[node.targets[0].id] = ast.literal_eval(node.value)
    introduced = version_data["KEY_IOS_VERSIONS"]
    removed = version_data["KEY_IOS_REMOVED"]
    reintroduced = version_data["KEY_IOS_REINTRODUCED"]
    rows = []
    for key, name in re.findall(r'^\s+"([^"]+)", "([^"]+)",', source_file("mapping-gestalt.h"), re.M):
        rows.append(dict(
            key=key, name=name, introduced=introduced.get(key, "unknown"),
            removed=removed.get(key, []), reintroduced=reintroduced.get(key, []),
        ))
    if len(rows) != 928 or len({row["key"] for row in rows}) != len(rows):
        raise SystemExit("Unexpected source table shape")
    path = ROOT / "GestaltX/MGReference.json"
    path.write_text("[\n" + ",\n".join(json.dumps(row, ensure_ascii=False) for row in rows) + "\n]\n")


if __name__ == "__main__":
    main()

"""Generate the iPhone and iPad model lookup from DeviceKit 5.10.0."""

import argparse
import json
from pathlib import Path
import re
import subprocess

REVISION = "fab82bd988405367c915143e293479f481e93ba0"
ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Local DeviceKit Git clone")
    args = parser.parse_args()
    text = subprocess.check_output(
        ["git", "-C", str(args.source), "show", f"{REVISION}:Source/Device.generated.swift"],
        text=True,
    )
    names = dict(re.findall(r'^\s+case \.(\w+): return "([^"]+)"\s*$', text, re.M))
    models = {}
    for identifiers, name in re.findall(r'^\s+case ("[^"\n]+"(?:, "[^"\n]+")*): return (\w+)\s*$', text, re.M):
        for identifier in re.findall(r'"((?:iPhone|iPad)\d+,\d+)"', identifiers):
            if identifier in models:
                raise SystemExit(f"Duplicate device identifier: {identifier}")
            models[identifier] = names[name]
    if len(models) < 100:
        raise SystemExit("Unexpected source table shape")
    (ROOT / "GestaltX/DeviceModels.json").write_text(json.dumps(models, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()

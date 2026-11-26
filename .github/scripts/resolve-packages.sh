#!/usr/bin/env bash
# Let Xcode refresh resolver metadata, but reject any change to the committed
# dependency identities, locations, versions, or revisions.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
project="GestaltX.xcodeproj/project.pbxproj"
lockfile="GestaltX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [[ ! -f "$lockfile" ]]; then
  if grep -q 'isa = XCRemoteSwiftPackageReference' "$project"; then
    echo "Error: a project with remote packages must commit Package.resolved." >&2
    exit 1
  fi
  exit 0
fi

expected="$(mktemp)"
trap 'rm -f "$expected"' EXIT
cp "$lockfile" "$expected"
xcodebuild -resolvePackageDependencies -project GestaltX.xcodeproj -scheme GestaltX

python3 - "$expected" "$lockfile" <<'VERIFY_PACKAGE_PINS'
import json
import sys


def read_pins(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    pins = {}
    for pin in data["pins"]:
        identity = pin["identity"]
        if identity in pins:
            raise SystemExit(f"Duplicate package identity: {identity}")
        location = pin["location"].rstrip("/")
        if location.endswith(".git"):
            location = location[:-4]
        pins[identity] = (pin["kind"], location, pin["state"])
    return pins


expected = read_pins(sys.argv[1])
actual = read_pins(sys.argv[2])
if not expected or expected != actual:
    changed = sorted(
        identity for identity in expected.keys() | actual.keys()
        if expected.get(identity) != actual.get(identity)
    )
    raise SystemExit(
        "Package resolution changed committed pins; update and review the lockfile: "
        + ", ".join(changed)
    )
print(f"Verified {len(actual)} committed package versions and revisions.")
VERIFY_PACKAGE_PINS

#!/usr/bin/env bash
# Build LilaShift and package an ad-hoc signed IPA with the entitlements of the
# app and its share extension embedded. Re-signing tools such as AltStore and
# SideStore read the entitlements from the existing signature to decide which
# App Groups to register, so an unsigned IPA ends up without an App Group.
#
# Usage: .github/scripts/build-ipa.sh [output-dir]   (default: build/ipa)
#
# Set BUILD_DATE (YYYY-MM-DD) to write it to GestaltX/BuildDate.txt, which the
# About page shows. Every package includes a SHA-256 checksum and a manifest
# recording its actual source commit, dependencies, toolchain and bundle versions.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$(mkdir -p "${1:-$root/build/ipa}" && cd "${1:-$root/build/ipa}" && pwd)"
cd "$root"

# Every target must share one marketing version and build number.
version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \(.*\);/\1/p' GestaltX.xcodeproj/project.pbxproj | sort -u)"
if [[ -z "$version" || "$(wc -l <<< "$version")" -ne 1 ]]; then
  echo "Error: expected one MARKETING_VERSION, found: ${version:-none}" >&2
  exit 1
fi
build="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' GestaltX.xcodeproj/project.pbxproj | sort -u)"
if [[ -z "$build" || "$(wc -l <<< "$build")" -ne 1 ]]; then
  echo "Error: expected one CURRENT_PROJECT_VERSION, found: ${build:-none}" >&2
  exit 1
fi
source_commit="$(git rev-parse HEAD)"
echo "==> Building LilaShift $version ($build) from $source_commit"

if [[ -n "${BUILD_DATE:-}" ]]; then
  printf '%s' "$BUILD_DATE" > GestaltX/BuildDate.txt
fi

# Locale JSON files must be compiled into the catalog used by both targets.
if [[ -f scripts/generate_localization.py ]]; then
  python3 scripts/generate_localization.py
fi

bash .github/scripts/resolve-packages.sh

# Building the app target also builds the embedded share extension
xcodebuild -quiet \
  -project GestaltX.xcodeproj \
  -target GestaltX \
  -configuration Release \
  -sdk iphoneos \
  -disableAutomaticPackageResolution \
  SYMROOT="$root/build" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  build

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload" "$out"
cp -R "$root/build/Release-iphoneos/GestaltX.app" "$stage/Payload/"
app="$stage/Payload/GestaltX.app"
appex="$app/PlugIns/GestaltXShare.appex"

echo "==> Signing with entitlements"
# Sign nested code from the inside out: frameworks and dylibs, then the
# extension, then the app
while IFS= read -r -d '' item; do
  codesign -f -s - "$item"
done < <(find "$app" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)

# Older versions have no share extension
bundles=()
if [[ -d "$appex" ]]; then
  codesign -f -s - --entitlements ShareExtension/GestaltXShare.entitlements "$appex"
  bundles+=("$appex")
fi
codesign -f -s - --entitlements GestaltX/GestaltX.entitlements "$app"
bundles+=("$app")

# Check the actual embedded signature, not just the entitlement source files.
python3 - "${bundles[@]}" <<'VERIFY_ENTITLEMENTS'
import plistlib, subprocess, sys
common = None
for bundle in sys.argv[1:]:
    subprocess.run(["codesign", "--verify", "--strict", bundle], check=True)
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", bundle], capture_output=True, check=True)
    entitlements = plistlib.loads(result.stdout)
    groups = entitlements.get("com.apple.security.application-groups", [])
    if not isinstance(groups, list) or not groups or not all(isinstance(group, str) and group for group in groups):
        raise SystemExit("Missing usable App Group entitlements in a signed bundle")
    if entitlements.get("com.apple.developer.team-identifier"):
        raise SystemExit("A developer Team ID must not be embedded in the ad-hoc package")
    metadata = subprocess.run(["codesign", "-dvv", bundle], capture_output=True, text=True, check=True).stderr
    if "Signature=adhoc" not in metadata or "TeamIdentifier=not set" not in metadata:
        raise SystemExit("Expected an ad-hoc signature without a developer identity")
    common = set(groups) if common is None else common.intersection(groups)
if not common:
    raise SystemExit("The app and share extension do not have a common App Group")
print("App and embedded extensions retain common App Groups with ad-hoc signatures.")
VERIFY_ENTITLEMENTS

ipa="$out/LilaShift_$version.ipa"
checksum="$ipa.sha256"
manifest="$out/build-manifest.json"
staged_ipa="$stage/LilaShift_$version.ipa"
# Keep an existing package until the replacement has passed archive and version checks.
(cd "$stage" && zip -qry "$staged_ipa" Payload)
python3 - "$staged_ipa" "$version" "$build" "$source_commit" <<'VERIFY_PACKAGE'
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile

ipa = Path(sys.argv[1])
version, build, source_commit = sys.argv[2:]
bundles = []
with zipfile.ZipFile(ipa) as archive:
    invalid_entry = archive.testzip()
    if invalid_entry:
        raise SystemExit(f"Invalid IPA ZIP entry: {invalid_entry}")
    info_paths = sorted(
        name for name in archive.namelist()
        if re.fullmatch(r"Payload/[^/]+\.app/(?:PlugIns/[^/]+\.appex/)?Info\.plist", name)
    )
    main_apps = [path for path in info_paths if "/PlugIns/" not in path]
    if len(main_apps) != 1:
        raise SystemExit("Expected exactly one app Info.plist in the IPA")
    for path in info_paths:
        info = plistlib.loads(archive.read(path))
        if info.get("CFBundleShortVersionString") != version or str(info.get("CFBundleVersion")) != build:
            raise SystemExit(f"Packaged version/build does not match project: {path}")
        bundles.append({
            "path": path.rsplit("/", 1)[0],
            "bundle_identifier": info["CFBundleIdentifier"],
            "version": info["CFBundleShortVersionString"],
            "build": str(info["CFBundleVersion"]),
        })

digest = hashlib.sha256()
with ipa.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
sha256 = digest.hexdigest()
lockfile = Path("GestaltX.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
lock = json.loads(lockfile.read_text(encoding="utf-8")) if lockfile.is_file() else {}
repository = os.environ.get("GITHUB_REPOSITORY")
run_id = os.environ.get("GITHUB_RUN_ID")
server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
manifest = {
    "schema_version": 1,
    "app": "LilaShift",
    "marketing_version": version,
    "build": build,
    "source_commit": source_commit,
    "source_repository": repository,
    "source_ref": os.environ.get("REF") or os.environ.get("GITHUB_REF"),
    "built_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "build_date": os.environ.get("BUILD_DATE"),
    "xcode_version": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "runner_image": os.environ.get("ImageOS"),
    "runner_image_version": os.environ.get("ImageVersion"),
    "workflow_run_url": f"{server}/{repository}/actions/runs/{run_id}" if repository and run_id else None,
    "package_pins": lock.get("pins", []),
    "package_origin_hash": lock.get("originHash"),
    "ipa": {"file": ipa.name, "sha256": sha256, "size_bytes": ipa.stat().st_size},
    "bundles": bundles,
    "signature": "ad-hoc",
    "app_groups_verified": True,
}
ipa.with_name("build-manifest.json").write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
ipa.with_suffix(".ipa.sha256").write_text(f"{sha256}  {ipa.name}\n", encoding="utf-8")
print(f"Verified IPA bundle versions and ZIP integrity; SHA-256 {sha256}")
VERIFY_PACKAGE

mv -f "$staged_ipa" "$ipa"
mv -f "$stage/LilaShift_$version.ipa.sha256" "$checksum"
mv -f "$stage/build-manifest.json" "$manifest"
echo "==> Wrote $ipa"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$version"
    echo "build=$build"
    echo "ipa=$ipa"
    echo "checksum=$checksum"
    echo "manifest=$manifest"
    echo "source_commit=$source_commit"
  } >> "$GITHUB_OUTPUT"
fi

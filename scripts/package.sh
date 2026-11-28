#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=5.0.0
build=50000001
out="$PWD/artifacts"
mkdir -p "$out"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

xcodebuild -project LilaShift.xcodeproj -target LilaShift -configuration Release \
  -sdk iphoneos ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  "CONFIGURATION_BUILD_DIR=$temp/products" "OBJROOT=$temp/obj" "SYMROOT=$temp/sym" build

app="$temp/products/LilaShift.app"
plist="$app/Info.plist"
plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
test "$(plist_value CFBundleShortVersionString)" = "$version"
test "$(plist_value CFBundleVersion)" = "$build"
test "$(plist_value CFBundleIdentifier)" = "com.lilashift.deviceutility"
test "$(plist_value MinimumOSVersion)" = "17.0"
exe="$(plist_value CFBundleExecutable)"
test "$exe" = "LilaShift"
test -s "$app/$exe"
test "$(xcrun lipo -archs "$app/$exe")" = arm64
xcrun vtool -show-build "$app/$exe" > "$temp/build-target"
grep -Eq '^[[:space:]]*platform[[:space:]]+IOS[[:space:]]*
test -s "$app/Assets.car"
test -s "$app/zh-Hans.lproj/Localizable.strings"
test -s "$app/en.lproj/Localizable.strings"
test ! -e "$app/embedded.mobileprovision"

mkdir "$temp/Payload"
mv "$app" "$temp/Payload/"
ipa="LilaShift_${version}_Official_API.ipa"
(cd "$temp"; /usr/bin/zip -q -r -y "$ipa" Payload)
unzip -tq "$temp/$ipa"
unzip -Z1 "$temp/$ipa" > "$temp/entries"
grep -Fx "Payload/LilaShift.app/Info.plist" "$temp/entries"
grep -Fx "Payload/LilaShift.app/$exe" "$temp/entries"
(cd "$temp"; shasum -a 256 "$ipa" > "$ipa.sha256"; shasum -a 256 -c "$ipa.sha256")
mv "$temp/$ipa" "$temp/$ipa.sha256" "$out/"
test -s "$out/$ipa"
(cd "$out"; shasum -a 256 -c "$ipa.sha256")
printf 'Artifact bytes: %s\n' "$(wc -c < "$out/$ipa" | tr -d ' ')"
cat "$out/$ipa.sha256"
 "$temp/build-target"
test -s "$app/PrivacyInfo.xcprivacy"
/usr/bin/plutil -lint "$app/PrivacyInfo.xcprivacy"
for table in W7Report W8Monitoring W9Studio W11Appearance; do
  test -s "$app/zh-Hans.lproj/$table.strings"
done
test -s "$app/Assets.car"
test -s "$app/zh-Hans.lproj/Localizable.strings"
test -s "$app/en.lproj/Localizable.strings"
test ! -e "$app/embedded.mobileprovision"

mkdir "$temp/Payload"
mv "$app" "$temp/Payload/"
ipa="LilaShift_$version.ipa"
(cd "$temp"; /usr/bin/zip -q -r -y "$ipa" Payload)
unzip -tq "$temp/$ipa"
unzip -Z1 "$temp/$ipa" > "$temp/entries"
grep -Fx "Payload/LilaShift.app/Info.plist" "$temp/entries"
grep -Fx "Payload/LilaShift.app/$exe" "$temp/entries"
(cd "$temp"; shasum -a 256 "$ipa" > "$ipa.sha256"; shasum -a 256 -c "$ipa.sha256")
mv "$temp/$ipa" "$temp/$ipa.sha256" "$out/"

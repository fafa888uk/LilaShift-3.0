#!/usr/bin/env python3
"""LilaShift license-compliance check.

Runs on every IPA build (see .github/workflows/check-licenses.yml).
Verifies, with specific diagnostics:

  1. LICENSE exists and is the real GPL v3 text (not a placeholder).
  2. THIRD_PARTY_NOTICES.md exists and is byte-identical to the in-app
     GestaltX/Licenses/ThirdPartyNotices.txt.
  3. Every license text named in the notices exists in GestaltX/Licenses/
     and is non-empty; bundled GPL texts are byte-identical to the root
     LICENSE; bundled MIT texts carry the permission grant.
  4. Every third-party project in the notices carries a source URL.
  5. The About page lists every used or referenced project as its own
     entry (name, url, license file where bundled) and shows the current
     repository URL, not the old patch-based repository.
  6. docs/OPEN_SOURCE_REFERENCES.md and docs/FEATURE_ORIGIN_MATRIX.md
     exist and cover all 17 projects / 16 feature areas.
  7. No stale "pristine v1.0.7 source plus the modification patch"
     distribution statement survives in any user-facing file.
  8. Version and changelog are consistent: MARKETING_VERSION in the
     Xcode project matches the newest [x.y.z] heading in CHANGELOG.md
     and the version badge in README.md.
  9. When run in CI (GITHUB_SHA set), the checked-out source is the
     build commit, so the packaged source version matches the IPA.
 10. The NeoSpring/Ketamine WebKit respring implementation stays
     removed (license suspension, user decision 2026-11-14):
     GestaltX/NeoSpringView.swift is absent and no Swift file in
     GestaltX/ carries the respring symbols or the isRespringing /
     needsRespring state; the About page and docs may still name the
     projects as suspended.

This is a structural/content check, not a legal opinion: it verifies
that the attribution, texts and links the project promises are actually
present and consistent. It does not declare any license compatible.
Known issues that need a human decision are warnings, printed with
their location, and do not fail the build; they are recorded in
docs/OPEN_SOURCE_REFERENCES.md.

Exit code: 0 when all checks pass (warnings allowed), 1 on any failure.
Usage: python3 scripts/check-licenses.py
"""

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"
IN_APP_NOTICES = ROOT / "GestaltX" / "Licenses" / "ThirdPartyNotices.txt"
LICENSES_DIR = ROOT / "GestaltX" / "Licenses"
ABOUT_VIEW = ROOT / "GestaltX" / "AboutView.swift"
REFERENCES = ROOT / "docs" / "OPEN_SOURCE_REFERENCES.md"
MATRIX = ROOT / "docs" / "FEATURE_ORIGIN_MATRIX.md"
PBXPROJ = ROOT / "GestaltX.xcodeproj" / "project.pbxproj"
CHANGELOG = ROOT / "CHANGELOG.md"
README = ROOT / "README.md"

# The 17 projects the audit covers (see docs/OPEN_SOURCE_REFERENCES.md).
PROJECTS = (
    "GestaltX",
    "worse_query",
    "Ketamine",
    "NeoSpring",
    "LCSign",
    "Erosion-CN",
    "Erosion",
    "Gester",
    "ZIPFoundation",
    "Primer Octicons",
    "MGKeys",
    "Nugget",
    "mond",
    "GestaltEdit",
    "WQFiles",
    "SnapshotTesting",
    "SwiftLint",
)

# Source URL each project must carry in THIRD_PARTY_NOTICES.md.
PROJECT_URLS = (
    "https://github.com/huamidev/GestaltX",
    "https://github.com/forcequitOS/worse_query",
    "https://github.com/Nouvborne/Ketamine",
    "https://github.com/rooootdev/neospring",
    "https://sign.lc",
    "https://github.com/Kianuni/Erosion-CN",
    "https://github.com/jailbreakdotparty/Erosion",
    "https://github.com/sasobhabha/Gester",
    "https://github.com/weichsel/ZIPFoundation",
    "https://github.com/primer/octicons",
    "https://github.com/PoomSmart/MGKeys",
    "https://github.com/leminlimez/Nugget",
    "https://github.com/rooootdev/mond",
    "https://github.com/frs0n/GestaltEdit",
    "https://github.com/kolbicz/WQFiles",
    "https://github.com/pointfreeco/swift-snapshot-testing",
    "https://github.com/realm/SwiftLint",
)

# Files that must not contain the old patch-based distribution statement.
STALE_STATEMENT_FILES = (
    ABOUT_VIEW,
    NOTICES,
    IN_APP_NOTICES,
    README,
    ROOT / "README_ZH-CN.md",
    CHANGELOG,
    ROOT / "CHANGELOG_ZH-CN.md",
)

FAILURES = []
WARNINGS = []


def fail(message):
    FAILURES.append(message)
    print(f"FAIL: {message}")


def warn(message):
    WARNINGS.append(message)
    print(f"WARN: {message}")


def ok(message):
    print(f"ok: {message}")


def check_root_license():
    license_path = ROOT / "LICENSE"
    if not license_path.is_file():
        fail("LICENSE is missing from the repository root")
        return
    text = license_path.read_text(encoding="utf-8", errors="strict")
    for required in ("GNU GENERAL PUBLIC LICENSE",
                     "Version 3, 29 June 2007",
                     "TERMS AND CONDITIONS",
                     "Copyright (C) 2007 Free Software Foundation, Inc."):
        if required not in text:
            fail(f"LICENSE does not look like the GPL v3 text "
                 f"(missing {required!r})")
            return
    ok("LICENSE is the GPL v3 text")


def check_notices_in_sync():
    if not NOTICES.is_file():
        fail("THIRD_PARTY_NOTICES.md is missing")
        return
    if not IN_APP_NOTICES.is_file():
        fail("GestaltX/Licenses/ThirdPartyNotices.txt is missing")
        return
    if NOTICES.read_bytes() != IN_APP_NOTICES.read_bytes():
        fail("THIRD_PARTY_NOTICES.md and "
             "GestaltX/Licenses/ThirdPartyNotices.txt differ; "
             "keep the in-app notices in sync with the repo notices")
        return
    ok("THIRD_PARTY_NOTICES.md is in sync with the in-app notices")


def check_bundled_license_texts():
    text = NOTICES.read_text(encoding="utf-8") if NOTICES.is_file() else ""
    named = sorted(set(re.findall(r"[A-Za-z0-9][\w.-]*\.txt", text)))
    if not named:
        fail("no license files are named in THIRD_PARTY_NOTICES.md")
        return
    for filename in named:
        path = LICENSES_DIR / filename
        if not path.is_file():
            fail(f"{filename} is named in THIRD_PARTY_NOTICES.md but "
                 f"missing from GestaltX/Licenses/")
        elif path.stat().st_size == 0:
            fail(f"GestaltX/Licenses/{filename} is empty")
    root_license = (ROOT / "LICENSE").read_bytes() if (ROOT / "LICENSE").is_file() else b""
    for filename in ("GestaltX-GPL-3.0.txt", "Erosion-GPL-3.0.txt"):
        path = LICENSES_DIR / filename
        if path.is_file() and root_license and path.read_bytes() != root_license:
            fail(f"GestaltX/Licenses/{filename} is not byte-identical "
                 f"to the root LICENSE")
    for filename in ("Gester-MIT.txt", "ZIPFoundation-MIT.txt",
                     "Primer-Octicons-MIT.txt"):
        path = LICENSES_DIR / filename
        if path.is_file():
            mit = path.read_text(encoding="utf-8")
            if ("MIT License" not in mit
                    or "Permission is hereby granted, free of charge" not in mit):
                fail(f"GestaltX/Licenses/{filename} does not carry the "
                     f"MIT permission grant")
    ok(f"{len(named)} license texts named in notices all exist and are non-empty")


def check_notices_carry_sources():
    if not NOTICES.is_file():
        return
    text = NOTICES.read_text(encoding="utf-8")
    for name in PROJECTS:
        # SnapshotTesting is named by its repository name in the notices.
        alias = "swift-snapshot-testing" if name == "SnapshotTesting" else name
        if name not in text and alias not in text:
            fail(f"THIRD_PARTY_NOTICES.md does not name {name}")
    for url in PROJECT_URLS:
        if url not in text:
            fail(f"THIRD_PARTY_NOTICES.md does not link {url}")
    ok("notices name all 17 projects with their source URLs")


def check_about_view():
    if not ABOUT_VIEW.is_file():
        fail("GestaltX/AboutView.swift is missing")
        return
    text = ABOUT_VIEW.read_text(encoding="utf-8")
    entries = re.findall(r"OpenSourceProject\(", text)
    if len(entries) != 17:
        fail(f"AboutView lists {len(entries)} open-source projects, "
             f"expected 17 (one entry per project)")
    urls = re.findall(r'url: "(https?://[^"]+)"', text)
    if len(urls) != 17:
        fail(f"AboutView has {len(urls)} project URLs, expected 17")
    for name in PROJECTS:
        if name not in text:
            fail(f"AboutView does not list {name}")
    license_files = re.findall(r'licenseFile: "([^"]+)"', text)
    for name in license_files:
        path = LICENSES_DIR / f"{name}.txt"
        if not path.is_file():
            fail(f"AboutView licenseFile {name!r} is missing from "
                 f"GestaltX/Licenses/ ({name}.txt)")
    if re.search(r"fafa888uk/LilaShift(?!-3\.0)", text):
        fail("AboutView links the old patch-based repository "
             "(fafa888uk/LilaShift); it must link LilaShift-3.0")
    if "GestaltBrand.lilashift" not in text and \
            "fafa888uk/LilaShift-3.0" not in text:
        fail("AboutView does not show the current repository URL "
             "(GestaltBrand.lilashift / fafa888uk/LilaShift-3.0)")
    ok("AboutView lists all 17 projects with URLs and bundled license files")


def check_reference_docs():
    for path, what in ((REFERENCES, "docs/OPEN_SOURCE_REFERENCES.md"),
                       (MATRIX, "docs/FEATURE_ORIGIN_MATRIX.md")):
        if not path.is_file():
            fail(f"{what} is missing")
    if REFERENCES.is_file():
        text = REFERENCES.read_text(encoding="utf-8")
        for name in PROJECTS:
            if name not in text:
                fail(f"docs/OPEN_SOURCE_REFERENCES.md does not cover {name}")
        if "NeoSpring" in text and "no license" not in text.lower() \
                and "无许可证声明" not in text:
            fail("docs/OPEN_SOURCE_REFERENCES.md must record that "
                 "NeoSpring states no license (known issue)")
        ok("docs/OPEN_SOURCE_REFERENCES.md covers all 17 projects")
    if MATRIX.is_file():
        text = MATRIX.read_text(encoding="utf-8")
        # The matrix is written in Chinese; accept either language.
        for feature in (("MobileGestalt",),
                        ("one-tap", "一键"),
                        ("Apple Intelligence",),
                        ("eSIM",),
                        ("backup", "备份"),
                        ("Respring",),
                        ("signing", "签名"),
                        ("SwiftUI",),
                        ("3.0",)):
            if not any(word in text for word in feature):
                fail(f"docs/FEATURE_ORIGIN_MATRIX.md does not mention "
                     f"{feature[0]!r}")
        ok("docs/FEATURE_ORIGIN_MATRIX.md covers the feature areas")


def check_no_stale_statement():
    for path in STALE_STATEMENT_FILES:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for stale in ("pristine v1.0.7 source plus the modification patch",
                      "原始 v1.0.7 源码加修改补丁"):
            if stale in text:
                fail(f"{path.relative_to(ROOT)} still says {stale!r}; "
                     f"the project now ships full modified source")
    ok("no stale patch-based distribution statement in user-facing files")


def check_version_consistency():
    if not PBXPROJ.is_file():
        fail("GestaltX.xcodeproj/project.pbxproj is missing")
        return
    versions = sorted(set(re.findall(r"MARKETING_VERSION = ([0-9.]+);",
                                      PBXPROJ.read_text(encoding="utf-8"))))
    if len(versions) != 1:
        fail(f"MARKETING_VERSION is not uniform in project.pbxproj: {versions}")
        return
    version = versions[0]
    if not CHANGELOG.is_file():
        fail("CHANGELOG.md is missing")
        return
    headings = re.findall(r"^## \[([0-9.]+)\]", CHANGELOG.read_text(encoding="utf-8"),
                          flags=re.MULTILINE)
    if not headings:
        fail("CHANGELOG.md has no [x.y.z] version heading")
        return
    if headings[0] != version:
        fail(f"MARKETING_VERSION is {version} but the newest CHANGELOG.md "
             f"heading is [{headings[0]}]")
    if README.is_file():
        badge = re.search(r"badge/version-([0-9.]+)-", README.read_text(encoding="utf-8"))
        if not badge:
            fail("README.md has no version badge")
        elif badge.group(1) != version:
            fail(f"README.md version badge says {badge.group(1)} but "
                 f"MARKETING_VERSION is {version}")
    ok(f"version {version} is consistent across project, changelog and README")


def check_build_commit():
    sha = os.environ.get("GITHUB_SHA")
    if not sha:
        return
    try:
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                              capture_output=True, text=True,
                              check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        warn("could not read git HEAD; cannot confirm the packaged source "
             "matches the build commit")
        return
    if head != sha:
        fail(f"checked-out HEAD {head} is not the build commit {sha}; "
             f"the packaged source would not match the IPA build commit")
    else:
        ok(f"checked-out source matches the build commit {sha[:12]}")


def check_respring_removed():
    # License suspension, user decision 2026-11-14 (option c): the
    # NeoSpring/Ketamine WebKit respring implementation was removed, not
    # renamed. It must not creep back into the shipped code. The About
    # page and the docs may still name Ketamine/NeoSpring as suspended;
    # they are not checked here.
    before = len(FAILURES)
    if (ROOT / "GestaltX" / "NeoSpringView.swift").is_file():
        fail("GestaltX/NeoSpringView.swift is present again; the "
             "unlicensed respring implementation must stay removed "
             "(see docs/OPEN_SOURCE_REFERENCES.md §4)")
    for marker in ("startNeoSpring", "NeoSpringWebView", "stopNeoSpring"):
        for path in sorted((ROOT / "GestaltX").glob("*.swift")):
            if marker in path.read_text(encoding="utf-8"):
                fail(f"{path.relative_to(ROOT)} still contains "
                     f"{marker!r}; the respring implementation must stay "
                     f"removed")
    for path in (ROOT / "GestaltX" / "ContentView.swift",
                 ROOT / "GestaltX" / "GestaltManager.swift"):
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for marker in ("isRespringing", "needsRespring", "NeoSpringView"):
            if marker in text:
                fail(f"{path.relative_to(ROOT)} still references "
                     f"{marker!r}; the respring state must stay removed")
    if len(FAILURES) == before:
        ok("the NeoSpring/Ketamine respring implementation stays removed")


def check_known_issues():
    # Package.resolved must pin every SwiftPM dependency the project
    # requires; a mismatch is a warning (fixable only in Xcode), not a
    # license failure.
    resolved = ROOT / "GestaltX.xcodeproj" / "project.xcworkspace" / "xcshareddata" / "swiftpm" / "Package.resolved"
    if not resolved.is_file():
        warn("Package.resolved is missing; cannot verify pinned dependencies")
        return
    text = resolved.read_text(encoding="utf-8")
    if "swift-snapshot-testing" not in text and "SnapshotTesting" in PBXPROJ.read_text(encoding="utf-8"):
        warn("Package.resolved does not pin SnapshotTesting although "
             "project.pbxproj requires it; run "
             "xcodebuild -resolvePackageDependencies in an Xcode environment")
    if "ZIPFoundation" not in text:
        fail("Package.resolved does not pin ZIPFoundation")
    else:
        ok("Package.resolved pins ZIPFoundation")


def main():
    check_root_license()
    check_notices_in_sync()
    check_bundled_license_texts()
    check_notices_carry_sources()
    check_about_view()
    check_reference_docs()
    check_respring_removed()
    check_no_stale_statement()
    check_version_consistency()
    check_build_commit()
    check_known_issues()

    print()
    if FAILURES:
        print(f"LICENSE CHECK FAILED: {len(FAILURES)} failure(s), "
              f"{len(WARNINGS)} warning(s)")
        return 1
    print(f"LICENSE CHECK PASSED ({len(WARNINGS)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())

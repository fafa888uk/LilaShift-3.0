import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"
LICENSES_DIR = ROOT / "GestaltX" / "Licenses"
ABOUT_VIEW = ROOT / "GestaltX" / "AboutView.swift"
REFERENCES = ROOT / "docs" / "OPEN_SOURCE_REFERENCES.md"
MATRIX = ROOT / "docs" / "FEATURE_ORIGIN_MATRIX.md"
GENERATE_LOCALIZATION = ROOT / "scripts" / "generate_localization.py"

# The 18 projects the audit covers (see docs/OPEN_SOURCE_REFERENCES.md).
AUDIT_PROJECTS = (
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
    "DeviceKit",
)

# Files that must not contain the old patch-based distribution statement.
STALE_STATEMENT_FILES = (
    ABOUT_VIEW,
    NOTICES,
    LICENSES_DIR / "ThirdPartyNotices.txt",
    ROOT / "README.md",
    ROOT / "README_ZH-CN.md",
    ROOT / "CHANGELOG.md",
    ROOT / "CHANGELOG_ZH-CN.md",
)

# Every third-party project the tree actually uses (see THIRD_PARTY_NOTICES.md
# for what each contributes). Distinctive strings, so "Erosion" cannot pass
# on the strength of "Erosion-CN" alone.
REQUIRED_NOTICE_NAMES = (
    "GestaltX",
    "huamidev",
    "@steam8871",
    "worse_query",
    "Ketamine",
    "NeoSpring",
    "LCSign",
    "Erosion-CN",
    "jailbreakdotparty/Erosion",
    "Gester",
    "ZIPFoundation",
    "Primer Octicons",
    "MGKeys",
    "Nugget",
    "mond",
    "GestaltEdit",
)

# Projects the in-app Credits & Licenses page must show, matching the
# completed notices file.
REQUIRED_ABOUT_NAMES = (
    "worse_query",
    "NeoSpring",
    "Ketamine",
    "MGKeys",
    "Nugget",
    "mond",
    "GestaltEdit",
    "LCSign",
    "Gester",
    "Erosion",
    "Erosion-CN",
    "ZIPFoundation",
    "Primer Octicons",
    "huamidev",
    "@steam8871",
)


class ThirdPartyNoticesTests(unittest.TestCase):
    def test_notices_file_exists_and_names_required_projects(self):
        self.assertTrue(NOTICES.is_file(), "THIRD_PARTY_NOTICES.md is missing")
        text = NOTICES.read_text(encoding="utf-8")
        for name in REQUIRED_NOTICE_NAMES:
            with self.subTest(project=name):
                self.assertIn(name, text)

    def test_notices_distinguishes_usage_kinds(self):
        text = NOTICES.read_text(encoding="utf-8")
        for kind in ("bundled code", "adapted code", "reused data",
                     "design reference", "research reference"):
            with self.subTest(kind=kind):
                self.assertIn(kind, text)

    def test_license_files_named_in_notices_exist_and_are_nonempty(self):
        text = NOTICES.read_text(encoding="utf-8")
        named = sorted(set(re.findall(r"[A-Za-z0-9][\w.-]*\.txt", text)))
        self.assertTrue(named, "no license files named in notices")
        for filename in named:
            with self.subTest(file=filename):
                path = LICENSES_DIR / filename
                self.assertTrue(path.is_file(), f"{filename} missing from GestaltX/Licenses/")
                self.assertGreater(path.stat().st_size, 0, f"{filename} is empty")

    def test_bundled_gpl_texts_match_root_license(self):
        root_license = (ROOT / "LICENSE").read_bytes()
        for filename in ("GestaltX-GPL-3.0.txt", "Erosion-GPL-3.0.txt"):
            with self.subTest(file=filename):
                self.assertEqual((LICENSES_DIR / filename).read_bytes(), root_license)

    def test_bundled_mit_texts_carry_the_permission_grant(self):
        for filename in ("Gester-MIT.txt", "ZIPFoundation-MIT.txt",
                         "Primer-Octicons-MIT.txt"):
            with self.subTest(file=filename):
                text = (LICENSES_DIR / filename).read_text(encoding="utf-8")
                self.assertIn("MIT License", text)
                self.assertIn("Permission is hereby granted, free of charge", text)

    def test_about_credits_match_notices(self):
        text = ABOUT_VIEW.read_text(encoding="utf-8")
        for name in REQUIRED_ABOUT_NAMES:
            with self.subTest(project=name):
                self.assertIn(name, text)

    def test_about_license_files_exist_in_bundle(self):
        text = ABOUT_VIEW.read_text(encoding="utf-8")
        # Both the licenseRow helper (file:) and the project data array
        # (licenseFile:) name bundled texts; both must exist.
        referenced = sorted(set(re.findall(r'(?:license)?[Ff]ile: "([^"]+)"', text)))
        self.assertTrue(referenced, "no licensedCredit files in AboutView")
        for name in referenced:
            with self.subTest(file=name):
                path = LICENSES_DIR / f"{name}.txt"
                self.assertTrue(path.is_file(), f"{name}.txt missing from GestaltX/Licenses/")

    def test_about_shows_current_repo_url(self):
        text = ABOUT_VIEW.read_text(encoding="utf-8")
        self.assertTrue("GestaltBrand.lilashift" in text
                        or "fafa888uk/LilaShift-3.0" in text,
                        "AboutView does not show the current repository URL")
        self.assertIsNone(
            re.search(r"fafa888uk/LilaShift(?!-3\.0)", text),
            "AboutView still links the old patch-based repository")

    def test_about_relationship_keys_exist_in_localization(self):
        about = ABOUT_VIEW.read_text(encoding="utf-8")
        keys = sorted(set(re.findall(r'relationshipKey: "([^"]+)"', about)))
        self.assertTrue(keys, "no relationship keys in AboutView")
        catalog = set()
        for line in GENERATE_LOCALIZATION.read_text(encoding="utf-8").splitlines():
            if "\t" in line:
                catalog.add(line.split("\t", 1)[0])
        for key in keys:
            with self.subTest(key=key):
                self.assertIn(key, catalog,
                              f"relationship label {key!r} is missing from "
                              f"the localization catalog")

    def test_open_source_references_doc_lists_all_projects(self):
        self.assertTrue(REFERENCES.is_file(),
                        "docs/OPEN_SOURCE_REFERENCES.md is missing")
        text = REFERENCES.read_text(encoding="utf-8")
        headings = re.findall(r"^## \d+\. ([^—\n]+?)(?: —|\n)",
                              text, flags=re.MULTILINE)
        self.assertEqual(sorted(headings), sorted(AUDIT_PROJECTS),
                         "the references doc must have one section per "
                         "audited project")
        # The NeoSpring no-license issue must stay recorded, not silently
        # dropped when the doc is edited.
        self.assertIn("无许可证声明", text)

    def test_feature_origin_matrix_covers_all_features(self):
        self.assertTrue(MATRIX.is_file(),
                        "docs/FEATURE_ORIGIN_MATRIX.md is missing")
        text = MATRIX.read_text(encoding="utf-8")
        headings = re.findall(r"^## \d+\. ([^\n]+)", text, flags=re.MULTILINE)
        self.assertEqual(len(headings), 16,
                         "the matrix must cover all 16 feature areas")
        for area in ("MobileGestalt", "一键解锁", "Apple Intelligence",
                     "eSIM", "安全写入", "备份与恢复", "设备指纹",
                     "智能兼容性诊断", "系统健康评分", "智能预设",
                     "启动图", "壁纸", "Respring", "签名", "SwiftUI", "3.0"):
            with self.subTest(area=area):
                self.assertIn(area, text)
        # The honesty guard: unimplemented features must stay listed as
        # unimplemented, never written as done.
        self.assertIn("未实现的功能", text)

    def test_no_pristine_patch_distribution_statement(self):
        for path in STALE_STATEMENT_FILES:
            with self.subTest(file=path.name):
                text = path.read_text(encoding="utf-8")
                self.assertNotIn(
                    "pristine v1.0.7 source plus the modification patch", text)
                self.assertNotIn("原始 v1.0.7 源码加修改补丁", text)

    def test_respring_implementation_removed(self):
        # License suspension, user decision 2026-11-14 (option c): the
        # NeoSpring/Ketamine WebKit respring implementation was removed,
        # not renamed. The shipped code must not contain any of its
        # symbols or the file that held them. The About page and docs
        # may still name the projects as suspended; they are covered by
        # the other tests, not by this one.
        self.assertFalse((ROOT / "GestaltX" / "NeoSpringView.swift").is_file(),
                         "GestaltX/NeoSpringView.swift must stay deleted")
        for marker in ("startNeoSpring", "NeoSpringWebView", "stopNeoSpring"):
            for path in sorted((ROOT / "GestaltX").glob("*.swift")):
                with self.subTest(marker=marker, file=path.name):
                    self.assertNotIn(marker,
                                     path.read_text(encoding="utf-8"))
        content = (ROOT / "GestaltX" / "ContentView.swift").read_text(
            encoding="utf-8")
        self.assertNotIn("NeoSpringView", content)
        self.assertNotIn("isRespringing", content)
        manager = (ROOT / "GestaltX" / "GestaltManager.swift").read_text(
            encoding="utf-8")
        self.assertNotIn("isRespringing", manager)
        self.assertNotIn("needsRespring", manager)
        # The replacement is a manual-restart prompt, not a silent
        # rename: the Tools action must offer a Restart Device button.
        self.assertIn('"Restart Device"', content)

    def test_about_marks_respring_projects_suspended(self):
        # License suspension, user decision 2026-11-14 (option c): the
        # Ketamine and NeoSpring entries must show the suspended
        # relationship and must not claim to ship in the IPA.
        text = ABOUT_VIEW.read_text(encoding="utf-8")
        for name in ("Ketamine", "NeoSpring"):
            lines = [line for line in text.splitlines()
                     if f'name: "{name}"' in line]
            self.assertEqual(len(lines), 1,
                             f"AboutView must have exactly one {name} entry")
            with self.subTest(project=name):
                self.assertIn('relationshipKey: "Suspended"', lines[0])
                self.assertIn("shippedInIPA: false", lines[0])


if __name__ == "__main__":
    unittest.main()

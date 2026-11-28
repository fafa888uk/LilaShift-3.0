import importlib.util
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "generate_apple_wiki_key_table.py"
GENERATED = ROOT / "GestaltX" / "AppleWikiKeyTable.swift"
CHINESE = ROOT / "GestaltX" / "MGKeyChineseNames.swift"
NOTICES = ROOT / "W4NOTICES.md"
SOURCE_URL = "https://theapplewiki.com/wiki/List_of_MobileGestalt_keys"


def load_generator():
    spec = importlib.util.spec_from_file_location(
        "generate_apple_wiki_key_table", GENERATOR
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SAMPLE_WIKITEXT = """Intro text, not a table.
{| class="wikitable sortable"
|+
!Key
!Hashed key
!iOS introduced
!iOS removed
!Device introduced
!Description
|-
|DeviceClass
|<code>+3Uf0Pm5F8Xy7Onyvko0vA</code>
|1.0
|
|
|Device class for this device. One of the kMGDeviceClass* constants defined below
|-
|arkit
|<code>67A3BpQkCRe1ihx0Me4lgg</code>
|
|
|
|The device is capable of using [[ARKit]].
|-
|NoDescriptionKey
|<code>AAAAAAAAAAAAAAAAAAAAAA</code>
|
|
|
|
|}
"""


class GeneratorTests(unittest.TestCase):
    def test_parser_reads_names_and_descriptions(self):
        gen = load_generator()
        entries = gen.parse_wikitext(SAMPLE_WIKITEXT)
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries["+3Uf0Pm5F8Xy7Onyvko0vA"][0], "DeviceClass")
        self.assertIn("Device class for this device", entries["+3Uf0Pm5F8Xy7Onyvko0vA"][1])
        # Wiki links are cleaned to their label; empty descriptions stay empty.
        self.assertEqual(
            entries["67A3BpQkCRe1ihx0Me4lgg"][1],
            "The device is capable of using ARKit.",
        )
        self.assertEqual(entries["AAAAAAAAAAAAAAAAAAAAAA"][1], "")

    def test_parser_rejects_bad_hashed_keys(self):
        gen = load_generator()
        bad = SAMPLE_WIKITEXT.replace("+3Uf0Pm5F8Xy7Onyvko0vA", "not-a-key!!")
        with self.assertRaises(ValueError):
            gen.parse_wikitext(bad)

    def test_swift_escaping(self):
        gen = load_generator()
        self.assertEqual(gen.swift_escape('a"b\\c'), 'a\\"b\\\\c')

    def test_render_carries_attribution(self):
        gen = load_generator()
        entries = gen.parse_wikitext(SAMPLE_WIKITEXT)
        output = gen.render(entries, "wiki revision 2026-11-28")
        self.assertIn("CC BY-SA 4.0", output)
        self.assertIn("The Apple Wiki", output)
        self.assertIn(SOURCE_URL, output)
        self.assertIn("Do not edit by hand", output)
        self.assertIn("static let count = 3", output)

    def test_generated_file_counts(self):
        # The committed file must be the generator's output for the live
        # wiki page (943 keys, 671 with descriptions; see records/w4-keytable.md).
        text = GENERATED.read_text(encoding="utf-8")
        self.assertIn("static let count = 943", text)
        names_section = text.split("static let names")[1].split("static let descriptions")[0]
        descriptions_section = text.split("static let descriptions")[1]
        names = re.findall(r'"([A-Za-z0-9+/=_-]{22})": "([^"]+)",', names_section)
        descriptions = re.findall(
            r'"([A-Za-z0-9+/=_-]{22})": "(.*)",', descriptions_section
        )
        self.assertEqual(len(names), 943)
        self.assertEqual(len({key for key, _ in names}), 943)
        self.assertEqual(len(descriptions), 671)
        self.assertTrue(
            {key for key, _ in descriptions} <= {key for key, _ in names}
        )
        self.assertIn("CC BY-SA 4.0", text)
        self.assertIn("The Apple Wiki", text)

    def test_chinese_map_counts(self):
        text = CHINESE.read_text(encoding="utf-8")
        names_section = text.split("static let names")[1].split("static let descriptions")[0]
        descriptions_section = text.split("static let descriptions")[1]
        names = dict(
            re.findall(r'"((?:[^"\\]|\\.)*)": "((?:[^"\\]|\\.)*)",', names_section)
        )
        descriptions = dict(
            re.findall(r'"((?:[^"\\]|\\.)*)": "((?:[^"\\]|\\.)*)",', descriptions_section)
        )
        self.assertEqual(len(names), 122)
        self.assertEqual(set(names), set(descriptions))
        self.assertTrue(all(value.strip() for value in names.values()))
        self.assertTrue(all(value.strip() for value in descriptions.values()))
        # No fabricated "translation" for untranslated keys: the map
        # only lists reviewed keys, and the missing-name label is separate.
        self.assertIn('static let missingChineseNameLabel = "暂无中文名"', text)

    def test_notices(self):
        text = NOTICES.read_text(encoding="utf-8")
        for required in (
            "worstgestalt",
            "GPL-3.0",
            "awesomenull",
            "Taj C",
            "forcequitOS",
            "CC BY-SA 4.0",
            "The Apple Wiki",
            "相同方式共享",
        ):
            self.assertIn(required, text)
        # What W4 deliberately did NOT port must be on record.
        for excluded in ("Nugget", "NeoSpring", "device spoofing", "bad_query"):
            self.assertIn(excluded, text)


if __name__ == "__main__":
    unittest.main()

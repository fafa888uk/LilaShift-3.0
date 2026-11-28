#!/usr/bin/env python3
"""Generate GestaltX/AppleWikiKeyTable.swift from The Apple Wiki.

Source: "List of MobileGestalt keys" (https://theapplewiki.com/wiki/List_of_MobileGestalt_keys),
fetched as wikitext through the MediaWiki API. This replaces the
upstream worstgestalt generator (tools/gen_keymap.py), which read the
wiki dump from the author's own machine path
(/home/awesomenull/.local/share/opencode/...) and could not be rerun
anywhere else.

Data license: the key table data is CC BY-SA 4.0, (c) The Apple Wiki
contributors. The generated Swift file carries that attribution and
must be redistributed under the same license (share-alike); the
surrounding Swift code is GPL-3.0-or-later, like the rest of LilaShift.

Usage:
    python3 scripts/generate_apple_wiki_key_table.py [--check] [--input FILE]
    python3 scripts/generate_apple_wiki_key_table.py --upstream PATH/TO/GestaltKeyMap.swift

Options:
    --input FILE     Parse a saved wikitext dump instead of fetching.
    --output FILE    Write the Swift file here (default:
                     GestaltX/AppleWikiKeyTable.swift, relative to the
                     repository root, i.e. the parent of scripts/).
    --check          Do not write; exit 1 if the generated output
                     differs from the committed file.
    --upstream FILE  Cross-check the parsed key set against a pinned
                     upstream GestaltKeyMap.swift (GoldensHQ/worstgestalt)
                     and report added/removed keys. Key sets must match;
                     description text may differ: upstream's generator
                     kept wikitext escape artefacts (e.g. "iOS \\>=4.2.1",
                     'YouTube")'), while this script cleans them.
"""
import argparse
import datetime
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

API_URL = (
    "https://theapplewiki.com/api.php"
    "?action=query&prop=revisions&titles=List_of_MobileGestalt_keys"
    "&rvprop=content&rvslots=main&format=json&formatversion=2"
)
SOURCE_URL = "https://theapplewiki.com/wiki/List_of_MobileGestalt_keys"
HASHED_RE = re.compile(r"^[A-Za-z0-9+/=_-]{20,30}$")

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "GestaltX" / "AppleWikiKeyTable.swift"


def fetch_wikitext() -> tuple[str, str]:
    """Fetch the wiki page; return (wikitext, revision date YYYY-MM-DD)."""
    request = urllib.request.Request(
        API_URL, headers={"User-Agent": "LilaShift-keytable-generator/1.0"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.load(response)
    pages = payload["query"]["pages"]
    if len(pages) != 1:
        raise ValueError(f"expected 1 page, got {len(pages)}")
    revision = pages[0]["revisions"][0]
    wikitext = revision["slots"]["main"]["content"]
    # The revision date (not today) goes in the header, so --check stays
    # stable until the wiki page itself changes.
    retrieved = revision.get("timestamp", "")[:10] or datetime.datetime.now(
        datetime.timezone.utc
    ).strftime("%Y-%m-%d")
    return wikitext, retrieved


def clean_description(raw: str) -> str:
    """Wikitext description -> plain text, same cleaning upstream used plus fixes.

    Upstream's generator (worstgestalt tools/gen_keymap.py) unescaped HTML
    entities, turned markdown links into labels and stripped tags, but kept
    wikitext backslash escapes (``\\.``, ``\\>``, ``\\_``, ``\\*``) and
    double spaces in the output. Those are artefacts of the wiki source
    markup, not part of the description, so they are removed here.
    """
    text = html.unescape(raw)
    text = re.sub(r"\[\[([^|\]]+)\|([^\]]+)\]\]", r"\2", text)
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("\\-", "-").replace("\\.", ".").replace("\\_", "_")
    text = text.replace("\\>", ">").replace("\\*", "*").replace("\\\\", "\\")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def parse_wikitext(wikitext: str) -> dict:
    """Parse the wiki table into {hashed key: (plain name, description)}."""
    rows: list[list[str]] = []
    current: list[str] = []
    in_table = False
    for line in wikitext.splitlines():
        if line.startswith("{|"):
            in_table = True
            continue
        if in_table and line.startswith("|}"):
            in_table = False
            break
        if not in_table:
            continue
        if line.startswith("|-"):
            if current:
                rows.append(current)
            current = []
        elif line.startswith("|") and not line.startswith("|-"):
            current.extend(cell.strip() for cell in line[1:].split("||"))
    if current:
        rows.append(current)

    parsed: dict[str, tuple[str, str]] = {}
    for row in rows:
        if len(row) < 2 or row[0].startswith("!") or row[0] == "Key":
            continue
        plain = html.unescape(row[0].strip())
        hashed = re.sub(r"</?code>", "", row[1]).strip().strip("`")
        if not plain or not hashed:
            continue
        if not HASHED_RE.match(hashed):
            raise ValueError(f"bad hashed key {hashed!r} for plain key {plain!r}")
        description = clean_description(row[5]) if len(row) >= 6 else ""
        previous = parsed.get(hashed)
        if previous is None or len(description) > len(previous[1]):
            parsed[hashed] = (plain, description)
    return parsed


def swift_escape(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )


def render(entries: dict, retrieved: str) -> str:
    names = sorted(entries)
    descriptions = sorted(h for h, (_, d) in entries.items() if d)
    lines = [
        "// SPDX-License-Identifier: GPL-3.0-or-later",
        "//",
        "//  AppleWikiKeyTable.swift — GENERATED from The Apple Wiki",
        "//  (https://theapplewiki.com/wiki/List_of_MobileGestalt_keys),",
        f"//  ({retrieved}), by scripts/generate_apple_wiki_key_table.py.",
        "//  Do not edit by hand: rerun the generator instead.",
        "//",
        "//  Data license: the key table data below is CC BY-SA 4.0,",
        "//  (c) The Apple Wiki contributors. If you redistribute this",
        "//  table, you must give the same attribution and share it",
        "//  under the same license (CC BY-SA 4.0). The surrounding",
        "//  Swift code is GPL-3.0-or-later.",
        "//",
        "",
        "/// The Apple Wiki MobileGestalt key table (W4).",
        "///",
        "/// Plain key names and English descriptions for the ~940 known",
        "/// MobileGestalt keys, taken verbatim (modulo wiki-markup",
        "/// cleaning) from The Apple Wiki. No key here is guessed: every",
        "/// row comes from the wiki table above, and `names`/`descriptions`",
        "/// are keyed by the 22-character obfuscated key, so they line up",
        "/// with the keys the app already reads from the cache.",
        "///",
        "/// Both dictionaries are `static let`, so they cost nothing at",
        "/// launch: Swift initializes them lazily on first access, and",
        "/// `MGKeysTable` only touches them when the user opens the key",
        "/// table or types a search.",
        "enum AppleWikiKeyTable {",
        "    /// Number of keys in the table (names and descriptions agree).",
        f"    static let count = {len(entries)}",
        "",
        "    /// Obfuscated key -> plain key name (every key has one).",
        "    static let names: [String: String] = [",
    ]
    for hashed in names:
        plain, _ = entries[hashed]
        lines.append(f'        "{swift_escape(hashed)}": "{swift_escape(plain)}",')
    lines.append("    ]")
    lines.append("")
    lines.append("    /// Obfuscated key -> English description (only keys that have one).")
    lines.append("    static let descriptions: [String: String] = [")
    for hashed in descriptions:
        _, description = entries[hashed]
        lines.append(f'        "{swift_escape(hashed)}": "{swift_escape(description)}",')
    lines.append("    ]")
    lines.append("")
    lines.append("    /// The plain key name for an obfuscated key, if the table knows it.")
    lines.append("    static func plainName(forHashedKey key: String) -> String? {")
    lines.append("        names[key]")
    lines.append("    }")
    lines.append("")
    lines.append("    /// The English description for an obfuscated key, if the table has one.")
    lines.append("    static func description(forHashedKey key: String) -> String? {")
    lines.append("        descriptions[key]")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def parse_upstream(path: Path) -> tuple[dict, dict]:
    """Parse a worstgestalt GestaltKeyMap.swift into (names, descriptions)."""
    text = path.read_text(encoding="utf-8")

    def unescape(value: str) -> str:
        return value.replace('\\"', '"').replace("\\\\", "\\")

    names_section = text.split("static let names", 1)[1].split(
        "static let descriptions", 1
    )[0]
    descriptions_section = text.split("static let descriptions", 1)[1]
    names = {
        unescape(plain): hashed
        for plain, hashed in re.findall(
            r'"((?:[^"\\]|\\.)*)": "([A-Za-z0-9+/=_-]{20,30})",', names_section
        )
    }
    descriptions = {
        hashed: unescape(desc)
        for hashed, desc in re.findall(
            r'"([A-Za-z0-9+/=_-]{20,30})": "((?:[^"\\]|\\.)*)",',
            descriptions_section,
        )
    }
    return names, descriptions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="saved wikitext dump (skip fetching)")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="compare only, do not write")
    parser.add_argument("--upstream", type=Path, help="pinned upstream GestaltKeyMap.swift to cross-check")
    args = parser.parse_args()

    if args.input is not None:
        wikitext = args.input.read_text(encoding="utf-8")
        retrieved = f"local dump {args.input.name}"
    else:
        wikitext, revision_date = fetch_wikitext()
        retrieved = f"wiki revision {revision_date}"
    entries = parse_wikitext(wikitext)
    with_descriptions = sum(1 for _, d in entries.values() if d)
    non_22 = sorted(h for h in entries if len(h) != 22)
    print(f"keys: {len(entries)}, with description: {with_descriptions}, "
          f"without description: {len(entries) - with_descriptions}")
    if non_22:
        print(f"warning: {len(non_22)} hashed keys are not 22 characters: {non_22[:5]}",
              file=sys.stderr)

    if args.upstream is not None:
        upstream_names, upstream_descriptions = parse_upstream(args.upstream)
        upstream_keys = set(upstream_names.values())
        wiki_keys = set(entries)
        added = sorted(wiki_keys - upstream_keys)
        removed = sorted(upstream_keys - wiki_keys)
        print(f"upstream keys: {len(upstream_keys)}, added: {len(added)}, removed: {len(removed)}")
        if added:
            print("added vs upstream:", added[:10])
        if removed:
            print("removed vs upstream:", removed[:10])
        desc_diff = sum(
            1
            for h in wiki_keys & upstream_keys
            if entries[h][1] != upstream_descriptions.get(h, "")
        )
        print(f"descriptions differing from upstream (escape cleanups): {desc_diff}")
        if added or removed:
            print("error: key set differs from upstream", file=sys.stderr)
            return 1

    output = render(entries, retrieved)
    if args.check:
        current = args.output.read_text(encoding="utf-8")
        if current == output:
            print(f"OK: {args.output} is up to date")
            return 0
        print(f"DIFF: {args.output} differs from regenerated output", file=sys.stderr)
        return 1
    args.output.write_text(output, encoding="utf-8")
    print(f"wrote {args.output} ({len(output)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

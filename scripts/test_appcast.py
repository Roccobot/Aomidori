#!/usr/bin/env python3
"""Tests of scripts/appcast.py: python3 scripts/test_appcast.py (runs on the box too)."""
import re
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.dont_write_bytecode = True  # no __pycache__ in scripts/
sys.path.insert(0, str(Path(__file__).resolve().parent))
import appcast  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
NS = {"sparkle": appcast.SPARKLE_NS}
DATE = "Fri, 09 Oct 2026 17:00:00 GMT"


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.published = (ROOT / "publish/appcast.xml").read_text(encoding="utf-8")
        # The published channel without its items: the tests add their own.
        self.empty = re.sub(r"    <item>.*?</item>\n", "", self.published, flags=re.S)

    def test_the_published_appcast_is_well_formed(self):
        channel = ET.fromstring(self.published).find("channel")
        self.assertEqual(channel.findtext("link"), "https://roccobot.github.io/Aomidori/")
        builds = [int(b) for b in appcast.builds(self.published)]
        self.assertEqual(builds, sorted(set(builds), reverse=True), "newest first, each build once")
        for item in channel.findall("item"):
            version = item.findtext("sparkle:shortVersionString", namespaces=NS)
            self.assertEqual(item.find("enclosure").get("url"), appcast.zip_url(version))

    def test_an_item_carries_what_sparkle_needs(self):
        text = appcast.add(self.empty, appcast.item(9, "0.52", 2745000, "c2ln+/w==", date=DATE))
        item = ET.fromstring(text).find("channel/item")
        self.assertEqual(item.findtext("sparkle:version", namespaces=NS), "9")
        self.assertEqual(item.findtext("sparkle:shortVersionString", namespaces=NS), "0.52")
        self.assertEqual(item.findtext("sparkle:minimumSystemVersion", namespaces=NS), "27.0")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"),
                         "https://github.com/Roccobot/Aomidori/releases/download/v0.52/Aomidori-0.52.zip")
        self.assertEqual(enclosure.get("length"), "2745000")
        self.assertEqual(enclosure.get(f"{{{appcast.SPARKLE_NS}}}edSignature"), "c2ln+/w==")
        self.assertIn("releases/tag/v0.52", item.findtext("description"))

    def test_newest_first_and_never_twice(self):
        text = appcast.add(self.empty, appcast.item(9, "0.52", 1, "a", date=DATE))
        text = appcast.add(text, appcast.item(10, "0.53", 1, "b", date=DATE))
        self.assertEqual(appcast.builds(text), ["10", "9"])
        with self.assertRaises(ValueError):
            appcast.add(text, appcast.item(9, "0.52", 1, "a", date=DATE))

    def test_bad_inputs_are_refused(self):
        for args in [("9a", "0.52", 1, "s"), (9, "0.5.2", 1, "s"), (9, "0.52", 0, "s")]:
            with self.assertRaises(ValueError):
                appcast.item(*args)


if __name__ == "__main__":
    unittest.main()

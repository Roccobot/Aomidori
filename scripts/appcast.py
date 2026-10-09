#!/usr/bin/env python3
"""Adds a release to Aomidori's Sparkle appcast (publish/appcast.xml), newest first.

    scripts/appcast.py add --appcast publish/appcast.xml --build 9 --version 0.52 \
        --length 2745000 --signature BASE64 [--min-system 27.0] [--date "RFC 822 date"]

The item points at the ZIP of the GitHub release `v<version>` and at its release page; the
signature and length are what Sparkle's `sign_update` prints for that ZIP. A build number that
is already in the appcast is refused, so a release cannot be listed twice. scripts/release.sh
calls this; the tests are in scripts/test_appcast.py.

Author: Rocco Casadei, a.k.a. Roccobot
"""
import argparse
import email.utils
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape

REPO = "https://github.com/Roccobot/Aomidori"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def zip_url(version):
    return f"{REPO}/releases/download/v{version}/Aomidori-{version}.zip"


def release_page(version):
    return f"{REPO}/releases/tag/v{version}"


def item(build, version, length, signature, min_system="27.0", date=None):
    """The <item> of one release, indented for the channel."""
    if not re.fullmatch(r"\d+", str(build)):
        raise ValueError(f"build must be CFBundleVersion, a whole number: {build!r}")
    if not re.fullmatch(r"\d+\.\d{2}", version):
        raise ValueError(f"version must be SlimVer x.xx: {version!r}")
    if int(length) <= 0:
        raise ValueError("length must be the ZIP's size in bytes")
    date = date or email.utils.formatdate(usegmt=True)
    notes = (f'<p>Aomidori {version}. '
             f'<a href="{release_page(version)}">Release notes on GitHub</a>.</p>')
    return f"""    <item>
      <title>Aomidori {escape(version)}</title>
      <pubDate>{escape(date)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(min_system)}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{release_page(version)}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{zip_url(version)}" length="{int(length)}" type="application/octet-stream" sparkle:edSignature="{escape(signature, {'"': '&quot;'})}"/>
    </item>
"""


def builds(xml_text):
    root = ET.fromstring(xml_text)
    return [e.text for e in root.iter(f"{{{SPARKLE_NS}}}version")]


def add(xml_text, new_item):
    """The appcast with the item placed before every other item (newest first)."""
    new_build = ET.fromstring(f'<x xmlns:sparkle="{SPARKLE_NS}">{new_item}</x>') \
        .find(f".//{{{SPARKLE_NS}}}version").text
    if new_build in builds(xml_text):
        raise ValueError(f"build {new_build} is already in the appcast")
    anchor = xml_text.find("    <item>")
    if anchor < 0:
        anchor = xml_text.index("  </channel>")
    result = xml_text[:anchor] + new_item + xml_text[anchor:]
    ET.fromstring(result)  # still well formed
    return result


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    a = sub.add_parser("add")
    a.add_argument("--appcast", type=Path, required=True)
    a.add_argument("--build", required=True)
    a.add_argument("--version", required=True)
    a.add_argument("--length", type=int, required=True)
    a.add_argument("--signature", required=True)
    a.add_argument("--min-system", default="27.0")
    a.add_argument("--date")
    args = parser.parse_args(argv)
    text = args.appcast.read_text(encoding="utf-8")
    new = add(text, item(args.build, args.version, args.length, args.signature, args.min_system, args.date))
    args.appcast.write_text(new, encoding="utf-8")
    print(f"appcast: Aomidori {args.version} (build {args.build}) added to {args.appcast}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except ValueError as error:
        print(f"appcast: {error}", file=sys.stderr)
        sys.exit(1)

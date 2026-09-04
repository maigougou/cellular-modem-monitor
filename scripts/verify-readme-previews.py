#!/usr/bin/env python3
"""Verify the bilingual gallery's asset links, ordering and paired dimensions."""

from html.parser import HTMLParser
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
SCENES = [
    "overview", "sa", "nsa", "ca", "connection", "radio", "nr-ca", "lte-ca",
    "controls", "speedtest", "details", "settings",
]


class Gallery(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tables = []
        self.images = None
        self.cell = {}
        self.link = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "table":
            assert self.images is None, "Nested gallery tables"
            self.images = []
        elif tag == "td":
            self.cell = attrs
        elif tag == "a":
            self.link = attrs.get("href")
        elif tag == "img":
            assert self.images is not None, "Image is not inside a theme pair"
            assert self.cell.get("valign") == "top", "Images must align at the top"
            assert self.cell.get("width") == "50%", "Columns must have equal widths"
            assert attrs.get("alt"), "Preview needs alt text"
            assert self.link == attrs["src"], "Image must link to its full-size asset"
            self.images.append(attrs["src"])

    def handle_endtag(self, tag):
        if tag == "table":
            self.tables.append(self.images)
            self.images = None
        elif tag == "a":
            self.link = None


def dimensions(path):
    with path.open("rb") as source:
        header = source.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", f"Not a PNG: {path}"
    return struct.unpack(">II", header[16:24])


for filename, language in [("README.md", "en"), ("README.zh-CN.md", "zh-CN")]:
    document = (ROOT / filename).read_text()
    block = document.split("<!-- BEGIN README PREVIEWS -->", 1)[1].split("<!-- END README PREVIEWS -->", 1)[0]
    assert block.count("<details>") == block.count("</details>") == len(SCENES) - 1
    gallery = Gallery()
    gallery.feed(block)
    assert len(gallery.tables) == len(SCENES)
    for scene, pair in zip(SCENES, gallery.tables):
        expected = [f"assets/previews/{language}/{scene}-{theme}.png" for theme in ("light", "dark")]
        assert pair == expected, f"Incorrect theme order or scene: {filename}: {pair}"
        sizes = [dimensions(ROOT / name) for name in pair]
        assert sizes[0] == sizes[1], f"Theme dimensions differ: {scene}: {sizes}"
        assert sizes[0][0] == 840 and sizes[0][1] > 100, f"Unexpected export size: {scene}"
    print(f"{filename}: {len(SCENES)} light/dark pairs verified")

print("48 localized PNGs verified; all images are linked, paired and top-aligned.")

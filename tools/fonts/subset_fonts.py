#!/usr/bin/env python3
"""Subset the Thai UI fonts to the characters zorx uses and write them as WOFF2.

Source TTFs live in art_source/fonts/ (full Google Fonts files, with their OFL.txt).
Only the subset WOFF2 files in art/fonts/ ship with the game, to keep the web data pack small.

Weights (Boss decision 2026-10-12): Taviraj SemiBold for display/headings, Sarabun Regular +
SemiBold for body text. The subset keeps the whole Thai block (U+0E00-U+0E7F, so any Thai string
renders), basic Latin + Latin-1 and the punctuation/symbols the UI shows (gold, +/-, %, arrows...).

Run (fonttools must be importable; see SKILL note, installed with --user):
    PATH="$HOME/Library/Python/3.10/bin:$PATH" python3 tools/fonts/subset_fonts.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art_source", "fonts")
OUT = os.path.join(ROOT, "art", "fonts")

# What the UI needs. Whole Thai block + Latin + the digits/punctuation/symbols seen in screens.
# U+2190-2193 arrows (←↑→↓, used in nav and the trip line), U+2022 bullet, U+2026 ellipsis,
# U+00D7 multiply (shown as x in sizes), U+2013/2014 dashes, U+2018-201D quotes.
UNICODES = (
    "U+0020-007E,"          # basic Latin (ASCII printable)
    "U+00A0-00FF,"          # Latin-1 supplement (accents, ©, °, ×, etc.)
    "U+0E00-0E7F,"          # Thai
    "U+2013-2014,"          # en/em dash
    "U+2018-2019,U+201C-201D,"  # curly quotes
    "U+2022,U+2026,"        # bullet, ellipsis
    "U+2190-2193,"          # arrows
    "U+00D7,U+2212"         # multiply, minus
)

# (source relative path, output file name)
FONTS = [
    ("sarabun/Sarabun-Regular.ttf",  "Sarabun-Regular.woff2"),
    ("sarabun/Sarabun-SemiBold.ttf", "Sarabun-SemiBold.woff2"),
    ("taviraj/Taviraj-SemiBold.ttf", "Taviraj-SemiBold.woff2"),
]


def main() -> int:
    try:
        from fontTools.subset import main as subset_main
    except ImportError:
        print("fonttools is not importable. Install with:  python3 -m pip install --user fonttools brotli")
        return 1
    os.makedirs(OUT, exist_ok=True)
    for src_rel, out_name in FONTS:
        src = os.path.join(SRC, src_rel)
        dst = os.path.join(OUT, out_name)
        argv = [
            src,
            "--unicodes=" + UNICODES,
            "--layout-features=*",      # keep Thai mark positioning (GPOS/GSUB)
            "--flavor=woff2",
            "--output-file=" + dst,
            "--desubroutinize",
            "--name-IDs=*",
            "--drop-tables+=DSIG",
        ]
        subset_main(argv)
        kb = os.path.getsize(dst) / 1024.0
        print(f"{out_name:26} {kb:6.1f} KB")
    total = sum(os.path.getsize(os.path.join(OUT, o)) for _, o in FONTS) / 1024.0
    print(f"{'TOTAL':26} {total:6.1f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())

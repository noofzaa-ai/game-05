"""Girth check of the level 15 race outfits against the starter outfits, from silhouettes rendered by
tools/shots/race_outfit_shots.gd (ZORX_ONLY=sil ZORX_TAG=<tag>): build/race_outfits/sil/<tag>_<race>_<look>_<front|side>.png.
Run: python -I tools/shots/girth_sheet.py <tag> [<out folder>]
Prints, per race and view, the silhouette width of the whole outfit at chest, waist, hips, thigh and calf height (level 15 as a
percentage of the starter) and writes <out>/girth_<tag>_<race>.png: starter (red) over level 15 (blue), front and side.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SIL = os.path.join(ROOT, "build", "race_outfits", "sil")
RACES = ["human", "viking", "elf", "runeborn"]
# skeleton-local metres: the camera is centred at y 0.3 and frames 0.72 high, so 1 m = 1000 / 0.72 px
PX_PER_M = 1000 / 0.72


def row_of(y_m):
    return int(round(1000 * 0.5 + (0.3 - y_m) * PX_PER_M))


BANDS = {"chest": (0.225, 0.27), "waist": (0.185, 0.225), "hips": (0.14, 0.185), "thigh": (0.09, 0.14), "calf": (0.035, 0.085)}


def mask(path):
    return np.asarray(Image.open(path).convert("RGBA").getchannel("A")) > 20


def band_width(m, lo, hi):
    rows = range(row_of(hi), row_of(lo))
    widths = [np.ptp(np.nonzero(m[r])[0]) + 1 if m[r].any() else 0 for r in rows]
    area = sum(int(m[r].sum()) for r in rows)
    return float(np.mean(widths)), area / max(1, len(rows))


def main():
    tag = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "build", "race_outfits", "sil")
    os.makedirs(out, exist_ok=True)
    worst = 0.0
    for race in RACES:
        sheet = Image.new("RGB", (1400, 1000), (236, 232, 222))
        for k, view in enumerate(("front", "side")):
            a = mask(os.path.join(SIL, "%s_%s_starter_%s.png" % (tag, race, view)))
            c = mask(os.path.join(SIL, "%s_%s_lv15_%s.png" % (tag, race, view)))
            img = np.full(a.shape + (3,), (236, 232, 222), np.uint8)
            img[a] = (210, 60, 60)
            img[c] = (60, 90, 210)
            img[a & c] = (120, 70, 120)
            sheet.paste(Image.fromarray(img), (k * 700, 0))
            line = []
            for band, (lo, hi) in BANDS.items():
                wa, aa = band_width(a, lo, hi)
                wc, ac = band_width(c, lo, hi)
                line.append("%s %3.0f%%/%3.0f%%" % (band, 100 * wc / max(wa, 1), 100 * ac / max(aa, 1)))
                worst = min(worst, wc / max(wa, 1) - 1.0)
            print("%-9s %-5s (width%% / filled%% of starter) %s" % (race, view, "  ".join(line)))
        d = ImageDraw.Draw(sheet)
        d.text((8, 6), "%s %s: red = starter, blue = lv15, purple = overlap; front | side" % (tag, race), fill=(20, 20, 20))
        sheet.save(os.path.join(out, "girth_%s_%s.png" % (tag, race)))


if __name__ == "__main__":
    main()

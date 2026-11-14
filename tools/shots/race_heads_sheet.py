"""Contact sheets for tools/shots/race_heads_shots.gd (art_source/codex_review/race_heads_2026-11-14/).
Run: python -I tools/shots/race_heads_sheet.py"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DIR = os.path.join(ROOT, "art_source", "codex_review", "race_heads_2026-11-14")
RACES = ["human", "elf", "viking", "runeborn"]
HAIRS = ["a", "b", "c", "e", "f", "g", "i"]
VIEWS = ["front", "q34", "side", "back"]


def sheet(rows, out, label_w=110):
    """rows: [(label, [file, ...])]"""
    tiles = [[Image.open(os.path.join(DIR, f)) for f in files] for _, files in rows]
    w, h = tiles[0][0].size
    cols = max(len(t) for t in tiles)
    img = Image.new("RGB", (label_w + cols * w, len(rows) * h), "white")
    draw = ImageDraw.Draw(img)
    for r, (label, _) in enumerate(rows):
        draw.text((6, r * h + h // 2), label, fill="black")
        for c, tile in enumerate(tiles[r]):
            img.paste(tile, (label_w + c * w, r * h))
    img.save(os.path.join(DIR, out))
    print(out, img.size)


for look in ["card", "toon"]:
    sheet([(race, ["%s_%s_%s_%s.png" % (look, kind, race, v) for kind in ["body", "head"] for v in ["front", "q34"]])
           for race in RACES], "sheet_%s.png" % look)
for hair in HAIRS:
    sheet([(race, ["hair_%s_%s_%s.png" % (hair, race, v) for v in VIEWS]) for race in RACES], "sheet_hair_%s.png" % hair)

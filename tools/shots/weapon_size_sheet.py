"""Size-overlay sheet of the level-15 race weapons against the level-1 ones, from the bind-pose vertices of the GLB files (no render):
class starter weapon (red), interim MID race file (green), level-15 file (blue), three views (side z-y, front x-y, top x-z),
one sheet per race x piece. Run: python -I tools/shots/weapon_size_sheet.py <out folder>
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "items"))
sys.path.insert(0, os.path.join(ROOT, "tools", "characters"))
import split_race_weapons_lv15 as w  # noqa: E402
import split_studio05_hair as glb  # noqa: E402

RACES = ["human", "viking", "elf", "runeborn"]
FILES = {"sword_shield": "| Sword", "shield": "| Shield", "greatsword": "| Sword", "longbow": "| Bow", "magic": "| Staff"}
GEAR = {"sword_shield": "armor_sword_shield", "shield": "armor_sword_shield", "greatsword": "armor_greatsword", "longbow": "armor_longbow", "magic": "armor_magic"}
VIEWS = [("side (z, y)", 2, 1), ("front (x, y)", 0, 1), ("top (x, z)", 0, 2)]
COLORS = {"class": (220, 60, 60), "mid": (60, 170, 80), "lv15": (60, 90, 230)}


def verts(path, kind=None):
    js, binary = glb.read_glb(path)
    parts = [w.mesh_arrays(js, binary, n["name"])[0] for n in js["nodes"] if "mesh" in n and (kind is None or kind in n["name"])]
    return np.concatenate(parts)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    size = 420
    for piece, kind in FILES.items():
        for race in RACES:
            sets = {"class": verts(os.path.join(ROOT, "art", "characters", "studio05", "v1111", "outfits", GEAR[piece] + ".glb"), kind),
                    "mid": verts(os.path.join(ROOT, "art", "weapons", "race_" + race, piece + ".glb")),
                    "lv15": verts(os.path.join(ROOT, "art", "weapons", "race_" + race, piece + "_lv15.glb"))}
            sheet = Image.new("RGB", (3 * size, size + 22), (236, 232, 222))
            d = ImageDraw.Draw(sheet)
            for k, (title, a, b) in enumerate(VIEWS):
                everything = np.concatenate(list(sets.values()))
                lo = everything[:, [a, b]].min(0)
                span = (everything[:, [a, b]].max(0) - lo).max() * 1.1
                scale = (size - 30) / span
                d.text((k * size + 6, 4), "%s %s - %s" % (race, piece, title), fill=(20, 20, 20))
                for name, pts in sets.items():
                    for x, y in pts[:, [a, b]]:
                        px = k * size + 15 + (x - lo[0]) * scale
                        py = 22 + size - 15 - (y - lo[1]) * scale
                        d.ellipse([px - 1.2, py - 1.2, px + 1.2, py + 1.2], fill=COLORS[name])
            d.text((3 * size - 330, 4), "red: lv1 class weapon  green: MID file  blue: lv15", fill=(20, 20, 20))
            sheet.save(os.path.join(out, "size_%s_%s.png" % (piece, race)))
    print("size sheets in", out)


if __name__ == "__main__":
    main()

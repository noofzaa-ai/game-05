"""Build the MID-tier race armour (Boss 2026-11-16): art/armor/race_shared/<race>_<slot>_mid.glb x 16 + race_wardrobe_atlas_mid.jpg.

Method (honest scope): the mid pieces are the starter meshes (same vertices, joints, inverse binds, weights, UVs and
budgets, byte for byte) with a second, race-graded atlas. Each race's UV islands (found by rasterising that race's 4 pieces
into the atlas) are re-graded: richer cloth in the race colour, brighter steel/silver, gold trim, and for Runeborn lit rune
tint. No skeleton change. Pure glTF surgery with the helpers of tools/characters/split_studio05_hair.py.
Run: python -I tools/items/build_mid_armor.py   (repo root)
"""
import colorsys, os, sys
import numpy as np
from PIL import Image, ImageDraw
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "characters"))
import split_studio05_hair as glb  # noqa: E402

DIR = os.path.join(ROOT, "art", "armor", "race_shared")
RACES = ["human", "viking", "elf", "runeborn"]
SLOTS = ["shirt", "pants", "armband", "shoes"]
ATLAS_MID = "race_wardrobe_atlas_mid.jpg"
S = 2048


def island_mask(race):
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    for slot in SLOTS:
        js, b = glb.read_glb(os.path.join(DIR, "%s_%s.glb" % (race, slot)))
        prim = js["meshes"][0]["primitives"][0]
        uv = np.frombuffer(glb.accessor_bytes(js, b, prim["attributes"]["TEXCOORD_0"]), "<f4").reshape(-1, 2)
        idx = np.frombuffer(glb.accessor_bytes(js, b, prim["indices"]), "<u2").reshape(-1, 3)
        for tri in idx:
            d.polygon([(float(uv[i][0]) * S, float(uv[i][1]) * S) for i in tri], fill=255)
    m = np.asarray(mask) > 0
    # grow 3 px so bilinear/mip bleed at island edges is graded too
    for _ in range(3):
        m = m | np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1)
    return m


def rgb2hsv(a):
    return np.asarray(Image.fromarray(a.astype(np.uint8)).convert("HSV")).astype(float) / 255.0


def hsv2rgb(h):
    return np.asarray(Image.fromarray((np.clip(h, 0, 1) * 255).astype(np.uint8), "HSV").convert("RGB")).astype(float)


def grade(rgb, race):
    """rgb float 0..255 (n,3) for one race's pixels -> graded."""
    hsv = rgb2hsv(rgb.reshape(-1, 1, 3)).reshape(-1, 3)
    h, s, v = hsv[:, 0], hsv[:, 1], hsv[:, 2]
    metal = (s < 0.22) & (v > 0.30)       # steel / silver / bone
    trim = (v > 0.72) & (s > 0.38) & (s < 0.7) & ((h > 0.08) & (h < 0.18))  # pale yellows -> gold trim
    cloth = ~metal
    out = hsv.copy()
    if race == "human":     # banner blue + steel + gold trim
        out[cloth, 0] = 0.60 + (h[cloth] - 0.60) * 0.15
        out[cloth, 1] = np.clip(s[cloth] * 1.5 + 0.28, 0, 0.85)
        out[cloth, 2] = np.clip(v[cloth] * 1.25 + 0.06, 0, 1)
        out[metal, 0] = 0.60; out[metal, 1] = np.clip(s[metal] + 0.10, 0, 0.3)
        out[metal, 2] = np.clip(v[metal] * 1.3 + 0.10, 0, 1)
    elif race == "viking":  # deep red-brown leather, cold dark iron, bright fur
        out[cloth, 0] = 0.015 + (h[cloth] - 0.04) * 0.2
        out[cloth, 1] = np.clip(s[cloth] * 1.35 + 0.18, 0, 0.9)
        out[cloth, 2] = np.clip(v[cloth] * 1.15 + 0.04, 0, 1)
        out[metal, 0] = 0.58; out[metal, 1] = np.clip(s[metal] + 0.05, 0, 0.2)
        out[metal, 2] = np.clip(v[metal] * 1.45 + 0.05, 0, 1)
    elif race == "elf":     # leaf green, silver
        out[cloth, 0] = 0.30 + (h[cloth] - 0.30) * 0.1
        out[cloth, 1] = np.clip(s[cloth] * 0.9 + 0.08, 0, 0.45)
        out[cloth, 2] = np.clip(v[cloth] * 0.9 + 0.02, 0, 0.7)
        out[metal, 0] = 0.50; out[metal, 1] = np.clip(s[metal] + 0.04, 0, 0.18)
        out[metal, 2] = np.clip(v[metal] * 1.45 + 0.12, 0, 1)
    else:                   # runeborn: dark stone, lit rune cyan on the bright parts
        out[cloth, 0] = 0.74 + (h[cloth] - 0.74) * 0.2
        out[cloth, 1] = np.clip(s[cloth] * 1.3 + 0.1, 0, 0.8)
        out[cloth, 2] = np.clip(v[cloth] * 0.9, 0, 1)
        out[cloth, 2] = np.clip(v[cloth] * 0.8, 0, 1)
        rune = (v > 0.78) | (metal & (v > 0.5))
        out[rune, 0] = 0.50; out[rune, 1] = 0.6; out[rune, 2] = np.clip(0.35 + v[rune] * 0.5, 0, 0.85)
    gold = trim
    out[gold, 0] = 0.12; out[gold, 1] = 0.6 if race == 'elf' else 0.8; out[gold, 2] = 0.9
    return hsv2rgb(out.reshape(-1, 1, 3)).reshape(-1, 3)


def main():
    atlas = np.asarray(Image.open(os.path.join(DIR, "race_wardrobe_atlas.jpg")).convert("RGB")).astype(float)
    result = atlas.copy()
    for race in RACES:
        m = island_mask(race)
        result[m] = grade(atlas[m], race)
        print(race, "island texels", int(m.sum()))
    Image.fromarray(result.astype(np.uint8)).save(os.path.join(DIR, ATLAS_MID), quality=90)
    total = 0
    for race in RACES:
        for slot in SLOTS:
            js, b = glb.read_glb(os.path.join(DIR, "%s_%s.glb" % (race, slot)))
            js["images"][0]["uri"] = ATLAS_MID
            js.setdefault("extras", {})["zorx_source"] = "%s_%s.glb regraded atlas (mid tier)" % (race, slot)
            out = os.path.join(DIR, "%s_%s_mid.glb" % (race, slot))
            glb.write_glb(out, js, b)
            nj, nb = glb.read_glb(out)
            oj, ob = glb.read_glb(os.path.join(DIR, "%s_%s.glb" % (race, slot)))
            n0, n1 = list(glb.meshed(oj).values())[0], list(glb.meshed(nj).values())[0]
            assert glb.rig_hash(nj, nb) == glb.rig_hash(oj, ob) and glb.mesh_hash(nj, nb, n1) == glb.mesh_hash(oj, ob, n0)
            tris = nj["accessors"][js["meshes"][0]["primitives"][0]["indices"]]["count"] // 3
            total += tris
            print("  %-22s %5d tris" % (os.path.basename(out), tris))
    print("total tris", total)


if __name__ == "__main__":
    main()

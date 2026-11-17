"""Review sheets for the level-15 race weapons (frames made by tools/shots/race_outfit_shots.gd ZORX_ONLY=wcompare).
Run: python -I tools/shots/weapon_sheet.py <out folder>
Writes <out>/weapons_<class>_<race>.png: a row each for the class starter weapon (level 1), the interim MID race file and the
level-15 file; columns idle front, idle side, run side, skill frame.
"""
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "build", "race_outfits", "wcompare")
CLASSES = ["sword_shield", "greatsword", "longbow", "magic"]
RACES = ["human", "viking", "elf", "runeborn"]
LOOKS = [("start", "lv1 class weapon"), ("mid", "MID race file"), ("lv15", "lv15")]
POSES = ["idle_front", "idle_side", "run_side", "skill"]


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    w, h = 300, 400
    for cls in CLASSES:
        for race in RACES:
            sheet = Image.new("RGB", (len(POSES) * w, len(LOOKS) * h), (40, 40, 44))
            d = ImageDraw.Draw(sheet)
            for k, (look, label) in enumerate(LOOKS):
                for c, pose in enumerate(POSES):
                    sheet.paste(Image.open(os.path.join(SRC, "%s_%s_%s_%s.png" % (cls, race, look, pose))).convert("RGB"), (c * w, k * h))
                    text = "%s | %s | %s" % (race, label, pose)
                    d.rectangle([c * w + 2, k * h + 2, c * w + 2 + 7 * len(text) + 8, k * h + 16], fill=(20, 20, 24))
                    d.text((c * w + 6, k * h + 3), text, fill=(240, 230, 150))
            sheet.save(os.path.join(out, "weapons_%s_%s.png" % (cls, race)))
    print("sheets in", out)


if __name__ == "__main__":
    main()

"""Contact sheets for the mid armour review: build/mid/shot_*.png -> one sheet per race (starter row over mid row, front/side/back)."""
import os, sys
from PIL import Image
D = sys.argv[1] if len(sys.argv) > 1 else "build/mid"
OUT = sys.argv[2] if len(sys.argv) > 2 else D
for race in ["human", "viking", "elf", "runeborn"]:
    sheet = Image.new("RGB", (900, 900), (150, 160, 140))
    for r, tier in enumerate(["starter", "mid"]):
        for c, view in enumerate(["front", "side", "back"]):
            im = Image.open(os.path.join(D, "shot_%s_%s_%s.png" % (race, tier, view))).convert("RGBA")
            bg = Image.new("RGBA", im.size, (150, 160, 140, 255)); bg.alpha_composite(im)
            sheet.paste(bg.convert("RGB"), (c * 300, r * 450))
    sheet.save(os.path.join(OUT, "sheet_%s_starter_over_mid.png" % race))

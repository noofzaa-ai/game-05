"""Orc Warlock boss accessory icons, step 2 of 2: the cel-shaded raw frames from tools/items/orc_warlock_icon_models.py
(build/orc_warlock_icons/raw-<name>.png) painted into the 96x96 boss icon style of art/items/boss/* with the same pass as
tools/items/boss_weapon_icons.py (colour clumping, a warm lift on the lit side, inner form shadow, dark warm-brown
outline, soft golden halo, a couple of sparkles on the coin/relic/ring). Tone is checked on the review strip against the
goblin and mummy icons (build/orc_warlock_icons/icons_cmp.png).
Run: blender -b --factory-startup --python tools/items/orc_warlock_icon_models.py -- build/orc_warlock_icons
     python -I tools/items/orc_warlock_icons.py
"""
import os
import sys

from PIL import Image, ImageEnhance, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import boss_weapon_icons as bw  # noqa: E402  (paint / rim / sparkles, ICON 96, SUPER 4)

ROOT = bw.ROOT
RAW = os.path.join(ROOT, "build", "orc_warlock_icons")
OUT = os.path.join(ROOT, "art", "items", "boss", "orc_warlock")
NAMES = ["necklace", "earring", "bracelet", "ring", "back", "coin", "relic"]
SPARKLES = {"coin": [(16, 18, 3.0), (82, 76, 2.2)], "relic": [(14, 20, 3.0), (84, 72, 2.4)], "ring": [(18, 22, 2.6)]}


def make(name):
    im = Image.open(os.path.join(RAW, "raw-%s.png" % name)).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
    inner = bw.ICON * bw.SUPER * 0.84
    s = inner / max(im.size)
    im = im.resize((max(1, round(im.size[0] * s)), max(1, round(im.size[1] * s))), Image.LANCZOS)
    canvas = Image.new("RGBA", (bw.ICON * bw.SUPER, bw.ICON * bw.SUPER), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((canvas.size[0] - im.size[0]) // 2, (canvas.size[1] - im.size[1]) // 2))
    painted = bw.paint(canvas)
    # the shared paint pass lifts saturation x1.25 (made for flat toon weapons); these are already toned: hand some back
    rgb = ImageEnhance.Color(painted.convert("RGB")).enhance(0.88)
    painted = Image.merge("RGBA", (*rgb.split(), painted.getchannel("A")))
    out = bw.rim(painted)
    if name in SPARKLES:
        out = bw.sparkles(out, SPARKLES[name])
    out = out.resize((bw.ICON, bw.ICON), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    out.save(path, optimize=True)
    print(path, os.path.getsize(path), "bytes")


def strip():
    """Review strip: goblin, mummy and orc rows of the seven icons at 2x on a dark panel, plus a 1x row."""
    rows = [("goblin_chief", NAMES), ("mummy_high_wizard", NAMES), ("orc_warlock", NAMES)]
    sheet = Image.new("RGBA", (len(NAMES) * 192, len(rows) * 192 + 96), (58, 52, 48, 255))
    for j, (d, names) in enumerate(rows):
        for i, n in enumerate(names):
            icon = Image.open(os.path.join(ROOT, "art", "items", "boss", d, n + ".png")).convert("RGBA")
            sheet.alpha_composite(icon.resize((192, 192), Image.LANCZOS), (i * 192, j * 192))
            if d == "orc_warlock":
                sheet.alpha_composite(icon, (i * 192 + 48, len(rows) * 192))
    sheet.convert("RGB").save(os.path.join(RAW, "icons_cmp.png"))
    print(os.path.join(RAW, "icons_cmp.png"))


if __name__ == "__main__":
    for n in NAMES:
        make(n)
    strip()

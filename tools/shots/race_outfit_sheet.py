"""Contact sheets and race piece icons for build/race_outfits/ (frames made by tools/shots/race_outfit_shots.gd).
Run: python -I tools/shots/race_outfit_sheet.py           (sheets + icons in build/race_outfits/)
     ZORX_ICONS=1 python -I tools/shots/race_outfit_sheet.py   (also writes the icons to their catalog paths in art/)
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "race_outfits")
CLASSES = ["sword_shield", "greatsword", "longbow", "magic"]
RACES = ["human", "viking", "elf", "runeborn"]
SLOTS = ["shirt", "pants", "armband", "shoes"]
RACE_WEAPONS = ["greatsword", "longbow", "magic"]  # one file per race x class (art/weapons/race_<race>/<class>.glb)
PIECES = SLOTS + ["sword", "shield"] + RACE_WEAPONS
ICON = 96  # the item icon size (art/items/icons)
SUPER = 4  # work at 4x, then scale down (soft edges)
# piece -> catalog icon path under art/ (armour is shared per race: every class reaches it through the icon fallback chain)
TARGETS = {}
for _r in RACES:
    for _s in SLOTS:
        TARGETS[(_r, _s)] = "armor/race_shared/icon-%s_%s.png" % (_r, _s)
    TARGETS[(_r, "sword")] = "weapons/race_%s/icon-sword_shield.png" % _r
    TARGETS[(_r, "shield")] = "weapons/race_%s/icon-shield.png" % _r
    for _c in RACE_WEAPONS:
        TARGETS[(_r, _c)] = "weapons/race_%s/icon-%s.png" % (_r, _c)


def grid(rows, cols, cell, names, title, label_w=120, scale=1.0):
    w, h = int(cell[0] * scale), int(cell[1] * scale)
    sheet = Image.new("RGB", (label_w + cols * w, 24 + rows * (h + 16)), (40, 40, 44))
    d = ImageDraw.Draw(sheet)
    d.text((6, 4), title, fill=(255, 255, 255))
    for r, (row_label, row) in enumerate(names):
        y = 24 + r * (h + 16)
        d.text((6, y + h // 2), row_label, fill=(230, 230, 230))
        for c, (col_label, name) in enumerate(row):
            x = label_w + c * w
            d.text((x + 4, y), col_label, fill=(200, 200, 160))
            p = os.path.join(OUT, name)
            if os.path.exists(p):
                im = Image.open(p).convert("RGBA").resize((w, h))
                bg = Image.new("RGBA", im.size, (120, 120, 128, 255))
                sheet.paste(Image.alpha_composite(bg, im).convert("RGB"), (x, y + 14))
    return sheet


def _rim(img):
    """A soft dark outline (reads on light panels) inside a faint light halo (reads on dark panels)."""
    alpha = img.getchannel("A")
    dark = alpha.filter(ImageFilter.MaxFilter(2 * SUPER + 1)).filter(ImageFilter.GaussianBlur(SUPER * 0.6))
    light = alpha.filter(ImageFilter.MaxFilter(4 * SUPER + 1)).filter(ImageFilter.GaussianBlur(SUPER * 1.2))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(Image.merge("RGBA", [Image.new("L", img.size, 236)] * 3 + [light.point(lambda a: int(a * 0.45))]))
    out.alpha_composite(Image.merge("RGBA", [Image.new("L", img.size, v) for v in (22, 18, 16)] + [dark.point(lambda a: int(a * 0.85))]))
    out.alpha_composite(img)
    return out


def _icon(raw, diagonal, flip=False):
    im = Image.open(raw).convert("RGBA")
    box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if box is None:
        return None
    im = im.crop(box)
    if diagonal:  # lay the long axis from bottom-left to top-right, like the existing blade icons
        a = np.asarray(im.getchannel("A")) > 8
        ys, xs = np.nonzero(a)
        _, v = np.linalg.eigh(np.cov(np.stack([xs - xs.mean(), ys - ys.mean()])))
        major = v[:, 1]
        angle = np.degrees(np.arctan2(-major[1], major[0]))
        im = im.rotate(45.0 - angle, resample=Image.BICUBIC, expand=True)
        im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
        if flip:  # the axis direction is sign-free: turn the piece end for end (staff gem to the top right)
            im = im.rotate(180)
    inner = ICON * SUPER * 0.84
    scale = inner / max(im.size)
    im = im.resize((max(1, round(im.size[0] * scale)), max(1, round(im.size[1] * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (ICON * SUPER, ICON * SUPER), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((canvas.size[0] - im.size[0]) // 2, (canvas.size[1] - im.size[1]) // 2))
    return _rim(canvas).resize((ICON, ICON), Image.LANCZOS)


def make_icons():
    made = 0
    for (race, piece), target in TARGETS.items():
        raw = os.path.join(OUT, "iconraw-%s_%s.png" % (race, piece))
        if not os.path.exists(raw):
            continue
        icon = _icon(raw, piece in ("sword", "greatsword", "magic"), piece == "magic")
        if icon is None:
            continue
        icon.save(os.path.join(OUT, "icon-%s_%s.png" % (race, piece)))
        made += 1
        if os.environ.get("ZORX_ICONS") == "1":
            icon.save(os.path.join(ROOT, "art", *target.split("/")))
    print("icons:", made)


def review_sheet():
    """icons_review.png: race x piece at 1x and 3x on a dark and a light panel; the top row is the current icons."""
    current = ["armor/ash_steel/icon-shirt.png", "armor/ash_steel/icon-pants.png", "armor/ash_steel/icon-arms.png",
               "armor/ash_steel/icon-shoes.png", "items/icons/weapon_blade_01.png", "items/icons/offhand_round_shield.png",
               "items/icons/weapon_blade_01.png", "items/icons/weapon_blade_01.png", "items/icons/weapon_blade_01.png"]
    cell1, cell3 = ICON + 12, ICON * 3 + 12
    width = 110 + len(PIECES) * (cell1 + cell3)
    rows = [("current", [os.path.join(ROOT, "art", *c.split("/")) for c in current])] + \
           [(race, [os.path.join(OUT, "icon-%s_%s.png" % (race, p)) for p in PIECES]) for race in RACES]
    sheet = Image.new("RGB", (width, 44 + 2 * len(rows) * (ICON * 3 + 8)), (60, 60, 64))
    d = ImageDraw.Draw(sheet)
    d.text((8, 6), "Race piece icons 96x96, 1x and 3x, on dark and light panels. Top row: the current icons (Ash steel, blade, round shield).", fill=(255, 255, 255))
    for c, p in enumerate(PIECES):
        d.text((110 + c * (cell1 + cell3), 26), p, fill=(230, 220, 150))
    y = 44
    for panel in [(34, 30, 28), (226, 218, 200)]:
        for label, files in rows:
            d.rectangle([0, y, width, y + ICON * 3], fill=panel)
            d.text((8, y + ICON * 3 // 2), label, fill=(128, 128, 128))
            for c, f in enumerate(files):
                if not os.path.exists(f):
                    continue
                icon = Image.open(f).convert("RGBA").resize((ICON, ICON), Image.LANCZOS)
                x = 110 + c * (cell1 + cell3)
                sheet.paste(icon, (x, y + ICON), icon)
                big = icon.resize((ICON * 3, ICON * 3), Image.NEAREST)
                sheet.paste(big, (x + cell1, y), big)
            y += ICON * 3 + 8
    sheet.save(os.path.join(OUT, "icons_review.png"))


def main():
    make_icons()
    review_sheet()
    looks = ["suit"] + RACES + ["mix_viking_elf", "mix_human_runeborn"]
    for side in ["front", "back"]:
        rows = [(cls, [(k, "card_%s_%s_%s.png" % (cls, k, side)) for k in looks]) for cls in CLASSES]
        grid(4, len(looks), (300, 450), rows, "Hub card portrait, %s (suit = class armour, no race piece)" % side, scale=0.6).save(os.path.join(OUT, "sheet_card_%s.png" % side))
    for pose in ["idle", "run"]:
        rows = []
        for cls in CLASSES:
            rows.append((cls, [("%s %s" % (k, s), "battle_%s_%s_%s_%s.png" % (cls, k, pose, s)) for k in ["suit"] + RACES for s in ["front", "back"]]))
        grid(4, 10, (360, 480), rows, "Battle 3/4 view, %s" % pose, scale=0.45).save(os.path.join(OUT, "sheet_battle_%s.png" % pose))
    weapons = os.path.join(OUT, "weapons")
    if os.path.isdir(weapons):
        frames = ["idle", "attack", "block"]
        sides = ["front", "back"]
        w, h = 300, 400
        sheet = Image.new("RGB", (110 + len(frames) * len(sides) * w, 24 + len(RACES) * (h + 16)), (40, 40, 44))
        d = ImageDraw.Draw(sheet)
        d.text((6, 4), "Race sword & shield (MID-tier delivery) + race outfit on the Sword & Shield body", fill=(255, 255, 255))
        for r, race in enumerate(RACES):
            y = 24 + r * (h + 16)
            d.text((6, y + h // 2), race, fill=(230, 230, 230))
            for c, (frame, side) in enumerate([(f, s) for f in frames for s in sides]):
                x = 110 + c * w
                d.text((x + 4, y), "%s %s" % (frame, side), fill=(200, 200, 160))
                p = os.path.join(weapons, "ss_%s_%s_%s.png" % (race, frame, side))
                if os.path.exists(p):
                    sheet.paste(Image.open(p).convert("RGB").resize((w, h)), (x, y + 14))
        sheet.save(os.path.join(weapons, "sheet_sword_shield.png"))
        frames_by_class = {"greatsword": ["idle", "reaping", "crater", "power_up"], "longbow": ["idle", "draw", "loose", "overdraw"],
                           "magic": ["idle", "orb", "starfall", "nova"]}
        w, h = 225, 300
        for cls, frames in frames_by_class.items():
            looks = ["suit"] + RACES
            sheet = Image.new("RGB", (110 + len(frames) * 2 * w, 24 + len(looks) * (h + 16)), (40, 40, 44))
            d = ImageDraw.Draw(sheet)
            d.text((6, 4), "Race %s weapon (MID-tier delivery) + race outfit on the %s body; suit row = class weapon reference" % (cls, cls), fill=(255, 255, 255))
            for r, look in enumerate(looks):
                y = 24 + r * (h + 16)
                d.text((6, y + h // 2), look, fill=(230, 230, 230))
                for c, (frame, side) in enumerate([(f, sd) for f in frames for sd in ["front", "back"]]):
                    x = 110 + c * w
                    d.text((x + 4, y), "%s %s" % (frame, side), fill=(200, 200, 160))
                    p = os.path.join(weapons, "%s_%s_%s_%s.png" % (cls, look, frame, side))
                    if os.path.exists(p):
                        sheet.paste(Image.open(p).convert("RGB").resize((w, h)), (x, y + 14))
            sheet.save(os.path.join(weapons, "sheet_%s.png" % cls))
    print("sheets in", OUT)


if __name__ == "__main__":
    main()

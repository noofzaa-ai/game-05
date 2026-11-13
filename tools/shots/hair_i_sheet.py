"""Contact sheets for build/hair_i/ (frames made by tools/shots/hair_i_shots.gd).
Run: python -I tools/shots/hair_i_sheet.py   -> build/hair_i/sheet_<class>.png, sheet_heads.png, sheet_compare.png
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "hair_i")
CLASSES = ["sword_shield", "greatsword", "longbow", "magic"]
LOOKS = ["suit", "human", "viking", "elf", "runeborn"]
SIDES = ["front", "side", "back"]
TINTS = ["default", "2a1d17", "c04080", "3a5fcd", "e8d27a"]


def grid(rows, title, scale=0.5, label_w=130):
    first = next(os.path.join(OUT, n) for _, row in rows for _, n in row if os.path.exists(os.path.join(OUT, n)))
    w0, h0 = Image.open(first).size
    w, h = int(w0 * scale), int(h0 * scale)
    cols = max(len(row) for _, row in rows)
    sheet = Image.new("RGB", (label_w + cols * w, 24 + len(rows) * (h + 16)), (40, 40, 44))
    d = ImageDraw.Draw(sheet)
    d.text((6, 4), title, fill=(255, 255, 255))
    for r, (label, row) in enumerate(rows):
        y = 24 + r * (h + 16)
        d.text((6, y + h // 2), label, fill=(230, 230, 230))
        for c, (col_label, name) in enumerate(row):
            x = label_w + c * w
            d.text((x + 4, y), col_label, fill=(200, 200, 160))
            p = os.path.join(OUT, name)
            if os.path.exists(p):
                sheet.paste(Image.open(p).convert("RGB").resize((w, h)), (x, y + 14))
    return sheet


def main():
    for cls in CLASSES:
        rows = []
        for look in LOOKS:
            row = [("%s %s" % (pose, side), "body_%s_%s_%s_%s.png" % (cls, look, pose, side)) for pose in ["idle", "run"] for side in SIDES]
            rows.append((look, row))
        grid(rows, "Hair I on %s: class suit + race outfits/weapons, idle and run" % cls).save(os.path.join(OUT, "sheet_%s.png" % cls))
    rows = []
    for cls in CLASSES:
        for look in LOOKS:
            rows.append(("%s %s" % (cls[:5], look), [(s, "head_%s_%s_%s.png" % (cls, look, s)) for s in SIDES]))
    grid(rows, "Hair I head close-ups (collar check)", scale=0.4).save(os.path.join(OUT, "sheet_heads.png"))
    rows = []
    for cls in CLASSES:
        rows.append((cls, [("%s %s" % (hair.upper(), s), "cmp_%s_%s_%s.png" % (cls, hair, s)) for hair in ["g", "i"] for s in SIDES]))
    rows.append(("tint (S&S)", [(t, "tint_%s.png" % t) for t in TINTS]))
    grid(rows, "Hair G (reference) vs Hair I; card hair_color tints", scale=0.5).save(os.path.join(OUT, "sheet_compare.png"))
    print("sheets in", OUT)


if __name__ == "__main__":
    main()

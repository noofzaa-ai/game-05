"""Contact sheets for the violent light-and-scatter looks (tools/shots/vfx_violence_shots.gd output).
python -I tools/shots/vfx_violence_sheet.py build/vfx_violence [level]
  <tag>_<map>_<name>_sheet.png : 2 rows (today's look / new look) x 7 frames 0.03 .. 2.0 s after the blow
  <tag>_<map>_overview.png     : every film's 0.1 s and 0.4 s frames, today vs new, one row per skill
  brightness.txt               : mean frame brightness per strip (a flash that pumps shows as a jump)"""
import glob, os, re, sys
from PIL import Image, ImageDraw, ImageFont, ImageStat

d = sys.argv[1]
level = sys.argv[2] if len(sys.argv) > 2 else "L3"
TIMES = ["0.03 s", "0.10 s", "0.20 s", "0.40 s", "0.70 s", "1.20 s", "2.00 s"]
try:
    FONT = ImageFont.truetype("arialbd.ttf", 20)
    SMALL = ImageFont.truetype("arial.ttf", 15)
except OSError:
    FONT = SMALL = ImageFont.load_default()


def label(img, text, font=FONT):
    dr = ImageDraw.Draw(img)
    bbox = dr.textbbox((8, 6), text, font=font)
    dr.rectangle((bbox[0] - 4, bbox[1] - 3, bbox[2] + 4, bbox[3] + 3), fill=(0, 0, 0))
    dr.text((8, 6), text, fill=(255, 255, 255), font=font)


def crop(im, frac=0.66):
    w, h = im.size
    cw, ch = int(w * frac), int(h * frac)
    x, y = (w - cw) // 2, (h - ch) // 2 - int(h * 0.04)
    return im.crop((x, y, x + cw, y + ch))


films = sorted({m.group(1) for f in glob.glob(os.path.join(d, "*_f0.png"))
                for m in [re.match(r"((?:desk|phone)_(?:goblin|mummy)_.+)_(current|L1|L2|L3)_f0\.png$", os.path.basename(f))] if m})
bright = []
overview = {}
for film in films:
    rows = []
    for lvl in ("current", level):
        frames = [os.path.join(d, "%s_%s_f%d.png" % (film, lvl, i)) for i in range(7)]
        if all(os.path.exists(p) for p in frames):
            ims = [Image.open(p).convert("RGB") for p in frames]
            rows.append((lvl, ims))
            bright.append("%s %s %s" % (film, lvl, " ".join("%.1f" % ImageStat.Stat(im.convert("L")).mean[0] for im in ims)))
    if not rows:
        continue
    cw = 340
    cells = []
    for lvl, ims in rows:
        row = []
        for i, im in enumerate(ims):
            c = crop(im)
            c = c.resize((cw, int(cw * c.size[1] / c.size[0])), Image.LANCZOS)
            label(c, ("%s  %s" % ("today" if lvl == "current" else lvl, TIMES[i])) if i == 0 else TIMES[i], FONT if i == 0 else SMALL)
            row.append(c)
        cells.append(row)
    ch = cells[0][0].size[1]
    sheet = Image.new("RGB", (cw * 7, ch * len(cells)), (20, 20, 20))
    for r, row in enumerate(cells):
        for c, im in enumerate(row):
            sheet.paste(im, (c * cw, r * ch))
    sheet.save(os.path.join(d, film + "_sheet.png"))
    tag_map = "_".join(film.split("_")[:2])
    overview.setdefault(tag_map, []).append((film, rows))

for tag_map, items in overview.items():
    cw = 300
    lines = []
    for film, rows in items:
        cells = []
        for lvl, ims in rows:
            for i in (1, 3):
                c = crop(ims[i])
                c = c.resize((cw, int(cw * c.size[1] / c.size[0])), Image.LANCZOS)
                label(c, "%s %s %s" % (film[len(tag_map) + 1:], "today" if lvl == "current" else lvl, TIMES[i]), SMALL)
                cells.append(c)
        lines.append(cells)
    ch = lines[0][0].size[1]
    sheet = Image.new("RGB", (cw * 4, ch * len(lines)), (20, 20, 20))
    for r, cells in enumerate(lines):
        for c, im in enumerate(cells):
            sheet.paste(im, (c * cw, r * ch))
    sheet.save(os.path.join(d, tag_map + "_overview.png"))
    print("overview", tag_map, len(lines))
open(os.path.join(d, "brightness.txt"), "w").write("\n".join(bright) + "\n")
print("sheets", len(films))

"""Contact sheets for the hub card level options (Boss 2026-11-19), from tools/shots/hub_level_shots.gd output.

  python tools/shots/hub_level_sheet.py   -> build/hub_level/sheet_<size>.png (rows = options, columns = cases,
                                             each cell the card row crop of the real windowed shot, at 1:1 or 2x)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2] / 'build' / 'hub_level'
STYLES = {1: '1  Plate split  (SQUAD 1 · Lv 10)', 2: '2  Hanging carved tab under the plate', 3: '3  Medallion seal on the plate end (recommended)'}
CASES = [('a_veteran_lv10', 'veteran: Lv 10'), ('b_mummy_lv5', 'mummy_zone_locked: Lv 5'),
         ('c_magic_locked', 'Magic locked: no level'), ('d_lv15', 'two digits: Lv 15')]
CROP = {'1280x720': ((375, 105, 1250, 405), 1), '844x390': ((228, 40, 800, 240), 2)}


def font(px):
    for name in ['C:/Windows/Fonts/segoeui.ttf', 'C:/Windows/Fonts/arial.ttf']:
        try:
            return ImageFont.truetype(name, px)
        except OSError:
            pass
    return ImageFont.load_default()


for size, (box, zoom) in CROP.items():
    cw, ch = (box[2] - box[0]) * zoom, (box[3] - box[1]) * zoom
    head, left, pad = 40, 300, 10
    sheet = Image.new('RGB', (left + len(CASES) * (cw + pad), head + len(STYLES) * (ch + pad)), (24, 20, 18))
    d = ImageDraw.Draw(sheet)
    d.text((10, 8), f'Hub card level options, {size} real window ({"crop x2" if zoom > 1 else "crop 1:1"})', fill=(240, 226, 196), font=font(20))
    for c, (_, title) in enumerate(CASES):
        d.text((left + c * (cw + pad) + 6, head - 22), title, fill=(240, 226, 196), font=font(18))
    for r, (st, title) in enumerate(STYLES.items()):
        y = head + r * (ch + pad)
        d.multiline_text((10, y + 10), title.replace('  ', '\n', 1), fill=(240, 226, 196), font=font(20))
        for c, (case, _) in enumerate(CASES):
            p = ROOT / f's{st}_{size}_{case}.png'
            if not p.exists():
                continue
            im = Image.open(p).convert('RGB').crop(box)
            if zoom > 1:
                im = im.resize((cw, ch), Image.LANCZOS)
            sheet.paste(im, (left + c * (cw + pad), y))
    out = ROOT / f'sheet_{size}.png'
    sheet.save(out)
    print(out)

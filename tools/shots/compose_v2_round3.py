"""Compose round3 review images (same layout as round2, reading from the round3 renders):
  - v1 | v2 side-by-side (bare + shinigami_f, front/3q/side)
  - two face contact sheets: all 11 v2 faces close-up on the head, and at fight size.

    python3 tools/shots/compose_v2_round3.py
"""
from PIL import Image, ImageDraw
import os

D = "art_source/preview/chibi_v2/round3"
BG = (30, 31, 34)

PAIRS = [
    ("doll_v1_bare_bob_front.png", "doll_v2_bare_bob_front.png", "cmp_bare_front.png"),
    ("doll_v1_bare_bob_threequarter.png", "doll_v2_bare_bob_threequarter.png", "cmp_bare_3q.png"),
    ("doll_v1_bare_bob_side.png", "doll_v2_bare_bob_side.png", "cmp_bare_side.png"),
    ("doll_v1_shinigami_f_bob_front.png", "doll_v2_shinigami_f_bob_front.png", "cmp_shinigami_front.png"),
    ("doll_v1_shinigami_f_bob_threequarter.png", "doll_v2_shinigami_f_bob_threequarter.png", "cmp_shinigami_3q.png"),
    ("doll_v1_shinigami_f_bob_side.png", "doll_v2_shinigami_f_bob_side.png", "cmp_shinigami_side.png"),
]

FACES = ["smile", "soft_smile", "playful", "prankster", "devious", "vampire",
         "bored", "annoyed", "err", "sad", "shout"]
NAMES = {"smile": "Smile", "soft_smile": "Soft Smile", "playful": "Playful", "prankster": "Prankster",
         "devious": "Devious", "vampire": "Fang", "bored": "Bored", "annoyed": "Annoyed",
         "err": "Err...", "sad": "Worried", "shout": "Shout"}


def pair_up():
    for a, b, out in PAIRS:
        pa, pb = os.path.join(D, a), os.path.join(D, b)
        if not (os.path.exists(pa) and os.path.exists(pb)):
            print("skip", out); continue
        ia, ib = Image.open(pa).convert("RGB"), Image.open(pb).convert("RGB")
        h = max(ia.height, ib.height)
        c = Image.new("RGB", (ia.width + ib.width, h + 28), BG)
        c.paste(ia, (0, 28)); c.paste(ib, (ia.width, 28))
        d = ImageDraw.Draw(c)
        d.text((ia.width // 2 - 50, 8), "CURRENT (v1)", fill=(220, 180, 180))
        d.text((ia.width + ib.width // 2 - 36, 8), "NEW (v2)", fill=(180, 220, 190))
        c.save(os.path.join(D, out)); print("wrote", out)


def sheet(prefix, out, cols=4, label_h=20):
    tiles = []
    for f in FACES:
        p = os.path.join(D, "%s_%s.png" % (prefix, f))
        if os.path.exists(p):
            tiles.append((f, Image.open(p).convert("RGB")))
    if not tiles:
        print("skip", out); return
    tw, th = tiles[0][1].width, tiles[0][1].height
    rows = (len(tiles) + cols - 1) // cols
    cell_h = th + label_h
    canvas = Image.new("RGB", (cols * tw, rows * cell_h), BG)
    d = ImageDraw.Draw(canvas)
    for i, (f, im) in enumerate(tiles):
        r, col = divmod(i, cols)
        x, y = col * tw, r * cell_h
        canvas.paste(im, (x, y))
        d.text((x + 6, y + th + 4), NAMES.get(f, f), fill=(220, 220, 210))
    canvas.save(os.path.join(D, out)); print("wrote", out)


pair_up()
sheet("faceclose", "faces_v2_closeup_sheet.png", cols=4)
sheet("facefit", "faces_v2_fightsize_sheet.png", cols=6)
print("COMPOSE_DONE")

"""Build old-vs-new (v1 | v2) side-by-side composites from the rendered doll shots."""
from PIL import Image, ImageDraw
import os

D = "art_source/preview/chibi_v2"
pairs = [
    ("doll_v1_bare_bob_front.png", "doll_v2_bare_bob_front.png", "bare_front_v1_vs_v2.png"),
    ("doll_v1_bare_bob_threequarter.png", "doll_v2_bare_bob_threequarter.png", "bare_3q_v1_vs_v2.png"),
    ("doll_v1_shinigami_f_bob_front.png", "doll_v2_shinigami_f_bob_front.png", "shinigami_front_v1_vs_v2.png"),
]
for a, b, out in pairs:
    pa, pb = os.path.join(D, a), os.path.join(D, b)
    if not (os.path.exists(pa) and os.path.exists(pb)):
        print("skip", out); continue
    ia, ib = Image.open(pa), Image.open(pb)
    h = max(ia.height, ib.height)
    canvas = Image.new("RGB", (ia.width + ib.width, h + 28), (30, 31, 34))
    canvas.paste(ia, (0, 28)); canvas.paste(ib, (ia.width, 28))
    d = ImageDraw.Draw(canvas)
    d.text((ia.width // 2 - 60, 6), "CURRENT (v1)", fill=(220, 180, 180))
    d.text((ia.width + ib.width // 2 - 40, 6), "NEW (v2)", fill=(180, 220, 190))
    canvas.save(os.path.join(D, out))
    print("wrote", out)

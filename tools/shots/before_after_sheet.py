"""Side-by-side before/after sheet: python before_after_sheet.py OUT.png W label1 before1 after1 [label2 before2 after2 ...]"""
import sys
from PIL import Image, ImageDraw
out, w = sys.argv[1], int(sys.argv[2])
rows = [sys.argv[i:i + 3] for i in range(3, len(sys.argv), 3)]
cells = []
for label, b, a in rows:
    ib, ia = Image.open(b).convert("RGB"), Image.open(a).convert("RGB")
    h = int(ib.height * w / ib.width)
    cells.append((label, ib.resize((w, h)), ia.resize((w, h)), h))
H = sum(c[3] + 24 for c in cells) + 24
sheet = Image.new("RGB", (w * 2 + 30, H), (20, 20, 24))
d = ImageDraw.Draw(sheet)
d.text((10, 4), "BEFORE", fill=(255, 255, 255)); d.text((w + 20, 4), "AFTER", fill=(255, 255, 255))
y = 24
for label, ib, ia, h in cells:
    d.text((10, y + 2), label, fill=(255, 220, 120))
    sheet.paste(ib, (10, y + 20)); sheet.paste(ia, (w + 20, y + 20))
    y += h + 24
sheet.save(out)
print(out)

"""Quick review sheet of captured frames: peek.py <shot dir> <out.png> <frame> [<frame> ...] (4 per row, 270x480 cells
for portrait frames, 480x270 for landscape)."""
import sys
from pathlib import Path
from PIL import Image

src, out, frames = Path(sys.argv[1]), sys.argv[2], [int(x) for x in sys.argv[3:]]
ims = []
for n in frames:
    p = src / ("%05d.jpg" % n)
    if p.exists():
        ims.append(Image.open(p))
w, h = ims[0].size
cell = (270, 480) if h > w else (480, 270)
cols = 4
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cell[0] * cols, cell[1] * rows))
for i, im in enumerate(ims):
    sheet.paste(im.resize(cell), ((i % cols) * cell[0], (i // cols) * cell[1]))
sheet.save(out)

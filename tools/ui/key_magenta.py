"""Keys a Codex sheet drawn on flat #FF00FF to real alpha and cuts out its pieces.

usage: python -I key_magenta.py <sheet.png> <out_dir> name1 [name2 ...]
Pieces are the connected opaque regions, ordered top-to-bottom then left-to-right (rows grouped by overlap);
each is saved trimmed (4 px clear margin) as <out_dir>/<name>.png. Pink fringes are despilled.
"""
import sys
from PIL import Image
import numpy as np


def key(img: Image.Image) -> np.ndarray:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # magenta-ness: red and blue both high above green
    m = np.minimum(r, b) - g
    alpha = np.clip(1.0 - (m - 60.0) / (170.0 - 60.0), 0.0, 1.0)
    # despill: pull red/blue toward green where pink leaks into the edge
    spill = np.clip(m, 0.0, None) * (1.0 - alpha * 0.0)
    limit = np.maximum(g, (r + b) * 0.5 - spill * 0.8)
    r2 = np.where(m > 20, np.minimum(r, limit + 25), r)
    b2 = np.where(m > 20, np.minimum(b, g + 10), b)
    out = np.dstack([r2, g, b2, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    return out


def pieces(rgba: np.ndarray):
    from scipy import ndimage
    mask = rgba[..., 3] > 40
    labels, n = ndimage.label(mask)
    boxes = []
    for i, sl in enumerate(ndimage.find_objects(labels)):
        h = sl[0].stop - sl[0].start
        w = sl[1].stop - sl[1].start
        if h * w < 2000:
            continue
        boxes.append((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop))
    boxes.sort(key=lambda bx: (bx[0] // 120, bx[2]))
    return boxes


def main() -> None:
    sheet, out_dir, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    rgba = key(Image.open(sheet))
    boxes = pieces(rgba)
    print("found", len(boxes), "pieces", boxes)
    for name, (y0, y1, x0, x1) in zip(names, boxes):
        y0, x0 = max(y0 - 4, 0), max(x0 - 4, 0)
        y1, x1 = min(y1 + 4, rgba.shape[0]), min(x1 + 4, rgba.shape[1])
        Image.fromarray(rgba[y0:y1, x0:x1]).save(f"{out_dir}/{name}.png", optimize=True)
        print(name, x1 - x0, "x", y1 - y0)


if __name__ == "__main__":
    main()

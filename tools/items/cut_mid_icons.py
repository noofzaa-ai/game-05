"""Cut the Codex mid-tier icon sheets (2x2 on #00FF00) into 192x192 transparent icon-<race>_<slot>_mid.png.
Usage: python -I tools/items/cut_mid_icons.py <sheet_dir> <out_dir>   (sheets: <race>_mid_sheet_v1.png)"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter
SLOTS = ["shirt", "pants", "armband", "shoes"]
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for race in ["human", "viking", "elf", "runeborn"]:
    im = Image.open(os.path.join(src, "%s_mid_sheet_v1.png" % race)).convert("RGB")
    a = np.asarray(im).astype(int)
    g = a[..., 1] - np.maximum(a[..., 0], a[..., 2])
    alpha = np.clip((g - 40) / -60.0 + 1.0, 0, 1)          # g>=100 transparent, g<=40 opaque
    alpha = np.where(g > 100, 0.0, np.where(g < 40, 1.0, (100 - g) / 60.0))
    rgb = a.copy()
    spill = g > 0                                             # despill green fringe
    rgb[..., 1] = np.where(spill, np.maximum(a[..., 0], a[..., 2]), a[..., 1])
    rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    full = Image.fromarray(rgba, "RGBA")
    from scipy import ndimage  # components assigned to a quadrant by their centre (sheets are 1024 or 1254 wide)
    lab, n = ndimage.label(alpha > 0.5)
    h, w = alpha.shape
    keep = [np.zeros((h, w), bool) for _ in range(4)]
    for k in range(1, n + 1):
        ys, xs = np.nonzero(lab == k)
        if len(ys) < 150:
            continue
        keep[(1 if xs.mean() > w / 2 else 0) + (2 if ys.mean() > h / 2 else 0)] |= lab == k
    for i, slot in enumerate(SLOTS):
        grown = ndimage.binary_dilation(keep[i], iterations=3)
        arr = rgba.copy()
        arr[..., 3] = np.where(grown, arr[..., 3], 0)
        q = Image.fromarray(arr, "RGBA")
        bb = q.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        q = q.crop(bb)
        scale = 154.0 / max(q.size)
        q = q.resize((max(1, round(q.width * scale)), max(1, round(q.height * scale))), Image.LANCZOS)
        icon = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
        icon.alpha_composite(q, ((192 - q.width) // 2, (192 - q.height) // 2))
        icon.save(os.path.join(out, "icon-%s_%s_mid.png" % (race, slot)))

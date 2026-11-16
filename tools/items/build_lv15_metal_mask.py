"""Build the metal mask for the level-15 race outfit atlas (stylised ink-metal shader, client/characters/studio05_toon.gdshader).
usage: python -I tools/items/build_lv15_metal_mask.py <lv15_atlas.jpg> <lv15_uv.json> <out_mask.png> [--debug <overlay.png>]
(run tools/items/extract_lv15_atlas.py first). Metal = pale/grey, low-saturation, bright-enough texels that are actually
covered by a UV triangle (plates, buckles, studs, trims). Warm gold (hue 38-58, bright) counts too. Cloth (saturated purple/green/teal), leather (brown) and skin
(peach, saturated) stay 0. The mask is soft (blurred 1.2 px) so mip filtering does not shimmer; saved 1024x1024 L."""
import json, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SAT_MAX = 0.20      # metal is nearly grey
VAL_MIN = 0.40      # dark steel still counts, black leather/ink does not
GOLD_HUE = (34.0, 60.0)  # degrees; skin (about 20-30) and brown leather stay out
GOLD_VAL_MIN = 0.36
GOLD_VAL_MAX = 0.88  # lighter than this is skin / cream cloth
TEXTURE_STD_MAX = 0.06  # grey fur / fluff is high-frequency; plates are smooth (local std of V, 9 px box)
SIZE = 1024

def coverage(uv, size):
    img = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(img)
    for tris in uv.values():
        for t in tris:
            d.polygon([(u * size, v * size) for u, v in t], fill=255)
    return np.asarray(img) > 0

def main():
    atlas, uvp, out = sys.argv[1:4]
    im = Image.open(atlas).convert('RGB')
    uv = json.load(open(uvp))
    hsv = np.asarray(im.convert('HSV')).astype(np.float32) / 255.0
    s, v = hsv[..., 1], hsv[..., 2]
    h = hsv[..., 0] * 360.0
    gold = (h > GOLD_HUE[0]) & (h < GOLD_HUE[1]) & (s > 0.30) & (s < 0.80) & (v > GOLD_VAL_MIN) & (v < GOLD_VAL_MAX)  # brass studs, buckles, trims
    silver = (s < SAT_MAX) & (v > VAL_MIN)
    box = ImageFilter.BoxBlur(4)
    vim = Image.fromarray((v * 255).astype(np.uint8))
    mean = np.asarray(vim.filter(box)).astype(np.float32) / 255.0
    mean2 = np.asarray(Image.fromarray((v * v * 255).astype(np.uint8)).filter(box)).astype(np.float32) / 255.0
    std = np.sqrt(np.maximum(mean2 - mean * mean, 0.0))
    metal = (silver & (std < TEXTURE_STD_MAX)) | gold  # small brass studs are noisy too: the fur filter is for silver only
    cov = coverage(uv, im.size[0])
    # keep only covered texels; drop single-pixel noise by a small open (median)
    m = Image.fromarray((metal & cov).astype(np.uint8) * 255).filter(ImageFilter.MedianFilter(3))
    m = m.resize((SIZE, SIZE), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.2))
    m.save(out, optimize=True)
    a = np.asarray(m) > 127
    print('metal share of covered area: %.1f%%  (of whole image %.1f%%)' % (
        100.0 * (metal & cov).sum() / cov.sum(), 100.0 * a.mean()))
    if '--debug' in sys.argv:
        o = np.asarray(im.resize((SIZE, SIZE))).copy()
        mm = np.asarray(m).astype(np.float32)[..., None] / 255.0
        o = (o * (1 - mm) + np.array([0, 255, 60]) * mm * 0.8 + o * mm * 0.2).astype(np.uint8)
        Image.fromarray(o).save(sys.argv[sys.argv.index('--debug') + 1])
main()

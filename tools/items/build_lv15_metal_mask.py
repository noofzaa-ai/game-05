"""Build the metal mask for the level-15 race outfit atlas (stylised ink-metal shader, client/characters/studio05_toon.gdshader).
usage: python -I tools/items/build_lv15_metal_mask.py <lv15_atlas.jpg> <lv15_uv.json> <out_mask.png> [--debug <overlay.png>]
(run tools/items/extract_lv15_atlas.py first). Metal = pale/grey, low-saturation, bright-enough texels that are actually
covered by a UV triangle (plates, buckles, studs, trims). Warm gold (hue 38-58, bright) counts too. Cloth (saturated purple/green/teal), leather (brown) and skin
(peach, saturated) stay 0. The mask is soft (blurred 1.2 px) so mip filtering does not shimmer; saved 1024x1024 RGB:
  R = metal (silver, gold, studs/buckles)   G = warm metal (gold / brass: the glint is warmer)   B = stud (small metal
  parts: buckles, rivets, studs, clasps, which also get the star-like sparkle dot).
Studs (buckles, rivets, studs, clasps) cannot be told from leather by colour alone (dull brass has leather's hue), so a stud is
a small WARM spot clearly brighter than its surroundings (LOCAL_BOX / STUD_CONTRAST below), plus the gold texels of small UV
islands. EXTRA_RECTS is the explicit,
reviewable hand override: [u0, v0, u1, v1, channels] in 0..1 UV rects forced on (channels: any of "m","w","s")."""
import json, os, sys
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFilter

SAT_MAX = 0.20      # metal is nearly grey
VAL_MIN = 0.40      # dark steel still counts, black leather/ink does not
GOLD_HUE = (34.0, 60.0)  # degrees; skin (about 20-30) and brown leather stay out
GOLD_VAL_MIN = 0.36
GOLD_VAL_MAX = 0.88  # lighter than this is skin / cream cloth
TEXTURE_STD_MAX = 0.06  # grey fur / fluff is high-frequency; plates are smooth (local std of V, 9 px box)
STUD_MAX_AREA = 2500      # texels at 2048: an island this small is a buckle / stud / rivet / clasp, not a panel
LOCAL_BOX = 21
STUD_CONTRAST = 0.10      # V above the local mean of covered texels
EXTRA_RECTS = []          # hand dabs, e.g. [0.512, 0.301, 0.520, 0.309, "msw"]
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
    full = metal & cov
    # --- studs: dull brass cannot be told from leather by colour alone, but a buckle / rivet / stud is a small WARM spot that is
    # clearly brighter than its surroundings (LOCAL_BOX texels), so: warm hue, some colour, bright, and brighter than the local
    # mean of covered texels by STUD_CONTRAST. Plus the gold texels of small UV islands.
    lab, n = ndimage.label(cov, structure=np.ones((3, 3)))
    area = ndimage.sum(cov, lab, index=np.arange(1, n + 1))
    small = np.zeros(n + 1, bool); small[1:] = area <= STUD_MAX_AREA
    cv = cov.astype(np.float32)
    local = ndimage.uniform_filter(v * cv, LOCAL_BOX) / np.maximum(ndimage.uniform_filter(cv, LOCAL_BOX), 1e-4)
    warm_spot = (h > 12) & (h < 62) & (s > 0.20) & (s < 0.75) & (v > 0.30) & (v - local > STUD_CONTRAST)
    stud = ndimage.binary_opening(warm_spot & cov, structure=np.ones((2, 2))) | (gold & small[lab] & cov)
    warm = gold | stud
    R = full | stud
    G = warm & R
    B = stud
    for u0, v0, u1, v1, ch in EXTRA_RECTS:
        box = (slice(int(v0 * 2048), int(v1 * 2048)), slice(int(u0 * 2048), int(u1 * 2048)))
        if "m" in ch: R[box] = True
        if "w" in ch: G[box] = True
        if "s" in ch: B[box] = True
    # thin buckle frames / rivets must survive the 2x downsample: studs are grown by 1 texel instead of median-filtered
    grow = lambda c: ndimage.binary_dilation(c, structure=np.ones((3, 3)), iterations=1)
    Bd = grow(grow(B))  # studs are tiny on screen: a slightly fatter dot reads better
    chans = []
    for name, c in (("R", R), ("G", G), ("B", B)):
        if name == "B":
            m1 = Image.fromarray(Bd.astype(np.uint8) * 255)
        else:
            m1 = Image.fromarray(c.astype(np.uint8) * 255).filter(ImageFilter.MedianFilter(3))
            m1 = Image.fromarray(np.maximum(np.asarray(m1), Bd.astype(np.uint8) * 255) if name == "R" else np.maximum(np.asarray(m1), (Bd & G).astype(np.uint8) * 255))
        chans.append(m1.resize((SIZE, SIZE), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.0)))
    m = Image.merge('RGB', chans)
    m.save(out, optimize=True)
    print('stud share of covered area %.1f%%' % (100.0 * stud.sum() / cov.sum()))
    print('metal share of covered area: %.1f%%  (of whole image %.1f%%)' % (
        100.0 * R.sum() / cov.sum(), 100.0 * R.mean()))
    if '--debug' in sys.argv:
        o = np.asarray(im.resize((SIZE, SIZE))).copy().astype(np.float32)
        mm = np.asarray(m).astype(np.float32) / 255.0
        o = o * (1 - 0.7 * mm[..., :1]) + np.array([0, 255, 60]) * 0.7 * mm[..., :1]
        o = o * (1 - 0.8 * mm[..., 2:3]) + np.array([255, 0, 255]) * 0.8 * mm[..., 2:3]
        Image.fromarray(o.clip(0, 255).astype(np.uint8)).save(sys.argv[sys.argv.index('--debug') + 1])
main()

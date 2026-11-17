"""Metal masks for the level-15 weapon textures (stylised ink-metal glints, client/characters/metal_glint.gd, kind "weapon").
usage: python -I tools/items/build_lv15_weapon_metal_masks.py <dir with the *_weapons_lv15.glb files> <out dir>
Reads sword_shield / greatsword / longbow / magic _weapons_lv15.glb (the delivery), takes the base-colour texture of every textured
material (the shared class atlas, plus the painted human shield front), and writes <out>/weapon_metal_lv15_<name>.png, RGB:
  R = metal   G = warm metal (gold)   B = accent (small bright warm or gem spots: studs, rivets, gem highlights)
Metal = pale/grey low-saturation bright texels (blades, guards, shield rims) and gold (hue 30-60, bright). Wood (brown),
leather, cloth wrap, green/teal/purple paint and the shield's turquoise face stay 0. Only texels covered by a UV triangle of the
material count. Reproducible: same inputs -> same bytes. Masks are 1024 px (the 384x448 shield front keeps its size)."""
import json, os, struct, sys
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFilter
import io

SAT_MAX = 0.20
VAL_MIN = 0.38
GOLD_HUE = (36.0, 60.0)    # wood and lacquer (hue 22-33) stay matte
GOLD_SAT = (0.32, 0.75)
GOLD_VAL = (0.42, 0.95)
TEXTURE_STD_MAX = 0.07     # plates / blades are smooth; fluff and noisy paint are not
LOCAL_BOX = 15
ACCENT_CONTRAST = 0.10
GEM_HUE = (165.0, 205.0)   # bright turquoise gem highlights
SIZE = 1024
CLASSES = ['sword_shield', 'greatsword', 'longbow', 'magic']


def load_glb(path):
    d = open(path, 'rb').read()
    jl = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack('<I', d[off:off + 4])[0]
    return j, d[off + 8:off + 8 + bl]


def accessor(j, b, i):
    a = j['accessors'][i]
    v = j['bufferViews'][a['bufferView']]
    ct = {5126: 'f4', 5123: 'u2', 5125: 'u4'}[a['componentType']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3}[a['type']]
    o = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    arr = np.frombuffer(b, dtype=ct, count=a['count'] * n, offset=o)
    return arr.reshape(-1, n) if n > 1 else arr


def coverage(tris, w, h):
    img = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(img)
    for t in tris:
        d.polygon([(u * w, v * h) for u, v in t], fill=255)
    return np.asarray(img) > 0


def classify(im, cov):
    hsv = np.asarray(im.convert('HSV')).astype(np.float32) / 255.0
    h, s, v = hsv[..., 0] * 360.0, hsv[..., 1], hsv[..., 2]
    box = ImageFilter.BoxBlur(3)
    mean = np.asarray(Image.fromarray((v * 255).astype(np.uint8)).filter(box)).astype(np.float32) / 255.0
    mean2 = np.asarray(Image.fromarray((v * v * 255).astype(np.uint8)).filter(box)).astype(np.float32) / 255.0
    std = np.sqrt(np.maximum(mean2 - mean * mean, 0.0))
    silver = (s < SAT_MAX) & (v > VAL_MIN) & (std < TEXTURE_STD_MAX)
    gold = (h > GOLD_HUE[0]) & (h < GOLD_HUE[1]) & (s > GOLD_SAT[0]) & (s < GOLD_SAT[1]) & (v > GOLD_VAL[0]) & (v < GOLD_VAL[1])
    cv = cov.astype(np.float32)
    local = ndimage.uniform_filter(v * cv, LOCAL_BOX) / np.maximum(ndimage.uniform_filter(cv, LOCAL_BOX), 1e-4)
    gem = (h > GEM_HUE[0]) & (h < GEM_HUE[1]) & (s > 0.35) & (v > 0.62)
    accent = ((gold | gem) & (v - local > ACCENT_CONTRAST)) | (gem & (v > 0.78))
    accent = ndimage.binary_opening(accent & cov, structure=np.ones((2, 2)))
    R = ((silver | gold) & cov) | accent
    G = (gold & cov) | (accent & ~gem)
    return R, G, accent


def to_mask(R, G, B, size):
    grow = lambda c: ndimage.binary_dilation(c, structure=np.ones((3, 3)), iterations=1)
    Bd = grow(B)
    chans = []
    for name, c in (('R', R), ('G', G), ('B', B)):
        if name == 'B':
            m = Image.fromarray(Bd.astype(np.uint8) * 255)
        else:
            m = Image.fromarray(c.astype(np.uint8) * 255).filter(ImageFilter.MedianFilter(3))
            extra = Bd if name == 'R' else (Bd & G)
            m = Image.fromarray(np.maximum(np.asarray(m), extra.astype(np.uint8) * 255))
        chans.append(m.resize(size, Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8)))
    return Image.merge('RGB', chans)


def main():
    src, out = sys.argv[1:3]
    os.makedirs(out, exist_ok=True)
    for cls in CLASSES:
        j, b = load_glb(os.path.join(src, f'{cls}_weapons_lv15.glb'))
        per_mat = {}
        for m in j['meshes']:
            for p in m['primitives']:
                mat = p.get('material')
                if mat is None or 'baseColorTexture' not in j['materials'][mat].get('pbrMetallicRoughness', {}):
                    continue
                uvs = accessor(j, b, p['attributes']['TEXCOORD_0'])
                idx = accessor(j, b, p['indices']).reshape(-1, 3)
                per_mat.setdefault(mat, []).extend(uvs[idx].tolist())
        for mat, tris in per_mat.items():
            tex = j['materials'][mat]['pbrMetallicRoughness']['baseColorTexture']['index']
            img = j['images'][j['textures'][tex]['source']]
            v = j['bufferViews'][img['bufferView']]
            im = Image.open(io.BytesIO(b[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']])).convert('RGB')
            w, h = im.size
            cov = coverage(tris, w, h)
            R, G, B = classify(im, cov)
            name = cls if w >= 1024 else 'shield_front'
            size = (SIZE, SIZE) if w >= 1024 else (w, h)
            mask = to_mask(R, G, B, size)
            path = os.path.join(out, f'weapon_metal_lv15_{name}.png')
            mask.save(path, optimize=True)
            print('%s: %s metal %.1f%% of used area, accent %.2f%%' % (path, j['materials'][mat]['name'], 100.0 * R.sum() / max(cov.sum(), 1), 100.0 * B.sum() / max(cov.sum(), 1)))


main()

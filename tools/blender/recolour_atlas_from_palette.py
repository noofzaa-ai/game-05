# tech-artist 2026-11-13 (drawn style repaint). Run:
#   blender -b --factory-startup --python tools/blender/recolour_atlas_from_palette.py -- <atlas.png> <palette.png> <out.png>
# then resize to 512 px (the shipped size). Source atlas: art/props/goblin_base/shared/relic_colour.png;
# palette: art_source/codex_review/repaint/repaint_prop_palette_v1.png; output: art/maps/goblin_base/painted/relic_colour_ink.png.
# Blender: recolour the goblin kit atlas (art/props/goblin_base/shared/relic_colour.png) toward the approved palette
# sheet. Each atlas pixel takes the hue/saturation of its nearest swatch (by chroma) and keeps its own brightness.
# Writes a NEW image; the original atlas is untouched.
import bpy, sys
import numpy as np
argv = sys.argv[sys.argv.index('--') + 1:]
atlas_path, palette_path, out_path = argv
pal_img = bpy.data.images.load(palette_path)
w, h = pal_img.size
pp = np.array(pal_img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]  # top row first
pal = []
for r in range(4):
    for c in range(4):
        cy, cx = int((r + 0.5) * h / 4), int((c + 0.5) * w / 4)
        pal.append(pp[cy - 40:cy + 40, cx - 40:cx + 40].reshape(-1, 3).mean(0))
pal = np.array(pal)
img = bpy.data.images.load(atlas_path)
aw, ah = img.size
a = np.array(img.pixels[:], dtype=np.float32).reshape(ah, aw, 4)
rgb = a[:, :, :3]
lw = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)  # linear (Blender image pixels are linear for sRGB images)
def chroma(x):
    l = (x * lw).sum(-1, keepdims=True)
    return x / np.maximum(l, 1e-4), l
ca, la = chroma(rgb)
cp, _ = chroma(pal)
idx = np.empty(ca.shape[:2], dtype=np.int32)
for y0 in range(0, ah, 128):
    d = ((ca[y0:y0 + 128, :, None, :] - cp[None, None, :, :]) ** 2).sum(-1)
    idx[y0:y0 + 128] = d.argmin(-1)
target = cp[idx] * la
out = rgb * 0.4 + target * 0.6
l = (out * lw).sum(-1, keepdims=True)
out = l + (out - l) * 0.85
a[:, :, :3] = np.clip(out, 0, 1)
new = bpy.data.images.new('relic_colour_ink', aw, ah)
new.pixels[:] = a.ravel()
new.filepath_raw = out_path
new.file_format = 'PNG'
new.save()
print('RECOLOURED', aw, ah, '->', out_path)

"""96x96 icons for the boss unique weapons, painted to sit with the boss accessory icons (art/items/boss/*): the raw 1024 frames
from tools/shots/boss_weapon_shots.gd (iconraw-crook/staff.png, the model alone, toon shaded) laid on the diagonal, then
a painterly pass (colour clumping, a warm lift on the lit side, contrast/saturation like the hand-painted set), a dark
warm-brown outline, a soft golden halo and a few sparkles (as on the relic/ring icons).
Run: python -I tools/items/boss_weapon_icons.py     (after the shots; writes the catalog icons)
"""
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "build", "boss_weapons", "shots")
ICON, SUPER = 96, 4
JOBS = {"crook": ("art/items/boss/mummy_boss/crook.png", True), "staff": ("art/items/boss/mummy_high_wizard/staff.png", True)}


def diagonal(im, head_top_right):
    a = np.asarray(im.getchannel("A")) > 8
    ys, xs = np.nonzero(a)
    _, v = np.linalg.eigh(np.cov(np.stack([xs - xs.mean(), ys - ys.mean()])))
    major = v[:, 1]
    angle = np.degrees(np.arctan2(-major[1], major[0]))
    im = im.rotate(45.0 - angle, resample=Image.BICUBIC, expand=True)
    im = im.crop(im.getchannel("A").point(lambda x: 255 if x > 8 else 0).getbbox())
    # the heavier (wider) end is the head: it goes top right
    a = np.asarray(im.getchannel("A")) > 8
    ys, xs = np.nonzero(a)
    if head_top_right and (xs + (a.shape[0] - ys)).mean() < (a.shape[1] + a.shape[0]) / 2:
        im = im.rotate(180)
    return im


def paint(im):
    rgb, alpha = im.convert("RGB"), im.getchannel("A")
    rgb = rgb.filter(ImageFilter.ModeFilter(5)).filter(ImageFilter.SMOOTH_MORE)  # clumped strokes
    rgb = ImageEnhance.Color(rgb).enhance(1.25)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.15)
    # light from the top left: a warm lift falling to a cool shade at the bottom right
    w, h = rgb.size
    yy, xx = np.mgrid[0:h, 0:w]
    g = ((xx / w) + (yy / h)) / 2.0
    arr = np.asarray(rgb, dtype=np.float64)
    arr = arr * (1.12 - 0.28 * g)[..., None] + np.array([10, 6, -4]) * (1 - g)[..., None]
    # inner edge darkening (painted form shadow along the silhouette)
    inner = np.asarray(alpha.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(6)), dtype=np.float64) / 255.0
    arr = arr * (0.72 + 0.28 * inner)[..., None]
    return Image.merge("RGBA", (*Image.fromarray(arr.clip(0, 255).astype(np.uint8)).split(), alpha))


def rim(img):
    alpha = img.getchannel("A")
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    halo = alpha.filter(ImageFilter.MaxFilter(6 * SUPER + 1)).filter(ImageFilter.GaussianBlur(SUPER * 2.5))
    out.alpha_composite(Image.merge("RGBA", [Image.new("L", img.size, v) for v in (255, 214, 120)] + [halo.point(lambda a: int(a * 0.35))]))
    dark = alpha.filter(ImageFilter.MaxFilter(2 * SUPER + 1)).filter(ImageFilter.GaussianBlur(SUPER * 0.5))
    out.alpha_composite(Image.merge("RGBA", [Image.new("L", img.size, v) for v in (40, 24, 14)] + [dark.point(lambda a: int(a * 0.95))]))
    out.alpha_composite(img)
    return out


def sparkles(img, spots):
    d = ImageDraw.Draw(img)
    for x, y, r in spots:
        x, y, r = x * SUPER, y * SUPER, r * SUPER
        d.polygon([(x, y - r), (x + r * 0.25, y - r * 0.25), (x + r, y), (x + r * 0.25, y + r * 0.25), (x, y + r),
                   (x - r * 0.25, y + r * 0.25), (x - r, y), (x - r * 0.25, y - r * 0.25)], fill=(255, 246, 200, 235))
    return img


def make(name, target, head_top_right):
    im = Image.open(os.path.join(RAW, "iconraw-%s.png" % name)).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
    im = diagonal(im, head_top_right)
    inner = ICON * SUPER * 0.86
    s = inner / max(im.size)
    im = im.resize((max(1, round(im.size[0] * s)), max(1, round(im.size[1] * s))), Image.LANCZOS)
    canvas = Image.new("RGBA", (ICON * SUPER, ICON * SUPER), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((canvas.size[0] - im.size[0]) // 2, (canvas.size[1] - im.size[1]) // 2))
    out = sparkles(rim(paint(canvas)), [(18, 20, 3.2), (80, 70, 2.4)])
    out = out.resize((ICON, ICON), Image.LANCZOS)
    path = os.path.join(ROOT, *target.split("/"))
    out.save(path, optimize=True)
    print(path, os.path.getsize(path), "bytes")


def main():
    for name, (target, top_right) in JOBS.items():
        make(name, target, top_right)
    # review strip: the new icons beside the painted boss set, 3x on a dark panel
    files = ["art/items/boss/mummy_high_wizard/ring.png", "art/items/boss/mummy_high_wizard/relic.png",
             "art/items/boss/mummy_high_wizard/staff.png", "art/items/boss/mummy_boss/crook.png", "art/items/boss/mummy_high_wizard/necklace.png"]
    strip = Image.new("RGBA", (len(files) * 288, 288 + 96), (58, 52, 48, 255))
    for k, f in enumerate(files):
        icon = Image.open(os.path.join(ROOT, *f.split("/"))).convert("RGBA")
        strip.alpha_composite(icon.resize((288, 288), Image.NEAREST), (k * 288, 0))
        strip.alpha_composite(icon, (k * 288 + 96, 288))
    strip.convert("RGB").save(os.path.join(RAW, "icons_cmp.png"))


if __name__ == "__main__":
    main()

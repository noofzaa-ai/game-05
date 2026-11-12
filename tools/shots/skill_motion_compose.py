"""Assembles the frames from tools/shots/skill_motion_preview.gd into
build/skill_motion_preview/: sheets/<ID>_<name>.png (6 frames x 3 views, release frame in red),
timing/<strip>.png (clip time under each frame), videos/<class>.mp4 + .gif (4 skills back to back).
Usage: python tools/shots/skill_motion_compose.py <repo root> [ffmpeg path]   (PREVIEW_DIR=skill_motion_preview_v2 for v2)"""
import json, os, subprocess, sys, glob, shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = sys.argv[1]
FFMPEG = sys.argv[2] if len(sys.argv) > 2 else "ffmpeg"
BASE = os.path.join(ROOT, "build", os.environ.get("PREVIEW_DIR", "skill_motion_preview"))
FR = os.path.join(BASE, "frames")
info = {}
for f in glob.glob(os.path.join(FR, "skills_*.json")):
    info.update(json.load(open(f)))
try:
    FONT = ImageFont.truetype("arial.ttf", 15)
    BIG = ImageFont.truetype("arialbd.ttf", 20)
except OSError:
    FONT = BIG = ImageFont.load_default()
RED = (230, 60, 60)
CROP = (40, 60, 440, 540)  # 400 x 480 of the 480 x 560 render

def tile(path):
    return Image.open(path).convert("RGB").crop(CROP)

os.makedirs(os.path.join(BASE, "sheets"), exist_ok=True)
for sid, s in info.items():
    if sid.startswith("timing_"):
        continue
    w, h = CROP[2] - CROP[0], CROP[3] - CROP[1]
    sheet = Image.new("RGB", (w * 6, h * 3 + 70), (20, 24, 32))
    d = ImageDraw.Draw(sheet)
    d.text((10, 8), f"{sid} {s['name']} ({s['cls']})  window {s['total']:.3f}s  release at " + ", ".join(f"{r:.3f}s" for r in s["releases"]) + "  rows: 3/4 view, side view, high board view", fill=(240, 240, 240), font=BIG)
    for k, lab in enumerate(s["sheet"]):
        for row, view in enumerate("abc"):
            sheet.paste(tile(os.path.join(FR, sid, f"sheet_{k}_{view}.png")), (k * w, 40 + row * h))
        txt = f"t={lab['t']:.3f}s  {lab['clip']} @ {lab['clip_time']:.3f}"
        d.text((k * w + 6, 44), txt, fill=(255, 255, 255), font=FONT)
        if lab["release"]:
            d.rectangle([k * w + 2, 42, (k + 1) * w - 3, 40 + 3 * h - 2], outline=RED, width=5)
            d.text((k * w + 6, 64), "RELEASE", fill=RED, font=BIG)
    d.text((10, 40 + 3 * h + 6), "Blend in/out 0.12 s to the class idle. Root motion removed (the game moves the body). Grid cells 25 cm.", fill=(200, 200, 200), font=FONT)
    sheet.save(os.path.join(BASE, "sheets", f"{sid}_{s['name'].replace(' ', '_')}.png"))

os.makedirs(os.path.join(BASE, "timing"), exist_ok=True)
for key, s in info.items():
    if not key.startswith("timing_"):
        continue
    folder = os.path.join(FR, key)
    times = s["times"]
    w, h = 200, 240
    cols = len(times)
    strip = Image.new("RGB", (w * cols, h * 2 + 30), (20, 24, 32))
    d = ImageDraw.Draw(strip)
    d.text((6, 6), f"{s['clip']}  (top: side view, bottom: 3/4 view)", fill=(240, 240, 240), font=FONT)
    for k, t in enumerate(times):
        for row, view in enumerate("ab"):
            im = tile(os.path.join(folder, f"{k:02d}_{view}.png")).resize((w, h))
            strip.paste(im, (k * w, 30 + row * h))
        d.text((k * w + 4, 32), f"{t:.3f}s", fill=(255, 230, 120), font=BIG)
    strip.save(os.path.join(BASE, "timing", key[len("timing_"):] + ".png"))

os.makedirs(os.path.join(BASE, "videos"), exist_ok=True)
CLASSES = {"sword_shield": ["S1", "S2", "S3", "S4"], "greatsword": ["G1", "G2", "G3", "G4"], "longbow": ["L1", "L2", "L3", "L4"], "magic": ["M1", "M2", "M3", "M4"]}
for cls, ids in CLASSES.items():
    tmp = os.path.join(BASE, "videos", "_" + cls)
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    n = 0
    for sid in ids:
        s = info[sid]
        for k, fr in enumerate(s["frames"]):
            im = tile(os.path.join(FR, sid, f"vid_{k:04d}.png"))
            d = ImageDraw.Draw(im)
            d.text((8, 6), f"{sid} {s['name']}", fill=(255, 255, 255), font=BIG)
            d.text((8, 32), f"t={fr['t']:+.2f}s  {fr['clip']} @ {fr['clip_time']:.2f}", fill=(220, 220, 220), font=FONT)
            if fr["release"]:
                d.rectangle([0, 0, im.width - 1, im.height - 1], outline=RED, width=8)
                d.text((8, 54), "RELEASE", fill=RED, font=BIG)
            reps = 4 if fr["release"] else 1  # hold the release frame 4 frames so it can be seen
            for _ in range(reps):
                im.save(os.path.join(tmp, f"{n:05d}.png"))
                n += 1
    mp4 = os.path.join(BASE, "videos", f"{cls}.mp4")
    gif = os.path.join(BASE, "videos", f"{cls}.gif")
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(tmp, "%05d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", mp4], check=True)
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(tmp, "%05d.png"), "-vf", "scale=300:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", gif], check=True)
    shutil.rmtree(tmp)
    print(cls, n, "frames")

"""Largest frame-to-frame image change per rendered skill video (build/<dir>/frames/<ID>/vid_*.png) and where
it happens, to catch pops the joint check misses (blend errors). Mean abs pixel difference, 0-255.
  python tools/shots/skill_frame_jumps.py build/skill_motion_preview_v2"""
import sys, os, glob, json
import numpy as np
from PIL import Image
base = sys.argv[1]
info = {}
for f in glob.glob(os.path.join(base, "frames", "skills_*.json")):
    info.update(json.load(open(f)))
for sid in sorted(k for k in info if not k.startswith("timing")):
    files = sorted(glob.glob(os.path.join(base, "frames", sid, "vid_*.png")))
    prev = None
    diffs = []
    for i, p in enumerate(files):
        a = np.asarray(Image.open(p).convert("L"), dtype=np.int16)
        if prev is not None:
            diffs.append((float(np.abs(a - prev).mean()), i))
        prev = a
    vals = sorted(diffs, reverse=True)
    med = float(np.median([d for d, _ in diffs]))
    fr = info[sid]["frames"]
    top = [(round(d, 2), i, fr[i]["clip"], round(fr[i]["clip_time"], 2)) for d, i in vals[:3]]
    print(f"{sid} median={med:.2f} top={top}")

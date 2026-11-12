"""Metrics from build/skill_motion_preview/data/<clip>.csv (skill_motion_analyze.gd):
root motion removed by the game, foot slide while planted, contact changes, hand speed peaks."""
import csv, math, sys, os
D = sys.argv[1]
WINDOWS = [l.split() for l in open(os.path.join(D, "windows.txt")).read().splitlines() if l.strip()]
def load(c):
    return [{k: float(v) for k, v in x.items()} for x in csv.DictReader(open(os.path.join(D, c + ".csv")))]
for sid, clip, a, b in WINDOWS:
    a, b = float(a), float(b)
    d = [x for x in load(clip) if a - 1e-6 <= x["t"] <= b + 1e-6]
    root = math.hypot(d[-1]["raw_hips_x"] - d[0]["raw_hips_x"], d[-1]["raw_hips_z"] - d[0]["raw_hips_z"])
    out = [f"{sid:4s} {clip:34s} {a:.3f}-{b:.3f} rootXZ_removed={root*100:5.1f}cm"]
    for side in ("Left", "Right"):
        k = side + "ToeBase"
        ground = min(x[k + "_y"] for x in load(clip))
        planted = [x for x in d if x[k + "_y"] < ground + 0.025]
        slide = 0.0
        # slide = horizontal travel of the toe over consecutive planted frames
        for p, q in zip(d, d[1:]):
            if p[k + "_y"] < ground + 0.025 and q[k + "_y"] < ground + 0.025:
                slide += math.hypot(q[k + "_x"] - p[k + "_x"], q[k + "_z"] - p[k + "_z"])
        lift = [x["t"] for p, x in zip(d, d[1:]) if (p[k + "_y"] < ground + 0.025) != (x[k + "_y"] < ground + 0.025)]
        out.append(f"{side[0]}slide={slide*100:4.1f}cm contacts@{[round(t,3) for t in lift]}")
    for h in ("RightHand", "LeftHand"):
        sp = []
        for p, q in zip(d, d[1:]):
            dt = q["t"] - p["t"]
            if dt > 0:
                sp.append((math.dist((p[h+"_x"], p[h+"_y"], p[h+"_z"]), (q[h+"_x"], q[h+"_y"], q[h+"_z"])) / dt, q["t"]))
        top = max(sp) if sp else (0, 0)
        out.append(f"{h[0]}H_peak={top[0]:.2f}m/s@{top[1]:.3f}")
    print("  ".join(out))

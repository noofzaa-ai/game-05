"""Pose gap (cm, worst body joint) between any two clip poses, from the joints_<clip>.txt files that
tools/shots/skill_motion_gaps.gd writes. Used to pick skill window edges and clip-to-clip joins.
  python tools/shots/skill_motion_pairs.py <data dir> gap clipA tA clipB tB
  python tools/shots/skill_motion_pairs.py <data dir> best clipA tA clipB [from to]   (best tB for a join)"""
import os, sys, math
D = sys.argv[1] if len(sys.argv) > 1 else "build/skill_motion_preview/data"
_cache = {}
def frames(clip):
    if clip not in _cache:
        rows = []
        for line in open(os.path.join(D, f"joints_{clip}.txt")):
            parts = line.split()
            t = float(parts[0]); v = list(map(float, parts[1:]))
            rows.append((t, [tuple(v[i:i + 3]) for i in range(0, len(v), 3)]))
        _cache[clip] = rows
    return _cache[clip]
def at(clip, t):
    rows = frames(clip)
    return min(rows, key=lambda r: abs(r[0] - t))[1]
def gap(a, b):
    return max(math.dist(p, q) for p, q in zip(a, b)) * 100
if __name__ == "__main__":
    mode = sys.argv[2]
    if mode == "gap":
        print(round(gap(at(sys.argv[3], float(sys.argv[4])), at(sys.argv[5], float(sys.argv[6]))), 1))
    else:
        a = at(sys.argv[3], float(sys.argv[4])); clip = sys.argv[5]
        lo = float(sys.argv[6]) if len(sys.argv) > 6 else 0; hi = float(sys.argv[7]) if len(sys.argv) > 7 else 99
        best = sorted((gap(a, p), t) for t, p in frames(clip) if lo <= t <= hi)[:5]
        print([(round(t, 3), round(g, 1)) for g, t in best])


def vs_idle(clip, t, idle):
    """Gap from a clip pose to the class idle over its whole cycle: (min, mean, max) cm. The game shows the
    idle on the model clock, so a cast can start from any idle frame."""
    a = at(clip, t)
    g = [gap(a, p) for _, p in frames(idle)[::6]]
    return round(min(g), 1), round(sum(g) / len(g), 1), round(max(g), 1)

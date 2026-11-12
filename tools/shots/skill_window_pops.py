"""Pop check for a class-skill window file (tools/shots/skill_windows_v2.json): for every edge (idle -> first
segment, segment -> segment, last segment -> idle) the worst body-joint gap in cm, from the joint dumps of
tools/shots/skill_motion_gaps.gd (ALL_CLIPS=1). The idle side is the class idle at its own t=0 and, for
reference, the mean over its cycle (the game shows the idle on the model clock).
  python tools/shots/skill_window_pops.py tools/shots/skill_windows_v2.json [limit_cm]"""
import json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import skill_motion_pairs as P
P.D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "skill_motion_preview", "data")

IDLE = {"sword_shield": "idle", "greatsword": "gs_idle", "longbow": "lb_idle_01", "magic": "mg_loco_idle"}
windows = json.load(open(sys.argv[1]))
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 15.0
bad = 0
for sid, s in windows.items():
    if sid.startswith("_"):
        continue
    idle = IDLE[s["cls"]]
    segs = s["segs"]
    edges = [("idle->" + segs[0][0], P.gap(P.at(idle, 0), P.at(segs[0][0], segs[0][1])), P.vs_idle(segs[0][0], segs[0][1], idle)[1])]
    for a, b in zip(segs, segs[1:]):
        edges.append((f"{a[0]}@{a[2]}->{b[0]}@{b[1]}", P.gap(P.at(a[0], a[2]), P.at(b[0], b[1])), None))
    last = segs[-1]
    edges.append((last[0] + "->idle", P.gap(P.at(last[0], last[2]), P.at(idle, 0)), P.vs_idle(last[0], last[2], idle)[1]))
    total = sum((float(x[2]) - float(x[1])) / float(x[3]) for x in segs)
    rel = []
    t0 = 0.0
    for x in segs:
        for r in x[4]:
            rel.append(round(t0 + (r - x[1]) / x[3], 3))
        t0 += (x[2] - x[1]) / x[3]
    worst = max(e[1] for e in edges)
    flag = "POP" if worst > limit else "ok"
    bad += worst > limit
    print(f"{sid} {s['name']:14s} total={total:.3f}s release@{rel} worst={worst:.1f}cm {flag}")
    for name, g, mean in edges:
        extra = f" (idle cycle mean {mean})" if mean is not None else ""
        print(f"    {name:52s} {g:5.1f}{extra}{'  <-- over' if g > limit else ''}")
print("windows over", limit, "cm:", bad)

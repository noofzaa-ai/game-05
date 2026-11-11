"""Goblin animation set: art/animations/goblin.glb (+ goblin.json), the goblin's own clips on its 27-bone rig.

    blender -b art_source/monsters/goblin/goblin.blend -P tools/blender/goblin_anims.py [-- nopreview]

Clips: idle (loop), run (loop), attack_1, attack_2, hit, death, taunt (loop). The game finds the set by the
model's file name ("goblin" -> art/animations/goblin.json), see client/animation_set.gd.
Every frame is solved here in Python (procedural layers + keyed channels, analytic two-bone IK for legs and
arms, all written as plain FK keys), so the export has no constraints. Planted feet pivot on the ball of the
foot, which never moves while planted. Previews: art_source/preview/goblin/v1/<clip>.png (game cam / front / side).

Pose channels (armature space: the goblin faces -y, its left is +x, up is +z). Rotations are degrees
(pitch +X = top leans forward, roll +Y = top tilts to its left, yaw +Z = face turns to its left), applied on
the bone's rest orientation and carried by its parent.
  hips (x, y, z) metres from rest, hipsr / spine / chest / neck / head (pitch, roll, yaw)
  jaw  degrees open; earL / earR (back, droop) degrees, tipL / tipR droop
  footL / footR (ball x, ball y, lift, pitch heel-up, yaw toe-left): the ball of the foot, pivot of the foot
  handL / handR (wrist x, y, z, dagger dir x, y, z) in chest space (the rest chest), twL / twR dagger twirl
"""
import bpy, os, sys, json, math
import numpy as np
from mathutils import Vector, Matrix, Quaternion

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_GLB = os.path.join(ROOT, "art/animations/goblin.glb")
OUT_JSON = os.path.join(ROOT, "art/animations/goblin.json")
PREVIEW = os.path.join(ROOT, "art_source/preview/goblin/v1")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FPS = 30
R = math.radians

sc = bpy.context.scene
sc.render.fps = FPS
rig = bpy.data.objects["goblin_rig"]
body = bpy.data.objects["goblin"]
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)          # drops deform_test
rig.animation_data_create(); rig.animation_data.action = None

REST = {b.name: b.matrix_local.copy() for b in rig.data.bones}
PARENT = {b.name: (b.parent.name if b.parent else None) for b in rig.data.bones}
LEN = {b.name: b.length for b in rig.data.bones}
ORDER = []
while len(ORDER) < len(REST):
    for n in REST:
        if n not in ORDER and (PARENT[n] is None or PARENT[n] in ORDER): ORDER.append(n)
SIDES = (("L", 1), ("R", -1))
BALL0 = {s: REST["toe." + s].translation.copy() for s, _ in SIDES}
ANKLE_OFF = {s: REST["foot." + s].translation - BALL0[s] for s, _ in SIDES}
HAND_REL = {s: REST["hand." + s].to_quaternion().inverted() @ REST["attach_weapon." + s].to_quaternion() for s, _ in SIDES}


def qx(d): return Quaternion((1, 0, 0), R(d))
def qy(d): return Quaternion((0, 1, 0), R(d))
def qz(d): return Quaternion((0, 0, 1), R(d))
def qe(p, r=0.0, y=0.0): return qz(y) @ qx(p) @ qy(r)
def smooth(x): x = min(1.0, max(0.0, x)); return x * x * (3 - 2 * x)
def bump(t, t0, dur):   # 0 -> 1 -> 0 over [t0, t0+dur], fast in, slower out
    if t < t0 or t > t0 + dur: return 0.0
    s = (t - t0) / dur
    return smooth(s / 0.3) if s < 0.3 else 1.0 - smooth((s - 0.3) / 0.7)
def lerp(a, b, s): return tuple(x + (y - x) * s for x, y in zip(a, b)) if isinstance(a, tuple) else a + (b - a) * s


# ---------------------------------------------------------------- the solver
class Poser:
    def __init__(self):
        self.basis, self.M = {}, {}
        self.miss = 0.0; self.leg_miss = 0.0

    def m0(self, n):
        p = PARENT[n]
        return REST[n].copy() if p is None else self.M[p] @ REST[p].inverted() @ REST[n]

    def put(self, n, basis):
        self.basis[n] = basis; self.M[n] = self.m0(n) @ basis

    def rot(self, n, q, loc=None):
        r = REST[n].to_quaternion()
        b = (r.inverted() @ q @ r).to_matrix().to_4x4()
        if loc is not None: b = Matrix.Translation(r.inverted() @ Vector(loc)) @ b
        self.put(n, b)

    def aim(self, n, d):
        M0 = self.m0(n); R0 = M0.to_quaternion()
        q = (R0 @ Vector((0, 1, 0))).rotation_difference(d)
        self.put(n, (R0.inverted() @ q @ R0).to_matrix().to_4x4())

    def absrot(self, n, rq):
        R0 = self.m0(n).to_quaternion()
        self.put(n, (R0.inverted() @ rq).to_matrix().to_4x4())

    def two_bone(self, up, lo, target, pole):
        A = self.m0(up).translation
        a, b = LEN[up], LEN[lo]
        v = target - A; d = v.length
        if up.startswith("thigh"): self.leg_miss = max(self.leg_miss, d - (a + b) * 0.999)
        else: self.miss = max(self.miss, d - (a + b) * 0.999)
        d = min(max(d, abs(a - b) + 1e-3), (a + b) * 0.999)
        u = v.normalized()
        c = (a * a + d * d - b * b) / (2 * a * d); s = math.sqrt(max(0.0, 1 - c * c))
        w = pole - u * pole.dot(u); w.normalize()
        knee = A + a * (c * u + s * w)
        self.aim(up, (knee - A).normalized())
        self.aim(lo, (A + u * d - knee).normalized())


BASE = dict(hips=(0.0, 0.0, -0.035), hipsr=(6, 0, 0), spine=(2, 0, 0), chest=(2, 0, 0), neck=(0, 0, 0),
            head=(-4, 0, 0), jaw=4.0, earL=(6, 4), earR=(6, 4), tipL=0.0, tipR=0.0,
            footL=(0.125, -0.015, 0.0, 0.0, 10.0), footR=(-0.125, 0.025, 0.0, 0.0, -10.0),
            handL=(0.25, -0.03, 0.29, 0.15, -1.0, -0.25), handR=(-0.25, -0.01, 0.29, -0.15, -1.0, -0.25),
            twL=0.0, twR=0.0)


def solve(P, drop=None):
    """P: pose channels (BASE keys). drop: {side: armature matrix} for daggers let go. Returns the Poser."""
    S = Poser()
    S.put("root", Matrix.Identity(4))
    S.rot("hips", qe(*P["hipsr"]), P["hips"])
    for n in ("spine", "chest", "neck", "head"):
        S.rot(n, qe(*P[n]))
    S.rot("jaw", qx(P["jaw"]))
    for s, sg in SIDES:
        back, droop = P["ear" + s]
        S.rot("ear." + s, qz(sg * back) @ qy(sg * droop))
        S.rot("ear_tip." + s, qy(sg * P["tip" + s]))
    # legs: the ball of the foot is the pivot
    for s, sg in SIDES:
        bx, by, lift, pitch, yaw = P["foot" + s]
        fr = qz(yaw) @ qx(pitch)
        ball = Vector((bx, by, BALL0[s].z + lift))
        ankle = ball + fr @ ANKLE_OFF[s]
        pole = P.get("knee" + s) or (qz(yaw) @ Vector((0, -1, 0)) + Vector((sg * 0.25, 0, 0)))
        S.two_bone("thigh." + s, "shin." + s, ankle, Vector(pole))
        S.absrot("foot." + s, fr @ REST["foot." + s].to_quaternion())
        toe = -pitch if lift < 0.004 else -0.4 * pitch
        S.rot("toe." + s, qx(toe))
    # arms: wrist and dagger direction in chest space
    C = S.M["chest"] @ REST["chest"].inverted(); C3 = C.to_3x3()
    for s, sg in SIDES:
        h = P["hand" + s]
        wrist = C @ Vector(h[:3]); d = (C3 @ Vector(h[3:])).normalized()
        S.two_bone("upper_arm." + s, "forearm." + s, wrist, C3 @ Vector((sg * 0.7, 0.6, -0.2)))
        hint = C3 @ Vector((0, 0, 1)) if abs(d.z) < 0.8 else C3 @ Vector((0, -1, 0))
        u = (hint - d * hint.dot(d)).normalized()
        Ra = Matrix((d.cross(u), d, u)).transposed().to_quaternion()   # columns X, Y (blade), Z
        S.absrot("hand." + s, Ra @ HAND_REL[s].inverted())
        if drop and s in drop:
            S.put("attach_weapon." + s, S.m0("attach_weapon." + s).inverted() @ drop[s])
        else:
            S.put("attach_weapon." + s, Quaternion((0, 0, 1), R(P["tw" + s])).to_matrix().to_4x4())
    return S


# ---------------------------------------------------------------- keyed channels
def keyed(keys, t, loop=None, ease_ch=("footL", "footR")):
    """keys: [(time, {channel: value})]; missing channels hold. Catmull-Rom for the body, smoothstep for feet."""
    P = dict(BASE)
    chans = {}
    for k_t, kv in keys:
        for c, v in kv.items(): chans.setdefault(c, []).append((k_t, v))
    for c, ks in chans.items():
        if ks[0][0] > 0: ks = [(0.0, BASE[c])] + ks
        if t <= ks[0][0]: P[c] = ks[0][1]; continue
        if t >= ks[-1][0]: P[c] = ks[-1][1]; continue
        i = max(j for j in range(len(ks)) if ks[j][0] <= t)
        (t1, v1), (t2, v2) = ks[i], ks[i + 1]
        s = (t - t1) / (t2 - t1)
        if c in ease_ch or c in ("twL", "twR"):
            P[c] = lerp(v1, v2, smooth(s)); continue
        v0 = ks[i - 1][1] if i > 0 else v1
        v3 = ks[i + 2][1] if i + 2 < len(ks) else v2
        def cr(a, b, cc, d):
            return 0.5 * (2 * b + (-a + cc) * s + (2 * a - 5 * b + 4 * cc - d) * s * s + (-a + 3 * b - 3 * cc + d) * s ** 3)
        P[c] = tuple(cr(*z) for z in zip(v0, v1, v2, v3)) if isinstance(v1, tuple) else cr(v0, v1, v2, v3)
    return P


def add(a, b): return tuple(x + y for x, y in zip(a, b))


# ---------------------------------------------------------------- clips
IDLE_LEN = 5.0
def idle(t):
    L = IDLE_LEN; w = 2 * math.pi / L
    P = dict(BASE)
    # weight from foot to foot, uneven timing (periodic Catmull-Rom over the loop)
    ks = [(0, 0.0), (0.5, 0.014), (1.6, 0.016), (2.2, -0.004), (2.6, -0.016), (3.6, -0.014), (4.3, 0.002), (5.0, 0.0)]
    x = periodic(ks, t, L)
    sniff = bump(t, 0.35, 0.65) + bump(t, 3.15, 0.55)
    breath = 0.004 * math.sin(7 * w * t) + 0.0015 * math.sin(11 * w * t + 1)
    P["hips"] = (x, 0.0, -0.035 + breath - 0.008 * sniff)
    P["hipsr"] = (6 + 1.5 * math.sin(3 * w * t), -x * 300, 2 * math.sin(2 * w * t + 0.5))
    P["chest"] = (2 + 2.0 * math.sin(7 * w * t + 0.6) + 4 * sniff, x * 360, 0.0)
    # glances: quick snaps into holds
    gk = [(0, 0), (1.0, 0), (1.1, 38), (1.8, 33), (1.9, -32), (2.6, -29), (2.75, 0), (3.9, 0), (4.02, 16), (4.6, 13), (4.72, 0), (5.0, 0)]
    yaw = snap(gk, t)
    bob = 4 * math.sin(2 * math.pi * 6.5 * t) * sniff
    P["chest"] = add(P["chest"], (0, 0, 0.15 * yaw))
    P["neck"] = (-3 * sniff, 0, 0.3 * yaw)
    P["head"] = (-4 - 10 * sniff + bob, x * -150 + 0.18 * yaw, 0.55 * yaw)
    P["jaw"] = 4 + 6 * sniff * abs(math.sin(2 * math.pi * 6.5 * t)) + 1.5 * math.sin(7 * w * t)
    fl = lambda t0, a: a * bump(t, t0, 0.24)
    P["earL"] = (6 + fl(0.85, 30) + fl(3.95, 24) - 0.2 * max(0, yaw), 4 - 10 * sniff)
    P["earR"] = (6 + fl(2.15, 30) + fl(3.95, 24) + fl(4.18, 18) + 0.2 * min(0, yaw), 4 - 10 * sniff)
    P["tipL"] = 4 * bump(t, 0.9, 0.3); P["tipR"] = 4 * bump(t, 2.2, 0.3)
    # unweighted heel peels; the right toes tap twice while the weight is on the left
    pL = 10 * max(0.0, -x) / 0.016; pR = 10 * max(0.0, x) / 0.016
    tap = bump(t, 0.62, 0.16) + bump(t, 0.82, 0.16)
    P["footL"] = (0.125, -0.015, 0.0, pL, 10.0)
    P["footR"] = (-0.125, 0.025, 0.02 * tap, pR * (1 - tap) - 15 * tap, -10.0)
    # left dagger taps (three beats), right dagger twirl
    taps = sum(bump(t, t0, 0.14) for t0 in (1.45, 1.65, 1.85))
    up = bump(t, 1.3, 0.85)
    hl = BASE["handL"]
    P["handL"] = (hl[0], hl[1] - 0.02 * up, hl[2] + 0.03 * up, hl[3], hl[4], hl[5] - 0.9 * taps + 0.2 * up)
    out = smooth((t - 3.2) / 0.2) * (1 - smooth((t - 3.95) / 0.25))
    hr = BASE["handR"]
    P["handR"] = (hr[0] - 0.05 * out, hr[1] - 0.05 * out, hr[2] + 0.025 * out, hr[3], hr[4], hr[5] + 0.25 * out)
    P["twR"] = -360 * smooth((t - 3.38) / 0.45)
    return P


def periodic(ks, t, L):
    t = t % L
    i = max(j for j in range(len(ks) - 1) if ks[j][0] <= t)
    n = len(ks) - 1
    (t1, v1), (t2, v2) = ks[i], ks[i + 1]
    v0 = ks[(i - 1) % n][1]; v3 = ks[(i + 2) % n][1]
    s = (t - t1) / (t2 - t1)
    return 0.5 * (2 * v1 + (-v0 + v2) * s + (2 * v0 - 5 * v1 + 4 * v2 - v3) * s * s + (-v0 + 3 * v1 - 3 * v2 + v3) * s ** 3)


def snap(ks, t):
    for (t1, v1), (t2, v2) in zip(ks, ks[1:]):
        if t1 <= t <= t2:
            s = (t - t1) / (t2 - t1)
            s = 1 - (1 - s) ** 3 if abs(v2 - v1) > 10 else smooth(s)   # fast glance snaps, slow drifts
            return v1 + (v2 - v1) * s
    return ks[-1][1]


RUN_T = 0.30          # one stride (left + right step); clip = 2 strides
RUN_LEN = 2 * RUN_T
DUTY = 0.30           # share of the stride a foot is on the floor
SWEEP = (-0.12, 0.10)  # ball y while planted: 0.22 m in 0.09 s = 2.44 m/s at playback rate 1.0
RUN_SPEED = (SWEEP[1] - SWEEP[0]) / (DUTY * RUN_T)
def run_foot(ph, sg):
    if ph < DUTY:
        s = ph / DUTY
        by = lerp(SWEEP[0], SWEEP[1], s); lift = 0.0
        pitch = -3 + 3 * smooth(s / 0.2) + 30 * s * s
    else:
        s = (ph - DUTY) / (1 - DUTY)
        by = SWEEP[1] + (SWEEP[0] - SWEEP[1]) * smooth(s)
        lift = 0.055 * math.sin(math.pi * s ** 0.8)
        pk = [(0, 33), (0.3, 45), (0.75, 2), (1.0, -3)]
        pitch = next(lerp(a[1], b[1], smooth((s - a[0]) / (b[0] - a[0]))) for a, b in zip(pk, pk[1:]) if s <= b[0])
    return (sg * 0.10, by, lift, pitch, sg * 6.0)


def run(t):
    P = dict(BASE)
    ph = t / RUN_T; c = math.cos(2 * math.pi * (ph - 0.15))
    second = t >= RUN_T
    P["footL"] = run_foot(ph % 1.0, 1); P["footR"] = run_foot((ph + 0.5) % 1.0, -1)
    P["hips"] = (0.012 * c, 0.0, -0.047 - 0.012 * math.cos(2 * math.pi * (2 * ph - 0.3)))
    P["hipsr"] = (22 + 2 * math.cos(2 * math.pi * (2 * ph - 0.45)), -4 * c, -7 * math.cos(2 * math.pi * ph))
    P["spine"] = (6, 0, 0)
    P["chest"] = (4 + 2 * math.cos(2 * math.pi * (2 * ph - 0.5)), 3 * c, 10 * math.cos(2 * math.pi * ph))
    P["neck"] = (-10, 0, -2 * math.cos(2 * math.pi * ph))
    P["head"] = (-14 - 3 * math.cos(2 * math.pi * (2 * ph - 0.6)), -2 * c, -1 * math.cos(2 * math.pi * ph)
                 + 10 * bump(t, 0.36, 0.2))   # a quick glance over its shoulder in the second stride
    P["jaw"] = 7 + 5 * math.sin(2 * math.pi * ph)
    tw = 3 * math.sin(2 * math.pi * 2 * ph)
    P["earL"] = (28 + 12 * bump(t, 0.33, 0.2), 8); P["earR"] = (28, 8)
    P["tipL"] = 4 + tw; P["tipR"] = 4 - tw
    pump = 0.03 * math.cos(2 * math.pi * ph)
    P["handL"] = (0.23, 0.09 - pump, 0.27, 0.1, 0.75, -0.65)
    P["handR"] = (-0.23, 0.09 + pump, 0.27, -0.1, 0.75, -0.65)
    return P


# attack_1: hop in, right jab, left jab, giggle, hop back
A1 = [
    (0.12, dict(hips=(0, 0.02, -0.065), hipsr=(10, 0, 8), chest=(4, 0, 14), neck=(-8, 0, 0), head=(-16, 0, -14), jaw=14.0,
                earL=(22, 6), earR=(22, 6), handR=(-0.22, 0.09, 0.31, -0.1, -1, 0.1), handL=(0.22, -0.06, 0.33, 0.2, -1, 0),
                footL=BASE["footL"], footR=BASE["footR"])),
    (0.20, dict(hips=(0, 0.03, -0.07), hipsr=(12, 0, 10), footL=BASE["footL"], footR=BASE["footR"])),
    (0.25, dict(hips=(0, -0.07, -0.005), hipsr=(14, 0, 0), chest=(6, 0, -6), jaw=18.0,
                handR=(-0.14, -0.16, 0.33, -0.05, -1, -0.1),
                footL=(0.125, -0.075, 0.035, 20, 10), footR=(-0.125, -0.04, 0.04, 25, -10))),
    (0.30, dict(hips=(0, -0.12, -0.06), hipsr=(16, 0, -8), chest=(8, 0, -18), head=(-18, 0, 16), jaw=8.0,
                handR=(-0.16, -0.20, 0.32, -0.05, -1, -0.05), handL=(0.22, 0.08, 0.31, 0.1, -1, 0.1),
                footL=(0.125, -0.135, 0, 0, 10), footR=(-0.125, -0.095, 0, 0, -10))),
    (0.36, dict(chest=(8, 0, 18), hipsr=(16, 0, 6), head=(-18, 0, -14), jaw=16.0,
                handL=(0.16, -0.20, 0.32, 0.05, -1, -0.05), handR=(-0.22, 0.08, 0.31, -0.1, -1, 0.1))),
    (0.43, dict(chest=(10, 0, 22), hips=(0, -0.125, -0.065), handL=(0.17, -0.21, 0.30, 0.05, -1, -0.15))),
    (0.52, dict(chest=(6, 2, 5), hipsr=(14, 0, 0), head=(-10, 4, 0), jaw=14.0, earL=(0, -6), earR=(0, -6),
                handL=(0.22, -0.05, 0.31, 0.15, -1, -0.2), handR=(-0.22, -0.03, 0.31, -0.15, -1, -0.2))),
    (0.58, dict(hips=(0, -0.11, -0.07), hipsr=(10, 0, 0), chest=(6, -2, 0), jaw=10.0,
                footL=(0.125, -0.135, 0, 0, 10), footR=(-0.125, -0.095, 0, 0, -10))),
    (0.65, dict(hips=(0, -0.03, 0.0), hipsr=(0, 0, 0), head=(-6, 0, 0), earL=(16, 2), earR=(16, 2),
                footL=(0.125, -0.06, 0.04, 15, 10), footR=(-0.125, -0.02, 0.04, 15, -10))),
    (0.72, dict(hips=(0, 0.0, -0.06), hipsr=(8, 0, 0), footL=BASE["footL"], footR=BASE["footR"], earL=(14, 2), earR=(14, 2))),
    (0.80, dict(hips=(0, 0, -0.03), hipsr=(4, 0, 0), earL=(2, 0), earR=(2, 0), head=(-4, 0, 0), chest=(2, 0, 0), jaw=6.0)),
    (0.90, dict(BASE)),
]

# attack_2: the telegraphed pounce
FL, FR = BASE["footL"], BASE["footR"]
A2 = [
    (0.18, dict(hips=(0, 0.04, -0.07), hipsr=(10, 0, 0), spine=(4, 0, 0), chest=(0, 0, 0), neck=(-14, 0, 0), head=(-26, 0, 0),
                earL=(32, 22), earR=(32, 22), jaw=12.0, footL=FL, footR=FR,
                handL=(0.29, 0.08, 0.34, 0.5, -0.6, -0.4), handR=(-0.29, 0.08, 0.34, -0.5, -0.6, -0.4))),
    (0.30, dict(hipsr=(12, -3, 7))),
    (0.40, dict(hipsr=(12, 3, -7), jaw=18.0)),
    (0.50, dict(hipsr=(12, -3, 6), jaw=22.0)),
    (0.56, dict(hips=(0, 0.05, -0.085), hipsr=(14, 0, 0), head=(-30, 0, 0), earL=(35, 25), earR=(35, 25), footL=FL, footR=FR,
                handL=(0.30, 0.10, 0.35, 0.5, -0.6, -0.4), handR=(-0.30, 0.10, 0.35, -0.5, -0.6, -0.4))),
    (0.60, dict(hips=(0, 0.045, -0.08), footL=FL, footR=FR)),
    (0.64, dict(hips=(0, -0.04, -0.01), hipsr=(24, 0, 0), footL=(0.125, -0.015, 0.0, 38, 10), footR=(-0.125, 0.025, 0.0, 38, -10))),
    (0.72, dict(hips=(0, -0.20, 0.10), hipsr=(22, 0, 0), chest=(4, 0, 0), neck=(-10, 0, 0), head=(-26, 0, 0), earL=(40, 10), earR=(40, 10),
                jaw=22.0, handL=(0.15, -0.16, 0.40, 0.05, -0.45, -0.9), handR=(-0.15, -0.16, 0.40, -0.05, -0.45, -0.9),
                footL=(0.125, -0.10, 0.12, 30, 10), footR=(-0.125, -0.08, 0.12, 30, -10))),
    (0.80, dict(hips=(0, -0.30, -0.07), hipsr=(22, 0, 0), chest=(8, 0, 0), neck=(-8, 0, 0), head=(-22, 0, 0), jaw=4.0,
                earL=(-10, -4), earR=(-10, -4),
                handL=(0.13, -0.17, 0.24, 0.05, -0.35, -0.94), handR=(-0.13, -0.17, 0.24, -0.05, -0.35, -0.94),
                footL=(0.125, -0.30, 0, 0, 10), footR=(-0.125, -0.27, 0, 0, -10))),
    (0.92, dict(hips=(0, -0.32, -0.09), hipsr=(28, 0, 0), chest=(12, 0, 0), head=(-16, 0, 0), earL=(5, 10), earR=(5, 10),
                handL=(0.13, -0.18, 0.20, 0.05, -0.3, -0.95), handR=(-0.13, -0.18, 0.20, -0.05, -0.3, -0.95),
                footL=(0.125, -0.30, 0, 0, 10), footR=(-0.125, -0.27, 0, 0, -10))),
    (1.02, dict(hips=(0.02, -0.36, -0.06), hipsr=(30, 6, 10), neck=(0, 0, 0), head=(-10, 8, 0), jaw=16.0, earL=(12, 18), earR=(12, 18),
                handL=(0.30, -0.06, 0.33, 0.6, -0.6, 0.2), handR=(-0.29, -0.02, 0.30, -0.6, -0.5, 0.0),
                footR=(-0.13, -0.34, 0.04, 10, -10))),
    (1.10, dict(hips=(-0.015, -0.36, -0.065), hipsr=(28, -6, -6), footL=(0.125, -0.30, 0, 0, 10), footR=(-0.14, -0.38, 0, 0, -15))),
    (1.20, dict(hipsr=(20, 4, 4), head=(-8, -8, 6), chest=(8, 0, 0))),
    (1.30, dict(hips=(0, -0.30, -0.05), hipsr=(12, 0, 0), head=(-10, 0, 0), jaw=10.0, earL=(20, 6), earR=(20, 6),
                handL=BASE["handL"], handR=BASE["handR"], footL=(0.125, -0.30, 0, 0, 10), footR=(-0.14, -0.38, 0, 0, -15))),
    (1.38, dict(hips=(0, -0.22, -0.04), footL=(0.125, -0.19, 0.04, 20, 10))),
    (1.46, dict(footL=(0.125, -0.10, 0, 0, 10), footR=(-0.14, -0.38, 0, 0, -15))),
    (1.50, dict(footR=(-0.13, -0.22, 0.04, 20, -12))),
    (1.56, dict(hips=(0, -0.06, -0.045), footR=(-0.125, 0.025, 0, 0, -10), footL=(0.125, -0.10, 0, 0, 10))),
    (1.62, dict(footL=(0.125, -0.05, 0.03, 15, 10), earL=(30, 4))),
    (1.70, dict(hips=(0, 0, -0.05), hipsr=(8, 0, 0), footL=FL, earL=(4, 4), earR=(14, 4))),
    (1.80, dict(BASE)),
]

HIT = [
    (0.06, dict(hips=(0, 0.03, -0.03), hipsr=(-6, 0, 0), spine=(-6, 0, 0), chest=(-8, 0, 0), neck=(-6, 0, 0), head=(-22, 0, 0),
                jaw=20.0, earL=(35, 30), earR=(35, 30), tipL=20.0, tipR=20.0,
                handL=(0.20, -0.06, 0.37, 0.3, -0.8, 0.3), handR=(-0.20, -0.06, 0.37, -0.3, -0.8, 0.3))),
    (0.14, dict(hipsr=(-2, 0, 0), head=(-16, 4, 0))),
    (0.26, dict(hips=(0, 0.0, -0.04), hipsr=(9, 0, 0), spine=(3, 0, 0), chest=(4, 0, 0), neck=(0, 0, 0), head=(-2, 0, 0),
                earL=(15, 12), earR=(15, 12), tipL=6.0, tipR=6.0, jaw=8.0, handL=BASE["handL"], handR=BASE["handR"])),
    (0.38, dict(hipsr=(5, 0, 0), head=(-6, 0, 0), earL=(8, 5), earR=(8, 5), tipL=0.0, tipR=0.0)),
    (0.50, dict(BASE)),
]

DROP_T, LAND_T = 0.35, 0.58
DEATH = [
    (0.07, dict(hips=(0, 0.03, -0.03), hipsr=(-10, 4, 0), head=(-28, 0, 8), chest=(-6, 0, 0), jaw=22.0, earL=(38, 30), earR=(38, 30),
                handL=(0.30, 0.02, 0.36, 0.7, -0.5, 0.3), handR=(-0.30, 0.02, 0.36, -0.7, -0.5, 0.3), footL=FL, footR=FR)),
    (0.25, dict(hips=(0, 0.07, -0.03), hipsr=(-12, -6, -10), footR=(-0.12, 0.09, 0.04, 15, -10))),
    (0.35, dict(footR=(-0.12, 0.13, 0, 0, -20), footL=FL)),
    (0.45, dict(hips=(0.0, 0.11, -0.035), hipsr=(-8, 8, 12), footL=(0.10, 0.10, 0.04, 15, 10))),
    (0.55, dict(hips=(-0.01, 0.13, -0.04), hipsr=(-6, -10, 20), footL=(0.04, 0.16, 0, 0, 25), footR=(-0.12, 0.13, 0, 0, -20))),
    (0.75, dict(hipsr=(-10, 10, -5), head=(-10, -15, 10), handL=(0.30, 0.0, 0.40, 0.9, 0.0, 0.4), handR=(-0.30, 0.05, 0.33, -0.9, 0.2, -0.2),
                footL=(0.04, 0.16, 0, 0, 25), footR=(-0.12, 0.13, 0, 15, -20))),
    (0.90, dict(hips=(0, 0.16, -0.05), hipsr=(-25, 0, 0), head=(-16, 0, 0), footL=(0.04, 0.16, 0, 0, 25), footR=(-0.12, 0.13, 0.0, 20, -20))),
    (1.15, dict(hips=(0, 0.26, -0.10), hipsr=(-82, 0, 0), spine=(-10, 0, 0), chest=(-14, 0, 0), neck=(-6, 0, 0), head=(-10, 0, 0),
                handL=(0.33, 0.02, 0.38, 0.6, -0.6, 0.0), handR=(-0.33, 0.02, 0.38, -0.6, -0.6, 0.0), jaw=10.0,
                earL=(10, -10), earR=(10, -10),
                footL=(0.10, 0.16, 0.24, -40, 10), footR=(-0.10, 0.12, 0.26, -40, -10))),
    (1.27, dict(hips=(0, 0.26, -0.07), earL=(20, 20), earR=(20, 20), footL=(0.14, 0.04, 0.10, -60, 15), footR=(-0.14, 0.02, 0.12, -60, -15))),
    (1.40, dict(hips=(0, 0.26, -0.10), footL=(0.17, -0.01, 0.03, -80, 20), footR=(-0.17, -0.02, 0.03, -80, -20), jaw=22.0,
                earL=(30, 35), earR=(30, 35))),
    (1.70, dict(footR=(-0.17, -0.02, 0.03, -80, -20))),
    (1.78, dict(footR=(-0.18, -0.04, 0.07, -70, -25), earL=(20, 25))),
    (1.88, dict(footR=(-0.17, -0.02, 0.03, -80, -20), earL=(30, 35))),
    (2.20, dict(footR=(-0.17, -0.02, 0.03, -80, -20))),
]

TAUNT_LEN = 1.6
def taunt(t):
    L = TAUNT_LEN; w = 2 * math.pi / L
    P = dict(BASE)
    sway = math.sin(w * t)
    P["hips"] = (0.012 * sway, 0.0, -0.04 + 0.006 * abs(math.sin(5 * w * t)))
    P["hipsr"] = (2, -sway * 4, 4 * math.sin(w * t + 0.4))
    P["chest"] = (-4, 3 * math.sin(5 * w * t), 0)
    P["neck"] = (-6, 0, 0)
    P["head"] = (-14 + 5 * math.sin(5 * w * t), 6 * math.sin(w * t + 1), 0)
    P["jaw"] = 6 + 14 * (0.5 + 0.5 * math.sin(10 * w * t))
    P["earL"] = (-5 + 4 * math.sin(5 * w * t), -14); P["earR"] = (-5 + 4 * math.sin(5 * w * t + 1), -14)
    P["tipL"] = -4.0; P["tipR"] = -4.0
    hopL = bump(t, 0.15, 0.35); hopR = bump(t, 0.95, 0.35)
    P["footL"] = (0.125, -0.015, 0.03 * hopL, 20 * hopL, 10.0)
    P["footR"] = (-0.125, 0.025, 0.03 * hopR, 20 * hopR, -10.0)
    clink = 0.02 * math.sin(4 * w * t)
    P["handL"] = (0.13 + clink, -0.12, 0.35, -0.3, -0.9, 0.3)
    P["handR"] = (-0.13 - clink, -0.12, 0.35, 0.3, -0.9, 0.3)
    return P


def death_drop(t, S_release):
    """Armature matrices of the dropped daggers at time t (None before the release)."""
    if t < DROP_T: return None
    out = {}
    for s, sg in SIDES:
        M0 = S_release[s]
        p0, r0 = M0.translation, M0.to_quaternion()
        pf = Vector((sg * 0.30, 0.02 + 0.04 * sg, 0.02))
        rf = Matrix(((0.0, 0.0, 1.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))).to_quaternion()
        d = Vector((sg * 0.55, -0.83, 0.0)).normalized(); u = Vector((0, 0, 1))
        rf = Matrix((d.cross(u), d, u)).transposed().to_quaternion()
        s_ = min(1.0, (t - DROP_T) / (LAND_T - DROP_T))
        p = p0.lerp(pf, s_); p.z = p0.z + (pf.z - p0.z) * s_ * s_
        p.z += 0.02 * math.sin(math.pi * min(1.0, max(0.0, (t - LAND_T) / 0.1)))   # one small bounce
        r = r0.slerp(rf, smooth(s_) if t < LAND_T + 0.1 else 1.0)
        out[s] = Matrix.Translation(p) @ r.to_matrix().to_4x4()
    return out


CLIPS = {   # name: (pose(t) function, length, loop, marks)
    "idle": (idle, IDLE_LEN, True, None),
    "run": (run, RUN_LEN, True, None),
    "attack_1": (lambda t: keyed(A1, t), 0.90, False, (0.20, 0.43)),
    "attack_2": (lambda t: keyed(A2, t), 1.80, False, (0.60, 0.92)),
    "hit": (lambda t: keyed(HIT, t), 0.50, False, None),
    "death": (lambda t: keyed(DEATH, t), 2.20, False, None),
    "taunt": (taunt, TAUNT_LEN, True, None),
}


# ---------------------------------------------------------------- bake
def apply_pose(S):
    for n in ORDER:
        pb = rig.pose.bones[n]; pb.rotation_mode = 'QUATERNION'
        loc, rq, _ = S.basis[n].decompose()
        pb.location = loc; pb.rotation_quaternion = rq
    bpy.context.view_layer.update()

def mesh_min_z():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg); me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    return float(co.reshape(-1, 3)[:, 2].min())

def footwork(name, frames, ground_v=0.0):
    """ground_v: the floor's speed toward +y under a looping run (planted feet move with it, not slide)."""
    st = dict(slide=0.0, low=9.0, cave=-9.0, air=0, miss=0.0, leg=0.0)
    run_ = {"L": None, "R": None}
    for f, S in frames:
        for s, sg in SIDES:
            ball = S.M["toe." + s].translation - Vector((0, ground_v * f / FPS, 0)); ankle = S.M["foot." + s].translation; knee = S.M["shin." + s].translation
            hip = S.M["thigh." + s].translation; tip = S.M["toe." + s] @ Vector((0, LEN["toe." + s], 0))
            st["low"] = min(st["low"], ball.z - BALL0[s].z, tip.z - BALL0[s].z, ankle.z - 0.02)
            if ball.z - BALL0[s].z < 0.01:
                run_[s] = ball.copy() if run_[s] is None else run_[s]
                st["slide"] = max(st["slide"], (ball - run_[s]).xy.length)
            else:
                run_[s] = None
            toe = (ball - ankle).xy
            if toe.length > 1e-4:
                n = (ankle - hip).cross(Vector((toe.x, toe.y, 0)).normalized()).normalized()
                other = S.M["foot." + ("R" if s == "L" else "L")].translation
                n = n if n.dot(other - ankle) > 0 else -n
                st["cave"] = max(st["cave"], (knee - hip).dot(n))
        st["miss"] = max(st["miss"], S.miss); st["leg"] = max(st["leg"], S.leg_miss)
    print("FOOTWORK %-8s planted slide %.1f cm | lowest ball/toe-tip/ankle vs floor %+.1f cm | knee in of toe line %.1f cm | leg reach miss %.1f cm | arm reach miss %.1f cm"
          % (name, 100 * st["slide"], 100 * st["low"], 100 * st["cave"], 100 * st["leg"], 100 * st["miss"]))
    return st

meta, baked = {}, {}
report = {}
for name, (fn, length, loop, marks) in CLIPS.items():
    act = bpy.data.actions.new(name); rig.animation_data.action = act
    n_f = int(round(length * FPS)); frames = []
    release = None; prevq = {}
    for f in range(n_f + 1):
        t = f / FPS
        P = fn(t)
        drop = None
        if name == "death":
            if release is None and t >= DROP_T:
                S0 = solve(fn(DROP_T)); release = {s: S0.M["attach_weapon." + s].copy() for s, _ in SIDES}
            drop = death_drop(t, release) if release else None
        S = solve(P, drop)
        if name == "death" and t >= 0.85:      # keep the body on (not in) the floor while it falls and lies
            for _ in range(2):
                apply_pose(S); mz = mesh_min_z()
                if mz >= 0.0 and t < 1.15: break
                P = dict(P); P["hips"] = (P["hips"][0], P["hips"][1], P["hips"][2] - mz)
                S = solve(P, drop)
        frames.append((f, S))
        for n in ORDER:
            pb = rig.pose.bones[n]; pb.rotation_mode = 'QUATERNION'
            loc, rq, _ = S.basis[n].decompose()
            if n in prevq and prevq[n].dot(rq) < 0: rq.negate()
            prevq[n] = rq
            pb.location = loc; pb.rotation_quaternion = rq
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    report[name] = footwork(name, frames, RUN_SPEED if name == "run" else 0.0)
    baked[name] = frames
    m = {"length": n_f / FPS, "loop": loop}
    if marks: m["windup_end"], m["strike_end"] = marks
    meta[name] = m
    rig.animation_data.action = None
    trk = rig.animation_data.nla_tracks.new(); trk.name = name; trk.strips.new(name, 0, act)
print("RUN stride authored for %.2f m/s at playback rate 1.0" % RUN_SPEED)

# ---------------------------------------------------------------- previews
if "nopreview" not in ARGS:
    os.makedirs(PREVIEW, exist_ok=True)
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.render.resolution_x = sc.render.resolution_y = 300
    w = sc.world or bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.57, 0.52, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sc.collection.objects.link(sun)
    sun.data.energy = 3.0; sun.rotation_euler = (R(35), 0, R(25))
    bpy.ops.mesh.primitive_plane_add(size=4); floor = bpy.context.object
    fm = bpy.data.materials.new("floor"); fm.diffuse_color = (0.42, 0.44, 0.38, 1); floor.data.materials.append(fm)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'
    VIEWS = {"game": ((0, -2.7, 4.6), (0, -0.1, 0.35), 1.8), "front": ((0, -5, 0.5), (0, 0, 0.5), 1.6),
             "side": ((5, -0.05, 0.45), (0, -0.05, 0.45), 1.9)}
    SHOTS = {"idle": [0.0, 0.5, 0.9, 1.15, 1.7, 2.0, 3.3, 3.6, 4.1],
             "run": [i * RUN_T / 6 for i in range(6)],
             "attack_1": [0.0, 0.12, 0.20, 0.25, 0.30, 0.36, 0.43, 0.52, 0.65, 0.80],
             "attack_2": [0.0, 0.30, 0.56, 0.64, 0.72, 0.80, 0.92, 1.05, 1.20, 1.42, 1.62, 1.80],
             "hit": [0.0, 0.06, 0.14, 0.26, 0.40],
             "death": [0.07, 0.25, 0.45, 0.62, 0.75, 0.95, 1.15, 1.27, 1.45, 2.2],
             "taunt": [0.0, 0.2, 0.4, 0.6, 0.9, 1.2]}
    for name, times in SHOTS.items():
        act = bpy.data.actions[name]
        for tr in rig.animation_data.nla_tracks: tr.mute = True
        rig.animation_data.action = act
        for i, t in enumerate(times):
            sc.frame_set(int(round(t * FPS)))
            for v, (loc, tgt, scale) in VIEWS.items():
                cam.location = loc; cam.data.ortho_scale = scale
                cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
                sc.render.filepath = os.path.join(PREVIEW, "_tiles", "%s_%02d_%s.png" % (name, i, v))
                bpy.ops.render.render(write_still=True)
        rig.animation_data.action = None
    print("PREVIEW tiles written")

# ---------------------------------------------------------------- export
for tr in rig.animation_data.nla_tracks: tr.mute = False
rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
for o in bpy.data.objects: o.select_set(o == rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=True, export_animations=True,
                          export_animation_mode='ACTIONS', export_skins=True, export_def_bones=False)
with open(OUT_JSON, "w", newline="\n") as fh:
    json.dump(meta, fh, indent=2)
print("GOBLIN_ANIMS", json.dumps(meta))

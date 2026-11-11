"""Goblin family animation sets: art/animations/goblin_<v>.glb (+ .json) for v = archer, mage, knight, chief.

    blender -b --factory-startup -P tools/blender/goblin_family_anims.py -- [archer mage knight chief] [noqa] [nopreview] [only=clip,clip]

Each variant has its own clips on its own rig (the goblin's 27 bones + bow_string / hat_tip / grip_offhand).
Every frame is solved in Python like goblin_anims.py: keyed channels + procedural layers, two-bone IK for
legs (the ball of the foot is the pivot of a planted foot) and arms, everything baked as plain FK keys at 60 fps.
Hand channels are wrist point + prop direction (+ optional prop "up" axis = attach bone Z) in chest space,
blended to armature space with ws<side> (1 = the hand is fixed in the world, e.g. a sword tip on the floor).
Extras: slide<side> = the prop slides through the fist along its axis (attach bone position; the client plays
it), draw = bow_string pull (0..0.25 along the bone), offL = the left fist on the knight's hilt (grip_offhand),
hat = hat_tip (pitch, roll), tw<side> = prop twirl about the attach Z axis, grip<side> = 1: the hand point is
the prop's grip (attach origin), not the wrist; tipz<side> = (h, L, w): the prop point L along its axis (negative =
behind the grip) is pulled to height h (armature) with weight w, keeping its heading.
QA per clip (printed "FAM ..."): accessory-vs-body and prop-vs-body intersecting triangle pairs (as
preview_goblin_family.py counts them, the holding fist excluded), lowest prop point, footwork. Previews:
art_source/preview/goblin_family/<v>/<clip>.png (rows: game camera, front, side).
"""
import bpy, os, sys, json, math
import numpy as np
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ALL = ["archer", "mage", "knight", "chief"]
VARIANTS = [a for a in ARGS if a in ALL] or ALL
ONLY = next((a[5:].split(",") for a in ARGS if a.startswith("only=")), None)
FPS = 60
R = math.radians
SCALE = {"archer": 1.06, "mage": 1.0, "knight": 1.28, "chief": 1.72}
RUN_REF = 2.44   # client/fighter_view.gd MONSTER_RUN_SPEED: a run plays at speed / (2.44 x fit); author it at 2.44 goblin units/s


def qx(d): return Quaternion((1, 0, 0), R(d))
def qy(d): return Quaternion((0, 1, 0), R(d))
def qz(d): return Quaternion((0, 0, 1), R(d))
def qe(p, r=0.0, y=0.0): return qz(y) @ qx(p) @ qy(r)
def smooth(x): x = min(1.0, max(0.0, x)); return x * x * (3 - 2 * x)
def bump(t, t0, dur, rise=0.3):
    if t < t0 or t > t0 + dur: return 0.0
    s = (t - t0) / dur
    return smooth(s / rise) if s < rise else 1.0 - smooth((s - rise) / (1 - rise))
def lerp(a, b, s): return tuple(x + (y - x) * s for x, y in zip(a, b)) if isinstance(a, tuple) else a + (b - a) * s
def add(a, b): return tuple(x + y for x, y in zip(a, b))
def wave(t, L, k, ph=0.0): return math.sin(2 * math.pi * k * t / L + ph)


class Rig:
    def __init__(self, rig):
        self.rig = rig
        self.REST = {b.name: b.matrix_local.copy() for b in rig.data.bones}
        self.PARENT = {b.name: (b.parent.name if b.parent else None) for b in rig.data.bones}
        self.LEN = {b.name: b.length for b in rig.data.bones}
        self.ORDER = []
        while len(self.ORDER) < len(self.REST):
            for n in self.REST:
                if n not in self.ORDER and (self.PARENT[n] is None or self.PARENT[n] in self.ORDER): self.ORDER.append(n)
        self.BALL0 = {s: self.REST["toe." + s].translation.copy() for s in "LR"}
        self.ANKLE_OFF = {s: self.REST["foot." + s].translation - self.BALL0[s] for s in "LR"}
        self.HAND_REL = {s: self.REST["hand." + s].to_quaternion().inverted() @ self.REST["attach_weapon." + s].to_quaternion() for s in "LR"}
        self.GRIP_OFF = {s: (self.REST["hand." + s].inverted() @ self.REST["attach_weapon." + s]).translation for s in "LR"}

G = None  # the bound Rig


class Poser:
    def __init__(self):
        self.basis, self.M = {}, {}
        self.miss = {"leg": 0.0, "arm": 0.0}

    def m0(self, n):
        p = G.PARENT[n]
        return G.REST[n].copy() if p is None else self.M[p] @ G.REST[p].inverted() @ G.REST[n]

    def put(self, n, basis):
        self.basis[n] = basis; self.M[n] = self.m0(n) @ basis

    def rot(self, n, q, loc=None):
        r = G.REST[n].to_quaternion()
        b = (r.inverted() @ q @ r).to_matrix().to_4x4()
        if loc is not None: b = Matrix.Translation(r.inverted() @ Vector(loc)) @ b
        self.put(n, b)

    def aim(self, n, d):
        M0 = self.m0(n); R0 = M0.to_quaternion()
        q = (R0 @ Vector((0, 1, 0))).rotation_difference(d)
        self.put(n, (R0.inverted() @ q @ R0).to_matrix().to_4x4())

    def absrot(self, n, rq, loc=None):
        R0 = self.m0(n).to_quaternion()
        b = (R0.inverted() @ rq).to_matrix().to_4x4()
        if loc is not None: b = Matrix.Translation(Vector(loc)) @ b
        self.put(n, b)

    def two_bone(self, up, lo, target, pole, kind):
        A = self.m0(up).translation
        a, b = G.LEN[up], G.LEN[lo]
        v = target - A; d = v.length
        self.miss[kind] = max(self.miss[kind], d - (a + b) * 0.999)
        d = min(max(d, abs(a - b) + 1e-3), (a + b) * 0.999)
        u = v.normalized()
        c = (a * a + d * d - b * b) / (2 * a * d); s = math.sqrt(max(0.0, 1 - c * c))
        w = pole - u * pole.dot(u); w.normalize()
        knee = A + a * (c * u + s * w)
        self.aim(up, (knee - A).normalized())
        self.aim(lo, (A + u * d - knee).normalized())


def prop_rot(d, z=None):
    """Attach-bone rotation with its Y (the prop's axis) along d and Z along z (or the nearest 'up')."""
    d = d.normalized()
    hint = z if z is not None else (Vector((0, 0, 1)) if abs(d.z) < 0.8 else Vector((0, -1, 0)))
    u = (hint - d * hint.dot(d)); u = u.normalized() if u.length > 1e-6 else Vector((1, 0, 0))
    return Matrix((d.cross(u), d, u)).transposed().to_quaternion()


def solve(P, drop=None):
    S = Poser()
    S.put("root", Matrix.Identity(4))
    S.rot("hips", qe(*P["hipsr"]), P["hips"])
    for n in ("spine", "chest", "neck", "head"):
        S.rot(n, qe(*P[n]))
    S.rot("jaw", qx(P["jaw"]))
    for s, sg in (("L", 1), ("R", -1)):
        back, droop = P["ear" + s]
        S.rot("ear." + s, qz(sg * back) @ qy(sg * droop))
        S.rot("ear_tip." + s, qy(sg * P["tip" + s]))
    if "hat_tip" in G.REST: S.rot("hat_tip", qe(P["hat"][0], P["hat"][1], 0))
    for s, sg in (("L", 1), ("R", -1)):
        bx, by, lift, pitch, yaw = P["foot" + s]
        fr = qz(yaw) @ qx(pitch)
        # the mesh's toes are weighted to the foot bone: a heel peel pivots on the toe tip (0.045 ahead of the
        # ball), a toe-up foot on the heel (0.15 behind), so neither end sinks into the floor
        sp = math.sin(math.radians(pitch))
        ball = Vector((bx, by, G.BALL0[s].z + lift + (0.045 * sp if sp > 0 else -0.15 * sp)))
        ankle = ball + fr @ G.ANKLE_OFF[s]
        pole = P.get("knee" + s) or (qz(yaw) @ Vector((0, -1, 0)) + Vector((sg * 0.25, 0, 0)))
        S.two_bone("thigh." + s, "shin." + s, ankle, Vector(pole), "leg")
        S.absrot("foot." + s, fr @ G.REST["foot." + s].to_quaternion())
        S.rot("toe." + s, qx(-pitch * (1.0 - 0.6 * smooth(lift / 0.03))))   # toes stay flat near the floor
    C = S.M["chest"] @ G.REST["chest"].inverted(); C3 = C.to_3x3()

    def target(s):
        h = P["hand" + s]; ws = P.get("ws" + s, 0.0)
        p = (C @ Vector(h[:3])).lerp(Vector(h[:3]), ws)
        rel = P.get("rel" + s, 0.0)      # 1: the wrist = shoulder + (x, y, z), armature axes
        if rel > 0:
            p = p.lerp(S.m0("upper_arm." + s).translation + Vector(h[:3]), rel); ws = max(ws, rel)
        d = (C3 @ Vector(h[3:6])).lerp(Vector(h[3:6]), ws)
        z = None
        if len(h) >= 9: z = (C3 @ Vector(h[6:9])).lerp(Vector(h[6:9]), ws)
        return p, d, z

    def fix(s, p, d, z):
        """grip<s>: the hand point is the prop's grip (attach origin), not the wrist. tipz<s> = (h, L): the
        prop point L along its axis (negative = the butt) sits at height h (armature), heading kept."""
        g = P.get("grip" + s, 0.0); tz = P.get("tipz" + s)
        if not g and not tz: return p, d, z
        d = d.normalized(); p0 = p.copy()
        if tz and (len(tz) < 3 or tz[2] > 0) and not (len(tz) > 3 and tz[3]): z = Vector((0, 0, 1))   # the blade lies flat to the floor
        for _ in range(3):
            Ra = prop_rot(d, z)
            off = (Ra @ G.HAND_REL[s].inverted()) @ G.GRIP_OFF[s]
            p = p0 - off * g
            if tz:
                h, L = tz[0], tz[1]; w = tz[2] if len(tz) > 2 else 1.0
                gp = p + off
                hd = Vector((d.x, d.y, 0.0)); hd = hd.normalized() if hd.length > 1e-6 else Vector((0, -1, 0))
                dz = max(-0.999, min(0.999, (h - gp.z) / L))
                dn = hd * math.sqrt(1 - dz * dz) + Vector((0, 0, dz))
                d = d.lerp(dn, w).normalized()
        return p, d, z

    def arm(s, sg, wrist, Ra):
        pole = C3 @ Vector(P.get("elbow" + s, (sg * 0.7, 0.6, -0.2)))
        S.two_bone("upper_arm." + s, "forearm." + s, wrist, pole, "arm")
        al = P.get("align" + s, 0.0); fl = P.get("floor" + s)
        if al > 0 or fl:
            d = Ra @ Vector((0, 1, 0)); zz = Ra @ Vector((0, 0, 1))
            if al > 0:   # a straight wrist: the prop extends the forearm, so a short handle lies inside it
                d = d.lerp(S.M["forearm." + s].to_quaternion() @ Vector((0, 1, 0)), al).normalized()
            if fl:       # floor<side> = (h, L): the point L along the prop never goes below h
                h, L = fl[0], fl[1]
                g = wrist + (prop_rot(d, zz) @ G.HAND_REL[s].inverted()) @ G.GRIP_OFF[s]
                if g.z + L * d.z < h:
                    hd = Vector((d.x, d.y, 0.0)); hd = hd.normalized() if hd.length > 1e-6 else Vector((0, -1, 0))
                    dz = max(-0.999, min(0.999, (h - g.z) / L))
                    d = hd * math.sqrt(1 - dz * dz) + Vector((0, 0, dz))
            Ra = prop_rot(d, zz)
        S.absrot("hand." + s, Ra @ G.HAND_REL[s].inverted())

    def attach(s):
        n = "attach_weapon." + s
        if drop and s in drop:
            S.put(n, S.m0(n).inverted() @ drop[s]); return
        b = Quaternion((0, 0, 1), R(P.get("tw" + s, 0.0))).to_matrix().to_4x4()
        S.put(n, Matrix.Translation((0, P.get("slide" + s, 0.0), 0)) @ b)

    def left():
        p, d, z = target("L"); p, d, z = fix("L", p, d, z); RaL = prop_rot(d, z)
        off = P.get("offL", 0.0)
        if off > 0 and "grip_offhand" in G.REST:
            MR = S.M["attach_weapon.R"]
            gpt = MR @ Vector((0, P.get("offAt", -0.135), 0))
            Rs = MR.to_quaternion() @ Quaternion((0, 1, 0), R(P.get("offTw", 0.0)))
            wrist = gpt - (Rs @ G.HAND_REL["L"].inverted()) @ G.GRIP_OFF["L"]
            p = p.lerp(wrist, off); RaL = RaL.slerp(Rs, off)
        arm("L", 1, p, RaL); attach("L")
        if "bow_string" in G.REST: S.put("bow_string", Matrix.Translation((0, P.get("draw", 0.0), 0)))

    def right():
        p, d, z = target("R"); p, d, z = fix("R", p, d, z); RaR = prop_rot(d, z)
        nock = P.get("nock", 0.0)
        if nock > 0 and "bow_string" in G.REST:     # the arrow's nock on the string, pointing at the bow grip
            spt = S.M["bow_string"].translation
            grip = S.M["attach_weapon.L"].translation
            ad = (grip - spt).normalized()
            Ra = prop_rot(ad, S.M["attach_weapon.L"].to_3x3() @ Vector((0, 1, 0)))
            Ra = Ra @ Quaternion((0, 1, 0), R(P.get("nockTw", 0.0)))
            gpt = spt + ad * P.get("nockOff", 0.015)   # the fist just ahead of the string
            wrist = gpt - (Ra @ G.HAND_REL["R"].inverted()) @ G.GRIP_OFF["R"]
            p = p.lerp(wrist, nock); RaR = RaR.slerp(Ra, nock)
        arm("R", -1, p, RaR); attach("R")
        if "grip_offhand" in G.REST: S.put("grip_offhand", Matrix.Identity(4))

    if P.get("nock", 0.0) > 0: left(); right()
    else: right(); left()
    return S


EASE = {"footL", "footR", "twL", "twR", "draw", "slideL", "slideR", "wsL", "wsR", "offL", "nock", "relL", "relR", "gripL", "gripR", "tipzL", "tipzR", "side", "push", "alignL", "alignR"}
def keyed(base, keys, t):
    P = dict(base)
    chans = {}
    for k_t, kv in keys:
        for c, v in kv.items(): chans.setdefault(c, []).append((k_t, v))
    for c, ks in chans.items():
        if ks[0][0] > 0: ks = [(0.0, base[c])] + ks
        if t <= ks[0][0]: P[c] = ks[0][1]; continue
        if t >= ks[-1][0]: P[c] = ks[-1][1]; continue
        i = max(j for j in range(len(ks)) if ks[j][0] <= t)
        (t1, v1), (t2, v2) = ks[i], ks[i + 1]
        s = (t - t1) / (t2 - t1)
        if c in EASE or v1 == v2:
            P[c] = lerp(v1, v2, smooth(s)); continue
        # time-aware Hermite (non-uniform Catmull-Rom): tangents scaled by the key spacing, so uneven keys do
        # not overshoot; a held value (equal neighbour) or the first / last key has a flat tangent.
        dt = t2 - t1
        def tan(j):
            if j <= 0 or j >= len(ks) - 1: return None
            (ta, va), (tb, vb) = ks[j - 1], ks[j + 1]
            if va == ks[j][1] or vb == ks[j][1]: return None
            return (va, vb, tb - ta)
        m1, m2 = tan(i), tan(i + 1)
        h00, h10, h01, h11 = 2 * s ** 3 - 3 * s * s + 1, s ** 3 - 2 * s * s + s, -2 * s ** 3 + 3 * s * s, s ** 3 - s * s
        def hm(k):
            a = v1[k] if k is not None else v1; b = v2[k] if k is not None else v2
            def m(mm):
                if mm is None: return 0.0
                va, vb, span = mm
                return ((vb[k] if k is not None else vb) - (va[k] if k is not None else va)) / span * dt
            return h00 * a + h10 * m(m1) + h01 * b + h11 * m(m2)
        P[c] = tuple(hm(k) for k in range(len(v1))) if isinstance(v1, tuple) else hm(None)
    return P


def periodic(ks, t, L):
    t = t % L
    n = len(ks) - 1
    i = max(j for j in range(n) if ks[j][0] <= t)
    (t1, v1), (t2, v2) = ks[i], ks[i + 1]
    v0 = ks[(i - 1) % n][1]; v3 = ks[(i + 2) % n][1]
    s = (t - t1) / (t2 - t1)
    return 0.5 * (2 * v1 + (-v0 + v2) * s + (2 * v0 - 5 * v1 + 4 * v2 - v3) * s * s + (-v0 + 3 * v1 - 3 * v2 + v3) * s ** 3)


def snap(ks, t, fast=10):
    for (t1, v1), (t2, v2) in zip(ks, ks[1:]):
        if t1 <= t <= t2:
            s = (t - t1) / (t2 - t1)
            s = 1 - (1 - s) ** 3 if abs(v2 - v1) > fast else smooth(s)
            return v1 + (v2 - v1) * s
    return ks[-1][1]


# ---------------------------------------------------------------- run generator
def run_pose(t, base, rp):
    """rp: T (stride s), duty, sweep (front, back ball y), x (foot half width), lift, drop (hips z at mid stance),
    bob, lean, roll, yaw, chest_yaw, head (pitch), arms(P, ph, c) -> hand channels."""
    P = dict(base)
    T, duty = rp["T"], rp["duty"]
    ph = t / T
    def foot(phi, sg):
        f0, f1 = rp["sweep"]
        if phi < duty:
            s = phi / duty
            by = lerp(f0, f1, s); lift = 0.0
            pitch = rp.get("peel", 30) * s * s     # lands flat on the ball (a heel-down pitch would sink the heel)
        else:
            s = (phi - duty) / (1 - duty)
            by = f1 + (f0 - f1) * smooth(s)
            lift = rp["lift"] * math.sin(math.pi * s ** 0.8)
            pk = [(0, rp.get("peel", 30)), (0.3, rp.get("peel", 30) + 15), (0.75, 4), (1.0, 0)]
            pitch = next(lerp(a[1], b[1], smooth((s - a[0]) / (b[0] - a[0]))) for a, b in zip(pk, pk[1:]) if s <= b[0])
        return (sg * rp["x"], by, lift, pitch, sg * rp.get("toe", 6.0))
    P["footL"] = foot(ph % 1.0, 1); P["footR"] = foot((ph + 0.5) % 1.0, -1)
    c = math.cos(2 * math.pi * (ph - duty / 2))
    bob = math.cos(2 * math.pi * (2 * ph - duty))
    P["hips"] = (rp.get("sway", 0.012) * c, 0.0, rp["drop"] + rp["bob"] * (1 - bob) / 2)
    P["hipsr"] = (rp["lean"] + 2 * math.cos(2 * math.pi * (2 * ph - duty - 0.15)), -rp["roll"] * c, -rp["yaw"] * math.cos(2 * math.pi * ph))
    P["spine"] = rp.get("spine", (6, 0, 0))
    P["chest"] = add(rp.get("chest", (4, 0, 0)), (2 * math.cos(2 * math.pi * (2 * ph - 0.5)), 3 * c, rp["chest_yaw"] * math.cos(2 * math.pi * ph)))
    P["neck"] = rp.get("neck", (-10, 0, 0))
    P["head"] = (rp["head"] - 3 * math.cos(2 * math.pi * (2 * ph - duty - 0.3)), -2 * c, -0.3 * (rp["chest_yaw"] - rp["yaw"]) * math.cos(2 * math.pi * ph))
    P["jaw"] = rp.get("jaw", 7) + 4 * math.sin(2 * math.pi * ph)
    tw = 3 * math.sin(4 * math.pi * ph)
    P["earL"] = rp.get("ears", (28, 8)); P["earR"] = rp.get("ears", (28, 8))
    P["tipL"] = 4 + tw; P["tipR"] = 4 - tw
    if "hat" in base: P["hat"] = (-8 + 4 * math.cos(2 * math.pi * (2 * ph - 0.5)), 3 * c)
    rp["arms"](P, ph, c)
    return P


# ---------------------------------------------------------------- dropped props (death)
def drop_path(t, t0, t1, M0, final, bounce=0.02):
    """M0: armature matrix at release; final: armature matrix lying on the floor."""
    if t < t0: return None
    s = min(1.0, (t - t0) / (t1 - t0))
    p0, pf = M0.translation, final.translation
    p = p0.lerp(pf, s); p.z = p0.z + (pf.z - p0.z) * s * s
    p.z += bounce * math.sin(math.pi * min(1.0, max(0.0, (t - t1) / 0.12)))
    r = M0.to_quaternion().slerp(final.to_quaternion(), smooth(s * 1.15))
    return Matrix.Translation(p) @ r.to_matrix().to_4x4()

def lying(pos, d, side_up=False, lift=0.0):
    d = Vector(d).normalized()
    z = Vector((0, 0, 1)) if not side_up else d.cross(Vector((0, 0, 1))).normalized()
    return Matrix.Translation(Vector(pos) + Vector((0, 0, lift))) @ prop_rot(d, z).to_matrix().to_4x4()


# ================================================================= variants
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from goblin_family_clips import VARIANT_CLIPS   # noqa: E402  (clip definitions, next to this script)


# ---------------------------------------------------------------- QA
def bvh_of(o):
    dg = bpy.context.evaluated_depsgraph_get(); e = o.evaluated_get(dg); me = e.to_mesh()
    n = len(me.vertices); co = np.empty(n * 3); me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3) @ np.array(e.matrix_world.to_3x3()).T + np.array(e.matrix_world.translation)
    ps = [tuple(p.vertices) for p in me.polygons]
    e.to_mesh_clear()
    return BVHTree.FromPolygons([Vector(v) for v in co], ps), co


def apply_pose(rig, S):
    for n in G.ORDER:
        pb = rig.pose.bones[n]; pb.rotation_mode = 'QUATERNION'
        loc, rq, _ = S.basis[n].decompose()
        pb.location = loc; pb.rotation_quaternion = rq
    bpy.context.view_layer.update()


class QA:
    def __init__(self, vname, rig, body, accs, props):
        self.vname, self.rig, self.body, self.accs, self.props = vname, rig, body, accs, props
        names = [g.name for g in body.vertex_groups]
        vb = [max(v.groups, key=lambda g: g.weight).group if v.groups else -1 for v in body.data.vertices]
        self.dom = [names[vb[p.vertices[0]]] if vb[p.vertices[0]] >= 0 else "" for p in body.data.polygons]
        self.vdom = [names[g] if g >= 0 else "" for g in vb]
        self.base = {}
        apply_pose(rig, rest_poser())
        bb, _ = bvh_of(body)
        for o in accs:
            ob, _ = bvh_of(o); self.base[o.name] = len(bb.overlap(ob))

    def side_of(self, o):
        return o.parent_bone.split(".")[-1] if o.parent_type == 'BONE' else "L"

    def frame(self, S, worst, f, skip=None, hidden=()):
        """skip: {prop: [body groups it may touch]} (a fist on the string, an arrow on the bow hand);
        hidden: props the game does not show at this moment (the nocked arrow outside its window)."""
        apply_pose(self.rig, S)
        skip = skip or {}
        bb, bco = bvh_of(self.body)
        for o in self.accs:
            ob, _ = bvh_of(o); ov = bb.overlap(ob)
            n = max(0, len(ov) - self.base[o.name])
            if n > worst.get(o.name, (0,))[0]:
                hist = {}
                for pr in ov: hist[self.dom[pr[0]]] = hist.get(self.dom[pr[0]], 0) + 1
                worst[o.name] = (n, f, hist)
        for o in self.props:
            if o.name in hidden: continue
            ob, vs = bvh_of(o); sd = self.side_of(o)
            ok = ("hand." + sd, "forearm." + sd) + tuple(skip.get(o.name, ()))
            pairs = [pr for pr in bb.overlap(ob) if self.dom[pr[0]] not in ok]
            if len(pairs) > worst.get(o.name, (0,))[0]:
                hist = {}
                for pr in pairs: hist[self.dom[pr[0]]] = hist.get(self.dom[pr[0]], 0) + 1
                worst[o.name] = (len(pairs), f, hist)
            gz = float(vs[:, 2].min())
            if gz < worst.get(o.name + "@ground", (0, 0, 0.0))[2]: worst[o.name + "@ground"] = (0, f, gz)
        gz = float(bco[:, 2].min())
        if gz < worst.get("body@ground", (0, 0, 0.0))[2]: worst["body@ground"] = (0, f, gz, self.vdom[int(bco[:, 2].argmin())])

    def report(self, clip, worst):
        out = []
        for nm, val in sorted(worst.items()):
            if nm.endswith("@ground"):
                if val[2] < -0.005: out.append("%s below ground %.3f (f%d%s)" % (nm[:-7], val[2], val[1], " " + val[3] if len(val) > 3 else ""))
            elif val[0]:
                out.append("%s %d pairs (f%d) %s" % (nm, val[0], val[1], val[2]))
        print("FAM %s %-11s QA %s" % (self.vname, clip, "; ".join(out) if out else "clean"))
        return out


def rest_poser():
    S = Poser()
    for n in G.ORDER: S.put(n, Matrix.Identity(4))
    return S


def footwork(vname, clip, frames, ground_v=0.0):
    st = dict(slide=0.0, low=9.0, cave=-9.0)
    run_ = {"L": None, "R": None}
    miss = {"leg": 0.0, "arm": 0.0}
    for f, S in frames:
        for s in "LR":
            ball = S.M["toe." + s].translation - Vector((0, ground_v * f / FPS, 0))
            ankle = S.M["foot." + s].translation; knee = S.M["shin." + s].translation; hip = S.M["thigh." + s].translation
            tip = S.M["toe." + s] @ Vector((0, G.LEN["toe." + s], 0))
            st["low"] = min(st["low"], ball.z - G.BALL0[s].z, tip.z - G.BALL0[s].z, ankle.z - 0.02)
            if ball.z - G.BALL0[s].z < 0.006:
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
        for k in miss:
            if S.miss[k] > miss[k]: miss[k] = S.miss[k]; st[k + "_f"] = f
    line = ("slide %.1f cm | lowest foot %+.1f cm | knee in %.1f cm | leg miss %.1f cm (f%d) | arm miss %.1f cm (f%d)"
            % (100 * st["slide"], 100 * st["low"], 100 * st["cave"], 100 * miss["leg"], st.get("leg_f", 0), 100 * miss["arm"], st.get("arm_f", 0)))
    print("FAM %s %-11s FOOT %s" % (vname, clip, line))
    return line


# ---------------------------------------------------------------- preview
def preview_setup():
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.render.resolution_x = sc.render.resolution_y = 300
    w = sc.world or bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.57, 0.52, 1)
    if "pv_sun" not in bpy.data.objects:
        sun = bpy.data.objects.new("pv_sun", bpy.data.lights.new("pv_sun", 'SUN')); sc.collection.objects.link(sun)
        sun.data.energy = 3.0; sun.rotation_euler = (R(35), 0, R(25))
        bpy.ops.mesh.primitive_plane_add(size=6); fl = bpy.context.object; fl.name = "pv_floor"
        fm = bpy.data.materials.new("pv_floor"); fm.diffuse_color = (0.42, 0.44, 0.38, 1); fl.data.materials.append(fm)
        cam = bpy.data.objects.new("pv_cam", bpy.data.cameras.new("pv_cam")); sc.collection.objects.link(cam)
    sc.camera = bpy.data.objects["pv_cam"]
    return sc, bpy.data.objects["pv_cam"]


GAME_DIR = Vector((0, -1, 1)).normalized()   # the game camera (0, 7, 7) looking at the fighter
def render_sheet(rig, poses, out, size, hides=None):
    sc, cam = preview_setup()
    files = []
    for view in ("game", "front", "side"):
        for i, S in enumerate(poses):
            apply_pose(rig, S)
            for o in bpy.data.objects:
                if o.type == 'MESH' and not o.name.startswith("pv_"): o.hide_render = bool(hides and o.name in hides[i])
            tgt = Vector((0, -0.15, size * 0.38))
            if view == "game":
                cam.data.type = 'PERSP'; cam.data.sensor_fit = 'VERTICAL'
                cam.data.angle_y = 2 * math.atan(size / 2 / 9.9); cam.location = tgt + GAME_DIR * 9.9
            else:
                cam.data.type = 'ORTHO'; cam.data.sensor_fit = 'AUTO'; cam.data.ortho_scale = size
                cam.location = tgt + (Vector((0, -6, 0.3)) if view == "front" else Vector((6, 0, 0.3)))
            cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
            p = out + "_%s_%02d.png" % (view, i); sc.render.filepath = p
            bpy.ops.render.render(write_still=True); files.append(p)
    ims = []
    for f in files:
        im = bpy.data.images.load(f); w, h = im.size
        ims.append(np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)); bpy.data.images.remove(im); os.remove(f)
    cols = len(poses); h, w = ims[0].shape[:2]; rows = 3
    Sh = np.ones((h * rows, w * cols, 4), dtype=np.float32)
    for i, im in enumerate(ims):
        r = rows - 1 - i // cols; Sh[r * h:(r + 1) * h, (i % cols) * w:(i % cols + 1) * w] = im
        Sh[r * h:(r + 1) * h, (i % cols) * w, :3] = 0.3
    o = bpy.data.images.new("sheet", w * cols, h * rows); o.pixels.foreach_set(Sh.ravel())
    o.filepath_raw = out + ".png"; o.file_format = 'PNG'; o.save(); bpy.data.images.remove(o)


# ---------------------------------------------------------------- main
def mesh_min_z(objs):
    return min(float(bvh_of(o)[1][:, 2].min()) for o in objs)


def hidden_at(spec, c, t):
    """The props the game hides at time t of clip c: the nocked arrow (spec["nock"]) shows only inside the
    clip's "show" window (from the move's start to its spawn frame), as client/fighter_view.gd does."""
    n = spec.get("nock")
    if not n: return ()
    w = c.get("show", {}).get(n)
    return () if w and w[0] <= t < w[1] else (n,)


def build(v):
    global G
    vname = "goblin_" + v
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "art_source/monsters", vname, vname + ".blend"))
    sc = bpy.context.scene; sc.render.fps = FPS
    rig = bpy.data.objects[vname + "_rig"]; body = bpy.data.objects[vname]
    for o in [o for o in bpy.data.objects if o.name.endswith("_mesh")]: bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions): bpy.data.actions.remove(a)
    rig.animation_data_create(); rig.animation_data.action = None
    for t in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(t)
    G = Rig(rig)
    accs = [o for o in bpy.data.objects if o.type == 'MESH' and o.parent == rig and o.parent_type != 'BONE' and o != body and o.name != "bow"]
    props = [o for o in bpy.data.objects if o.type == 'MESH' and (o.parent_type == 'BONE' or o.name == "bow")]
    skinned = [body] + accs
    spec = VARIANT_CLIPS[v](globals())
    qa = QA(vname, rig, body, accs, props) if "noqa" not in ARGS else None
    meta, summary, made = {}, {}, []
    pdir = os.path.join(ROOT, "art_source/preview/goblin_family", v); os.makedirs(pdir, exist_ok=True)
    for name, c in spec["clips"].items():
        if ONLY and name not in ONLY: continue
        fn, length, loop = c["fn"], c["length"], c.get("loop", False)
        rig.animation_data.action = None   # solve, QA and render with no action on the rig, key at the end
        n_f = int(round(length * FPS)); frames = []; prevq = {}; worst = {}
        drop_fn = c.get("drop")
        rel = None
        for f in range(n_f + 1):
            t = f / FPS
            P = fn(t)
            drop = None
            if drop_fn:
                if rel is None and t >= drop_fn["t0"]:
                    S0 = solve(fn(drop_fn["t0"])); rel = {s: S0.M["attach_weapon." + s].copy() for s in drop_fn["final"]}
                if rel: drop = {s: drop_path(t, drop_fn["t0"], drop_fn["t1"], rel[s], drop_fn["final"][s]) for s in rel}
            S = solve(P, drop)
            if c.get("ground_from") is not None and t >= c["ground_from"]:   # the body rests on (not in) the floor
                for _ in range(2):
                    apply_pose(rig, S); mz = mesh_min_z(skinned)
                    if mz >= 0.0 and t < c.get("ground_lock", 9.0): break
                    P = dict(P); P["hips"] = (P["hips"][0], P["hips"][1], P["hips"][2] - mz)
                    if c.get("feet_follow") and t >= c["feet_follow"]:   # lying: the raised legs ride along
                        for k in ("footL", "footR"): P[k] = P[k][:2] + (P[k][2] - mz,) + P[k][3:]
                    S = solve(P, drop)
            frames.append((f, S))
            if qa and f % 2 == 0: qa.frame(S, worst, f, spec.get("qa_skip"), hidden_at(spec, c, t))
        if "nopreview" not in ARGS:
            shots = c.get("shots") or [length * k / 5 for k in range(6)]
            poses = [dict(frames)[min(n_f, int(round(s * FPS)))] for s in shots]
            render_sheet(rig, poses, os.path.join(pdir, name), spec.get("view", 1.6), [hidden_at(spec, c, s) for s in shots])
        act = bpy.data.actions.new(name); act.use_fake_user = True; rig.animation_data.action = act
        for f, S in frames:
            for n in G.ORDER:
                pb = rig.pose.bones[n]; pb.rotation_mode = 'QUATERNION'
                loc, rq, _ = S.basis[n].decompose()
                if n in prevq and prevq[n].dot(rq) < 0: rq.negate()
                prevq[n] = rq
                pb.location = loc; pb.rotation_quaternion = rq
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
        foot = footwork(vname, name, frames, c.get("ground_v", 0.0))
        qrep = qa.report(name, worst) if qa else []
        m = {"length": n_f / FPS, "loop": loop}
        if "marks" in c: m["windup_end"], m["strike_end"] = c["marks"]
        meta[name] = m
        summary[name] = (foot, qrep)
        for key, fn_ in c.get("probe", {}).items():   # spawn points etc. at a time
            print("FAM %s %-11s PROBE %s %s" % (vname, name, key, fn_(dict(frames)[int(round(c["probe_t"][key] * FPS))])))
        rig.animation_data.action = None
        made.append(act)
    # export (rig only; clips as actions)
    if not ONLY:
        for act in made:
            trk = rig.animation_data.nla_tracks.new(); trk.name = act.name; trk.strips.new(act.name, 0, act)
        for pb in rig.pose.bones: pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
        for o in bpy.data.objects: o.select_set(o == rig)
        bpy.context.view_layer.objects.active = rig
        out = os.path.join(ROOT, "art/animations", vname)
        bpy.ops.export_scene.gltf(filepath=out + ".glb", export_format='GLB', use_selection=True, export_animations=True,
                                  export_animation_mode='ACTIONS', export_skins=True, export_def_bones=False)
        with open(out + ".json", "w", newline="\n") as fh: json.dump(meta, fh, indent=2)
        print("FAM %s EXPORT %s" % (vname, json.dumps(meta)))


if __name__ == "__main__":
    for v in VARIANTS:
        build(v)

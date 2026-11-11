"""The goblin family: goblin_archer, goblin_mage, goblin_knight, goblin_chief, built on the approved goblin.

    blender -b --factory-startup -P tools/blender/build_goblin_variants.py [-- archer mage knight chief]

Every variant keeps the goblin's 27 bones exactly (same names, rest, rolls), so art/animations/goblin.glb
plays on it unchanged. The clips key every bone's rotation and the positions of hips/attach_weapon.*, so a
variant's proportions come from its mesh (limb girth, armour) and its size from the rig object's scale.
Extra bones are only added as children (bow_string, hat_tip, grip_offhand).
Starts from the pre-hunch cache of build_goblin.py (identical body, UVs, weights and hi-poly bake maps).
Accessories are parametric surfaces fitted to the body by ray casts: clean grids, clean UVs, painted in
their own (u, v). Skinned from the body's weights (cloth, armour) or rigid (hats, props).
Long props lie along their attach bone's +Y like the goblin's daggers: the goblin idle rolls
attach_weapon.R a full turn about +Y, which a prop along +Y survives.
Out per variant v: art/monsters/goblin_v/goblin_v.glb, art_source/monsters/goblin_v/goblin_v.blend,
art_source/monsters/goblin_v/textures/goblin_v_albedo.png (1024: body 640 px + accessory atlas).
"""
import bpy, bmesh, os, sys, math, subprocess
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CACHE = os.path.join(ROOT, "art_source/monsters/goblin/cache")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ALL = ["archer", "mage", "knight", "chief"]
SWORD_DIR = int(os.environ.get("SWORD_DIR", "1"))
EMBED_CLIPS = os.environ.get("GOBLIN_EMBED_CLIPS", "1") == "1"   # see build_variant: export
VARIANTS = [a for a in ARGS if a in ALL] or ALL
TEX = 1024
BODY_PX = 640                  # the goblin body atlas (UV [0, 0.9375]) scaled into [0, 0.625]
BINS = [(BODY_PX, 0, TEX - BODY_PX, TEX), (0, BODY_PX, BODY_PX, TEX - BODY_PX)]   # accessory atlas (x, y, w, h)
PAD = 6
HUNCH = {"spine": (10, 0, 0), "chest": (12, 0, 0), "neck": (-6, 0, 0), "head": (-16, 0, 0),      # = build_goblin.py
         "upper_arm.L": (12, 0, 0), "upper_arm.R": (12, 0, 0), "forearm.L": (18, 0, 0), "forearm.R": (18, 0, 0),
         "ear.L": (8, 0, 0), "ear.R": (8, 0, 0)}
HC = Vector((0, 0.02, 0.72))   # inside the head (pre-hunch)
LIGHT = np.array([0.3, -0.5, 0.8]) / np.linalg.norm([0.3, -0.5, 0.8])
R_ID = dict(skin=0, warm=1, inner_ear=2, iron=3, leather=4, strap=5, cloth=6, pants=7, boot=8, mouth=9, brass=10, gullet=11)

def V(*a): return Vector(a)
def sm(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t)

def ensure_cache():
    if not os.path.exists(os.path.join(CACHE, "goblin_prehunch.blend")):
        subprocess.run([bpy.app.binary_path, "-b", "--factory-startup", "-P", os.path.join(ROOT, "tools/blender/build_goblin.py")],
                       env=dict(os.environ, GOBLIN_STAGE="prehunch"), check=True)

# ------------------------------------------------------------------ numpy paint helpers (sRGB)
def _hash(ix, iy, seed):
    h = np.sin(ix * 127.1 + iy * 311.7 + seed * 74.7) * 43758.5453; return h - np.floor(h)
def vnoise(x, y, seed=0):
    ix, iy = np.floor(x), np.floor(y); fx, fy = x - ix, y - iy
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    a, b = _hash(ix, iy, seed), _hash(ix + 1, iy, seed); c, d = _hash(ix, iy + 1, seed), _hash(ix + 1, iy + 1, seed)
    top = a + (b - a) * fx; bot = c + (d - c) * fx
    return top + (bot - top) * fy
def fbm(x, y, seed=0): return 0.55 * vnoise(x, y, seed) + 0.3 * vnoise(x * 2.1, y * 2.1, seed + 1) + 0.15 * vnoise(x * 4.3, y * 4.3, seed + 2)
def col(c, n): return np.tile(np.array(c, float), (n, 1))
def mix(a, b, t):
    t = np.clip(np.asarray(t, float), 0, 1)
    if t.ndim == 1: t = t[:, None]
    return a * (1 - t) + np.asarray(b, float) * t
def band(x, c, w): return np.clip(1 - np.abs(x - c) / w, 0, 1)   # 1 at c, 0 beyond w

def felt(c, U, Vv, su=8, sv=8, amt=0.18, seed=0):
    n = len(U); return col(c, n) * (1 - amt / 2 + amt * fbm(U * su, Vv * sv, seed))[:, None]
def metal(c, U, Vv, rust=0.5, su=6, sv=6, seed=3, rustc=(0.52, 0.30, 0.17)):
    n = len(U); base = col(c, n) * (0.9 + 0.2 * fbm(U * su * 3, Vv * sv * 3, seed))[:, None]
    r = np.clip((fbm(U * su, Vv * sv, seed + 5) - (1 - rust * 0.5)) * 4, 0, 0.85)
    return mix(base, rustc, r)
def wood(c, U, Vv, sv=40, seed=7):
    n = len(U); g = 0.86 + 0.14 * np.sin(Vv * sv + 6 * fbm(U * 3, Vv * 2, seed)) * 0.5 + 0.08 * fbm(U * 20, Vv * 4, seed + 1)
    return col(c, n) * g[:, None]
def edges(cl, U, Vv, w=0.06, amt=1.18, u=False):   # brighten plate edges (v ends, optionally u ends)
    e = np.maximum(band(Vv, 0, w), band(Vv, 1, w))
    if u: e = np.maximum(e, np.maximum(band(U, 0, w), band(U, 1, w)))
    return cl * (1 + (amt - 1) * e)[:, None]
def rivets(cl, U, Vv, vrow, count, rc=(0.80, 0.74, 0.62), r=0.012, asp=1.0):
    for vr in vrow:
        cu = (np.floor(U * count) + 0.5) / count
        d = np.sqrt(((U - cu) * asp) ** 2 + (Vv - vr) ** 2)
        cl = np.where((d < r)[:, None], np.array(rc), cl)
        cl = np.where(((d >= r) & (d < r * 1.5))[:, None], cl * 0.55, cl)
    return cl

# ------------------------------------------------------------------ geometry helpers
def catmull(pts, s):
    n = len(pts) - 1; x = min(max(s, 0.0), 1.0) * n; i = min(int(x), n - 1); t = x - i
    p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, n)]
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)

def tube(path, radius, sides, front=V(0, -1, 0), start=0.0):
    """Rings around a polyline; radius(k, ang) or a list. Ring k starts at angle `start` from the `front` side."""
    rows, ef = [], None
    for k, p in enumerate(path):
        T = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
        e = (front if ef is None else ef); e = e - T * e.dot(T)
        if e.length < 1e-6: e = T.orthogonal()
        ef = e.normalized(); es = T.cross(ef)
        ring = []
        for j in range(sides):
            a = start + 2 * math.pi * j / sides
            r = radius(k, a) if callable(radius) else radius[k]
            ring.append(p + (ef * math.cos(a) + es * math.sin(a)) * r)
        rows.append(ring)
    return rows

class Part:
    """One surface grid with its own UV rectangle. group: 'acc' (skinned, joined into the body mesh on
    export) or a prop name (rigid on a bone, or skinned when `skin_prop`)."""
    def __init__(self, name, group, paint, weights, solid=None, flat=False, out=None):
        self.name, self.group, self.paint, self.weights, self.solid, self.flat, self.out = name, group, paint, weights, solid, flat, out
        self.V, self.F, self.UV, self.P = [], [], [], []      # P: per-vertex parameter for custom weights
        self.size = None; self.rect = None; self.mat = 0; self.bone = None
    def grid(self, rows, closed=False, pole0=None, pole1=None, u=(0.0, 1.0), v=(0.0, 1.0), param=None, mat=0):
        m, n = len(rows), len(rows[0]); base = len(self.V)
        nr = m + (pole0 is not None) + (pole1 is not None)
        def vr(i): return v[0] + (v[1] - v[0]) * ((i + (pole0 is not None)) / max(1, nr - 1))
        def uc(j): return u[0] + (u[1] - u[0]) * j / nc
        nc = n if closed else n - 1
        for i, r in enumerate(rows):
            self.V.extend(Vector(p) for p in r); self.P.extend([param[i] if param else 0.0] * n)
        for i in range(m - 1):
            for j in range(nc):
                j2 = (j + 1) % n
                self.F.append(((base + i * n + j, base + i * n + j2, base + (i + 1) * n + j2, base + (i + 1) * n + j), mat))
                self.UV.append([(uc(j), vr(i)), (uc(j + 1), vr(i)), (uc(j + 1), vr(i + 1)), (uc(j), vr(i + 1))])
        for pole, row, vv, first in ((pole0, 0, v[0], True), (pole1, m - 1, v[1], False)):
            if pole is None: continue
            p = len(self.V); self.V.append(Vector(pole)); self.P.append(param[0 if first else -1] if param else 0.0)
            for j in range(nc):
                j2 = (j + 1) % n; a, b = base + row * n + j, base + row * n + j2
                if first:
                    self.F.append(((p, b, a), mat)); self.UV.append([(uc(j + 0.5), vv), (uc(j + 1), vr(row)), (uc(j), vr(row))])
                else:
                    self.F.append(((a, b, p), mat)); self.UV.append([(uc(j), vr(row)), (uc(j + 1), vr(row)), (uc(j + 0.5), vv)])
        if self.size is None:
            rl = [sum((r[(k + 1) % n] - r[k]).length for k in range(nc)) for r in rows]
            cl = []
            for j in range(n):
                pts = ([Vector(pole0)] if pole0 is not None else []) + [Vector(rows[i][j]) for i in range(m)] + ([Vector(pole1)] if pole1 is not None else [])
                cl.append(sum((pts[k + 1] - pts[k]).length for k in range(len(pts) - 1)))
            self.size = (max(0.01, sum(rl) / len(rl)), max(0.01, sum(cl) / len(cl)))
        return self

class Ctx:
    def __init__(self, body, rig):
        me = body.data
        self.verts = [v.co.copy() for v in me.vertices]
        self.polys = [tuple(p.vertices) for p in me.polygons]
        self.bvh = BVHTree.FromPolygons(self.verts, self.polys)
        self.rig = rig
        self.bones = {b.name: b for b in rig.data.bones}
    def cast(self, o, d, far=2.0):
        hit = self.bvh.ray_cast(o, d.normalized(), far); return hit[0]
    def outer(self, o, d, far=2.0):
        d = d.normalized(); last = None; p = Vector(o)
        for _ in range(12):
            hit = self.bvh.ray_cast(p, d, far)
            if hit[0] is None: break
            last = hit[0]; p = hit[0] + d * 1e-4
        return last
    def edge(self, phi, zf, zs, zb):
        A = ((zf + zb) / 2 + zs) / 2; B = (zf - zb) / 2; C = ((zf + zb) / 2 - zs) / 2
        z = A + B * math.cos(phi) + C * math.cos(2 * phi)
        d = V(math.sin(phi), -math.cos(phi), 0); o = V(0, 0.02, z)
        return self.cast(o, d) or o + d * 0.25
    def shell(self, E, t, off):
        d0 = (E - HC).normalized(); d = d0.slerp(V(0, 0, 1), t) if t < 0.999 else V(0, 0, 1)
        hit = self.cast(HC, d) or HC + d * 0.28
        return hit + d * off
    def torso(self, phi, z, outer=False):
        d = V(math.sin(phi), -math.cos(phi), 0); o = V(0, 0.05, z)
        p = (self.outer(o, d) if outer else self.cast(o, d)) or o + d * 0.18
        return p, d
    def M(self, bone): return self.bones[bone].matrix_local.copy()
    def axis(self, bone): b = self.bones[bone]; return b.head_local.copy(), b.tail_local.copy()

def limb_rings(ctx, bone, ts, off, sides=8, flare=None):
    h, t = ctx.axis(bone); a = (t - h).normalized()
    e1 = (V(0, -1, 0) - a * a.dot(V(0, -1, 0))).normalized(); e2 = a.cross(e1)
    rows = []
    for k, s in enumerate(ts):
        c = h.lerp(t, s); ring = []
        for j in range(sides):
            ang = 2 * math.pi * j / sides; d = e1 * math.cos(ang) + e2 * math.sin(ang)
            p = ctx.outer(c, d, far=0.085) or c + d * 0.04
            ring.append(p + d * (off + (flare(k) if flare else 0.0)))
        rows.append(ring)
    return rows

def skull_rows(c, size, front=V(0, -1, 0), up=V(0, 0, 1), nrow=6, ncol=10):
    """A low-poly skull (sphere grid narrowed into a jaw); u around starting at the back, v top->bottom."""
    side = up.cross(front); rows = []
    for i in range(1, nrow):
        th = math.pi * i / nrow; ring = []
        for j in range(ncol):
            ph = -math.pi + 2 * math.pi * j / ncol
            x, y, z = math.sin(th) * math.sin(ph), math.sin(th) * -math.cos(ph), math.cos(th)
            if z < -0.2: x *= 0.78; y = y * 0.85 - 0.12 * (1 - z) * 0.5     # jaw narrower, chin forward
            ring.append(c + (side * x * 0.88 + front * (-y) + up * z * 1.05) * size)
        rows.append(ring)
    return rows, c + up * size * 1.05, c - up * size * 0.95

# ------------------------------------------------------------------ the four variants
XFER = {}
def cloth_w(co, top=0.40, arm_cap=0.45):
    """Capes/cloaks: copy the body's weights (shoulder blades + a little upper arm) near the top, blend to
    clean chest/spine/hips bands by height lower down; never the legs (they swing under it)."""
    z = co.z
    if z > 0.40: band_w = {"chest": 1.0}
    elif z > 0.31: t = sm(0.31, 0.40, z); band_w = {"chest": t, "spine": 1 - t}
    elif z > 0.22: t = sm(0.22, 0.31, z); band_w = {"spine": t, "hips": 1 - t}
    else: band_w = {"hips": 1.0}
    k = sm(top - 0.08, top, z)
    if k <= 0: return band_w
    tw = transfer(XFER["ctx"], XFER["W"], XFER["colix"], co, {"chest", "spine", "upper_arm.L", "upper_arm.R"}, arm_cap)
    s_ = sum(tw.values()) or 1.0
    out = {b_: w_ * (1 - k) for b_, w_ in band_w.items()}
    for b_, w_ in tw.items(): out[b_] = out.get(b_, 0.0) + k * w_ / s_
    return out

def shoulder_w(co, center, side, arm_max=0.3, arm_min=0.0, xfer=None):
    """Shoulder armour (pauldrons, their spikes, the chief's mantle/tusks): ride the chest, with at most
    arm_max upper arm on the outer-lower side (where the arm leaves the shoulder), so a raised arm shrugs
    the piece a little instead of swinging it into the head. xfer: bones to copy from the body before the
    arm share is mixed in (the mantle follows spine/neck too); default pure chest."""
    d = Vector(co) - Vector(center)
    d = d.normalized() if d.length > 1e-6 else V(side, 0, 0)
    m = d.dot(V(0.5 * side, 0, -0.866))          # 1 = out and down toward the arm, <= 0 = top / inner side
    arm = arm_min + arm_max * sm(-0.3, 0.7, m)
    base = {"chest": 1.0}
    if xfer:
        tw = transfer(XFER["ctx"], XFER["W"], XFER["colix"], Vector(co), xfer)
        s_ = sum(tw.values())
        if s_ > 1e-6: base = {k: v / s_ for k, v in tw.items()}
    out = {k: v * (1 - arm) for k, v in base.items()}
    if arm > 0: out["upper_arm." + ("L" if side > 0 else "R")] = arm
    return out

def fix_soles(body, rig, W, colix):
    """Sole and heel ride the foot bone (the cached goblin had them ~50 % shin, so a knee bend pushed the
    heel under the floor). Below the ankle the shin share fades out to 0 at half the ankle height."""
    gi = {g.name: g.index for g in body.vertex_groups}; moved = 0
    for sd in "LR":
        az = rig.data.bones["foot." + sd].head_local.z; sh, ft = "shin." + sd, "foot." + sd
        if sh not in colix or ft not in colix: continue
        for v in body.data.vertices:
            ws = W[v.index, colix[sh]]
            if ws <= 0 or v.co.z >= az: continue
            keep = sm(0.5 * az, az, v.co.z); dw = ws * (1 - keep)
            if dw < 1e-4: continue
            W[v.index, colix[sh]] -= dw; W[v.index, colix[ft]] += dw; moved += 1
            body.vertex_groups[gi[ft]].add([v.index], float(W[v.index, colix[ft]]), 'REPLACE')
            if W[v.index, colix[sh]] > 1e-5: body.vertex_groups[gi[sh]].add([v.index], float(W[v.index, colix[sh]]), 'REPLACE')
            else: body.vertex_groups[gi[sh]].remove([v.index])
    print("SOLES moved shin->foot on %d verts" % moved)

def build_archer(ctx):
    P, extras = [], []
    n = 20; phis = [-math.pi + 2 * math.pi * j / n for j in range(n)]
    zf, zs, zb = 0.865, 0.942, 0.83
    E = [ctx.edge(p, zf, zs, zb) for p in phis]
    tip = V(0, 0.19, 1.17); ts = [0, 0.14, 0.28, 0.42, 0.56, 0.70, 0.82, 0.92]
    rows = []
    for t in ts:
        row = []
        for j, p in enumerate(phis):
            q = ctx.shell(E[j], t, 0.017 + 0.022 * t); q.z += 0.022 * abs(math.cos(p)) ** 4 * t
            row.append(q.lerp(tip, max(0.0, (t - 0.40) / 0.60) ** 1.5 * 0.85))
        rows.append(row)
    def p_cap(U, Vv, Pp, N):
        c = felt((0.15, 0.30, 0.12), U, Vv, 14, 8, 0.22, 1)
        c = mix(c, (0.09, 0.20, 0.07), band(np.abs(U - 0.5) * 2, 0.0, 0.06) * (Vv > 0.15))   # front/back seam
        c = mix(c, (0.09, 0.20, 0.07), band(U, 0.0, 0.03) + band(U, 1.0, 0.03))
        hb = Vv < 0.13
        c = np.where(hb[:, None], felt((0.42, 0.27, 0.15), U, Vv, 30, 4, 0.2, 2), c)          # leather hat band
        st = (band(Vv, 0.155, 0.012) * (np.sin(U * 260) > 0.2))
        return mix(c, (0.80, 0.72, 0.45), st * 0.8) * (0.92 + 0.12 * Vv)[:, None]
    P.append(Part("cap", "acc", p_cap, ("rigid", {"head": 1.0}), solid=("rim", 0.008), out=HC).grid(rows, True, pole1=tip))
    rb = [[], [], []]
    for j, p in enumerate(phis):
        d = V(math.sin(p), -math.cos(p), 0)
        w = (0.040 + 0.024 * math.cos(p) + 0.012 * math.cos(2 * p)) * (1 + 0.75 * max(0.0, math.cos(p)) ** 10)
        h = 0.022 - 0.036 * math.cos(p); b = ctx.shell(E[j], 0, 0.017)
        rb[0].append(b); rb[1].append(b + d * w * 0.55 + V(0, 0, h * 0.40)); rb[2].append(b + d * w + V(0, 0, h))
    def p_brim(U, Vv, Pp, N):
        return mix(felt((0.16, 0.31, 0.12), U, Vv, 30, 4, 0.2, 3), (0.48, 0.34, 0.18), band(Vv, 1, 0.12))   # leather-bound edge
    P.append(Part("brim", "acc", p_brim, ("rigid", {"head": 1.0}), solid=("full", 0.007), out=HC).grid(rb, True))
    pf = math.radians(118); B = ctx.shell(ctx.edge(pf, zf, zs, zb), 0.10, 0.02)
    ctrl = [B, B + V(0.035, 0.09, 0.10), B + V(0.06, 0.19, 0.19), B + V(0.07, 0.30, 0.24)]
    fr = [[], [], []]
    for k in range(10):
        s = k / 9; c = catmull(ctrl, s)
        tg = (catmull(ctrl, min(1, s + 0.02)) - catmull(ctrl, max(0, s - 0.02))).normalized()
        side = tg.cross(V(0, 0, 1)).normalized(); up = side.cross(tg)
        w = 0.036 * math.sin(math.pi * min(1.0, s * 1.06 + 0.04)) ** 0.7
        fr[0].append(c - side * w - up * 0.003); fr[1].append(c + up * 0.004); fr[2].append(c + side * w - up * 0.003)
    def p_feather(U, Vv, Pp, N):
        c = col((0.80, 0.16, 0.12), len(U))
        c = mix(c, (0.95, 0.93, 0.86), np.clip((U - 0.72) * 6, 0, 1))
        c = mix(c, (0.12, 0.10, 0.10), band(U, 0.70, 0.025))
        c = c * (0.86 + 0.14 * (np.sin(U * 160 + np.abs(Vv - 0.5) * 40) > 0))[:, None]
        return mix(c, (0.93, 0.88, 0.75), band(Vv, 0.5, 0.07))
    P.append(Part("feather", "acc", p_feather, ("rigid", {"head": 1.0}), solid=("full", 0.003)).grid(fr, False))
    # quiver on the back, arrows, chest strap
    def back_at(x, z):
        hit = ctx.cast(V(x, 0.05, z), V(0, 1, 0)); return hit.y if hit else 0.19
    A0, B0 = V(0.075, 0, 0.215), V(-0.215, 0, 0.405)     # low and diagonal: the big head swings over the upper back
    A0.y = back_at(A0.x, 0.25) + 0.05; B0.y = back_at(-0.12, 0.39) + 0.056
    ax = (B0 - A0).normalized()
    ts = (0, 0.06, 0.12, 0.5, 0.88, 0.94, 0.985); rad = [0.042, 0.047, 0.047, 0.044, 0.047, 0.047, 0.045]
    qrows = tube([A0.lerp(B0, t) for t in ts], rad, 8, front=V(0, 1, 0))
    def p_quiver(U, Vv, Pp, N):
        c = felt((0.46, 0.29, 0.16), U, Vv, 10, 14, 0.22, 4)
        bands = (band(Vv, 0.13, 0.06) + band(Vv, 0.86, 0.06)) > 0
        c = np.where(bands[:, None], felt((0.30, 0.20, 0.12), U, Vv, 30, 4, 0.2, 5), c)
        c = mix(c, (0.86, 0.72, 0.38), band(Vv, 0.5, 0.04) * (np.abs(U - 0.5) < 0.12))       # brass stud
        return c
    P.append(Part("quiver", "acc", p_quiver, ("rigid_at", A0.lerp(B0, 0.45), {"chest", "spine"}), out=A0.lerp(B0, 0.5)).grid(qrows, True, pole0=A0 - ax * 0.01))
    top_c = A0.lerp(B0, 0.96)
    trow = tube([top_c], [0.041], 8, front=V(0, 1, 0))
    P.append(Part("quiver_top", "acc", lambda U, Vv, Pp, N: col((0.10, 0.07, 0.05), len(U)),
                  ("rigid_at", A0.lerp(B0, 0.45), {"chest", "spine"}), flat=True).grid(trow, True, pole1=top_c - ax * 0.004))
    ap = Part("arrows", "acc", None, ("rigid_at", A0.lerp(B0, 0.45), {"chest", "spine"}), flat=True)
    e1 = ax.cross(V(0, 0, 1)).normalized(); e2 = ax.cross(e1)
    out_dir = (ax + V(-0.55, 0.3, -0.15)).normalized()     # arrows lean out to the side and back, away from the head
    for k, (oa, ob, ext) in enumerate(((0.018, 0.0, 0.075), (-0.012, 0.014, 0.095), (-0.008, -0.017, 0.065), (0.004, 0.026, 0.085), (0.024, -0.02, 0.07))):
        base = top_c - ax * 0.2 + e1 * oa + e2 * ob; end = top_c + out_dir * ext + e1 * oa * 1.4 + e2 * ob * 1.4
        sh = tube([base, end], [0.0045, 0.0045], 3, front=e2)
        ap.grid(sh, True, pole1=end + (end - base).normalized() * 0.012, u=(0.0, 0.45))
        dd = (end - base).normalized()
        for vang in (0.0, 2.1, 4.2):
            vd = (e1 * math.cos(vang + k) + e2 * math.sin(vang + k))
            a0, a1 = end - dd * 0.065, end - dd * 0.012
            ap.grid([[a0, a1], [a0 + vd * 0.004, a1 + vd * 0.016]], False, u=(0.55, 1.0))
    def p_arrows(U, Vv, Pp, N):
        c = np.where((U < 0.5)[:, None], col((0.62, 0.48, 0.30), len(U)), col((0.85, 0.20, 0.14), len(U)))
        c = np.where(((U >= 0.5) & (Vv > 0.55))[:, None], np.array((0.94, 0.92, 0.85)), c)
        return np.where(((U < 0.5) & (Vv > 0.85))[:, None], np.array((0.20, 0.15, 0.10)), c)
    ap.paint = p_arrows; ap.size = (0.04, 0.3); P.append(ap)
    sr = [[], [], []]
    for k in range(15):
        s = k / 14; x = -0.10 + 0.23 * s; z = 0.44 - 0.13 * s
        hit = ctx.bvh.ray_cast(V(x, -0.6, z), V(0, 1, 0), 2.0)
        p, nrm = (hit[0], hit[1]) if hit[0] else (V(x, -0.1, z), V(0, -1, 0))
        dirs = V(0.25, 0, -0.135).normalized(); wd = dirs.cross(nrm).normalized()
        sr[0].append(p + nrm * 0.015 - wd * 0.017); sr[1].append(p + nrm * 0.019); sr[2].append(p + nrm * 0.015 + wd * 0.017)
    br_ = [[], [], []]
    q_top = A0.lerp(B0, 0.86)
    for k in range(9):
        s = k / 8; target = q_top.lerp(V(-0.10, 0.0, 0.452), s)
        hit = ctx.bvh.ray_cast(V(target.x, 0.7, target.z), V(0, -1, 0), 2.0)
        p, nrm = (hit[0], hit[1]) if hit[0] else (V(target.x, 0.2, target.z), V(0, 1, 0))
        if s < 0.25: p = p.lerp(q_top + (q_top - (A0.lerp(B0, 0.5) * 0 + V(q_top.x, q_top.y - 0.05, q_top.z))).normalized() * 0.0, 1 - s * 4) if False else p
        dirs = (V(-0.10, 0.0, 0.452) - q_top); dirs.y = 0; dirs.normalize(); wd = dirs.cross(nrm).normalized()
        off = 0.015 + (0.03 * (1 - s / 0.3) if s < 0.3 else 0.0)
        br_[0].append(p + nrm * off - wd * 0.016); br_[1].append(p + nrm * (off + 0.004)); br_[2].append(p + nrm * off + wd * 0.016)
    def p_strap(U, Vv, Pp, N):
        c = felt((0.34, 0.22, 0.13), U, Vv, 40, 4, 0.2, 6)
        c = mix(c, (0.72, 0.60, 0.40), (band(Vv, 0.12, 0.04) + band(Vv, 0.88, 0.04)) * (np.sin(U * 300) > 0.3) * 0.7)
        bk = (np.abs(U - 0.55) < 0.05) & (np.abs(Vv - 0.5) < 0.42)
        return np.where(bk[:, None], np.array((0.82, 0.68, 0.36)), c)
    P.append(Part("strap", "acc", p_strap, ("transfer", {"chest", "spine", "hips"})).grid(sr, False))
    P.append(Part("strap_back", "acc", p_strap, ("transfer", {"chest", "spine", "upper_arm.R"})).grid(br_, False))
    def p_bracer(U, Vv, Pp, N):
        c = felt((0.40, 0.25, 0.14), U, Vv, 20, 10, 0.2, 8)
        lace = band(np.abs(((Vv * 6) % 1) - 0.5) * 2 - np.abs(U - 0.5) * 12, 0, 0.25) * (np.abs(U - 0.5) < 0.08)
        c = mix(c, (0.78, 0.70, 0.52), lace * 0.8)
        return edges(c, U, Vv, 0.1, 0.8)
    # (the goblin's own modelled forearm bracers are repainted as the archer's laced arm guards: paint_body)
    # the bow (skinned prop on attach_weapon.L + bow_string), the arrow (attach_weapon.R)
    ML = ctx.M("attach_weapon.L"); X, Y, Z = (ML.to_3x3().col[i].normalized() for i in range(3)); O = ML.translation
    def L(bx, by, bz): return O + X * bx + Y * by + Z * bz
    half = 0.34; rows, pr = [], []
    ss = [-1, -0.97, -0.85, -0.7, -0.52, -0.34, -0.18, -0.08, 0, 0.08, 0.18, 0.34, 0.52, 0.7, 0.85, 0.97, 1]
    def cx(s): return -0.125 * s * s + 0.05 * max(0.0, abs(s) - 0.78) ** 2 / 0.0484
    tipx = cx(1.0)
    for s in ss:
        tb = 0.013 * (1 - 0.55 * abs(s)) + (0.007 if abs(s) < 0.12 else 0.0)
        wb = 0.026 * (1 - 0.55 * abs(s)) + (0.002 if abs(s) < 0.12 else 0.0)
        rows.append([L(cx(s) + tb * math.cos(a), s * half, wb * math.sin(a)) for a in [2 * math.pi * j / 6 for j in range(6)]])
        pr.append(s)
    def p_bow(U, Vv, Pp, N):
        s = Vv * 2 - 1
        c = wood((0.45, 0.27, 0.14), U, Vv, 70, 9)
        c = mix(c, (0.80, 0.70, 0.50), np.clip((np.abs(s) - 0.9) * 12, 0, 1))         # horn nocks
        g = np.abs(s) < 0.12
        wrap = felt((0.55, 0.20, 0.13), U, Vv, 10, 200, 0.4, 10) * (0.8 + 0.2 * (np.sin(Vv * 900) > 0))[:, None]
        return np.where(g[:, None], wrap, c)
    bow = Part("bow", "bow", p_bow, ("fn", None)); bow.skin_prop = True
    bow.grid(rows, True, pole0=L(tipx, -half - 0.012, 0), pole1=L(tipx, half + 0.012, 0), param=pr)
    def w_bow(i, co, part):
        s = part.P[i]; t = 0.14 * max(0.0, abs(s) - 0.55) / 0.45
        return {"attach_weapon.L": 1 - t, "bow_string": t}
    bow.weights = ("fn", w_bow); P.append(bow)
    sx = tipx - 0.0
    srows = tube([L(sx, -half + 0.004, 0), L(sx, 0, 0), L(sx, half - 0.004, 0)], [0.0028] * 3, 3, front=Z)
    st = Part("string", "bow", lambda U, Vv, Pp, N: col((0.88, 0.84, 0.72), len(U)), None, flat=True)
    st.grid(srows, True, param=[0.9, 2.0, 0.9])
    st.weights = ("fn", lambda i, co, part: ({"bow_string": 1.0} if part.P[i] > 1.5 else {"attach_weapon.L": 0.86, "bow_string": 0.14}))
    st.skin_prop = True; P.append(st)
    extras.append(dict(name="bow_string", parent="attach_weapon.L", head=L(sx, 0, 0), tail=L(sx - 0.08, 0, 0), up=V(0, 0, 1), deform=True))
    MR = ctx.M("attach_weapon.R"); Xr, Yr, Zr = (MR.to_3x3().col[i].normalized() for i in range(3)); Or = MR.translation
    def R_(bx, by, bz): return Or + Xr * bx + Yr * by + Zr * bz
    arw = Part("arrow", "arrow", None, ("bone", "attach_weapon.R"), flat=True)
    arw.grid(tube([R_(0, -0.13, 0), R_(0, 0.29, 0)], [0.005, 0.005], 3, front=Zr), True, u=(0.0, 0.45))
    head = tube([R_(0, 0.285, 0), R_(0, 0.300, 0)], [0.006, 0.014], 4, front=Zr)
    arw.grid(head, True, pole1=R_(0, 0.345, 0), u=(0.5, 0.6))
    for vang in (0.0, 2.094, 4.189):
        vd = Xr * math.cos(vang) + Zr * math.sin(vang)
        arw.grid([[R_(0, -0.125, 0), R_(0, -0.06, 0)], [R_(0, -0.125, 0) + vd * 0.016, R_(0, -0.07, 0) + vd * 0.005]], False, u=(0.65, 1.0))
    def p_arrow(U, Vv, Pp, N):
        c = col((0.64, 0.50, 0.32), len(U))
        c = np.where(((U >= 0.48) & (U < 0.62))[:, None], np.array((0.50, 0.50, 0.52)), c)
        c = np.where((U >= 0.62)[:, None], np.array((0.86, 0.20, 0.14)), c)
        return np.where(((U >= 0.62) & (Vv > 0.6))[:, None], np.array((0.94, 0.92, 0.85)), c)
    arw.paint = p_arrow; arw.size = (0.04, 0.3); P.append(arw)
    return P, extras

def build_mage(ctx):
    P, extras = [], []
    n = 18; phis = [-math.pi + 2 * math.pi * j / n for j in range(n)]
    zf, zs, zb = 0.875, 0.952, 0.845
    E = [ctx.edge(p, zf, zs, zb) for p in phis]
    C = [V(0, 0.04, 0.99), V(0.02, 0.07, 1.13), V(-0.03, 0.13, 1.28), V(0.02, 0.11, 1.40), V(0.07, 0.01, 1.45), V(0.09, -0.10, 1.39)]
    rows, prm = [], []
    for t in (0.0, 0.25):
        rows.append([ctx.shell(E[j], t, 0.019 + 0.026 * t) for j in range(n)]); prm.append(-1.0)
    ef = None
    svals = [0.0, 0.08, 0.17, 0.27, 0.37, 0.47, 0.56, 0.64, 0.72, 0.80, 0.87, 0.94]
    for s in svals:
        c = catmull(C, s); T = (catmull(C, min(1, s + 0.02)) - catmull(C, max(0, s - 0.02))).normalized()
        e = V(0, -1, 0) if ef is None else ef; e = (e - T * e.dot(T)).normalized(); ef = e; es = T.cross(e)
        ring = []
        for j, p in enumerate(phis):
            r = (0.205 * (1 - s) ** 1.15 + 0.012) * (1 + 0.05 * math.sin(3 * p + 7 * s)) * (0.86 if 0.55 < s < 0.68 else 1.0)
            ring.append(c + (e * math.cos(p) + es * math.sin(p)) * r)
        rows.append(ring); prm.append(s)
    tipp = catmull(C, 1.0)
    def p_hat(U, Vv, Pp, N):
        c = felt((0.30, 0.22, 0.52), U, Vv, 10, 16, 0.25, 11)
        c = c * (0.9 + 0.1 * np.sin(U * 6.28 * 3 + Vv * 9))[:, None]                      # felt folds
        for (u0, v0, w, h, pc) in ((0.22, 0.42, 0.16, 0.10, (0.52, 0.34, 0.22)), (0.70, 0.62, 0.12, 0.09, (0.22, 0.38, 0.30)),
                                   (0.45, 0.80, 0.10, 0.06, (0.55, 0.20, 0.18))):
            inn = (np.abs(U - u0) < w / 2) & (np.abs(Vv - v0) < h / 2)
            edge = inn & ((np.abs(U - u0) > w / 2 - 0.012) | (np.abs(Vv - v0) > h / 2 - 0.008))
            c = np.where(inn[:, None], felt(pc, U, Vv, 30, 30, 0.25, 12), c)
            c = np.where((edge & (np.sin((U + Vv) * 400) > 0))[:, None], np.array((0.85, 0.80, 0.62)), c)
        hb = (Vv > 0.10) & (Vv < 0.21)
        c = np.where(hb[:, None], felt((0.55, 0.40, 0.18), U, Vv, 40, 4, 0.2, 13), c)
        c = np.where((hb & (np.abs(U - 0.5) < 0.035))[:, None], np.array((0.90, 0.78, 0.35)), c)  # buckle
        return c
    hat = Part("hat", "acc", p_hat, ("fn", lambda i, co, part: (
        {"head": 1.0} if part.P[i] < 0.3 else {"head": 1 - sm(0.35, 0.65, part.P[i]), "hat_tip": sm(0.35, 0.65, part.P[i])})),
        solid=("rim", 0.009), out=None)
    hat.grid(rows, True, pole1=tipp, param=prm)
    hat.out_fn = lambda fc: fc - (catmull(C, 0.5) if fc.z > 1.0 else HC)
    P.append(hat)
    rb = [[], [], []]
    for j, p in enumerate(phis):
        d = V(math.sin(p), -math.cos(p), 0); w = 0.078 + 0.044 * math.cos(2 * p)
        h = -0.02 - 0.012 * math.cos(2 * p) + 0.010 * math.sin(5 * p + 0.7); b = ctx.shell(E[j], 0, 0.019)
        rb[0].append(b); rb[1].append(b + d * w * 0.5 + V(0, 0, 0.006 + h * 0.2)); rb[2].append(b + d * w + V(0, 0, h))
    P.append(Part("brim", "acc", lambda U, Vv, Pp, N: felt((0.28, 0.20, 0.48), U, Vv, 30, 4, 0.22, 14) * (1 - 0.18 * band(Vv, 1, 0.2))[:, None],
                  ("rigid", {"head": 1.0}), solid=("full", 0.006), out=HC).grid(rb, True))
    ch = Part("charm", "acc", None, ("rigid", {"hat_tip": 1.0}), flat=True)
    ch.grid(tube([tipp, tipp + V(0, 0, -0.07)], [0.0028] * 2, 3), True, u=(0.0, 0.3))
    bc = tipp + V(0, 0, -0.082)
    ch.grid(tube([bc + V(-0.032, 0, 0), bc + V(-0.026, 0, 0), bc + V(0.026, 0, 0), bc + V(0.032, 0, 0)], [0.011, 0.0065, 0.0065, 0.011], 5, front=V(0, 0, 1)),
            True, pole0=bc + V(-0.04, 0, 0), pole1=bc + V(0.04, 0, 0), u=(0.4, 1.0))
    ch.paint = lambda U, Vv, Pp, N: np.where((U < 0.35)[:, None], col((0.30, 0.20, 0.12), len(U)), col((0.88, 0.84, 0.72), len(U)) * (0.9 + 0.1 * np.sin(Vv * 40))[:, None])
    ch.size = (0.04, 0.12); P.append(ch)
    extras.append(dict(name="hat_tip", parent="head", head=catmull(C, 0.45), tail=tipp, up=V(0, -1, 0), deform=True))
    # ragged cloak on the back
    cols = 13; ph = [math.pi + math.radians(-52 + 104 * j / (cols - 1)) for j in range(cols)]
    zrows = [0.432, 0.40, 0.355, 0.30, 0.25, 0.20, 0.16, 0.13]
    crow, rprev = [], [0.0] * cols
    for i, z in enumerate(zrows):
        row = []
        for j, p in enumerate(ph):
            zz = z
            if i == len(zrows) - 1: zz = z + (0.035 if j % 3 == 1 else 0.012 if j % 3 == 2 else -0.012) + 0.008 * math.sin(j * 2.3)
            hit, d = ctx.torso(p, max(zz, 0.24), outer=False)
            r = max((hit - V(0, 0.05, hit.z)).length, rprev[j]); rprev[j] = r
            rr = r + 0.022 + 0.11 * (0.432 - zz)
            row.append(V(0, 0.05, zz) + d * rr)
        crow.append(row)
    def w_cloak(i, co, part): return cloth_w(co, 0.42)
    def p_cloak(U, Vv, Pp, N):
        c = felt((0.22, 0.17, 0.40), U, Vv, 8, 12, 0.25, 15) * (0.88 + 0.12 * np.sin(U * 6.28 * 5 + fbm(U * 3, Vv * 3, 16) * 3))[:, None]
        c = mix(c, (0.13, 0.10, 0.22), np.clip((Vv - 0.82) * 5, 0, 1) * 0.7)
        inn = (np.abs(U - 0.30) < 0.07) & (np.abs(Vv - 0.55) < 0.08)
        c = np.where(inn[:, None], felt((0.40, 0.28, 0.20), U, Vv, 40, 40, 0.3, 17), c)
        rune = band(np.abs(U - 0.62) * 3 + np.abs(Vv - 0.35), 0.06, 0.02) * (np.abs(U - 0.62) < 0.06)
        return mix(c, (0.80, 0.66, 0.30), rune)
    P.append(Part("cloak", "acc", p_cloak, ("fn", w_cloak), solid=("full", 0.007), out=V(0, 0.0, 0.3)).grid(crow, False))
    # scroll case strapped across the cloak's upper back (clear of fists and thighs in every goblin clip)
    sp_, d_ = ctx.torso(math.pi, 0.355); y_back = crow[3][cols // 2].y
    scc = V(0.0, y_back + 0.03, 0.352)
    srow = tube([scc + V(-0.085, 0, 0.012), scc + V(0.085, 0, -0.012)], [0.02, 0.02], 7, front=V(0, 0, 1))
    def p_scroll(U, Vv, Pp, N):
        c = felt((0.50, 0.32, 0.20), U, Vv, 10, 10, 0.2, 19)
        c = np.where((band(Vv, 0.12, 0.05) + band(Vv, 0.88, 0.05) > 0)[:, None], np.array((0.82, 0.66, 0.30)), c)
        return np.where((np.abs(Vv - 0.5) < 0.05)[:, None], np.array((0.62, 0.14, 0.12)), c)
    P.append(Part("scroll_case", "acc", p_scroll, ("rigid_at", scc - V(0, 0.06, 0), {"chest", "spine"})).grid(
        srow, True, pole0=scc + V(-0.092, 0, 0.013), pole1=scc + V(0.092, 0, -0.013)))
    # gnarled staff on attach_weapon.R, held mid-shaft; the focus crystal is material 1 (glow)
    MR = ctx.M("attach_weapon.R"); X, Y, Z = (MR.to_3x3().col[i].normalized() for i in range(3)); O = MR.translation
    def S(bx, by, bz): return O + X * bx + Y * by + Z * bz
    bys = [-0.40 + 0.80 * k / 12 for k in range(13)]
    path = [S(0.007 * math.sin(k * 1.7), by, 0.007 * math.cos(k * 2.3)) for k, by in enumerate(bys)]
    rads = [0.0205 * (1.3 if k in (3, 9) else 1.0) * (1.1 if k == 12 else 1.0) for k in range(13)]
    staff = Part("staff", "staff", None, ("bone", "attach_weapon.R"))
    staff.grid(tube(path, rads, 6, front=Z), True, pole0=S(0, -0.44, 0), pole1=S(0, 0.415, 0), param=bys, u=(0.0, 1.0))
    def p_staff(U, Vv, Pp, N):
        by = -0.44 + Vv * 0.855
        c = wood((0.38, 0.25, 0.16), U, Vv, 120, 20)
        c = mix(c, (0.22, 0.14, 0.09), fbm(U * 8, Vv * 40, 21) * 0.5)
        grip = np.abs(by) < 0.075
        c = np.where(grip[:, None], felt((0.36, 0.22, 0.30), U, Vv, 10, 300, 0.3, 22) * (0.8 + 0.2 * (np.sin(Vv * 700) > 0))[:, None], c)
        return np.where((by < -0.38)[:, None], metal((0.42, 0.42, 0.44), U, Vv, 0.5), c)
    staff.paint = p_staff; P.append(staff)
    pg = Part("prongs", "staff", None, ("bone", "attach_weapon.R"))
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        def at(by, r): return S(r * math.cos(a), by, r * math.sin(a))
        pth = [at(0.39, 0.014), at(0.45, 0.046), at(0.53, 0.046), at(0.585, 0.016)]
        pg.grid(tube(pth, [0.0085, 0.0075, 0.006, 0.0035], 4, front=Z), True, pole1=at(0.60, 0.008), u=(k / 3, (k + 1) / 3))
    pg.paint = lambda U, Vv, Pp, N: wood((0.33, 0.22, 0.14), U, Vv, 60, 23); pg.size = (0.06, 0.18); P.append(pg)
    cr = Part("crystal", "staff", lambda U, Vv, Pp, N: col((0.55, 0.92, 1.0), len(U)), ("bone", "attach_weapon.R"), flat=True)
    cr.grid([[S(0.034 * math.cos(a), 0.52, 0.034 * math.sin(a)) for a in [2 * math.pi * j / 6 for j in range(6)]]], True,
            pole0=S(0, 0.455, 0), pole1=S(0, 0.595, 0), mat=1)
    P.append(cr)
    return P, extras

def plate_rows(ctx, phis, zs, off, ridge=0.0, outer=False, bottom_flare=0.0):
    rows = []
    for i, z in enumerate(zs):
        row = []
        for p in phis:
            hit, d = ctx.torso(p, z, outer)
            ext = off + ridge * math.exp(-((math.atan2(math.sin(p), math.cos(p))) / 0.28) ** 2) + (bottom_flare if i == 0 else 0.0)
            row.append(hit + d * ext)
        rows.append(row)
    return rows

def build_knight(ctx):
    P, extras = [], []
    n = 22; phis = [-math.pi + 2 * math.pi * j / n for j in range(n)]
    zf, zs, zb = 0.862, 0.948, 0.785
    E = [ctx.edge(p, zf, zs, zb) for p in phis]
    ts = [0, 0.12, 0.25, 0.38, 0.5, 0.62, 0.74, 0.86]
    rows = [[ctx.shell(E[j], t, 0.027 + 0.006 * t) + V(0, 0, 0.016 * math.exp(-math.sin(p) ** 2 * 25) * t) for j, p in enumerate(phis)] for t in ts]
    top = ctx.shell(E[0], 1.0, 0.03)
    def p_helm(U, Vv, Pp, N):
        c = metal((0.42, 0.42, 0.45), U, Vv, 0.7, 6, 6, 31)
        c = mix(c, (0.30, 0.30, 0.33), band(np.abs(U - 0.5) * 2, 0, 0.04))
        c = mix(c, (0.30, 0.30, 0.33), band(U, 0, 0.02) + band(U, 1, 0.02))
        c = edges(c, U, Vv, 0.08, 1.25)
        return rivets(c, U, Vv, [0.07], 22, r=0.012, asp=1.6)
    P.append(Part("helmet", "acc", p_helm, ("rigid", {"head": 1.0}), solid=("rim", 0.014), out=HC).grid(rows, True, pole1=top))
    fl = [[], []]
    for j, p in enumerate(phis):
        d = V(math.sin(p), -math.cos(p), 0); w = 0.032 + 0.016 * abs(math.cos(p))
        b0_ = rows[0][j]; fl[0].append(b0_ - V(0, 0, 0.004)); fl[1].append(b0_ + d * w - V(0, 0, 0.012))
    P.append(Part("helm_flange", "acc", lambda U, Vv, Pp, N: rivets(edges(metal((0.40, 0.40, 0.43), U, Vv, 0.8, 20, 3, 45), U, Vv, 0.2, 1.3), U, Vv, [0.5], 22, r=0.06, asp=6),
                  ("rigid", {"head": 1.0}), solid=("full", 0.008), out=HC).grid(fl, True))
    nas = []
    for z in (0.878, 0.845, 0.812, 0.782):
        w = 0.021 if z > 0.83 else 0.016; row = []
        for x in (-w, w):
            hit = ctx.cast(V(x, 0.02, z), V(0, -1, 0)); row.append((hit or V(x, -0.27, z)) + V(0, -0.028, 0))
        nas.append(row)
    P.append(Part("nasal", "acc", lambda U, Vv, Pp, N: edges(metal((0.46, 0.45, 0.47), U, Vv, 0.5, 4, 4, 32), U, Vv, 0.1, 1.2, True),
                  ("rigid", {"head": 1.0}), solid=("rim", 0.01), out=HC).grid(nas, False))
    def horn(sx, broken):
        phi = math.radians(72) * sx; Eh = ctx.edge(phi, zf, zs, zb); B = ctx.shell(Eh, 0.45, 0.03)
        ctrl = [B, B + V(0.09 * sx, -0.01, 0.05), B + V(0.17 * sx, -0.05, 0.14), B + V(0.21 * sx, -0.11, 0.25)]
        ks = [k / 9 for k in range(10)]
        if broken: ks = [k * 0.62 for k in ks]
        path = [catmull(ctrl, s) for s in ks]
        rad = [0.036 * (1 - s) ** 0.9 + 0.006 for s in ks]
        rr = tube(path, (lambda k, a: rad[k] * (1 + (0.12 * math.sin(a * 3 + k) if broken and k == len(ks) - 1 else 0))), 8, front=V(0, -1, 0))
        endp = path[-1] + (path[-1] - path[-2]).normalized() * (0.004 if broken else 0.018)
        def p_horn(U, Vv, Pp, N):
            c = mix(col((0.42, 0.34, 0.25), len(U)), (0.86, 0.80, 0.66), np.clip(Vv * 1.6, 0, 1))
            c = c * (0.9 + 0.1 * np.sin(Vv * 70))[:, None]
            if broken: c = mix(c, (0.55, 0.48, 0.38), np.clip((Vv - 0.9) * 10, 0, 1))
            return c
        return Part("horn" + ("_R" if sx < 0 else "_L"), "acc", p_horn, ("rigid", {"head": 1.0})).grid(rr, True, pole1=endp)
    P.append(horn(1, False)); P.append(horn(-1, True))
    def pauldron(sx, big):
        S = V(0.234 * sx, 0.065, 0.446); a = V(math.cos(math.radians(2)) * sx, 0, math.sin(math.radians(2)))
        R = 0.098 if big else 0.090
        up = (V(0, 0, 1) - a * a.dot(V(0, 0, 1))).normalized(); fw = a.cross(up) * sx
        al = [12, 24, 36, 47, 56, 62]; cols = 14; rows = []
        for i, A0 in enumerate(al):
            row = []
            for j in range(cols):
                b = 2 * math.pi * j / cols
                A = A0 * (1 - 0.55 * max(0.0, -math.cos(b)))           # shorter on the underside (elbow room)
                rr = R * (1 + 0.10 * (A0 / 62) ** 3) * (1 + (0.035 if (not big and i in (2, 4)) else 0.0))
                dirv = a * math.cos(math.radians(A)) + (up * math.cos(b) + fw * math.sin(b)) * math.sin(math.radians(A))
                row.append(S + dirv * rr)
            rows.append(row)
        def p_pd(U, Vv, Pp, N):
            base = (0.40, 0.40, 0.43) if big else (0.50, 0.40, 0.30)   # mismatched: one iron, one bronze-ish
            c = metal(base, U, Vv, 0.8 if big else 0.4, 5, 5, 33 if big else 34)
            c = edges(c, U, Vv, 0.07, 1.3)
            if not big: c = mix(c, c * 0.7, band(Vv, 0.45, 0.03) + band(Vv, 0.8, 0.03))
            return rivets(c, U, Vv, [0.86], 14, r=0.02, asp=1.0)
        w_sh = ("fn", lambda i, co, part, S=S, sx=sx: shoulder_w(co, S, sx, 0.85))
        allow = {"chest", "upper_arm." + ("L" if sx > 0 else "R")}
        pt = Part("pauldron_" + ("L" if sx > 0 else "R"), "acc", p_pd, w_sh, solid=("rim", 0.012), out=S).grid(rows, True, pole0=S + a * R)
        pt.bake, pt.bake_cap = ("transfer", allow), 0.55
        out = [pt]
        if big:
            sp = Part("spikes", "acc", None, w_sh, flat=True); sp.bake, sp.bake_cap = ("transfer", allow), 0.55
            for (A, b) in ((22, 0.3), (30, 1.2), (30, -0.6)):
                dirv = (a * math.cos(math.radians(A)) + (up * math.cos(b) + fw * math.sin(b)) * math.sin(math.radians(A))).normalized()
                c0 = S + dirv * (R * 0.98)
                sp.grid(tube([c0, c0 + dirv * 0.001], [0.021, 0.021], 4, front=up), True, pole1=c0 + dirv * 0.085, u=(0, 1))
            sp.paint = lambda U, Vv, Pp, N: mix(col((0.36, 0.36, 0.38), len(U)), (0.75, 0.75, 0.78), Vv); sp.size = (0.05, 0.08)
            out.append(sp)
        return out
    P += pauldron(1, True) + pauldron(-1, False)
    fph = [math.radians(-50 + 100 * j / 12) for j in range(13)]
    fr = plate_rows(ctx, fph, [0.272, 0.302, 0.334, 0.364, 0.39, 0.41], 0.028, ridge=0.012, bottom_flare=0.006)
    def p_cuir(U, Vv, Pp, N):
        c = metal((0.40, 0.40, 0.43), U, Vv, 0.8, 6, 6, 35)
        c = mix(c, (0.26, 0.26, 0.29), band(U, 0.5, 0.015))
        c = edges(c, U, Vv, 0.08, 1.3, u=True)
        c = mix(c, (0.62, 0.20, 0.14), np.clip((fbm(U * 4, Vv * 4, 36) - 0.62) * 6, 0, 0.6))   # red paint daub
        return rivets(c, U, Vv, [0.1, 0.9], 9, r=0.016, asp=1.4)
    P.append(Part("cuirass", "acc", p_cuir, ("transfer", {"hips", "spine", "chest"}), solid=("rim", 0.014), out=V(0, 0.05, 0.33)).grid(fr, False))
    bph = [math.pi + math.radians(-46 + 92 * j / 12) for j in range(13)]
    bk = plate_rows(ctx, bph, [0.272, 0.31, 0.35, 0.39, 0.425, 0.442], 0.026)
    P.append(Part("backplate", "acc", lambda U, Vv, Pp, N: rivets(edges(metal((0.46, 0.43, 0.40), U, Vv, 0.9, 6, 6, 37), U, Vv, 0.08, 1.3, True), U, Vv, [0.1, 0.9], 9, r=0.016, asp=1.4),
                  ("transfer", {"hips", "spine", "chest"}), solid=("rim", 0.012), out=V(0, 0.05, 0.33)).grid(bk, False))
    # (gauntlets: the goblin's modelled bracers and fists are painted as plate, see paint_body "gauntlets")
    cols = 11; ph = [math.pi + math.radians(-46 + 92 * j / (cols - 1)) for j in range(cols)]
    zr = [0.43, 0.39, 0.34, 0.29, 0.245]; rows, rprev = [], [0.0] * cols
    for i, z in enumerate(zr):
        row = []
        for j, p in enumerate(ph):
            zz = z + ((0.03 if j % 2 else -0.012) + 0.01 * math.sin(j * 1.9) if i == len(zr) - 1 else 0.0)
            hit, d = ctx.torso(p, max(zz, 0.24)); r = max((hit - V(0, 0.05, hit.z)).length, rprev[j]); rprev[j] = r
            row.append(V(0, 0.05, zz) + d * (r + 0.055 + 0.08 * (0.43 - zz)))
        rows.append(row)
    def w_cape(i, co, part): return cloth_w(co, 0.42)
    def p_cape(U, Vv, Pp, N):
        c = felt((0.66, 0.15, 0.12), U, Vv, 8, 10, 0.25, 39) * (0.88 + 0.12 * np.sin(U * 6.28 * 4))[:, None]
        c = mix(c, (0.35, 0.07, 0.06), np.clip((Vv - 0.75) * 4, 0, 0.8))
        sk = (np.abs(U - 0.5) < 0.09) & (np.abs(Vv - 0.40) < 0.11)
        d = np.sqrt(((U - 0.5) / 0.09) ** 2 + ((Vv - 0.38) / 0.09) ** 2)
        skull = (d < 1) & ~((np.sqrt(((U - 0.47) / 0.025) ** 2 + ((Vv - 0.37) / 0.03) ** 2) < 1) | (np.sqrt(((U - 0.53) / 0.025) ** 2 + ((Vv - 0.37) / 0.03) ** 2) < 1))
        return np.where((skull & sk)[:, None], np.array((0.86, 0.82, 0.70)), c)
    P.append(Part("cape", "acc", p_cape, ("fn", w_cape), solid=("full", 0.006), out=V(0, 0.0, 0.33)).grid(rows, False))
    # greatsword on attach_weapon.R (blade flat in the bone's X-Y plane), off-hand grip on the hilt.
    # SWORD_DIR -1: the blade trails behind the fist (along -Y), +1: forward like the goblin's daggers.
    MR = ctx.M("attach_weapon.R"); X, Y, Z = (MR.to_3x3().col[i].normalized() for i in range(3)); O = MR.translation
    def S(bx, by, bz): return O + X * bx * SWORD_DIR + Y * by * SWORD_DIR + Z * bz
    b0, b1 = 0.10, 0.99
    def notch(s, spots, depth):
        return sum(depth * max(0.0, 1 - abs(s - c) / 0.022) for c in spots)
    sl = sorted(set([b0 + (b1 - b0) * k / 22 for k in range(23)] + [c + o for c in (0.30, 0.47, 0.66, 0.81, 0.39, 0.58, 0.74) for o in (-0.022, 0, 0.022)]))
    sl = [s for s in sl if b0 <= s <= b1]
    rows, prm = [], []
    for by in sl:
        f = (by - b0) / (b1 - b0)
        w = 0.052 - 0.012 * f
        wp = w - notch(by, (0.30, 0.47, 0.66, 0.81), 0.014); wm = w - notch(by, (0.39, 0.58, 0.74), 0.012)
        th = 0.010 * (1 - 0.6 * f)
        rows.append([S(wp, by, 0), S(0, by, th), S(-wm, by, 0), S(0, by, -th)]); prm.append(by)
    def p_blade(U, Vv, Pp, N):
        c = metal((0.47, 0.49, 0.52), U, Vv, 0.6, 3, 10, 40)
        edge = np.minimum(np.minimum(np.abs(U - 0.0), np.abs(U - 0.5)), np.abs(U - 1.0))
        c = mix(c, (0.80, 0.82, 0.84), np.clip(1 - edge / 0.08, 0, 1) * 0.8)
        c = mix(c, (0.28, 0.29, 0.31), band(np.abs(U - 0.25), 0, 0.03) + band(np.abs(U - 0.75), 0, 0.03))   # fuller
        return mix(c, (0.40, 0.14, 0.10), np.clip((fbm(U * 6, Vv * 30, 41) - 0.68) * 5, 0, 0.7))
    sw = Part("blade", "greatsword", p_blade, ("bone", "attach_weapon.R"))
    sw.grid(rows, True, pole1=S(-0.012, b1 + 0.06, 0), param=prm); P.append(sw)
    gpath = [S(x, 0.093, -0.022 * (abs(x) / 0.135) ** 2) for x in (-0.135, -0.09, -0.04, 0, 0.04, 0.09, 0.135)]
    gd = Part("guard", "greatsword", lambda U, Vv, Pp, N: edges(metal((0.36, 0.34, 0.33), U, Vv, 0.8, 4, 10, 42), U, Vv, 0.1, 1.25), ("bone", "attach_weapon.R"))
    gd.grid(tube(gpath, [0.02, 0.016, 0.015, 0.018, 0.015, 0.016, 0.02], 4, front=Y, start=math.pi / 4), True,
            pole0=S(-0.152, 0.093, -0.026), pole1=S(0.152, 0.093, -0.026)); P.append(gd)
    gp = [S(0, by, 0) for by in (0.085, 0.04, 0.0, -0.04, -0.08, -0.12, -0.16, -0.20, -0.215)]
    grip = Part("grip", "greatsword", None, ("bone", "attach_weapon.R"))
    grip.grid(tube(gp, [0.018 + (0.002 if k % 2 else 0) for k in range(9)], 6, front=Z), True)
    grip.paint = lambda U, Vv, Pp, N: felt((0.55, 0.12, 0.10), U, Vv, 10, 200, 0.3, 43) * (0.75 + 0.25 * (np.sin(Vv * 160 + U * 6.28) > 0))[:, None]
    P.append(grip)
    pm = Part("pommel", "greatsword", lambda U, Vv, Pp, N: edges(metal((0.38, 0.36, 0.34), U, Vv, 0.7, 4, 4, 44), U, Vv, 0.2, 1.3), ("bone", "attach_weapon.R"))
    pm.grid(tube([S(0, -0.222, 0), S(0, -0.245, 0), S(0, -0.268, 0)], [0.022, 0.034, 0.02], 6, front=Z), True, pole0=S(0, -0.215, 0), pole1=S(0, -0.29, 0))
    P.append(pm)
    extras.append(dict(name="grip_offhand", parent="attach_weapon.R", head=S(0, -0.135, 0), tail=S(0, -0.035, 0), up=Z, deform=False))
    return P, extras

def build_chief(ctx):
    P, extras = [], []
    n = 24; phis = [-math.pi + 2 * math.pi * j / n for j in range(n)]
    zf, zs, zb = 0.895, 0.950, 0.862
    E = [ctx.edge(p, zf, zs, zb) for p in phis]
    b0 = [ctx.shell(E[j], 0, 0.016) for j in range(n)]
    outs = [V(math.sin(p), -math.cos(p), 0) for p in phis]
    b1 = [b0[j] + V(0, 0, 0.058) + outs[j] * 0.012 for j in range(n)]
    def p_band(U, Vv, Pp, N):
        c = metal((0.86, 0.66, 0.26), U, Vv, 0.25, 8, 3, 51, rustc=(0.45, 0.32, 0.14))
        c = edges(c, U, Vv, 0.15, 1.25)
        gem = np.sqrt(((((U * 8) % 1) - 0.5) * 2.2) ** 2 + ((Vv - 0.5) * 3.2) ** 2) < 0.55
        return np.where(gem[:, None], np.array((0.75, 0.08, 0.08)), c)
    P.append(Part("crown_band", "acc", p_band, ("rigid", {"head": 1.0}), solid=("full", 0.012), out=HC).grid([b0, b1], True))
    sp = Part("crown_spikes", "acc", None, ("rigid", {"head": 1.0}), flat=True)
    for k in range(9):
        ph = math.radians(-160 + 40 * k); j = int(round((ph + math.pi) / (2 * math.pi) * n)) % n
        base = b1[j] - V(0, 0, 0.012); o = outs[j]
        ax = (V(0, 0, 1) * math.cos(math.radians(22)) + o * math.sin(math.radians(22))).normalized()
        h = 0.10 + 0.085 * max(0.0, math.cos(ph)) ** 2 + 0.02 * (k % 2)
        mid = base + ax * h * 0.55 + o * 0.012
        sp.grid(tube([base, mid], [0.021, 0.014], 4, front=o, start=math.pi / 4), True, pole1=base + ax * h + o * 0.02, u=(k / 9, (k + 1) / 9))
    sp.paint = lambda U, Vv, Pp, N: mix(col((0.90, 0.86, 0.74), len(U)), (0.36, 0.28, 0.22), np.clip((Vv - 0.75) * 4, 0, 1)) * (0.88 + 0.12 * np.sin(Vv * 50))[:, None]
    sp.size = (0.25, 0.15); P.append(sp)
    def p_skull(U, Vv, Pp, N):
        c = col((0.90, 0.86, 0.74), len(U)) * (0.9 + 0.1 * fbm(U * 20, Vv * 20, 52))[:, None]
        for eu in (0.43, 0.57):
            c = np.where((np.sqrt(((U - eu) / 0.05) ** 2 + ((Vv - 0.45) / 0.09) ** 2) < 1)[:, None], np.array((0.10, 0.06, 0.05)), c)
        c = np.where((np.sqrt(((U - 0.5) / 0.022) ** 2 + ((Vv - 0.60) / 0.05) ** 2) < 1)[:, None], np.array((0.15, 0.10, 0.08)), c)
        teeth = (np.abs(U - 0.5) < 0.09) & (np.abs(Vv - 0.76) < 0.035) & (np.sin(U * 200) > 0.6)
        return np.where(teeth[:, None], np.array((0.30, 0.24, 0.18)), c)
    cf = b0[n // 2].lerp(b1[n // 2], 0.5) + outs[n // 2] * 0.035
    sr, t0, t1 = skull_rows(cf, 0.042)
    P.append(Part("crown_skull", "acc", p_skull, ("rigid", {"head": 1.0}), out=cf).grid(sr, True, pole0=t0, pole1=t1))
    # fur mantle around the back and shoulders (outermost body surface, so it clears the arms)
    cols = 31; ph = [math.pi + math.radians(-115 + 230 * j / (cols - 1)) for j in range(cols)]
    spec = [(0.45, 0.024), (0.475, 0.08), (0.462, 0.14), (0.418, 0.178), (0.37, 0.198)]
    mrows = []
    for i, (z, off) in enumerate(spec):
        row = []
        for j, p in enumerate(ph):
            r = 0.0; d = V(math.sin(p), -math.cos(p), 0)
            for dz in (-0.03, 0.0, 0.03):
                hit = ctx.outer(V(0, 0.05, z + dz), d)
                if hit: r = max(r, (hit - V(0, 0.05, hit.z)).length)
            last = i == len(spec) - 1
            jag = ((0.05 if j % 2 else -0.012) + 0.012 * math.sin(j * 2.7)) if last else (0.012 * math.sin(j * 1.9 + i) if i > 0 else 0.0)
            zz = z + (((-0.04 if j % 2 else 0.012) + 0.01 * math.cos(j * 3.1)) if last else 0.008 * math.sin(j * 2.3 + i) * (i > 0))
            if i == 0: r = ctx.torso(p, z)[0].__sub__(V(0, 0.05, z)).length
            row.append(V(0, 0.05, zz) + d * (r + off + jag))
        mrows.append(row)
    def p_fur(U, Vv, Pp, N):
        st = fbm(U * 140, Vv * 5, 53); clump = fbm(U * 18, Vv * 3, 61)
        c = mix(col((0.24, 0.17, 0.11), len(U)), (0.62, 0.52, 0.38), np.clip(Vv * 1.3 - 0.35 + (st - 0.5) * 1.0 + (clump - 0.5) * 0.6, 0, 1))
        c = mix(c, (0.80, 0.74, 0.62), np.clip((Vv - 0.86) * 6, 0, 1) * (st > 0.5) * 0.7)
        return c * (0.68 + 0.55 * st)[:, None]
    def w_mantle(i, co, part):   # chest/spine/neck from the body; upper arm only out past the shoulder joint
        sx = 1 if co.x >= 0 else -1; ax = ctx.bones["upper_arm." + ("L" if sx > 0 else "R")].head_local
        k = sm(abs(ax.x) - 0.02, abs(ax.x) + 0.10, abs(co.x))
        return shoulder_w(co, V(ax.x * 0.6, ax.y, ax.z + 0.02), sx, 0.85 * k, 0.0, {"chest", "spine", "neck"})
    mant = Part("mantle", "acc", p_fur, ("fn", w_mantle), solid=("full", 0.02), out=V(0, 0.05, 0.38))
    mant.bake, mant.bake_cap = ("transfer", {"chest", "spine", "neck", "upper_arm.L", "upper_arm.R"}), 0.5
    P.append(mant.grid(mrows, False))
    def tusk_w(B, sx):   # rigid: the mantle's body weights at the base, a fixed 20 % upper arm (they point at the head)
        d = {k: v * 0.8 for k, v in w_mantle(0, B, None).items() if not k.startswith("upper_arm")}
        s_ = sum(d.values()) or 1.0; d = {k: 0.8 * v / s_ for k, v in d.items()}; d["upper_arm." + ("L" if sx > 0 else "R")] = 0.2
        print("TUSK", sx, tuple(round(c, 3) for c in B), {k: round(v, 2) for k, v in d.items()})
        return d
    for sx in (1, -1):
        j = int(round(((180 - 84 * sx) - 65) / 230 * (cols - 1)))
        j = min(max(j, 0), cols - 1)
        B = mrows[2][j] + V(0, 0, 0.01)
        ctrl = [B, B + V(0.035 * sx, -0.03, 0.07), B + V(0.06 * sx, -0.08, 0.13), B + V(0.05 * sx, -0.135, 0.17)]
        path = [catmull(ctrl, k / 7) for k in range(8)]
        tk = Part("tusk_" + ("L" if sx > 0 else "R"), "acc",
                      lambda U, Vv, Pp, N: mix(col((0.55, 0.46, 0.34), len(U)), (0.95, 0.91, 0.80), np.clip(Vv * 2, 0, 1)) * (0.92 + 0.08 * np.sin(Vv * 60))[:, None],
                      ("rigid", tusk_w(B, sx))).grid(
            tube(path, [0.032 * (1 - k / 8) + 0.004 for k in range(8)], 7, front=V(0, -1, 0)), True, pole1=path[-1] + (path[-1] - path[-2]).normalized() * 0.012)
        tk.bake = ("rigid_at", B, {"chest", "upper_arm." + ("L" if sx > 0 else "R")}); P.append(tk)
    # long tattered cape under the mantle
    cols = 15; ph = [math.pi + math.radians(-62 + 124 * j / (cols - 1)) for j in range(cols)]
    zr = [0.43, 0.37, 0.30, 0.23, 0.16, 0.10, 0.05]; rows, rprev = [], [0.0] * cols
    for i, z in enumerate(zr):
        row = []
        for j, p in enumerate(ph):
            zz = z + ((0.035 if j % 3 == 1 else 0.012 if j % 3 == 2 else -0.012) + 0.008 * math.sin(j * 2.1) if i == len(zr) - 1 else 0.0)
            hit, d = ctx.torso(p, max(zz, 0.24), outer=True); r = max((hit - V(0, 0.05, hit.z)).length, rprev[j]); rprev[j] = r
            row.append(V(0, 0.05, zz) + d * (r + 0.03 + 0.13 * (0.43 - zz)))
        rows.append(row)
    def w_cape(i, co, part): return cloth_w(co, 0.41)
    def p_cape(U, Vv, Pp, N):
        c = felt((0.58, 0.09, 0.08), U, Vv, 8, 12, 0.25, 54) * (0.86 + 0.14 * np.sin(U * 6.28 * 5 + fbm(U * 3, Vv * 3, 55) * 2))[:, None]
        c = mix(c, (0.25, 0.05, 0.05), np.clip((Vv - 0.78) * 4.5, 0, 0.85))
        c = mix(c, (0.85, 0.66, 0.26), band(Vv, 0.06, 0.02))
        return c
    P.append(Part("cape", "acc", p_cape, ("fn", w_cape), solid=("full", 0.007), out=V(0, 0.0, 0.3)).grid(rows, False))
    fph = [math.radians(-50 + 100 * j / 12) for j in range(13)]
    fr = plate_rows(ctx, fph, [0.272, 0.302, 0.334, 0.364, 0.39, 0.41], 0.03, ridge=0.014, bottom_flare=0.006)
    def p_cuir(U, Vv, Pp, N):
        c = metal((0.32, 0.30, 0.30), U, Vv, 0.5, 6, 6, 56)
        tr = np.maximum(np.maximum(band(Vv, 0.0, 0.09), band(Vv, 1.0, 0.09)), np.maximum(band(U, 0.0, 0.05), band(U, 1.0, 0.05)))
        c = mix(c, (0.88, 0.68, 0.27), (tr > 0.25) * 0.95)
        c = mix(c, (0.88, 0.68, 0.27), band(U, 0.5, 0.012) * (Vv > 0.1) * (Vv < 0.9))
        return rivets(c, U, Vv, [0.5], 4, rc=(0.75, 0.10, 0.08), r=0.03, asp=1.4)
    P.append(Part("cuirass", "acc", p_cuir, ("transfer", {"hips", "spine", "chest"}), solid=("rim", 0.014), out=V(0, 0.05, 0.33)).grid(fr, False))
    bp, d = ctx.torso(0.0, 0.262); sc = bp + d * 0.062
    sr, t0, t1 = skull_rows(sc, 0.05, front=d)
    P.append(Part("belt_skull", "acc", p_skull, ("rigid_at", sc, {"hips", "spine"}), out=sc).grid(sr, True, pole0=t0, pole1=t1))
    for sd in "LR":   # twin oversized cleaver-daggers
        M = ctx.M("attach_weapon." + sd); X, Y, Z = (M.to_3x3().col[i].normalized() for i in range(3)); O = M.translation
        sgn = 1 if sd == "L" else -1
        def S(bx, by, bz, O=O, X=X, Y=Y, Z=Z): return O + X * bx + Y * by + Z * bz
        bys = [0.085 + 0.33 * k / 14 for k in range(15)]
        rows, prm = [], []
        for k, by in enumerate(bys):
            f = k / 14
            spine = 0.014 * sgn - (0.012 * sgn if k in (4, 7, 10) else 0.0) * 0.6
            ew = 0.070 + 0.03 * math.sin(f * math.pi * 0.9) - 0.06 * max(0.0, f - 0.85) / 0.15
            edge = -ew * sgn; th = 0.007 * (1 - 0.4 * f)
            rows.append([S(spine, by, th), S(edge, by, 0), S(spine, by, -th), S(spine + 0.006 * sgn, by, 0)]); prm.append(by)
        def p_cl(U, Vv, Pp, N):
            c = metal((0.36, 0.36, 0.38), U, Vv, 0.6, 3, 12, 58)
            c = mix(c, (0.85, 0.86, 0.88), band(U, 0.25, 0.09) * 0.85)
            c = mix(c, (0.38, 0.06, 0.05), np.clip((fbm(U * 5, Vv * 12, 59) - 0.55) * 4, 0, 0.75) * (np.abs(U - 0.25) < 0.2))
            hole = np.sqrt(((Vv - 0.78) / 0.05) ** 2 + ((U - 0.06) / 0.04) ** 2) < 1
            return np.where(hole[:, None], np.array((0.08, 0.07, 0.07)), c)
        P.append(Part("cleaver_blade." + sd, "cleaver." + sd, p_cl, ("bone", "attach_weapon." + sd)).grid(rows, True, pole1=S(0.004 * sgn, 0.43, 0), param=prm))
        hp = [S(0, by, 0) for by in (0.09, 0.07, 0.03, -0.01, -0.05, -0.09, -0.11)]
        def p_h(U, Vv, Pp, N):
            c = mix(col((0.88, 0.83, 0.70), len(U)), (0.42, 0.24, 0.14), (np.sin(Vv * 90) > 0.2) * 0.85)
            return np.where(((Vv < 0.18) | (Vv > 0.88))[:, None], metal((0.88, 0.68, 0.27), U, Vv, 0.2, 4, 4, 60), c)
        P.append(Part("cleaver_grip." + sd, "cleaver." + sd, p_h, ("bone", "attach_weapon." + sd)).grid(
            tube(hp, [0.024, 0.02, 0.016, 0.017, 0.016, 0.017, 0.021], 6, front=Z), True, pole0=S(0, 0.095, 0), pole1=S(0, -0.125, 0)))
    return P, extras

# ------------------------------------------------------------------ per-variant look
CFG = {
    "archer": dict(scale=1.06, build=build_archer,
                   girth={"upper_arm": 0.88, "forearm": 0.88, "hand": 0.95, "thigh": 0.9, "shin": 0.9, "hips": 0.92, "spine": 0.9, "chest": 0.92},
                   pal=dict(skin=(0.50, 0.58, 0.27), warm=(0.66, 0.66, 0.36), iron=(0.27, 0.39, 0.19), leather=(0.45, 0.30, 0.17),
                            strap=(0.32, 0.22, 0.13), cloth=(0.36, 0.48, 0.24), pants=(0.40, 0.31, 0.20), boot=(0.33, 0.22, 0.13), brass=(0.72, 0.58, 0.32)),
                   rust=0.0, eye=((0.86, 0.96, 0.32), (1.0, 1.0, 0.8)), armguard=True),
    "mage": dict(scale=1.0, build=build_mage,
                 girth={"upper_arm": 0.92, "forearm": 0.92, "thigh": 0.94, "shin": 0.94, "spine": 0.95, "chest": 0.95, "hips": 0.97},
                 pal=dict(skin=(0.45, 0.53, 0.33), warm=(0.60, 0.63, 0.41), iron=(0.30, 0.23, 0.50), leather=(0.40, 0.27, 0.32),
                          strap=(0.25, 0.18, 0.30), cloth=(0.82, 0.62, 0.25), pants=(0.32, 0.25, 0.42), boot=(0.30, 0.22, 0.20), brass=(0.86, 0.70, 0.30)),
                 rust=0.0, eye=((0.50, 0.92, 1.0), (0.95, 1.0, 1.0))),
    "knight": dict(scale=1.28, build=build_knight,
                   girth={"upper_arm": 1.18, "forearm": 1.2, "hand": 1.12, "thigh": 1.15, "shin": 1.16, "foot": 1.1, "toe": 1.08,
                          "hips": 1.12, "spine": 1.18, "chest": 1.18, "neck": 1.1},
                   pal=dict(skin=(0.40, 0.52, 0.24), warm=(0.54, 0.60, 0.30), iron=(0.40, 0.40, 0.43), leather=(0.36, 0.26, 0.18),
                            strap=(0.28, 0.20, 0.14), cloth=(0.70, 0.16, 0.13), pants=(0.32, 0.29, 0.28), boot=(0.32, 0.32, 0.34), brass=(0.62, 0.52, 0.30)),
                   rust=0.8, eye=((1.0, 0.70, 0.15), (1.0, 0.95, 0.7)), gauntlets=(0.44, 0.44, 0.47)),
    "chief": dict(scale=1.72, build=build_chief,
                  girth={"upper_arm": 1.22, "forearm": 1.22, "hand": 1.18, "thigh": 1.2, "shin": 1.18, "foot": 1.1,
                         "hips": 1.22, "spine": 1.28, "chest": 1.25, "neck": 1.15},
                  pal=dict(skin=(0.40, 0.50, 0.26), warm=(0.56, 0.58, 0.33), iron=(0.33, 0.31, 0.30), leather=(0.42, 0.24, 0.16),
                           strap=(0.30, 0.16, 0.12), cloth=(0.62, 0.10, 0.10), pants=(0.30, 0.22, 0.18), boot=(0.28, 0.20, 0.15), brass=(0.90, 0.72, 0.28)),
                  rust=0.3, eye=((1.0, 0.30, 0.10), (1.0, 0.85, 0.5)), warpaint=True, gauntlets=(0.34, 0.32, 0.31), gold_trim=True),
}
BASE_PAL = dict(skin=(0.44, 0.56, 0.25), warm=(0.60, 0.64, 0.32), inner_ear=(0.72, 0.50, 0.40), iron=(0.55, 0.52, 0.48),
                leather=(0.50, 0.33, 0.19), strap=(0.36, 0.24, 0.15), cloth=(0.66, 0.30, 0.22), pants=(0.42, 0.37, 0.30),
                boot=(0.38, 0.26, 0.17), mouth=(0.88, 0.80, 0.55), brass=(0.78, 0.62, 0.30), gullet=(0.36, 0.11, 0.10))

def bilinear(img, x, y):
    h, w = img.shape[:2]; x = np.clip(x, 0, w - 1.001); y = np.clip(y, 0, h - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int); fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    a, b, c, d = img[y0, x0], img[y0, x0 + 1], img[y0 + 1, x0], img[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def paint_body(cfg):
    m = np.load(os.path.join(CACHE, "goblin_bake.npz"))
    yy, xx = np.mgrid[0:BODY_PX, 0:BODY_PX].astype(float)
    ox, oy = (xx + 0.5) * 0.75 - 0.5, (yy + 0.5) * 0.75 - 0.5
    REG = m["region"][np.clip(np.round(oy).astype(int), 0, 511), np.clip(np.round(ox).astype(int), 0, 511)]
    POS, NRM, AO = bilinear(m["pos"], ox, oy), bilinear(m["nrm"], ox, oy), bilinear(m["ao"], ox, oy)
    pal = dict(BASE_PAL); pal.update(cfg["pal"])
    rid = np.clip((REG[..., 0] * 16).astype(int), 0, 15)
    pos = POS[..., :3] * 2 - 1; nrm = NRM[..., :3] * 2 - 1; nrm /= np.maximum(np.linalg.norm(nrm, axis=2, keepdims=True), 1e-6)
    ao = np.clip(AO[..., 0], 0, 1); X, Y, Z = pos[..., 0], pos[..., 1], pos[..., 2]
    base = np.zeros((BODY_PX, BODY_PX, 3))
    for k, i in R_ID.items(): base[rid == i] = pal[k]
    def nz(a, b, c): return (np.sin(X * a + Z * 1.7) * np.sin(Y * b - Z * c) + 0.5 * np.sin(Z * c * 2.1 + X * b)) / 1.5
    streak, blot = nz(31, 23, 47), nz(13, 11, 9)
    iron = rid == R_ID["iron"]
    if cfg["rust"] > 0:
        rust = (np.clip((blot - 0.15) * 3, 0, 1) * 0.75 * cfg["rust"])[..., None]
        base = np.where(iron[..., None], base * (1 - rust) + np.array((0.60, 0.36, 0.20)) * rust, base)
    else:   # cloth/leather jerkin or robe: stitched seams instead of rust
        seam = (np.abs(np.sin(Z * 70)) < 0.08) & iron
        base = np.where(seam[..., None], base * 0.75, base)
        lace = iron & (np.abs(X) < 0.014) & (Y < -0.04) & (Z > 0.31) & (Z < 0.455) & (np.abs(np.sin(Z * 160 + np.abs(X) * 300)) > 0.4)
        base[lace] = (0.80, 0.72, 0.50)
    skin = np.isin(rid, [R_ID["skin"], R_ID["warm"]])
    base = np.where(skin[..., None], base * (1 + 0.07 * blot[..., None]), base)
    if cfg.get("gauntlets"):   # the modelled bracers + fists painted as plate gauntlets
        gc = np.array(cfg["gauntlets"])
        fist = np.isin(rid, [R_ID["skin"], R_ID["warm"]]) & (np.abs(X) > 0.2) & (Z < 0.31) & (Z > 0.12)
        brac = rid == R_ID["leather"]
        g = fist | brac
        plate = gc * (0.88 + 0.18 * blot[..., None])
        base = np.where(g[..., None], plate, base)
        ring = g & (np.abs(np.sin(Z * 95)) < 0.16); base[ring] = gc * 0.6
        if cfg.get("gold_trim"):
            base[brac & (np.abs(np.sin(Z * 60)) < 0.12)] = (0.88, 0.68, 0.27)
    if cfg.get("armguard"):   # laced leather arm guards on the modelled forearm bracers
        lth = rid == R_ID["leather"]
        lace = lth & (Z > 0.27) & (np.abs(np.sin(Z * 220)) > 0.75) & (np.abs(np.sin((X * 3 + Y * 3) * 40)) < 0.35)
        base[lace] = (0.82, 0.74, 0.55)
    mouth = rid == R_ID["mouth"]
    base = np.where((mouth & (ao < 0.62))[..., None], np.array((0.32, 0.10, 0.09)), base)
    gul = rid == R_ID["gullet"]; base[gul & (ao > 0.80) & (Y < -0.215)] = pal["warm"]
    front = (nrm[..., 1] < -0.2) & (Y < -0.10)
    if cfg.get("warpaint"):   # blood-red mask across the eyes + two chin stripes
        mask = front & (np.abs(Z - 0.79 - 0.05 * np.abs(X)) < 0.045) & (np.abs(X) < 0.27) & skin
        base = np.where(mask[..., None], base * 0.35 + np.array((0.55, 0.05, 0.04)) * 0.65, base)
        chin = front & skin & (Z < 0.55) & (Z > 0.47) & ((np.abs(X - 0.05) < 0.012) | (np.abs(X + 0.05) < 0.012))
        base[chin] = (0.55, 0.06, 0.05)
    e_col, e_core = cfg["eye"]
    for ex in (0.135, -0.135):
        sx = np.sign(ex); dx = X - ex; dz = Z - 0.79 - 0.22 * dx * sx
        dd = np.sqrt((dx / 0.068) ** 2 + (dz / 0.040) ** 2)
        base[front & (dd < 1.15)] = base[front & (dd < 1.15)] * 0.35 + np.array((0.13, 0.11, 0.08)) * 0.65
        base[front & (dd < 1.0)] = (0.11, 0.09, 0.07)
        de = np.sqrt((X - ex * 0.9) ** 2 + (Z - 0.784) ** 2)
        base[front & (de < 0.019)] = e_col; base[front & (de < 0.007)] = e_core
    light = 0.80 + 0.22 * np.clip((nrm * LIGHT).sum(2), 0, 1)
    shade = light * (0.45 + 0.55 * ao ** 0.9) * (1 + 0.05 * streak)
    edge = np.clip((ao - 0.93) * 8, 0, 1) * iron * (cfg["rust"] > 0)
    return np.clip(base * shade[..., None] + edge[..., None] * 0.10, 0, 1)

# ------------------------------------------------------------------ pipeline
def activate(obj, *others):
    if bpy.context.object and bpy.context.object.mode != 'OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for o in others: o.select_set(True)
    obj.select_set(True); bpy.context.view_layer.objects.active = obj

def body_weights(body, deform):
    W = np.zeros((len(body.data.vertices), len(deform))); colix = {n: i for i, n in enumerate(deform)}
    for v in body.data.vertices:
        for g in v.groups:
            nm = body.vertex_groups[g.group].name
            if nm in colix: W[v.index, colix[nm]] = g.weight
    return W, colix

def girth(body, rig, factors, W, colix):
    segs = {}
    for n, i in colix.items():
        b = rig.data.bones[n]; segs[n] = (np.array(b.head_local), np.array(b.tail_local), factors.get(n.split(".")[0], 1.0))
    co = np.array([v.co[:] for v in body.data.vertices]); new = co.copy()
    for n, i in colix.items():
        h, t, k = segs[n]
        if abs(k - 1) < 1e-6: continue
        a = t - h; L = np.dot(a, a); s = np.clip(((co - h) @ a) / L, 0, 1)
        p = h + s[:, None] * a; d = co - p; an = a / np.sqrt(L)
        dperp = d - (d @ an)[:, None] * an
        new += W[:, i][:, None] * (k - 1) * dperp
    body.data.vertices.foreach_set("co", new.ravel()); body.data.update()

def pack(parts):
    total = sum(p.size[0] * p.size[1] for p in parts)
    area = sum(b[2] * b[3] for b in BINS)
    D = math.sqrt(0.62 * area / total)
    for attempt in range(40):
        rects = []
        for p in parts:
            w, h = max(8, int(p.size[0] * D)), max(8, int(p.size[1] * D))
            rects.append([p, w, h, False])
        order = sorted(rects, key=lambda r: -max(r[1], r[2]))
        shelves = [[b, 0, 0, 0] for b in BINS]    # bin, shelf_y, cursor_x, shelf_h
        ok = True
        for r in order:
            placed = False
            for sh in shelves:
                (bx, by, bw, bh) = sh[0]
                for rot in (False, True):
                    w, h = (r[2], r[1]) if rot else (r[1], r[2])
                    if w + PAD > bw: continue
                    if sh[2] + w + PAD > bw:      # new shelf
                        if sh[1] + sh[3] + h + PAD > bh: continue
                        sh[1] += sh[3]; sh[2] = 0; sh[3] = 0
                    if sh[1] + h + PAD > bh: continue
                    r[0].rect = (bx + sh[2] + PAD // 2, by + sh[1] + PAD // 2, w, h, rot)
                    sh[2] += w + PAD; sh[3] = max(sh[3], h + PAD); placed = True; break
                if placed: break
            if not placed: ok = False; break
        if ok: return D
        D *= 0.95
    raise RuntimeError("UV pack failed")

def make_object(part, rig, coll):
    me = bpy.data.meshes.new(part.name); bm = bmesh.new(); uvl = bm.loops.layers.uv.new("UVMap")
    vs = [bm.verts.new(v) for v in part.V]; faces = []
    x0, y0, w, h, rot = part.rect
    for (f, mat), uv in zip(part.F, part.UV):
        try: bf = bm.faces.new([vs[i] for i in f])
        except ValueError: continue
        bf.material_index = mat
        for lp, (u, v) in zip(bf.loops, uv):
            lp[uvl].uv = (((x0 + v * w) if rot else (x0 + u * w)) / TEX, ((y0 + u * h) if rot else (y0 + v * h)) / TEX)
        faces.append(bf)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    fn = getattr(part, "out_fn", None)
    if fn or part.out is not None:
        s = sum(f.normal.dot(fn(f.calc_center_median()) if fn else (f.calc_center_median() - Vector(part.out))) for f in faces)
        if s < 0: bmesh.ops.reverse_faces(bm, faces=faces)
    bm.to_mesh(me); bm.free()
    mi = me.attributes.new("mat_slot", 'INT', 'FACE')   # kept: clearing material slots (bake) resets material_index
    mi.data.foreach_set("value", [p.material_index for p in me.polygons])
    ob = bpy.data.objects.new(part.name, me); coll.objects.link(ob)
    return ob

def transfer(ctx, W, colix, co, allow, arm_cap=None):
    loc, nrm, fi, dist = ctx.bvh.find_nearest(co)
    if fi is None: return {}
    tri = ctx.polys[fi]; pts = [ctx.verts[i] for i in tri]
    import mathutils.geometry as G
    a = G.area_tri(loc, pts[1], pts[2]); b = G.area_tri(pts[0], loc, pts[2]); c = G.area_tri(pts[0], pts[1], loc)
    s = max(a + b + c, 1e-12); w = (a * W[tri[0]] + b * W[tri[1]] + c * W[tri[2]]) / s
    out = {n: float(w[i]) for n, i in colix.items() if n in allow and w[i] > 1e-3}
    if arm_cap is not None:
        for n in list(out):
            if n.startswith("upper_arm"): out[n] *= arm_cap
    return out

def norm4(d, fallback):
    d = {k: v for k, v in sorted(d.items(), key=lambda kv: -kv[1])[:4] if v > 1e-4}
    s = sum(d.values())
    return {k: v / s for k, v in d.items()} if s > 1e-6 else {fallback: 1.0}

def build_variant(name):
    cfg = CFG[name]; vname = "goblin_" + name
    bpy.ops.wm.open_mainfile(filepath=os.path.join(CACHE, "goblin_prehunch.blend"))
    sc = bpy.context.scene
    body, rig = bpy.data.objects["goblin"], bpy.data.objects["goblin_rig"]
    for o in [o for o in bpy.data.objects if o.name.startswith("dagger")]: bpy.data.objects.remove(o, do_unlink=True)
    body.name = vname; body.data.name = vname; rig.name = vname + "_rig"; rig.data.name = vname + "_rig"
    deform = [b.name for b in rig.data.bones if b.use_deform]
    W, colix = body_weights(body, deform)
    girth(body, rig, cfg["girth"], W, colix)
    fix_soles(body, rig, W, colix)
    ctx = Ctx(body, rig); XFER.update(ctx=ctx, W=W, colix=colix)
    parts, extras = cfg["build"](ctx)
    D = pack(parts)
    coll = sc.collection
    objs = [make_object(p, rig, coll) for p in parts]
    # ---- bake AO / normal / position of the accessories (body present as occluder)
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 32; sc.render.bake.margin = 4
    bmat = bpy.data.materials.new("bake"); bmat.use_nodes = True; nt = bmat.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); emi = nt.nodes.new("ShaderNodeEmission"); img = nt.nodes.new("ShaderNodeTexImage")
    geo = nt.nodes.new("ShaderNodeNewGeometry"); vm = nt.nodes.new("ShaderNodeVectorMath"); vm.operation = 'MULTIPLY_ADD'
    vm.inputs[1].default_value = (0.5, 0.5, 0.5); vm.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(geo.outputs["Position"], vm.inputs[0]); nt.links.new(vm.outputs[0], emi.inputs[0]); nt.links.new(emi.outputs[0], out.inputs[0])
    nt.nodes.active = img
    for o in objs:
        o.data.materials.clear(); o.data.materials.append(bmat); o.data.materials.append(bmat)
    maps = {}
    for kind, btype in (("ao", 'AO'), ("nrm", 'NORMAL'), ("pos", 'EMIT')):
        im = bpy.data.images.new("bk_" + kind, TEX, TEX, float_buffer=True); im.colorspace_settings.name = 'Non-Color'; img.image = im
        activate(objs[0], *objs[1:])
        bpy.ops.object.bake(type=btype, normal_space='OBJECT', margin=4, use_selected_to_active=False)
        maps[kind] = np.array(im.pixels[:], dtype=np.float32).reshape(TEX, TEX, 4)
    # ---- paint
    texa = np.zeros((TEX, TEX, 3)); texa[:] = (0.35, 0.33, 0.30)
    texa[:BODY_PX, :BODY_PX] = paint_body(cfg)
    nrmA = maps["nrm"][..., :3] * 2 - 1; nrmA /= np.maximum(np.linalg.norm(nrmA, axis=2, keepdims=True), 1e-6)
    posA = maps["pos"][..., :3] * 2 - 1; aoA = np.clip(maps["ao"][..., 0], 0, 1)
    for p in parts:
        x0, y0, w, h, rot = p.rect
        xs0, ys0, xs1, ys1 = max(0, x0 - 2), max(0, y0 - 2), min(TEX, x0 + w + 2), min(TEX, y0 + h + 2)
        yy, xx = np.mgrid[ys0:ys1, xs0:xs1]
        fu, fv = np.clip((xx + 0.5 - x0) / w, 0, 1), np.clip((yy + 0.5 - y0) / h, 0, 1)
        U, Vv = (fv, fu) if rot else (fu, fv)
        U, Vv = U.ravel(), Vv.ravel()
        Pp = posA[ys0:ys1, xs0:xs1].reshape(-1, 3); N = nrmA[ys0:ys1, xs0:xs1].reshape(-1, 3); A = aoA[ys0:ys1, xs0:xs1].ravel()
        c = p.paint(U, Vv, Pp, N)
        if not p.flat:
            light = 0.80 + 0.22 * np.clip(N @ LIGHT, 0, 1)
            c = c * (light * (0.45 + 0.55 * A ** 0.9))[:, None]
        texa[ys0:ys1, xs0:xs1] = np.clip(c, 0, 1).reshape(ys1 - ys0, xs1 - xs0, 3)
    tdir = os.path.join(ROOT, "art_source/monsters", vname, "textures"); os.makedirs(tdir, exist_ok=True)
    tpath = os.path.join(tdir, vname + "_albedo.png")
    tex = bpy.data.images.new(vname + "_albedo", TEX, TEX, alpha=False)
    px = np.ones((TEX, TEX, 4), dtype=np.float32); px[..., :3] = texa
    tex.pixels.foreach_set(px.ravel()); tex.filepath_raw = tpath; tex.file_format = 'PNG'; tex.save(); tex.reload()
    mat = bpy.data.materials.new(vname); mat.use_nodes = True
    bs = mat.node_tree.nodes["Principled BSDF"]; bs.inputs["Roughness"].default_value = 0.88
    ti = mat.node_tree.nodes.new("ShaderNodeTexImage"); ti.image = tex; mat.node_tree.links.new(ti.outputs["Color"], bs.inputs["Base Color"])
    glow = bpy.data.materials.new(vname + "_glow"); glow.use_nodes = True
    gb = glow.node_tree.nodes["Principled BSDF"]; gb.inputs["Base Color"].default_value = (0.30, 0.80, 1.0, 1)
    gb.inputs["Emission Color"].default_value = (0.30, 0.80, 1.0, 1); gb.inputs["Emission Strength"].default_value = 2.2
    body.data.materials.clear(); body.data.materials.append(mat)
    uv = body.data.uv_layers.active.data; arr = np.zeros(len(uv) * 2); uv.foreach_get("uv", arr); uv.foreach_set("uv", arr * (BODY_PX / TEX) / 0.9375)
    for o in objs:
        o.data.materials.clear(); o.data.materials.append(mat); o.data.materials.append(glow)
        att = o.data.attributes["mat_slot"]; vals = [0] * len(o.data.polygons); att.data.foreach_get("value", vals)
        o.data.polygons.foreach_set("material_index", vals); o.data.attributes.remove(att); o.data.update()
    # ---- extra bones (pre-hunch rest; children, never renamed/removed bones)
    activate(rig); bpy.ops.object.mode_set(mode='EDIT')
    for ex in extras:
        eb = rig.data.edit_bones.new(ex["name"]); eb.head = ex["head"]; eb.tail = ex["tail"]
        eb.parent = rig.data.edit_bones[ex["parent"]]; eb.align_roll(ex["up"]); eb.use_deform = ex["deform"]
    if name == "archer": rig.data.edit_bones["attach_weapon.L"].use_deform = True    # the skinned bow
    bpy.ops.object.mode_set(mode='OBJECT')
    # ---- weights, thickness, skinning / bone parenting
    props = {}
    for p, o in zip(parts, objs):
        kind = p.weights[0]
        if p.group != "acc" and not getattr(p, "skin_prop", False):
            props.setdefault(p.group, []).append((p, o)); continue
        def weigh(spec, cap):
            per = []
            for i, v in enumerate(o.data.vertices):
                k_ = spec[0]
                if k_ == "rigid": d = dict(spec[1])
                elif k_ == "rigid_at":
                    d = per[0] if per else transfer(ctx, W, colix, Vector(spec[1]), spec[2])
                elif k_ == "transfer": d = transfer(ctx, W, colix, v.co, spec[1], cap)
                else: d = spec[1](i, v.co, p)
                per.append(norm4(d, "chest"))
            return per
        # p.bake: the weights the hunch is baked with (the piece's approved rest shape); p.weights then
        # replace them after the bake (kept meanwhile in "anim__<bone>" groups, which solidify copies too)
        bake = getattr(p, "bake", None)
        for pre, spec, cap in ((("", bake, getattr(p, "bake_cap", None)), ("anim__", p.weights, None)) if bake else (("", p.weights, getattr(p, "arm_cap", None)),)):
            for i, d in enumerate(weigh(spec, cap)):
                for bn, wv in d.items():
                    g = o.vertex_groups.get(pre + bn) or o.vertex_groups.new(name=pre + bn); g.add([i], wv, 'REPLACE')
        if p.solid:
            mod = o.modifiers.new("solid", 'SOLIDIFY'); mod.thickness = p.solid[1]; mod.offset = -1.0
            mod.use_rim = True; mod.use_rim_only = p.solid[0] == "rim"; mod.use_even_offset = True
            activate(o); bpy.ops.object.modifier_apply(modifier="solid")
        o.parent = rig; am = o.modifiers.new("Armature", 'ARMATURE'); am.object = rig
    prop_objs = []
    for grp, lst in props.items():
        ob = lst[0][1]
        if len(lst) > 1:
            activate(ob, *[o for _, o in lst[1:]]); bpy.ops.object.join()
        ob.name = grp; ob.data.name = grp
        bone = lst[0][0].weights[1]
        mw = ob.matrix_world.copy(); ob.parent = rig; ob.parent_type = 'BONE'; ob.parent_bone = bone
        bpy.context.view_layer.update(); ob.matrix_world = mw
        prop_objs.append(ob)
    skinned_props = [o for p, o in zip(parts, objs) if getattr(p, "skin_prop", False)]
    if len(skinned_props) > 1:
        activate(skinned_props[0], *skinned_props[1:]); bpy.ops.object.join()
    if skinned_props:
        bo = skinned_props[0]; bo.name = "bow"; bo.data.name = "bow"; prop_objs.append(bo)
    acc = [o for p, o in zip(parts, objs) if p.group == "acc" and o.name in bpy.data.objects]
    for o in acc + [body] + [o for o in prop_objs if o.parent_type != 'BONE']:
        for pl in o.data.polygons: pl.use_smooth = True
        o.data.set_sharp_from_angle(angle=math.radians(38))
    for o in prop_objs:
        if o.parent_type == 'BONE':
            for pl in o.data.polygons: pl.use_smooth = True
            o.data.set_sharp_from_angle(angle=math.radians(38))
    # ---- bake the goblin hunch into the rest (exactly as build_goblin.py)
    skinned = [body] + acc + [o for o in prop_objs if o.parent_type != 'BONE']
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'; pb.location = (0, 0, 0)
        pb.rotation_euler = [math.radians(a) for a in HUNCH.get(pb.name, (0, 0, 0))]
    bpy.context.view_layer.update()
    for o in skinned:
        activate(o); bpy.ops.object.modifier_apply(modifier=[m for m in o.modifiers if m.type == 'ARMATURE'][0].name)
    rigid_w = [(o, o.matrix_world.copy()) for o in prop_objs if o.parent_type == 'BONE']
    activate(rig); bpy.ops.object.mode_set(mode='POSE'); bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.pose.armature_apply(selected=False); bpy.ops.object.mode_set(mode='OBJECT'); bpy.context.view_layer.update()
    for o, mw in rigid_w: o.matrix_world = mw
    for pb in rig.pose.bones: pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = (1, 0, 0, 0)   # as the clips key it
    for o in skinned:
        if any(g.name.startswith("anim__") for g in o.vertex_groups):   # swap in the animated weights
            for g in [g for g in o.vertex_groups if not g.name.startswith("anim__")]: o.vertex_groups.remove(g)
            for g in o.vertex_groups: g.name = g.name[6:]
        am = o.modifiers.new("Armature", 'ARMATURE'); am.object = rig
    ht = rig.data.bones["head"].tail_local
    assert (ht - V(0, -0.033, 0.933)).length < 2e-3, ht
    for a in list(bpy.data.actions): bpy.data.actions.remove(a)
    # ---- save, export. The GLB stays in goblin units (no node scale): Godot fits a monster to its mesh
    # bounds (fighter_view), and a scaled skeleton node makes skinned-mesh bounds count the scale twice.
    # The intended size is cfg["scale"] x the goblin and is set in the data (model_height/body_height).
    sc["intended_scale"] = cfg["scale"]
    tex.pack()
    bdir = os.path.join(ROOT, "art_source/monsters", vname); os.makedirs(bdir, exist_ok=True)
    tris = {o.name: sum(len(pl.vertices) - 2 for pl in o.data.polygons) for o in [body] + acc + prop_objs}
    sc["variant"] = name; sc["tris"] = str(tris)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(bdir, vname + ".blend"))
    # export: body + skinned accessories joined into one mesh, props separate
    dups = []
    for o in [body] + acc:
        d = o.copy(); d.data = o.data.copy(); coll.objects.link(d); dups.append(d)
    activate(dups[0], *dups[1:]); bpy.ops.object.join(); joined = dups[0]; joined.name = vname + "_mesh"; joined.data.name = vname
    for m in [m for m in joined.modifiers if m.type == 'ARMATURE'][1:]: joined.modifiers.remove(m)
    odir = os.path.join(ROOT, "art/monsters", vname); os.makedirs(odir, exist_ok=True)
    embed = EMBED_CLIPS and not os.path.exists(os.path.join(ROOT, "art/animations", vname + ".glb"))
    if embed:   # stand-in: the approved goblin clips ride inside the model until art/animations/<variant>.glb lands
        sc.render.fps = 30   # the clips' own rate (goblin_anims.py), so every clip keeps its exact length
        before = set(bpy.data.objects); bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "art/animations/goblin.glb"))
        for o in set(bpy.data.objects) - before: bpy.data.objects.remove(o, do_unlink=True)
        rig.animation_data_create()
        for act in [a_ for a_ in bpy.data.actions]:
            act.use_fake_user = True
            tr = rig.animation_data.nla_tracks.new(); tr.name = act.name
            st = tr.strips.new(act.name, int(act.frame_range[0]), act)
            if getattr(act, "slots", None) and len(act.slots): st.action_slot = act.slots[0]
        with open(os.path.join(ROOT, "art/animations/goblin.json"), "r", encoding="utf-8") as f: marks = f.read()
        with open(os.path.join(odir, vname + ".json"), "w", encoding="utf-8", newline="") as f: f.write(marks)
    bpy.context.view_layer.update()
    keep = [rig, joined] + prop_objs
    for o in bpy.data.objects:
        if o.name in bpy.context.view_layer.objects: o.select_set(o in keep)
    bpy.ops.export_scene.gltf(filepath=os.path.join(odir, vname + ".glb"), export_format='GLB', use_selection=True,
                              export_animations=embed, export_animation_mode='NLA_TRACKS', export_skins=True, export_def_bones=False,
                              export_image_format='JPEG', export_jpeg_quality=90, export_apply=False)
    total = sum(tris.values()); bb = None
    zs = [(joined.matrix_world @ v.co).z for v in joined.data.vertices]
    print("VARIANT %s tris %d (%s) px/m %.0f scale %.2f mesh top (goblin units) %.3f extra %s glb %d KB tex %d KB" % (
        vname, total, tris, D, cfg["scale"], max(zs), [e["name"] for e in extras],
        os.path.getsize(os.path.join(odir, vname + ".glb")) // 1024, os.path.getsize(tpath) // 1024))

def export_arrow(path):
    """The in-flight arrow: 0.5 m, pointing along glTF/Godot +Z (Blender -Y), origin at its middle,
    three flat materials (no texture) so the projectile costs almost nothing."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    def m(name, c, rough=0.8, metal=0.0):
        mt = bpy.data.materials.new(name); mt.use_nodes = True; b = mt.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*[x ** 2.2 for x in c], 1); b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal; return mt
    mats = [m("arrow_shaft", (0.66, 0.50, 0.30)), m("arrow_head", (0.55, 0.55, 0.58), 0.5, 0.6), m("arrow_fletch", (0.86, 0.20, 0.14)), m("arrow_fletch_tip", (0.95, 0.93, 0.86))]
    bm = bmesh.new()
    def ring(y, r, n, rot=0.0): return [bm.verts.new((r * math.cos(rot + 2 * math.pi * k / n), y, r * math.sin(rot + 2 * math.pi * k / n))) for k in range(n)]
    def bridge(a, b, mi):
        for k in range(len(a)):
            f = bm.faces.new((a[k], a[(k + 1) % len(a)], b[(k + 1) % len(b)], b[k])); f.material_index = mi
    def cap(rr, p, mi, flip=False):
        c = bm.verts.new(p)
        for k in range(len(rr)):
            f = bm.faces.new((rr[(k + 1) % len(rr)], rr[k], c) if not flip else (rr[k], rr[(k + 1) % len(rr)], c)); f.material_index = mi
    # Blender -Y is forward (Godot +Z): the head at y = -0.25, the nock at y = +0.25
    tail = ring(0.25, 0.0065, 6); nock = ring(0.235, 0.0065, 6); front = ring(-0.19, 0.0055, 6)
    cap(tail, (0, 0.255, 0), 0, flip=True); bridge(tail, nock, 0); bridge(nock, front, 0)
    h0 = ring(-0.19, 0.009, 4, math.pi / 4); h1 = ring(-0.205, 0.016, 4, math.pi / 4)
    bridge(front, front, 0) if False else None
    cap(front, (0, -0.19, 0), 1, flip=False); bridge(h0, h1, 1); cap(h1, (0, -0.25, 0), 1); cap(h0, (0, -0.18, 0), 1, flip=True)
    for k in range(3):
        a = 2 * math.pi * k / 3; d = Vector((math.cos(a), 0, math.sin(a)))
        for side in (1, -1):
            vs = [bm.verts.new(v) for v in (Vector((0, 0.235, 0)) + d * 0.006, Vector((0, 0.16, 0)) + d * 0.006,
                                             Vector((0, 0.17, 0)) + d * 0.024, Vector((0, 0.235, 0)) + d * 0.02)]
            f = bm.faces.new(vs if side > 0 else list(reversed(vs))); f.material_index = 2
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f.material_index != 2])
    me = bpy.data.meshes.new("arrow"); bm.to_mesh(me); bm.free()
    for mt in mats: me.materials.append(mt)
    ob = bpy.data.objects.new("arrow", me); bpy.context.scene.collection.objects.link(ob)
    for pl in me.polygons: pl.use_smooth = False
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_animations=False)
    print("ARROW", path, len(me.polygons), "faces", os.path.getsize(path), "bytes")

ensure_cache()
for v in VARIANTS:
    build_variant(v)
    if v == "archer": export_arrow(os.path.join(ROOT, "art/monsters/goblin_archer/arrow.glb"))

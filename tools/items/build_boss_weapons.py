"""Boss unique weapons (Boss 2026-11-21): the Mummy Pyramid wave-9 boss pair's own weapons as player items.

  boss_mummy_boss_crook         the Pharaoh mini boss's golden crook  -> a greatsword  art/weapons/race_boss/mummy_crook.glb
  boss_mummy_high_wizard_staff  the High Wizard's scarab staff        -> a magic staff art/weapons/race_boss/mummy_staff.glb

Rebuild after the Boss rejected the first crook (a flat untextured gold plate lifted from the monster, no handle) and asked
for ROUND handles (no hex/octagon profiles): both weapons are now built here with numpy, no Blender.

Crook (fully procedural, about the length of the level-15 greatsword, the right fist at the same grip):
  rounded pommel ball with a lapis gem cap -> gold collar -> a two-hand leather grip (round, 12 sides, slight taper, a spiral
  wrap painted in the atlas and a faint wrap ripple in the geometry, one gold band between the hands) -> rounded torus-like
  gold guard collar with a lapis scarab on both faces -> a round tapered shaft in pharaoh nemes stripes (gold, lapis, white)
  -> gold collar -> the crook hook (round, tapering to a rounded tip, striped) with a crescent gold blade on its outer rim
  (thick at the root, a pale sharpened edge). The hook curls in the player blade's plane (the swing plane).
Staff: the High Wizard's own head (snake crook, orb, gold collars; its triangles and the wizard's albedo JPEG kept) on a new
  round shaft: rounded gold foot cap with a gem, round 12-sided shaft, a leather-wrapped grip with gold collars at the fist
  and a gold collar hiding the cut under the head.

Every round piece is a lathe/sweep with 12 radial segments and smooth normals. One shared 128 px PNG atlas
(art/weapons/race_boss/boss_weapons_atlas.png, written here): leather spiral wrap, nemes stripes, gold with a lit/dark ramp,
lapis, turquoise, and a gold-to-pale blade edge ramp.

Files: the player's RightHand frame of the level-15 race weapon (art/weapons/race_human/<class>_lv15.glb: the same 102-joint
Studio rig, inverse bind matrices copied byte for byte), every vertex 100% on RightHand, node names "Weapon_Boss | Sword" /
"| Staff" (the labels the client reads). The folder race_boss makes the client treat the file as a Studio-rig weapon.
Checks after writing: rig identical, only RightHand weighted, triangles <= the budget, length and grip printed.
Run: python -I tools/items/build_boss_weapons.py            (from the repo root)
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "characters"))
sys.path.insert(0, os.path.join(ROOT, "tools", "items"))
import split_studio05_hair as glb  # noqa: E402
import split_race_weapons_lv15 as lv15  # noqa: E402

OUT = os.path.join(ROOT, "art", "weapons", "race_boss")
ATLAS = "boss_weapons_atlas.png"
ATLAS_PX = 128
HAND = "RightHand"
SIDES = 12  # radial segments of every round piece (Boss: round, no hex/octagon)
BUDGET = {"mummy_crook": 1200, "mummy_staff": 900}
GREATSWORD = "art/weapons/race_human/greatsword_lv15.glb"
MAGIC = "art/weapons/race_human/magic_lv15.glb"
WIZARD = "art/monsters/mummy_high_wizard/mummy_high_wizard.glb"
WIZARD_IMAGE = "../../monsters/mummy_high_wizard/mummy_high_wizard_bandage_albedo.jpg"

# atlas regions (x0, y0, x1, y1) in pixels; u runs across x, v across y
R_LEATHER = (0, 0, 32, 128)
R_STRIPE = (32, 0, 64, 128)
R_GOLD = (64, 0, 96, 128)
R_LAPIS = (96, 0, 112, 64)
R_TURQ = (112, 0, 128, 64)
R_EDGE = (96, 64, 128, 128)

GOLD_HI, GOLD, GOLD_LO = (255, 226, 132), (226, 168, 52), (150, 92, 24)
LAPIS, LAPIS_HI = (30, 52, 150), (70, 110, 210)
TURQ, TURQ_HI = (20, 140, 140), (110, 220, 200)
CREAM = (240, 230, 200)
LEATHER, LEATHER_HI, LEATHER_LO = (122, 62, 40), (168, 96, 58), (66, 30, 20)


# ---------------------------------------------------------------------------------------------------------------- atlas
def _lerp(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def make_atlas(path):
    rng = np.random.default_rng(7)
    img = np.zeros((ATLAS_PX, ATLAS_PX, 3), dtype=np.float64)
    # leather: a spiral wrap; band = frac(u + WRAPS * v): dark groove at the band edges, lit middle, a stitched cloth fleck
    x0, y0, x1, y1 = R_LEATHER
    for y in range(y0, y1):
        for x in range(x0, x1):
            u = (x - x0 + 0.5) / (x1 - x0)
            v = (y - y0 + 0.5) / (y1 - y0)
            band = (u + 10.0 * v) % 1.0
            shade = np.sin(band * np.pi) ** 0.6
            c = np.array(_lerp(LEATHER_LO, LEATHER, min(1.0, shade * 1.6))) if shade < 0.6 else np.array(_lerp(LEATHER, LEATHER_HI, (shade - 0.6) / 0.4))
            img[y, x] = c
    # nemes stripes along v: gold, lapis, gold, thin white, ... (pharaoh headdress bands)
    x0, y0, x1, y1 = R_STRIPE
    pattern = [(GOLD, 14), (LAPIS, 7), (CREAM, 3), (LAPIS, 7)]
    seq = []
    while len(seq) < (y1 - y0):
        for col, n in pattern:
            seq += [col] * n
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = np.array(seq[y - y0], dtype=np.float64)
            k = (y - y0) % 22
            if seq[y - y0] in (GOLD,):
                c = np.array(_lerp(GOLD_HI, GOLD, abs(((y - y0) % 31) - 7) / 7.5))
            img[y, x] = c
    # gold ramp along v: lo -> mid -> hi -> mid -> lo (a ring's profile maps across it: lit crown, dark edges)
    x0, y0, x1, y1 = R_GOLD
    for y in range(y0, y1):
        v = (y - y0 + 0.5) / (y1 - y0)
        s = np.sin(v * np.pi)
        c = _lerp(GOLD_LO, GOLD, min(1.0, s * 1.5)) if s < 0.66 else _lerp(GOLD, GOLD_HI, (s - 0.66) / 0.34)
        img[y, x0:x1] = c
    for region, base, hi in ((R_LAPIS, LAPIS, LAPIS_HI), (R_TURQ, TURQ, TURQ_HI)):
        x0, y0, x1, y1 = region
        for y in range(y0, y1):
            v = (y - y0 + 0.5) / (y1 - y0)
            img[y, x0:x1] = _lerp(base, hi, max(0.0, np.sin(v * np.pi)) ** 2)
    # blade edge ramp along u: gold root -> lit gold -> pale sharpened edge
    x0, y0, x1, y1 = R_EDGE
    for x in range(x0, x1):
        u = (x - x0 + 0.5) / (x1 - x0)
        c = _lerp(GOLD_LO, GOLD, u / 0.45) if u < 0.45 else (_lerp(GOLD, GOLD_HI, (u - 0.45) / 0.4) if u < 0.85 else _lerp(GOLD_HI, (255, 246, 214), (u - 0.85) / 0.15))
        img[y0:y1, x] = c
    # painterly grain: a soft low-frequency noise over everything (+-6%), then blur a touch inside each region
    noise = rng.normal(0.0, 1.0, (ATLAS_PX // 8, ATLAS_PX // 8))
    noise = np.kron(noise, np.ones((8, 8)))
    noise = np.asarray(Image.fromarray(((noise + 3) * 40).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4)), dtype=np.float64) / 40 - 3
    img = img * (1.0 + 0.05 * noise[..., None])
    for y in range(ATLAS_PX):  # fine fleck in the lapis (gold pyrite specks)
        for x in range(R_LAPIS[0], R_LAPIS[2]):
            if y < R_LAPIS[3] and rng.random() < 0.035:
                img[y, x] = GOLD_HI
    Image.fromarray(img.clip(0, 255).astype(np.uint8), "RGB").save(path, optimize=True)


def region_uv(region, u, v):
    """Atlas UV for (u, v) in 0..1 inside a region, inset 1.5 px from its edges (mipmap bleed)."""
    x0, y0, x1, y1 = region
    pad = 1.5
    x = x0 + pad + np.asarray(u) * (x1 - x0 - 2 * pad)
    y = y0 + pad + np.asarray(v) * (y1 - y0 - 2 * pad)
    return np.stack([x / ATLAS_PX, y / ATLAS_PX], -1)


# ---------------------------------------------------------------------------------------------------------------- geometry
class Mesh:
    def __init__(self):
        self.pos, self.nrm, self.uv, self.tris = [], [], [], []
        self.count = 0

    def add(self, pos, nrm, uv, tris):
        self.pos.append(np.asarray(pos, dtype=np.float64))
        self.nrm.append(np.asarray(nrm, dtype=np.float64))
        self.uv.append(np.asarray(uv, dtype=np.float64))
        self.tris.append(np.asarray(tris, dtype=np.int64) + self.count)
        self.count += len(pos)

    def arrays(self):
        nrm = np.concatenate(self.nrm)
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
        return np.concatenate(self.pos), nrm, np.concatenate(self.uv), np.concatenate(self.tris)


def grid_normals(P, closed_u=True):
    """Smooth normals of a (rings, SIDES+1) vertex grid (the last column repeats the first): area-weighted face normals,
    seam columns averaged; pole rings (zero radius) take the pole direction."""
    n_r, n_c = P.shape[:2]
    acc = np.zeros_like(P)
    for i in range(n_r - 1):
        for j in range(n_c - 1):
            a, b, c, d = P[i, j], P[i, j + 1], P[i + 1, j + 1], P[i + 1, j]
            n1 = np.cross(b - a, c - a)
            n2 = np.cross(c - a, d - a)
            for (r, s), n in (((i, j), n1 + n2), ((i, j + 1), n1), ((i + 1, j + 1), n1 + n2), ((i + 1, j), n2)):
                acc[r, s] += n
    if closed_u:
        seam = acc[:, 0] + acc[:, -1]
        acc[:, 0] = acc[:, -1] = seam
    return acc


def sweep(mesh, centres, frames, radii, region, v, flatten=None, outward=None):
    """A round tube: rings of SIDES around `centres` (N, 3) in the plane of frames (N, 2, 3) (two unit vectors), radius
    radii (N,), atlas `region` with u around and v (N,) along. A radius 0 closes the end (a rounded cap when the profile
    is a quarter circle). flatten (N,) optional: the second frame axis scaled (an oval section)."""
    n = len(centres)
    ang = np.linspace(0.0, 2.0 * np.pi, SIDES + 1)
    ang[-1] = 0.0
    cos, sin = np.cos(ang), np.sin(ang)
    fl = np.ones(n) if flatten is None else np.asarray(flatten)
    P = (centres[:, None, :] + radii[:, None, None] * (cos[None, :, None] * frames[:, 0][:, None, :]
                                                       + fl[:, None, None] * sin[None, :, None] * frames[:, 1][:, None, :]))
    N = grid_normals(P)
    for i in range(n):  # poles: the axis direction (out of the tube end)
        if radii[i] < 1e-7:
            other = centres[1] if i == 0 else centres[-2]
            d = centres[i] - other
            N[i, :] = d / np.linalg.norm(d)
    u = np.linspace(0.0, 1.0, SIDES + 1)
    UV = region_uv(region, np.broadcast_to(u[None, :], (n, SIDES + 1)), np.broadcast_to(np.asarray(v)[:, None], (n, SIDES + 1)))
    tris = []
    for i in range(n - 1):
        for j in range(SIDES):
            a, b = i * (SIDES + 1) + j, i * (SIDES + 1) + j + 1
            c, d = (i + 1) * (SIDES + 1) + j + 1, (i + 1) * (SIDES + 1) + j
            if radii[i] >= 1e-7:
                tris.append((a, c, b))
            if radii[i + 1] >= 1e-7:
                tris.append((a, d, c))
    if outward is None:  # wind the triangles outward (the normals know which way out is)
        Pf = P.reshape(-1, 3)
        Nf = N.reshape(-1, 3)
        t0 = np.array(tris)
        fn = np.cross(Pf[t0[:, 1]] - Pf[t0[:, 0]], Pf[t0[:, 2]] - Pf[t0[:, 0]])
        if float((fn * Nf[t0].sum(1)).sum()) < 0:
            tris = [(a, c, b) for a, b, c in tris]
    mesh.add(P.reshape(-1, 3), N.reshape(-1, 3), UV.reshape(-1, 2), tris)


def lathe(mesh, axis, side, origin, profile):
    """A straight lathe along unit `axis` from `origin`: profile = list of (t, radius, region, v) rows; consecutive rows with
    the same region share a ring, a region change starts a new ring at the same t (a clean colour edge)."""
    side = side - axis * (side @ axis)
    side /= np.linalg.norm(side)
    other = np.cross(axis, side)
    groups, cur = [], []
    for row in profile:
        if cur and row[2] != cur[-1][2]:
            groups.append(cur)
            cur = [(cur[-1][0], cur[-1][1], row[2], row[3])] if cur[-1][1] > 1e-7 else []
        cur.append(row)
    groups.append(cur)
    for g in groups:
        if len(g) < 2:
            continue
        t = np.array([r[0] for r in g])
        rad = np.array([r[1] for r in g])
        v = np.array([r[3] for r in g])
        centres = origin + np.outer(t, axis)
        frames = np.broadcast_to(np.stack([side, other])[None], (len(g), 2, 3))
        sweep(mesh, centres, frames, rad, g[0][2], v)


def ball(t0, r, n, region, v0=0.0, v1=1.0, bottom=True):
    """Profile rows for a quarter/half sphere ending at a pole (a rounded pommel or cap), t increasing."""
    rows = []
    for k in range(n + 1):
        a = (k / n) * (np.pi / 2)
        if bottom:  # pole at t0 - r, widening up to the equator at t0
            rows.append((t0 - r * np.cos(a), r * np.sin(a), region, v0 + (v1 - v0) * k / n))
        else:  # equator at t0 closing to the pole at t0 + r
            rows.append((t0 + r * np.sin(a), r * np.cos(a), region, v0 + (v1 - v0) * k / n))
    return rows


def torus_ring(t0, r_in, r_out, region, n=4):
    """A rounded collar ring (half-round bulge from r_in up to r_out and back), as lathe rows; the gold ramp's lit crown on top."""
    h = r_out - r_in
    rows = []
    for k in range(n + 1):
        a = np.pi * k / n
        rows.append((t0 - h * np.cos(a), r_in + h * np.sin(a), region, k / n))
    return rows


def ellipsoid(mesh, centre, axes, radii, region, rings=5):
    """A small smooth ellipsoid (a gem / scarab): axes (3, 3) unit, radii (3,), poles along axes[2]."""
    centres, frames, rad, flat, v = [], [], [], [], []
    for k in range(rings + 1):
        a = np.pi * k / rings
        centres.append(centre + axes[2] * (-radii[2] * np.cos(a)))
        frames.append(np.stack([axes[0], axes[1]]))
        rad.append(radii[0] * np.sin(a))
        flat.append(radii[1] / radii[0])
        v.append(k / rings)
    rad = np.array(rad)
    rad[0] = rad[-1] = 0.0
    sweep(mesh, np.array(centres), np.array(frames), rad, region, np.array(v), flatten=np.array(flat))


# ---------------------------------------------------------------------------------------------------------------- frames
def acc(js, binary, index):
    a = js["accessors"][index]
    dtype = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    return np.frombuffer(glb.accessor_bytes(js, binary, index), dtype=dtype).reshape(-1, n)


def joint_index(js, name):
    for k, j in enumerate(js["skins"][0]["joints"]):
        if js["nodes"][j]["name"].replace("mixamorig:", "").replace("mixamorig_", "") == name:
            return k
    raise KeyError(name)


def inverse_bind(js, binary, name):
    m = acc(js, binary, js["skins"][0]["inverseBindMatrices"]).reshape(-1, 4, 4)
    return m[joint_index(js, name)].T.astype(np.float64)  # glTF matrices are column-major


def apply(m, points):
    return points @ m[:3, :3].T + m[:3, 3]


def frame(points, hand=np.zeros(3), wide_head=False):
    """Main axis (pointing to the head: the far end from the hand, or with `wide_head` the end with the wider cross-section),
    length, and the hand's grip fraction from the low (butt) end."""
    centre = points.mean(0)
    axis = np.linalg.eigh(np.cov((points - centre).T))[1][:, 2]
    t = (points - centre) @ axis
    g = float((hand - centre) @ axis)
    if wide_head:
        span = t.max() - t.min()
        radial = np.linalg.norm((points - centre) - np.outer(t, axis), axis=1)
        flip = radial[t < t.min() + 0.2 * span].mean() > radial[t > t.max() - 0.2 * span].mean()
    else:
        flip = t.max() - g < g - t.min()
    if flip:
        axis, t, g = -axis, -t, -g
    length = float(t.max() - t.min())
    return axis, length, (g - float(t.min())) / length


def player_frame(path):
    js, binary = glb.read_glb(os.path.join(ROOT, path))
    name = list(glb.meshed(js))[0]
    pos, _, _ = lv15.mesh_arrays(js, binary, name)
    return js, binary, apply(inverse_bind(js, binary, HAND), pos)


def blade_plane(points, axis):
    """The player's blade width direction (perpendicular to the axis) and the centre of its handle near the fist."""
    c = points.mean(0)
    flat = (points - c) - np.outer((points - c) @ axis, axis)
    w = np.linalg.eigh(np.cov(flat.T))[1][:, 2]
    w = w - axis * (w @ axis)
    w /= np.linalg.norm(w)
    t = points @ axis
    near = points[np.abs(t) < 0.03]
    return w, (near - np.outer(near @ axis, axis)).mean(0)


# ---------------------------------------------------------------------------------------------------------------- crook
def build_crook():
    """The crook in the player's RightHand frame (hand at the origin): positions, normals, uvs, triangles."""
    _, _, player = player_frame(GREATSWORD)
    ax, p_len, _ = frame(player)
    w, c0 = blade_plane(player, ax)
    z = np.cross(ax, w)
    m = Mesh()
    G, L, S = R_GOLD, R_LEATHER, R_STRIPE
    # the straight part along the axis, t = 0 at the fist; the player blade spans t -0.137 .. 0.709
    prof = []
    prof += [(t, r, R_LAPIS, v) for t, r, _, v in ball(-0.150, 0.019, 1, None, 0.0, 0.5)]   # lapis gem cap (pole at the butt)
    prof += [(t, r, G, v) for t, r, _, v in ball(-0.134, 0.033, 3, None, 0.15, 0.85)][1:]  # gold pommel ball, lower half
    prof += [(-0.110, 0.024, G, 1.0)]                             # pommel neck
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(-0.100, 0.023, 0.029, G, 3)]       # collar under the grip
    grip = np.linspace(-0.090, 0.024, 5)
    for k, t in enumerate(grip):                                                          # leather wrap, faint wrap ripple
        r = 0.0225 - 0.0015 * (t - grip[0]) / (grip[-1] - grip[0]) + (0.0008 if k % 2 else 0.0)
        prof.append((t, r, L, (t - grip[0]) / (grip[-1] - grip[0])))
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(0.034, 0.021, 0.029, G, 3)]         # guard collar: three rounded rings
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(0.052, 0.025, 0.037, G, 3)][1:]
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(0.070, 0.021, 0.028, G, 3)][1:]
    shaft = np.linspace(0.078, 0.470, 3)
    for t in shaft:                                                                       # nemes-striped shaft, tapered
        f = (t - shaft[0]) / (shaft[-1] - shaft[0])
        prof.append((t, 0.0200 - 0.0030 * f, S, 0.05 + 0.9 * f))
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(0.480, 0.0168, 0.0245, G, 3)]
    prof += [(0.492, 0.017, G, 0.5), (0.500, 0.0, G, 0.5)]                                # closes inside the hook root
    lathe(m, ax, w, c0, prof)
    # the guard's scarabs: a lapis/turquoise oval on each face (+-z, the faces seen side-on to the swing plane)
    for s in (1.0, -1.0):
        ellipsoid(m, c0 + ax * 0.052 + z * s * 0.0315, np.stack([ax, w, z * s]), np.array([0.019, 0.014, 0.0075]), R_TURQ, rings=3)
    # the hook: from inside the top collar up the axis, then a curl toward +w (in the swing plane) back down, tapering
    R = 0.092
    centre = c0 + ax * 0.555 + w * R
    pts, tans, rad, v = [], [], [], []
    for k, t in enumerate(np.linspace(0.486, 0.555, 2)):
        pts.append(c0 + ax * t)
        tans.append(ax)
        rad.append(0.0168)
    arc = np.radians(np.linspace(0.0, 215.0, 9))[1:]
    for k, a in enumerate(arc):
        pts.append(centre + R * (np.sin(a) * ax - np.cos(a) * w))
        tans.append(np.cos(a) * ax + np.sin(a) * w)
        f = a / arc[-1]
        rad.append(0.0168 - 0.0080 * f ** 1.3)
    tip_dir, end, r_end = tans[-1], pts[-1], rad[-1]
    for a in np.radians((50.0, 90.0)):  # rounded tip: a quarter-circle cap
        pts.append(end + tip_dir * r_end * np.sin(a))
        tans.append(tip_dir)
        rad.append(r_end * np.cos(a) if a < np.pi / 2 - 1e-6 else 0.0)
    pts, tans, rad = np.array(pts), np.array(tans), np.array(rad)
    frames = np.stack([np.cross(z, tans), np.broadcast_to(z, tans.shape)], 1)
    frames[:, 0] /= np.linalg.norm(frames[:, 0], axis=1, keepdims=True)
    seg = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
    sweep(m, pts, frames, rad, S, 0.02 + 0.96 * seg / seg[-1])
    # the crescent blade on the hook's outer rim: rows root (inside the tube) -> bevel -> edge, both faces (+-z)
    a = np.radians(np.linspace(18.0, 178.0, 11))
    width = 0.052 * np.sin((a - a[0]) / (a[-1] - a[0]) * np.pi) ** 0.8
    rows = [(0.0, 0.0085, 0.05), (0.55, 0.0058, 0.55), (1.0, 0.0008, 0.97)]  # (fraction of the width, half thickness, u)
    radial = np.sin(a)[:, None] * ax - np.cos(a)[:, None] * w                  # out from the curl centre
    for s in (1.0, -1.0):
        P, N, UV = [], [], []
        for i in range(len(a)):
            for frac, half, u in rows:
                tube_r = 0.0168 - 0.0080 * (a[i] / np.radians(215.0)) ** 1.3
                d = R + tube_r * 0.4 + frac * width[i]
                P.append(centre + radial[i] * d + z * s * (half if width[i] > 1e-6 else 0.0006))
                UV.append(region_uv(R_EDGE, u, i / (len(a) - 1)))
        P = np.array(P).reshape(len(a), 3, 3)
        Nf = grid_normals(P, closed_u=False).reshape(-1, 3)
        Nf = np.where(((Nf @ (z * s)) < 0)[:, None], -Nf, Nf)  # each face's normals point out of its side
        Nf = Nf + z * s * 0.6  # bias toward the face normal: the bevel reads as one lit face, not a crease
        tris = []
        for i in range(len(a) - 1):
            for j in range(2):
                q = [i * 3 + j, i * 3 + j + 1, (i + 1) * 3 + j + 1, (i + 1) * 3 + j]
                tris += [(q[0], q[1], q[2]), (q[0], q[2], q[3])]
        Pf = P.reshape(-1, 3)
        t0 = np.array(tris)
        fn = np.cross(Pf[t0[:, 1]] - Pf[t0[:, 0]], Pf[t0[:, 2]] - Pf[t0[:, 0]])
        if float((fn @ (z * s)).sum()) < 0:
            tris = [(x, zz, y) for x, y, zz in tris]
        m.add(Pf, Nf, np.array(UV), tris)
    return m.arrays(), p_len


# ---------------------------------------------------------------------------------------------------------------- staff
def staff_head():
    """The High Wizard's staff head (snake crook, orb, gold collars) in the player's RightHand frame, as the first build
    placed it: RightHand-weighted islands of the wizard body minus the fist, turned onto the player's level-15 staff axis,
    scaled to 1.6x its length, the fist at 30% from the foot. Returns (pos, nrm, uv, tris, axis, shaft centre offset)."""
    js, binary = glb.read_glb(os.path.join(ROOT, WIZARD))
    node = [n for n in js["nodes"] if n.get("name") == "Monster_MummyHighWizard_Body"][0]
    prim = js["meshes"][node["mesh"]]["primitives"][0]
    at = prim["attributes"]
    pos = acc(js, binary, at["POSITION"]).astype(np.float64)
    nrm = acc(js, binary, at["NORMAL"]).astype(np.float64)
    uv = acc(js, binary, at["TEXCOORD_0"]).astype(np.float64)
    tris = acc(js, binary, prim["indices"]).reshape(-1, 3).astype(np.int64)
    hand = inverse_bind(js, binary, HAND)
    joints = acc(js, binary, at["JOINTS_0"]).astype(int)
    weights = acc(js, binary, at["WEIGHTS_0"])
    names = [js["nodes"][j]["name"] for j in js["skins"][0]["joints"]]
    on = joints[np.arange(len(joints)), weights.argmax(1)] == names.index("mixamorig_RightHand")
    comp = _islands(tris, pos)
    local = apply(hand, pos)
    held = [c for c in np.unique(comp) if on[comp == c].mean() >= 0.99]
    fist = min(held, key=lambda c: float(np.linalg.norm(local[comp == c].mean(0))))
    held.remove(fist)
    tris = tris[np.isin(comp[tris[:, 0]], held)]
    used = np.unique(tris)
    remap = -np.ones(len(pos), dtype=np.int64)
    remap[used] = np.arange(len(used))
    pos, nrm, uv, tris = local[used], nrm[used] @ np.linalg.inv(hand[:3, :3]), uv[used], remap[tris]
    _, _, player = player_frame(MAGIC)
    p_axis, p_len, _ = frame(player)
    s_axis, s_len, _ = frame(pos, wide_head=True)
    rot = _turn(s_axis, p_axis)
    pts = (pos @ rot.T) * (p_len * 1.6 / s_len)
    nrm = nrm @ rot.T
    t = pts @ p_axis
    pts = pts - p_axis * (float(t.min()) + 0.30 * (float(t.max()) - float(t.min())))
    t = pts @ p_axis
    shaft = (t > -0.06) & (t < 0.15)
    off = (pts[shaft] - np.outer(pts[shaft] @ p_axis, p_axis)).mean(0)
    keep = pts[tris].mean(1) @ p_axis > CUT
    tris = tris[keep]
    used = np.unique(tris)
    remap = -np.ones(len(pts), dtype=np.int64)
    remap[used] = np.arange(len(used))
    nrm = nrm / np.linalg.norm(nrm, axis=1, keepdims=True)
    return pts[used], nrm[used], uv[used], remap[tris], p_axis, off, float(t.min())


CUT = 0.185  # staff: the source triangles above this (along the axis from the fist) are the head


def build_staff():
    head_pos, head_nrm, head_uv, head_tris, ax, off, foot = staff_head()
    side = np.cross(ax, np.array([0.0, 0.0, 1.0]))
    m = Mesh()
    G, L = R_GOLD, R_LEATHER
    prof = []
    prof += [(t, r, R_LAPIS, v) for t, r, _, v in ball(foot - 0.002, 0.012, 2, None, 0.0, 0.5)]  # gem at the foot
    prof += [(t, r, G, v) for t, r, _, v in ball(foot + 0.010, 0.017, 2, None, 0.15, 0.85)][1:]  # rounded gold foot cap
    prof += [(foot + 0.022, 0.0145, G, 1.0)]
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(foot + 0.030, 0.0125, 0.0165, G, 2)][1:]
    low = np.linspace(foot + 0.038, -0.072, 2)
    prof += [(t, 0.0118 + 0.0006 * k, R_STRIPE, 0.1 + 0.3 * k) for k, t in enumerate(low)]         # lower shaft (nemes)
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(-0.066, 0.0125, 0.0175, G, 3)]              # collar under the fist
    grip = np.linspace(-0.058, 0.060, 4)
    for k, t in enumerate(grip):
        prof.append((t, 0.0138 + (0.0005 if k % 2 else 0.0), L, (t - grip[0]) / (grip[-1] - grip[0])))
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(0.068, 0.0125, 0.0175, G, 3)]               # collar over the fist
    up = np.linspace(0.076, CUT - 0.004, 2)
    prof += [(t, 0.0128 - 0.0004 * k, R_STRIPE, 0.5 + 0.2 * k) for k, t in enumerate(up)]
    prof += [(t, r, G, v) for t, r, _, v in torus_ring(CUT + 0.004, 0.012, 0.0195, G, 3)]          # hides the cut
    prof += [(CUT + 0.016, 0.0, G, 0.5)]
    lathe(m, ax, side, off, prof)
    return m.arrays(), (head_pos, head_nrm, head_uv, head_tris)


# ---------------------------------------------------------------------------------------------------------------- helpers
def _islands(tris, positions):
    parent = list(range(len(positions)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b, c in tris:
        parent[find(a)] = find(b)
        parent[find(b)] = find(c)
    seen = {}
    for i, p in enumerate(np.round(positions, 5)):
        key = tuple(p)
        if key in seen:
            parent[find(i)] = find(seen[key])
        else:
            seen[key] = i
    return np.array([find(i) for i in range(len(positions))])


def _turn(a, b):
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k * (1.0 / (1.0 + c))


def write(wid, player_path, label, surfaces, source_note):
    """surfaces: list of (pos, nrm, uv, tris, material, image uri) in the RightHand frame; one mesh, one primitive each."""
    tjs, tbin = glb.read_glb(os.path.join(ROOT, player_path))
    to_mesh = np.linalg.inv(inverse_bind(tjs, tbin, HAND))
    assert np.linalg.det(to_mesh[:3, :3]) > 0
    out_js = {k: json.loads(json.dumps(v)) for k, v in tjs.items() if k in ("asset", "scene", "scenes", "nodes", "skins")}
    chunks = []

    def add(array, ctype, kind, target=None, minmax=False):
        data = np.ascontiguousarray(array).tobytes()
        offset = sum(len(c) for c in chunks)
        pad = -offset % 4
        chunks.append(b"\0" * pad)
        offset += pad
        chunks.append(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            view["target"] = target
        out_js.setdefault("bufferViews", []).append(view)
        a = {"bufferView": len(out_js["bufferViews"]) - 1, "componentType": ctype, "count": len(array), "type": kind}
        if minmax:
            a["min"] = [float(x) for x in np.min(array, 0)]
            a["max"] = [float(x) for x in np.max(array, 0)]
        out_js.setdefault("accessors", []).append(a)
        return len(out_js["accessors"]) - 1

    out_js["skins"][0]["inverseBindMatrices"] = add(acc(tjs, tbin, tjs["skins"][0]["inverseBindMatrices"]).astype("<f4"), 5126, "MAT4")
    k = joint_index(tjs, HAND)
    prims, materials, images = [], [], []
    n_tris = 0
    for pos, nrm, uv, tris, material, uri in surfaces:
        mesh_pos = apply(to_mesh, pos)
        mesh_nrm = nrm @ to_mesh[:3, :3].T
        mesh_nrm /= np.linalg.norm(mesh_nrm, axis=1, keepdims=True)
        joints = np.zeros((len(pos), 4), dtype="u1")
        joints[:, 0] = k
        weights = np.zeros((len(pos), 4), dtype="<f4")
        weights[:, 0] = 1.0
        if uri not in images:
            images.append(uri)
        material = json.loads(json.dumps(material))
        material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": images.index(uri)}
        materials.append(material)
        prims.append({"attributes": {
            "POSITION": add(mesh_pos.astype("<f4"), 5126, "VEC3", 34962, True),
            "NORMAL": add(mesh_nrm.astype("<f4"), 5126, "VEC3", 34962),
            "TEXCOORD_0": add(uv.astype("<f4"), 5126, "VEC2", 34962),
            "JOINTS_0": add(joints, 5121, "VEC4", 34962),
            "WEIGHTS_0": add(weights, 5126, "VEC4", 34962),
        }, "indices": add(np.asarray(tris).reshape(-1).astype("<u2"), 5123, "SCALAR", 34963), "material": len(materials) - 1})
        n_tris += len(tris)
    out_js["meshes"] = [{"name": wid, "primitives": prims}]
    out_js["materials"] = materials
    out_js["images"] = [{"name": os.path.splitext(os.path.basename(u))[0], "uri": u,
                         "mimeType": "image/png" if u.endswith(".png") else "image/jpeg"} for u in images]
    out_js["samplers"] = [{"magFilter": 9729, "minFilter": 9987}]
    out_js["textures"] = [{"sampler": 0, "source": i} for i in range(len(images))]
    for node in out_js["nodes"]:
        if "mesh" in node:
            node["name"] = label
            node["mesh"] = 0
    out_js["extras"] = {"zorx_source": source_note + " (tools/items/build_boss_weapons.py)"}
    binary = b"".join(chunks)
    out_js["buffers"] = [{"byteLength": len(binary)}]
    path = os.path.join(OUT, wid + ".glb")
    glb.write_glb(path, out_js, binary)
    njs, nbin = glb.read_glb(path)
    assert glb.rig_hash(njs, nbin) == glb.rig_hash(tjs, tbin), "rig differs from the player's weapon file"
    assert lv15.bound_joints(njs, nbin, label) == {HAND}
    assert n_tris <= BUDGET[wid], "%s: %d triangles" % (wid, n_tris)
    _, _, player = player_frame(player_path)
    p_axis, p_len, p_grip = frame(player)
    check = apply(inverse_bind(njs, nbin, HAND), lv15.mesh_arrays(njs, nbin, label)[0])
    t = check @ p_axis
    f_len = float(t.max() - t.min())
    print("%-12s %4d tris %6d bytes  length %.3f = %.2f x the player weapon  grip %.2f (player %.2f)"
          % (wid, n_tris, os.path.getsize(path), f_len, f_len / p_len, -float(t.min()) / f_len, p_grip))
    return n_tris


def main():
    os.makedirs(OUT, exist_ok=True)
    make_atlas(os.path.join(OUT, ATLAS))
    print("atlas %s %d bytes" % (ATLAS, os.path.getsize(os.path.join(OUT, ATLAS))))
    mat = {"name": "Boss Crook | Pharaoh Atlas", "doubleSided": True, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.6}}
    (pos, nrm, uv, tris), _ = build_crook()
    write("mummy_crook", GREATSWORD, "Weapon_Boss | Sword", [(pos, nrm, uv, tris, mat, ATLAS)], "procedural pharaoh crook")
    (spos, snrm, suv, stris), (hpos, hnrm, huv, htris) = build_staff()
    shaft_mat = {"name": "Boss Staff | Pharaoh Atlas", "doubleSided": True, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.6}}
    head_mat = {"name": "Boss Staff | Wizard Atlas", "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.8}}
    write("mummy_staff", MAGIC, "Weapon_Boss | Staff", [(hpos, hnrm, huv, htris, head_mat, WIZARD_IMAGE), (spos, snrm, suv, stris, shaft_mat, ATLAS)],
          "%s head + procedural round shaft" % WIZARD)


if __name__ == "__main__":
    main()

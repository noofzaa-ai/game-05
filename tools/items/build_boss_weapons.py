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


def player_frame(path, hand=HAND):
    js, binary = glb.read_glb(os.path.join(ROOT, path))
    name = list(glb.meshed(js))[0]
    pos, _, _ = lv15.mesh_arrays(js, binary, name)
    return js, binary, apply(inverse_bind(js, binary, hand), pos)


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
ORIGINAL_CROOK = "art/monsters/mummy_boss/mummy_boss.glb"
CROOK_GOLD = {"name": "Boss Crook | Gold", "pbrMetallicRoughness": {
    "baseColorFactor": [0.570481538772583, 0.2632734179496765, 0.02198094315826893, 1.0], "metallicFactor": 0.45, "roughnessFactor": 0.45}}
# The original crook exactly as the first build placed it in the player's RightHand frame (commit be242d6b, lifted from the
# monster's "Monster_MummyBoss_Khopesh"): a flat plate. Its outline in (w, axis) coordinates of the level-15 greatsword
# frame (w = the blade's width direction, axis = the blade direction), z from -0.036 to 0.020. The hook (with its root) and
# the guard crossbar keep this outline; only the flat bar under the hook becomes a round handle on the bar's centre line.
HOOK = [(0.0808, 0.3729), (0.0942, 0.4154), (0.0991, 0.4602), (0.0951, 0.5056), (0.0823, 0.5498), (0.0608, 0.5912),
        (0.0314, 0.6279), (-0.0049, 0.6585), (-0.047, 0.6817), (-0.0932, 0.6964), (-0.1419, 0.7019), (-0.0924, 0.7014),
        (-0.0435, 0.6912), (0.0248, 0.7071), (0.092, 0.6936), (0.1534, 0.6588), (0.2012, 0.6051), (0.2279, 0.538),
        (0.2283, 0.4659), (0.1995, 0.3993), (0.1282, 0.3557)]
GUARD = [(-0.0165, 0.2025), (-0.0051, 0.2341), (0.1055, 0.1942), (0.0941, 0.1625)]
BAR_BOTTOM, BAR_TOP = np.array([-0.0584, -0.0861]), np.array([0.1045, 0.3643])  # the flat bar's centre line
Z_MID, Z_HALF = -0.008, 0.028
THICKEN = 1.25  # Boss: "a little" thicker than the original plate, same outline


def _area(poly):
    x, y = poly[:, 0], poly[:, 1]
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


def _ear_clip(poly):
    """Triangles of a simple counter-clockwise polygon, as index triples."""
    def cross(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    idx = list(range(len(poly)))
    out = []
    while len(idx) > 3:
        for k in range(len(idx)):
            i, j, l = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i], poly[j], poly[l]
            if cross(a, b, c) <= 1e-12:
                continue
            if any(cross(a, b, poly[m]) >= 0 and cross(b, c, poly[m]) >= 0 and cross(c, a, poly[m]) >= 0
                   for m in idx if m not in (i, j, l)):
                continue
            out.append((i, j, l))
            idx.pop(k)
            break
        else:
            raise ValueError("ear clipping failed")
    out.append(tuple(idx))
    return out


def _inset(poly, d):
    """Each vertex of a counter-clockwise polygon moved inward by about d (miter, clamped at sharp corners)."""
    out = []
    n = len(poly)
    for i in range(n):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % n]
        e0 = (p1 - p0) / np.linalg.norm(p1 - p0)
        e1 = (p2 - p1) / np.linalg.norm(p2 - p1)
        n0, n1 = np.array([-e0[1], e0[0]]), np.array([-e1[1], e1[0]])  # left = inward
        m = n0 + n1
        m = n0 if np.linalg.norm(m) < 1e-6 else m / np.linalg.norm(m)
        out.append(p1 + m * min(d / max(float(m @ n0), 1e-3), 1.5 * d))
    return np.array(out)


def _slab(mesh, poly2, to3, ez, zc, half, bevel):
    """A bevelled extrusion of a 2D outline: flat caps at zc +- half (inset by `bevel`), and a rounded edge band (the outline
    itself at the middle, smooth normals blending from the cap to the side) so the plate reads as a thick piece of gold."""
    poly2 = np.asarray(poly2, dtype=np.float64)
    if _area(poly2) < 0:
        poly2 = poly2[::-1]
    n = len(poly2)
    tri = _ear_clip(poly2)
    inner = _inset(poly2, bevel)
    side = []
    for i in range(n):
        e0 = poly2[i] - poly2[i - 1]
        e1 = poly2[(i + 1) % n] - poly2[i]
        v = np.array([e0[1], -e0[0]]) / np.linalg.norm(e0) + np.array([e1[1], -e1[0]]) / np.linalg.norm(e1)
        side.append(to3(v / max(np.linalg.norm(v), 1e-9), 0.0) - to3(np.zeros(2), 0.0))
    for s in (1.0, -1.0):
        P = np.array([to3(p, zc + s * half) for p in inner])
        mesh.add(P, np.broadcast_to(ez * s, P.shape).copy(), np.zeros((n, 2)), [(a, b, c) if s > 0 else (a, c, b) for a, b, c in tri])
    rows = [(inner, zc + half, 0.8), (poly2, zc + half * 0.35, 0.3), (poly2, zc - half * 0.35, -0.3), (inner, zc - half, -0.8)]
    P, N = [], []
    for ring, zz, nz in rows:
        for i in range(n):
            P.append(to3(ring[i], zz))
            v = side[i] * (1.0 - abs(nz)) + ez * nz
            N.append(v / np.linalg.norm(v))
    T = []
    for r in range(3):
        for i in range(n):
            a, b = r * n + i, r * n + (i + 1) % n
            c, d = (r + 1) * n + (i + 1) % n, (r + 1) * n + i
            T += [(a, d, c), (a, c, b)]
    P, N = np.array(P), np.array(N)
    t0 = np.array(T)
    fn = np.cross(P[t0[:, 1]] - P[t0[:, 0]], P[t0[:, 2]] - P[t0[:, 0]])
    if float((fn * N[t0].sum(1)).sum()) < 0:
        T = [(a, c, b) for a, b, c in T]
    mesh.add(P, N, np.zeros((len(P), 2)), T)


def _lathe_split(gold, atlas, axis, side, origin, profile):
    """lathe(): gold rows go to the untextured gold mesh, the other rows (gem, leather) to the atlas mesh."""
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
        frames = np.broadcast_to(np.stack([side, other])[None], (len(g), 2, 3))
        sweep(gold if g[0][2] == R_GOLD else atlas, origin + np.outer(t, axis), frames, np.array([r[1] for r in g]), g[0][2],
              np.array([r[3] for r in g]))


def build_crook():
    """The crook in the player's RightHand frame (fist at the origin): (gold arrays, atlas arrays). Gold, the original
    material: the original hook and guard outlines thickened a little, the round shaft, pommel ball and collar rings.
    Atlas: the leather spiral-wrapped two-hand grip and the lapis gem capping the pommel."""
    _, _, player = player_frame(GREATSWORD)
    ax, _, _ = frame(player)
    w, _ = blade_plane(player, ax)
    z = np.cross(ax, w)

    def to3(p, zz):
        return w * p[0] + ax * p[1] + z * zz
    gold, atlas = Mesh(), Mesh()
    half = Z_HALF * THICKEN
    _slab(gold, HOOK, to3, z, Z_MID, half, 0.007)
    _slab(gold, GUARD, to3, z, Z_MID, half * 0.85, 0.006)
    d2 = (BAR_TOP - BAR_BOTTOM) / np.linalg.norm(BAR_TOP - BAR_BOTTOM)
    axis = w * d2[0] + ax * d2[1]
    origin = to3(BAR_BOTTOM, Z_MID)  # s = 0 at the old bar's bottom; the fist sits at s ~ 0.09
    G = R_GOLD
    rows = [(t, r, R_LAPIS, v) for t, r, _, v in ball(-0.064, 0.013, 2, None, 0.0, 0.5)]   # lapis gem cap
    rows += [(t, r, G, v) for t, r, _, v in ball(-0.042, 0.029, 3, None, 0.15, 0.85)][1:]   # round gold pommel ball
    rows += [(-0.031, 0.026, G, 0.9), (-0.024, 0.019, G, 1.0)]                              # its upper half, the neck
    rows += [(t, r, G, v) for t, r, _, v in torus_ring(-0.016, 0.0195, 0.0255, G, 3)][1:]  # gold collar ring
    grip = np.linspace(-0.008, 0.170, 6)
    rows += [(t, 0.0215 - 0.0014 * k / 5 + (0.0008 if k % 2 else 0.0), R_LEATHER, k / 5) for k, t in enumerate(grip)]
    rows += [(t, r, G, v) for t, r, _, v in torus_ring(0.178, 0.019, 0.025, G, 3)]          # gold collar ring
    rows += [(0.186, 0.0185, G, 0.5), (0.330, 0.0175, G, 0.5), (0.440, 0.0165, G, 0.5)]  # round gold shaft
    rows += [(t, r, G, v) for t, r, _, v in torus_ring(0.452, 0.0165, 0.0225, G, 3)][1:]   # small collar at the hook root
    rows += [(0.475, 0.0165, G, 0.5), (0.492, 0.0, G, 0.5)]                                # ends inside the hook
    _lathe_split(gold, atlas, axis, z, origin, rows)
    return gold.arrays(), atlas.arrays()


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


def write(wid, player_path, label, surfaces, source_note, hand=HAND, budget=None, script="tools/items/build_boss_weapons.py"):
    """surfaces: list of (pos, nrm, uv, tris, material, image uri) in the `hand` joint frame (RightHand by default; the Orc
    Warlock shield uses LeftForeArm like the race shields); one mesh, one primitive each."""
    tjs, tbin = glb.read_glb(os.path.join(ROOT, player_path))
    to_mesh = np.linalg.inv(inverse_bind(tjs, tbin, hand))
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
    k = joint_index(tjs, hand)
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
        material = json.loads(json.dumps(material))
        if uri is not None:  # None: an untextured surface (the crook's original flat gold)
            if uri not in images:
                images.append(uri)
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
    out_js["extras"] = {"zorx_source": source_note + " (%s)" % script}
    binary = b"".join(chunks)
    out_js["buffers"] = [{"byteLength": len(binary)}]
    path = os.path.join(OUT, wid + ".glb")
    glb.write_glb(path, out_js, binary)
    njs, nbin = glb.read_glb(path)
    assert glb.rig_hash(njs, nbin) == glb.rig_hash(tjs, tbin), "rig differs from the player's weapon file"
    assert lv15.bound_joints(njs, nbin, label) == {hand}
    assert n_tris <= (BUDGET[wid] if budget is None else budget), "%s: %d triangles" % (wid, n_tris)
    _, _, player = player_frame(player_path, hand)
    p_axis, p_len, p_grip = frame(player)
    check = apply(inverse_bind(njs, nbin, hand), lv15.mesh_arrays(njs, nbin, label)[0])
    t = check @ p_axis
    f_len = float(t.max() - t.min())
    print("%-12s %4d tris %6d bytes  length %.3f = %.2f x the player weapon  grip %.2f (player %.2f)"
          % (wid, n_tris, os.path.getsize(path), f_len, f_len / p_len, -float(t.min()) / f_len, p_grip))
    return n_tris


def main():
    os.makedirs(OUT, exist_ok=True)
    make_atlas(os.path.join(OUT, ATLAS))
    print("atlas %s %d bytes" % (ATLAS, os.path.getsize(os.path.join(OUT, ATLAS))))
    grip_mat = {"name": "Boss Crook | Grip Atlas", "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.6}}
    gold, grip = build_crook()
    write("mummy_crook", GREATSWORD, "Weapon_Boss | Sword", [(*gold, CROOK_GOLD, None), (*grip, grip_mat, ATLAS)],
          "%s Monster_MummyBoss_Khopesh outline (hook, guard) + round handle" % ORIGINAL_CROOK)
    (spos, snrm, suv, stris), (hpos, hnrm, huv, htris) = build_staff()
    shaft_mat = {"name": "Boss Staff | Pharaoh Atlas", "doubleSided": True, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.6}}
    head_mat = {"name": "Boss Staff | Wizard Atlas", "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.8}}
    write("mummy_staff", MAGIC, "Weapon_Boss | Staff", [(hpos, hnrm, huv, htris, head_mat, WIZARD_IMAGE), (spos, snrm, suv, stris, shaft_mat, ATLAS)],
          "%s head + procedural round shaft" % WIZARD)


if __name__ == "__main__":
    main()

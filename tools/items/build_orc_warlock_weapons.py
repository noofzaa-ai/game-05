"""Orc Warlock boss weapons (Boss 2026-11-21), PLACEHOLDER 3D until the real models arrive:

  boss_orc_warlock_sword   -> art/weapons/race_boss/orc_warlock_sword.glb   (Sword & Shield one-hand sword, weapon_type blade)
  boss_orc_warlock_shield  -> art/weapons/race_boss/orc_warlock_shield.glb  (off-hand shield)

The shapes are the Warlock monster's own mockup pieces (art/monsters/orc_warlock/orc_warlock.glb meshes
Monster_OrcWarlock_MOCKUP_Sword / _Shield; the monster model is NOT changed), their outlines measured in the monster's
RightHand / LeftForeArm joint frames and rebuilt on the player rig:
  sword  = the mockup blade + crossguard outline (bevelled slabs, scaled 0.55 so it is about as long as the player's
           level-15 sword, blade 1.25x wider), dark iron with an ember rune strip; the mockup's box grip becomes a ROUND
           leather-wrapped grip (12 sides) with iron collars and a round bone pommel capped by an ember gem.
  shield = the mockup kite board outline (0.68x along the forearm, 0.9x across: a little larger than the race shield), brown wood with a dark iron rim, two iron
           bands, a round iron boss, two ivory tusks and an ember rune on the face.
Frames: the sword in the player's RightHand frame of art/weapons/race_human/sword_shield_lv15.glb (handle on that sword's
axis and blade plane, the fist at the same place); the shield in the LeftForeArm frame of
art/weapons/race_human/shield_lv15.glb (the race shields are LeftForeArm-bound: face toward +x of the bone, board just off
the forearm, centred where the race shield is). Same 102-joint Studio rig, inverse bind matrices copied byte for byte, every
vertex 100% on one joint. Writer and helpers: tools/items/build_boss_weapons.py.

SWAP when the real 3D arrives: replace the two GLBs (same paths and node labels "Weapon_Boss | Sword" / "| Shield", same
rig, bound to RightHand / LeftForeArm) or point catalog.json asset_path at the new files: data only, no code.
Run: python -I tools/items/build_orc_warlock_weapons.py            (from the repo root)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_boss_weapons as B  # noqa: E402

SWORD_REF = "art/weapons/race_human/sword_shield_lv15.glb"
SHIELD_REF = "art/weapons/race_human/shield_lv15.glb"
BUDGET = {"orc_warlock_sword": 700, "orc_warlock_shield": 900}

# Mockup outlines, read from Monster_OrcWarlock_MOCKUP_* in the monster's joint frames (see the module comment).
# Sword: (width, along the blade) about the monster's fist; the blade centre line is at width 0.010.
MOCK_BLADE = [(-0.016, 0.093), (0.036, 0.093), (0.033, 0.420), (0.010, 0.466), (-0.013, 0.420)]
MOCK_GUARD = [(-0.065, 0.075), (0.085, 0.075), (0.085, 0.093), (-0.065, 0.093)]
SWORD_SCALE, BLADE_WIDEN = 0.55, 1.25
# Shield board: (along the forearm, across) in the LeftForeArm frame; apex toward the hand.
MOCK_BOARD = [(0.198, 0.011), (0.106, 0.079), (-0.022, 0.114), (-0.169, 0.107), (-0.165, -0.119), (-0.017, -0.112), (0.110, -0.066)]
BOARD_ALONG, BOARD_ACROSS = 0.68, 0.9
BOARD_CENTRE_Y = 0.075  # the race shield's centre along the forearm
BOARD_X, BOARD_HALF = 0.030, 0.0075  # board mid plane (in front of the forearm) and half thickness


def mat(name, rgb, metal=0.0, rough=0.7, emissive=None):
    m = {"name": name, "pbrMetallicRoughness": {"baseColorFactor": [rgb[0], rgb[1], rgb[2], 1.0], "metallicFactor": metal, "roughnessFactor": rough}}
    if emissive:
        m["emissiveFactor"] = list(emissive)
    return m


IRON = mat("Orc Warlock | Iron", (0.085, 0.085, 0.095), 0.5, 0.5)
IRON_DARK = mat("Orc Warlock | Iron Rim", (0.05, 0.048, 0.052), 0.5, 0.55)
WOOD = mat("Orc Warlock | Wood", (0.20, 0.095, 0.038), 0.0, 0.85)
BONE = mat("Orc Warlock | Bone", (0.72, 0.62, 0.44), 0.0, 0.6)
EMBER = mat("Orc Warlock | Ember", (1.0, 0.30, 0.03), 0.0, 0.4, (1.0, 0.35, 0.05))
LEATHER = {"name": "Orc Warlock | Grip Atlas", "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.7}}


def lathe_parts(meshes, axis, side, origin, profile):
    """A straight lathe whose rows carry a part key (rows: (t, radius, key)); each run of one key goes to meshes[key]
    (a new ring at the key change keeps a clean colour edge). Leather rows map onto the shared atlas' leather wrap."""
    side = side - axis * (side @ axis)
    side /= np.linalg.norm(side)
    other = np.cross(axis, side)
    groups, cur = [], []
    for row in profile:
        if cur and row[2] != cur[-1][2]:
            groups.append(cur)
            cur = [(cur[-1][0], cur[-1][1], row[2])] if cur[-1][1] > 1e-7 else []
        cur.append(row)
    groups.append(cur)
    for g in groups:
        if len(g) < 2:
            continue
        t = np.array([r[0] for r in g])
        v = (t - t.min()) / max(float(t.max() - t.min()), 1e-6)
        frames = np.broadcast_to(np.stack([side, other])[None], (len(g), 2, 3))
        B.sweep(meshes[g[0][2]], origin + np.outer(t, axis), frames, np.array([r[1] for r in g]), B.R_LEATHER if g[0][2] == "leather" else B.R_GOLD, v)


def build_sword():
    _, _, player = B.player_frame(SWORD_REF)
    ax, _, _ = B.frame(player)
    w, off = B.blade_plane(player, ax)
    z = np.cross(ax, w)

    def to3(p, zz):
        return off + w * p[0] + ax * p[1] + z * zz

    def fit(poly, widen=1.0):
        return [((x - 0.010) * SWORD_SCALE * widen, t * SWORD_SCALE) for x, t in poly]
    m = {k: B.Mesh() for k in ("iron", "dark", "ember", "bone", "leather")}
    blade = fit(MOCK_BLADE, BLADE_WIDEN)
    guard = fit(MOCK_GUARD)
    B._slab(m["iron"], blade, to3, z, 0.0, 0.0045, 0.003)
    B._slab(m["dark"], guard, to3, z, 0.0, 0.0085, 0.004)
    t0, t1 = guard[2][1] + 0.016, blade[2][1] - 0.03  # the ember rune strip along the blade's middle (shows on both faces)
    B._slab(m["ember"], [(-0.003, t0), (0.003, t0), (0.0022, t1), (0.0, t1 + 0.006), (-0.0022, t1)], to3, z, 0.0, 0.0052, 0.0008)
    g0 = guard[0][1]  # bottom of the guard
    rows = [(t, r, "ember") for t, r, _, _ in B.ball(-0.034, 0.0065, 2, None)]               # ember gem cap
    rows += [(t, r, "bone") for t, r, _, _ in B.ball(-0.022, 0.0135, 3, None)][1:]           # round bone pommel
    rows += [(-0.0135, 0.0115, "bone"), (-0.0095, 0.0085, "bone")]
    rows += [(t, r, "dark") for t, r, _, _ in B.torus_ring(-0.0075, 0.0095, 0.0125, None, 3)][1:]  # iron collar
    grip = np.linspace(-0.004, g0 - 0.005, 5)
    rows += [(t, 0.0102 + (0.0006 if k % 2 else 0.0), "leather") for k, t in enumerate(grip)]  # round leather grip
    rows += [(t, r, "dark") for t, r, _, _ in B.torus_ring(g0 - 0.002, 0.0095, 0.0125, None, 3)]   # collar under the guard
    rows += [(g0 + 0.004, 0.0085, "dark"), (g0 + 0.008, 0.0, "dark")]
    lathe_parts(m, ax, w, off, rows)
    out = [(*m["iron"].arrays(), IRON, None), (*m["dark"].arrays(), IRON_DARK, None), (*m["ember"].arrays(), EMBER, None),
           (*m["bone"].arrays(), BONE, None), (*m["leather"].arrays(), LEATHER, B.ATLAS)]
    return out


def build_shield():
    ex = np.array([1.0, 0.0, 0.0])  # face normal (front = +x of LeftForeArm, as the race shields)
    ey = np.array([0.0, 1.0, 0.0])  # along the forearm (toward the hand)
    ez = np.array([0.0, 0.0, 1.0])
    centre_mock = np.mean([p[0] for p in MOCK_BOARD])
    across_mock = np.mean([p[1] for p in MOCK_BOARD])

    def to3(p, xx):
        return ex * xx + ey * p[0] + ez * p[1]
    board = [((y - centre_mock) * BOARD_ALONG + BOARD_CENTRE_Y, (s - across_mock) * BOARD_ACROSS) for y, s in MOCK_BOARD]
    c2 = np.array(board).mean(0)
    rim = [tuple(c2 + (np.array(p) - c2) * 1.07) for p in board]
    m = {k: B.Mesh() for k in ("wood", "iron", "dark", "bone", "ember")}
    B._slab(m["wood"], board, to3, ex, BOARD_X, BOARD_HALF, 0.004)
    B._slab(m["dark"], rim, to3, ex, BOARD_X - 0.002, BOARD_HALF * 0.75, 0.006)  # iron rim: a larger, thinner plate behind
    face = BOARD_X + BOARD_HALF
    # two iron bands across the board (clipped to its width at their height by a simple inset)
    for yb in (c2[0] + 0.075, c2[0] - 0.07):
        half_w = _width_at(board, yb) - 0.006
        B._slab(m["dark"], [(yb - 0.009, -half_w), (yb + 0.009, -half_w), (yb + 0.009, half_w), (yb - 0.009, half_w)], to3, ex, face, 0.0022, 0.002)
    # ember rune (a small chevron) under the boss
    yr = c2[0] - 0.045
    B._slab(m["ember"], [(yr - 0.012, 0.0), (yr + 0.010, -0.016), (yr + 0.016, -0.012), (yr + 0.002, 0.0), (yr + 0.016, 0.012), (yr + 0.010, 0.016)],
            to3, ex, face + 0.0006, 0.0012, 0.0006)
    # round iron boss: a dome on the face
    centre = to3(c2, face)
    rows = [(0.0, 0.034, "iron"), (0.005, 0.032, "iron"), (0.011, 0.026, "iron"), (0.016, 0.016, "iron"), (0.0185, 0.007, "iron"), (0.019, 0.0, "iron")]
    lathe_parts(m, ex, ez, centre - ex * 0.001, rows)
    # two ivory tusks curling out of the boss sides (tapered sweeps)
    for s in (1.0, -1.0):
        n = 6
        k = np.linspace(0.0, 1.0, n)
        base = centre + ez * s * 0.026 + ex * 0.008
        pts = np.array([base + ez * s * (0.028 * kk) + ex * (0.016 * kk) + ey * (0.026 * kk * kk) for kk in k])
        tang = np.gradient(pts, axis=0)
        tang /= np.linalg.norm(tang, axis=1, keepdims=True)
        frames = []
        for tg in tang:
            a = np.cross(tg, ey)
            a /= np.linalg.norm(a)
            frames.append(np.stack([a, np.cross(tg, a)]))
        radii = 0.0075 * (1.0 - k) ** 0.8
        radii[-1] = 0.0
        B.sweep(m["bone"], pts, np.array(frames), radii, B.R_GOLD, k)
    return [(*m["wood"].arrays(), WOOD, None), (*m["dark"].arrays(), IRON_DARK, None), (*m["iron"].arrays(), IRON, None),
            (*m["bone"].arrays(), BONE, None), (*m["ember"].arrays(), EMBER, None)]


def _width_at(poly, y):
    """Half width (across) of a polygon symmetric-ish about 0 at height y (along): the smallest |across| of its edge
    crossings, so a band stays inside the board."""
    hits = []
    n = len(poly)
    for i in range(n):
        (y0, s0), (y1, s1) = poly[i], poly[(i + 1) % n]
        if (y0 - y) * (y1 - y) <= 0 and y0 != y1:
            hits.append(abs(s0 + (s1 - s0) * (y - y0) / (y1 - y0)))
    return min(hits) if hits else 0.05


def main():
    script = "tools/items/build_orc_warlock_weapons.py"
    src = "art/monsters/orc_warlock/orc_warlock.glb"
    B.write("orc_warlock_sword", SWORD_REF, "Weapon_Boss | Sword", build_sword(),
            "%s Monster_OrcWarlock_MOCKUP_Sword outline + round grip (PLACEHOLDER)" % src, budget=BUDGET["orc_warlock_sword"], script=script)
    B.write("orc_warlock_shield", SHIELD_REF, "Weapon_Boss | Shield", build_shield(),
            "%s Monster_OrcWarlock_MOCKUP_Shield outline (PLACEHOLDER)" % src, hand="LeftForeArm", budget=BUDGET["orc_warlock_shield"], script=script)


if __name__ == "__main__":
    main()

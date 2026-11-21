"""Orc Warlock boss weapons, the Boss's REAL models (warlock-ss.fbx, 2026-11-21; replaces the placeholder of be499d67):

  boss_orc_warlock_sword   -> art/weapons/race_boss/orc_warlock_sword.glb  (+ orc_warlock_sword.jpg)   Sword & Shield one-hand sword
  boss_orc_warlock_shield  -> art/weapons/race_boss/orc_warlock_shield.glb (+ orc_warlock_shield.jpg)  off-hand shield

Input: tools/items/prep_orc_warlock_weapons_fbx.py output in build/warlock_ss (kept out of git): the source parts decimated
(sword_hi 760, shield_hi 1300 triangles for the player; sword_lo / shield_lo for the monster), canonical frames (sword: grip
centre at the origin, blade +Y, blade width X; shield: board centre at the origin, top +Y, face +Z), and the base colour
re-baked into one compact UV per weapon (purple repainted brown like the monster; 256 px shipped as JPEG).
Placement (the player's joint frames, as the placeholder had): the sword on the player's level-15 Sword & Shield sword axis
and blade plane (art/weapons/race_human/sword_shield_lv15.glb RightHand frame), the fist round the source's own ROUND leather
grip, the guard where the player's guard is, overall length about the player's sword; the shield on LeftForeArm like the race
shields (art/weapons/race_human/shield_lv15.glb: face toward +x of the bone, kite point toward the hand, centred where the race
shield is), a little larger. Same 102-joint Studio rig, inverse bind matrices copied byte for byte, every vertex 100% on one
joint (tools/items/build_boss_weapons.py write()).
Also writes the MONSTER pieces (lo meshes, the request sheet's proportions: sword x1.05, shield x1.15 of the player's) to
build/warlock_ss/monster_sword.glb / monster_shield.glb, read by tools/monsters/build_mummy_family.gd (gear real_sword / real_shield).
Run: python -I tools/items/build_orc_warlock_weapons.py            (from the repo root, after the prep step)
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_boss_weapons as B  # noqa: E402

SWORD_REF = "art/weapons/race_human/sword_shield_lv15.glb"
SHIELD_REF = "art/weapons/race_human/shield_lv15.glb"
PREP = os.path.join(B.ROOT, "build", "warlock_ss")
BUDGET = {"orc_warlock_sword": 1500, "orc_warlock_shield": 1500}
SWORD_SCALE = 0.33   # source metres -> the player's RightHand frame (the whole sword 0.89 m -> 0.29, the player's is 0.28)
SHIELD_SCALE = 0.32  # board 0.89 x 0.61 m -> 0.28 along the forearm, 0.20 across (the placeholder: 0.25 x 0.21)
SHIELD_CENTRE = np.array([0.030, 0.075, 0.0])  # the race shield's centre (face plane just off the forearm)
MONSTER = {"sword": 1.05, "shield": 1.15}  # the request sheet: the monster's sword x1.05, shield x1.15 of the player's


def material(name):
    return {"name": name, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.8}}


def load(name):
    js, binary = B.glb.read_glb(os.path.join(PREP, name + ".glb"))
    prim = js["meshes"][0]["primitives"][0]
    at = prim["attributes"]
    pos = B.acc(js, binary, at["POSITION"]).astype(np.float64)
    nrm = B.acc(js, binary, at["NORMAL"]).astype(np.float64)
    uv = B.acc(js, binary, at["TEXCOORD_0"]).astype(np.float64)
    tris = B.acc(js, binary, prim["indices"]).reshape(-1, 3).astype(np.int64)
    return pos, nrm, uv, tris


def sword_basis():
    """Canonical sword axes (X width, Y blade, Z flat normal) as columns in the player's RightHand frame, and the handle offset."""
    _, _, player = B.player_frame(SWORD_REF)
    ax, _, _ = B.frame(player)
    w, off = B.blade_plane(player, ax)
    return np.stack([w, ax, np.cross(w, ax)], 1), off


def shield_basis():
    """Canonical shield axes as columns in LeftForeArm: across -> +z, top -> -y (the elbow; the kite point toward the hand),
    face -> +x (as the race shields)."""
    return np.array([[0.0, 0.0, 1.0], [0.0, -1.0, 0.0], [1.0, 0.0, 0.0]]).T


def place(name, basis, scale, offset):
    pos, nrm, uv, tris = load(name)
    return pos @ basis.T * scale + offset, nrm @ basis.T, uv, tris


def main():
    script = "tools/items/build_orc_warlock_weapons.py"
    src = "Boss FBX warlock-ss.fbx (2026-11-21)"
    sb, soff = sword_basis()
    hb = shield_basis()
    assert np.linalg.det(sb) > 0 and np.linalg.det(hb) > 0
    for key in ("sword", "shield"):
        Image.open(os.path.join(PREP, key + "_256.png")).convert("RGB").save(os.path.join(B.OUT, "orc_warlock_%s.jpg" % key), quality=85, optimize=True)
    sword = place("sword_hi", sb, SWORD_SCALE, soff)
    shield = place("shield_hi", hb, SHIELD_SCALE, SHIELD_CENTRE)
    B.write("orc_warlock_sword", SWORD_REF, "Weapon_Boss | Sword", [(*sword, material("Orc Warlock | Sword"), "orc_warlock_sword.jpg")],
            "%s sword parts, decimated + re-baked" % src, budget=BUDGET["orc_warlock_sword"], script=script)
    B.write("orc_warlock_shield", SHIELD_REF, "Weapon_Boss | Shield", [(*shield, material("Orc Warlock | Shield"), "orc_warlock_shield.jpg")],
            "%s shield parts, decimated + re-baked" % src, hand="LeftForeArm", budget=BUDGET["orc_warlock_shield"], script=script)
    # the monster's pieces (lo meshes) on the same rig, next to the prep output for build_mummy_family.gd
    out = B.OUT
    B.OUT = PREP
    try:
        m_sword = place("sword_lo", sb, SWORD_SCALE * MONSTER["sword"], soff)
        m_shield = place("shield_lo", hb, SHIELD_SCALE * MONSTER["shield"], SHIELD_CENTRE + np.array([0.004, 0.0, 0.0]))
        B.write("monster_sword", SWORD_REF, "Monster | Sword", [(*m_sword, material("sword"), "sword_256.png")], "monster piece", budget=400, script=script)
        B.write("monster_shield", SHIELD_REF, "Monster | Shield", [(*m_shield, material("shield"), "shield_256.png")], "monster piece",
                hand="LeftForeArm", budget=400, script=script)
    finally:
        B.OUT = out


if __name__ == "__main__":
    main()

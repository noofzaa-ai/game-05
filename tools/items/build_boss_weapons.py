"""Boss unique weapons (Boss 2026-11-21): the Mummy Pyramid wave-9 boss pair's own weapons as player items.

  boss_mummy_boss_crook         the Pharaoh mini boss's golden crook  -> a greatsword  art/weapons/race_boss/mummy_crook.glb
  boss_mummy_high_wizard_staff  the High Wizard's scarab staff        -> a magic staff art/weapons/race_boss/mummy_staff.glb

Pure glTF surgery, no Blender: the weapon triangles are lifted out of the monster GLBs (art/monsters/mummy_boss: the mesh
"Monster_MummyBoss_Khopesh", the gold crook built by tools/monsters/build_mummy_family.gd; art/monsters/mummy_high_wizard:
the RightHand-weighted islands of the one body mesh, minus the wizard's own fist), taken into the monster's RightHand joint
frame (its inverse bind matrix), turned so the shaft lies along the player's level-15 weapon of the same class (smallest
rotation, the piece keeps its own roll), scaled about the hand to the player's proportions, slid along the shaft so the hand
sits at the player weapon's grip fraction, and written into the player's RightHand frame of the level-15 race weapon file
(art/weapons/race_human/<class>_lv15.glb: the same 102-joint Studio rig, inverse bind matrices copied byte for byte), every
vertex 100% on RightHand. Node names "Weapon_Boss | Sword" / "| Staff" (the labels the client reads, WEAPON_PIECE).
The folder name race_boss makes the client treat the file as a Studio-rig weapon (is_studio_rig_file).

Materials: the crook keeps its flat gold colour (no texture); the staff references the High Wizard's own albedo JPEG
(../../monsters/mummy_high_wizard/mummy_high_wizard_bandage_albedo.jpg, already shipped with the monster: no new bytes).
Checks after writing: rig identical to the Studio body, only RightHand weighted, triangles <= BUDGET, length and grip as asked.
Run: python -I tools/items/build_boss_weapons.py            (from the repo root)
"""
import json
import os
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "characters"))
sys.path.insert(0, os.path.join(ROOT, "tools", "items"))
import split_studio05_hair as glb  # noqa: E402
import split_race_weapons_lv15 as lv15  # noqa: E402

OUT = os.path.join(ROOT, "art", "weapons", "race_boss")
BUDGET = 1500
HAND = "RightHand"
# id -> source, how to pick its triangles, the player weapon it is fitted to, label, length (x the player weapon), grip
# fraction from the low end (None = keep the source's grip), material
WEAPONS = {
    "mummy_crook": {
        "source": "art/monsters/mummy_boss/mummy_boss.glb", "mesh_node": "Monster_MummyBoss_Khopesh",
        "player": "art/weapons/race_human/greatsword_lv15.glb", "label": "Weapon_Boss | Sword",
        "length": 0.95, "grip": None, "roll_to_blade": 1, "thicken": 2.2,
        "material": {"name": "Boss Crook | Gold", "pbrMetallicRoughness": {"baseColorFactor": [0.570481538772583, 0.2632734179496765, 0.02198094315826893, 1.0],
                                                                           "metallicFactor": 0.45, "roughnessFactor": 0.45}},
    },
    "mummy_staff": {
        "source": "art/monsters/mummy_high_wizard/mummy_high_wizard.glb", "mesh_node": "Monster_MummyHighWizard_Body",
        "islands_on": "mixamorig_RightHand", "drop_near_hand": True, "wide_head": True,
        "player": "art/weapons/race_human/magic_lv15.glb", "label": "Weapon_Boss | Staff",
        "length": 1.6, "grip": 0.30,
        "material": {"name": "Boss Staff | Wizard Atlas", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.8}},
        "image": "../../monsters/mummy_high_wizard/mummy_high_wizard_bandage_albedo.jpg",
    },
}


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


def islands(tris, positions):
    """Connected pieces of a triangle list (vertices that share an index or a position are joined)."""
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


def source_part(spec):
    """The weapon's triangles: (positions, normals, uvs, triangles) in the SOURCE's RightHand joint frame."""
    js, binary = glb.read_glb(os.path.join(ROOT, spec["source"]))
    node = [n for n in js["nodes"] if n.get("name") == spec["mesh_node"]][0]
    prim = js["meshes"][node["mesh"]]["primitives"][0]
    at = prim["attributes"]
    pos = acc(js, binary, at["POSITION"]).astype(np.float64)
    nrm = acc(js, binary, at["NORMAL"]).astype(np.float64)
    uv = acc(js, binary, at["TEXCOORD_0"]).astype(np.float64)
    tris = acc(js, binary, prim["indices"]).reshape(-1, 3).astype(np.int64)
    hand = inverse_bind(js, binary, HAND)
    if "islands_on" in spec:
        joints = acc(js, binary, at["JOINTS_0"]).astype(int)
        weights = acc(js, binary, at["WEIGHTS_0"])
        names = [js["nodes"][j]["name"] for j in js["skins"][0]["joints"]]
        on = joints[np.arange(len(joints)), weights.argmax(1)] == names.index(spec["islands_on"])
        comp = islands(tris, pos)
        local = apply(hand, pos)
        held = [c for c in np.unique(comp) if on[comp == c].mean() >= 0.99]
        if spec.get("drop_near_hand"):
            # the wizard's fist: the held island whose centre is nearest the hand joint (the shaft runs through the hand too,
            # but its centre is far along the staff)
            fist = min(held, key=lambda c: float(np.linalg.norm(local[comp == c].mean(0))))
            print("  dropped the fist island (%d triangles)" % int((comp[tris[:, 0]] == fist).sum()))
            held.remove(fist)
        keep = held
        tris = tris[np.isin(comp[tris[:, 0]], keep)]
    used = np.unique(tris)
    remap = -np.ones(len(pos), dtype=np.int64)
    remap[used] = np.arange(len(used))
    pos, nrm, uv, tris = pos[used], nrm[used], uv[used], remap[tris]
    local = apply(hand, pos)
    nrm = nrm @ np.linalg.inv(hand[:3, :3])  # normals: inverse transpose of the linear part
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    return local, nrm, uv, tris


def frame(points, hand=np.zeros(3), wide_head=False):
    """Main axis (pointing to the head: the far end from the hand, or with `wide_head` the end with the wider cross-section,
    for a staff held mid-shaft), length, and the hand's grip fraction from the low (butt) end."""
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


def turn(a, b):
    """Smallest rotation taking unit a onto unit b."""
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k * (1.0 / (1.0 + c))


def player_frame(path):
    js, binary = glb.read_glb(os.path.join(ROOT, path))
    name = list(glb.meshed(js))[0]
    pos, _, _ = lv15.mesh_arrays(js, binary, name)
    return js, binary, apply(inverse_bind(js, binary, HAND), pos)


def build(wid, spec):
    local, nrm, uv, tris = source_part(spec)
    tjs, tbin, player_local = player_frame(spec["player"])
    p_axis, p_len, p_grip = frame(player_local)
    s_axis, s_len, s_grip = frame(local, wide_head=spec.get("wide_head", False))
    rot = turn(s_axis, p_axis)
    if spec.get("roll_to_blade"):
        # the crook is flat: turn it about the shaft so its flat plane is the player's blade plane (the hook curls along the
        # blade's edge direction, i.e. in the swing plane, instead of lying across it); sign = roll_to_blade
        def width(points, axis):
            c = points.mean(0)
            flat = (points - c) - np.outer((points - c) @ axis, axis)
            w = np.linalg.eigh(np.cov(flat.T))[1][:, 2]
            return w - axis * (w @ axis), c
        sw, sc = width(local @ rot.T, p_axis)
        pw, _ = width(player_local, p_axis)
        sw /= np.linalg.norm(sw)
        pw /= np.linalg.norm(pw)
        if float(((local @ rot.T) - sc) @ sw @ np.ones(len(local))) < 0:  # point sw toward the hook (the bulk of the off-axis mass)
            sw = -sw
        pw = pw * float(spec["roll_to_blade"])
        rot = turn(sw, pw) @ rot
    scale = p_len * spec["length"] / s_len
    pts = (local @ rot.T) * scale
    nrm = nrm @ rot.T
    if spec.get("thicken", 1.0) != 1.0:  # thicker across the flat plane (a stretch: normals by the inverse transpose)
        c = pts.mean(0)
        flat = np.cross(p_axis, (pw if spec.get("roll_to_blade") else np.array([0.0, 0.0, 1.0])))
        flat /= np.linalg.norm(flat)
        k = float(spec["thicken"])
        pts = pts + np.outer((pts - c) @ flat, flat) * (k - 1.0)
        nrm = nrm + np.outer(nrm @ flat, flat) * (1.0 / k - 1.0)
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    if spec["grip"] is not None:  # slide along the shaft (about the hand) so the hand sits at the asked grip fraction
        t = pts @ p_axis
        want = float(t.min()) + spec["grip"] * (float(t.max()) - float(t.min()))
        pts = pts - p_axis * want
    # into the player's mesh (bind) space
    to_mesh = np.linalg.inv(inverse_bind(tjs, tbin, HAND))
    mesh_pos = apply(to_mesh, pts)
    mesh_nrm = nrm @ to_mesh[:3, :3].T
    mesh_nrm /= np.linalg.norm(mesh_nrm, axis=1, keepdims=True)
    # glTF winding: a mirror would flip it (it never does here: rotations and a positive scale)
    assert np.linalg.det(to_mesh[:3, :3] @ rot) > 0
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

    ibm = add(acc(tjs, tbin, tjs["skins"][0]["inverseBindMatrices"]).astype("<f4"), 5126, "MAT4")
    out_js["skins"][0]["inverseBindMatrices"] = ibm
    k = joint_index(tjs, HAND)
    joints = np.zeros((len(mesh_pos), 4), dtype="u1")
    joints[:, 0] = k
    weights = np.zeros((len(mesh_pos), 4), dtype="<f4")
    weights[:, 0] = 1.0
    attributes = {
        "POSITION": add(mesh_pos.astype("<f4"), 5126, "VEC3", 34962, True),
        "NORMAL": add(mesh_nrm.astype("<f4"), 5126, "VEC3", 34962),
        "TEXCOORD_0": add(uv.astype("<f4"), 5126, "VEC2", 34962),
        "JOINTS_0": add(joints, 5121, "VEC4", 34962),
        "WEIGHTS_0": add(weights, 5126, "VEC4", 34962),
    }
    indices = add(tris.reshape(-1).astype("<u2"), 5123, "SCALAR", 34963)
    out_js["meshes"] = [{"name": wid, "primitives": [{"attributes": attributes, "indices": indices, "material": 0}]}]
    out_js["materials"] = [spec["material"]]
    if "image" in spec:
        out_js["images"] = [{"name": "albedo", "uri": spec["image"], "mimeType": "image/jpeg"}]
        out_js["samplers"] = [{"magFilter": 9729, "minFilter": 9987}]
        out_js["textures"] = [{"sampler": 0, "source": 0}]
    for node in out_js["nodes"]:
        if "mesh" in node:
            node["name"] = spec["label"]
            node["mesh"] = 0
    out_js["extras"] = {"zorx_source": "%s %s (tools/items/build_boss_weapons.py)" % (spec["source"], spec["mesh_node"])}
    binary = b"".join(chunks)
    out_js["buffers"] = [{"byteLength": len(binary)}]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, wid + ".glb")
    glb.write_glb(path, out_js, binary)
    # checks on the file as written
    njs, nbin = glb.read_glb(path)
    assert glb.rig_hash(njs, nbin) == glb.rig_hash(tjs, tbin), "rig differs from the player's weapon file"
    assert lv15.bound_joints(njs, nbin, spec["label"]) == {HAND}
    n_tris = len(tris)
    assert n_tris <= BUDGET, "%s: %d triangles" % (wid, n_tris)
    check = apply(inverse_bind(njs, nbin, HAND), lv15.mesh_arrays(njs, nbin, spec["label"])[0])
    _, f_len, f_grip = frame(check, wide_head=spec.get("wide_head", False))
    print("%-12s %4d tris %6d bytes  length %.3f = %.2f x the player weapon (source %.3f, scale %.3f)  grip %.2f (player %.2f, source %.2f)  turned %.1f deg"
          % (wid, n_tris, os.path.getsize(path), f_len, f_len / p_len, s_len, scale, f_grip, p_grip, s_grip,
             np.degrees(np.arccos(np.clip(s_axis @ p_axis, -1, 1)))))
    return n_tris


def main():
    for wid, spec in WEAPONS.items():
        build(wid, spec)


if __name__ == "__main__":
    main()

"""Split the Boss's LEVEL 15 race weapons into one GLB per race x weapon piece, in the same layout as the MID-tier files.

Sources (art_source/race_gear/, Boss delivery 2026-11-17, not shipped; same 102-joint Studio rig, no clips, one material per
file except the sword and shield file; embedded JPEG textures, base colour only):
  sword_shield_weapons_lv15.glb   Weapon_Lv15_<Race>_Sword and _Shield (the Human shield has three primitives)
  greatsword_weapons_lv15.glb     Weapon_Lv15_<Race>_Greatsword
  longbow_weapons_lv15.glb        Weapon_Lv15_<Race>_Bow
  magic_weapons_lv15.glb          Weapon_Lv15_<Race>_Staff
Outputs (like tools/items/split_race_outfits.py WEAPON_DELIVERIES, names with _lv15):
  art/weapons/race_<race>/sword_shield_lv15.glb, shield_lv15.glb, greatsword_lv15.glb, longbow_lv15.glb, magic_lv15.glb
  node renamed "Weapon_<Race> | Sword" / "| Shield" / "| Sword" (greatsword) / "| Bow" / "| Staff" (the labels the client reads)
  art/weapons/race_shared/<delivery>_lv15_<n>.jpg  every texture once, referenced externally (only the textures a file uses)
Pure glTF surgery (helpers from tools/characters/split_studio05_hair.py): accessors are copied byte for byte (a documented GRIP
SHIFT below may move the vertices of one file); the script re-reads each output and fails loudly if the rig differs from the
Studio class bodies, if the joints / weights / UVs / indices / material differ from the source, or if the weapon is bound to
other bones than the matching MID-tier file (the weighted joints must be the same: RightHand, LeftHand or LeftForeArm).

SIZE (Boss 2026-11-17): the level-1 weapon a player sees is the MID race weapon (starter-* pieces use the race weapon ids and
the MID files), and the delivered Lv15 weapons are exactly as long as the MID files (ratio 1.00 in every race and piece), so
nothing is scaled; widths and thicknesses stay as the Studio delivered them. `--measure` prints the ratios.

GRIP SHIFT: the weapon must be held at the same place as its MID file. Grip position = where the holding joint (RightHand,
LeftHand, LeftForeArm) projects on the weapon's main axis, as a fraction of the length from the low end (axis direction taken
from the MID file). Where the Lv15 file differs from the MID file by more than 5% of the length (the staff: 0.44 against
0.22), the whole weapon is moved along its main axis, about the hand joint, until the grip fraction equals the MID file's:
GRIP_SHIFT[(race, file)] = the move in units of the weapon length (built by `--measure`, frozen below). Only POSITION (with its
min / max) changes; joints, weights, UVs, indices, material and rig stay byte-identical.
Run: python -I tools/items/split_race_weapons_lv15.py            (from the repo root)
     python -I tools/items/split_race_weapons_lv15.py --measure   (print the ratios and the GRIP_SHIFT table)
"""
import json
import os
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "characters"))
import split_studio05_hair as glb  # noqa: E402

TEXTURES = os.path.join(ROOT, "art", "weapons", "race_shared")
RACES = {"human": "Human", "viking": "Viking", "elf": "Elf", "runeborn": "Runeborn"}
# source file -> (texture prefix, {source mesh kind: (class-gear label kind, output file, mid file, holding joint)})
DELIVERIES = {
    "sword_shield_weapons_lv15.glb": ("ss_weapons_lv15", {"Sword": ("Sword", "sword_shield_lv15.glb", "sword_shield.glb", "RightHand"),
                                                         "Shield": ("Shield", "shield_lv15.glb", "shield.glb", "LeftForeArm")}),
    "greatsword_weapons_lv15.glb": ("greatsword_weapons_lv15", {"Greatsword": ("Sword", "greatsword_lv15.glb", "greatsword.glb", "RightHand")}),
    "longbow_weapons_lv15.glb": ("longbow_weapons_lv15", {"Bow": ("Bow", "longbow_lv15.glb", "longbow.glb", "LeftHand")}),
    "magic_weapons_lv15.glb": ("magic_weapons_lv15", {"Staff": ("Staff", "magic_lv15.glb", "magic.glb", "RightHand")}),
}
GRIP_SHIFT = {
    ('human', 'magic_lv15.glb'): 0.215,
    ('viking', 'magic_lv15.glb'): 0.224,
    ('elf', 'magic_lv15.glb'): 0.222,
    ('runeborn', 'magic_lv15.glb'): 0.215,
}
GRIP_TOLERANCE = 0.05
LENGTH_TOLERANCE = 0.03


def _acc(js, binary, index):
    a = js["accessors"][index]
    dtype = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    return np.frombuffer(glb.accessor_bytes(js, binary, index), dtype=dtype).reshape(-1, n)


def mesh_arrays(js, binary, name):
    node = [n for n in js["nodes"] if n.get("name") == name][0]
    pos, joints, weights = [], [], []
    for prim in js["meshes"][node["mesh"]]["primitives"]:
        at = prim["attributes"]
        pos.append(_acc(js, binary, at["POSITION"]).astype(np.float64))
        joints.append(_acc(js, binary, at["JOINTS_0"]).astype(int))
        weights.append(_acc(js, binary, at["WEIGHTS_0"]).astype(np.float64))
    return np.concatenate(pos), np.concatenate(joints), np.concatenate(weights)


def joint_info(js):
    """The skin's joint names and {joint name: bind-pose world position}."""
    nodes = js["nodes"]
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    cache = {}

    def world(i):
        if i not in cache:
            n = nodes[i]
            x, y, z, w = n.get("rotation", [0, 0, 0, 1])
            rot = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
            m = np.eye(4)
            m[:3, :3] = rot * np.array(n.get("scale", [1, 1, 1]))
            m[:3, 3] = n.get("translation", [0, 0, 0])
            cache[i] = world(parent[i]) @ m if i in parent else m
        return cache[i]

    joints = js["skins"][0]["joints"]
    names = [nodes[j]["name"].replace("mixamorig:", "") for j in joints]
    return names, {nodes[j]["name"].replace("mixamorig:", ""): world(j)[:3, 3] for j in joints}


def bound_joints(js, binary, name):
    """The joints that carry more than 5% of the weight of the mesh, by name."""
    _, joints, weights = mesh_arrays(js, binary, name)
    names, _ = joint_info(js)
    total = weights.sum()
    return {names[k] for k in np.unique(joints) if weights[joints == k].sum() > 0.05 * total}


def shape(js, binary, name, hold, ref_axis=None):
    """Length (along the main axis), width, thickness, the grip point on the axis as a fraction of the length from the low end,
    the distance of the holding joint from the axis, and the axis itself (flipped to point the way of `ref_axis`); all in the
    skeleton's bind units."""
    pos, _, _ = mesh_arrays(js, binary, name)
    _, jpos = joint_info(js)
    centre = pos.mean(0)
    vecs = np.linalg.eigh(np.cov((pos - centre).T))[1]
    axis = vecs[:, 2]
    if ref_axis is not None and float(axis @ ref_axis) < 0:
        axis = -axis
    proj = (pos - centre) @ axis
    length = float(proj.max() - proj.min())
    w = (pos - centre) @ vecs[:, 1]
    t = (pos - centre) @ vecs[:, 0]
    gt = float((jpos[hold] - centre) @ axis)
    return {"length": length, "width": float(w.max() - w.min()), "thickness": float(t.max() - t.min()),
            "grip": (gt - float(proj.min())) / length, "off": float(np.linalg.norm((jpos[hold] - centre) - gt * axis)), "axis": axis}


def translate(js, binary, name, offset):
    node = [n for n in js["nodes"] if n.get("name") == name][0]
    for prim in js["meshes"][node["mesh"]]["primitives"]:
        acc = js["accessors"][prim["attributes"]["POSITION"]]
        view = js["bufferViews"][acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        assert view.get("byteStride", 0) in (0, 12)
        values = np.frombuffer(bytes(binary[start: start + 12 * acc["count"]]), dtype="<f4").reshape(-1, 3).astype(np.float64) + offset
        binary[start: start + 12 * acc["count"]] = values.astype("<f4").tobytes()
        acc["min"], acc["max"] = [float(x) for x in values.min(0)], [float(x) for x in values.max(0)]


def attribute_hash(js, binary, name):
    import hashlib
    node = [n for n in js["nodes"] if n.get("name") == name][0]
    h = hashlib.sha1()
    for p in js["meshes"][node["mesh"]]["primitives"]:
        for k in sorted(p["attributes"]):
            if k != "POSITION":
                h.update(k.encode() + glb.accessor_bytes(js, binary, p["attributes"][k]))
        h.update(glb.accessor_bytes(js, binary, p["indices"]))
        h.update(json.dumps(js["materials"][p["material"]], sort_keys=True).encode())
    return h.hexdigest()


def _refs(m):
    out = []
    for holder in (m, m.get("pbrMetallicRoughness", {})):
        for key in ("baseColorTexture", "metallicRoughnessTexture", "normalTexture", "occlusionTexture", "emissiveTexture"):
            if key in holder:
                out.append(holder[key])
    return out


def pick_textures(part, uris):
    """Keep only the images / textures the part's materials use (renumbered); `uris` = the external image entries."""
    used = sorted({r["index"] for m in part["materials"] for r in _refs(m)})
    if not used:
        part.pop("textures", None)
        part.pop("samplers", None)
        return
    textures = [dict(part["textures"][i]) for i in used]
    images = sorted({t["source"] for t in textures})
    part["images"] = [uris[i] for i in images]
    for t in textures:
        t["source"] = images.index(t["source"])
    remap = {old: new for new, old in enumerate(used)}
    for m in part["materials"]:
        for r in _refs(m):
            r["index"] = remap[r["index"]]
    part["textures"] = textures


def main():
    measure = "--measure" in sys.argv
    body_js, body_bin = glb.read_glb(os.path.join(ROOT, "art", "characters", "studio05", "split", "body_greatsword.glb"))
    rig = glb.rig_hash(body_js, body_bin)
    os.makedirs(TEXTURES, exist_ok=True)
    table = {}
    total = 0
    for source_name, (prefix, pieces) in DELIVERIES.items():
        js, binary = glb.read_glb(os.path.join(ROOT, "art_source", "race_gear", source_name))
        assert not js.get("animations") and glb.rig_hash(js, binary) == rig, "%s: rig differs from the Studio body rig: stop" % source_name
        uris = []
        for index, image in enumerate(js["images"]):
            view = js["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            mime = image.get("mimeType", "image/jpeg")
            name = "%s_%d.%s" % (prefix, index, "png" if mime == "image/png" else "jpg")
            with open(os.path.join(TEXTURES, name), "wb") as f:
                f.write(binary[start: start + view["byteLength"]])
            uris.append({"name": image.get("name", name), "uri": "../race_shared/" + name, "mimeType": mime})
            print("  %-30s %8d bytes" % (name, view["byteLength"]))
        bare = json.loads(json.dumps(js))
        bare.pop("images")
        all_textures, samplers = bare.pop("textures"), bare.pop("samplers", None)
        for race, rname in RACES.items():
            for kind, (label_kind, out_file, mid_file, hold) in pieces.items():
                keep = "Weapon_Lv15_%s_%s" % (rname, kind)
                assert keep in glb.meshed(js), keep
                part, part_bin = glb.subset(bare, binary, lambda n, keep=keep: "mesh" in n and n["name"] != keep, False)
                part["textures"] = json.loads(json.dumps(all_textures))
                if samplers is not None:
                    part["samplers"] = samplers
                pick_textures(part, uris)
                label = "Weapon_%s | %s" % (rname, label_kind)
                for node in part["nodes"]:
                    if node.get("name") == keep:
                        node["name"] = label
                part.setdefault("extras", {})["zorx_source"] = "%s %s" % (source_name, keep)
                folder = os.path.join(ROOT, "art", "weapons", "race_" + race)
                mj, mb = glb.read_glb(os.path.join(folder, mid_file))
                mid_label = list(glb.meshed(mj))[0]
                old = shape(mj, mb, mid_label, hold)
                new = shape(part, part_bin, label, hold, old["axis"])
                if measure:
                    print("    %-9s %-22s length %.3f vs %.3f = %.3f  width %.3f  thick %.3f  grip %.2f vs MID %.2f  off-axis %.3f vs %.3f"
                          % (race, out_file, new["length"], old["length"], new["length"] / old["length"], new["width"] / old["width"],
                             new["thickness"] / old["thickness"], new["grip"], old["grip"], new["off"], old["off"]))
                    if abs(new["grip"] - old["grip"]) > GRIP_TOLERANCE:
                        table[(race, out_file)] = round(float(new["grip"] - old["grip"]), 3)
                part_bin = bytearray(part_bin)
                shift = GRIP_SHIFT.get((race, out_file), 0.0)
                if shift:
                    translate(part, part_bin, label, new["axis"] * shift * new["length"])
                out = os.path.join(folder, out_file)
                glb.write_glb(out, part, bytes(part_bin))
                nj, nb = glb.read_glb(out)
                assert glb.rig_hash(nj, nb) == rig
                assert list(glb.meshed(nj)) == [label]
                assert attribute_hash(nj, nb, label) == attribute_hash(js, binary, keep), "joints / weights / UVs / indices / material changed"
                assert bound_joints(nj, nb, label) == bound_joints(mj, mb, mid_label), "%s is bound to %s, the MID file to %s" % (
                    out_file, bound_joints(nj, nb, label), bound_joints(mj, mb, mid_label))
                if not shift:
                    assert glb.mesh_hash(nj, nb, glb.meshed(nj)[label]) == glb.mesh_hash(js, binary, glb.meshed(js)[keep])
                final = shape(nj, nb, label, hold, old["axis"])
                assert abs(final["length"] / old["length"] - 1.0) <= LENGTH_TOLERANCE, "%s: length %.3f of the MID file" % (out_file, final["length"] / old["length"])
                if not measure:
                    assert abs(final["grip"] - old["grip"]) <= GRIP_TOLERANCE, "%s: grip %.2f, MID %.2f" % (out_file, final["grip"], old["grip"])
                total += os.path.getsize(out)
                print("  %-34s %8d bytes  length %.3f = %.3f of the MID file, grip %.2f (MID %.2f)%s  bound to %s" % (
                    os.path.relpath(out, ROOT), os.path.getsize(out), final["length"], final["length"] / old["length"], final["grip"], old["grip"],
                    " [shifted %.3f of the length]" % shift if shift else "", sorted(bound_joints(nj, nb, label))))
    print("weapons: %d bytes of GLB" % total)
    if measure:
        print("GRIP_SHIFT = {")
        for k, v in table.items():
            print("    %r: %r," % (k, v))
        print("}")


if __name__ == "__main__":
    main()

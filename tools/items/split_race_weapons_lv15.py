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
Pure glTF surgery (helpers from tools/characters/split_studio05_hair.py): accessors are copied byte for byte, then the SIZE
CORRECTION below may move the vertices; the script re-reads each output and fails loudly if the rig differs from the Studio
class bodies, if the joints / weights / UVs / indices / material differ from the source, or if the weapon is bound to other
bones than the matching MID-tier file (the weighted joints must be the same: RightHand, LeftHand or LeftForeArm).

SIZE CORRECTION (Boss: the level-15 weapons must be as big as the level-1 weapons). The level-1 weapon the game shows is the
class's own starter weapon (the "| Sword", "| Shield", "| Bow", "| Staff" pieces of art/characters/studio05/v1111/outfits/
armor_<class>.glb); its length along the main axis is the reference (CLASS_GEAR). The delivered Lv15 weapons are as long as
the interim MID race files (ratio 1.00) but shorter than the class weapons (sword 0.60, shield 0.73, greatsword 0.94, bow 0.88,
staff 0.84), so SIZE[(race, file)] = factor = reference length / delivered length, a uniform
scale about the grip point (the point of the weapon axis nearest to the holding joint; for the shield about the closest point
to the LeftForeArm joint) applied to POSITION (min / max updated), NORMAL unchanged. `--measure` prints the ratios of length,
width, thickness and grip position against the MID file of the same race and piece and the table to paste into SIZE.
Run: python -I tools/items/split_race_weapons_lv15.py            (from the repo root)
     python -I tools/items/split_race_weapons_lv15.py --measure   (print the size ratios)
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
# the class starter weapons (level 1): file in art/characters/studio05/v1111/outfits/ and the label that marks the piece
CLASS_GEAR = {"sword_shield_lv15.glb": ("armor_sword_shield.glb", "| Sword"), "shield_lv15.glb": ("armor_sword_shield.glb", "| Shield"),
              "greatsword_lv15.glb": ("armor_greatsword.glb", "| Sword"), "longbow_lv15.glb": ("armor_longbow.glb", "| Bow"),
              "magic_lv15.glb": ("armor_magic.glb", "| Staff")}
# SIZE[(race, file)] = uniform scale about the grip point; built by --measure (see the docstring)
SIZE = {
    ('human', 'sword_shield_lv15.glb'): 1.68,
    ('human', 'shield_lv15.glb'): 1.376,
    ('viking', 'sword_shield_lv15.glb'): 1.672,
    ('viking', 'shield_lv15.glb'): 1.612,
    ('elf', 'sword_shield_lv15.glb'): 1.664,
    ('elf', 'shield_lv15.glb'): 1.362,
    ('runeborn', 'sword_shield_lv15.glb'): 1.662,
    ('runeborn', 'shield_lv15.glb'): 1.387,
    ('human', 'greatsword_lv15.glb'): 1.067,
    ('viking', 'greatsword_lv15.glb'): 1.071,
    ('elf', 'greatsword_lv15.glb'): 1.063,
    ('runeborn', 'greatsword_lv15.glb'): 1.066,
    ('human', 'longbow_lv15.glb'): 1.132,
    ('viking', 'longbow_lv15.glb'): 1.102,
    ('elf', 'longbow_lv15.glb'): 1.103,
    ('runeborn', 'longbow_lv15.glb'): 1.103,
    ('human', 'magic_lv15.glb'): 1.189,
    ('viking', 'magic_lv15.glb'): 1.171,
    ('elf', 'magic_lv15.glb'): 1.173,
    ('runeborn', 'magic_lv15.glb'): 1.187,
}
TOLERANCE = 0.03


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


def main_axis(pos):
    centre = pos.mean(0)
    vals, vecs = np.linalg.eigh(np.cov((pos - centre).T))
    return centre, vecs


def shape(js, binary, name, hold):
    """Length (along the main axis), width, thickness, the grip point on the axis as a fraction of the length from the low end,
    and the distance of the holding joint from the axis; all in the skeleton's bind units."""
    pos, _, _ = mesh_arrays(js, binary, name)
    _, jpos = joint_info(js)
    centre, vecs = main_axis(pos)
    axis = vecs[:, 2]
    proj = (pos - centre) @ axis
    length = float(proj.max() - proj.min())
    w = (pos - centre) @ vecs[:, 1]
    t = (pos - centre) @ vecs[:, 0]
    gt = float((jpos[hold] - centre) @ axis)
    return {"length": length, "width": float(w.max() - w.min()), "thickness": float(t.max() - t.min()),
            "grip": (gt - float(proj.min())) / length, "off": float(np.linalg.norm((jpos[hold] - centre) - gt * axis))}


def class_length(out_file):
    """Length of the class starter weapon (main axis of all its pieces together) for the Lv15 file `out_file`."""
    gear, kind = CLASS_GEAR[out_file]
    js, binary = glb.read_glb(os.path.join(ROOT, "art", "characters", "studio05", "v1111", "outfits", gear))
    pos = np.concatenate([mesh_arrays(js, binary, n["name"])[0] for n in js["nodes"] if "mesh" in n and kind in n["name"]])
    centre, vecs = main_axis(pos)
    proj = (pos - centre) @ vecs[:, 2]
    return float(proj.max() - proj.min())


def grip_point(js, binary, name, hold):
    """The point of the weapon's main axis nearest to the holding joint."""
    pos, _, _ = mesh_arrays(js, binary, name)
    _, jpos = joint_info(js)
    centre, vecs = main_axis(pos)
    axis = vecs[:, 2]
    return centre + axis * float((jpos[hold] - centre) @ axis)


def scale_about(js, binary, name, factor, point):
    node = [n for n in js["nodes"] if n.get("name") == name][0]
    for prim in js["meshes"][node["mesh"]]["primitives"]:
        acc = js["accessors"][prim["attributes"]["POSITION"]]
        view = js["bufferViews"][acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        assert view.get("byteStride", 0) in (0, 12)
        values = np.frombuffer(bytes(binary[start: start + 12 * acc["count"]]), dtype="<f4").reshape(-1, 3).astype(np.float64)
        values = point + (values - point) * factor
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
                new = shape(part, part_bin, label, hold)
                old = shape(mj, mb, mid_label, hold)
                if measure:
                    print("    %-9s %-22s length %.3f vs %.3f = %.3f  width %.3f  thick %.3f  grip at %.2f vs %.2f  off-axis %.3f vs %.3f"
                          % (race, out_file, new["length"], old["length"], new["length"] / old["length"], new["width"] / old["width"],
                             new["thickness"] / old["thickness"], new["grip"], old["grip"], new["off"], old["off"]))
                    print("              class starter weapon length %.3f: Lv15 is %.3f of it (MID %.3f)" % (
                        class_length(out_file), new["length"] / class_length(out_file), old["length"] / class_length(out_file)))
                    table[(race, out_file)] = round(float(class_length(out_file) / new["length"]), 3)
                part_bin = bytearray(part_bin)
                factor = SIZE.get((race, out_file), 1.0)
                if factor != 1.0:
                    scale_about(part, part_bin, label, factor, grip_point(part, part_bin, label, hold))
                out = os.path.join(folder, out_file)
                glb.write_glb(out, part, bytes(part_bin))
                nj, nb = glb.read_glb(out)
                assert glb.rig_hash(nj, nb) == rig
                assert list(glb.meshed(nj)) == [label]
                assert attribute_hash(nj, nb, label) == attribute_hash(js, binary, keep), "joints / weights / UVs / indices / material changed"
                assert bound_joints(nj, nb, label) == bound_joints(mj, mb, mid_label), "%s is bound to %s, the MID file to %s" % (
                    out_file, bound_joints(nj, nb, label), bound_joints(mj, mb, mid_label))
                if factor == 1.0:
                    assert glb.mesh_hash(nj, nb, glb.meshed(nj)[label]) == glb.mesh_hash(js, binary, glb.meshed(js)[keep])
                total += os.path.getsize(out)
                final = shape(nj, nb, label, hold)
                reference = class_length(out_file)
                if SIZE:
                    assert abs(final["length"] / reference - 1.0) <= TOLERANCE, "%s: %.3f of the class weapon" % (out_file, final["length"] / reference)
                print("  %-34s %8d bytes  length %.3f = %.3f of the class weapon (MID file %.3f)  bound to %s" % (
                    os.path.relpath(out, ROOT), os.path.getsize(out), final["length"], final["length"] / reference, old["length"],
                    sorted(bound_joints(nj, nb, label))))
    print("weapons: %d bytes of GLB" % total)
    if measure:
        print("SIZE = {")
        for k, v in table.items():
            print("    %r: %r," % (k, v))
        print("}")


if __name__ == "__main__":
    main()

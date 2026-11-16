"""Split the Boss's LEVEL 15 race outfits (one look per race) into one GLB per race x armour slot.

Source: art_source/race_gear/race_outfits_lv15.glb (Boss delivery 2026-11-16; same layout as race_outfits.glb: 102-joint Studio
rig, 16 skinned meshes Outfit_Lv15_<Race>_<Boots|Gloves|Pants|Shirt>, ONE material "Level 15 | Original Armor.001", one 2048
JPEG atlas, no clips). Not shipped (art_source/).
Outputs (art/armor/race_shared/), next to the starter pieces they replace for the level-15 class armour:
  <race>_<slot>_lv15.glb           one mesh + the full rig; slot: shirt, pants, armband (= Gloves), shoes (= Boots)
  race_wardrobe_atlas_lv15.jpg     the atlas bytes as delivered, referenced by every GLB as an external image
The client (client/item_assets.gd) shows these for armour_<class>_<slot> items by the wearing card's race, and the starter
files (split_race_outfits.py) for the starter white kit and as the fallback.
Same pure glTF surgery as split_race_outfits.py: every kept accessor is copied byte for byte, the script re-reads each output
and checks the rig against the class bodies and each mesh against the source, and fails loudly on a difference.
GIRTH MATCH (Boss 2026-11-16: "the Lv15 torso and legs look much too thin next to the level 1 outfits"). The delivered Lv15
meshes are slimmer than the starter pieces on the trunk (front to back above all), the hips and the lower legs. Per race x slot,
a documented vertex adjustment in the bind pose (GIRTH below: per bone an (fx, fz) pair, built by `--measure` from the girth
of the starter piece and of the Lv15 piece, never shrinking, at most x1.20, left and right averaged): every vertex moves by
sum over its skin joints j of w_j * ((fx_j - 1) * perp_j.x * ex + (fz_j - 1) * perp_j.z * ez), where perp_j is the part of
(p - a_j) perpendicular to the bone axis (a_j = the joint, axis = joint to its longest child) and ex, ez the sideways and
front-to-back axes of the skeleton. The weights blend the factors, so there is no seam between bones. Normals get the matching
inverse scale. Only POSITION (with its min / max) and NORMAL change; joints, weights, UVs, indices, material, inverse binds and
the rig stay byte-identical (the script checks that, and checks every 7th moved vertex against this formula with plain
loops). Only the shirt and pants are adjusted: gloves and boots keep the Studio's shape (hands and feet are not distorted),
and parts thicker than the starter (shoulder pads) are not shrunk.
Girth of a bone = the 80th percentile of |x| and of |z| (distance from the bone axis along ex / ez) of the vertices mostly
weighted to it, along the middle of the bone.
Run: python -I tools/items/split_race_outfits_lv15.py   (from the repo root)
     python -I tools/items/split_race_outfits_lv15.py --measure   (print the girth ratios and the GIRTH table to paste below)
"""
import json
import os
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "characters"))
import split_studio05_hair as glb  # noqa: E402

SOURCE = os.path.join(ROOT, "art_source", "race_gear", "race_outfits_lv15.glb")
OUT = os.path.join(ROOT, "art", "armor", "race_shared")
ATLAS = "race_wardrobe_atlas_lv15.jpg"
RACES = {"human": "Human", "viking": "Viking", "elf": "Elf", "runeborn": "Runeborn"}
SLOTS = {"shirt": "Shirt", "pants": "Pants", "armband": "Gloves", "shoes": "Boots"}


def source_mesh_name(race, slot):
    return "Outfit_Lv15_%s_%s" % (RACES[race], SLOTS[slot])

ADJUST = {"shirt": ["Hips", "Spine", "Spine1", "Spine2", "Arm", "ForeArm"], "pants": ["Hips", "UpLeg", "Leg"]}
MAX_FACTOR = 1.20  # --measure limit; the hand-raised hips entries go to 1.25
PCT = 80  # percentile of the distance from the bone axis that counts as the girth (robust against flaps and straps)
TOLERANCE = 0.03
MIN_VERTS = 25
# GIRTH[(race, slot)][bone without Left/Right and the mixamorig: prefix] = (fx, fz). Built by --measure, then the Hips entries were
# raised by hand after a silhouette check (tools/shots/girth_sheet.py: front + side outfit silhouettes, hips band within ~5%).
GIRTH = {}
GIRTH[('human', 'shirt')] = {'Arm': (1.0, 1.02), 'ForeArm': (1.2, 1.2), 'Hips': (1.19, 1.06), 'Spine1': (1.2, 1.2), 'Spine2': (1.16, 1.06)}
GIRTH[('human', 'pants')] = {'Hips': (1.16, 1.09), 'Leg': (1.0, 1.0), 'UpLeg': (1.09, 1.18)}
GIRTH[('viking', 'shirt')] = {'Arm': (1.0, 1.2), 'ForeArm': (1.2, 1.2), 'Hips': (1.0, 1.2), 'Spine1': (1.0, 1.09), 'Spine2': (1.0, 1.08)}
GIRTH[('viking', 'pants')] = {'Hips': (1.2, 1.12), 'Leg': (1.07, 1.03), 'UpLeg': (1.07, 1.08)}
GIRTH[('elf', 'shirt')] = {'Arm': (1.0, 1.2), 'ForeArm': (1.16, 1.2), 'Hips': (1.1, 1.06), 'Spine2': (1.0, 1.0)}
GIRTH[('elf', 'pants')] = {'Hips': (1.15, 1.1), 'Leg': (1.0, 1.1), 'UpLeg': (1.02, 1.05)}
GIRTH[('runeborn', 'shirt')] = {'Arm': (1.07, 1.2), 'ForeArm': (1.2, 1.2), 'Hips': (1.25, 1.2), 'Spine1': (1.2, 1.2), 'Spine2': (1.0, 1.11)}
GIRTH[('runeborn', 'pants')] = {'Hips': (1.25, 1.22), 'Leg': (1.0, 1.0), 'UpLeg': (1.04, 1.06)}


def _acc(js, binary, index):
    a = js["accessors"][index]
    dtype = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    return np.frombuffer(glb.accessor_bytes(js, binary, index), dtype=dtype).reshape(-1, n)


def _skeleton(js):
    """Joint names and bone segments (origin, unit axis, length) of the skin, in the bind pose."""
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
    pos = [world(j)[:3, 3] for j in joints]
    at = {j: k for k, j in enumerate(joints)}
    seg = []
    for k, j in enumerate(joints):
        kids = [at[c] for c in nodes[j].get("children", []) if c in at]
        d = max((pos[c] - pos[k] for c in kids), key=np.linalg.norm) if kids else np.array([0.0, 1.0, 0.0])
        length = float(np.linalg.norm(d))
        seg.append((pos[k], d / length if length > 1e-9 else np.array([0.0, 1.0, 0.0]), length))
    return [nodes[j]["name"].replace("mixamorig:", "") for j in joints], seg


def _mesh_arrays(js, binary, name):
    node = [n for n in js["nodes"] if n.get("name") == name][0]
    at = js["meshes"][node["mesh"]]["primitives"][0]["attributes"]
    return (_acc(js, binary, at["POSITION"]).astype(np.float64), _acc(js, binary, at["NORMAL"]).astype(np.float64),
            _acc(js, binary, at["JOINTS_0"]).astype(int), _acc(js, binary, at["WEIGHTS_0"]).astype(np.float64))


def sector_girth(js, binary, name):
    """{bone: (gx, gz) or None}: PCT-th percentile of the distance from the bone axis along x and along z, for the vertices
    mostly weighted to the bone along its middle (-20% .. +120% of its length)."""
    pos, _, joints, weights = _mesh_arrays(js, binary, name)
    names, seg = _skeleton(js)
    out = {}
    for k, bone in enumerate(names):
        mask = ((joints == k) & (weights > 0.5)).any(1)
        a, d, length = seg[k]
        rel = pos[mask] - a
        t = rel @ d
        perp = rel - np.outer(t, d)
        perp = perp[(t > -0.2 * length) & (t < 1.2 * length)]
        if len(perp) < MIN_VERTS:
            out[bone] = None
            continue
        out[bone] = (float(np.percentile(np.abs(perp[:, 0]), PCT)), float(np.percentile(np.abs(perp[:, 2]), PCT)))
    return out


def _side(bone):
    return bone[4:] if bone.startswith("Left") else bone[5:] if bone.startswith("Right") else bone


def measure_factors(start_js, start_bin, start_name, new_js, new_bin, new_name, slot):
    """The per-bone (fx, fz) that bring the Lv15 piece to the starter girth (left / right averaged, never < 1, <= MAX_FACTOR)."""
    a = sector_girth(start_js, start_bin, start_name)
    c = sector_girth(new_js, new_bin, new_name)
    ratios = {}
    for bone in a:
        if _side(bone) in ADJUST[slot] and a[bone] and c[bone]:
            ratios.setdefault(_side(bone), []).append((a[bone][0] / c[bone][0], a[bone][1] / c[bone][1]))
    out = {}
    for bone, pairs in sorted(ratios.items()):
        fx, fz = np.mean(pairs, axis=0)
        out[bone] = (round(min(MAX_FACTOR, max(1.0, float(fx))), 2), round(min(MAX_FACTOR, max(1.0, float(fz))), 2))
    return out


def girth_adjust(js, binary, name, factors):
    """Apply `factors` ({bone without side: (fx, fz)}) to the named mesh's POSITION and NORMAL in `binary` (a bytearray).
    Returns the old and the new positions. Updates the POSITION accessor's min / max."""
    node = [n for n in js["nodes"] if n.get("name") == name][0]
    prim = js["meshes"][node["mesh"]]["primitives"][0]
    pos, nor, joints, weights = _mesh_arrays(js, binary, name)
    names, seg = _skeleton(js)
    new_pos, new_nor = pos.copy(), nor.copy()
    for k, bone in enumerate(names):
        fx, fz = factors.get(_side(bone), (1.0, 1.0))
        if fx == 1.0 and fz == 1.0:
            continue
        a, d, _ = seg[k]
        w = np.where(joints == k, weights, 0.0).sum(1)
        rel = pos - a
        perp = rel - np.outer(rel @ d, d)
        new_pos[:, 0] += w * (fx - 1.0) * perp[:, 0]
        new_pos[:, 2] += w * (fz - 1.0) * perp[:, 2]
        nperp = nor - np.outer(nor @ d, d)
        new_nor[:, 0] += w * (1.0 / fx - 1.0) * nperp[:, 0]
        new_nor[:, 2] += w * (1.0 / fz - 1.0) * nperp[:, 2]
    lengths = np.linalg.norm(new_nor, axis=1, keepdims=True)
    new_nor = new_nor / np.where(lengths > 1e-9, lengths, 1.0)
    for attribute, values in (("POSITION", new_pos), ("NORMAL", new_nor)):
        acc = js["accessors"][prim["attributes"][attribute]]
        view = js["bufferViews"][acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        assert view.get("byteStride", 0) in (0, 12)
        binary[start: start + 12 * len(values)] = values.astype("<f4").tobytes()
        if attribute == "POSITION":
            acc["min"], acc["max"] = [float(x) for x in values.min(0)], [float(x) for x in values.max(0)]
    return pos, new_pos


def attribute_hash(js, binary, name):
    """Hash of everything on the mesh except POSITION and NORMAL (joints, weights, UVs, indices, material)."""
    import hashlib
    node = [n for n in js["nodes"] if n.get("name") == name][0]
    h = hashlib.sha1()
    for p in js["meshes"][node["mesh"]]["primitives"]:
        for k in sorted(p["attributes"]):
            if k not in ("POSITION", "NORMAL"):
                h.update(k.encode() + glb.accessor_bytes(js, binary, p["attributes"][k]))
        h.update(glb.accessor_bytes(js, binary, p["indices"]))
        h.update(json.dumps(js["materials"][p["material"]], sort_keys=True).encode())
        assert not p.get("targets")
    return h.hexdigest()


def starter_piece(race, slot):
    path = os.path.join(OUT, "%s_%s.glb" % (race, slot))
    sj, sb = glb.read_glb(path)
    return sj, sb, list(glb.meshed(sj))[0]


def check_formula(old, new, joints, weights, factors, names, seg):
    """Independent per-vertex check of the documented adjustment (plain loops, no shared code with girth_adjust)."""
    worst = 0.0
    for i in range(0, len(old), 7):
        expect = old[i].copy()
        for slot_k in range(4):
            w = weights[i][slot_k]
            if w <= 0.0:
                continue
            k = joints[i][slot_k]
            fx, fz = factors.get(_side(names[k]), (1.0, 1.0))
            a, d, _ = seg[k]
            rel = old[i] - a
            perp = rel - d * float(rel @ d)
            expect = expect + w * np.array([(fx - 1.0) * perp[0], 0.0, (fz - 1.0) * perp[2]])
        worst = max(worst, float(np.abs(expect - new[i]).max()))
    return worst


def main():
    measure = "--measure" in sys.argv
    js, binary = glb.read_glb(SOURCE)
    assert len(js["images"]) == 1 and len(js["materials"]) == 1 and not js.get("animations"), "unexpected source layout"
    assert js["materials"][0]["name"].startswith("Level 15 | Original Armor"), js["materials"][0]["name"]
    body_js, body_bin = glb.read_glb(os.path.join(ROOT, "art", "characters", "studio05", "split", "body_greatsword.glb"))
    rig = glb.rig_hash(body_js, body_bin)
    assert glb.rig_hash(js, binary) == rig, "the delivery's rig differs from the Studio body rig: stop, do not adapt"
    os.makedirs(OUT, exist_ok=True)
    view = js["bufferViews"][js["images"][0]["bufferView"]]
    start = view.get("byteOffset", 0)
    with open(os.path.join(OUT, ATLAS), "wb") as f:
        f.write(binary[start: start + view["byteLength"]])
    bare = json.loads(json.dumps(js))
    images, textures, samplers = bare.pop("images"), bare.pop("textures"), bare.pop("samplers", None)
    names = set(glb.meshed(js))
    expected = {source_mesh_name(r, s) for r in RACES for s in SLOTS}
    assert names == expected, sorted(names ^ expected)
    total = 0
    for race in RACES:
        for slot in SLOTS:
            keep = source_mesh_name(race, slot)
            part, part_bin = glb.subset(bare, binary, lambda n, keep=keep: "mesh" in n and n["name"] != keep, False)
            part["images"] = [{"name": images[0].get("name", "atlas"), "uri": ATLAS, "mimeType": "image/jpeg"}]
            part["textures"] = textures
            if samplers is not None:
                part["samplers"] = samplers
            part.setdefault("extras", {})["zorx_source"] = "race_outfits_lv15.glb " + keep
            factors = GIRTH.get((race, slot), {})
            if measure and slot in ADJUST:
                sj, sb, sname = starter_piece(race, slot)
                found = measure_factors(sj, sb, sname, part, part_bin, keep, slot)
                print("    GIRTH[(%r, %r)] = %r" % (race, slot, found))
                before_g, starter_g = sector_girth(part, part_bin, keep), sector_girth(sj, sb, sname)
                for bone, was in before_g.items():
                    now = starter_g.get(bone)
                    if was and now and _side(bone) in ADJUST[slot]:
                        print("        %-14s starter x %5.1f z %5.1f  lv15 x %5.1f z %5.1f" % (bone, now[0] * 1000, now[1] * 1000, was[0] * 1000, was[1] * 1000))
            part_bin = bytearray(part_bin)
            moved = None
            if factors:
                moved = girth_adjust(part, part_bin, keep, factors)
                jn, wt = _mesh_arrays(part, part_bin, keep)[2:]
                bone_names, bone_seg = _skeleton(part)
                err = check_formula(moved[0], moved[1], jn, wt, factors, bone_names, bone_seg)
                assert err < 1e-6, "%s: the moved vertices differ from the documented formula by %g" % (keep, err)
            out = os.path.join(OUT, "%s_%s_lv15.glb" % (race, slot))
            glb.write_glb(out, part, bytes(part_bin))
            nj, nb = glb.read_glb(out)
            assert glb.rig_hash(nj, nb) == rig
            assert list(glb.meshed(nj)) == [keep]
            assert attribute_hash(nj, nb, keep) == attribute_hash(js, binary, keep), "joints / weights / UVs / indices / material changed"
            if not factors:
                assert glb.mesh_hash(nj, nb, glb.meshed(nj)[keep]) == glb.mesh_hash(js, binary, glb.meshed(js)[keep])
            assert nj["materials"][0]["name"] == js["materials"][0]["name"]
            if factors:
                sj, sb, sname = starter_piece(race, slot)
                a, c = sector_girth(sj, sb, sname), sector_girth(nj, nb, keep)
                low = ["%s x %.0f%% z %.0f%%" % (b, 100 * c[b][0] / a[b][0], 100 * c[b][1] / a[b][1]) for b in a if a[b] and c[b] and _side(b) in factors
                       and (c[b][0] < a[b][0] * (1 - TOLERANCE) or c[b][1] < a[b][1] * (1 - TOLERANCE))]
                print("    girth vs starter after the adjustment: %s" % (("still thinner: " + ", ".join(low)) if low else "within %d%% on every adjusted bone" % int(TOLERANCE * 100)))
            size = os.path.getsize(out)
            total += size
            tris = sum(js["accessors"][p["indices"]]["count"] for p in js["meshes"][glb.meshed(js)[keep]["mesh"]]["primitives"]) // 3 if "mesh" in glb.meshed(js)[keep] else -1
            print("  %-26s %8d bytes  %6d tris  <- %s" % (os.path.basename(out), size, tris, keep))
    atlas_size = os.path.getsize(os.path.join(OUT, ATLAS))
    print("  %-26s %8d bytes" % (ATLAS, atlas_size))
    print("rig identical to the Studio class bodies; meshes byte-identical; total %d bytes" % (total + atlas_size))


if __name__ == "__main__":
    main()

"""Split the studio05 whole-character GLBs into one base body per class + small hair-only files + one
Silver Silk outfit file (Boss 2026-11-13 item B: "load the body once, swap only the hair", as the Studio's
class-gear.js replaceCharacterHair() does).

Pure glTF JSON/binary surgery: every kept accessor's bytes are copied verbatim, so bones, inverse bind
matrices, rest transforms, skin weights, vertex colours, morph targets and animation keys stay bit-identical.
Only whole nodes/meshes/animations are dropped and the buffers repacked. The script then re-reads every
output and checks it against the source (hashes) and fails loudly on any difference.

Sources (all on the same 102-joint rig):
  art/characters/studio05/our_character_lowpoly_toon_hair_{a,b,c,e,f}_5k[_silver].glb   (Sword & Shield)
  art/characters/studio05/v1111/hair/our_character_{greatsword,longbow,magic}_hair_{a,b,c,e,f}_5k.glb
Outputs (art/characters/studio05/split/):
  body_<class>.glb       Base_Body + Head_Anime + rig + the class clips (from the class's hair C file)
  hair_<x>[_<class>].glb one hair mesh + the rig, no clips; hair meshes identical across classes share a file
  outfit_silver_silk.glb Outfit_SilverSilk + the rig (byte-identical in all silver files)
  manifest.json          class -> body file, class -> hair letter -> hair file, silver file; hair G
                         and hair I stay at v1111/hair/hair_{g,i}.glb (already hair-only files)

Clip check (printed): the clips of hair A/B/C/E (and Magic F) are byte-identical; the Great Sword and Longbow
hair F files hold the same keys on a timeline stretched x2.5 (an export frame-rate slip: 1/24 s steps instead
of 1/60 s), and Sword & Shield F only marks constant end-bone channels STEP. The game's clip marks
(data/classes/*.json clip_marks) are timed for the 1/60 s clips, so every hair uses the class body's clips.

Run: python -I tools/characters/split_studio05_hair.py   (from the repo root; re-run after a Studio drop)
"""
import hashlib
import json
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art", "characters", "studio05")
OUT = os.path.join(SRC, "split")
RES = "res://art/characters/studio05/split/"
CLASSES = {"sword_shield": "lowpoly_toon", "greatsword": "greatsword", "longbow": "longbow", "magic": "magic"}
LETTERS = ["a", "b", "c", "e", "f"]
STUDIO_HAIR_ONLY = ["g", "i"]  # already hair-only files at v1111/hair/hair_<x>.glb (no split needed)
BODY_FROM = "c"  # every class's hair C file (clips identical to A/B/E; head without the unused all-white COLOR_0)
COMP_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def source_path(cls, letter, silver=False):
    model = CLASSES[cls]
    if model == "lowpoly_toon":
        return os.path.join(SRC, "our_character_lowpoly_toon_hair_%s_5k%s.glb" % (letter, "_silver" if silver else ""))
    assert not silver
    return os.path.join(SRC, "v1111", "hair", "our_character_%s_hair_%s_5k.glb" % (model, letter))


def read_glb(path):
    data = open(path, "rb").read()
    assert data[:4] == b"glTF", path
    offset, js, binary = 12, None, b""
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + length]
        if kind == 0x4E4F534A:
            js = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + length
    return js, binary


def write_glb(path, js, binary):
    text = json.dumps(js, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def accessor_bytes(js, binary, index):
    acc = js["accessors"][index]
    assert "sparse" not in acc
    view = js["bufferViews"][acc["bufferView"]]
    size = COMP_SIZE[acc["componentType"]] * TYPE_COUNT[acc["type"]]
    stride = view.get("byteStride", 0)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    if stride in (0, size):
        return binary[start: start + size * acc["count"]]
    return b"".join(binary[start + i * stride: start + i * stride + size] for i in range(acc["count"]))


def subset(js, binary, drop_node, keep_animations):
    """A copy with the nodes for which drop_node(node) is true removed (leaves only), the meshes / materials /
    accessors / buffer views nobody uses any more removed, and the binary repacked (bytes copied as they are)."""
    js = json.loads(json.dumps(js))
    assert not js.get("textures") and not js.get("images"), "textured sources are not handled"
    drop = {i for i, n in enumerate(js["nodes"]) if drop_node(n)}
    for i in drop:
        assert not js["nodes"][i].get("children"), "only leaf nodes can be dropped"
    node_map, nodes = {}, []
    for i, n in enumerate(js["nodes"]):
        if i not in drop:
            node_map[i] = len(nodes)
            nodes.append(n)
    for n in nodes:
        if "children" in n:
            n["children"] = [node_map[c] for c in n["children"] if c in node_map]
            if not n["children"]:
                del n["children"]
    for scene in js["scenes"]:
        scene["nodes"] = [node_map[c] for c in scene["nodes"] if c in node_map]
    for skin in js.get("skins", []):
        skin["joints"] = [node_map[j] for j in skin["joints"]]
        if "skeleton" in skin:
            skin["skeleton"] = node_map[skin["skeleton"]]
    js["nodes"] = nodes
    if not keep_animations:
        js.pop("animations", None)
    for anim in js.get("animations", []):
        for ch in anim["channels"]:
            assert ch["target"]["node"] in node_map
            ch["target"]["node"] = node_map[ch["target"]["node"]]
    # meshes / skins / materials still used
    mesh_map, meshes = {}, []
    for n in nodes:
        if "mesh" in n:
            if n["mesh"] not in mesh_map:
                mesh_map[n["mesh"]] = len(meshes)
                meshes.append(js["meshes"][n["mesh"]])
            n["mesh"] = mesh_map[n["mesh"]]
    js["meshes"] = meshes
    skin_ids = sorted({n["skin"] for n in nodes if "skin" in n})
    skin_map = {s: i for i, s in enumerate(skin_ids)}
    js["skins"] = [js["skins"][s] for s in skin_ids]
    for n in nodes:
        if "skin" in n:
            n["skin"] = skin_map[n["skin"]]
    mat_map, materials = {}, []
    for m in meshes:
        for p in m["primitives"]:
            if "material" in p:
                if p["material"] not in mat_map:
                    mat_map[p["material"]] = len(materials)
                    materials.append(js["materials"][p["material"]])
                p["material"] = mat_map[p["material"]]
    js["materials"] = materials
    # accessors
    acc_map, accessors = {}, []

    def use(a):
        if a not in acc_map:
            acc_map[a] = len(accessors)
            accessors.append(js["accessors"][a])
        return acc_map[a]

    for m in meshes:
        for p in m["primitives"]:
            p["attributes"] = {k: use(v) for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = use(p["indices"])
            if "targets" in p:
                p["targets"] = [{k: use(v) for k, v in t.items()} for t in p["targets"]]
    for skin in js["skins"]:
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = use(skin["inverseBindMatrices"])
    for anim in js.get("animations", []):
        for s in anim["samplers"]:
            s["input"] = use(s["input"])
            s["output"] = use(s["output"])
    js["accessors"] = accessors
    # buffer views, repacked in order of first use; their bytes are copied verbatim
    view_map, views, chunks, offset = {}, [], [], 0
    for acc in accessors:
        v = acc["bufferView"]
        if v not in view_map:
            view = dict(js["bufferViews"][v])
            start = view.get("byteOffset", 0)
            data = binary[start: start + view["byteLength"]]
            pad = -offset % 4
            chunks.append(b"\0" * pad)
            offset += pad
            view["byteOffset"] = offset
            view["buffer"] = 0
            chunks.append(data)
            offset += len(data)
            view_map[v] = len(views)
            views.append(view)
        acc["bufferView"] = view_map[v]
    js["bufferViews"] = views
    out = b"".join(chunks)
    js["buffers"] = [{"byteLength": len(out)}]
    return js, out


# ---- fingerprints used for grouping and for the check ----------------------------------------------------

def mesh_hash(js, binary, node):
    m = js["meshes"][node["mesh"]]
    h = hashlib.sha1()
    for p in m["primitives"]:
        for k in sorted(p["attributes"]):
            h.update(k.encode() + accessor_bytes(js, binary, p["attributes"][k]))
        h.update(accessor_bytes(js, binary, p["indices"]))
        h.update(json.dumps(js["materials"][p["material"]], sort_keys=True).encode())
        for t in p.get("targets", []):
            for k in sorted(t):
                h.update(k.encode() + accessor_bytes(js, binary, t[k]))
    h.update(json.dumps([m.get("weights"), m.get("extras")]).encode())
    return h.hexdigest()


def rig_hash(js, binary):
    skin = js["skins"][0]
    joints = skin["joints"]
    h = hashlib.sha1(accessor_bytes(js, binary, skin["inverseBindMatrices"]))
    for j in joints:
        n = js["nodes"][j]
        h.update(json.dumps([n["name"], n.get("translation"), n.get("rotation"), n.get("scale"),
                             sorted(js["nodes"][c]["name"] for c in n.get("children", []))]).encode())
    return h.hexdigest()


def wrapper(js):
    return {n["name"]: [n.get("translation"), n.get("rotation"), n.get("scale")] for n in js["nodes"]
            if n["name"] in ("OurCharacter_50Percent", "ReferenceRig_Meshy")}


def clip_hashes(js, binary):
    out = {}
    for anim in js.get("animations", []):
        for ch in anim["channels"]:
            s = anim["samplers"][ch["sampler"]]
            key = (anim["name"], js["nodes"][ch["target"]["node"]]["name"], ch["target"]["path"])
            out[key] = hashlib.sha1(accessor_bytes(js, binary, s["input"]) + accessor_bytes(js, binary, s["output"])
                                    + s.get("interpolation", "LINEAR").encode()).hexdigest()
    return out


def meshed(js):
    return {n["name"]: n for n in js["nodes"] if "mesh" in n}


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"_comment": "Written by tools/characters/split_studio05_hair.py. The game loads body_<class> once and "
                "merges one hair file (and the Silver Silk outfit) onto its skeleton, like class-gear.js "
                "replaceCharacterHair(). Hairs G and I are hair-only files as delivered.",
                "bodies": {}, "hair": {}, "silver": RES + "outfit_silver_silk.glb",
                "hair_g": "res://art/characters/studio05/v1111/hair/hair_g.glb"}
    rig = None
    report = []
    # bodies
    for cls in CLASSES:
        path = source_path(cls, BODY_FROM)
        js, binary = read_glb(path)
        rig = rig or rig_hash(js, binary)
        assert rig_hash(js, binary) == rig
        body, body_bin = subset(js, binary, lambda n: str(n.get("name", "")).startswith("Hair_") and "mesh" in n, True)
        out = os.path.join(OUT, "body_%s.glb" % cls)
        write_glb(out, body, body_bin)
        manifest["bodies"][cls] = RES + "body_%s.glb" % cls
        # check against the source and the other hairs' clips
        nj, nb = read_glb(out)
        assert rig_hash(nj, nb) == rig and wrapper(nj) == wrapper(js)
        for name, node in meshed(nj).items():
            assert mesh_hash(nj, nb, node) == mesh_hash(js, binary, meshed(js)[name]), name
        assert sorted(meshed(nj)) == ["Base_Body", "Head_Anime"], sorted(meshed(nj))
        clips = clip_hashes(nj, nb)
        assert clips == clip_hashes(js, binary)
        for letter in LETTERS:
            other_js, other_bin = read_glb(source_path(cls, letter))
            other = clip_hashes(other_js, other_bin)
            same = sum(1 for k in clips if other.get(k) == clips[k])
            report.append("  %s hair %s: %d/%d clip channels byte-identical to the body" % (cls, letter, same, len(clips)))
    # hair: group identical hair meshes across classes
    groups = {}  # hash -> {"letter", "users": [(cls)], "src"}
    for cls in CLASSES:
        for letter in LETTERS:
            path = source_path(cls, letter)
            js, binary = read_glb(path)
            assert rig_hash(js, binary) == rig
            hair = [n for name, n in meshed(js).items() if name.startswith("Hair_")]
            assert len(hair) == 1
            h = mesh_hash(js, binary, hair[0])
            groups.setdefault(h, {"letter": letter, "users": [], "src": path})["users"].append(cls)
    by_letter = {}
    for h, g in groups.items():
        by_letter.setdefault(g["letter"], []).append((h, g))
    for letter, entries in by_letter.items():
        entries.sort(key=lambda e: -len(e[1]["users"]))
        for rank, (h, g) in enumerate(entries):
            name = "hair_%s.glb" % letter if rank == 0 else "hair_%s_%s.glb" % (letter, "_".join(g["users"]))
            js, binary = read_glb(g["src"])
            part, part_bin = subset(js, binary, lambda n: "mesh" in n and not str(n["name"]).startswith("Hair_")
                                    or ("mesh" not in n and n.get("name", "").startswith("Sharp ")), False)
            out = os.path.join(OUT, name)
            write_glb(out, part, part_bin)
            nj, nb = read_glb(out)
            assert rig_hash(nj, nb) == rig and wrapper(nj) == wrapper(js)
            names = list(meshed(nj))
            assert len(names) == 1 and mesh_hash(nj, nb, meshed(nj)[names[0]]) == h
            for cls in g["users"]:
                manifest["hair"].setdefault(cls, {})[letter] = RES + name
            report.append("  %s <- %s (%s) used by %s" % (name, os.path.basename(g["src"]), names[0], ", ".join(g["users"])))
    # Silver Silk: one outfit file (the silk mesh is byte-identical in every silver file)
    silk_hashes = set()
    for letter in LETTERS:
        js, binary = read_glb(source_path("sword_shield", letter, True))
        silk_hashes.add(mesh_hash(js, binary, meshed(js)["Outfit_SilverSilk"]))
        assert rig_hash(js, binary) == rig
    assert len(silk_hashes) == 1
    js, binary = read_glb(source_path("sword_shield", "c", True))
    silk, silk_bin = subset(js, binary, lambda n: "mesh" in n and n["name"] != "Outfit_SilverSilk", False)
    out = os.path.join(OUT, "outfit_silver_silk.glb")
    write_glb(out, silk, silk_bin)
    nj, nb = read_glb(out)
    assert rig_hash(nj, nb) == rig and list(meshed(nj)) == ["Outfit_SilverSilk"]
    assert mesh_hash(nj, nb, meshed(nj)["Outfit_SilverSilk"]) in silk_hashes
    # hairs G and I: hair-only files from the Studio / Boss (I = art_source/hair/hair_i.glb, 2026-11-13), same rig
    for letter in STUDIO_HAIR_ONLY:
        gj, gb = read_glb(os.path.join(SRC, "v1111", "hair", "hair_%s.glb" % letter))
        assert rig_hash(gj, gb) == rig, letter
        manifest["hair_" + letter] = "res://art/characters/studio05/v1111/hair/hair_%s.glb" % letter
        for cls in CLASSES:
            manifest["hair"][cls][letter] = manifest["hair_" + letter]
    with open(os.path.join(OUT, "manifest.json"), "w", newline="\n") as f:
        json.dump(manifest, f, indent=1)
        f.write("\n")
    print("rig (inverse binds + joint rest) identical in every file:", rig[:12])
    print("\n".join(report))
    for name in sorted(os.listdir(OUT)):
        if name.endswith(".glb"):
            print("  %-40s %9d bytes" % (name, os.path.getsize(os.path.join(OUT, name))))


if __name__ == "__main__":
    sys.exit(main())

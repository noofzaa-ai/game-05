#!/usr/bin/env python3
"""Imports the model team's skill packs into art/skills/, shrunk for the web build.

    python3 tools/skills/shrink_skills.py <pack root (has art/skills/skill_manifest.json)> [<project root>]
        [--only blade_inferno_ultimate,...] [--dry-run]

Per skill listed in the pack's art/skills/skill_manifest.json (folder must hold <id>.tres, skill.json,
motion.glb and vfx.glb, else it is skipped with the reason; folders the manifest does not list, such as
*_preview pose studies, are skipped too):
  motion.glb  the reference character's meshes and materials go (they only carried the skeleton); one
              tiny skinned triangle stays so Godot and Blender still build the same 57-bone Skeleton3D
              from the skin, and the clip keeps every bone. Redundant keys go (see TOL_MOTION).
  vfx.glb     keys that a straight line between their neighbours already gives go (TOL_VFX; constant
              tracks keep their two ends), zero scales become ZERO_SCALE (invisible, but no more
              "Basis must be normalized" import errors), embedded images over MAX_IMAGE px are halved.
  .import     written for each GLB with Godot's lossy animation compression on (the AnimationPlayer's
              compression/enabled), and for the shared flame texture as lossy WebP.
  shared/     the pack's runtime scripts/shaders (the .tres needs weapon_skill_pack.gd), the flame
              texture scaled to MAX_SHARED_TEXTURE px on its long side.
Never copied: project.godot, scenes/, scripts/ (their demo), art/characters (their rig = ours), any
.blend/.mp4/.zip/preview images. art/skills/skill_manifest.json is rewritten to list what is present,
keeping our "in_game" map (move id -> skill id; read by client/vfx/skill_vfx.gd).
Prints raw sizes before/after and triangles per skill; IMPORTED.md is written from the same numbers.
"""
import argparse
import copy
import io
import json
import os
import shutil
import struct
import sys

import numpy as np

TOL_VFX = {"translation": 1e-3, "rotation": 1e-3, "scale": 1e-3}       # metres / quaternion units / scale
TOL_MOTION = {"translation": 2e-4, "rotation": 2e-4, "scale": 2e-4}
ZERO_SCALE = 1e-4
MAX_IMAGE = 512
MAX_SHARED_TEXTURE = 768
PAGE_VFX, PAGE_MOTION = 512, 16  # KB, Godot animation compression pages (see scene_import)
SHARED_RUNTIME = (".gd", ".gdshader")
COMP = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


# ---------------------------------------------------------------- GLB in/out
class Glb:
    def __init__(self, path):
        data = open(path, "rb").read()
        assert data[:4] == b"glTF", path
        jlen = struct.unpack("<I", data[12:16])[0]
        self.j = json.loads(data[20:20 + jlen])
        off = 20 + jlen
        self.bin = b""
        if off < len(data):
            blen = struct.unpack("<I", data[off:off + 4])[0]
            self.bin = data[off + 8:off + 8 + blen]
        self.new = {}  # accessor index -> numpy array replacing its data
        self.new_images = {}  # image index -> (bytes, mime)

    def read(self, i):
        if i in self.new:
            return self.new[i]
        a = self.j["accessors"][i]
        assert "sparse" not in a, "sparse accessors are not supported"
        n = NCOMP[a["type"]]
        dt = np.dtype(COMP[a["componentType"]])
        if "bufferView" not in a:
            return np.zeros((a["count"], n), dt)
        v = self.j["bufferViews"][a["bufferView"]]
        assert not v.get("byteStride") or v["byteStride"] == dt.itemsize * n, "interleaved views are not supported"
        o = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        return np.frombuffer(self.bin, dt, a["count"] * n, o).reshape(a["count"], n)

    def add_accessor(self, arr, gltf_type, component=5126, minmax=False):
        a = {"componentType": component, "count": int(arr.shape[0]), "type": gltf_type}
        if minmax:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        self.j["accessors"].append(a)
        i = len(self.j["accessors"]) - 1
        self.new[i] = arr
        return i

    def image_bytes(self, i):
        if i in self.new_images:
            return self.new_images[i][0]
        v = self.j["bufferViews"][self.j["images"][i]["bufferView"]]
        o = v.get("byteOffset", 0)
        return self.bin[o:o + v["byteLength"]]

    def save(self, path):
        """Writes only what is still referenced (meshes, materials, textures, images, accessors)."""
        j = self.j
        meshes = sorted({n["mesh"] for n in j.get("nodes", []) if "mesh" in n})
        mesh_map = {m: k for k, m in enumerate(meshes)}
        for n in j.get("nodes", []):
            if "mesh" in n:
                n["mesh"] = mesh_map[n["mesh"]]
        j["meshes"] = [j["meshes"][m] for m in meshes]
        used_acc, used_mat = set(), set()
        for m in j["meshes"]:
            for p in m["primitives"]:
                used_acc.update(p["attributes"].values())
                if "indices" in p:
                    used_acc.add(p["indices"])
                for t in p.get("targets", []):
                    used_acc.update(t.values())
                if "material" in p:
                    used_mat.add(p["material"])
        for s in j.get("skins", []):
            if "inverseBindMatrices" in s:
                used_acc.add(s["inverseBindMatrices"])
        for an in j.get("animations", []):
            for s in an["samplers"]:
                used_acc.update((s["input"], s["output"]))
        # materials -> textures -> images
        mats = sorted(used_mat)
        mat_map = {m: k for k, m in enumerate(mats)}
        j["materials"] = [j["materials"][m] for m in mats] if "materials" in j else []
        used_tex = set()

        def walk(o, fn):  # texture infos: any "...Texture": {"index": n} in a material or its extensions
            if isinstance(o, dict):
                for k, v in o.items():
                    if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
                        fn(v)
                    walk(v, fn)
            elif isinstance(o, list):
                for v in o:
                    walk(v, fn)

        walk(j["materials"], lambda o: used_tex.add(o["index"]))
        texs = sorted(used_tex)
        tex_map = {t: k for k, t in enumerate(texs)}
        walk(j["materials"], lambda o: o.__setitem__("index", tex_map[o["index"]]))
        j["textures"] = [j["textures"][t] for t in texs] if "textures" in j else []
        imgs = sorted({t["source"] for t in j["textures"] if "source" in t})
        img_map = {im: k for k, im in enumerate(imgs)}
        for t in j["textures"]:
            if "source" in t:
                t["source"] = img_map[t["source"]]
        for m in j["meshes"]:
            for p in m["primitives"]:
                if "material" in p:
                    p["material"] = mat_map[p["material"]]
        # rebuild the binary buffer
        out = io.BytesIO()
        views = []

        def put(blob, target=None):
            while out.tell() % 4:
                out.write(b"\0")
            v = {"buffer": 0, "byteOffset": out.tell(), "byteLength": len(blob)}
            if target:
                v["target"] = target
            out.write(blob)
            views.append(v)
            return len(views) - 1

        accs = sorted(used_acc)
        acc_map = {a: k for k, a in enumerate(accs)}
        anim_only = set()
        for an in j.get("animations", []):
            for s in an["samplers"]:
                anim_only.update((s["input"], s["output"]))
        anim_blob, anim_offsets = io.BytesIO(), {}
        for a in accs:  # animation data: one view, accessors at offsets (saves a view per key track)
            if a in anim_only:
                while anim_blob.tell() % 4:
                    anim_blob.write(b"\0")
                anim_offsets[a] = anim_blob.tell()
                anim_blob.write(np.ascontiguousarray(self.read(a)).tobytes())
        anim_view = put(anim_blob.getvalue()) if anim_offsets else None
        new_accessors = []
        for a in accs:
            arr = self.read(a)
            acc = copy.deepcopy(j["accessors"][a])
            acc.pop("byteOffset", None)
            acc["count"] = int(arr.shape[0])
            if a in anim_offsets:
                acc["bufferView"] = anim_view
                if anim_offsets[a]:
                    acc["byteOffset"] = anim_offsets[a]
            else:
                acc["bufferView"] = put(np.ascontiguousarray(arr).tobytes())
            new_accessors.append(acc)
        new_images = []
        for im in imgs:
            img = copy.deepcopy(j["images"][im])
            if "bufferView" in img:
                blob = self.image_bytes(im)
                if im in self.new_images:
                    img["mimeType"] = self.new_images[im][1]
                img["bufferView"] = put(blob)
            new_images.append(img)
        for m in j["meshes"]:
            for p in m["primitives"]:
                p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
                if "indices" in p:
                    p["indices"] = acc_map[p["indices"]]
                p["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in p.get("targets", [])]
                if not p["targets"]:
                    del p["targets"]
        for s in j.get("skins", []):
            if "inverseBindMatrices" in s:
                s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
        for an in j.get("animations", []):
            for s in an["samplers"]:
                s["input"], s["output"] = acc_map[s["input"]], acc_map[s["output"]]
        j["accessors"], j["bufferViews"], j["images"] = new_accessors, views, new_images
        for key in ("images", "textures", "materials", "samplers"):
            if key in j and not j[key]:
                del j[key]
        while out.tell() % 4:
            out.write(b"\0")
        blob = out.getvalue()
        j["buffers"] = [{"byteLength": len(blob)}]
        js = json.dumps(j, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        total = 12 + 8 + len(js) + 8 + len(blob)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(blob), 0x004E4942) + blob)


def triangles(g):
    tris = 0
    for m in g.j.get("meshes", []):
        for p in m["primitives"]:
            if p.get("mode", 4) != 4:
                continue
            tris += (g.j["accessors"][p["indices"]]["count"] if "indices" in p else g.j["accessors"][p["attributes"]["POSITION"]]["count"]) // 3
    return tris


# ---------------------------------------------------------------- animation
def _keep_linear(t, v, tol, quat):
    """Indices of the keys to keep so straight lines between them stay within tol of every key."""
    n = len(t)
    if n <= 2:
        return list(range(n))
    keep = np.zeros(n, bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        mid = np.arange(a + 1, b)
        span = t[b] - t[a]
        f = ((t[mid] - t[a]) / span if span > 0 else np.zeros(len(mid)))[:, None]
        guess = v[a] * (1 - f) + v[b] * f
        if quat:
            guess /= np.maximum(np.linalg.norm(guess, axis=1, keepdims=True), 1e-12)
        err = np.abs(guess - v[mid]).max(axis=1)
        k = int(err.argmax())
        if err[k] > tol:
            keep[mid[k]] = True
            stack += [(a, mid[k]), (mid[k], b)]
    return list(np.nonzero(keep)[0])


def reduce_animations(g, tol, fix_zero_scale):
    """Drops redundant keys; returns (keys before, keys after)."""
    before = after = 0
    shared_times = {}  # identical key times share one input accessor
    for an in g.j.get("animations", []):
        for ch in an["channels"]:
            path = ch["target"]["path"]
            s = an["samplers"][ch["sampler"]]
            if path not in tol:
                continue  # (morph weights: kept as they are)
            t = g.read(s["input"]).astype(np.float64)[:, 0]
            v = g.read(s["output"]).astype(np.float64).copy()
            before += len(t)
            interp = s.get("interpolation", "LINEAR")
            if path == "scale" and fix_zero_scale:
                small = np.abs(v) < ZERO_SCALE
                v[small] = np.where(v[small] < 0, -ZERO_SCALE, ZERO_SCALE)
            if interp == "CUBICSPLINE":
                keep = list(range(len(t)))
            elif interp == "STEP":
                keep = [0] + [i for i in range(1, len(t)) if np.abs(v[i] - v[i - 1]).max() > 0] + [len(t) - 1]
                keep = sorted(set(keep))
            else:
                if path == "rotation":
                    for i in range(1, len(v)):  # same rotations, no sign flips between keys
                        if np.dot(v[i], v[i - 1]) < 0:
                            v[i] = -v[i]
                keep = _keep_linear(t, v, tol[path], path == "rotation")
            after += len(keep)
            times = t[keep].astype(np.float32)[:, None]
            if times.tobytes() not in shared_times:
                shared_times[times.tobytes()] = g.add_accessor(times, "SCALAR", minmax=True)
            s["input"] = shared_times[times.tobytes()]
            s["output"] = g.add_accessor(v[keep].astype(np.float32), {3: "VEC3", 4: "VEC4"}[v.shape[1]])
    if fix_zero_scale:
        for n in g.j.get("nodes", []):
            if "scale" in n:
                n["scale"] = [x if abs(x) >= ZERO_SCALE else (-ZERO_SCALE if x < 0 else ZERO_SCALE) for x in n["scale"]]
    return before, after


# ---------------------------------------------------------------- per file
def shrink_motion(src, dst):
    """Keeps the skeleton (skin joints) + clip; the reference body becomes one tiny skinned triangle."""
    g = Glb(src)
    j = g.j
    tris_before = triangles(g)
    skins = j.get("skins", [])
    assert len(skins) == 1, "motion.glb: expected one skin (the 57-bone rig), found %d" % len(skins)
    holder = next(i for i, n in enumerate(j["nodes"]) if n.get("skin") == 0)
    for n in j["nodes"]:
        n.pop("mesh", None)
        n.pop("skin", None)
        n.pop("weights", None)
    pos = np.array([[0, 0, 0], [0.001, 0, 0], [0, 0.001, 0]], np.float32)
    joints = np.zeros((3, 4), np.uint8)
    weights = np.array([[1, 0, 0, 0]] * 3, np.float32)
    j["meshes"].append({"name": "skeleton_carrier", "primitives": [{"attributes": {
        "POSITION": g.add_accessor(pos, "VEC3", minmax=True),
        "JOINTS_0": g.add_accessor(joints, "VEC4", component=5121),
        "WEIGHTS_0": g.add_accessor(weights, "VEC4")}}]})
    j["nodes"][holder]["mesh"] = len(j["meshes"]) - 1
    j["nodes"][holder]["skin"] = 0
    j.pop("materials", None)
    for p in j["meshes"][-1]["primitives"]:
        p.pop("material", None)
    keys = reduce_animations(g, TOL_MOTION, False)
    g.save(dst)
    return {"tris_before": tris_before, "keys": keys, "bones": len(skins[0]["joints"]),
            "clips": [a.get("name", "") for a in j.get("animations", [])]}


def shrink_vfx(src, dst):
    g = Glb(src)
    tris = triangles(g)
    zero_nodes = sum(1 for n in g.j.get("nodes", []) if "scale" in n and min(abs(x) for x in n["scale"]) < ZERO_SCALE)
    keys = reduce_animations(g, TOL_VFX, True)
    resized = 0
    for i, img in enumerate(g.j.get("images", [])):
        if "bufferView" not in img:
            continue
        from PIL import Image
        im = Image.open(io.BytesIO(g.image_bytes(i)))
        if max(im.size) > MAX_IMAGE:
            k = MAX_IMAGE / max(im.size)
            im = im.resize((max(1, round(im.size[0] * k)), max(1, round(im.size[1] * k))), Image.LANCZOS)
            b = io.BytesIO()
            im.save(b, "PNG", optimize=True)
            g.new_images[i] = (b.getvalue(), "image/png")
            resized += 1
    g.save(dst)
    return {"tris": tris, "keys": keys, "zero_scale_nodes": zero_nodes, "images_resized": resized,
            "clips": [a.get("name", "") for a in g.j.get("animations", [])]}


def scene_import(dst_glb, page_kb):
    """A .import that turns on Godot's animation compression for the GLB's AnimationPlayer.
    (Godot fills in every other option with its default on the next --import.) A VFX clip animates
    ~2000-3000 tracks: pages under ~128 KB fail ("Cannot compress with the given page size") and Godot
    keeps it uncompressed, so VFX use PAGE_VFX. remove_immutable_tracks is off: a bone/particle held still
    away from its rest pose must keep its track (Godot would drop it and the node would sit at rest)."""
    sub = {"nodes": {"PATH:AnimationPlayer": {"optimizer/enabled": True, "compression/enabled": True,
                                              "compression/page_size": page_kb}}}
    with open(dst_glb + ".import", "w") as f:
        f.write('[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
                'meshes/generate_lods=false\nmeshes/create_shadow_meshes=false\nmeshes/light_baking=0\n'
                'meshes/ensure_tangents=false\nanimation/import=true\nanimation/remove_immutable_tracks=false\n'
                '_subresources=%s\n' % json.dumps(sub))


def texture_import(dst_png):
    with open(dst_png + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                'compress/mode=1\ncompress/lossy_quality=0.8\nmipmaps/generate=true\n')


# ---------------------------------------------------------------- main
def size(p):
    return os.path.getsize(p) if os.path.exists(p) else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pack")
    ap.add_argument("project", nargs="?", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
    ap.add_argument("--only", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    src_root = os.path.join(a.pack, "art", "skills")
    dst_root = os.path.join(a.project, "art", "skills")
    pack_manifest = json.load(open(os.path.join(src_root, "skill_manifest.json")))
    only = set(filter(None, a.only.split(",")))
    report, skipped, listed = [], [], set()
    for entry in pack_manifest["skills"]:
        sid = entry["id"]
        rel = entry["resource_path"].replace("res://art/skills/", "")
        folder = os.path.dirname(rel)
        listed.add(folder)
        if only and sid not in only:
            continue
        src = os.path.join(src_root, folder)
        need = [os.path.basename(rel), "skill.json", "motion.glb", "vfx.glb"]
        missing = [n for n in need if not os.path.exists(os.path.join(src, n))]
        if missing:
            skipped.append((sid, "missing " + ", ".join(missing)))
            continue
        skill = json.load(open(os.path.join(src, "skill.json")))
        if skill.get("slot") != "ultimate" or skill.get("attack", {}).get("direction") != "forward":
            skipped.append((sid, "not a forward ultimate (breaks art/skills/ultimate_defaults.json)"))
            continue
        dst = os.path.join(dst_root, folder)
        raw = sum(size(os.path.join(src, n)) for n in need)
        row = {"id": sid, "name": entry.get("name", ""), "weapon_type": skill.get("weapon_type", ""),
               "folder": folder, "raw": raw, "duration_s": skill.get("duration_s"),
               "asset_version": entry.get("asset_version"),
               "presentation": skill.get("godot_visual", {}).get("presentation", "")}
        if a.dry_run:
            report.append(row)
            continue
        if os.path.isdir(dst):
            shutil.rmtree(dst)  # a re-run replaces the folder (our old copy of the same skill)
        os.makedirs(dst)
        for n in (os.path.basename(rel), "skill.json"):
            shutil.copy2(os.path.join(src, n), os.path.join(dst, n))
        row["motion"] = shrink_motion(os.path.join(src, "motion.glb"), os.path.join(dst, "motion.glb"))
        row["vfx"] = shrink_vfx(os.path.join(src, "vfx.glb"), os.path.join(dst, "vfx.glb"))
        scene_import(os.path.join(dst, "motion.glb"), PAGE_MOTION)
        scene_import(os.path.join(dst, "vfx.glb"), PAGE_VFX)
        row["shrunk"] = sum(size(os.path.join(dst, n)) for n in need)
        report.append(row)
        print("%-34s raw %6.2f MB -> %5.2f MB  vfx %5d tris  keys vfx %d->%d motion %d->%d" % (
            sid, raw / 1e6, row["shrunk"] / 1e6, row["vfx"]["tris"], *row["vfx"]["keys"], *row["motion"]["keys"]))
    for t in sorted(os.listdir(src_root)):
        if t == "shared" or not os.path.isdir(os.path.join(src_root, t)):
            continue
        for s in sorted(os.listdir(os.path.join(src_root, t))):
            if os.path.isdir(os.path.join(src_root, t, s)) and t + "/" + s not in listed:
                why = "pose study / preview pack (no .tres or skill.json, not in the pack manifest)" \
                    if s.endswith("_preview") else "not in the pack manifest"
                skipped.append((t + "/" + s, why))
    if a.dry_run:
        print(json.dumps({"would_import": [r["id"] for r in report], "skipped": skipped}, indent=1))
        return
    # shared runtime: scripts + shaders as they are, the flame texture scaled down
    shared_src, shared_dst = os.path.join(src_root, "shared"), os.path.join(dst_root, "shared")
    for base, _, files in os.walk(shared_src):
        for n in files:
            s = os.path.join(base, n)
            d = os.path.join(shared_dst, os.path.relpath(s, shared_src))
            os.makedirs(os.path.dirname(d), exist_ok=True)
            if n.endswith(SHARED_RUNTIME):
                shutil.copy2(s, d)
            elif n.endswith(".png"):
                from PIL import Image
                im = Image.open(s)
                if max(im.size) > MAX_SHARED_TEXTURE:
                    k = MAX_SHARED_TEXTURE / max(im.size)
                    im = im.resize((round(im.size[0] * k), round(im.size[1] * k)), Image.LANCZOS)
                im.save(d, "PNG", optimize=True)
                texture_import(d)
    for n in ("ultimate_defaults.json", "weapon_movement_policies.json"):
        if os.path.exists(os.path.join(src_root, n)):
            shutil.copy2(os.path.join(src_root, n), os.path.join(dst_root, n))
    # our manifest: only what is present now, our in_game map kept
    ours_path = os.path.join(dst_root, "skill_manifest.json")
    ours = json.load(open(ours_path)) if os.path.exists(ours_path) else {}
    present = []
    for entry in pack_manifest["skills"]:
        folder = os.path.dirname(entry["resource_path"].replace("res://art/skills/", ""))
        if os.path.exists(os.path.join(dst_root, folder, "vfx.glb")):
            present.append(entry)
    out = {k: v for k, v in pack_manifest.items() if k != "skills"}
    out["in_game"] = ours.get("in_game", {"blade_ultimate": "blade_inferno_ultimate"})
    out["_comment"] = ("Skill packs present in art/skills (imported and shrunk by tools/skills/shrink_skills.py, see "
                       "IMPORTED.md). in_game: which pack a move shows (move id in data/combat/weapons.json -> skill "
                       "id); a pack not listed there is in the build but not shown yet.")
    out["skills"] = present
    with open(ours_path, "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write("\n")
    json.dump({"imported": report, "skipped": skipped}, open(os.path.join(a.project, "art_source", "skills_shrink_report.json"), "w"), indent=1, ensure_ascii=False)
    print("skipped:")
    for s in skipped:
        print("  %s: %s" % s)


if __name__ == "__main__":
    main()

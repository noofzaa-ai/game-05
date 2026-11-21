"""Rigs the squeezed Boss ORC WARLOCK body (tools/monsters/squeeze_fbx.py output of the Boss's warlock FBX 2026-11-21: 20 loose
parts, no armature, a hooded purple-robed orc with horns, spiked pauldrons, a long coat, empty hands, A-pose) with a landmark
armature named like the mummy stand-in's own rig, so tools/monsters/build_mummy_family.gd puts it on the shared 102-joint
studio05 rig (same pipeline as rig_orc_fbx.py). Skin parts get smooth distance weights over the bones listed in SMOOTH; the
coat skirt (below the belt) is blended from the hips toward the thigh on its side (SKIRT) so it follows the stride without
tearing between the legs; every accessory is weighted 100% to one bone (RIGID). All parts are joined into ONE mesh, one material.
blender --background --factory-startup --python tools/monsters/rig_warlock_fbx.py -- <squeezed.glb> <out.glb> [markers.png]
Landmarks in glTF space (x = the character's LEFT, y up, z forward), feet at y = 0, measured from build/orc_warlock/parts.txt
and the front/side renders.
"""
import sys, bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
markers = args[2] if len(args) > 2 else ""

BONES = {
    "root": ((0.0, 0.0, 0.0), (0.0, 0.08, 0.0), None),
    "hips": ((0.0, 0.40, 0.0), (0.0, 0.48, 0.0), "root"),
    "spine": ((0.0, 0.48, 0.0), (0.0, 0.56, 0.0), "hips"),
    "chest": ((0.0, 0.56, 0.0), (0.0, 0.68, 0.0), "spine"),
    "neck": ((0.0, 0.68, 0.0), (0.0, 0.74, 0.01), "chest"),
    "head": ((0.0, 0.74, 0.01), (0.0, 1.0, 0.01), "neck"),
    "clavicle.L": ((0.04, 0.67, 0.0), (0.19, 0.69, 0.0), "chest"),
    "upper_arm.L": ((0.19, 0.69, 0.0), (0.30, 0.57, 0.0), "clavicle.L"),
    "forearm.L": ((0.30, 0.57, 0.0), (0.39, 0.46, 0.0), "upper_arm.L"),
    "hand.L": ((0.39, 0.46, 0.0), (0.43, 0.33, 0.0), "forearm.L"),
    "clavicle.R": ((-0.04, 0.67, 0.0), (-0.19, 0.69, 0.0), "chest"),
    "upper_arm.R": ((-0.19, 0.69, 0.0), (-0.30, 0.57, 0.0), "clavicle.R"),
    "forearm.R": ((-0.30, 0.57, 0.0), (-0.39, 0.46, 0.0), "upper_arm.R"),
    "hand.R": ((-0.39, 0.46, 0.0), (-0.43, 0.33, 0.0), "forearm.R"),
    "thigh.L": ((0.10, 0.39, 0.0), (0.13, 0.24, 0.0), "hips"),
    "shin.L": ((0.13, 0.24, 0.0), (0.135, 0.075, -0.01), "thigh.L"),
    "foot.L": ((0.135, 0.075, -0.01), (0.135, 0.02, 0.07), "shin.L"),
    "toe.L": ((0.135, 0.02, 0.07), (0.135, 0.015, 0.13), "foot.L"),
    "thigh.R": ((-0.10, 0.39, 0.0), (-0.13, 0.24, 0.0), "hips"),
    "shin.R": ((-0.13, 0.24, 0.0), (-0.135, 0.075, -0.01), "thigh.R"),
    "foot.R": ((-0.135, 0.075, -0.01), (-0.135, 0.02, 0.07), "shin.R"),
    "toe.R": ((-0.135, 0.02, 0.07), (-0.135, 0.015, 0.13), "foot.R"),
}
ARM_L = ["clavicle.L", "upper_arm.L", "forearm.L"]
ARM_R = ["clavicle.R", "upper_arm.R", "forearm.R"]
SMOOTH = {
    "part_16": ["hips", "spine", "chest", "neck"] + ARM_L + ARM_R,  # the coat: torso, sleeves to the wrist, skirt (SKIRT below)
    "part_14": ["hips", "thigh.L", "shin.L", "thigh.R", "shin.R"],  # trousers
    "part_13": ["shin.L", "foot.L", "toe.L"],  # left boot
    "part_12": ["shin.R", "foot.R", "toe.R"],  # right boot
    "part_3": ["clavicle.L", "upper_arm.L"],  # left spiked pauldron
    "part_0": ["clavicle.R", "upper_arm.R"],  # right spiked pauldron
    "part_9": ["chest", "neck", "head"],  # the hood (drapes onto the shoulders)
    "part_19": ["hips"],  # the coat's side panel (right hip; SKIRT)
}
# below the belt: weight drifts from the hips to the thigh on the vertex's side (max SKIRT_MAX at SKIRT_DEPTH under SKIRT_TOP)
SKIRT = {"part_16", "part_19"}
# (0.6 stretched the coat between the legs in the wide block stance, Boss 2026-11-21: 0.35 keeps the skirt mostly on the hips)
SKIRT_TOP, SKIRT_DEPTH, SKIRT_MAX, SKIRT_SPLIT = 0.40, 0.26, 0.35, 0.12
# Boss 2026-11-21: the source robe is purple-magenta (albedo hue 280-350; the game's toon light makes it read pink). The robe and
# hood are repainted warm earth BROWN in the albedo (only inside these parts' UV islands and only purple pixels: green skin, bone
# horns, belt and the pauldrons stay as they are; the light rune trim becomes bronze), and the face in the hood is lifted so it
# reads at phone size. Written as <out dir>/albedo_brown.png, which build_mummy_family.gd uses.
KEEP_PARTS = ["part_3", "part_0"]  # the spiked pauldrons keep their purple
FACE_PARTS = ["part_17"]
RIGID = {
    "part_17": "head",       # the face in the hood
    "part_2": "head",        # right horn
    "part_4": "head",        # left horn
    "part_5": "head",        # hood crest spike
    "part_1": "hips",        # skull buckle
    "part_10": "hips",       # belt
    "part_11": "forearm.L",  # left cuff
    "part_8": "forearm.R",   # right cuff
    "part_7": "hand.L",      # left hand
    "part_6": "hand.R",      # right hand
    "part_15": "shin.L",     # left boot strap
    "part_18": "shin.R",     # right boot strap
}


def bl(p):
    """glTF (x, y up, z forward) -> Blender (x, -z, y)."""
    return Vector((p[0], -p[2], p[1]))


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = {o.name.split(".")[0]: o for o in bpy.data.objects if o.type == "MESH"}
missing = [n for n in list(SMOOTH) + list(RIGID) if n not in objs]
extra = [n for n in objs if n not in SMOOTH and n not in RIGID]
print("PARTS", len(objs), "missing", missing, "unassigned", extra)
assert not missing and not extra
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.select_all(action="DESELECT")

arm_data = bpy.data.armatures.new("rig")
arm = bpy.data.objects.new("rig", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, parent) in BONES.items():
    b = arm_data.edit_bones.new(name)
    b.head = bl(h)
    b.tail = bl(t)
for name, (h, t, parent) in BONES.items():
    if parent:
        arm_data.edit_bones[name].parent = arm_data.edit_bones[parent]
        arm_data.edit_bones[name].use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
arm_data.bones["root"].use_deform = False
segs = {b.name: (b.head_local, b.tail_local) for b in arm_data.bones if b.use_deform}


def smooth_weights(co, allowed):
    ds = []
    for n in allowed:
        a, c = segs[n]
        ab = c - a
        t = max(0.0, min(1.0, (co - a).dot(ab) / ab.length_squared))
        ds.append(((a + ab * t - co).length, n))
    ds.sort()
    near = ds[0][0]
    pick = [(d, n) for d, n in ds[:3] if d <= near * 1.8 + 0.02]
    ws = [1.0 / (d + 0.01) ** 3 for d, n in pick]
    tot = sum(ws)
    return {n: w / tot for (d, n), w in zip(pick, ws)}


for part, allowed in SMOOTH.items():
    o = objs[part]
    for n in set(allowed + (["thigh.L", "thigh.R"] if part in SKIRT else [])):
        o.vertex_groups.new(name=n)
    for v in o.data.vertices:
        up = v.co.z  # Blender z = glTF y (up)
        if part in SKIRT and up < SKIRT_TOP:
            a = min(1.0, (SKIRT_TOP - up) / SKIRT_DEPTH) * SKIRT_MAX
            left = max(0.0, min(1.0, 0.5 + v.co.x / (2.0 * SKIRT_SPLIT)))
            ws = {"hips": 1.0 - a, "thigh.L": a * left, "thigh.R": a * (1.0 - left)}
        else:
            ws = smooth_weights(v.co, [n for n in allowed])
        for n, w in ws.items():
            if w > 0.0:
                o.vertex_groups[n].add([v.index], w, "REPLACE")
import os
import numpy as np


def uv_mask(parts, size):
    """Pixels covered by the UV triangles of `parts` (Blender image rows: 0 = bottom = uv v 0)."""
    mask = np.zeros((size, size), dtype=bool)
    ys, xs = np.mgrid[0:size, 0:size]
    for name in parts:
        me = objs[name].data
        uv = me.uv_layers.active.data
        for poly in me.polygons:
            pts = [uv[li].uv for li in poly.loop_indices]
            for k in range(1, len(pts) - 1):
                a, b, c = [np.array((p.x * size, p.y * size)) for p in (pts[0], pts[k], pts[k + 1])]
                x0, x1 = int(max(0, min(a[0], b[0], c[0]) - 1)), int(min(size - 1, max(a[0], b[0], c[0]) + 1))
                y0, y1 = int(max(0, min(a[1], b[1], c[1]) - 1)), int(min(size - 1, max(a[1], b[1], c[1]) + 1))
                if x1 < x0 or y1 < y0:
                    continue
                d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
                if abs(d) < 1e-9:
                    continue
                px_ = xs[y0:y1 + 1, x0:x1 + 1] + 0.5
                py_ = ys[y0:y1 + 1, x0:x1 + 1] + 0.5
                l1 = ((b[1] - c[1]) * (px_ - c[0]) + (c[0] - b[0]) * (py_ - c[1])) / d
                l2 = ((c[1] - a[1]) * (px_ - c[0]) + (a[0] - c[0]) * (py_ - c[1])) / d
                l3 = 1.0 - l1 - l2
                e = -0.02  # a little slack so island edges are covered
                mask[y0:y1 + 1, x0:x1 + 1] |= (l1 >= e) & (l2 >= e) & (l3 >= e)
    return mask


albedo_path = os.path.join(os.path.dirname(os.path.abspath(src)), "albedo.png")
img = bpy.data.images.load(albedo_path)
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
rgb = px[..., :3]
mx = rgb.max(-1)
mn = rgb.min(-1)
sat = np.where(mx > 1e-5, (mx - mn) / np.maximum(mx, 1e-5), 0.0)
r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
hue = np.degrees(np.arctan2(np.sqrt(3.0) * (g - b), 2.0 * r - g - b)) % 360.0
purple = ((hue >= 245.0) | (hue < 5.0)) & (sat > 0.12) & (b > g)
# every purple pixel except the spiked pauldrons' islands (kept as they are): the robe/hood islands alone missed seams and
# small islands the decimated mesh still samples (purple patches remained on the hood)
keep = uv_mask(KEEP_PARTS, W)
robe = purple & ~keep
# brown: value a little darker, hue 24 (shadow) to 36 (light rune trim -> bronze), saturation 0.52-0.6
v = mx * 0.82
t = np.clip((mx - 0.5) / 0.3, 0.0, 1.0)
h6 = (24.0 + 12.0 * t) / 60.0
s_new = 0.52 + 0.08 * t
c = v * s_new
x = c * (1.0 - np.abs(h6 % 2.0 - 1.0))
brown = np.stack([v, v - c + x, v - c], -1)  # hue in [0, 60): r = v, g = m + x, b = m
rgb[robe] = brown[robe]
face = uv_mask(FACE_PARTS, W)
rgb[face] = np.clip(np.power(np.clip(rgb[face], 0.0, 1.0), 0.7) * 1.2, 0.0, 1.0)
px[..., :3] = rgb
out_img = bpy.data.images.new("albedo_brown", W, H)
out_img.pixels = px.ravel().tolist()
out_img.filepath_raw = os.path.join(os.path.dirname(os.path.abspath(out)), "albedo_brown.png")
out_img.file_format = "PNG"
out_img.save()
print("RECOLOUR robe px", int(robe.sum()), "face px", int(face.sum()), "->", out_img.filepath_raw)

for part, bone in RIGID.items():
    o = objs[part]
    g = o.vertex_groups.new(name=bone)
    g.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
for o in objs.values():
    m = o.modifiers.new("arm", "ARMATURE")
    m.object = arm
    o.parent = arm

bpy.ops.object.select_all(action="DESELECT")
for o in objs.values():
    o.select_set(True)
body = objs["part_16"]
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "warlock_body"
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.shade_smooth()  # see rig_orc_fbx.py: flat faces split every vertex (over the 450 KB budget)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
print("TRIS", sum(len(p.vertices) - 2 for p in body.data.polygons), "VERTS", len(body.data.vertices))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_tangents=False, export_image_format="JPEG", export_jpeg_quality=90, export_animations=False, export_skins=True)

if markers:
    for b in arm_data.bones:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.012, location=b.head_local, segments=8, ring_count=6)
        s = bpy.context.active_object
        mat = bpy.data.materials.new("mk")
        mat.diffuse_color = (1, 0, 0, 1)
        s.data.materials.append(mat)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_xray = True
    scene.display.shading.xray_alpha = 0.6
    scene.render.resolution_x, scene.render.resolution_y = 700, 900
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 1.3
    scene.collection.objects.link(cam)
    scene.camera = cam
    centre = Vector((0, 0, 0.56))
    for view, d in [("front", Vector((0, -1, 0))), ("side", Vector((1, 0, 0)))]:
        cam.location = centre + d * 5
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = markers.replace(".png", "_%s.png" % view)
        bpy.ops.render.render(write_still=True)

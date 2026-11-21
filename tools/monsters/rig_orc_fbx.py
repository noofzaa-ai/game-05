"""Rigs the squeezed Boss orc body (tools/monsters/squeeze_fbx.py output of the Boss's orc FBX, 19 loose parts, no armature) with a
landmark armature named like the mummy stand-in's own rig (root, hips, spine, chest, neck, head, clavicle/upper_arm/forearm/hand,
thigh/shin/foot/toe .L/.R), so tools/monsters/build_mummy_family.gd puts it on the shared 102-joint studio05 rig and makes every orc
type out of it (Boss 2026-11-21: ONE supplied body, rigged once; each type = tint, proportions, own weapon, own animations).
Skin parts (torso+arms+head, legs, boots, shoulder pads) get smooth distance weights over the bones listed for them in SMOOTH (a
boot never takes the other leg, the torso never takes a thigh); every accessory is weighted 100% to one bone (RIGID).
All parts are joined into ONE mesh with one material.
blender --background --factory-startup --python tools/monsters/rig_orc_fbx.py -- <squeezed.glb> <out.glb> [markers.png]
Landmarks are in glTF space (x = the character's LEFT, y up, z forward); the model stands centred on x = 0, feet at y = 0.
Measured from the per-part bounds (build/orc_base/parts.txt) and the front/side renders: T-ish pose, arms 45 degrees down.
"""
import sys, bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
markers = args[2] if len(args) > 2 else ""

# bone: (head, tail, parent) in glTF coordinates
BONES = {
    "root": ((0.0, 0.0, 0.0), (0.0, 0.08, 0.0), None),
    "hips": ((0.0, 0.40, 0.0), (0.0, 0.49, 0.0), "root"),
    "spine": ((0.0, 0.49, 0.0), (0.0, 0.58, 0.0), "hips"),
    "chest": ((0.0, 0.58, 0.0), (0.0, 0.70, 0.0), "spine"),
    "neck": ((0.0, 0.70, 0.0), (0.0, 0.77, 0.01), "chest"),
    "head": ((0.0, 0.77, 0.01), (0.0, 1.02, 0.01), "neck"),
    "clavicle.L": ((0.04, 0.68, 0.0), (0.16, 0.665, 0.0), "chest"),
    "upper_arm.L": ((0.16, 0.665, 0.0), (0.255, 0.57, -0.01), "clavicle.L"),
    "forearm.L": ((0.255, 0.57, -0.01), (0.375, 0.455, -0.01), "upper_arm.L"),
    "hand.L": ((0.375, 0.455, -0.01), (0.43, 0.34, 0.01), "forearm.L"),
    "clavicle.R": ((-0.04, 0.68, 0.0), (-0.16, 0.665, 0.0), "chest"),
    "upper_arm.R": ((-0.16, 0.665, 0.0), (-0.255, 0.57, -0.01), "clavicle.R"),
    "forearm.R": ((-0.255, 0.57, -0.01), (-0.375, 0.455, -0.01), "upper_arm.R"),
    "hand.R": ((-0.375, 0.455, -0.01), (-0.43, 0.34, 0.01), "forearm.R"),
    "thigh.L": ((0.105, 0.385, 0.0), (0.13, 0.225, 0.0), "hips"),
    "shin.L": ((0.13, 0.225, 0.0), (0.14, 0.07, -0.01), "thigh.L"),
    "foot.L": ((0.14, 0.07, -0.01), (0.14, 0.02, 0.07), "shin.L"),
    "toe.L": ((0.14, 0.02, 0.07), (0.14, 0.015, 0.13), "foot.L"),
    "thigh.R": ((-0.105, 0.385, 0.0), (-0.13, 0.225, 0.0), "hips"),
    "shin.R": ((-0.13, 0.225, 0.0), (-0.14, 0.07, -0.01), "thigh.R"),
    "foot.R": ((-0.14, 0.07, -0.01), (-0.14, 0.02, 0.07), "shin.R"),
    "toe.R": ((-0.14, 0.02, 0.07), (-0.14, 0.015, 0.13), "foot.R"),
}
ARM_L = ["clavicle.L", "upper_arm.L", "forearm.L"]
ARM_R = ["clavicle.R", "upper_arm.R", "forearm.R"]
# smooth-weighted parts -> the bones they may take
SMOOTH = {
    "part_12": ["hips", "spine", "chest", "neck", "head"] + ARM_L + ARM_R,  # torso, vest, arms to the wrist, head and face
    "part_14": ["hips", "spine", "thigh.L", "shin.L", "thigh.R", "shin.R"],  # the legs (trousers)
    "part_0": ["shin.L", "foot.L", "toe.L"],  # left boot
    "part_6": ["shin.R", "foot.R", "toe.R"],  # right boot
    "part_2": ["clavicle.L", "upper_arm.L"],  # left shoulder pad
    "part_1": ["clavicle.R", "upper_arm.R"],  # right shoulder pad
}
# rigid accessories (from the per-part contact sheet, tools/monsters/part_sheet.py)
RIGID = {
    "part_3": "head",        # mohawk
    "part_11": "head",       # ear
    "part_4": "forearm.L",   # left bracer
    "part_5": "forearm.R",   # right bracer
    "part_17": "hand.L",     # left hand
    "part_16": "hand.R",     # right hand
    "part_10": "hips",       # belt
    "part_13": "hips",       # belt stone buckle
    "part_7": "hips",        # belt side strap R
    "part_8": "hips",        # belt side strap L
    "part_9": "chest",       # vest side strap
    "part_15": "hips",       # loincloth front
    "part_18": "hips",       # loincloth back
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

# smooth distance weights (see rig_boss_fbx.py): the (up to 3) nearest allowed bone segments, 1/(d+0.01)^3, only bones within
# 1.8x the nearest distance + 2 cm, so joints fall off over a few cm
for part, allowed in SMOOTH.items():
    o = objs[part]
    for n in allowed:
        o.vertex_groups.new(name=n)
    for v in o.data.vertices:
        ds = []
        for n in allowed:
            a, c = segs[n]
            ab = c - a
            t = max(0.0, min(1.0, (v.co - a).dot(ab) / ab.length_squared))
            ds.append(((a + ab * t - v.co).length, n))
        ds.sort()
        near = ds[0][0]
        pick = [(d, n) for d, n in ds[:3] if d <= near * 1.8 + 0.02]
        ws = [1.0 / (d + 0.01) ** 3 for d, n in pick]
        tot = sum(ws)
        for (d, n), w in zip(pick, ws):
            o.vertex_groups[n].add([v.index], w / tot, "REPLACE")
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
body = objs["part_12"]
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "orc_body"
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
# smooth shading: flat faces split every vertex per face in glTF (6.9k vertices for 3.9k triangles, over the 450 KB model budget);
# smooth keeps one vertex per UV island corner. The game's toon shading and outline give the faceted read back.
bpy.ops.object.shade_smooth()
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

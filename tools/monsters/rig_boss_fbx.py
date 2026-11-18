"""Rigs the squeezed Pharaoh High Wizard (tools/monsters/squeeze_fbx.py output, loose parts, no armature) with a landmark armature
named like the mummy stand-in's own rig (root, hips, spine, chest, neck, head, clavicle/upper_arm/forearm/hand, thigh/shin/foot/toe .L/.R),
so tools/monsters/build_mummy_family.gd can put it on the shared 102-joint studio05 rig exactly as it does the stand-in.
The body (one fused mesh) gets Blender's heat weights; every accessory is weighted 100% to one bone (table PARTS).
The parts are all joined into one mesh with one material.
blender --background --factory-startup --python tools/monsters/rig_boss_fbx.py -- <squeezed.glb> <out.glb> [markers.png]
Landmarks are in glTF space (x left of the character = +x, y up, z forward), before centring; the model is centred on its feet.
"""
import sys, os, bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
markers = args[2] if len(args) > 2 else ""
CENTRE_X = 0.034  # the feet centre in x (the staff makes the bounds lopsided)

# bone: (head, tail, parent) in glTF coordinates
BONES = {
    "root": ((0.034, 0.0, 0.0), (0.034, 0.08, 0.0), None),
    "hips": ((0.034, 0.32, -0.01), (0.034, 0.40, -0.01), "root"),
    "spine": ((0.034, 0.40, -0.01), (0.034, 0.49, -0.01), "hips"),
    "chest": ((0.034, 0.49, -0.01), (0.034, 0.59, -0.01), "spine"),
    "neck": ((0.034, 0.59, -0.01), (0.034, 0.64, 0.0), "chest"),
    "head": ((0.034, 0.64, 0.0), (0.034, 0.95, 0.0), "neck"),
    "clavicle.L": ((0.07, 0.57, -0.01), (0.15, 0.56, -0.01), "chest"),
    "upper_arm.L": ((0.15, 0.56, -0.01), (0.235, 0.48, 0.0), "clavicle.L"),
    "forearm.L": ((0.235, 0.48, 0.0), (0.29, 0.415, 0.0), "upper_arm.L"),
    "hand.L": ((0.29, 0.415, 0.0), (0.33, 0.35, 0.0), "forearm.L"),
    "clavicle.R": ((-0.002, 0.57, -0.01), (-0.08, 0.56, -0.01), "chest"),
    "upper_arm.R": ((-0.08, 0.56, -0.01), (-0.17, 0.49, 0.03), "clavicle.R"),
    "forearm.R": ((-0.17, 0.49, 0.03), (-0.235, 0.46, 0.07), "upper_arm.R"),
    "hand.R": ((-0.235, 0.46, 0.07), (-0.29, 0.44, 0.1), "forearm.R"),
    "thigh.L": ((0.15, 0.31, 0.0), (0.15, 0.17, 0.0), "hips"),
    "shin.L": ((0.15, 0.17, 0.0), (0.15, 0.06, -0.015), "thigh.L"),
    "foot.L": ((0.15, 0.06, -0.015), (0.15, 0.015, 0.055), "shin.L"),
    "toe.L": ((0.15, 0.015, 0.055), (0.15, 0.012, 0.09), "foot.L"),
    "thigh.R": ((-0.083, 0.31, 0.0), (-0.083, 0.17, 0.0), "hips"),
    "shin.R": ((-0.083, 0.17, 0.0), (-0.083, 0.06, -0.015), "thigh.R"),
    "foot.R": ((-0.083, 0.06, -0.015), (-0.083, 0.015, 0.055), "shin.R"),
    "toe.R": ((-0.083, 0.015, 0.055), (-0.083, 0.012, 0.09), "foot.R"),
}
# accessory part -> bone (from the per-part contact sheet: tools/monsters/part_sheet.py)
PARTS = {
    "part_0": "hips",      # belt gem
    "part_1": "chest",     # collar
    "part_2": "hips",      # tabard edge
    "part_3": "head",      # nemes
    "part_4": "hand.L",    # left fist
    "part_5": "hand.R",    # serpent staff
    "part_6": "head",      # cobra head (crown)
    "part_7": "hips",      # tabard tip
    "part_8": "hand.R",    # staff foot spike
    "part_10": "head",     # forehead gem
    "part_11": "head",     # cobra neck
    "part_12": "hips",     # belt
    "part_13": "head",     # nemes back
    "part_14": "hand.R",   # right fist
    "part_15": "head",     # face
    "part_16": "hand.R",   # purple orb (kept as its own object, glow material)
    "part_17": "hips",     # side panel
    "part_18": "hips",     # tabard back
}
BODY = "part_9"


def bl(p):
    """glTF (x, y up, z forward) -> Blender (x, -z, y), centred on the feet."""
    return Vector((p[0] - CENTRE_X, -p[2], p[1]))


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = {o.name.split(".")[0]: o for o in bpy.data.objects if o.type == "MESH"}
for o in objs.values():
    o.location.x -= CENTRE_X
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

# the body: smooth distance weights (Blender's heat weighting fails on this fused, non-manifold mesh: 0 of 1790 vertices got a
# weight). Each vertex blends the (up to 3) nearest deform bone segments, weight 1/(d+0.01)^3, only bones within 1.8x the nearest
# distance + 2 cm, so joints fall off over a few cm and a leg never inherits the other leg or the torso far away.
arm_data.bones["root"].use_deform = False
body = objs[BODY]
segs = {b.name: (b.head_local, b.tail_local) for b in arm_data.bones if b.use_deform}
for n in segs:
    body.vertex_groups.new(name=n)
for v in body.data.vertices:
    ds = []
    for n, (a, c) in segs.items():
        ab = c - a
        t = max(0.0, min(1.0, (v.co - a).dot(ab) / ab.length_squared))
        ds.append(((a + ab * t - v.co).length, n))
    ds.sort()
    near = ds[0][0]
    pick = [(d, n) for d, n in ds[:3] if d <= near * 1.8 + 0.02]
    ws = [1.0 / (d + 0.01) ** 3 for d, n in pick]
    tot = sum(ws)
    for (d, n), w in zip(pick, ws):
        body.vertex_groups[n].add([v.index], w / tot, "REPLACE")
m = body.modifiers.new("arm", "ARMATURE")
m.object = arm
body.parent = arm
print("BODY smooth weights on", len(body.data.vertices), "vertices")

for part, bone in PARTS.items():
    o = objs[part]
    g = o.vertex_groups.new(name=bone)
    g.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
    m = o.modifiers.new("arm", "ARMATURE")
    m.object = arm
    o.parent = arm

# ONE mesh for everything (one material: the orb is a flat purple patch of the atlas), so the game model has one body surface
bpy.ops.object.select_all(action="DESELECT")
for name, o in objs.items():
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "wizard_body"
orb = body

# limit to 4 normalised influences
for o in (body,):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)

print("TRIS", sum(len(p.vertices) - 2 for o in (body,) for p in o.data.polygons))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, export_tangents=False, export_image_format="JPEG", export_jpeg_quality=90, export_animations=False, export_skins=True)

if markers:
    # joint markers (small spheres) over the flat-textured model, front and side, to check the landmark placement
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

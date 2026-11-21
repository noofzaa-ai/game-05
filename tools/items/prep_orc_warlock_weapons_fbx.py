"""The Boss's real Orc Warlock SWORD and SHIELD (warlock-ss.fbx, 2026-11-21: 21 loose parts, 2.43 M triangles, no rig, one
4096 PBR set) reduced to game pieces, read only on the source.
blender --background --factory-startup --python tools/items/prep_orc_warlock_weapons_fbx.py -- <fbx> <out_dir>
Parts: the sword = every part left of x = -0.25 (blade, guard, collar, grip + ring pommel), the shield = the rest (kite board,
rim and rivets, boss, horns, drapes, back straps and handle).
Writes to <out_dir> (canonical frames, source metres, glTF Y up):
  sword_hi.glb / sword_lo.glb    grip centre at the origin, blade along +Y, blade width along X
  shield_hi.glb / shield_lo.glb  board centre at the origin, top along +Y, face toward +Z, across X
  sword.png / shield.png         the base colour re-baked into one compact UV per weapon (512 px), purple repainted brown
                                 (*_256.png: the shipped size, player items and the monster pieces)
  render_*.png                   flat textured looks of the hi meshes with the new texture
hi = the player items (<= 1500 triangles each), lo = the monster's pieces (the monster model's 5,000 triangle / 450 KB budget).
Next: python -I tools/items/build_orc_warlock_weapons.py (player GLBs) and build_mummy_family.gd -- orc_warlock (monster).
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
fbx, out_dir = args[0], args[1]
os.makedirs(out_dir, exist_ok=True)
TARGET = {"sword": (760, 190), "shield": (1300, 250)}  # lo: the monster file's 450 KB (no texture) budget leaves ~40 KB  # (hi, lo) triangles
ORIGIN = {"sword": Vector((-0.427, 0.005, 0.20)), "shield": Vector((0.182, 0.0, 0.443))}  # grip centre / board centre (Blender)
TEX = 512

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mat = bpy.data.materials[0]
src_img = None
for n in mat.node_tree.nodes:
    if n.type == "TEX_IMAGE" and n.image and not any(k in n.image.name for k in ("normal", "rough", "metal")):
        src_img = n.image
print("source albedo", src_img.name, tuple(src_img.size))


def max_x(o):
    return max((o.matrix_world @ Vector(c)).x for c in o.bound_box)


groups = {"sword": [o for o in meshes if max_x(o) < -0.25], "shield": [o for o in meshes if max_x(o) >= -0.25]}
print({k: sorted(o.name for o in v) for k, v in groups.items()})


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def decimate(o, target):
    m = o.modifiers.new("dec", "DECIMATE")
    m.decimate_type = "COLLAPSE"
    m.ratio = min(1.0, target / max(1, tris(o)))
    m.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="dec")


def only(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def recolour(px):
    """The monster's rule (tools/monsters/rig_warlock_fbx.py): every purple pixel becomes warm earth brown (hue 24-36)."""
    rgb = px[..., :3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 1e-5, (mx - mn) / np.maximum(mx, 1e-5), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.degrees(np.arctan2(np.sqrt(3.0) * (g - b), 2.0 * r - g - b)) % 360.0
    purple = ((hue >= 245.0) | (hue < 5.0)) & (sat > 0.12) & (b > g)
    v = mx * 0.82
    t = np.clip((mx - 0.5) / 0.3, 0.0, 1.0)
    h6 = (24.0 + 12.0 * t) / 60.0
    c = v * (0.52 + 0.08 * t)
    x = c * (1.0 - np.abs(h6 % 2.0 - 1.0))
    brown = np.stack([v, v - c + x, v - c], -1)
    rgb[purple] = brown[purple]
    px[..., :3] = rgb
    return int(purple.sum())


scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 1
for key, objs in groups.items():
    only(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = key
    before = tris(o)
    decimate(o, TARGET[key][0])
    # the new compact UV for the bake, then bake the source base colour through the old UV
    old_uv = o.data.uv_layers[0].name
    new_uv = o.data.uv_layers.new(name="bake")
    o.data.uv_layers.active = new_uv
    only(o)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.012, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    m = bpy.data.materials.new(key + "_bake")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = old_uv
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = src_img
    emit = nt.nodes.new("ShaderNodeEmission")
    outn = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(uvn.outputs["UV"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], outn.inputs["Surface"])
    target = bpy.data.images.new(key + "_baked", TEX, TEX, alpha=False)
    tnode = nt.nodes.new("ShaderNodeTexImage")
    tnode.image = target
    nt.nodes.active = tnode
    o.data.materials.clear()
    o.data.materials.append(m)
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
    px = np.array(target.pixels[:], dtype=np.float32).reshape(TEX, TEX, 4)
    n_purple = recolour(px)
    target.pixels = px.ravel().tolist()
    target.filepath_raw = os.path.join(out_dir, key + ".png")
    target.file_format = "PNG"
    target.save()
    small = target.copy()
    small.scale(256, 256)
    small.filepath_raw = os.path.join(out_dir, key + "_256.png")
    small.file_format = "PNG"
    small.save()
    # display material for the renders / export: the baked texture on the new UV
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    tex2 = nt.nodes.new("ShaderNodeTexImage")
    tex2.image = target
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    outn = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tex2.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], outn.inputs["Surface"])
    o.data.uv_layers.remove(o.data.uv_layers[old_uv])
    # canonical frame: the origin point at the world origin (glTF export maps Blender (x, y, z) to (x, z, -y))
    o.location = -ORIGIN[key]
    only(o)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    bpy.ops.object.shade_smooth_by_angle(angle=0.7)
    hi_tris = tris(o)
    lo = o.copy()
    lo.data = o.data.copy()
    lo.name = key + "_lo"
    scene.collection.objects.link(lo)
    decimate(lo, TARGET[key][1])
    for obj, tag in ((o, "hi"), (lo, "lo")):
        only(obj)
        bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "%s_%s.glb" % (key, tag)), export_format="GLB", use_selection=True,
                                  export_yup=True, export_tangents=False, export_materials="NONE", export_skins=False, export_animations=False)
    lo.hide_render = True
    print("WEAPON %s source %d tris -> hi %d, lo %d; purple px repainted %d" % (key, before, hi_tris, tris(lo), n_purple))

# looks: front (-Y) and back, flat textured
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
for o in bpy.data.objects:
    o.hide_render = o.type != "MESH" or o.name.endswith("_lo")
sw, sh = bpy.data.objects["sword"], bpy.data.objects["shield"]
sw.location = Vector((-0.45, 0, -0.1))
sh.location = Vector((0.15, 0, 0.0))
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 1.15
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
centre = Vector((-0.1, 0.0, 0.05))
for name, d in [("front", Vector((0, -1, 0))), ("back", Vector((0, 1, 0))), ("side", Vector((1, 0, 0)))]:
    cam.location = centre + d * 4.0
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(out_dir, "render_%s.png" % name)
    bpy.ops.render.render(write_still=True)

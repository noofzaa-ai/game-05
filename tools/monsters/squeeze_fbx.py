"""Squeeze a high-poly monster FBX (loose parts, no rig) into a game-size mesh, read only on the source.
blender --background --factory-startup --python tools/monsters/squeeze_fbx.py -- <fbx> <out_dir> <target_tris> [render]
Writes <out_dir>/squeezed.glb (Y up, +Z forward as glTF, parts kept as separate objects, decimated so the whole file has about
<target_tris> triangles, each part in proportion to its surface area with a floor so small parts keep their shape),
<out_dir>/albedo.png (the base colour map shrunk to 1024), <out_dir>/parts.txt (per part: triangles before/after, bounds)
and with `render` front/side/back/top PNGs (flat textured, workbench) to look at.
"""
import sys, os, math, bpy, bmesh
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
fbx, out_dir, target = args[0], args[1], int(args[2])
render = len(args) > 3 and args[3] == "render"
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def area(o):
    return sum(p.area for p in o.data.polygons)
areas = {o.name: area(o) for o in meshes}
total_area = sum(areas.values())
log = []
for o in meshes:
    before = sum(len(p.vertices) - 2 for p in o.data.polygons)
    want = max(60, int(target * areas[o.name] / total_area))
    ratio = min(1.0, want / max(1, before))
    m = o.modifiers.new("dec", "DECIMATE")
    m.decimate_type = "COLLAPSE"
    m.ratio = ratio
    m.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="dec")
    after = len(o.data.polygons)
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    log.append("%s before=%d after=%d area=%.4f min=%s max=%s" % (o.name, before, after, areas[o.name], tuple(round(v, 3) for v in mn), tuple(round(v, 3) for v in mx)))
total = sum(len(o.data.polygons) for o in meshes)
log.append("TOTAL %d" % total)
open(os.path.join(out_dir, "parts.txt"), "w").write("\n".join(log) + "\n")
print("\n".join(log))

# the base colour map only, 1024 px; the material keeps just that map (no PBR maps are shipped)
mat = bpy.data.materials[0]
base = None
for n in mat.node_tree.nodes:
    if n.type == "TEX_IMAGE" and n.image and "normal" not in n.image.name and "rough" not in n.image.name and "metal" not in n.image.name:
        base = n
img = base.image
img.scale(1024, 1024)
img.filepath_raw = os.path.join(out_dir, "albedo.png")
img.file_format = "PNG"
img.save()
for n in list(mat.node_tree.nodes):
    if n.type == "TEX_IMAGE" and n != base:
        mat.node_tree.nodes.remove(n)
bsdf = [n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
mat.node_tree.links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.9
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "squeezed.glb"), export_format="GLB", export_yup=True, export_tangents=False, export_image_format="JPEG", export_jpeg_quality=85)

if render:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 700
    scene.render.resolution_y = 900
    lo = Vector((min((o.matrix_world @ Vector(c)).x for o in meshes for c in o.bound_box), 0, 0))
    zmax = max((o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = zmax * 1.15
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    centre = Vector((0.0, 0.0, zmax * 0.5))
    # Blender -Y is the model's front after the FBX import (glTF +Z)
    for name, d in [("front", Vector((0, -1, 0))), ("side", Vector((1, 0, 0))), ("back", Vector((0, 1, 0))), ("top", Vector((0, -0.45, 1)).normalized())]:
        cam.location = centre + d * 5.0
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, "render_%s.png" % name)
        bpy.ops.render.render(write_still=True)

"""Contact sheet of the loose parts of a glb (each part alone, front and side, flat textured) so each part can be named.
blender --background --factory-startup --python tools/monsters/part_sheet.py -- <glb> <out.png>"""
import sys, os, bpy
from mathutils import Vector

glb, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
meshes = sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: int(o.name.split("_")[1].split(".")[0]) if o.name.split("_")[-1].split(".")[0].isdigit() else 0)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "TEXTURE"
scene.render.film_transparent = False
W, H = 200, 260
scene.render.resolution_x, scene.render.resolution_y = W, H
zmax = max((o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = zmax * 1.15
scene.collection.objects.link(cam)
scene.camera = cam
centre = Vector((0, 0, zmax * 0.5))
tiles = []
for o in meshes:
    for other in meshes:
        other.hide_render = other != o
    for view, d in [("f", Vector((0, -1, 0))), ("s", Vector((1, 0, 0)))]:
        cam.location = centre + d * 5
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(os.path.dirname(out), "_tile_%s_%s.png" % (o.name, view))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        tiles.append(path)
cols = 8
rows = (len(tiles) + cols - 1) // cols
sheet = bpy.data.images.new("sheet", W * cols, H * rows)
px = [0.0] * (W * cols * H * rows * 4)
for k, path in enumerate(tiles):
    im = bpy.data.images.load(path)
    p = list(im.pixels)
    cx, cy = (k % cols) * W, (rows - 1 - k // cols) * H
    for y in range(H):
        row = (cy + y) * W * cols + cx
        px[row * 4:(row + W) * 4] = p[y * W * 4:(y + 1) * W * 4]
sheet.pixels = px
sheet.filepath_raw = out
sheet.file_format = "PNG"
sheet.save()
print("ORDER", [o.name for o in meshes])

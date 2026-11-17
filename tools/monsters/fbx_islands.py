"""Connected-part analysis + orthographic previews of the single mesh in a modular FBX.
blender --background --factory-startup --python tools/monsters/fbx_islands.py -- <fbx> <out_dir>"""
import sys, os, bpy, bmesh, json
from mathutils import Vector
fbx, out = sys.argv[sys.argv.index("--") + 1:][:2]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
me = ob.data
bm = bmesh.new(); bm.from_mesh(me); bm.transform(ob.matrix_world)
bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
seen = set(); islands = []
for v in bm.verts:
    if v.index in seen: continue
    stack = [v]; seen.add(v.index); comp = []
    while stack:
        x = stack.pop(); comp.append(x)
        for e in x.link_edges:
            y = e.other_vert(x)
            if y.index not in seen: seen.add(y.index); stack.append(y)
    islands.append(comp)
rows = []
for k, comp in enumerate(islands):
    idx = {v.index for v in comp}
    faces = {f for v in comp for f in v.link_faces}
    tris = sum(len(f.verts) - 2 for f in faces)
    mn = Vector((min(v.co.x for v in comp), min(v.co.y for v in comp), min(v.co.z for v in comp)))
    mx = Vector((max(v.co.x for v in comp), max(v.co.y for v in comp), max(v.co.z for v in comp)))
    uvl = bm.loops.layers.uv.active
    us = [l[uvl].uv for f in faces for l in f.loops]
    rows.append((tris, k, mn, mx, (min(u.x for u in us), min(u.y for u in us), max(u.x for u in us), max(u.y for u in us))))
rows.sort(key=lambda r: -r[0])
print("ISLANDS", len(rows))
for tris, k, mn, mx, uv in rows[:60]:
    print("island %3d tris=%5d size=(%.3f %.3f %.3f) min=(%.3f %.3f %.3f) uvbox=(%.2f %.2f %.2f %.2f)" % (k, tris, *(mx - mn), *mn, *uv))
print("small islands (<20 tris):", sum(1 for r in rows if r[0] < 20))
# previews
for img in bpy.data.images: pass
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 1400; scene.render.resolution_y = 1000
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.collection.objects.link(cam)
cam.data.type = "ORTHO"; scene.camera = cam
bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
c = sum(bb, Vector()) / 8; size = max((max(v[i] for v in bb) - min(v[i] for v in bb)) for i in range(3))
cam.data.ortho_scale = size * 1.15
views = {"top": (Vector((0, 0, 5)), (0, 0, 0)), "front": (Vector((0, -5, 0)), (1.5708, 0, 0)), "side": (Vector((5, 0, 0)), (1.5708, 0, 1.5708))}
for name, (off, rot) in views.items():
    cam.location = c + off; cam.rotation_euler = rot
    scene.render.filepath = os.path.join(out, "fbx_" + name + ".png")
    bpy.ops.render.render(write_still=True)
print("bbox world", [round(v, 3) for v in (c - Vector((size/2,)*3))], "size", size)

"""Render front / three-quarter / side previews of a GLB in Blender (EEVEE).

    blender -b --factory-startup --python tools/blender/preview_chibi_v2.py -- <glb> <out_dir>
"""
import bpy, sys, os, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
GLB, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

# bounds of all meshes (world)
mins = Vector((1e9, 1e9, 1e9))
maxs = Vector((-1e9, -1e9, -1e9))
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    for v in o.data.vertices:
        p = o.matrix_world @ v.co
        for i in range(3):
            mins[i] = min(mins[i], p[i]); maxs[i] = max(maxs[i], p[i])
centre = (mins + maxs) / 2
height = maxs.z - mins.z

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 700
scene.render.resolution_y = 950
scene.render.film_transparent = False
world = bpy.data.worlds.new("W"); scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.17, 0.19, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0

# key + fill light
for ang, en in [((-35, 25, 0), 3.0), ((-20, -120, 0), 1.2)]:
    d = bpy.data.lights.new("L", "SUN"); d.energy = en
    lo = bpy.data.objects.new("L", d); scene.collection.objects.link(lo)
    lo.rotation_euler = tuple(math.radians(a) for a in ang)

cam_data = bpy.data.cameras.new("C"); cam_data.lens = 70
cam = bpy.data.objects.new("C", cam_data); scene.collection.objects.link(cam)
scene.camera = cam

dist = height * 2.2
# front = -Y (face points -Y), so camera at -Y looking +Y
angles = {
    "front": Vector((0, -dist, 0)),
    "threequarter": Vector((-dist * 0.72, -dist * 0.72, 0)),
    "side": Vector((-dist, 0, 0)),
}
target = Vector((centre.x, centre.y, centre.z + height * 0.08))
for name, off in angles.items():
    cam.location = target + off + Vector((0, 0, height * 0.05))
    dirv = (target - cam.location).normalized()
    cam.rotation_euler = dirv.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, "blender_%s.png" % name)
    bpy.ops.render.render(write_still=True)
print("PREVIEW_DONE", OUT)

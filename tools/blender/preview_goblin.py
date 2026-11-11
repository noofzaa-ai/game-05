# Preview renders for the goblin (run after build_goblin.py):
#   blender -b art_source/monsters/goblin/goblin.blend -P tools/blender/preview_goblin.py
# Writes art_source/monsters/goblin/preview/{views,game_cam,deform}.png (contact sheets).
import bpy, os, math, subprocess, sys
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art_source/monsters/goblin/preview")
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
rig = bpy.data.objects["goblin_rig"]
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "art/characters/chibi-studio/chibi_base_animated.glb"))
chibi = [o for o in bpy.context.selected_objects]
for o in chibi:
    if o.name.startswith("Icosphere") or "Boy " in o.name or "Short swept" in o.name or "fringe" in o.name.lower() or "Side lock" in o.name:
        o.hide_render = True
for o in chibi:
    if o.parent is None: o.location.x += 0.75

sc.render.engine = 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = sc.render.resolution_y = 560
sc.render.film_transparent = False
w = sc.world or bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.57, 0.52, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 3.0; sun.rotation_euler = (math.radians(40), 0, math.radians(25))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'

def shot(path, loc, target, scale):
    cam.location = loc; cam.data.ortho_scale = scale
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = path; bpy.ops.render.render(write_still=True)

def show_chibi(v):
    for o in chibi:
        if o.type == 'MESH' and not (o.name.startswith("Icosphere") or "Boy " in o.name or "Short swept" in o.name
                                     or "fringe" in o.name.lower() or "Side lock" in o.name):
            o.hide_render = not v

files = []
sc.frame_set(1)
for nm, loc in (("front", (0.375, -5, 0.75)), ("side", (5, 0, 0.75)), ("back", (0.375, 5, 0.75))):
    p = os.path.join(OUT, f"_v_{nm}.png"); shot(p, loc, (0.375 if nm != "side" else 0, 0, 0.75), 2.0); files.append(p)
# in-game style: steep top-down (camera ~60 deg pitch), perspective-ish ortho
p = os.path.join(OUT, "_v_game.png"); shot(p, (0.375, -2.6, 4.6), (0.375, 0, 0.4), 2.0); files.append(p)
show_chibi(False)
poses = sc.get("deform_test_poses", "").split(",")
dfiles = []
for i, nm in enumerate(poses):
    if i == 0: continue
    sc.frame_set(1 + i * 10)
    for tag, loc in (("f", (0, -5, 0.5)), ("q", (2.6, -3.2, 2.2)), ("s", (5, 0.3, 0.6))):
        p = os.path.join(OUT, f"_d_{nm}_{tag}.png"); shot(p, loc, (0, 0, 0.45), 1.35); dfiles.append(p)
sc.frame_set(1)
p = os.path.join(OUT, "_d_close_face.png"); shot(p, (0.35, -3, 0.95), (0, 0, 0.72), 0.75); dfiles.append(p)
p = os.path.join(OUT, "_d_close_top.png"); shot(p, (0, -0.4, 4), (0, 0, 0.5), 1.35); dfiles.append(p)
print("PREVIEW", ";".join(files), "|", ";".join(dfiles))

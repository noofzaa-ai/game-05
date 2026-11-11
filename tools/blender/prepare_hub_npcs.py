"""Convert supplied camp NPCs without modifying their FBX sources. Run with Blender."""
import bpy
import sys
from pathlib import Path
from mathutils import Matrix, Vector
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art/npcs'
OUT.mkdir(parents=True, exist_ok=True)
ASSETS = [('Qboard', 'quest_board'), ('storage', 'storage'), ('backsmith', 'blacksmith'), ('merchance', 'merchant'), ('capcut', 'tailor')]
selected = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
for source, name in ASSETS:
    if selected and name not in selected:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(ROOT.parent / 'assets' / (source + '.fbx')))
    objects = list(bpy.context.scene.objects)
    meshes = [o for o in objects if o.type == 'MESH']
    points = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    scale = 1.6 / (hi.z - lo.z)
    wrapper = bpy.data.objects.new('NPC', None)
    bpy.context.collection.objects.link(wrapper)
    for obj in objects:
        if obj.parent is None:
            world = obj.matrix_world.copy()
            obj.parent = wrapper
            obj.matrix_world = world
    wrapper.matrix_world = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-(lo.x+hi.x)/2, -(lo.y+hi.y)/2, -lo.z)))
    for image in bpy.data.images:
        if image.size[0] and image.size[1]:
            # Bound derivative texture memory; source FBX remains untouched.
            largest = max(image.size)
            cap = 512 if any(role in image.name.lower() for role in ("normal", "metallic", "roughness", "occlusion")) else 1024
            if largest > cap:
                image.scale(round(image.size[0]*cap/largest), round(image.size[1]*cap/largest))
            image.pack()
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + '.glb')), export_format='GLB', export_animations=False)
    print('NPC_EXPORTED', name, 'triangles', sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes), 'bones', [b.name for o in objects if o.type == 'ARMATURE' for b in o.data.bones], flush=True)

"""Blender inspection of a modular monster FBX. blender --background --factory-startup --python tools/monsters/inspect_fbx.py -- <fbx>"""
import sys, bpy, bmesh
from mathutils import Vector
fbx = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)
print("=== OBJECTS", len(bpy.data.objects))
dg = bpy.context.evaluated_depsgraph_get()
tot = 0
def depth(o):
    d = 0
    while o.parent: o = o.parent; d += 1
    return d
for o in sorted(bpy.data.objects, key=lambda o: (depth(o), o.name)):
    line = "%s%s [%s] parent=%s loc=%s rot=%s scl=%s" % ("  " * depth(o), o.name, o.type, o.parent.name if o.parent else None, tuple(round(v, 3) for v in o.location), tuple(round(v, 1) for v in (o.rotation_euler[0]*57.3, o.rotation_euler[1]*57.3, o.rotation_euler[2]*57.3)), tuple(round(v, 3) for v in o.scale))
    if o.type == "MESH":
        me = o.data
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        tot += tris
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        vg = len(o.vertex_groups)
        mods = [m.type + ":" + (m.object.name if getattr(m, "object", None) else "") for m in o.modifiers]
        bm = bmesh.new(); bm.from_mesh(me)
        nonman = sum(1 for e in bm.edges if not e.is_manifold)
        bm.free()
        line += "\n%s    verts=%d tris=%d mats=%s vgroups=%d mods=%s nonmanifold_edges=%d uv=%s bbox_min=%s bbox_max=%s" % ("  " * depth(o), len(me.vertices), tris, [m.name if m else None for m in me.materials], vg, mods, nonman, [u.name for u in me.uv_layers], tuple(round(v, 3) for v in mn), tuple(round(v, 3) for v in mx))
    if o.type == "ARMATURE":
        line += "\n%s    bones=%d" % ("  " * depth(o), len(o.data.bones))
    print(line)
print("=== TOTAL TRIS", tot)
print("=== ARMATURES")
for a in bpy.data.armatures:
    print(a.name, len(a.bones))
    for b in a.bones:
        print("   ", b.name, "parent=", b.parent.name if b.parent else None, "head=", tuple(round(v, 3) for v in b.head_local))
print("=== MATERIALS")
for m in bpy.data.materials:
    imgs = []
    if m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                imgs.append((n.image.name, tuple(n.image.size), n.image.packed_file is not None, n.image.filepath))
    print(m.name, "users=", m.users, imgs)
print("=== IMAGES")
for i in bpy.data.images:
    print(i.name, tuple(i.size), "packed" if i.packed_file else "ext", i.filepath, (len(i.packed_file.data) if i.packed_file else 0))
print("=== ACTIONS", [a.name for a in bpy.data.actions])
print("=== SCENE", bpy.context.scene.unit_settings.system, bpy.context.scene.unit_settings.scale_length)

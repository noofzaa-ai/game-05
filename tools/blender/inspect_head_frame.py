"""Inspect the attach_head bone frame (rest, model space) in the source chibi skeleton, and the
vertex bounds + materials of an existing model-team face GLB, so we can place chibi_v2 faces in
the SAME attach_head frame the model team's faces use.

    blender -b --factory-startup --python tools/blender/inspect_head_frame.py -- <src_glb> <face_glb>
"""
import bpy, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, FACE = argv[0], argv[1]


def dump_bone(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    print("ARMATURE matrix_world:", [round(v, 4) for v in sum([list(r) for r in arm.matrix_world], [])])
    eb = arm.data.bones
    for bn in ["attach_head", "Head", "Neck"]:
        if bn in eb:
            b = eb[bn]
            head_ws = arm.matrix_world @ b.head_local
            tail_ws = arm.matrix_world @ b.tail_local
            print("BONE %s head_local=%s tail_local=%s" % (bn, [round(v, 4) for v in b.head_local], [round(v, 4) for v in b.tail_local]))
            print("BONE %s head_world=%s tail_world=%s" % (bn, [round(v, 4) for v in head_ws], [round(v, 4) for v in tail_ws]))
            # bone matrix (rest, armature space)
            m = b.matrix_local
            print("BONE %s matrix_local=\n%s" % (bn, m))


def dump_face():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=FACE)
    for o in bpy.data.objects:
        if o.type == "MESH":
            mn = [m.name for m in o.data.materials]
            vs = [o.matrix_world @ v.co for v in o.data.vertices]
            if not vs:
                continue
            mins = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
            maxs = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
            print("FACEMESH %s verts=%d tris~%d mats=%s" % (o.name, len(o.data.vertices), sum(len(p.vertices) - 2 for p in o.data.polygons), mn))
            print("  bounds min=%s max=%s center=%s" % ([round(v, 4) for v in mins], [round(v, 4) for v in maxs], [round(v, 4) for v in (mins + maxs) / 2]))
            print("  parent=%s type=%s" % (o.parent.name if o.parent else None, o.parent.type if o.parent else None))
        for m in bpy.data.materials:
            if m.use_nodes:
                b = m.node_tree.nodes.get("Principled BSDF")
                if b:
                    print("  MAT %s base=%s" % (m.name, [round(v, 3) for v in b.inputs["Base Color"].default_value]))


print("==== SOURCE SKELETON ====")
dump_bone("attach_head")
print("==== EXISTING FACE GLB ====")
dump_face()
print("INSPECT_DONE")

"""Inspect art/characters/chibi-studio/chibi_base_animated.glb and dump the contract
(armature bones + rest matrices, meshes, materials, vertex groups, triangle counts) as JSON.

    blender -b --factory-startup --python tools/blender/inspect_chibi.py -- <glb> <out.json>
"""
import bpy, sys, json

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

report = {"objects": [], "armature": None, "materials": [], "meshes": [], "actions": []}

for obj in bpy.data.objects:
    report["objects"].append({"name": obj.name, "type": obj.type,
                              "parent": obj.parent.name if obj.parent else None})

arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if arm:
    bones = []
    for b in arm.data.bones:
        ml = b.matrix_local
        bones.append({
            "name": b.name,
            "parent": b.parent.name if b.parent else None,
            "head": list(b.head_local),
            "tail": list(b.tail_local),
            "matrix_local": [list(row) for row in ml],
            "length": b.length,
        })
    report["armature"] = {"name": arm.name, "bone_count": len(bones), "bones": bones}

total_tris = 0
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    me = obj.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    total_tris += tris
    extras = {}
    for k in obj.keys():
        if k in ("_RNA_UI",):
            continue
        try:
            extras[k] = obj[k]
        except Exception:
            extras[k] = str(obj[k])
    for k in me.keys():
        if k in ("_RNA_UI",):
            continue
        try:
            extras["mesh:" + k] = me[k]
        except Exception:
            pass
    report["meshes"].append({
        "name": obj.name,
        "mesh_data": me.name,
        "tris": tris,
        "verts": len(me.vertices),
        "materials": [m.name if m else None for m in me.materials],
        "vertex_groups": [vg.name for vg in obj.vertex_groups],
        "extras": extras,
        "parent": obj.parent.name if obj.parent else None,
    })
report["total_tris"] = total_tris

for m in bpy.data.materials:
    bc = None
    if m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                bc = list(n.inputs["Base Color"].default_value)
    report["materials"].append({"name": m.name, "base_color": bc})

for a in bpy.data.actions:
    report["actions"].append({"name": a.name, "frame_range": list(a.frame_range)})

with open(out, "w") as f:
    json.dump(report, f, indent=2)
print("WROTE", out, "total_tris=", total_tris)

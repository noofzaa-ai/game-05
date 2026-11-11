"""Close comparison renders of the orc kit (Boss 2026-10-16): each piece from the bought source sheet (its own
4096 PBR material, untouched geometry) next to the game kit piece (art/props/orc_camp/orc_kit.glb), from the same
high three-quarter view as the game camera (8: High). Writes 800-px PNGs:

    art_source/preview/orc_kit/v2/source_<name>.png   new_<name>.png

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/orc_kit_compare.py [-- <name> ...]
"""
import bpy, math, os, sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["ORC_KIT_IMPORT"] = "1"
import build_orc_kit as K  # noqa: E402

OUT = os.path.join(K.ROOT, "art_source/preview/orc_kit/v2")
SIZE = 800


def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.render.resolution_x = sc.render.resolution_y = SIZE
    sc.eevee.taa_render_samples = 16
    sc.view_settings.view_transform = 'Standard'   # (what the texture painter's colours are; no filmic wash)
    sc.world = bpy.data.worlds.new("w")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.30, 0.31, 0.33, 1)
    bg.inputs[1].default_value = 0.8
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(45), 0, math.radians(25))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = 'ORTHO'
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc, cam


def frame(cam, lo, hi):
    """High three-quarter view from the south (-Y in Blender), 55 degrees down, like camera 8."""
    c = (lo + hi) / 2
    ext = (hi - lo).length
    pitch = math.radians(55)
    d = Vector((0, -math.cos(pitch), math.sin(pitch)))
    cam.location = c + d * ext * 3
    cam.rotation_euler = (math.radians(90) - pitch, 0, 0)
    cam.data.ortho_scale = ext * 1.05
    cam.data.clip_end = ext * 10


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    want = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(K.PROPS)
    os.makedirs(OUT, exist_ok=True)
    if os.environ.get("ORC_CMP_KIT"):   # (an older kit file: render only its pieces, e.g. ORC_CMP_PREFIX=old)
        want_src = []
    else:
        want_src = want
    # ---- source: the untouched sheet, every other prop's faces hidden by deleting them on a copy
    ob, img, nrm = K.load_source()
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    parts = K.loose_parts(bm)
    names = K.assign(parts)
    vprop = {}
    for i, p in enumerate(parts):
        for v in p:
            vprop[v.index] = names[i]
    bm.free()
    sc, cam = setup_scene()
    me = ob.data
    for name in want_src:
        ob.hide_render = True
        dup = ob.copy()
        dup.hide_render = False
        dup.data = me.copy()
        sc.collection.objects.link(dup)
        bpy.context.view_layer.objects.active = dup
        for o in bpy.context.selected_objects:
            o.select_set(False)
        dup.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='DESELECT')
        bpy.ops.object.mode_set(mode='OBJECT')
        for poly in dup.data.polygons:
            poly.select = vprop[poly.vertices[0]] != name
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.delete(type='FACE')   # (keeps the remaining faces' custom normals)
        bpy.ops.object.mode_set(mode='OBJECT')
        ob.hide_render = True
        vs = [dup.matrix_world @ v.co for v in dup.data.vertices]
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        frame(cam, lo, hi)
        render(os.path.join(OUT, "source_%s.png" % name))
        bpy.data.objects.remove(dup)
    # ---- new: the kit glb as the game gets it
    bpy.data.objects.remove(ob)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.environ.get("ORC_CMP_KIT", os.path.join(K.OUT_DIR, "orc_kit.glb")))
    kit = {o.name.split(".")[0]: o for o in bpy.data.objects if o not in before and o.type == 'MESH'}
    for o in kit.values():
        for m in o.data.materials:   # COLOR_0 multiplies the albedo in the game (stage_props.use_vertex_colors)
            nt = m.node_tree
            bsdf = nt.nodes.get("Principled BSDF")
            tex = [n for n in nt.nodes if n.type == 'TEX_IMAGE' and "normal" not in n.image.name][0]
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = o.data.color_attributes[0].name   # (COLOR_0 imports as "Color")
            mul = nt.nodes.new("ShaderNodeMix")
            mul.data_type = 'RGBA'
            mul.blend_type = 'MULTIPLY'
            mul.inputs[0].default_value = 1.0
            nt.links.new(tex.outputs["Color"], mul.inputs[6])
            nt.links.new(vc.outputs["Color"], mul.inputs[7])
            nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    for name in want:
        for n, o in kit.items():
            o.hide_render = n != name
        o = kit[name]
        vs = [o.matrix_world @ v.co for v in o.data.vertices]
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        frame(cam, lo, hi)
        render(os.path.join(OUT, os.environ.get("ORC_CMP_PREFIX", "new") + "_%s.png" % name))


main()

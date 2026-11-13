# Drawn-style repaint (tech-artist 2026-11-13, PO-approved Codex watercolour set): lays the painted sandstone tile
# (art/maps/mummy_tomb/painted/floor_tile.png, a 2x2 grid of slabs; stored as warm greyscale so it adds only the
# painting's pools, cracks and grout, and the art's own stone colour stays) onto the modelled 2 m floor slabs of a mummy
# arena, so each painted slab sits exactly on one modelled slab and the painted grout lines up with the modelled gaps.
# No new geometry: only the UVs of the slabs' upward faces change, and the two stone floor materials get the tile as
# their base colour texture (their colour factor kept, so the shading stays the art's). The original GLB is left
# untouched; the result is written next to it as <map>_painted.glb (data/maps/<map>.json points at it).
# The desert sand (gf_mummy_sand) gets the painted sand texture the same way, with UVs from world XZ (4 m per repeat).
#   blender -b --factory-startup --python tools/blender/bake_mummy_floor_tile.py -- <in.glb> <out.glb> <tile.png> <sand.png>
import bpy, bmesh, sys, os
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
src, dst, tile, sand = argv[0], argv[1], argv[2], argv[3]
SLAB = 2.0  # metres per modelled slab (tools/blender/build_mummy_stage.py: slabs 1.89-1.95 m on a 2 m grid)
FLOOR_MATERIALS = ('gf_mummy_stone', 'gf_mummy_light_stone')
SAND_MATERIAL = 'gf_mummy_sand'
SAND_METRES = 4.0
SAND_AVERAGE = 0.60  # the sand texture's mean brightness, linear (sRGB 0.80)
TILE_AVERAGE = 0.55  # the tile's mean brightness in linear colour (the shipped tile is warm greyscale, sRGB ~0.76)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob = next(o for o in bpy.data.objects if o.type == 'MESH')
me = ob.data
M = ob.matrix_world
mats = [m.name for m in me.materials]

bm = bmesh.new()
bm.from_mesh(me)
bm.faces.ensure_lookup_table()
uv_layer = bm.loops.layers.uv.active

# One island per slab (the bevelled top is several faces). Its centre picks the cell of the 2x2 painted tile, so
# neighbouring slabs use different painted slabs, like the tile itself.
seen = set()
changed = 0
for f in bm.faces:
    if f.index in seen or mats[f.material_index] not in FLOOR_MATERIALS:
        continue
    stack, island = [f], []
    while stack:
        g = stack.pop()
        if g.index in seen:
            continue
        seen.add(g.index)
        island.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h.index not in seen and h.material_index == f.material_index:
                    stack.append(h)
    ws = [M @ v.co for g in island for v in g.verts]
    lo = Vector((min(v.x for v in ws), min(v.y for v in ws)))
    hi = Vector((max(v.x for v in ws), max(v.y for v in ws)))
    size = hi - lo
    if not (1.8 < size.x < 2.1 and 1.8 < size.y < 2.1):
        continue  # not a floor slab (walls, steps, pillars keep their UVs)
    centre = (lo + hi) / 2
    # Blender Y = -glTF Z. The painted tile holds 2x2 slabs per repeat: column/row from the slab grid index.
    col = int(round((centre.x - 1.0) / SLAB)) % 2
    row = int(round((-centre.y) / SLAB)) % 2
    for g in island:
        if g.normal.z < 0.5:
            continue  # the slab's sides keep their UVs (the flat colour)
        for loop in g.loops:
            w = M @ loop.vert.co
            u = (w.x - (centre.x - SLAB / 2)) / SLAB  # 0..1 across this slab's 2 m cell
            v = ((-w.y) - (-centre.y - SLAB / 2)) / SLAB
            loop[uv_layer].uv = ((col + u) / 2.0, 1.0 - (row + v) / 2.0)
        changed += 1
sand_faces = 0
for f in bm.faces:
    if mats[f.material_index] == SAND_MATERIAL and f.normal.z > 0.5:
        for loop in f.loops:
            w = M @ loop.vert.co
            loop[uv_layer].uv = (w.x / SAND_METRES, -w.y / SAND_METRES)
        sand_faces += 1
bm.to_mesh(me)
bm.free()

images = {name: bpy.data.images.load(tile) for name in FLOOR_MATERIALS}
images[SAND_MATERIAL] = bpy.data.images.load(sand)
for m in me.materials:
    if m.name not in images:
        continue
    image = images[m.name]
    average = SAND_AVERAGE if m.name == SAND_MATERIAL else TILE_AVERAGE
    nodes = m.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = image
    # glTF multiplies the texture by the colour factor: divide the stone colour by the tile's mean brightness so
    # the floor keeps today's average brightness and only gains the painted pools, cracks and grout.
    base = bsdf.inputs['Base Color'].default_value
    mix = nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 1.0
    factor = [min(1.0, base[i] / average) for i in range(3)]
    mix.inputs['A'].default_value = (factor[0], factor[1], factor[2], 1.0)
    m.node_tree.links.new(tex.outputs['Color'], mix.inputs['B'])
    m.node_tree.links.new(mix.outputs['Result'], bsdf.inputs['Base Color'])

bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_keep_originals=True, export_animations=False,
    export_extras=True, export_lights=False, export_cameras=False)
print('BAKED slab_faces=%d sand_faces=%d -> %s' % (changed, sand_faces, dst))

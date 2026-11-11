"""Goblin Base obstacle dressing: art that encloses the map's collision boxes so the plain collider boxes
(drawn by StageView with the ink ground wash) are never seen.

Each piece is authored around the UNIT collider box  x,z in [-0.5, 0.5], y in [0, 1]  (Godot axes) and is
scaled per obstacle by tools/maps/build_goblin_base.gd to the obstacle's AABB size (x1.03 so the faces never
z-fight with the collider box that stays inside). Every piece is built to contain the whole unit box
(each has a core box that IS the unit box), so no collider face can poke through at any obstacle size.

  goblin_crate      plank crate: dark core, horizontal side planks, corner posts, rims, X braces, lid, iron caps
  goblin_stoneblock dry-stone block/pillar: staggered cut stones over a mortar core, bevelled mossy cap
  goblin_logwall    stacked log barricade for long thin obstacles (long axis = x), two sharpened end stakes

Opaque, vertex colours only (no textures, no transparency), a few hundred triangles each: one shared draw per
kind via MultiMesh in the map scene. Output (authoring, not exported): art_source/props/goblin_base/dressing/.

  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_goblin_base_dressing.py
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art_source", "props", "goblin_base", "dressing")

# Ink Garden goblin palette (muted, a little warm; reads against the olive/dirt vertex ground).
WOOD = (0.43, 0.30, 0.18)
WOOD_DARK = (0.17, 0.11, 0.07)
WOOD_FRAME = (0.30, 0.20, 0.12)
IRON = (0.15, 0.12, 0.10)
STONE = (0.42, 0.34, 0.24)
STONE_EDGE = (0.50, 0.42, 0.31)
MORTAR = (0.13, 0.12, 0.10)
MOSS = (0.27, 0.34, 0.15)
BARK = (0.29, 0.21, 0.14)
CUT = (0.62, 0.48, 0.31)


def G(x, y, z):
    """Godot (x, y-up, z) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


class Piece:
    def __init__(self, seed):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.rng = random.Random(seed)

    def jitter(self, c, amount=0.06):
        k = 1.0 + self.rng.uniform(-amount, amount)
        return tuple(min(1.0, max(0.0, v * k)) for v in c)

    def paint(self, faces, c):
        # The glTF exporter linearises colour attributes (sRGB -> linear). The palette above is written in the
        # same convention as the goblin ground's vertex colours (values the renderer uses as linear), so store the
        # sRGB encoding: the exported COLOR_0 then equals the palette value exactly.
        s = tuple((12.92 * v) if v <= 0.0031308 else (1.055 * v ** (1 / 2.4) - 0.055) for v in c[:3])
        for f in faces:
            for loop in f.loops:
                loop[self.col] = (s[0], s[1], s[2], 1.0)

    def box(self, center, size, c, rot=None, spin=None):
        """Box in Godot coords (center, size). rot: the part's own tilt (Blender-space 3x3, about its centre);
        spin: a turn of the whole part (centre included) about the piece's vertical axis."""
        res = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = res["verts"]
        m = Matrix.Diagonal((size[0], size[2], size[1], 1.0))
        if rot is not None:
            m = rot.to_4x4() @ m
        offset = G(*center)
        if spin is not None:
            m = spin.to_4x4() @ m
            offset = spin @ offset
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(offset) @ m, verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        self.paint(faces, c)
        return faces

    def cylinder(self, a, b, r1, r2, segs, side_c, cap_c, squash=(1.0, 1.0)):
        """Cylinder (cone when r2 == 0) from Godot point a to b."""
        A, B = G(*a), G(*b)
        axis = (B - A)
        length = axis.length
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1,
                                    radius2=max(r2, 0.0001), depth=length)
        verts = res["verts"]
        bmesh.ops.transform(self.bm, matrix=Matrix.Diagonal((squash[0], squash[1], 1.0, 1.0)), verts=verts)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation((A + B) * 0.5) @ rot, verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        for f in faces:
            f.normal_update()
            is_cap = abs(f.normal.normalized().dot(axis.normalized())) > 0.9 if f.normal.length > 0 else False
            self.paint([f], cap_c if is_cap else side_c)
        return faces

    def finish(self, name):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = False
        me.color_attributes.active_color_index = me.color_attributes.find("Col")
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
        mat = bpy.data.materials.new("goblin_dressing")
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        attr = mat.node_tree.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.92
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def crate():
    k = Piece(11)
    k.box((0, 0.5, 0), (1.0, 1.0, 1.0), WOOD_DARK)  # core: fills plank gaps, encloses the collider
    t = 0.035  # plank thickness
    rows = 4
    gap = 0.018
    h = (0.92 - gap * (rows - 1)) / rows
    for side in range(4):
        rot = Matrix.Rotation(side * math.pi / 2, 3, 'Z')
        for r in range(rows):
            y = 0.04 + r * (h + gap) + h / 2
            c = k.jitter(WOOD, 0.12)
            k.box((0, y, 0.5 + t / 2), (0.86, h, t), c, spin=rot)
        # X brace (one diagonal per side, alternating)
        ang = math.atan2(0.80, 0.80) * (1 if side % 2 == 0 else -1)
        k.box((0, 0.5, 0.5 + t + 0.012), (1.08, 0.09, 0.024), k.jitter(WOOD_FRAME, 0.08),
              rot=Matrix.Rotation(ang, 3, 'Y'), spin=rot)
        # rims (bottom and top boards)
        for y in (0.045, 0.955):
            k.box((0, y, 0.5 + t + 0.01), (1.0, 0.09, 0.02 + t), k.jitter(WOOD_FRAME, 0.08), spin=rot)
    for sx in (-1, 1):
        for sz in (-1, 1):
            k.box((sx * 0.52, 0.5, sz * 0.52), (0.11, 1.0, 0.11), k.jitter(WOOD_FRAME, 0.1))
            for y in (0.03, 0.97):
                k.box((sx * 0.53, y, sz * 0.53), (0.15, 0.07, 0.15), IRON)
    for i in range(4):  # lid planks
        z = -0.39 + i * 0.26
        k.box((0, 1.0 + 0.018, z), (0.98, 0.036, 0.24), k.jitter(WOOD, 0.12))
    k.box((0, 1.04, -0.30), (1.02, 0.03, 0.09), WOOD_FRAME)
    k.box((0, 1.04, 0.30), (1.02, 0.03, 0.09), WOOD_FRAME)
    k.box((0.0, 1.06, 0.0), (0.18, 0.04, 0.18), IRON)  # a lock plate: something to look at from above
    return k.finish("goblin_crate")


def stoneblock():
    """Dry-stone block / pillar: three courses of cut stones over a dark mortar core, stones staggered per course
    and proud of the core by a few cm, a bevelled cap slab with moss on top. A box collider stays a box, so a cut
    stone block (not a boulder) can wrap it without growing the footprint."""
    k = Piece(23)
    rng = k.rng
    k.box((0, 0.5, 0), (1.0, 1.0, 1.0), MORTAR)
    rows = 3
    gap = 0.03
    ch = (0.94 - gap * (rows - 1)) / rows
    for r in range(rows):
        y = r * (ch + gap) + ch / 2
        for side in range(4):
            rot = Matrix.Rotation(side * math.pi / 2, 3, 'Z')
            cuts = sorted(rng.uniform(-0.25, 0.25) for _ in range(rng.choice((1, 2))))
            edges = [-0.53] + cuts + [0.53]
            for e0, e1 in zip(edges, edges[1:]):
                t = rng.uniform(0.025, 0.06)
                width = e1 - e0 - gap
                c = k.jitter(STONE, 0.18)
                if rng.random() < 0.25:
                    c = tuple(a + (b - a) * 0.35 for a, b in zip(c, MOSS))
                k.box(((e0 + e1) / 2, y + rng.uniform(-0.01, 0.01), 0.5 + t / 2 - 0.005), (width, ch, t), c, spin=rot)
    sx = rng.uniform(-0.18, 0.18)
    sz = [rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2)]
    for i, (x0, x1) in enumerate(((-0.56, sx), (sx, 0.56))):  # cap: four slabs of different heights/tones
        for z0, z1 in ((-0.56, sz[i]), (sz[i], 0.56)):
            h = rng.uniform(0.07, 0.12)
            slab = k.box(((x0 + x1) / 2, 0.95 + h / 2, (z0 + z1) / 2), (x1 - x0 - 0.03, h, z1 - z0 - 0.03),
                         k.jitter(STONE, 0.16))
            edges = list({e for f in slab for e in f.edges})
            res = bmesh.ops.bevel(k.bm, geom=edges, offset=0.022, segments=1, affect='EDGES')
            k.paint([f for f in res.get("faces", []) if f.is_valid], k.jitter(STONE_EDGE, 0.06))
    for i in range(rng.randint(5, 7)):  # moss clumps creeping over the slab edges
        ang = rng.uniform(0, math.tau)
        r = rng.uniform(0.15, 0.5)
        size = rng.uniform(0.09, 0.22)
        k.box((math.cos(ang) * r, 1.05 + rng.uniform(0.0, 0.03), math.sin(ang) * r),
              (size, rng.uniform(0.03, 0.06), size * rng.uniform(0.6, 1.3)), k.jitter(MOSS, 0.18))
    return k.finish("goblin_stoneblock")


def logwall():
    k = Piece(31)
    k.box((0, 0.5, 0), (1.0, 1.0, 1.0), WOOD_DARK)
    rows = 3
    for r in range(rows):
        y = (r + 0.5) / rows
        off = 0.03 * (1 if r % 2 else -1)
        # (local x of the cone -> Godot up, local y -> depth; the builder scales depth/height per obstacle)
        k.cylinder((-0.53 + off, y, 0), (0.53 + off, y, 0), 0.5 / rows * 1.12, 0.5 / rows * 1.12, 9,
                   k.jitter(BARK, 0.1), k.jitter(CUT, 0.06), squash=(1.0, 2.9))
    for sx in (-1, 1):  # rope lashings (no vertical round parts: the long axis is stretched per obstacle)
        k.box((sx * 0.30, 0.5, 0.0), (0.05, 1.06, 1.14), (0.40, 0.33, 0.22))
    return k.finish("goblin_logwall")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    report = {}
    for build in (crate, stoneblock, logwall):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        ob = build()
        # (each piece encloses its collider by construction: its first part is a core box exactly the unit box)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        path = os.path.join(OUT, ob.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_animations=False,
                                  export_lights=False, export_cameras=False, export_apply=False, export_yup=True,
                                  export_vertex_color='ACTIVE')
        report[ob.name] = tris
        print("DRESSING", ob.name, "tris", tris, "->", path)
    print("GOBLIN DRESSING BUILT", report)


main()

"""Treasure chest prop (for the journey's treasure stage; the combat-designer opens it in code).

    art/props/treasure_chest/treasure_chest.glb

Nodes (Godot names after import; the scene root is the file's root):
    body        the box: wooden planks, iron bands and feet, brass corners and lock plate, a glowing gold seam on
                the rim, a heap of glowing gold inside
    lid         the rounded lid. Its ORIGIN IS THE HINGE (back top edge of the box), so opening it is one rotation
                about its local X axis: rotation.x = 0 closed, rotation.x = -deg_to_rad(105) fully open
                (NEGATIVE opens: the front edge swings up and back)
    loot_point  an empty just above the open chest (where loot pops out)

Size: 1.0 m wide (x), 0.64 m deep (z), 0.72 m tall closed. The front faces +z (south = towards the game camera).
Vertex colours like the goblin stages (glTF COLOR_0, linear). Materials: chest_main (vertex colour, rough),
chest_glow (gold seam + gold inside; client/stage_props.gd shows *_glow materials unshaded). Call
StageProps.use_vertex_colors(node) after instancing (Godot's glTF import leaves vertex colours off).

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_treasure_chest.py
Then: godot --headless --path . --import
"""
import bpy, bmesh, math, random, os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "art/props/treasure_chest/treasure_chest.glb")

W, D = 1.0, 0.64          # width (x), depth (z)
FOOT = 0.05               # feet height
WALL_TOP = 0.455          # top of the box walls
HINGE_Y = 0.475           # the lid rests a little above the walls: the gap shows the glowing seam
LID_H = 0.245             # height of the lid's arch
T = 0.05                  # wall thickness
OPEN_DEG = -105.0         # (documented; the shot uses it)

# palette (sRGB as painted)
WOOD = [(0.55, 0.34, 0.18), (0.50, 0.31, 0.16), (0.60, 0.38, 0.20)]
WOOD_IN = (0.20, 0.12, 0.07)
IRON = (0.24, 0.24, 0.26)
BRASS = (0.80, 0.60, 0.26)
GOLD = (1.0, 0.80, 0.34)
GOLD_DEEP = (1.0, 0.62, 0.18)
KEYHOLE = (0.05, 0.04, 0.03)

rng = random.Random(5)


def P(x, y, z):
    """Godot (x right, y up, z front) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def lin(c, k=1.0):
    def f(v):
        v = max(0.0, min(1.0, v * k))
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


class Part:
    """One object's bmesh: faces get a material index (0 main, 1 glow) and a vertex colour."""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")

    def face(self, pts, color, mat=0, k=None):
        vs = [self.bm.verts.new(P(*p)) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = mat
        kk = k if k is not None else 1.0 + rng.uniform(-0.05, 0.05)
        for loop in f.loops:
            loop[self.col] = lin(color, kk)
        return f

    def box(self, c, s, color, mat=0, inner=None, center=None, skip=()):
        """Axis-aligned box (Godot centre c, size s). Faces pointing towards `center` get the `inner` colour
        (the inside of the chest is dark); `skip` = face names not to build ('top', 'bottom', ...)."""
        x0, x1 = c[0] - s[0] / 2, c[0] + s[0] / 2
        y0, y1 = c[1] - s[1] / 2, c[1] + s[1] / 2
        z0, z1 = c[2] - s[2] / 2, c[2] + s[2] / 2
        faces = {
            "front": ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
            "back": ([(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)], (0, 0, -1)),
            "right": ([(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)], (1, 0, 0)),
            "left": ([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1, 0, 0)),
            "top": ([(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)], (0, 1, 0)),
            "bottom": ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
        }
        k = 1.0 + rng.uniform(-0.06, 0.06)
        for name, (pts, n) in faces.items():
            if name in skip:
                continue
            col = color
            if inner is not None and center is not None:
                to_c = (center[0] - c[0], center[1] - c[1], center[2] - c[2])
                if name in ("front", "back", "left", "right") and to_c[0] * n[0] + to_c[2] * n[2] > 0.0:
                    col = inner
            self.face(pts, col, mat, k)

    def to_object(self, name, location, materials):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in materials:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        ob.location = location
        bpy.context.scene.collection.objects.link(ob)
        return ob, sum(len(p.vertices) - 2 for p in me.polygons)


def make_material(name, emissive=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    if emissive:
        bsdf.inputs["Emission Color"].default_value = emissive
        bsdf.inputs["Emission Strength"].default_value = 1.5
    return m


def build_body():
    b = Part()
    mid = (0.0, 0.25, 0.0)
    wall_h = WALL_TOP - FOOT
    # walls: 3 planks per wall (slightly different tones, hairline gaps); dark on the inside
    for i in range(3):
        ph = wall_h / 3
        y = FOOT + ph * (i + 0.5)
        tone = WOOD[(i + 1) % 3]
        b.box((0, y, D / 2 - T / 2), (W, ph - 0.008, T), tone, inner=WOOD_IN, center=mid)
        b.box((0, y, -D / 2 + T / 2), (W, ph - 0.008, T), WOOD[i % 3], inner=WOOD_IN, center=mid)
        b.box((W / 2 - T / 2, y, 0), (T, ph - 0.008, D - 2 * T), WOOD[(i + 2) % 3], inner=WOOD_IN, center=mid)
        b.box((-W / 2 + T / 2, y, 0), (T, ph - 0.008, D - 2 * T), WOOD[i % 3], inner=WOOD_IN, center=mid)
    # gap filler behind the planks (so no light leaks through the hairline gaps)
    b.box((0, FOOT + wall_h / 2, 0), (W - 0.02, wall_h - 0.01, D - 0.02), WOOD_IN, skip=("top",))
    b.box((0, FOOT + 0.06, 0), (W - 2 * T, 0.02, D - 2 * T), WOOD_IN)  # floor
    # the gold: a heap and a few coins (glow material)
    hb = bmesh.ops.create_icosphere(b.bm, subdivisions=2, radius=1.0)
    for v in hb["verts"]:
        g = Vector((v.co.x * 0.40, max(v.co.z, 0.0) * 0.19 + 0.25, v.co.y * 0.24))  # (godot-ish: x, y, z)
        g.x += rng.uniform(-0.02, 0.02)
        g.y += rng.uniform(-0.015, 0.015)
        v.co = P(g.x, g.y, g.z)
    for f in {f for v in hb["verts"] for f in v.link_faces}:
        f.material_index = 1
        k = 1.0 + rng.uniform(-0.12, 0.08)
        for loop in f.loops:
            y = -loop.vert.co.y * 0 + loop.vert.co.z
            loop[b.col] = lin(GOLD if y > 0.33 else GOLD_DEEP, k)
    for i in range(6):
        a = i * 1.7
        cx, cz = math.cos(a) * 0.30, math.sin(a) * 0.16
        b.box((cx, 0.40 + rng.uniform(-0.03, 0.02), cz), (0.07, 0.012, 0.07), GOLD, mat=1)
    # the glowing seam: a thin strip all round the rim, set in a hair from the outer faces
    s_y = (WALL_TOP + HINGE_Y) / 2
    s_h = HINGE_Y - WALL_TOP + 0.004
    b.box((0, s_y, D / 2 - 0.03), (W - 0.04, s_h, 0.04), GOLD, mat=1, skip=("bottom",))
    b.box((0, s_y, -D / 2 + 0.03), (W - 0.04, s_h, 0.04), GOLD, mat=1, skip=("bottom",))
    b.box((W / 2 - 0.03, s_y, 0), (0.04, s_h, D - 0.1), GOLD, mat=1, skip=("bottom",))
    b.box((-W / 2 + 0.03, s_y, 0), (0.04, s_h, D - 0.1), GOLD, mat=1, skip=("bottom",))
    # iron: feet, a bottom band, two vertical straps over front and back
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box((sx * (W / 2 - 0.06), FOOT / 2, sz * (D / 2 - 0.06)), (0.12, FOOT, 0.12), IRON)
    b.box((0, FOOT + 0.035, 0), (W + 0.02, 0.06, D + 0.02), IRON, skip=("top", "bottom"))
    for sx in (-0.33, 0.33):
        b.box((sx, FOOT + wall_h / 2, D / 2 + 0.006), (0.075, wall_h, 0.016), IRON, skip=("back",))
        b.box((sx, FOOT + wall_h / 2, -D / 2 - 0.006), (0.075, wall_h, 0.016), IRON, skip=("front",))
        for y in (FOOT + 0.12, FOOT + 0.30):  # rivets
            b.box((sx, y, D / 2 + 0.017), (0.025, 0.025, 0.01), BRASS, skip=("back",))
    # brass corner caps
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box((sx * (W / 2 - 0.02), FOOT + wall_h / 2, sz * (D / 2 - 0.02)), (0.07, wall_h + 0.01, 0.07), BRASS,
                  skip=("bottom",))
    # brass lock plate + keyhole
    b.box((0, 0.33, D / 2 + 0.012), (0.16, 0.14, 0.024), BRASS, skip=("back",))
    b.box((0, 0.315, D / 2 + 0.025), (0.025, 0.05, 0.006), KEYHOLE, skip=("back",))
    return b


def lid_profile(n=6, grow=0.0):
    """Arch across the depth, local to the hinge (z 0 at the back .. D at the front)."""
    pts = []
    for i in range(n + 1):
        a = math.pi * i / n
        z = D / 2 - (D / 2 + grow) * math.cos(a)
        y = (LID_H + grow) * math.sin(a)
        pts.append((y, z))
    return pts


def build_lid():
    """Lid geometry in LOCAL coordinates: origin = the hinge (back edge), the lid reaches forward to z = D."""
    b = Part()
    prof = lid_profile()
    x0, x1 = -W / 2, W / 2
    for i in range(len(prof) - 1):  # the arch: one plank per strip
        (ya, za), (yb, zb) = prof[i], prof[i + 1]
        b.face([(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)][::-1], WOOD[i % 3])
    for x, rev in ((x0, False), (x1, True)):  # end caps (fan)
        pts = [(x, y, z) for y, z in prof]
        b.face(pts if not rev else pts[::-1], WOOD[1])
    b.face([(x0, 0, 0), (x1, 0, 0), (x1, 0, D), (x0, 0, D)][::-1], WOOD_IN)  # underside (seen when open)
    # iron straps over the arch (match the box's straps)
    band = lid_profile(grow=0.016)
    for sx in (-0.33, 0.33):
        a0, a1 = sx - 0.0375, sx + 0.0375
        for i in range(len(band) - 1):
            (ya, za), (yb, zb) = band[i], band[i + 1]
            b.face([(a0, ya, za), (a1, ya, za), (a1, yb, zb), (a0, yb, zb)][::-1], IRON, k=1.0)
            (yi, zi), (yj, zj) = prof[i], prof[i + 1]
            b.face([(a0, yi, zi), (a0, ya, za), (a0, yb, zb), (a0, yj, zj)][::-1], IRON, k=0.8)
            b.face([(a1, yi, zi), (a1, ya, za), (a1, yb, zb), (a1, yj, zj)], IRON, k=0.8)
        b.box((sx, LID_H + 0.02, D / 2), (0.03, 0.012, 0.03), BRASS)  # rivet on top
    # brass trim on the front and back lips, brass end-cap corners
    b.box((0, 0.025, D - 0.012), (W + 0.012, 0.05, 0.03), BRASS)
    b.box((0, 0.025, 0.012), (W + 0.012, 0.05, 0.03), BRASS)
    for x in (x0 - 0.004, x1 + 0.004):
        b.box((x, LID_H * 0.5, D / 2), (0.012, 0.05, D * 0.9), BRASS)
    # the hasp that hangs over the lock plate
    b.box((0, -0.04, D + 0.02), (0.11, 0.13, 0.02), BRASS)
    b.box((0, -0.06, D + 0.032), (0.04, 0.04, 0.008), IRON)
    # a thin glowing seam on the underside rim (seen from the front when it starts to open)
    b.box((0, -0.002, D - 0.05), (W - 0.06, 0.004, 0.03), GOLD, mat=1, skip=("top",))
    return b


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    main_m = make_material("chest_main")
    glow_m = make_material("chest_glow", emissive=(1.0, 0.72, 0.25, 1.0))
    body, body_tris = build_body().to_object("body", Vector((0, 0, 0)), [main_m, glow_m])
    lid_loc = P(0.0, HINGE_Y, -D / 2)
    lid, lid_tris = build_lid().to_object("lid", lid_loc, [main_m, glow_m])
    loot = bpy.data.objects.new("loot_point", None)
    loot.empty_display_type = 'PLAIN_AXES'
    loot.location = P(0.0, 0.95, 0.04)
    bpy.context.scene.collection.objects.link(loot)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in (body, lid, loot):
        o.select_set(True)
    kw = dict(filepath=OUT, export_format='GLB', use_selection=True, export_animations=False, export_lights=False,
              export_cameras=False, export_apply=False, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    print("CHEST tris body %d lid %d total %d  glb %d KB" % (body_tris, lid_tris, body_tris + lid_tris,
                                                           os.path.getsize(OUT) // 1024))


main()

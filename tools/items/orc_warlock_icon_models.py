"""Orc Warlock boss accessory icons, step 1 of 2: small Blender scenes of the seven icon subjects (tusk necklace, bone hook
earring, iron-studded bracer, ember skull ring, night hide cloak, coin, relic), cel-shaded and rendered alone on a
transparent 384x384 frame. Step 2 (tools/items/orc_warlock_icons.py) paints them into the 96x96 boss icon style.
Theme (Boss 2026-11-21): orc warlock night camp: brown leather, bone, tusk, iron, ember fire, a touch of purple magic.
Run: blender -b --factory-startup --python tools/items/orc_warlock_icon_models.py -- <out_dir>
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(os.getcwd(), "build", "orc_warlock_icons")
RES = 384

# palette (linear-ish, picked against the goblin/mummy icons: warm, not saturated)
# sRGB picks, sampled against the goblin chief icons (leather, bone, iron) and kept below their saturation
LEATHER = (0.47, 0.27, 0.16)
LEATHER_DK = (0.33, 0.19, 0.11)
BONE = (0.88, 0.80, 0.64)
TUSK = (0.93, 0.87, 0.72)
IRON = (0.42, 0.40, 0.39)
BRONZE = (0.70, 0.46, 0.24)
WOOD = (0.40, 0.24, 0.14)
FUR = (0.36, 0.27, 0.21)
PURPLE = (0.50, 0.30, 0.66)
EMBER = (1.0, 0.55, 0.20)
RED = (0.66, 0.20, 0.14)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    # ink lines: Freestyle silhouette/crease/border in a dark warm brown (the painted icons have inked inner lines too)
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = "ABSOLUTE"
    sc.render.line_thickness = 2.0
    vl = sc.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("ink")
    ls.select_by_visibility = True
    ls.select_silhouette = ls.select_border = ls.select_crease = True
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("ink")
    ls.linestyle.color = (0.03, 0.015, 0.008)
    ls.linestyle.thickness = 2.0
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.33, 0.32, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = Euler((math.radians(50), math.radians(-35), math.radians(-30)))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.location = (0, -10, 0)
    cam.rotation_euler = Euler((math.radians(90), 0, 0))
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


_mats = {}


def mat(name, color, emit=None, gloss=False):
    """Cel material: diffuse -> Shader to RGB -> 3-step ramp (shade / base / lit), optional emission on top."""
    key = (name, color, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    if emit is not None:
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs[0].default_value = (*[v ** 2.2 for v in color], 1)
        em.inputs[1].default_value = emit
        nt.links.new(em.outputs[0], out.inputs[0])
        _mats[key] = m
        return m
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diff.inputs[0].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(diff.outputs[0], s2r.inputs[0])
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(s2r.outputs[0], bw.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    el = ramp.color_ramp.elements
    c = Vector([v ** 2.2 for v in color])  # the palette is picked in sRGB; the ramp works in linear
    el[0].position = 0.0
    el[0].color = (*(c * 0.45), 1)
    el[1].position = 0.22
    el[1].color = (*c, 1)
    hi = el.new(0.75 if gloss else 0.85)
    hi.color = (*[min(1.0, v * 1.45 + 0.04) for v in c], 1)
    nt.links.new(bw.outputs[0], ramp.inputs[0])
    emis = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(ramp.outputs[0], emis.inputs[0])
    nt.links.new(emis.outputs[0], out.inputs[0])
    _mats[key] = m
    return m


def link(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    bpy.context.scene.collection.objects.link(obj) if obj.name not in bpy.context.scene.collection.objects else None
    return obj


def from_bm(bm, name, material, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(material)
    return ob


def prim(kind, material, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), smooth=True, **kw):
    getattr(bpy.ops.mesh, "primitive_%s_add" % kind)(location=loc, rotation=rot, **kw)
    ob = bpy.context.active_object
    ob.scale = scale
    ob.data.materials.append(material)
    if smooth:
        bpy.ops.object.shade_smooth()
    return ob


def tube(points, radii, material, name="tube", seg=12, cap_tip=True):
    """A tapered tube along a polyline (tusks, hooks, cords)."""
    bm = bmesh.new()
    rings = []
    n = len(points)
    for i, p in enumerate(points):
        p = Vector(p)
        t = (Vector(points[min(i + 1, n - 1)]) - Vector(points[max(i - 1, 0)])).normalized()
        a = t.orthogonal().normalized()
        b = t.cross(a).normalized()
        r = radii[i]
        rings.append([bm.verts.new(p + (a * math.cos(2 * math.pi * k / seg) + b * math.sin(2 * math.pi * k / seg)) * r) for k in range(seg)])
    for i in range(n - 1):
        for k in range(seg):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    if cap_tip:
        bm.faces.new(rings[-1])
    return from_bm(bm, name, material)


def tusk(base, direction, length, r0, curl, material, side=Vector((0, -1, 0))):
    """A curved, tapering tusk from `base` along `direction`, bending toward `curl` (a unit vector)."""
    base, d, cu = Vector(base), Vector(direction).normalized(), Vector(curl).normalized()
    pts, rs = [], []
    steps = 10
    for i in range(steps + 1):
        f = i / steps
        pts.append(base + d * length * f + cu * length * 0.35 * f * f)
        rs.append(max(0.004, r0 * (1.0 - f) ** 0.8))
    return tube(pts, rs, material, "tusk")


def arc_points(center, radius, a0, a1, count, plane="xz"):
    out = []
    for i in range(count):
        a = a0 + (a1 - a0) * i / (count - 1)
        if plane == "xz":
            out.append(Vector(center) + Vector((math.cos(a) * radius, 0, math.sin(a) * radius)))
    return out


def render(name):
    sc = bpy.context.scene
    # frame the ortho camera around everything
    lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    for ob in sc.objects:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    cam = sc.camera
    cam.location.x = (lo.x + hi.x) / 2
    cam.location.z = (lo.z + hi.z) / 2
    cam.data.ortho_scale = max(hi.x - lo.x, hi.z - lo.z) * 1.12
    os.makedirs(OUT, exist_ok=True)
    sc.render.filepath = os.path.join(OUT, "raw-%s.png" % name)
    bpy.ops.render.render(write_still=True)
    print("RAW", sc.render.filepath)


# ------------------------------------------------------------------------------------------------ subjects

def necklace():
    reset()
    cord = mat("cord", LEATHER)
    # leather thong: a hanging loop open at the top (as the goblin necklace)
    loop = lambda a: Vector((math.cos(a) * 1.0, 0, math.sin(a) * 0.95))
    pts = [loop(math.radians(a)) for a in range(105, 436, 6)]
    tube(pts, [0.05] * len(pts), cord, "cord", cap_tip=False)
    # beads: dark wood and iron up the sides, bone tusks hanging from the lower half
    wood, iron, tusk_m, purple = mat("wood", WOOD), mat("iron", IRON, gloss=True), mat("tusk", TUSK), mat("purple", PURPLE, emit=1.0)
    for i, a in enumerate([125, 145, 165, 185, 355, 375, 395, 415]):
        prim("uv_sphere", wood if i % 2 else iron, loc=loop(math.radians(a)), scale=(0.1, 0.1, 0.1), segments=16, ring_count=8)
    for a, ln in [(212, 0.5), (240, 0.62), (270, 0.85), (300, 0.62), (328, 0.5)]:
        r = math.radians(a)
        p = loop(r)
        out = Vector((math.cos(r) * 0.55, 0, math.sin(r))).normalized()
        curl = Vector((0.6 if a > 270 else -0.6 if a < 270 else 0.25, 0, 0.15))
        tusk(p - out * 0.04, out, ln, 0.1 if a == 270 else 0.085, curl, tusk_m)
        prim("cylinder", iron, loc=p + out * 0.04, rot=(math.radians(90), 0, 0), scale=(0.095, 0.095, 0.06), vertices=12)
    # purple charm bead above the centre tusk
    prim("uv_sphere", purple, loc=(0, -0.1, -0.8), scale=(0.12, 0.12, 0.12), segments=16, ring_count=8)
    render("necklace")


def earring():
    reset()
    iron, tusk_m, leather, ember = mat("iron", IRON, gloss=True), mat("bone", BONE), mat("leather", LEATHER), mat("ember", EMBER, emit=1.0)
    prim("torus", iron, loc=(0, 0, 0.9), rot=(math.radians(90), 0, 0), major_radius=0.36, minor_radius=0.06, major_segments=32, minor_segments=10)
    prim("cylinder", leather, loc=(0, 0, 0.5), rot=(0, 0, 0), scale=(0.11, 0.11, 0.14), vertices=12)
    prim("cylinder", iron, loc=(0, 0, 0.38), scale=(0.12, 0.12, 0.03), vertices=12)
    # bone hook: a tusk curling up into a hook
    pts = [Vector((0.02 * f, 0, 0.36 - 0.85 * f)) for f in [i / 8 for i in range(9)]]
    for i in range(1, 17):
        a = math.radians(180 + 205 * i / 16)
        pts.append(Vector((0.3 + math.cos(a) * 0.3, 0, -0.49 + math.sin(a) * 0.32)))
    rs = [max(0.012, 0.14 * (1 - i / (len(pts) - 1)) ** 0.75) for i in range(len(pts))]
    tube(pts, rs, tusk_m, "hook")
    # red war-paint bands and an ember bead
    prim("torus", mat("red", RED), loc=pts[6], rot=(math.radians(90), 0, 0), major_radius=rs[6] * 0.95, minor_radius=0.02, major_segments=20, minor_segments=6)
    prim("uv_sphere", ember, loc=(0, -0.1, 0.5), scale=(0.05, 0.05, 0.05), segments=12, ring_count=6)
    render("earring")


def bracelet():
    reset()
    sc = bpy.context.scene
    leather, iron, bone, purple = mat("leather", LEATHER), mat("iron", IRON, gloss=True), mat("bone", BONE), mat("purple", PURPLE, emit=1.0)
    ob = prim("cylinder", leather, loc=(0, 0, 0), scale=(1.0, 1.0, 0.55), vertices=40)
    mod = ob.modifiers.new("solid", "SOLIDIFY")
    mod.thickness = 0.16
    # remove caps so it reads as a band
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.z) > 0.9], context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    for z in (0.5, -0.5):
        prim("torus", iron, loc=(0, 0, z), major_radius=1.04, minor_radius=0.07, major_segments=48, minor_segments=8)
    # studs: iron spikes on the front half
    for k in range(9):
        a = math.radians(-160 + k * 17.5)
        for z in (0.24, -0.24):
            p = Vector((math.cos(a) * 1.08, math.sin(a) * 1.08, z))
            prim("cone", iron, loc=p, rot=(0, math.radians(90), 0), vertices=8, radius1=0.07, depth=0.14).rotation_euler = Euler((0, math.radians(90), a))
    # bone plate with a purple rune
    plate = prim("cube", bone, loc=(0, -1.12, 0), scale=(0.3, 0.05, 0.22))
    prim("cylinder", purple, loc=(0, -1.18, 0), rot=(math.radians(90), 0, 0), scale=(0.11, 0.11, 0.02), vertices=6)
    # view at 3/4 from above like the other bracelet icons
    for ob in list(sc.objects):
        if ob.type == "MESH":
            ob.matrix_world = Matrix.Rotation(math.radians(-28), 4, "X") @ ob.matrix_world
    render("bracelet")


def ring():
    reset()
    sc = bpy.context.scene
    iron, bone, ember, tusk_m = mat("iron", IRON, gloss=True), mat("bone", BONE), mat("ember", EMBER, emit=1.0), mat("tusk", TUSK)
    prim("torus", iron, loc=(0, 0, -0.45), rot=(math.radians(90), 0, 0), major_radius=0.62, minor_radius=0.17, major_segments=40, minor_segments=12)
    prim("cylinder", mat("bronze", BRONZE, gloss=True), loc=(0, 0, 0.2), scale=(0.6, 0.35, 0.1), vertices=8)
    # skull: cranium, jaw, eye sockets with ember eyes, red war paint
    prim("uv_sphere", bone, loc=(0, -0.05, 0.78), scale=(0.62, 0.5, 0.55), segments=24, ring_count=14)
    prim("cube", bone, loc=(0, -0.2, 0.32), scale=(0.36, 0.26, 0.16))
    for x in (-0.24, 0.24):
        prim("uv_sphere", mat("sock", (0.22, 0.12, 0.08)), loc=(x, -0.5, 0.8), scale=(0.16, 0.08, 0.13), segments=12, ring_count=6)
        prim("uv_sphere", ember, loc=(x, -0.56, 0.8), scale=(0.075, 0.04, 0.065), segments=12, ring_count=6)
    prim("cube", mat("red", RED), loc=(0, -0.53, 1.05), scale=(0.05, 0.02, 0.18))
    # tusks from the jaw, curling up
    for s in (-1, 1):
        tusk((s * 0.26, -0.38, 0.26), (s * 0.35, -0.2, 1.0), 0.5, 0.085, (s, 0, 0), tusk_m)
    for ob in list(sc.objects):
        if ob.type == "MESH":
            ob.matrix_world = Matrix.Rotation(math.radians(-14), 4, "X") @ Matrix.Rotation(math.radians(18), 4, "Z") @ ob.matrix_world
    render("ring")


def back():
    reset()
    leather, fur, bone, purple, iron = mat("hide", (0.52, 0.32, 0.19)), mat("fur", FUR), mat("bone", BONE), mat("purple", PURPLE), mat("iron", IRON, gloss=True)
    # cloak: a curved, tattered hide panel
    bm = bmesh.new()
    cols, rows = 14, 12
    grid = []
    for j in range(rows + 1):
        v = j / rows
        row = []
        for i in range(cols + 1):
            u = i / cols - 0.5
            width = 0.7 + 0.55 * v
            x = u * 2 * width
            z = 1.0 - v * 2.3
            if j == rows:
                z -= 0.18 * (1 if i % 2 else 0) + 0.06 * math.sin(i * 1.7)
            y = 0.35 * (u * 2) ** 2 - 0.05 * math.sin(v * 6 + u * 4)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    ob = from_bm(bm, "cloak", leather)
    ob.modifiers.new("s", "SOLIDIFY").thickness = 0.05
    # darker stitched hide patches and leather straps
    for s in (-1, 1):
        pts = [Vector((s * (0.2 + 0.5 * f), 0.3 * (0.4 + f) ** 2 - 0.08, 0.75 - 1.4 * f)) for f in [i / 10 for i in range(11)]]
        tube(pts, [0.04] * 11, mat("strap", LEATHER_DK), "strap", cap_tip=False)
    # purple trim near the hem
    pts = [Vector(((i / 20 - 0.5) * 2 * 1.18, 0.35 * ((i / 20 - 0.5) * 2) ** 2 - 0.06, -1.0)) for i in range(21)]
    tube(pts, [0.035] * 21, purple, "trim", cap_tip=False)
    # fur collar and bone clasp with tusks
    pts = [Vector(((i / 20 - 0.5) * 1.7, 0.3 * ((i / 20 - 0.5) * 2) ** 2 - 0.08, 1.02 - 0.12 * ((i / 20 - 0.5) * 2) ** 2)) for i in range(21)]
    tube(pts, [0.17 + 0.03 * math.sin(i * 2.1) for i in range(21)], fur, "collar", cap_tip=True)
    prim("uv_sphere", bone, loc=(0, -0.28, 0.9), scale=(0.2, 0.08, 0.17), segments=16, ring_count=8)
    prim("torus", iron, loc=(0, -0.3, 0.9), rot=(math.radians(90), 0, 0), major_radius=0.2, minor_radius=0.03, major_segments=24, minor_segments=6)
    for s in (-1, 1):
        tusk((s * 0.18, -0.25, 0.82), (s * 0.6, -0.1, -0.6), 0.35, 0.05, (s, 0, 0), mat("tusk", TUSK))
    render("back")


def coin():
    reset()
    bronze, iron, bone, tusk_m, ember = mat("bronze", BRONZE, gloss=True), mat("iron", IRON, gloss=True), mat("bone", (0.80, 0.62, 0.40)), mat("tusk", TUSK), mat("ember", EMBER, emit=1.0)
    prim("cylinder", bronze, loc=(0, 0, 0), rot=(math.radians(90), 0, 0), scale=(1.0, 1.0, 0.08), vertices=48)
    prim("torus", iron, loc=(0, -0.08, 0), rot=(math.radians(90), 0, 0), major_radius=0.95, minor_radius=0.07, major_segments=48, minor_segments=8)
    for k in range(16):  # rivets on the rim
        a = 2 * math.pi * k / 16
        prim("uv_sphere", iron, loc=(math.cos(a) * 0.82, -0.1, math.sin(a) * 0.82), scale=(0.04, 0.04, 0.04), segments=8, ring_count=4)
    # embossed orc head: broad brow, jaw, tusks
    prim("uv_sphere", bone, loc=(0, -0.08, 0.12), scale=(0.42, 0.1, 0.36), segments=24, ring_count=12)
    prim("cube", bone, loc=(0, -0.1, -0.28), scale=(0.3, 0.08, 0.14))
    prim("cube", mat("brow", (0.58, 0.40, 0.22)), loc=(0, -0.17, 0.25), scale=(0.36, 0.04, 0.06))
    for x in (-0.15, 0.15):
        prim("uv_sphere", ember, loc=(x, -0.18, 0.13), scale=(0.06, 0.03, 0.04), segments=10, ring_count=6)
    for s in (-1, 1):
        tusk((s * 0.18, -0.16, -0.32), (s * 0.12, -0.05, 1.0), 0.32, 0.06, (s, 0, 0), tusk_m)
    for ob in list(bpy.context.scene.objects):
        if ob.type == "MESH":
            ob.matrix_world = Matrix.Rotation(math.radians(-16), 4, "Z") @ ob.matrix_world
    render("coin")


def relic():
    reset()
    iron, bone, purple, ember, leather = mat("iron", IRON, gloss=True), mat("bone", BONE), mat("purple", (0.56, 0.34, 0.76), emit=1.0), mat("ember", EMBER, emit=1.0), mat("leather", LEATHER)
    # leather-backed oval
    prim("cylinder", leather, loc=(0, 0.05, 0), rot=(math.radians(90), 0, 0), scale=(0.85, 1.05, 0.05), vertices=40)
    prim("torus", iron, loc=(0, -0.02, 0), rot=(math.radians(90), 0, 0), scale=(0.82, 1.0, 1.0), major_radius=1.0, minor_radius=0.08, major_segments=48, minor_segments=8)
    # purple gem
    gem = prim("ico_sphere", purple, loc=(0, -0.15, 0), scale=(0.42, 0.18, 0.55), subdivisions=1, smooth=False)
    prim("ico_sphere", mat("gemhi", (0.92, 0.84, 1.0), emit=1.0), loc=(-0.13, -0.32, 0.2), scale=(0.08, 0.03, 0.1), subdivisions=1, smooth=False)
    # bone claws gripping the gem and ember runes around
    for a in (40, 140, 220, 320):
        r = math.radians(a)
        base = Vector((math.cos(r) * 0.8, -0.05, math.sin(r) * 1.0))
        tusk(base, Vector((-math.cos(r), -0.6, -math.sin(r))), 0.38, 0.07, Vector((-math.cos(r), 0, -math.sin(r))), bone)
    for k in range(10):
        a = 2 * math.pi * (k + 0.5) / 10
        prim("cube", ember, loc=(math.cos(a) * 0.66, -0.07, math.sin(a) * 0.82), rot=(0, a, 0), scale=(0.035, 0.01, 0.07))
    # tusk horns on top
    for s in (-1, 1):
        tusk((s * 0.3, 0, 0.92), (s * 0.4, 0, 1.0), 0.45, 0.08, (s, 0, 0), mat("tusk", TUSK))
    render("relic")


if __name__ == "__main__":
    for fn in (necklace, earring, bracelet, ring, back, coin, relic):
        fn()

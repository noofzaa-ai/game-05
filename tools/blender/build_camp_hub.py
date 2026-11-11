# Builds the walkable camp hub (Boss 2026-10-13, after Lost Castle 2's camp): a forest clearing at night
# with a big campfire and seats in the middle, a tent, a blacksmith's forge + anvil + counter, a quest
# board, a cauldron, a storage chest, a merchant's stall with crates/barrels, lanterns, and the warp gate
# at the north edge; dense dark pines all around as the border.
# Run:  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P tools/blender/build_camp_hub.py
# Out:  art/maps/camp_hub/camp_hub.glb, art_source/maps/camp_hub/camp_hub.blend
#
# Low-poly, flat shaded, painted with vertex colours (written as sRGB; the exporter stores COLOR_0 linear) - the import leaves
# vertex_color_use_as_albedo off: client/hub_world.gd switches it on. Three materials, one mesh each
# (everything static is merged per material): camp_paint (vertex colours), camp_glow_warm (lantern
# glass, embers), camp_glow_cyan (gate runes and crystals). Fake light is painted into the ground
# colours (warm around the fire and lanterns, cyan at the gate) so the scene needs few real lights.
#
# Coordinates: everything below is written in GAME terms, G(x, z, y): x = east, z = SOUTH (toward the
# camera), y = up, as Godot sees it after the glTF Y-up export. Blender gets (x, -z, y).
#
# Named empties the game reads (client/hub_world.gd):
#   spawn, campfire, warp_gate, npc_blacksmith, npc_merchant, npc_tailor, npc_storage, npc_quest,
#   light_forge, lantern_1..n (warm lantern glass spots)
#   bounds         - scale = the walkable half extents (x, -, z) around the origin
#   col_<name>     - box colliders: position = centre, scale = half extents (never rotated)
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_GLB = os.path.join(ROOT, "art/maps/camp_hub/camp_hub.glb")
OUT_BLEND = os.path.join(ROOT, "art_source/maps/camp_hub/camp_hub.blend")

random.seed(20261013)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# --------------------------------------------------------------------------------------------- layout
# The walkable clearing = union of two boxes (a plus-shape with notched corners: trees fill the notches).
WALK_A = (12.5, 7.0)    # |x| <= 12.5, |z| <= 7
WALK_B = (8.5, 10.5)    # |x| <= 8.5,  |z| <= 10.5
BOUNDS = (12.5, 33.0)   # the simulation's rectangle; the 4 notches are col_corner_* boxes

FIRE = (0.0, 0.0)
GATE = (0.0, -29.5)       # the ring on the ground you walk into
GATE_ARCH_Z = -30.8      # the standing stone ring behind it
TENT = (-8.6, -4.6)
FORGE = (8.6, -5.6)
ANVIL = (6.5, -4.3)
COUNTER = (8.8, -3.1)
BOARD = (-9.6, 2.6)
STALL = (9.4, 4.4)
CHEST = (-4.2, 7.6)
CAULDRON = (-4.0, -6.4)

SPOTS = {  # name -> (x, z, facing yaw degrees about up, 0 = facing south / the camera)
    "spawn": (0.0, 3.6),
    "campfire": FIRE,
    "warp_gate": GATE,
    "plaza": (0.0, -22.0),
    "plaza_entry": (0.0, -12.5),
    "npc_blacksmith": (8.4, -4.6),
    "npc_merchant": (8.4, 6.2),
    "npc_tailor": (-5.8, -2.5),
    "tailor_house": TENT,
    "merchant_shop": STALL,
    "storage_station": CHEST,
    "npc_storage": (-2.0, 6.1),
    "npc_quest": (-7.9, 3.4),
    "light_forge": (FORGE[0], FORGE[1] + 0.2),
}


def G(x, z, y=0.0):
    return Vector((x, -z, y))


def srgb(h):
    h = h.lstrip("#")
    # (the glTF exporter treats the colour attribute as sRGB and writes linear COLOR_0 itself)
    return Vector([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return a * (1.0 - t) + b * t


def vary(c, amount=0.08):
    return c * (1.0 + random.uniform(-amount, amount))


# ------------------------------------------------------------------------------------------ materials
def make_material(name, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    if emission is None:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Color"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


class Layer:
    """One merged mesh (one material)."""

    def __init__(self, name, material):
        self.name, self.material = name, material
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Color")

    def paint(self, faces, color, shade=True, jitter=0.05):
        for f in faces:
            f.normal_update()
            c = Vector(color)
            if shade:  # painted top light: tops brighter, undersides darker (reads at night, top-down)
                c = c * (0.62 + 0.48 * max(0.0, f.normal.z) + 0.12 * max(0.0, -f.normal.y))
            c = vary(c, jitter)
            for loop in f.loops:
                loop[self.col] = (c.x, c.y, c.z, 1.0)

    def faces_of(self, verts):
        return list({f for v in verts for f in v.link_faces})

    def box(self, centre, size, color, yaw=0.0, tilt=(0.0, 0.0), shade=True, rough=0.0):
        m = Matrix.Translation(centre) @ Matrix.Rotation(math.radians(yaw), 4, "Z") \
            @ Matrix.Rotation(math.radians(tilt[0]), 4, "X") @ Matrix.Rotation(math.radians(tilt[1]), 4, "Y") \
            @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
        if rough > 0.0:
            for v in verts:
                v.co += Vector((random.uniform(-rough, rough), random.uniform(-rough, rough), random.uniform(-rough, rough) * 0.6))
        faces = self.faces_of(verts)
        self.paint(faces, color, shade)
        return faces

    def cyl(self, centre, r1, r2, depth, segs, color, rot=None, caps=True, shade=True, rough=0.0):
        m = Matrix.Translation(centre) @ (rot if rot is not None else Matrix.Identity(4))
        verts = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r1,
                                      radius2=r2, depth=depth, matrix=m)["verts"]
        if rough > 0.0:
            for v in verts:
                v.co += Vector((random.uniform(-rough, rough), random.uniform(-rough, rough), 0.0))
        faces = self.faces_of(verts)
        self.paint(faces, color, shade)
        return faces

    def quad(self, pts, color, shade=True):
        verts = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(verts)
        self.paint([f], color, shade)
        return f

    def build(self):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        color_index = mesh.color_attributes.find("Color")
        if color_index >= 0:
            mesh.color_attributes.active_color_index = color_index
            mesh.color_attributes.render_color_index = color_index
        for poly in mesh.polygons:
            poly.use_smooth = False
        mesh.materials.append(self.material)
        obj = bpy.data.objects.new(self.name, mesh)
        scene.collection.objects.link(obj)
        tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
        self.bm.free()
        return obj, tris


PAINT = Layer("camp_paint", make_material("camp_paint"))
WARM = Layer("camp_glow_warm", make_material("camp_glow_warm", emission=(1.0, 0.62, 0.25), strength=3.0))
CYAN = Layer("camp_glow_cyan", make_material("camp_glow_cyan", emission=(0.25, 0.95, 1.0), strength=3.0))

C = {
    "dirt": srgb("#5a4733"), "dirt_light": srgb("#6e573c"), "grass": srgb("#2c3b24"), "grass_dark": srgb("#1f2a1b"),
    "forest_floor": srgb("#121a15"), "warm": srgb("#d08a45"), "cyan": srgb("#47b8c4"),
    "trunk": srgb("#2e2119"), "pine_a": srgb("#1a2c26"), "pine_b": srgb("#20352c"), "pine_c": srgb("#284232"),
    "rock": srgb("#53565c"), "rock_dark": srgb("#3c3f45"), "moss": srgb("#3c5038"),
    "wood": srgb("#6e4c2f"), "wood_dark": srgb("#4a3220"), "wood_light": srgb("#9a7650"), "plank": srgb("#7d5a37"),
    "canvas": srgb("#9a7d55"), "canvas_dark": srgb("#7a6142"), "trim": srgb("#7a2f28"), "cloth_blue": srgb("#2f4f6e"),
    "iron": srgb("#3b3e44"), "iron_dark": srgb("#26282c"), "brass": srgb("#b48c4c"),
    "stone": srgb("#646468"), "stone_light": srgb("#7b7b7e"), "gate_stone": srgb("#5d646c"),
    "paper": srgb("#d9cfae"), "seal": srgb("#9a2a22"), "ash": srgb("#2a2624"), "brew": srgb("#4f8a3a"),
    "sack": srgb("#8d7a58"), "bush": srgb("#22382a"), "bush_light": srgb("#2d4834"), "leaf_tip": srgb("#3b5a3c"),
    "mushroom": srgb("#c9b48a"),
}


def walk_distance(x, z):
    """How far (x, z) is outside the walkable clearing (0 inside)."""
    def out(hx, hz):
        dx, dz = max(0.0, abs(x) - hx), max(0.0, abs(z) - hz)
        return math.hypot(dx, dz)
    corridor = math.hypot(max(0.0, abs(x) - 3.0), max(0.0, abs(z + 11.5) - 4.5))
    plaza = math.hypot(max(0.0, abs(x) - 12.5), max(0.0, abs(z + 23.0) - 10.0))
    return min(out(*WALK_A), out(*WALK_B), corridor, plaza)


# ----------------------------------------------------------------------------------------------- ground
LIGHTS = [  # painted light pools: (x, z, radius, colour, strength)
    (FIRE[0], FIRE[1], 7.5, C["warm"], 0.55),
    (0.0, -22.0, 14.0, C["warm"], 0.32),
    (GATE[0], GATE[1], 4.5, C["cyan"], 0.55),
    (FORGE[0], FORGE[1] + 1.0, 3.5, C["warm"], 0.4),
]
LANTERNS = [(-3.8, -12.5), (3.8, -12.5), (-9.8, -17), (9.8, -17), (-9.8, -26), (9.8, -26), (-2.6, -7.6), (2.6, -7.6), (-11.4, -1.2), (11.6, 0.6), (-7.0, 9.3), (5.6, 9.2)]
for lx, lz in LANTERNS:
    LIGHTS.append((lx, lz, 2.6, C["warm"], 0.32))


def ground_color(x, z):
    d = walk_distance(x, z)
    r = math.hypot(x, z * 1.15)
    base = mix(C["dirt_light"], C["dirt"], r / 6.0)
    base = mix(base, C["grass"], (r - 5.0) / 6.0)
    # a trodden path from the fire to the gate, and to the stations
    if abs(x) < 1.6 and -29.0 < z < -1.0:
        base = mix(base, C["dirt_light"], 0.7 - abs(x) / 2.5)
    base = mix(base, C["grass_dark"], d / 2.0)
    base = mix(base, C["forest_floor"], (d - 1.5) / 4.0)
    n = 0.06 * math.sin(x * 1.7 + z * 0.9) + 0.05 * math.sin(x * 0.6 - z * 2.3)
    base = base * (1.0 + n)
    for lx, lz, rad, col, k in LIGHTS:
        fall = max(0.0, 1.0 - math.hypot(x - lx, z - lz) / rad)
        base = mix(base, col * 0.55, k * fall * fall)
    return base


def ground_height(x, z):
    d = walk_distance(x, z)
    if d < 0.8:
        return 0.0
    return min(0.7, (d - 0.8) * 0.12) + 0.08 * math.sin(x * 0.8) * math.sin(z * 0.7)


def build_ground():
    x0, x1, z0, z1 = -38.0, 38.0, -40.0, 22.0
    step = 1.25
    nx, nz = int((x1 - x0) / step), int((z1 - z0) / step)
    bm, col = PAINT.bm, PAINT.col
    grid = {}
    for i in range(nx + 1):
        for j in range(nz + 1):
            x, z = x0 + i * step, z0 + j * step
            jx = random.uniform(-0.3, 0.3) if 0 < i < nx else 0.0
            jz = random.uniform(-0.3, 0.3) if 0 < j < nz else 0.0
            if walk_distance(x, z) < 0.5:
                jx *= 0.5; jz *= 0.5
            x += jx; z += jz
            grid[(i, j)] = bm.verts.new(G(x, z, ground_height(x, z)))
    for i in range(nx):
        for j in range(nz):
            a, b, c, d = grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]
            for tri in ((a, b, c), (a, c, d)) if (i + j) % 2 == 0 else ((a, b, d), (b, c, d)):
                f = bm.faces.new(tri)
                for loop in f.loops:
                    p = loop.vert.co
                    cc = ground_color(p.x, -p.y)
                    loop[col] = (cc.x, cc.y, cc.z, 1.0)


# ------------------------------------------------------------------------------------------------ props
COLLIDERS = {}  # name -> (centre x, z, half x, half z, height)


def collider(name, x, z, hx, hz, h=1.5):
    COLLIDERS[name] = (x, z, hx, hz, h)


def rock(x, z, s, color=None):
    PAINT.box(G(x, z, s * 0.3), (s, s * random.uniform(0.7, 1.1), s * 0.65), color or vary(C["rock"], 0.12),
              yaw=random.uniform(0, 90), rough=s * 0.18)


def pine(x, z, scale):
    h_trunk = 1.1 * scale
    y0 = ground_height(x, z)
    PAINT.cyl(G(x, z, y0 + h_trunk / 2), 0.2 * scale, 0.14 * scale, h_trunk, 5, C["trunk"], caps=False)
    tones = [C["pine_a"], C["pine_b"], C["pine_c"]]
    random.shuffle(tones)
    y = y0 + h_trunk * 0.75
    r = random.uniform(1.25, 1.55) * scale
    for k in range(3):
        depth = (1.7 - 0.25 * k) * scale
        PAINT.cyl(G(x, z, y + depth / 2), r, 0.0, depth, 6, vary(tones[k], 0.1), caps=False,
                  rot=Matrix.Rotation(random.uniform(0, 1.0), 4, "Z"), rough=0.08 * scale)
        y += depth * 0.52
        r *= 0.72


def bush(x, z, s):
    for k in range(random.randint(2, 3)):
        ox, oz = random.uniform(-0.4, 0.4) * s, random.uniform(-0.3, 0.3) * s
        PAINT.box(G(x + ox, z + oz, 0.32 * s), (0.9 * s, 0.8 * s, 0.6 * s), vary(random.choice([C["bush"], C["bush_light"]]), 0.1),
                  yaw=random.uniform(0, 90), rough=0.15 * s)


def grass_tuft(x, z):
    for k in range(3):
        a = random.uniform(0, math.tau)
        h = random.uniform(0.25, 0.45)
        dx, dz = math.cos(a) * 0.12, math.sin(a) * 0.12
        v = [PAINT.bm.verts.new(G(x - dz, z + dx, 0.0)), PAINT.bm.verts.new(G(x + dz, z - dx, 0.0)),
             PAINT.bm.verts.new(G(x + dx * 2.0, z + dz * 2.0, h))]
        f = PAINT.bm.faces.new(v)
        PAINT.paint([f], vary(mix(C["grass"], C["leaf_tip"], random.random()), 0.1), shade=False)


def build_forest():
    count = 0
    x0, x1, z0, z1 = -36.0, 36.0, -38.0, 20.0
    z = z0
    while z < z1:
        x = x0
        while x < x1:
            d = walk_distance(x, z)
            cell = 2.1 if d < 6.0 else 3.2
            px, pz = x + random.uniform(-0.8, 0.8) * cell * 0.5, z + random.uniform(-0.8, 0.8) * cell * 0.5
            dp = walk_distance(px, pz)
            if dp > 0.9:
                scale = random.uniform(0.85, 1.15) * (1.0 + min(1.0, dp / 12.0) * 0.7)
                if dp < 2.2:
                    scale = min(scale, 0.75 + dp * 0.15)  # small trees right at the edge: no canopy over the walk
                pine(px, pz, scale)
                count += 1
            x += cell
        z += 2.1 if -17.0 < z < 16.0 else 3.2
    # a soft edge of bushes, rocks, ferns and tufts just inside the treeline
    for _ in range(70):
        a = random.uniform(0, math.tau)
        x, z = math.cos(a) * random.uniform(11.0, 15.0), math.sin(a) * random.uniform(9.0, 13.0)
        d = walk_distance(x, z)
        if 0.15 < d < 2.5 and not (abs(x) < 3.5 and z < -8.0):
            bush(x, z, random.uniform(0.7, 1.2))
    for _ in range(45):
        x, z = random.uniform(-15, 15), random.uniform(-13, 13)
        d = walk_distance(x, z)
        if 0.0 < d < 3.0:
            rock(x, z, random.uniform(0.35, 0.8))
    for _ in range(170):
        x, z = random.uniform(-13.5, 13.5), random.uniform(-11.5, 11.5)
        d = walk_distance(x, z)
        if d < 1.2 and math.hypot(x, z) > 4.0 and walk_distance(x, z) > -1 and (d > 0.0 or random.random() < 0.35):
            grass_tuft(x, z)
    # little glowing mushrooms at the treeline (cyan: ties the gate's colour into the forest)
    for _ in range(14):
        x, z = random.uniform(-14, 14), random.uniform(-12, 12)
        if 0.3 < walk_distance(x, z) < 1.8:
            CYAN.cyl(G(x, z, 0.12), 0.07, 0.07, 0.24, 4, C["mushroom"], caps=False, shade=False)
            CYAN.cyl(G(x, z, 0.27), 0.17, 0.02, 0.1, 6, C["mushroom"], shade=False)
    return count


def build_campfire():
    x, z = FIRE
    PAINT.cyl(G(x, z, 0.015), 1.0, 1.0, 0.03, 10, C["ash"], shade=False)
    for k in range(10):
        a = math.tau * k / 10 + random.uniform(-0.1, 0.1)
        rock(x + math.cos(a) * 0.95, z + math.sin(a) * 0.95, random.uniform(0.32, 0.42), vary(C["stone"], 0.12))
    for k in range(4):  # crossed burning logs
        a = math.pi * k / 4
        rot = Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.radians(80), 4, "Y")
        PAINT.cyl(G(x, z, 0.14), 0.08, 0.08, 1.15, 6, C["wood_dark"], rot=rot)
    WARM.cyl(G(x, z, 0.06), 0.45, 0.3, 0.1, 8, C["warm"], shade=False)  # glowing embers bed
    collider("campfire", x, z, 1.15, 1.15, 0.6)
    # seats: 3 logs and 2 stumps around the fire, an opening toward the gate (north) and the spawn (south)
    seats = [(-2.6, -0.4, 80), (2.6, -0.5, 100), (-1.8, 2.3, 145), (1.9, 2.3, 30)]
    for i, (sx, sz, yaw) in enumerate(seats):
        rot = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "Y")
        PAINT.cyl(G(sx, sz, 0.26), 0.26, 0.26, 1.7, 7, C["wood"], rot=rot, caps=False)
        for end in (-1, 1):  # light cut ends
            ex = sx + math.cos(math.radians(yaw)) * 0.85 * end
            ez = sz - math.sin(math.radians(yaw)) * 0.85 * end
            PAINT.cyl(G(ex, ez, 0.26), 0.25, 0.25, 0.04, 7, C["wood_light"],
                      rot=Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "Y"), shade=False)
        hx = abs(math.cos(math.radians(yaw))) * 0.85 + 0.25
        hz = abs(math.sin(math.radians(yaw))) * 0.85 + 0.25
        collider("seat_%d" % i, sx, sz, hx * 0.8, hz * 0.8, 0.5)
    for i, (sx, sz) in enumerate([(-2.7, -2.3), (2.8, -2.2)]):
        PAINT.cyl(G(sx, sz, 0.25), 0.38, 0.34, 0.5, 8, C["wood"])
        PAINT.cyl(G(sx, sz, 0.505), 0.33, 0.33, 0.02, 8, C["wood_light"], shade=False)
        collider("stump_%d" % i, sx, sz, 0.35, 0.35, 0.5)


def build_gate():
    before_paint = set(PAINT.bm.faces)
    before_cyan = set(CYAN.bm.faces)
    gx, gz = GATE
    # flush stone platform with a cyan rune circle (walk onto it)
    PAINT.cyl(G(gx, gz, 0.02), 2.0, 2.0, 0.04, 14, C["stone"], shade=False)
    PAINT.cyl(G(gx, gz, 0.045), 1.55, 1.55, 0.02, 14, C["stone_light"], shade=False)
    for k in range(12):  # rune marks in a ring
        a = math.tau * k / 12
        CYAN.box(G(gx + math.cos(a) * 1.75, gz + math.sin(a) * 1.75, 0.05), (0.16, 0.34, 0.02), C["cyan"],
                 yaw=-math.degrees(a), shade=False)
    # the standing ring (portal frame) at the back, facing the camera (south)
    az = GATE_ARCH_Z
    ring_r, n = 2.15, 16
    for k in range(n):
        a = math.tau * (k + 0.5) / n
        cx, cy = math.cos(a) * ring_r, 2.25 + math.sin(a) * ring_r
        if cy < 0.15:
            continue
        stone = vary(mix(C["gate_stone"], C["moss"], 0.4 if cy < 1.2 else random.random() * 0.25), 0.1)
        PAINT.box(G(gx + cx, az, cy), (0.9, 0.62, 0.66), stone, yaw=0.0, tilt=(0.0, -math.degrees(a) + 90), rough=0.05)
        CYAN.box(G(gx + math.cos(a) * (ring_r - 0.36), az + 0.05, 2.25 + math.sin(a) * (ring_r - 0.36)),
                 (0.36, 0.14, 0.12), C["cyan"], tilt=(0.0, -math.degrees(a) + 90), shade=False)
    # two pillars with floating crystals, and a stepped base
    for side in (-1, 1):
        px = gx + side * 2.9
        PAINT.box(G(px, az + 0.2, 0.9), (0.7, 0.7, 1.8), C["gate_stone"], rough=0.06)
        PAINT.box(G(px, az + 0.2, 1.86), (0.86, 0.86, 0.14), C["stone_light"])
        CYAN.cyl(G(px, az + 0.2, 2.25), 0.0, 0.2, 0.32, 4, C["cyan"], shade=False)
        CYAN.cyl(G(px, az + 0.2, 2.57), 0.2, 0.0, 0.32, 4, C["cyan"], shade=False)
        collider("gate_pillar_%s" % ("w" if side < 0 else "e"), px, az + 0.2, 0.45, 0.45, 2.0)
    PAINT.box(G(gx, az, 0.1), (5.0, 1.0, 0.2), C["stone"], rough=0.04)
    collider("gate_arch", gx, az, 2.45, 0.55, 2.5)
    # Keep RNG consumption, replace portal frame/platform with supplied crystal asset.
    bmesh.ops.delete(PAINT.bm, geom=[f for f in PAINT.bm.faces if f not in before_paint], context="FACES")
    bmesh.ops.delete(CYAN.bm, geom=[f for f in CYAN.bm.faces if f not in before_cyan], context="FACES")
    for name in ["gate_pillar_w", "gate_pillar_e", "gate_arch"]: COLLIDERS.pop(name, None)
    # Keep the circular front platform walkable; stop the player at rear pillars.
    collider("crystal_frame", gx, gz - 1.25, 2.4, .45, 4.92)
    return


def lantern(x, z, i, hang=0.0):
    PAINT.box(G(x, z, 1.0), (0.13, 0.13, 2.0), C["wood_dark"])
    PAINT.box(G(x, z, 2.02), (0.5, 0.1, 0.08), C["wood_dark"], yaw=hang)
    lx = x + math.cos(math.radians(hang)) * 0.22
    lz = z - math.sin(math.radians(hang)) * 0.22
    PAINT.box(G(lx, lz, 1.95), (0.26, 0.26, 0.05), C["iron"])
    PAINT.box(G(lx, lz, 1.62), (0.28, 0.28, 0.04), C["iron"])
    WARM.box(G(lx, lz, 1.78), (0.2, 0.2, 0.28), C["warm"], shade=False)
    PAINT.cyl(G(lx, lz, 2.04), 0.2, 0.0, 0.14, 4, C["iron_dark"])
    SPOTS["lantern_%d" % i] = (lx, lz)
    collider("lantern_%d" % i, x, z, 0.2, 0.2, 2.0)


def build_tent():
    before_paint = set(PAINT.bm.faces)
    x, z = TENT
    yaw = 25.0
    R = Matrix.Rotation(math.radians(yaw), 4, "Z")
    base = G(x, z, 0.0)

    def P(px, pz, py):  # tent-local (x across, z depth: + = front/south-east) -> world
        return base + (R @ Vector((px, -pz, py)))
    w, d, h = 1.9, 1.7, 2.3
    PAINT.quad([P(-w, -d, 0.05), P(-w, d, 0.05), P(0, d, h), P(0, -d, h)], C["canvas"])
    PAINT.quad([P(w, d, 0.05), P(w, -d, 0.05), P(0, -d, h), P(0, d, h)], C["canvas_dark"])
    PAINT.quad([P(-w, -d, 0.05), P(0, -d, h), P(w, -d, 0.05)], C["canvas_dark"])  # back wall (triangle)
    # open front flaps folded aside, a dark doorway
    PAINT.quad([P(-0.55, d, 0.05), P(0.55, d, 0.05), P(0, d, 1.5)], C["iron_dark"], shade=False)
    PAINT.quad([P(-w, d, 0.05), P(-0.55, d + 0.25, 0.05), P(-0.25, d + 0.15, 1.2), P(0, d, h)], C["trim"])
    PAINT.quad([P(w, d, 0.05), P(0, d, h), P(0.25, d + 0.15, 1.2), P(0.55, d + 0.25, 0.05)], C["trim"])
    for side in (-1, 1):  # trim strip along the ridge and the hems
        PAINT.quad([P(side * w, -d, 0.05), P(side * w, d, 0.05), P(side * (w - 0.18), d, 0.27), P(side * (w - 0.18), -d, 0.27)],
                   C["trim"])
    PAINT.cyl(P(0, d + 0.05, h * 0.5 + 0.2), 0.05, 0.05, h + 0.3, 5, C["wood_dark"], caps=False)
    PAINT.cyl(P(0, -d - 0.05, h * 0.5 + 0.2), 0.05, 0.05, h + 0.3, 5, C["wood_dark"], caps=False)
    collider("tent", x, z, 2.1, 2.0, 2.4)
    # tailor's corner: a clothes rack with hanging cloths and a bolt of cloth
    rx, rz = -6.0, -5.3
    for side in (-0.75, 0.75):
        PAINT.box(G(rx + side, rz, 0.8), (0.08, 0.08, 1.6), C["wood_dark"])
    PAINT.box(G(rx, rz, 1.58), (1.6, 0.07, 0.07), C["wood_dark"])
    for k, col in enumerate([C["cloth_blue"], C["trim"], C["canvas"], C["cloth_blue"]]):
        PAINT.box(G(rx - 0.55 + k * 0.37, rz, 1.12), (0.3, 0.06, 0.85), col, tilt=(random.uniform(-6, 6), 0))
    PAINT.cyl(G(rx + 0.2, rz + 0.75, 0.16), 0.16, 0.16, 0.9, 7, C["cloth_blue"],
              rot=Matrix.Rotation(math.radians(90), 4, "Y"))
    collider("rack", rx, rz, 0.85, 0.3, 1.6)
    # Consume the same random values before replacing the old tent/rack, so all other scenery stays stable.
    bmesh.ops.delete(PAINT.bm, geom=[f for f in PAINT.bm.faces if f not in before_paint], context='FACES')
    COLLIDERS.pop("rack", None)
    collider("tent", x, z, 2.4, 1.495, 1.868)  # prepared tailor_house asset bounds


def build_forge():
    x, z = FORGE
    before_paint = set(PAINT.bm.faces)
    before_warm = set(WARM.bm.faces)
    PAINT.box(G(x, z, 0.5), (2.2, 1.5, 1.0), C["stone"], rough=0.05)
    PAINT.box(G(x, z, 1.02), (2.3, 1.6, 0.06), C["stone_light"])
    WARM.box(G(x, z + 0.05, 1.07), (1.2, 0.8, 0.04), C["warm"], shade=False)  # glowing coals
    PAINT.box(G(x, z - 0.95, 1.6), (0.9, 0.6, 3.2), C["stone"], rough=0.04)    # chimney at the back
    PAINT.box(G(x, z - 0.95, 3.25), (1.05, 0.75, 0.15), C["stone_light"])
    WARM.box(G(x, z - 0.64, 0.45), (0.7, 0.04, 0.4), C["warm"], shade=False)  # the furnace mouth (front face)
    PAINT.box(G(x + 1.45, z + 0.1, 0.45), (0.7, 0.5, 0.35), C["canvas_dark"], tilt=(0, 15))  # bellows
    ax, az = ANVIL
    PAINT.box(G(ax, az, 0.25), (0.55, 0.55, 0.5), C["wood_dark"])
    PAINT.box(G(ax, az, 0.58), (0.3, 0.22, 0.16), C["iron_dark"])
    PAINT.box(G(ax, az, 0.74), (0.75, 0.32, 0.16), C["iron"])
    PAINT.cyl(G(ax - 0.53, az, 0.76), 0.12, 0.0, 0.32, 5, C["iron"], rot=Matrix.Rotation(math.radians(-90), 4, "Y"))
    PAINT.box(G(ax + 0.05, az - 0.05, 0.86), (0.36, 0.08, 0.06), C["wood_light"], yaw=30)  # hammer handle
    PAINT.box(G(ax + 0.2, az - 0.14, 0.88), (0.1, 0.16, 0.1), C["iron_dark"], yaw=30)
    collider("anvil", ax, az, 0.45, 0.35, 0.9)
    cx, cz = COUNTER
    PAINT.box(G(cx, cz, 0.85), (2.6, 0.75, 0.1), C["plank"])
    for side in (-1, 1):
        PAINT.box(G(cx + side * 1.15, cz, 0.42), (0.18, 0.6, 0.84), C["wood_dark"])
    PAINT.box(G(cx, cz + 0.35, 0.6), (2.5, 0.05, 0.4), C["wood"])
    for k in range(3):  # blades laid out on the counter
        PAINT.box(G(cx - 0.75 + k * 0.6, cz - 0.05, 0.92), (0.11, 0.62, 0.03), C["stone_light"], yaw=random.uniform(-12, 12))
        PAINT.box(G(cx - 0.75 + k * 0.6, cz + 0.3, 0.93), (0.22, 0.06, 0.05), C["brass"])
    collider("counter", cx, cz, 1.35, 0.42, 1.0)
    # weapon rack against the forge's west side
    wx, wz = x - 1.9, z - 0.3
    PAINT.box(G(wx, wz, 0.95), (0.1, 1.2, 0.1), C["wood_dark"])
    PAINT.box(G(wx, wz, 0.2), (0.25, 1.2, 0.1), C["wood_dark"])
    for k in range(4):
        PAINT.box(G(wx + 0.05, wz - 0.45 + k * 0.3, 0.75), (0.05, 0.08, 1.3), C["stone_light"] if k % 2 == 0 else C["wood_light"])
    collider("weapon_rack", wx, wz, 0.25, 0.65, 1.4)

    # Keep RNG consumption stable for all other scenery; replace the entire workshop
    # because the user asset already includes furnace, anvil, counter and rack.
    bmesh.ops.delete(PAINT.bm, geom=[f for f in PAINT.bm.faces if f not in before_paint], context='FACES')
    bmesh.ops.delete(WARM.bm, geom=[f for f in WARM.bm.faces if f not in before_warm], context='FACES')
    collider("forge", 8.8, -6.1, 1.1, 0.6, 2.7)
    collider("anvil", 6.9, -4.8, 0.55, 0.5, 1.1)
    collider("counter", 8.3, -3.65, 1.1, 0.4, 0.9)
    collider("weapon_rack", 7.1, -5.5, 0.4, 0.7, 1.4)


def build_board():
    x, z = BOARD
    yaw = -70.0  # faces east-south-east, toward the fire
    R = Matrix.Rotation(math.radians(yaw), 4, "Z")
    base = G(x, z, 0.0)

    def P(px, py, pz=0.0):
        return base + (R @ Vector((px, pz, py)))
    for side in (-1, 1):
        PAINT.box(P(side * 0.95, 1.05), (0.14, 0.14, 2.1), C["wood_dark"], yaw=yaw)
    PAINT.box(P(0, 1.35, 0.0), (2.1, 0.08, 1.2), C["plank"], yaw=yaw, tilt=(8, 0))
    PAINT.box(P(0, 2.12, 0.05), (2.4, 0.5, 0.08), C["wood_dark"], yaw=yaw, tilt=(-25, 0))  # little roof
    notes = [(-0.6, 1.55), (0.0, 1.62), (0.6, 1.5), (-0.35, 1.08), (0.4, 1.05), (-0.75, 1.15)]
    for k, (nx, ny) in enumerate(notes):
        PAINT.box(P(nx, ny, -0.07), (0.38, 0.03, 0.42), C["paper"] if k != 2 else C["canvas"], yaw=yaw + random.uniform(-6, 6),
                  tilt=(8, 0), shade=False)
        PAINT.box(P(nx, ny + 0.16, -0.09), (0.07, 0.02, 0.07), C["seal"], yaw=yaw, shade=False)
    collider("board", x, z, 0.55, 1.05, 2.2)


def crate(x, z, s=0.7, yaw=0.0, y=0.0):
    PAINT.box(G(x, z, y + s / 2), (s, s, s), C["plank"], yaw=yaw)
    PAINT.box(G(x, z, y + s + 0.01), (s * 0.9, s * 0.12, 0.02), C["wood_dark"], yaw=yaw, shade=False)
    PAINT.box(G(x, z, y + s + 0.01), (s * 0.12, s * 0.9, 0.02), C["wood_dark"], yaw=yaw, shade=False)


def barrel(x, z, s=1.0):
    PAINT.cyl(G(x, z, 0.45 * s), 0.34 * s, 0.34 * s, 0.9 * s, 8, C["wood"])
    PAINT.cyl(G(x, z, 0.3 * s), 0.36 * s, 0.36 * s, 0.07 * s, 8, C["iron_dark"], caps=False)
    PAINT.cyl(G(x, z, 0.72 * s), 0.36 * s, 0.36 * s, 0.07 * s, 8, C["iron_dark"], caps=False)


def build_stall():
    before_paint = set(PAINT.bm.faces)
    x, z = STALL
    PAINT.box(G(x, z, 0.8), (2.6, 1.0, 0.1), C["plank"])
    for sx in (-1.2, 1.2):
        PAINT.box(G(x + sx, z, 0.4), (0.15, 0.85, 0.8), C["wood_dark"])
        PAINT.box(G(x + sx, z + 0.6, 1.25), (0.1, 0.1, 2.5), C["wood_dark"])
    for k in range(5):  # striped canopy, sloping back (north... away from the camera so it hides little)
        col = C["trim"] if k % 2 == 0 else C["canvas"]
        PAINT.box(G(x - 1.04 + k * 0.52, z + 0.25, 2.35), (0.52, 1.5, 0.05), col, tilt=(-22, 0))
    goods = [C["brew"], C["seal"], C["brass"], C["cloth_blue"]]
    for k in range(6):
        PAINT.box(G(x - 1.0 + k * 0.4, z - 0.1, 0.92), (0.22, 0.22, 0.18), goods[k % 4])
    crate(x + 1.9, z - 0.2, 0.75, 12)
    crate(x + 1.85, z + 0.65, 0.65, -8)
    crate(x + 1.9, z - 0.15, 0.55, 30, 0.75)
    barrel(x - 1.9, z + 0.1)
    barrel(x - 2.15, z + 0.85, 0.85)
    PAINT.box(G(x - 1.6, z - 0.75, 0.25), (0.6, 0.5, 0.5), C["sack"], rough=0.06)
    collider("stall", x, z + 0.15, 1.35, 0.65, 2.4)
    collider("stall_crates", x + 1.9, z + 0.2, 0.5, 0.75, 1.4)
    collider("stall_barrels", x - 2.0, z + 0.4, 0.55, 0.9, 1.0)
    # Replace the full old stall, retaining random consumption for stable scenery.
    bmesh.ops.delete(PAINT.bm, geom=[f for f in PAINT.bm.faces if f not in before_paint], context="FACES")
    COLLIDERS.pop("stall_crates", None)
    COLLIDERS.pop("stall_barrels", None)
    collider("stall", x, z, 2.4, 1.172, 2.175)


def build_storage():
    before_paint = set(PAINT.bm.faces)
    x, z = CHEST
    yaw = 10.0
    PAINT.box(G(x, z, 0.32), (1.3, 0.8, 0.64), C["plank"], yaw=yaw)
    PAINT.cyl(G(x, z, 0.64), 0.4, 0.4, 1.3, 7, C["wood"], rot=Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "Y"))
    for side in (-0.45, 0.45):
        PAINT.box(G(x + side, z, 0.5), (0.1, 0.84, 0.98), C["brass"], yaw=yaw)
    PAINT.box(G(x, z + 0.42, 0.55), (0.18, 0.04, 0.2), C["brass"], yaw=yaw)  # lock
    crate(x - 1.3, z + 0.3, 0.7, 20)
    crate(x - 1.25, z + 0.3, 0.55, -5, 0.7)
    crate(x - 1.5, z - 0.55, 0.6, 40)
    barrel(x + 1.2, z + 0.4, 0.9)
    collider("storage", x - 0.35, z, 1.35, 0.7, 1.4)
    collider("storage_barrel", x + 1.2, z + 0.4, 0.35, 0.35, 1.0)
    # Keep RNG consumption, replace old chest/clutter with the supplied storage station.
    bmesh.ops.delete(PAINT.bm, geom=[f for f in PAINT.bm.faces if f not in before_paint], context="FACES")
    COLLIDERS.pop("storage_barrel", None)
    collider("storage", x, z, 2.4, 0.738, 2.011)


def build_cauldron():
    before_paint = set(PAINT.bm.faces)
    before_warm = set(WARM.bm.faces)
    x, z = CAULDRON
    PAINT.cyl(G(x, z, 0.03), 0.8, 0.8, 0.04, 8, C["ash"], shade=False)
    WARM.cyl(G(x, z, 0.08), 0.32, 0.22, 0.08, 6, C["warm"], shade=False)
    PAINT.cyl(G(x, z, 0.45), 0.38, 0.62, 0.55, 9, C["iron_dark"])
    PAINT.cyl(G(x, z, 0.75), 0.66, 0.66, 0.06, 9, C["iron"], caps=False)
    PAINT.cyl(G(x, z, 0.72), 0.58, 0.58, 0.02, 9, C["brew"], shade=False)
    for k in range(3):
        a = math.tau * k / 3 + 0.4
        PAINT.box(G(x + math.cos(a) * 0.7, z + math.sin(a) * 0.7, 0.75), (0.07, 0.07, 1.6), C["wood_dark"],
                  yaw=-math.degrees(a), tilt=(0, 14))
    PAINT.box(G(x + 0.5, z + 0.5, 0.95), (0.05, 0.05, 0.9), C["wood_light"], tilt=(28, 0))  # ladle
    crate(x - 1.2, z - 0.4, 0.55, 25)
    PAINT.box(G(x + 1.0, z - 0.6, 0.22), (0.55, 0.45, 0.45), C["sack"], rough=0.06)
    collider("cauldron", x, z, 0.75, 0.75, 1.0)
    collider("cauldron_crate", x - 1.2, z - 0.4, 0.35, 0.35, 0.6)
    # The Tailor asset supplies its own dye pots; remove this duplicate station.
    # Preserve random consumption so later scenery remains exactly where it was.
    bmesh.ops.delete(PAINT.bm, geom=[f for f in PAINT.bm.faces if f not in before_paint], context='FACES')
    bmesh.ops.delete(WARM.bm, geom=[f for f in WARM.bm.faces if f not in before_warm], context='FACES')
    COLLIDERS.pop("cauldron", None)
    COLLIDERS.pop("cauldron_crate", None)


def build_extras():
    # stepping stones from the fire to the gate
    for k in range(6):
        zz = -1.9 - k * 1.05
        PAINT.box(G(random.uniform(-0.3, 0.3), zz, 0.015), (random.uniform(0.6, 0.85), 0.55, 0.04), vary(C["stone_light"], 0.1),
                  yaw=random.uniform(-25, 25), rough=0.02)
    # Legacy firewood blocked the Tailor approach. Consume its original random
    # draws, then discard its faces so rebuilding does not move other scenery.
    before_firewood = set(PAINT.bm.faces)
    for k in range(4):
        PAINT.cyl(G(-4.3, -1.6 + k * 0.0, 0.12 + k * 0.0) + Vector((0, k * 0.24, (k % 2) * 0.2)), 0.1, 0.1, 0.9, 5, C["wood"],
                  rot=Matrix.Rotation(math.radians(90), 4, "Y"))
    bmesh.ops.delete(PAINT.bm, geom=[f for f in PAINT.bm.faces if f not in before_firewood], context='FACES')
    crate(5.3, -6.6, 0.6, 15)
    barrel(4.7, -7.3, 0.8)
    collider("forge_crates", 5.0, -6.95, 0.6, 0.65, 0.8)


def build_plaza():
    # Open social square: no economy/camp-level buildings or additional texture assets.
    x, z = 0.0, -22.0
    PAINT.cyl(G(x, z, 0.025), 4.4, 4.4, 0.05, 20, C["stone"], shade=False)
    PAINT.cyl(G(x, z, 0.055), 3.9, 3.9, 0.02, 20, C["dirt_light"], shade=False)
    for side in (-1, 1):
        for depth in (-18.0, -25.0):
            PAINT.box(G(side * 8.5, depth, .4), (2.2, .65, .8), C["wood_dark"])
            collider("plaza_bench_%s_%s" % (side, depth), side*8.5, depth, 1.1, .33, .8)
    for k in range(12):
        PAINT.box(G(0, -9.0-k*1.55, .015), (1.3, .7, .03), C["stone_light"], yaw=(k%3-1)*8, shade=False)
    # Bring the forest in beside the portal, leaving the middle approach open.
    state = random.getstate()
    random.seed(20261020)
    for side in (-1, 1):
        for index, (px, pz, scale) in enumerate([
            (4.4, -29.0, 1.15), (4.0, -32.0, 1.2),
            (6.7, -30.0, 1.35), (6.6, -33.0, 1.3),
        ]):
            pine(side * px, pz, scale)
            collider("warp_pine_%s_%s" % (side, index), side*px, pz, .23*scale, .23*scale, 2.0)
    random.setstate(state)


def build_markers():
    for name, spot in SPOTS.items():
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "SPHERE"
        e.empty_display_size = 0.3
        e.location = G(spot[0], spot[1], 0.0)
        scene.collection.objects.link(e)
    e = bpy.data.objects.new("bounds", None)
    e.empty_display_type = "CUBE"
    e.location = G(0, 0, 0)
    e.scale = (BOUNDS[0], BOUNDS[1], 1.0)  # Blender y = game -z: half extents x, z
    scene.collection.objects.link(e)
    # the clearing's notched corners (trees grow there)
    hx, hz = (WALK_A[0] - WALK_B[0]) / 2, (WALK_B[1] - WALK_A[1]) / 2
    for sx in (-1, 1):
        for sz in (-1, 1):
            collider("corner_%s%s" % ("w" if sx < 0 else "e", "n" if sz < 0 else "s"),
                     sx * (WALK_B[0] + hx), sz * (WALK_A[1] + hz), hx, hz, 3.0)
    # Simulation bounds are centered; fence off the unused southern extension.
    collider("south_limit", 0, 22, 13.5, 11.5, 3.0)
    for side in (-1, 1):
        collider("plaza_path_side_%s" % side, side*8.0, -11.5, 5.0, 1.5, 3.0)
    for name, (x, z, hx, hz, h) in COLLIDERS.items():
        e = bpy.data.objects.new("col_" + name, None)
        e.empty_display_type = "CUBE"
        e.location = G(x, z, h / 2)
        e.scale = (hx, hz, h / 2)
        scene.collection.objects.link(e)


# ------------------------------------------------------------------------------------------------- main
build_ground()
trees = build_forest()
before_fire = {layer: set(layer.bm.faces) for layer in (PAINT, WARM, CYAN)}
build_campfire()
for layer in (PAINT, WARM, CYAN):
    bmesh.ops.delete(layer.bm, geom=[f for f in layer.bm.faces if f not in before_fire[layer]], context='FACES')
for name in list(COLLIDERS):
    if name.startswith(('seat_', 'stump_')): COLLIDERS.pop(name)
build_gate()
for i, (lx, lz) in enumerate(LANTERNS):
    lantern(lx, lz, i + 1, hang=random.choice([0.0, 180.0]) if abs(lx) > 3 else (0.0 if lx > 0 else 180.0))
build_tent()
build_forge()
build_board()
build_stall()
build_storage()
build_cauldron()
build_extras()
build_plaza()
build_markers()

total = 0
for layer in (PAINT, WARM, CYAN):
    obj, tris = layer.build()
    total += tris
    print("MESH %-16s %6d tris" % (obj.name, tris))
print("TREES", trees, " COLLIDERS", len(COLLIDERS) + 4, " TOTAL TRIS", total)

os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
kwargs = dict(filepath=OUT_GLB, export_format="GLB", use_selection=False, export_yup=True, export_apply=True,
              export_animations=False, export_cameras=False, export_lights=False)
try:
    bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
except TypeError:
    bpy.ops.export_scene.gltf(**kwargs)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("EXPORTED", OUT_GLB)

# Preserve the Lv2 farm clearance when the camp source is rebuilt.
import runpy
runpy.run_path(os.path.join(ROOT,"tools/maps/split_farm_trees.py"))["split_farm_trees"](OUT_GLB)

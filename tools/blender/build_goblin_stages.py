"""Goblin-forest stages (Boss 2026-10-13: every journey stage is ONE small arena; portals appear when it is
cleared). Builds the art AND the map data from one layout, so the glb's gameplay empties and the map JSON
can never drift apart:

    art/maps/goblin_forest/<map_id>.glb     low-poly, vertex-coloured, one mesh per material
    data/maps/<map_id>.json                 bounds / spawn / solids / enemy_spawns / exit_portals / ...

Run:  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_goblin_stages.py [-- <map_id> ...]
Then: godot --headless --path . --import   (and the tests)

Coordinates in this file are GODOT coordinates: x = east, y = up, z = south (the camera sits south and looks
north, so "up-screen" = -z). P() converts to Blender (x, -z, y); glTF export converts back.

Gameplay empties in every glb: spawn, enemy_0..n, exit_portal_0, exit_portal_1 (+ campfire in the rest map)
and light_fire_* / light_lantern_* / light_glow_* (client/stage_props.gd puts an OmniLight3D on each).
Colliders are NOT in the glb: they are the map's `solids` (each obstacle below = art + its solid box; the art
is built a little larger than the box so the box never shows).

Materials (merged per material -> one draw call each): gf_main (vertex colour, rough), gf_fire (warm
emissive: flames, embers, lantern), gf_glow (cool emissive: night mushrooms, fireflies).
"""
import bpy, bmesh, math, random, json, os, sys
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ART_DIR = os.path.join(ROOT, "art/maps/goblin_forest")
MAP_DIR = os.path.join(ROOT, "data/maps")
RES_ART = "res://art/maps/goblin_forest/"
ORC_KIT_GLB = os.path.join(ROOT, "art/props/orc_camp/orc_kit.glb")   # tools/blender/build_orc_kit.py (Boss 2026-10-15)
ORC_ATLAS = os.path.join(ROOT, "art/props/orc_camp/orc_kit_atlas.png")
ORC_ATLAS_URI = "../../props/orc_camp/orc_kit_atlas.png"   # (relative to the stage glb: every stage shares the one atlas)
ORC_NORMAL = os.path.join(ROOT, "art/props/orc_camp/orc_kit_normal.png")   # (kit v2, Boss 2026-10-16: + its normal map)
ORC_NORMAL_URI = "../../props/orc_camp/orc_kit_normal.png"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["ORC_KIT_IMPORT"] = "1"
import build_orc_kit  # noqa: E402  (glb_external_image)
FLOOR_Y = 0.02     # the art ground sits just above the map's floor solid (its top is y = 0)
SPOT_Y = 0.05      # gameplay positions (as the other maps)


def P(x, y, z):
    return Vector((x, -z, y))


def clamp(v):
    return max(0.0, min(1.0, v))


GAIN = 1.0  # per stage: the palette below is painted dark; night stages lift it so they read from the camera
PAINT_GAIN = 1.0  # the gain in use: GAIN for gf_main, 1.0 for the emissive materials (set by Kit.bm)


def paint(c, k=1.0):
    """Palette colour (sRGB as painted) x brightness -> the LINEAR float colour stored in the mesh (COLOR_0)."""
    def lin(v):
        v = clamp(v * k * PAINT_GAIN)
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (lin(c[0]), lin(c[1]), lin(c[2]), 1.0)


def mix(a, b, t):
    t = clamp(t)
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def hash_noise(x, z, s=0.0):
    """Cheap smooth-ish value noise (sum of sines), -1..1."""
    return (math.sin(x * 0.53 + s) * math.cos(z * 0.61 - s * 1.3) * 0.5
            + math.sin(x * 1.37 + z * 1.11 + s * 2.1) * 0.3 + math.sin(x * 2.9 - z * 2.3) * 0.2)


# ---------------------------------------------------------------- palette (sRGB as painted)
DIRT = (0.29, 0.22, 0.15)
DIRT_LIGHT = (0.40, 0.31, 0.20)
MOSS = (0.17, 0.25, 0.15)
FOREST_FLOOR = (0.11, 0.15, 0.13)   # (2026-10-13 r2: was 0.06 = black from the camera; the rim must still read)
BARK = (0.17, 0.12, 0.09)
CONIFER = [(0.06, 0.15, 0.13), (0.08, 0.19, 0.15), (0.05, 0.12, 0.12)]
BROAD = [(0.10, 0.17, 0.10), (0.13, 0.20, 0.11), (0.08, 0.14, 0.11)]
WOOD = (0.33, 0.23, 0.14)
WOOD_TIP = (0.50, 0.42, 0.30)
ROPE = (0.42, 0.33, 0.20)
HIDE = [(0.44, 0.31, 0.20), (0.33, 0.25, 0.18), (0.52, 0.38, 0.25), (0.38, 0.30, 0.22)]
RAG_RED = (0.32, 0.09, 0.08)
BONE = (0.50, 0.47, 0.40)
ROOT_RED = (0.27, 0.05, 0.06)
ROOT_TIP = (0.44, 0.12, 0.09)
STONE = (0.25, 0.24, 0.22)
STONE_MOSS = (0.15, 0.22, 0.11)
TOTEM = [(0.36, 0.25, 0.16), (0.27, 0.19, 0.13)]
PAINT_RED = (0.42, 0.10, 0.07)
FIRE = (1.0, 0.55, 0.16)
GLOW = (0.45, 0.85, 0.95)
# rest camp: greener, softer
CAMP_GRASS = (0.20, 0.32, 0.15)
CAMP_GRASS_LIGHT = (0.30, 0.42, 0.18)
CAMP_PATH = (0.36, 0.29, 0.19)
CAMP_FLOWERS = [(0.85, 0.75, 0.40), (0.80, 0.50, 0.55), (0.70, 0.75, 0.90)]
CANVAS = [(0.52, 0.48, 0.40), (0.46, 0.42, 0.34)]
CRATE = (0.40, 0.31, 0.21)
# quarry (arena C): dusty worked stone, warm not icy (r3 round 2: the first grey-blue palette lit by the
# moon read as an ice level, so every stone here is darker and browner than real granite)
QUARRY_STONE = (0.22, 0.20, 0.19)
QUARRY_LIGHT = (0.34, 0.29, 0.23)
QUARRY_DARK = (0.13, 0.12, 0.12)
GRAVEL = (0.30, 0.26, 0.21)
GRAVEL_LIGHT = (0.43, 0.37, 0.29)
OCHRE = (0.38, 0.27, 0.15)
RUST = (0.30, 0.17, 0.11)
IRON = (0.18, 0.17, 0.18)
WATER_DARK = (0.20, 0.22, 0.22)


class Kit:
    """Accumulates geometry per material in bmeshes (merge per material = one draw call each)."""

    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.bms = {}
        self.empties = []  # (name, Vector godot)

    def bm(self, mat):
        global PAINT_GAIN
        PAINT_GAIN = GAIN if mat == "gf_main" else 1.0  # (flames keep their own colours, never washed to white)
        if mat not in self.bms:
            b = bmesh.new()
            b.loops.layers.float_color.new("Col")
            if mat == "orc_kit":
                b.loops.layers.uv.new("UVMap")
                for k in ("lnx", "lny", "lnz"):   # the kit's shading normals (set as custom normals in build())
                    b.loops.layers.float.new(k)
            self.bms[mat] = b
        return self.bms[mat]

    def light(self, kind, pos):
        """A light_* empty with the next free number (kit lights start at 10, clear of the hand-named ones)."""
        self.light_n = getattr(self, "light_n", 10) + 1
        self.empty("%s_%d" % (kind, self.light_n), pos)

    def orc(self, name, x, z, yaw=0.0, s=1.0, scale=None, y=0.0, lights=None):
        """Places an orc-kit piece (tools/blender/build_orc_kit.py): standing at (x, y, z), turned `yaw` degrees
        (0 = its front faces +z, the camera; 90 = faces +x), scaled `s` or per axis `scale` = (sx, sy, sz) in its
        own frame. Textured faces go to the orc_kit mesh, its flames to gf_fire (unshaded). `lights`: None = an
        empty on every light anchor of the piece, else a list of anchor indices ([] = none)."""
        kit_data = orc_kit()
        K = kit_data[name] if name in kit_data else kit_data[name[:-3]]   # (shared spec-budget mesh; historical _lo names are aliases)
        sx, sy, sz = scale or (s, s, s)
        a = math.radians(yaw)
        ca, sa = math.cos(a), math.sin(a)

        def tf(p):
            px, py, pz = p[0] * sx, p[1] * sy, p[2] * sz
            return (x + px * ca + pz * sa, y + py, z - px * sa + pz * ca)

        def tn(n):   # a normal through the same (per-axis scale, yaw) -> Blender coords
            px, py, pz = n[0] / sx, n[1] / sy, n[2] / sz
            v = Vector((px * ca + pz * sa, py, -px * sa + pz * ca)).normalized()
            return (v.x, -v.z, v.y)
        made = {}
        for mat in ("orc_kit", "gf_fire"):
            b = self.bm(mat)
            col = b.loops.layers.float_color["Col"]
            uvl = b.loops.layers.uv.get("UVMap") if mat == "orc_kit" else None
            lnl = [b.loops.layers.float[k] for k in ("lnx", "lny", "lnz")] if mat == "orc_kit" else None
            vmap = {}
            for (idx, uvs, cols, fire, nrms) in K["faces"]:
                if fire != (mat == "gf_fire"):
                    continue
                vs = []
                for i in idx:
                    if i not in vmap:
                        vmap[i] = b.verts.new(P(*tf(K["verts"][i])))
                    vs.append(vmap[i])
                try:
                    f = b.faces.new(vs)
                except ValueError:
                    continue
                f.smooth = True
                for l, uv, c, n in zip(f.loops, uvs, cols, nrms):
                    l[col] = c
                    if uvl is not None:
                        l[uvl].uv = uv
                        l[lnl[0]], l[lnl[1]], l[lnl[2]] = tn(n)
            made[mat] = len(vmap)
        at = K["lights"]["at"]
        for i, p in enumerate(at):
            if lights is None or i in lights:
                self.light(K["lights"]["kind"], tf(p))

    def r(self, a, b):
        return self.rng.uniform(a, b)

    def pick(self, seq):
        return seq[self.rng.randrange(len(seq))]

    def _faces(self, b, verts, faces_idx, color, jitter, shade=None):
        layer = b.loops.layers.float_color["Col"]
        for idx in faces_idx:
            try:
                f = b.faces.new([verts[i] for i in idx])
            except ValueError:
                continue
            k = 1.0 + self.r(-jitter, jitter)
            for loop in f.loops:
                c = shade(loop.vert.co, f) if shade else color
                loop[layer] = paint(c, k)

    def prism(self, mat, base, r1, r2, h, seg, color, rot=None, jitter=0.07, cap_top=True, cap_bottom=False,
              top_color=None, squash=(1.0, 1.0), twist=0.0):
        """A tapered n-gon column standing on `base` (Godot coords). r2 == 0 -> a cone (apex)."""
        b = self.bm(mat)
        R = rot or Matrix.Identity(3)
        o = P(*base)
        verts = []
        for ring, (rad, z) in enumerate(((r1, 0.0), (r2, h))):
            if rad <= 0.0:
                verts.append(b.verts.new(o + R @ Vector((0, 0, z))))
                continue
            for i in range(seg):
                a = (i / seg) * math.tau + twist * ring
                verts.append(b.verts.new(o + R @ Vector((math.cos(a) * rad * squash[0], math.sin(a) * rad * squash[1], z))))
        faces = []
        apex = r2 <= 0.0
        for i in range(seg):
            j = (i + 1) % seg
            if apex:
                faces.append((i, j, seg))
            else:
                faces.append((i, j, seg + j, seg + i))
        if cap_top and not apex:
            faces.append(tuple(range(seg, 2 * seg)))
        if cap_bottom:
            faces.append(tuple(reversed(range(seg))))
        tc = top_color

        def shade(co, f):
            if tc is None:
                return color
            return mix(color, tc, (R.transposed() @ (co - o)).z / max(h, 0.001))
        self._faces(b, verts, faces, color, jitter, shade if tc else None)

    def tube(self, mat, a, bpt, r1, r2, seg, color, top_color=None, jitter=0.07):
        """A tapered column from Godot point a to Godot point b."""
        A, B = P(*a), P(*bpt)
        d = B - A
        R = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
        ga = (A.x, A.z, -A.y)
        self.prism(mat, ga, r1, r2, d.length, seg, color, rot=R, jitter=jitter, cap_top=r2 > 0, top_color=top_color)

    def blob(self, mat, center, radius, color, scale=(1, 1, 1), subdiv=2, jitter=0.08, wobble=0.12,
             shade=None, rot_z=0.0):
        b = self.bm(mat)
        M = (Matrix.Translation(P(*center)) @ Matrix.Rotation(rot_z, 4, 'Z')
             @ Matrix.Diagonal((scale[0], scale[2], scale[1], 1.0)))
        res = bmesh.ops.create_icosphere(b, subdivisions=subdiv, radius=radius, matrix=Matrix.Identity(4))
        vs = res['verts']
        for v in vs:
            v.co *= 1.0 + self.r(-wobble, wobble)
            v.co = M @ v.co
        layer = b.loops.layers.float_color["Col"]
        for f in {f for v in vs for f in v.link_faces}:
            k = 1.0 + self.r(-jitter, jitter)
            for loop in f.loops:
                c = shade(loop.vert.co, f) if shade else color
                loop[layer] = paint(c, k)

    def box(self, mat, center, size, color, yaw=0.0, tilt=(0.0, 0.0), jitter=0.06, shade=None):
        b = self.bm(mat)
        M = (Matrix.Translation(P(*center)) @ Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Rotation(tilt[0], 4, 'X')
             @ Matrix.Rotation(tilt[1], 4, 'Y') @ Matrix.Diagonal((size[0], size[2], size[1], 1.0)))
        res = bmesh.ops.create_cube(b, size=1.0, matrix=M)
        layer = b.loops.layers.float_color["Col"]
        for f in {f for v in res['verts'] for f in v.link_faces}:
            k = 1.0 + self.r(-jitter, jitter)
            for loop in f.loops:
                c = shade(loop.vert.co, f) if shade else color
                loop[layer] = paint(c, k)

    def flat(self, mat, center, radius, seg, color, y=0.035, squash=(1.0, 1.0), yaw=0.0, jitter=0.06):
        """A flat n-gon on the ground (stones, puddles, glow rings)."""
        self.prism(mat, (center[0], y - 0.03, center[2]), radius, radius * 0.92, 0.03, seg, color,
                   rot=Matrix.Rotation(yaw, 3, 'Z'), squash=squash, jitter=jitter)

    def empty(self, name, pos):
        self.empties.append((name, Vector(pos)))


_ORC = None


def orc_kit():
    """The orc kit pieces as plain data (Godot coords, per-loop uv/colour, fire flag), read once from the kit glb
    and cached across the stages (each stage build resets Blender's scene)."""
    global _ORC
    if _ORC is not None:
        return _ORC
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=ORC_KIT_GLB)
    _ORC = {}
    for ob in [o for o in bpy.data.objects if o not in before]:
        if ob.type != 'MESH':
            continue
        me = ob.data
        mw = ob.matrix_world
        verts = [tuple(mw @ v.co) for v in me.vertices]
        verts = [(v[0], v[2], -v[1]) for v in verts]   # Blender -> Godot
        uv = me.uv_layers.active.data
        cn = [(n.vector[0], n.vector[2], -n.vector[1]) for n in me.corner_normals]   # (Blender -> Godot)
        ca = me.color_attributes.get("Col") or me.color_attributes[0]
        fire_mats = {i for i, m in enumerate(me.materials) if m and m.name.startswith("orc_kit_fire")}
        faces = []
        for poly in me.polygons:
            li = list(poly.loop_indices)
            if ca.domain == 'CORNER':
                cols = [tuple(ca.data[k].color) for k in li]
            else:
                cols = [tuple(ca.data[me.loops[k].vertex_index].color) for k in li]
            faces.append((list(poly.vertices), [tuple(uv[k].uv) for k in li], cols, poly.material_index in fire_mats,
                          [cn[k] for k in li]))
        name = ob.name.split(".")[0]
        lights = json.loads(ob.get("lights", '{"kind": "", "at": []}'))
        _ORC[name] = {"verts": verts, "faces": faces, "lights": lights}
    for ob in [o for o in bpy.data.objects if o not in before]:
        bpy.data.objects.remove(ob, do_unlink=True)
    for m in [m for m in bpy.data.materials if m.name.startswith("orc_kit")]:
        bpy.data.materials.remove(m)   # (so the stage's own material keeps the plain name "orc_kit")
    return _ORC


# ---------------------------------------------------------------- scenery pieces

def ground(kit, half_x, z0, z1, cell, colour_at, height_at):
    b = kit.bm("gf_main")
    layer = b.loops.layers.float_color["Col"]
    nx = int(round(2 * half_x / cell))
    nz = int(round((z1 - z0) / cell))
    grid = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            x = -half_x + i * cell
            z = z0 + j * cell
            row.append(b.verts.new(P(x, height_at(x, z), z)))
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            # alternate the diagonal so the facets read as soft, not striped
            q = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
            tris = [(q[0], q[1], q[2]), (q[0], q[2], q[3])] if (i + j) % 2 else [(q[0], q[1], q[3]), (q[1], q[2], q[3])]
            for t in tris:
                f = b.faces.new(t[::-1])  # (wound to face UP: the game draws stage art one-sided, Boss 2026-10-15)
                for loop in f.loops:
                    v = loop.vert
                    loop[layer] = paint(colour_at(v.co.x, -v.co.y), 1.0 + 0.04 * hash_noise(v.co.x * 3.1, v.co.y * 2.7, 9.0))


def conifer(kit, x, z, h):
    kit.prism("gf_main", (x, -0.05, z), 0.22 * h / 8, 0.12 * h / 8, h * 0.45, 5, BARK, cap_top=False)
    col = kit.pick(CONIFER)
    tiers = 3 if h > 6.5 else 2
    for t in range(tiers):
        f = t / tiers
        rad = (2.0 - 1.1 * f) * h / 8.5
        base = h * (0.25 + 0.24 * t)
        kit.prism("gf_main", (x, base, z), rad, 0.0, h * 0.42, 7, col, twist=0.0,
                  top_color=mix(col, (0.18, 0.30, 0.26), 0.6), jitter=0.10)


def broadleaf(kit, x, z, h, palette=BROAD):
    kit.tube("gf_main", (x, -0.05, z), (x + kit.r(-0.3, 0.3), h * 0.55, z + kit.r(-0.3, 0.3)), 0.28, 0.16, 5, BARK)
    col = kit.pick(palette)
    for k in range(2 if h > 7.0 else 1):
        rad = h * kit.r(0.22, 0.30) * (1.0 if h > 7.0 else 1.25)
        kit.blob("gf_main", (x + kit.r(-0.8, 0.8), h * (0.62 + 0.18 * k), z + kit.r(-0.8, 0.8)), rad, col,
                 scale=(1.0, 0.8, 1.0), subdiv=2, wobble=0.14,
                 shade=lambda co, f, c=col: mix(c, (c[0] * 1.6, c[1] * 1.5, c[2] * 1.3), (co.z - h * 0.5) / (h * 0.6)))


def dead_tree(kit, x, z, h):
    kit.tube("gf_main", (x, -0.05, z), (x, h, z), 0.26, 0.05, 5, (0.20, 0.15, 0.12))
    for k in range(3):
        y = h * kit.r(0.45, 0.85)
        a = kit.r(0, math.tau)
        L = kit.r(1.0, 1.8)
        kit.tube("gf_main", (x, y, z), (x + math.cos(a) * L, y + kit.r(0.4, 1.0), z + math.sin(a) * L), 0.09, 0.02, 4,
                 (0.20, 0.15, 0.12))


def bush(kit, x, z, s, palette=BROAD):
    col = kit.pick(palette)
    for k in range(2):
        kit.blob("gf_main", (x + kit.r(-0.4, 0.4) * s, 0.25 * s, z + kit.r(-0.4, 0.4) * s), kit.r(0.45, 0.65) * s, col,
                 scale=(1.0, 0.7, 1.0), subdiv=1, wobble=0.15)


def fern(kit, x, z, s, col=(0.12, 0.24, 0.13)):
    for k in range(5):
        a = k / 5 * math.tau + kit.r(-0.3, 0.3)
        kit.tube("gf_main", (x, 0.0, z), (x + math.cos(a) * 0.6 * s, 0.35 * s, z + math.sin(a) * 0.6 * s), 0.08 * s, 0.0, 3,
                 col, jitter=0.15)


def rock(kit, x, z, s, mossy=True, y=0.0):
    def shade(co, f):
        up = f.normal.z
        return mix(STONE, STONE_MOSS, (up - 0.35) * 2.0) if mossy else STONE
    kit.blob("gf_main", (x, y + 0.45 * s, z), 0.8 * s, STONE, scale=(1.15, 0.85, 1.0), subdiv=2, wobble=0.16,
             shade=shade, rot_z=kit.r(0, math.tau))


def big_rock(kit, x, z, solid_size):
    """A moss rock cluster wrapping a solid box (solid_size = (sx, sy, sz))."""
    sx, sy, sz = solid_size

    def shade(co, f):
        return mix(STONE, STONE_MOSS, (f.normal.z - 0.3) * 2.2)
    r = math.sqrt((sx / 2) ** 2 + (sy / 2) ** 2 + (sz / 2) ** 2) * 1.17
    kit.blob("gf_main", (x, sy * 0.5, z), r, STONE, scale=(1.0, sy / (2 * r) * 1.25 + 0.15, 1.0), subdiv=2, wobble=0.06,
             shade=shade, rot_z=kit.r(0, math.tau))
    for k in range(3):
        a = kit.r(0, math.tau)
        rock(kit, x + math.cos(a) * r * 0.95, z + math.sin(a) * r * 0.95, kit.r(0.45, 0.7))


def palisade(kit, a, b, gaps=(), height=(2.2, 2.9), spacing=0.42, lean=0.10):
    """A row of sharpened logs from a to b (Godot x,z) with a lashing rail; gaps = [(x, z, half_width)]."""
    ax, az = a
    bx, bz = b
    L = math.hypot(bx - ax, bz - az)
    n = max(2, int(L / spacing))
    nx, nz = (bz - az) / L, -(bx - ax) / L  # normal (lean direction)
    for i in range(n + 1):
        t = i / n
        x, z = ax + (bx - ax) * t, az + (bz - az) * t
        if any(math.hypot(x - gx, z - gz) < gw for gx, gz, gw in gaps):
            continue
        h = kit.r(*height)
        top = (x + nx * lean * h + kit.r(-0.05, 0.05), h, z + nz * lean * h)
        r = kit.r(0.16, 0.21)
        kit.tube("gf_main", (x, -0.1, z), top, r, r * 0.9, 6, WOOD, top_color=mix(WOOD, WOOD_TIP, 0.5))
        d = Vector((top[0] - x, top[1] + 0.1, top[2] - z)).normalized()
        kit.tube("gf_main", top, (top[0] + d.x * 0.5, top[1] + d.y * 0.5, top[2] + d.z * 0.5), r * 0.9, 0.0, 6, WOOD_TIP)
    # two lashing rails (skip the gaps by splitting)
    segs = [(0.0, 1.0)]
    for gx, gz, gw in gaps:
        tg = ((gx - ax) * (bx - ax) + (gz - az) * (bz - az)) / (L * L)
        dg = gw / L
        new = []
        for s0, s1 in segs:
            if tg + dg < s0 or tg - dg > s1:
                new.append((s0, s1))
            else:
                if tg - dg > s0:
                    new.append((s0, tg - dg))
                if tg + dg < s1:
                    new.append((tg + dg, s1))
        segs = new
    for s0, s1 in segs:
        for y in (0.7, 1.6):
            p0 = (ax + (bx - ax) * s0 + nx * (0.2 + lean * y), y, az + (bz - az) * s0 + nz * (0.2 + lean * y))
            p1 = (ax + (bx - ax) * s1 + nx * (0.2 + lean * y), y + kit.r(-0.1, 0.1), az + (bz - az) * s1 + nz * (0.2 + lean * y))
            kit.tube("gf_main", p0, p1, 0.07, 0.07, 4, ROPE)


def spike_cluster(kit, x, z, facing):
    """Crossed sharpened stakes (a goblin 'cheval de frise')."""
    for k in range(3):
        a = facing + (k - 1) * 0.5
        dx, dz = math.cos(a), math.sin(a)
        kit.tube("gf_main", (x - dx * 0.6, 0.05, z - dz * 0.6), (x + dx * 0.9, 1.1, z + dz * 0.9), 0.08, 0.0, 5, WOOD,
                 top_color=WOOD_TIP)


def tent(kit, x, z, s=1.0, yaw=0.0):
    """Crude goblin tent: patchy hide cone on crooked poles that poke out of the top."""
    col = kit.pick(HIDE)
    b = kit.bm("gf_main")
    seg = 6
    R, H = 1.5 * s, 2.3 * s
    o = P(x, 0.0, z)
    ring = []
    for i in range(seg):
        a = i / seg * math.tau + yaw
        rr = R * kit.r(0.85, 1.1)
        ring.append(b.verts.new(o + Vector((math.cos(a) * rr, math.sin(a) * rr, kit.r(-0.05, 0.15)))))
    mid = []
    for i in range(seg):
        a = (i + 0.5) / seg * math.tau + yaw
        mid.append(b.verts.new(o + Vector((math.cos(a) * R * 0.55, math.sin(a) * R * 0.55, H * 0.55))))
    apex = b.verts.new(o + Vector((kit.r(-0.1, 0.1), kit.r(-0.1, 0.1), H)))
    layer = b.loops.layers.float_color["Col"]
    for i in range(seg):
        j = (i + 1) % seg
        for tri in ((ring[i], ring[j], mid[i]), (mid[i], ring[j], mid[j]), (mid[i], mid[j], apex)):
            f = b.faces.new(tri)
            c = kit.pick(HIDE) if kit.rng.random() < 0.45 else col
            k = kit.r(0.85, 1.12)
            for loop in f.loops:
                loop[layer] = paint(c, k)
    for k in range(3):
        a = k / 3 * math.tau + yaw + 0.4
        kit.tube("gf_main", (x + math.cos(a) * 0.25 * s, H * 0.75, z + math.sin(a) * 0.25 * s),
                 (x - math.cos(a) * 0.35 * s, H + 0.6 * s, z - math.sin(a) * 0.35 * s), 0.05, 0.03, 4, WOOD)
    # a dark doorway flap facing the arena (south-ish)
    kit.box("gf_main", (x + math.sin(yaw) * 0.0, 0.5 * s, z + R * 0.62), (0.7 * s, 1.0 * s, 0.08), (0.08, 0.06, 0.05),
            yaw=0.0, tilt=(0.45, 0.0))


def skull(kit, x, y, z, s=1.0):
    kit.blob("gf_main", (x, y + 0.13 * s, z), 0.16 * s, BONE, scale=(1.0, 0.9, 1.15), subdiv=1, wobble=0.05)
    kit.box("gf_main", (x, y + 0.08 * s, z + 0.12 * s), (0.18 * s, 0.07 * s, 0.05 * s), (0.10, 0.08, 0.07))


def bones(kit, x, z, n=4):
    for k in range(n):
        a = kit.r(0, math.tau)
        cx, cz = x + kit.r(-0.6, 0.6), z + kit.r(-0.6, 0.6)
        dx, dz = math.cos(a) * 0.35, math.sin(a) * 0.35
        kit.tube("gf_main", (cx - dx, 0.04, cz - dz), (cx + dx, 0.06, cz + dz), 0.035, 0.03, 4, BONE)
    skull(kit, x + kit.r(-0.3, 0.3), 0.0, z + kit.r(-0.3, 0.3), kit.r(0.8, 1.1))


def totem(kit, x, z, solid=(0.8, 1.6, 0.8), height=2.7):
    """Stacked carved blocks wrapping the solid box, a painted face, horns and a skull on top."""
    sx, sy, sz = solid
    w = max(sx, sz) * 1.18
    y = 0.0
    k = 0
    while y < height - 0.6:
        hh = kit.r(0.55, 0.7)
        col = TOTEM[k % 2]
        kit.box("gf_main", (x, y + hh / 2, z), (w * kit.r(0.95, 1.05), hh, w * kit.r(0.95, 1.05)), col,
                yaw=kit.r(-0.15, 0.15))
        # painted eyes / mouth on the south face (towards the camera)
        kit.box("gf_main", (x - w * 0.22, y + hh * 0.62, z + w * 0.51), (w * 0.2, hh * 0.18, 0.04), PAINT_RED)
        kit.box("gf_main", (x + w * 0.22, y + hh * 0.62, z + w * 0.51), (w * 0.2, hh * 0.18, 0.04), PAINT_RED)
        kit.box("gf_main", (x, y + hh * 0.25, z + w * 0.51), (w * 0.55, hh * 0.12, 0.04), (0.08, 0.05, 0.04))
        y += hh
        k += 1
    skull(kit, x, y, z, 1.6)
    for side in (-1, 1):
        kit.tube("gf_main", (x + side * w * 0.35, y + 0.1, z), (x + side * w * 0.95, y + 0.75, z - 0.1), 0.09, 0.0, 5,
                 BONE)
    kit.tube("gf_main", (x + w * 0.45, y - 0.3, z + 0.1), (x + w * 0.7, y - 1.2, z + 0.25), 0.06, 0.04, 4, RAG_RED)


def campfire(kit, x, z, s=1.0, light_name="light_fire_0", calm=False):
    for i in range(9):
        a = i / 9 * math.tau
        kit.blob("gf_main", (x + math.cos(a) * 0.7 * s, 0.08, z + math.sin(a) * 0.7 * s), 0.17 * s, (0.28, 0.27, 0.27),
                 scale=(1.2, 0.7, 1.0), subdiv=1, wobble=0.1)
    kit.flat("gf_main", (x, 0, z), 0.62 * s, 9, (0.07, 0.05, 0.04))
    for k in range(4):
        a = k / 4 * math.tau + 0.4
        kit.tube("gf_main", (x + math.cos(a) * 0.55 * s, 0.05, z + math.sin(a) * 0.55 * s), (x, 0.4 * s, z), 0.09 * s,
                 0.07 * s, 5, (0.22, 0.14, 0.09), top_color=(0.08, 0.05, 0.04))
    # the flame: layered, crossed tongues (outer red-orange, inner orange-yellow, a pale core), each a pair of
    # crossed ribbons so it reads as a flame from any yaw; plus floating embers
    k = 0.8 if calm else 1.0
    tongues = [  # (dx, dz, height, width, lean_x, lean_z, layer)
        (0.00, 0.00, 1.15, 0.36, 0.05, -0.04, 0), (0.18, 0.06, 0.80, 0.24, 0.16, 0.02, 0),
        (-0.16, -0.06, 0.85, 0.24, -0.15, -0.05, 0), (0.03, 0.17, 0.70, 0.22, 0.02, 0.15, 0),
        (-0.05, -0.15, 0.72, 0.22, -0.03, -0.14, 0),
        (0.02, 0.01, 0.88, 0.24, 0.03, 0.02, 1), (0.11, -0.06, 0.62, 0.17, 0.10, -0.03, 1),
        (-0.10, 0.07, 0.60, 0.17, -0.09, 0.05, 1),
        (0.0, 0.0, 0.50, 0.12, 0.0, 0.0, 2),
    ]
    for i, (fx, fz, fh, fw, lx, lz, layer) in enumerate(tongues):
        flame_tongue(kit, x + fx * s, z + fz * s, 0.10, fh * s * k, fw * s, lx * s, lz * s, layer, yaw=i * 0.7)
    kit.flat("gf_fire", (x, 0, z), 0.34 * s, 7, (1.0, 0.42, 0.10), y=0.06)
    for i in range(7):
        a = i * 2.4
        rr = kit.r(0.1, 0.45) * s
        kit.blob("gf_fire", (x + math.cos(a) * rr, kit.r(1.0, 1.9) * s * k, z + math.sin(a) * rr), 0.025 * s,
                 (1.0, 0.62, 0.22), subdiv=1, wobble=0.0, jitter=0.0)
    kit.empty(light_name, (x, 1.1 * s, z))


FLAME_LAYERS = [  # (base colour, tip colour) per layer: outer, middle, core
    ((1.0, 0.55, 0.12), (0.85, 0.16, 0.05)),
    ((1.0, 0.82, 0.30), (1.0, 0.46, 0.10)),
    ((1.0, 0.97, 0.78), (1.0, 0.84, 0.42)),
]


def flame_tongue(kit, x, z, y0, h, w, lean_x, lean_z, layer, yaw=0.0, rows=5):
    """One flame tongue: two crossed, double-sided ribbons that swell near the base and taper to a curling tip."""
    b = kit.bm("gf_fire")
    col = b.loops.layers.float_color["Col"]
    base_c, tip_c = FLAME_LAYERS[layer]
    for cross in (0.0, math.pi / 2):
        a = yaw + cross
        ax, az = math.cos(a), math.sin(a)
        left, right, mids = [], [], []
        for r in range(rows + 1):
            t = r / rows
            cx = x + lean_x * t * t
            cz = z + lean_z * t * t
            cy = y0 + h * t
            half = w * (math.sin(math.pi * min(1.0, 0.25 + t * 0.95)) if t < 0.999 else 0.0) * (1.0 - t) ** 0.35
            left.append(b.verts.new(P(cx - ax * half, cy, cz - az * half)))
            right.append(b.verts.new(P(cx + ax * half, cy, cz + az * half)))
            mids.append(t)
        for r in range(rows):
            for quad in ((left[r], right[r], right[r + 1], left[r + 1]),):
                try:
                    f = b.faces.new(quad)
                except ValueError:
                    continue
                for loop in f.loops:
                    t = mids[r] if loop.vert in (left[r], right[r]) else mids[r + 1]
                    loop[col] = paint(mix(base_c, tip_c, t ** 0.8))


def root(kit, pts, r0, r1, thorns=True, col=ROOT_RED, thorn_scale=1.0, thorns_per_segment=2):
    """A thorny red root along a polyline of Godot points; tapers from r0 to r1."""
    n = len(pts) - 1
    for i in range(n):
        a, b = pts[i], pts[i + 1]
        ra = r0 + (r1 - r0) * i / n
        rb = r0 + (r1 - r0) * (i + 1) / n
        kit.tube("gf_main", a, b, ra, rb, 6, col, top_color=mix(col, ROOT_TIP, 0.25 + 0.5 * (i + 1) / n), jitter=0.08)
        if thorns:
            for k in range(thorns_per_segment):
                t = kit.r(0.15, 0.85)
                c = Vector(a).lerp(Vector(b), t)
                ang = kit.r(0, math.tau)
                rr = ra + (rb - ra) * t
                d = Vector((math.cos(ang), kit.r(0.2, 0.9), math.sin(ang))).normalized()
                base = c + d * rr * 0.7
                tip = base + d * (0.22 + rr * 1.4) * thorn_scale
                kit.tube("gf_main", tuple(base), tuple(tip), rr * 0.35, 0.0, 4, ROOT_TIP)


def root_arc(kit, x0, z0, x1, z1, lift, r0, r1, steps=7, wiggle=0.6):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = x0 + (x1 - x0) * t + math.sin(t * math.pi * 2 + x0) * wiggle * (1 - abs(2 * t - 1))
        z = z0 + (z1 - z0) * t + math.cos(t * math.pi * 2 + z0) * wiggle * (1 - abs(2 * t - 1))
        y = -0.1 + math.sin(t * math.pi) * lift
        pts.append((x, y, z))
    root(kit, pts, r0, r1)


def root_stump(kit, x, z, solid):
    """A broken old stump (brown bark, pale cut top with rings and splinters) on flared buttress roots, gripped by
    three thin red thorny roots that spiral round it and dive into the ground. Wraps the solid box."""
    sx, sy, sz = solid
    R = math.hypot(sx, sz) * 0.5 / math.cos(math.pi / 9) + 0.04  # 9-gon that still covers the box corners
    h = sy + 0.06
    bark, bark_top = (0.30, 0.22, 0.15), (0.26, 0.19, 0.13)
    kit.prism("gf_main", (x, -0.05, z), R * 1.32, R * 1.02, 0.42, 9, (0.30, 0.20, 0.13), top_color=bark, cap_top=False)
    kit.prism("gf_main", (x, 0.37, z), R * 1.02, R * 0.94, h - 0.37, 9, bark, top_color=bark_top)
    kit.flat("gf_main", (x, 0, z), R * 0.86, 9, (0.42, 0.33, 0.22), y=h + 0.01)
    kit.flat("gf_main", (x, 0, z), R * 0.55, 9, (0.34, 0.25, 0.16), y=h + 0.02)
    kit.flat("gf_main", (x + 0.05, 0, z - 0.04), R * 0.22, 7, (0.30, 0.20, 0.12), y=h + 0.03)
    for k in range(7):  # splinters round the broken rim
        a = k / 7 * math.tau + kit.r(-0.3, 0.3)
        rr = R * 0.9
        tip = kit.r(0.12, 0.38)
        kit.tube("gf_main", (x + math.cos(a) * rr, h - 0.04, z + math.sin(a) * rr),
                 (x + math.cos(a) * (rr + 0.06), h + tip, z + math.sin(a) * (rr + 0.06)), 0.11, 0.0, 4, bark_top,
                 top_color=(0.52, 0.40, 0.26))
    for k in range(5):  # brown buttress roots
        a = k / 5 * math.tau + 0.5
        kit.tube("gf_main", (x + math.cos(a) * R * 0.8, 0.55, z + math.sin(a) * R * 0.8),
                 (x + math.cos(a) * (R + 0.85), -0.04, z + math.sin(a) * (R + 0.85)), 0.24, 0.07, 6, (0.32, 0.22, 0.14),
                 top_color=(0.25, 0.17, 0.11))
    for k in range(3):  # the red thorny roots gripping it (r3: thinner, fewer thorns - the old ones read as a
        a0 = k / 3 * math.tau + 1.1   # red spiky lump from the camera; now they are veins on a brown stump)
        pts = []
        for i in range(7):
            t = i / 6
            a = a0 + t * 1.7
            rad = R * 1.0 + 0.04 + max(0.0, t - 0.6) * 2.2
            pts.append((x + math.cos(a) * rad, (h - 0.2) * (1.0 - t) - 0.06 * t, z + math.sin(a) * rad))
        root(kit, pts, 0.09, 0.04, thorn_scale=0.55, thorns_per_segment=1)


def glow_mushrooms(kit, x, z, n=4):
    for k in range(n):
        cx, cz = x + kit.r(-0.5, 0.5), z + kit.r(-0.5, 0.5)
        h = kit.r(0.12, 0.3)
        kit.tube("gf_main", (cx, 0.0, cz), (cx, h, cz), 0.03, 0.025, 4, (0.65, 0.62, 0.55))
        kit.prism("gf_glow", (cx, h, cz), kit.r(0.08, 0.14), 0.0, 0.08, 6, GLOW, jitter=0.0)


def mud_puddle(kit, x, z, r, base=DIRT_LIGHT):
    """A flat trodden patch (walkable): breaks up the big open floor without blocking anything.
    (r3: the first two versions were much darker than the floor and read as a hole or a stone lid from the
    camera; the patch is now only a little off the floor tone - texture, not an object. `base` = the floor
    colour it sits on.)"""
    kit.flat("gf_main", (x, 0, z), r, 9, mix(base, (0.10, 0.09, 0.08), 0.22), y=0.03, squash=(1.25, 0.85),
             yaw=kit.r(0, 3))
    kit.flat("gf_main", (x + kit.r(-0.25, 0.25), 0, z + kit.r(-0.25, 0.25)), r * 0.6, 7,
             mix(base, (1.0, 0.95, 0.85), 0.16), y=0.045, squash=(1.2, 0.9), yaw=kit.r(0, 3))


def watchtower(kit, x, z, yaw=0.0, light="light_fire_1"):
    """Goblin lookout: four leaning legs, a lashed platform, a crooked railing and a watch-fire on top.
    A landmark - it always stands OUTSIDE the walkable bounds, so it can never hide a fight."""
    h = 5.2
    legs = []
    for k in range(4):
        a = yaw + k / 4 * math.tau + math.pi / 4
        bx, bz = x + math.cos(a) * 1.55, z + math.sin(a) * 1.55
        tx, tz = x + math.cos(a) * 0.95, z + math.sin(a) * 0.95
        kit.tube("gf_main", (bx, -0.1, bz), (tx, h, tz), 0.18, 0.13, 5, (0.27, 0.19, 0.12))
        legs.append((bx, bz, tx, tz))
    for y in (1.5, 3.3):
        t = y / h
        for k in range(4):
            bx, bz, tx, tz = legs[k]
            nbx, nbz, ntx, ntz = legs[(k + 1) % 4]
            kit.tube("gf_main", (bx + (tx - bx) * t, y, bz + (tz - bz) * t),
                     (nbx + (ntx - nbx) * t, y + kit.r(-0.07, 0.07), nbz + (ntz - nbz) * t), 0.07, 0.07, 4, ROPE)
    kit.prism("gf_main", (x, h, z), 1.4, 1.32, 0.2, 6, WOOD, top_color=WOOD_TIP, cap_bottom=True)
    for k in range(6):  # railing
        a = k / 6 * math.tau + yaw
        px, pz = x + math.cos(a) * 1.2, z + math.sin(a) * 1.2
        kit.tube("gf_main", (px, h + 0.2, pz), (px + math.cos(a) * 0.08, h + 0.95 + kit.r(-0.1, 0.1), pz + math.sin(a) * 0.08),
                 0.07, 0.05, 4, WOOD)
        na = (k + 1) / 6 * math.tau + yaw
        kit.tube("gf_main", (px, h + 0.8, pz), (x + math.cos(na) * 1.2, h + 0.8, z + math.sin(na) * 1.2), 0.05, 0.05, 4,
                 ROPE)
    for i in range(4):  # the watch-fire in a stone ring on the platform
        a = i / 4 * math.tau
        kit.blob("gf_main", (x + math.cos(a) * 0.4, h + 0.26, z + math.sin(a) * 0.4), 0.13, (0.26, 0.25, 0.25),
                 scale=(1.1, 0.7, 1.0), subdiv=1, wobble=0.1)
    for i, (fx, fz, fh, fw, layer) in enumerate([(0.0, 0.0, 0.75, 0.24, 0), (0.1, 0.05, 0.52, 0.16, 1),
                                                 (-0.08, -0.04, 0.5, 0.15, 0), (0.0, 0.0, 0.32, 0.09, 2)]):
        flame_tongue(kit, x + fx, z + fz, h + 0.28, fh, fw, 0.03, -0.02, layer, yaw=i * 0.8)
    kit.box("gf_main", (x, h + 0.55, z + 1.28), (1.1, 0.75, 0.06), RAG_RED, tilt=(0.12, 0.0))  # a banner on the rail
    skull(kit, x + 1.15, h + 0.95, z - 0.2, 1.3)
    kit.empty(light, (x, h + 0.75, z))


def plank_barricade(kit, x, z, solid, yaw=0.0):
    """Goblin patch-work cover: mismatched planks lashed between two posts, a stretched hide, a spear jammed in
    the ground and a skull on a post. Wraps the solid box (sx = its length, sz = its thickness).
    `yaw` is a Blender-space angle (as kit.box uses): the wall runs along godot (cos yaw, -sin yaw)."""
    sx, sy, sz = solid
    dx, dz = math.cos(yaw), -math.sin(yaw)
    nx, nz = -dz, dx
    for side in (-1, 1):
        px, pz = x + dx * sx * 0.52 * side, z + dz * sx * 0.52 * side
        kit.tube("gf_main", (px, -0.1, pz), (px - nx * 0.04, sy + 0.4, pz - nz * 0.04), 0.17, 0.13, 5, (0.26, 0.18, 0.11))
    rows = 4
    for i in range(rows):
        y = (i + 0.5) / rows * (sy + 0.06)
        kit.box("gf_main", (x + nx * kit.r(-0.05, 0.05), y, z + nz * kit.r(-0.05, 0.05)),
                (sx * kit.r(0.93, 1.03), (sy + 0.06) / rows * 0.9, sz * kit.r(0.85, 1.15)),
                mix((0.30, 0.21, 0.13), (0.21, 0.15, 0.10), kit.r(0.0, 1.0)), yaw=yaw, tilt=(0.0, kit.r(-0.05, 0.05)))
    kit.box("gf_main", (x + nx * sz * 0.62, sy * 0.58, z + nz * sz * 0.62), (sx * 0.5, sy * 0.72, 0.07),
            kit.pick(HIDE), yaw=yaw, tilt=(0.1, 0.0))
    skull(kit, x + dx * sx * 0.52, sy + 0.4, z + dz * sx * 0.52, 1.35)
    kit.tube("gf_main", (x - dx * sx * 0.3, 0.0, z - dz * sx * 0.3 + sz * 0.8),
             (x - dx * sx * 0.42, sy + 1.25, z - dz * sx * 0.42 + sz * 0.3), 0.06, 0.04, 4, WOOD, top_color=BONE)


def log_pile(kit, x, z, solid, yaw=0.0):
    """Felled logs stacked 3-2-1 with their cut ends towards the camera, held by two stakes. Wraps the solid.
    `yaw` is a Blender-space angle: the logs run along godot (cos yaw, -sin yaw)."""
    sx, sy, sz = solid
    dx, dz = math.cos(yaw), -math.sin(yaw)
    nx, nz = -dz, dx
    r = sy / 3.75
    for row, count in enumerate((3, 2)):
        y = r * (1.0 + 1.75 * row)
        for i in range(count):
            off = (i - (count - 1) / 2.0) * r * 2.1
            cx, cz = x + nx * off, z + nz * off
            kit.tube("gf_main", (cx - dx * sx * 0.5, y, cz - dz * sx * 0.5), (cx + dx * sx * 0.5, y + kit.r(-0.05, 0.05), cz + dz * sx * 0.5),
                     r, r * 0.95, 7, mix(WOOD, (0.22, 0.15, 0.10), kit.r(0.25, 0.8)),
                     top_color=(0.38, 0.30, 0.20))
    for side in (-1, 1):
        kit.tube("gf_main", (x + dx * sx * 0.52 * side, -0.1, z + dz * sx * 0.52 * side),
                 (x + dx * sx * 0.58 * side, sy + 0.25, z + dz * sx * 0.58 * side), 0.1, 0.07, 4, WOOD, top_color=WOOD_TIP)


# orc-kit pieces wrapping a cover solid (Boss 2026-10-15). Kit sizes at s = 1 (w x h x d, m; build_orc_kit.py):
# totem 2.8 (horns) x 3.0 x 0.94, picket_fence 2.24 x 1.81 x 1.40, bone_fence 2.00 x 1.31 x 1.56.
ORC_FOOT = {"totem": (1.0, 0.94), "picket_fence": (2.24, 1.40), "bone_fence": (2.0, 1.56)}
ORC_HEIGHT = {"picket_fence": 1.81, "bone_fence": 1.31}


def orc_totem(kit, x, z, solid, height=1.95):
    """The horned skull totem standing on a stacked-stone cairn that wraps the solid box (the totem's pole alone is
    too thin to hide the box, which the stage draws in the ink ground material)."""
    sx, sy, sz = solid
    cairn(kit, x, z, solid)
    kit.orc("totem", x, z, s=height / 3.0, y=sy + 0.02)


def cairn(kit, x, z, solid):
    """Three stacked, turned courses of dark mossy stone round a solid box (a plinth for a kit piece)."""
    sx, sy, sz = solid
    R = math.hypot(sx, sz) * 0.5 / math.cos(math.pi / 8) + 0.05
    h = (sy + 0.04) / 3.0
    for i in range(3):
        kit.prism("gf_main", (x, i * h - (0.06 if i == 0 else 0.0), z), R * (1.06 - 0.03 * i), R * (1.0 - 0.03 * i),
                  h + (0.06 if i == 0 else 0.02), 8, mix((0.27, 0.25, 0.22), STONE_MOSS, 0.15 + 0.12 * i),
                  rot=Matrix.Rotation(i * 0.37, 3, 'Z'), jitter=0.09, top_color=(0.30, 0.28, 0.24))


def plank_core(kit, x, z, solid):
    """Lashed dark planks filling a wall-shaped solid box (axis-aligned like the solid), so a see-through kit fence
    in front of it reads as a filled barricade and the box never shows."""
    sx, sy, sz = solid
    rows = 4
    for i in range(rows):
        y0 = i / rows * (sy + 0.04)
        hh = (sy + 0.04) / rows
        size = (sx + 0.06, hh * 0.98, sz + 0.06)
        top = i == rows - 1
        kit.box("gf_main", (x, y0 + hh / 2, z), size,
                mix(mix(WOOD, (0.25, 0.17, 0.11), kit.r(0.0, 0.7)), WOOD_TIP, 0.45 if top else 0.0), jitter=0.05)


def orc_wall(kit, name, o):
    """A fence piece along a wall-shaped solid round a plank core. Solids are axis-aligned boxes, so the fence
    runs along the box's long axis (the obstacle's yaw only picks which way it faces)."""
    sx, sy, sz = o["size"]
    fw, fd = ORC_FOOT[name]
    plank_core(kit, o["x"], o["z"], o["size"])
    L, T = (sx, sz) if sx >= sz else (sz, sx)
    yaw = (0.0 if sx >= sz else 90.0) + (180.0 if math.cos(o.get("yaw", 0.0)) < 0 else 0.0)
    for back in (False, True):   # a fence on each face of the core: stakes screen it from every side
        if name == "bone_fence":
            # a thin row of stakes (its core is 1.5 m wide, 0.5 m deep): one on each face, just outside the core
            off = T / 2 + 0.12
            nx, nz = (0.0, 1.0) if sx >= sz else (1.0, 0.0)
            sgn = -1.0 if back else 1.0
            if math.cos(o.get("yaw", 0.0)) < 0:
                sgn = -sgn
            kit.orc(name + ("_lo" if back else ""), o["x"] + nx * off * sgn, o["z"] + nz * off * sgn,
                    yaw=yaw + (180.0 if back else 0.0),
                    scale=(L * 1.04 / 1.5, max(1.0, sy * 1.25 / ORC_HEIGHT[name]), 1.0))
            continue
        kit.orc(name + ("_lo" if back else ""), o["x"], o["z"], yaw=yaw + (180.0 if back else 0.0),
                scale=(L * 1.06 / fw, max(1.0, sy * 1.25 / ORC_HEIGHT[name]), max(0.75, T * 1.4 / fd)))


def root_well(kit, x, z, solid):
    """Thornroot Hollow's landmark cover: an old stone well the roots have broken into - a mossy stacked-stone
    kerb, three red thorn roots bursting out of its mouth and arching down to the ground, a skull and a broken
    bucket on the rim, and a dim cold glow deep inside. Wraps the solid box.
    (r3 round 2: the first version was a cage of roots round a bright disc and read as a pale slab with spider
    legs from the camera; a round kerb with roots bursting out of it reads as one object.)"""
    sx, sy, sz = solid
    # (2026-10-15: the kerb must cover the box's corners, and its top the box's top: the stage draws the solid)
    R = math.hypot(sx, sz) * 0.5 / math.cos(math.pi / 11) + 0.06
    sy = sy + 0.06

    def kerb_shade(co, f):
        return mix(STONE, STONE_MOSS, clamp((f.normal.z - 0.1) * 1.4))  # (unused: the courses are flat-coloured)
    for i in range(3):   # three stacked courses of flat stones, each turned a little
        y = i * (sy / 3.0)
        kit.prism("gf_main", (x, y, z), R * (1.0 - 0.03 * i), R * (0.97 - 0.03 * i), sy / 3.0 + 0.02, 11,
                  mix((0.30, 0.27, 0.23), STONE_MOSS, 0.18 + 0.1 * i), rot=Matrix.Rotation(i * 0.19, 3, 'Z'), jitter=0.09,
                  cap_top=False)
    kit.prism("gf_main", (x, sy - 0.1, z), R * 0.96, R * 0.92, 0.12, 11, (0.36, 0.32, 0.26), jitter=0.07,
              cap_top=False)
    kit.flat("gf_main", (x, 0, z), R * 0.95, 11, (0.05, 0.04, 0.04), y=sy - 0.03)   # the dark mouth
    kit.flat("gf_glow", (x, 0, z), R * 0.42, 9, (0.16, 0.40, 0.38), y=sy - 0.02)    # a dim glow far down
    for k in range(3):   # the roots bursting out and diving back into the ground
        a0 = k / 3 * math.tau + 0.7
        pts = []
        for i in range(6):
            t = i / 5
            a = a0 + t * 0.5
            rad = R * (0.3 + t * t * 1.35)
            pts.append((x + math.cos(a) * rad, sy + 0.45 * math.sin(min(1.0, t * 1.35) * math.pi) - 0.1 * t * t * 3.0,
                        z + math.sin(a) * rad))
        root(kit, pts, 0.15, 0.05, thorn_scale=0.8, thorns_per_segment=1)
    for i in range(3):
        a = i * 2.1
        kit.blob("gf_glow", (x + math.cos(a) * R * 0.3, sy + kit.r(0.2, 0.8), z + math.sin(a) * R * 0.3), 0.045,
                 (0.55, 0.95, 0.9), subdiv=1, wobble=0.0)
    skull(kit, x + R * 0.78, sy - 0.02, z + R * 0.5, 1.3)
    kit.prism("gf_main", (x - R * 0.8, sy - 0.02, z + R * 0.55), 0.2, 0.17, 0.3, 7, (0.30, 0.21, 0.13),
              top_color=(0.22, 0.15, 0.10), cap_top=False)   # the broken bucket
    kit.empty("light_glow_0", (x, sy + 0.3, z))


def hide_rack(kit, x, z, yaw=0.0):
    """A drying rack: two forked poles, a crossbar and two stretched hides (goblin camp dressing, no collision)."""
    dx, dz = math.cos(yaw), -math.sin(yaw)
    for side in (-1, 1):
        kit.tube("gf_main", (x + dx * 1.3 * side, -0.05, z + dz * 1.3 * side), (x + dx * 1.2 * side, 1.9, z + dz * 1.2 * side),
                 0.09, 0.07, 5, WOOD)
    kit.tube("gf_main", (x - dx * 1.35, 1.85, z - dz * 1.35), (x + dx * 1.35, 1.9, z + dz * 1.35), 0.06, 0.06, 4, WOOD)
    for t in (-0.55, 0.3):
        kit.box("gf_main", (x + dx * 1.35 * t, 1.25, z + dz * 1.35 * t), (0.95, 1.2, 0.05), kit.pick(HIDE), yaw=yaw,
                tilt=(0.0, kit.r(-0.06, 0.06)))


def stone_block(kit, x, z, solid, yaw=0.0):
    """A cut quarry block: an almost-square stone with chisel steps, a mossy top and chips at its foot."""
    sx, sy, sz = solid

    def shade(co, f):
        return mix(QUARRY_STONE, QUARRY_LIGHT, clamp(0.3 + f.normal.z * 0.45))
    # (the body stays axis-aligned like its solid, which the stage draws: only the chisel step on top turns)
    kit.box("gf_main", (x, sy * 0.5, z), (sx * 1.06, sy + 0.04, sz * 1.06), QUARRY_STONE, shade=shade, jitter=0.05)
    kit.box("gf_main", (x + kit.r(-0.1, 0.1), sy + 0.02, z + kit.r(-0.1, 0.1)), (sx * 0.78, 0.08, sz * 0.78),
            mix(QUARRY_LIGHT, GRAVEL_LIGHT, 0.5), yaw=yaw + kit.r(-0.2, 0.2), jitter=0.08)
    for k in range(3):
        a = kit.r(0, math.tau)
        kit.blob("gf_main", (x + math.cos(a) * sx * 0.75, 0.1, z + math.sin(a) * sz * 0.75), kit.r(0.16, 0.3),
                 QUARRY_LIGHT, scale=(1.2, 0.6, 1.0), subdiv=1, wobble=0.2, rot_z=a)


def spoil_heap(kit, x, z, solid):
    """A cone of quarry spoil (rubble) with a shovel stuck in it. Wraps the solid box."""
    sx, sy, sz = solid
    R = max(sx, sz) * 0.5 * 1.35
    # (2026-10-15: a steep mound whose shoulder still covers the solid box's top corners, then a low cone)
    rc = math.hypot(sx, sz) * 0.5 / math.cos(math.pi / 9) + 0.06
    kit.prism("gf_main", (x, -0.05, z), max(R * 1.25, rc * 1.35), rc, sy + 0.12, 9, QUARRY_STONE,
              top_color=mix(GRAVEL, QUARRY_STONE, 0.4), jitter=0.12, twist=0.3)
    kit.prism("gf_main", (x, sy + 0.06, z), rc, rc * 0.3, 0.25, 9, mix(GRAVEL, QUARRY_STONE, 0.4), jitter=0.12)
    for k in range(9):   # boulders on the shoulder break the cone's outline
        a = k / 9 * math.tau + kit.r(-0.2, 0.2)
        rr = rc * kit.r(0.75, 1.05)
        kit.blob("gf_main", (x + math.cos(a) * rr, sy * kit.r(0.55, 1.0), z + math.sin(a) * rr), kit.r(0.25, 0.4),
                 mix(QUARRY_DARK, QUARRY_STONE, kit.r(0.3, 1.0)), scale=(1.2, 0.8, 1.0), subdiv=1, wobble=0.2, rot_z=a)
    for k in range(10):
        a = kit.r(0, math.tau)
        rr = kit.r(0.3, 1.1) * R
        kit.blob("gf_main", (x + math.cos(a) * rr, kit.r(0.05, 0.5), z + math.sin(a) * rr), kit.r(0.14, 0.3),
                 mix(QUARRY_STONE, QUARRY_LIGHT, kit.r(0.0, 1.0)), scale=(1.2, 0.7, 1.0), subdiv=1, wobble=0.25,
                 rot_z=a)
    kit.tube("gf_main", (x + R * 0.2, sy * 0.3, z + R * 0.5), (x + R * 0.45, sy + 1.1, z + R * 0.75), 0.05, 0.04, 4, WOOD)
    kit.box("gf_main", (x + R * 0.47, sy + 1.05, z + R * 0.78), (0.3, 0.34, 0.05), IRON, tilt=(0.3, 0.0))


def rail_track(kit, x0, z0, x1, z1):
    """Two rusty rails on sleepers, flat on the ground (walkable): it tells the eye which way the quarry works."""
    L = math.hypot(x1 - x0, z1 - z0)
    dx, dz = (x1 - x0) / L, (z1 - z0) / L
    nx, nz = -dz, dx
    yaw = math.atan2(-dz, dx)  # Blender-space yaw of the godot direction (dx, dz)
    n = max(2, int(L / 1.1))
    for i in range(n + 1):
        t = i / n
        cx, cz = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
        kit.box("gf_main", (cx, 0.04, cz), (0.2, 0.08, 0.95), mix(WOOD, (0.18, 0.13, 0.09), 0.65), yaw=yaw)
    for side in (-1, 1):
        kit.tube("gf_main", (x0 + nx * 0.36 * side, 0.1, z0 + nz * 0.36 * side), (x1 + nx * 0.36 * side, 0.1, z1 + nz * 0.36 * side),
                 0.042, 0.042, 4, RUST, jitter=0.1)


def ore_cart(kit, x, z, solid, yaw=0.0, tipped=True):
    """A goblin ore cart: an iron-banded tub on four small wheels, spilling broken stone. Wraps the solid box.
    `yaw` is a Blender-space angle (as kit.box uses): the cart's length runs along godot (cos yaw, -sin yaw)."""
    sx, sy, sz = solid
    dx, dz = math.cos(yaw), -math.sin(yaw)
    nx, nz = -dz, dx
    tilt = (0.0, 0.26) if tipped else (0.0, 0.0)
    kit.box("gf_main", (x, sy * 0.52, z), (sx * 1.05, sy * 1.06, sz * 1.05), mix(WOOD, (0.25, 0.17, 0.11), 0.3),
            yaw=yaw, tilt=tilt)
    for t in (-0.3, 0.3):
        kit.box("gf_main", (x + dx * sx * t, sy * 0.56, z + dz * sx * t), (0.12, sy * 1.0, sz * 1.08), IRON,
                yaw=yaw, tilt=tilt)
    for side in (-1, 1):
        for t in (-0.3, 0.3):
            wx = x + dx * sx * t + nx * sz * 0.55 * side
            wz = z + dz * sx * t + nz * sz * 0.55 * side
            kit.prism("gf_main", (wx, 0.1, wz), 0.26, 0.26, 0.1, 8, IRON,
                      rot=Matrix.Rotation(yaw, 3, 'Z') @ Matrix.Rotation(math.pi / 2, 3, 'X'), jitter=0.05)
    for k in range(7):  # the spilled ore
        a = kit.r(0, math.tau)
        rr = kit.r(0.2, 1.0)
        kit.blob("gf_main", (x + nx * sz * 0.9 + math.cos(a) * rr, kit.r(0.08, 0.45),
                             z + nz * sz * 0.9 + math.sin(a) * rr), kit.r(0.13, 0.24),
                 mix(QUARRY_STONE, OCHRE, kit.r(0.0, 0.6)), scale=(1.1, 0.8, 1.0), subdiv=1, wobble=0.22, rot_z=a)


def winch_frame(kit, x, z, light="light_fire_1"):
    """The quarry's landmark: a huge timber A-frame with a drum, a rope and a cracked boulder hanging in a rope
    net, goblin rags and skulls lashed to it. Stands outside the bounds on the quarry face."""
    h = 6.4
    for side in (-1, 1):
        kit.tube("gf_main", (x + side * 2.6, -0.1, z + 1.0), (x + side * 0.42, h, z), 0.26, 0.17, 6, (0.27, 0.19, 0.12))
        kit.tube("gf_main", (x + side * 2.2, -0.1, z - 1.6), (x + side * 0.42, h, z), 0.2, 0.15, 5, (0.25, 0.17, 0.11))
        kit.tube("gf_main", (x + side * 1.9, 2.6, z + 0.55), (x + side * 1.6, 2.6, z - 1.15), 0.08, 0.08, 4, ROPE)
    kit.tube("gf_main", (x - 0.5, h, z), (x + 0.5, h, z), 0.19, 0.19, 6, WOOD, top_color=WOOD_TIP)
    kit.prism("gf_main", (x - 0.75, h - 0.45, z - 0.1), 0.3, 0.3, 1.5, 8, (0.3, 0.21, 0.13),
              rot=Matrix.Rotation(math.pi / 2, 3, 'Y'), jitter=0.05)       # the drum
    kit.tube("gf_main", (x + 0.9, h - 0.45, z - 0.1), (x + 1.7, h - 0.2, z - 0.1), 0.06, 0.05, 4, WOOD)  # the handle
    kit.tube("gf_main", (x, h - 0.08, z), (x, 3.3, z + 0.1), 0.05, 0.05, 4, ROPE)                        # the rope
    kit.blob("gf_main", (x, 2.5, z + 0.12), 0.95, QUARRY_STONE, scale=(1.0, 0.85, 1.0), subdiv=2, wobble=0.14,
             shade=lambda co, f: mix(QUARRY_DARK, QUARRY_LIGHT, clamp(0.3 + f.normal.z * 0.9)))
    for k in range(4):  # the rope net round the boulder
        a = k / 4 * math.pi
        kit.tube("gf_main", (x + math.cos(a) * 0.95, 2.55, z + math.sin(a) * 0.95 + 0.12),
                 (x - math.cos(a) * 0.95, 2.55, z - math.sin(a) * 0.95 + 0.12), 0.035, 0.035, 3, ROPE, jitter=0.1)
    kit.box("gf_main", (x + 1.35, h - 1.15, z - 0.05), (0.8, 1.3, 0.05), RAG_RED, tilt=(0.0, 0.1))
    skull(kit, x - 1.5, h - 0.15, z, 1.5)
    skull(kit, x + 2.0, 2.4, z - 1.3, 1.1)
    for i, (fx, fz, fh, fw, layer) in enumerate([(0.0, 0.0, 0.8, 0.26, 0), (0.1, 0.06, 0.55, 0.17, 1),
                                                 (0.0, 0.0, 0.34, 0.1, 2)]):
        flame_tongue(kit, x + 2.8 + fx, z - 2.4 + fz, 0.95, fh, fw, 0.04, -0.03, layer, yaw=i * 0.9)
    kit.prism("gf_main", (x + 2.8, 0.0, z - 2.4), 0.42, 0.34, 0.95, 7, IRON, top_color=(0.3, 0.3, 0.32))  # brazier
    kit.empty(light, (x + 2.8, 1.3, z - 2.4))


def crate(kit, x, y, z, s, yaw=0.0):
    kit.box("gf_main", (x, y + s / 2, z), (s, s, s), CRATE, yaw=yaw)
    for dy in (0.15, 0.85):
        kit.box("gf_main", (x, y + s * dy, z), (s * 1.03, s * 0.1, s * 1.03), (0.30, 0.21, 0.12), yaw=yaw)


def barrel(kit, x, z, s=1.0):
    kit.prism("gf_main", (x, 0.0, z), 0.38 * s, 0.42 * s, 0.9 * s, 8, (0.36, 0.25, 0.15), top_color=(0.30, 0.21, 0.13))
    for y in (0.15, 0.7):
        kit.prism("gf_main", (x, y * s, z), 0.43 * s, 0.43 * s, 0.07, 8, (0.20, 0.19, 0.18), cap_top=False)


def flagstone_path(kit, x0, z0, x1, z1, col=(0.30, 0.29, 0.27)):
    """Stepping stones from the clearing to an exit portal spot, ending in a stone pad: 'the way out'."""
    L = math.hypot(x1 - x0, z1 - z0)
    n = max(2, int(L / 0.9))
    for i in range(n):
        t = (i + 0.5) / n
        kit.flat("gf_main", (x0 + (x1 - x0) * t + kit.r(-0.15, 0.15), 0, z0 + (z1 - z0) * t), kit.r(0.22, 0.3), 6, col,
                 squash=(1.2, 0.8), yaw=kit.r(0, 3))
    for i in range(10):
        a = i / 10 * math.tau
        kit.flat("gf_main", (x1 + math.cos(a) * 1.15, 0, z1 + math.sin(a) * 1.15), 0.24, 5, col, yaw=a)
    kit.flat("gf_main", (x1, 0, z1), 0.95, 12, mix(col, (0.12, 0.12, 0.13), 0.4), y=0.03)


def lantern_post(kit, x, z, light="light_lantern_0"):
    kit.tube("gf_main", (x, 0.0, z), (x, 2.0, z), 0.06, 0.05, 5, WOOD)
    kit.tube("gf_main", (x, 1.95, z), (x + 0.45, 2.05, z), 0.04, 0.04, 4, WOOD)
    kit.box("gf_main", (x + 0.45, 1.80, z), (0.24, 0.05, 0.24), (0.15, 0.12, 0.10))
    kit.prism("gf_fire", (x + 0.45, 1.52, z), 0.10, 0.10, 0.26, 6, (1.0, 0.75, 0.35), jitter=0.0)
    kit.box("gf_main", (x + 0.45, 1.48, z), (0.24, 0.05, 0.24), (0.15, 0.12, 0.10))
    kit.empty(light, (x + 0.45, 1.6, z))


def log_seat(kit, x, z, yaw, L=1.5):
    dx, dz = math.cos(yaw) * L / 2, math.sin(yaw) * L / 2
    kit.tube("gf_main", (x - dx, 0.22, z - dz), (x + dx, 0.24, z + dz), 0.22, 0.2, 7, (0.38, 0.26, 0.16),
             top_color=(0.42, 0.30, 0.18))


def low_plant(kit, x, z, s, palette=None, bush_share=0.6):
    if kit.rng.random() < bush_share:
        bush(kit, x, z, s, palette or BROAD)
    else:
        fern(kit, x, z, s)


def forest_border(kit, hw, hd, keep_out=(), density=1.0, broad_share=0.3, dead_share=0.06, palette=None,
                  north_to=-24.0, side_to=25.0, south_low_to=13.0):
    """Dense forest around the walkable box: tall trees north and on the sides (never south of z = hd - 2, so
    nothing tall stands between the camera and a fight), low bushes, ferns and rocks on the south band."""
    rng = kit.rng
    sp = 2.6 / math.sqrt(density)
    z = north_to
    while z < south_low_to:
        x = -side_to
        while x < side_to:
            px, pz = x + rng.uniform(-0.9, 0.9) * sp * 0.45, z + rng.uniform(-0.9, 0.9) * sp * 0.45
            x += sp
            outside_x = abs(px) - hw
            outside_z = -hd - pz  # > 0 north of the bounds
            south = pz - hd
            if any(math.hypot(px - kx, pz - kz) < kr for kx, kz, kr in keep_out):
                continue
            if south > -0.3 and abs(px) < hw + 3.0:
                # camera side: only low things
                if rng.random() < 0.55:
                    low_plant(kit, px, pz, rng.uniform(0.8, 1.3), palette)
                elif rng.random() < 0.3:
                    rock(kit, px, pz, rng.uniform(0.4, 0.8))
                continue
            if outside_x < 1.4 and outside_z < 1.4:
                continue  # inside or hugging the bounds: keep the arena open
            if pz > hd - 2.0 and abs(px) < hw + 6.0:
                if rng.random() < 0.6:
                    bush(kit, px, pz, rng.uniform(0.9, 1.4), *([palette] if palette else []))
                continue
            near = min(max(outside_x, outside_z), 12.0)
            if near > 5.0 and rng.random() < 0.4:
                continue  # deep forest: thinner (the crowns of the front rows hide it)
            h = rng.uniform(6.5, 10.5) + near * 0.15
            roll = rng.random()
            if roll < dead_share:
                dead_tree(kit, px, pz, h * 0.8)
            elif roll < dead_share + broad_share:
                broadleaf(kit, px, pz, h * 0.85, palette or BROAD)
            else:
                conifer(kit, px, pz, h)
            if near < 4.0 and rng.random() < 0.5:
                bush(kit, px + rng.uniform(-1, 1), pz + rng.uniform(0.5, 1.5), rng.uniform(0.9, 1.3), *([palette] if palette else []))
        z += sp


def border_undergrowth(kit, hw, hd, n=26, palette=None):
    """Bushes and ferns right on the edge of the bounds so the clearing has a soft, dense rim."""
    for i in range(n):
        t = i / n
        if t < 0.5:  # north edge, west->east
            x, z = -hw - 1 + (2 * hw + 2) * (t / 0.5), -hd - kit.r(0.6, 1.6)
        elif t < 0.75:
            x, z = -hw - kit.r(0.6, 1.6), -hd + (2 * hd) * ((t - 0.5) / 0.25)
        else:
            x, z = hw + kit.r(0.6, 1.6), -hd + (2 * hd) * ((t - 0.75) / 0.25)
        low_plant(kit, x, z, kit.r(0.9, 1.4), palette, bush_share=0.65)


# ---------------------------------------------------------------- the stages

def quarry_border(kit, hw, hd, ramps=(), keep_out=()):
    """The quarry walls: a low bench hugging the walkable box with a high cut face behind it (two ramps hacked
    through the north face, where the exit portals stand), loose talus at their feet and only rubble on the
    south (camera) side. Goblin patch-work on the rim: stakes, skulls, thorn roots, a few dead trees.
    (r3 round 2: the first version was a field of separate pale hexagons; the rows now overlap into one wall
    and every stone is darker at the top, so the moon cannot wash it to white.)"""
    rng = kit.rng

    def face(x, z, w, depth, h, dark=0.0):
        base = mix(QUARRY_STONE, QUARRY_DARK, dark)
        kit.prism("gf_main", (x, -0.25, z), w * 0.5, w * 0.5 * rng.uniform(0.82, 0.96), h + 0.25, 6, base,
                  squash=(1.0, depth / max(w, 0.01)), jitter=0.07, twist=rng.uniform(-0.25, 0.25),
                  top_color=mix(base, QUARRY_DARK, 0.55))
        if rng.random() < 0.5:  # a chisel step / strata ledge on the face
            kit.box("gf_main", (x, h * rng.uniform(0.35, 0.7), z + depth * 0.45), (w * 0.8, 0.22, 0.4),
                    mix(QUARRY_LIGHT, QUARRY_STONE, 0.5), yaw=rng.uniform(-0.2, 0.2), jitter=0.08)
    # north: a bench, then the high wall, with gaps at the ramps
    x = -hw - 7.0
    while x < hw + 7.0:
        w = rng.uniform(3.4, 5.0)
        if all(abs(x - rx) > rw + w * 0.45 for rx, rw in ramps):
            face(x, -hd - 1.9, w, rng.uniform(2.6, 3.6), rng.uniform(1.3, 2.1))
            face(x + rng.uniform(-0.8, 0.8), -hd - 4.4, w * 1.2, rng.uniform(3.4, 4.8), rng.uniform(5.0, 7.5), dark=0.25)
            face(x + rng.uniform(-1.2, 1.2), -hd - 7.6, w * 1.3, rng.uniform(4.0, 5.2), rng.uniform(7.0, 9.0), dark=0.5)
            if rng.random() < 0.45:
                kit.tube("gf_main", (x, 1.5, -hd - 2.2), (x + rng.uniform(-0.3, 0.3), 2.9, -hd - 2.4), 0.15, 0.1, 5,
                         (0.24, 0.17, 0.11), top_color=WOOD_TIP)
        x += w * 0.72
    for rx, rw in ramps:  # a cut ramp: steps climbing into the gap, lighter than the wall so the way out reads
        for i in range(4):
            kit.box("gf_main", (rx, 0.1 + i * 0.3, -hd - 1.1 - i * 1.05), (rw * 2.1, 0.26 + i * 0.6, 1.25),
                    mix(QUARRY_LIGHT, GRAVEL_LIGHT, 0.2 + 0.15 * i), jitter=0.06)
        # the horned orc gate at the top of the ramp marks the way out (orc kit, Boss 2026-10-15)
        kit.orc("gate_lo", rx, -hd - 4.5, y=1.95, s=0.8, lights=[0 if rx > 0 else 1])
    # side benches: low next to the bound, high behind
    for sx in (-1, 1):
        z = -hd - 4.0
        while z < hd + 1.5:
            if any(math.hypot(sx * (hw + 2.2) - kx, z - kz) < kr for kx, kz, kr in keep_out):
                z += 3.0
                continue
            w = rng.uniform(3.0, 4.4)
            high = z < hd - 3.0
            face(sx * (hw + 2.0), z, rng.uniform(2.6, 3.4), w, rng.uniform(1.2, 1.9))
            if high:
                face(sx * (hw + 5.0), z + rng.uniform(-0.6, 0.6), rng.uniform(4.0, 5.2), w * 1.15,
                     rng.uniform(4.5, 7.0), dark=0.3)
                face(sx * (hw + 8.4), z + rng.uniform(-1.0, 1.0), rng.uniform(4.4, 5.6), w * 1.2,
                     rng.uniform(6.5, 8.5), dark=0.5)
            z += w * 0.72
    # talus and rubble all round (low on the south: the camera looks over it)
    for i in range(70):
        a = rng.uniform(0, math.tau)
        px = math.cos(a) * rng.uniform(hw + 0.6, hw + 7.0)
        pz = math.sin(a) * rng.uniform(hd + 0.5, hd + 6.0)
        if abs(px) < hw + 0.4 and abs(pz) < hd + 0.4:
            continue
        s = rng.uniform(0.3, 0.75) * (0.7 if pz > hd else 1.0)
        rock(kit, px, pz, s, mossy=rng.random() < 0.35)
    for i in range(5):  # a few dead trees clinging to the rim (north and sides only)
        a = rng.uniform(0.15, 0.85) * math.pi
        dead_tree(kit, math.cos(a) * (hw + rng.uniform(3.0, 6.0)), -math.sin(a) * (hd + rng.uniform(2.5, 6.0)) + 1.0,
                  rng.uniform(4.0, 6.0))
    root_arc(kit, -hw - 5.0, -hd - 3.0, -hw + 1.4, -hd + 2.0, 1.1, 0.34, 0.06)
    root_arc(kit, hw + 4.5, -hd - 2.0, hw - 1.0, -hd + 3.0, 1.0, 0.32, 0.06)
    root_arc(kit, hw + 4.0, 3.0, hw - 0.8, 6.0, 0.4, 0.26, 0.05)
    root_arc(kit, -hw - 4.0, 4.0, -hw + 0.6, 7.0, 0.4, 0.26, 0.05)


def night_ground(hw, hd, seed):
    def colour_at(x, z):
        e = (x / (hw + 0.5)) ** 2 + (z / (hd + 0.5)) ** 2
        n = hash_noise(x, z, seed)
        if e < 1.0:
            c = mix(DIRT, DIRT_LIGHT, 0.55 + 0.35 * n - 0.25 * e)
            c = mix(c, MOSS, clamp((e - 0.62) * 1.8 + 0.25 * n))
        else:
            # the camera looks over the south rim: fade out slower there so it never drops to black
            fade = 1.0 - 0.45 * clamp((z - hd + 1.5) / 3.0)
            c = mix(MOSS, FOREST_FLOOR, clamp(((math.sqrt(e) - 1.0) * 1.4 + 0.2 * n) * fade))
        return c

    def height_at(x, z):
        e = max(abs(x) - hw, -z - hd, z - hd, 0.0)
        return FLOOR_Y + (0.0 if e <= 0.3 else min(e * 0.12, 0.6) * (0.6 + 0.4 * hash_noise(x * 1.7, z * 1.7, seed)))
    return colour_at, height_at


def build_arena_a(kit, L):
    """Goblin Camp Gate (night): the goblins' palisade closes the north side, its two gates are the exits."""
    hw, hd = L["hw"], L["hd"]
    col, hgt = night_ground(hw, hd, 1.3)
    ground(kit, 34.0, -30.0, 18.0, 1.6, col, hgt)
    gates = [(p[0], -12.0, 2.9) for p in L["exit_portals"]]
    # the war camp's north wall (orc kit, Boss 2026-10-15): two horned gates behind the exit portals, palisade
    # sections between and beyond them, a short return down each side, the watchtower on the north-east corner
    for gx, gz, _ in gates:
        kit.orc("gate_lo", gx, gz, lights=[0 if gx > 0 else 1])   # (one lantern light each, on the inner side)
    kit.orc("palisade_lo", 0.0, -12.25)
    for side in (-1, 1):
        kit.orc("palisade_lo", side * 9.6, -12.3, yaw=side * 2.0)
        kit.orc("palisade_lo", side * 13.7, -12.0, yaw=side * 5.0)
        kit.orc("palisade_lo", side * 16.1, -8.3, yaw=-side * 90.0)   # the side returns face the arena
    kit.orc("palisade_lo", -17.7, -11.6, yaw=-8.0)
    for p in L["exit_portals"]:
        flagstone_path(kit, p[0] * 0.45, -2.0, p[0], p[2])
    # the landmarks: the watchtower over the north-east corner, the hanging cage by the west huts (both outside
    # the bounds, so the fight is never hidden)
    kit.orc("watchtower", 17.9, -12.4, yaw=-25.0, lights=[0])
    kit.orc("cage_lo", -17.0, 0.6, yaw=90.0)
    # the camp outside the bounds: hide huts facing in, a war banner, low bone fences, junk
    kit.orc("hut_lo", -17.9, -3.6, yaw=90.0)
    kit.orc("hut_lo", 18.0, -4.6, yaw=-90.0)
    kit.orc("hut_lo", -17.6, 5.0, yaw=75.0, s=0.9)
    kit.orc("war_banner_lo", 15.6, 0.0, yaw=-90.0)
    barrel(kit, hw + 1.6, 2.4)
    barrel(kit, hw + 2.2, 3.1, 0.9)
    crate(kit, hw + 1.7, 0.0, 4.6, 0.8, 0.3)
    kit.orc("bone_fence_lo", hw + 2.1, 6.8, yaw=-80.0)
    kit.orc("bone_fence_lo", -hw - 1.6, -6.4, yaw=95.0, s=0.9)
    bones(kit, -9.4, 1.4)
    bones(kit, 8.4, 6.6, 3)
    bones(kit, -3.0, -8.2, 3)
    bones(kit, 12.0, -3.0, 2)
    # the floor: trodden mud patches so the bigger open middle is not an empty brown sheet
    mud_puddle(kit, -2.6, 5.6, 1.5)
    mud_puddle(kit, 5.6, -1.0, 1.2)
    mud_puddle(kit, -7.0, -6.6, 1.3)
    mud_puddle(kit, 11.0, 1.4, 1.1)
    # thorny red roots creeping in from the forest (low: walkable, never over the arena)
    root_arc(kit, -hw - 4.5, -8.0, -hw + 1.4, -5.0, 0.5, 0.32, 0.06)
    root_arc(kit, hw + 3.8, 1.0, hw - 1.0, 4.6, 0.45, 0.30, 0.05)
    root_arc(kit, -hw - 3.2, 6.8, -hw + 0.8, 8.6, 0.35, 0.26, 0.05)
    root_arc(kit, hw + 4.4, -10.5, hw + 0.9, -12.5, 1.4, 0.38, 0.08)
    glow_mushrooms(kit, -hw - 0.8, 2.4)
    glow_mushrooms(kit, hw + 0.7, -3.0, 3)
    glow_mushrooms(kit, 6.6, -hd - 0.8, 3)
    glow_mushrooms(kit, -11.8, -1.2, 3)
    # campfire on the south-west (flat: walkable)
    campfire(kit, *L["fire"], light_name="light_fire_0")
    log_seat(kit, L["fire"][0] + 1.5, L["fire"][1] + 0.3, 1.2)
    log_seat(kit, L["fire"][0] + 0.2, L["fire"][1] - 1.7, 0.1)
    # obstacles (each = art + solid)
    for o in L["obstacles"]:
        if o["kind"] == "totem":
            orc_totem(kit, o["x"], o["z"], o["size"])
            bones(kit, o["x"] + 0.9, o["z"] + 0.7, 2)
        elif o["kind"] == "rock":
            big_rock(kit, o["x"], o["z"], o["size"])
        elif o["kind"] == "crates":
            sx, sy, sz = o["size"]
            crate(kit, o["x"], 0.0, o["z"], max(sx, sz) * 1.12, 0.0)
            crate(kit, o["x"], max(sx, sz) * 1.12, o["z"], max(sx, sz) * 1.12, 0.0)
            barrel(kit, o["x"] + sx * 0.9, o["z"] + 0.4, 0.8)
        elif o["kind"] == "barricade":
            orc_wall(kit, "picket_fence", o)
        elif o["kind"] == "logs":
            orc_wall(kit, "bone_fence", o)
    forest_border(kit, hw, hd, density=0.85, keep_out=[(g[0], g[1], 3.4) for g in gates]
                  + [(-17.9, -3.6, 3.0), (18.0, -4.6, 3.0), (-17.6, 5.0, 2.8), (17.9, -12.4, 3.4),
                     (-17.0, 0.6, 2.2), (0.0, -12.3, 2.6), (9.6, -12.3, 2.6), (-9.6, -12.3, 2.6), (13.7, -12.0, 2.6),
                     (-13.7, -12.0, 2.6), (-17.7, -11.6, 2.6), (16.1, -8.3, 2.6), (-16.1, -8.3, 2.6)])
    border_undergrowth(kit, hw, hd, n=34)


def build_arena_b(kit, L):
    """Thornroot Hollow (dusk): a round hollow ringed by giant red thorn roots; a goblin shrine between the exits."""
    hw, hd = L["hw"], L["hd"]
    col, hgt = night_ground(hw, hd, 4.1)
    ground(kit, 34.0, -30.0, 18.0, 1.6, col, hgt)
    # the giant root arch over the north edge, framing the shrine and the two exits
    root(kit, [(-hw - 2.5, -0.2, -hd - 0.5), (-7.5, 1.6, -hd - 1.8), (-3.0, 3.8, -hd - 2.6), (0.0, 4.5, -hd - 2.7),
               (3.1, 3.7, -hd - 2.5), (7.2, 1.8, -hd - 1.6), (hw + 2.5, -0.2, -hd - 0.4)], 0.5, 0.36)
    root(kit, [(-3.4, 3.6, -hd - 2.6), (-4.4, 2.2, -hd - 3.8), (-5.4, 0.6, -hd - 4.8), (-5.8, -0.2, -hd - 5.5)], 0.4, 0.2)
    root(kit, [(3.4, 3.5, -hd - 2.5), (4.8, 2.0, -hd - 3.6), (6.0, 0.5, -hd - 4.4), (6.4, -0.2, -hd - 5.0)], 0.4, 0.2)
    # a second, smaller arch over the west rim: the other landmark on the way round the hollow
    root(kit, [(-hw - 3.4, -0.2, -5.6), (-hw - 2.2, 1.8, -3.0), (-hw - 1.6, 2.6, -0.4), (-hw - 2.4, 1.7, 2.2),
               (-hw - 3.6, -0.2, 4.6)], 0.38, 0.26, thorn_scale=0.8)
    # roots creeping round the rim (low, a few cross the edge of the floor)
    for (x0, z0, x1, z1, lift, r0) in [(-hw - 3, -2.5, -hw + 1.6, 2.0, 0.5, 0.36), (-hw - 2.6, 5.0, -hw + 0.5, 8.8, 0.4, 0.3),
                                       (hw + 3, -4.5, hw - 1.5, -0.6, 0.5, 0.36), (hw + 2.6, 4.5, hw - 0.3, 8.6, 0.4, 0.3),
                                       (-hw - 1.0, -hd - 1.5, -hw + 2.6, -hd + 1.0, 0.6, 0.34),
                                       (hw + 1.0, -hd - 1.5, hw - 2.8, -hd + 0.8, 0.6, 0.34),
]:  # (none on the south, camera side)
        root_arc(kit, x0, z0, x1, z1, lift, r0, 0.05)
    for p in L["exit_portals"]:
        flagstone_path(kit, p[0] * 0.4, -1.6, p[0], p[2], col=(0.27, 0.27, 0.26))
    # a ring of bone stakes around the hollow's middle (flat bones: walkable)
    for i in range(12):
        a = i / 12 * math.tau
        bones(kit, math.cos(a) * 8.0, math.sin(a) * 6.0 + 0.6, 1)
    mud_puddle(kit, 2.6, 5.4, 1.5)
    mud_puddle(kit, -5.4, -1.0, 1.2)
    mud_puddle(kit, 10.4, 1.2, 1.1)
    for o in L["obstacles"]:
        if o["kind"] == "totem":
            # the shrine (orc kit): the horned totem on its cairn, a war banner on each side, both behind it
            # (north), so they frame the exits without hiding the floor
            orc_totem(kit, o["x"], o["z"], o["size"], height=2.1)
            for side in (-1, 1):
                kit.orc("war_banner_lo", o["x"] + side * 2.1, o["z"] - 1.3, yaw=-side * 12.0, s=0.95)
            glow_mushrooms(kit, o["x"] - 0.9, o["z"] + 0.8, 3)
        elif o["kind"] == "rock":
            big_rock(kit, o["x"], o["z"], o["size"])
            glow_mushrooms(kit, o["x"] + 0.9, o["z"] + 0.9, 2)
        elif o["kind"] == "rootknot":
            root_stump(kit, o["x"], o["z"], o["size"])
        elif o["kind"] == "rootwell":
            root_well(kit, o["x"], o["z"], o["size"])
    # the goblins' camp on the rim (orc kit, outside the bounds): hide huts facing in, a hanging cage on the east
    # rim, bone fences where the old stake clusters stood
    kit.orc("hut_lo", -hw - 3.9, -6.4, yaw=80.0)
    kit.orc("hut_lo", hw + 3.6, 2.6, yaw=-100.0, s=0.85)
    kit.orc("cage_lo", hw + 2.9, -6.2, yaw=-90.0)
    kit.orc("bone_fence_lo", hw + 1.9, -1.0, yaw=-90.0)
    kit.orc("bone_fence_lo", -hw - 1.9, 3.4, yaw=90.0)
    kit.orc("bone_fence_lo", 9.6, -hd - 1.3, yaw=8.0)
    bones(kit, -11.6, -6.4, 3)
    bones(kit, 11.4, -7.0, 2)
    glow_mushrooms(kit, -hw - 0.7, -5.5, 4)
    glow_mushrooms(kit, hw + 0.7, 5.5, 4)
    glow_mushrooms(kit, 8.6, -hd - 1.2, 3)
    glow_mushrooms(kit, -8.8, -hd - 0.9, 3)
    campfire(kit, *L["fire"], s=0.8, light_name="light_fire_0")
    log_seat(kit, L["fire"][0] - 1.6, L["fire"][1] - 0.4, 1.6)
    forest_border(kit, hw, hd, keep_out=[(0, -hd - 3, 3.5), (-hw - 3.9, -6.4, 3.0), (hw + 3.6, 2.6, 2.8),
                                         (-hw - 2.4, 0.0, 3.2), (hw + 2.9, -6.2, 2.2), (hw + 1.9, -1.0, 1.6),
                                         (-hw - 1.9, 3.4, 1.6), (9.6, -hd - 1.3, 1.6)], broad_share=0.35, dead_share=0.12)
    border_undergrowth(kit, hw, hd, n=34)


def build_arena_c(kit, L):
    """Goblin Quarry (night): a worked-out stone pit the goblins have taken over. The cut rock face closes the
    north side and the two ramps up through it are the exits; the winch with its hanging boulder is the landmark."""
    hw, hd = L["hw"], L["hd"]

    def colour_at(x, z):
        e = (x / (hw + 0.5)) ** 2 + (z / (hd + 0.5)) ** 2
        n = hash_noise(x, z, 6.7)
        # a worked floor: grey cut stone with gravel drifts and ochre water stains
        c = mix(GRAVEL, GRAVEL_LIGHT, clamp(0.45 + 0.4 * n - 0.2 * e))
        c = mix(c, OCHRE, clamp(0.5 * hash_noise(x * 0.6 + 4.0, z * 0.5, 1.9)))
        c = mix(c, QUARRY_DARK, clamp((math.sqrt(max(e, 0.0)) - 0.9) * 1.5))
        return c

    def height_at(x, z):
        e = max(abs(x) - hw, -z - hd, z - hd, 0.0)
        return FLOOR_Y + (0.0 if e <= 0.3 else min(e * 0.14, 0.7) * (0.6 + 0.4 * hash_noise(x * 1.7, z * 1.7, 6.7)))
    ground(kit, 34.0, -30.0, 18.0, 1.6, colour_at, height_at)
    ramps = [(p[0], 1.3) for p in L["exit_portals"]]
    quarry_border(kit, hw, hd, ramps=ramps, keep_out=[(hw + 2.1, 4.0, 3.0), (-hw - 2.1, 5.0, 3.0),
                                                      (hw + 2.1, -4.0, 2.4)])
    winch_frame(kit, 0.0, -hd - 2.6, light="light_fire_1")
    # the rails: from the north-east ramp down across the pit to the south-west loading spot
    rail_track(kit, 7.8, -hd - 0.5, 12.6, 7.4)
    ore_cart(kit, 13.4, 8.6, (1.9, 1.4, 1.1), yaw=1.9, tipped=False)   # a sound cart parked at the end of the line
    # worked stone: half-cut blocks still attached to the floor, chisel marks, puddles in the hollows
    for (bx, bz, bw, bd) in [(-9.0, 4.6, 3.0, 1.8), (7.8, 6.4, 2.6, 1.6), (-12.2, -3.6, 2.2, 1.5)]:
        kit.box("gf_main", (bx, 0.1, bz), (bw, 0.2, bd), mix(QUARRY_LIGHT, QUARRY_STONE, 0.3), yaw=kit.r(-0.2, 0.2))
    mud_puddle(kit, 3.4, 4.8, 1.6, base=GRAVEL_LIGHT)
    mud_puddle(kit, -4.4, -2.2, 1.3, base=GRAVEL_LIGHT)
    mud_puddle(kit, 11.0, -4.4, 1.2, base=GRAVEL_LIGHT)
    mud_puddle(kit, -8.0, 8.0, 1.1, base=GRAVEL_LIGHT)
    for p in L["exit_portals"]:
        flagstone_path(kit, p[0] * 0.45, -2.2, p[0], p[2], col=(0.38, 0.37, 0.35))
    # goblin squatters: tents and junk wedged against the quarry walls (outside the bounds)
    # goblin squatters (orc kit): huts and junk wedged against the quarry walls (outside the bounds), the forge
    # where they work the iron, a war banner and picket fences on the benches
    kit.orc("hut_lo", -hw - 2.9, 5.4, yaw=90.0, s=0.9)
    kit.orc("hut_lo", hw + 2.9, 4.2, yaw=-90.0, s=0.85)
    kit.orc("forge_lo", hw + 2.6, -4.0, yaw=-90.0, s=0.9)
    barrel(kit, hw + 1.7, 7.0)
    crate(kit, -hw - 1.6, 0.0, 8.0, 0.8, 0.2)
    kit.orc("war_banner_lo", -hw - 1.9, 1.2, yaw=90.0)
    kit.orc("picket_fence_lo", hw + 1.7, 0.2, yaw=-90.0)
    kit.orc("picket_fence_lo", -hw - 1.7, -5.0, yaw=90.0)
    bones(kit, -5.6, 6.6, 3)
    bones(kit, 6.0, -8.6, 2)
    bones(kit, 12.4, 5.0, 2)
    glow_mushrooms(kit, -hw - 0.6, -7.0, 4)   # the shade under the north-west wall
    glow_mushrooms(kit, hw + 0.6, -6.0, 4)
    glow_mushrooms(kit, -3.0, -hd - 0.8, 3)
    glow_mushrooms(kit, 4.0, -hd - 0.9, 3)
    campfire(kit, *L["fire"], s=0.9, light_name="light_fire_0")
    log_seat(kit, L["fire"][0] + 1.6, L["fire"][1] + 0.2, 1.3)
    for o in L["obstacles"]:
        if o["kind"] == "block":
            stone_block(kit, o["x"], o["z"], o["size"], yaw=o.get("yaw", 0.0))
        elif o["kind"] == "spoil":
            spoil_heap(kit, o["x"], o["z"], o["size"])
        elif o["kind"] == "orecart":   # (axis-aligned and upright: the tub must wrap its solid box)
            ore_cart(kit, o["x"], o["z"], o["size"], yaw=0.0, tipped=False)
        elif o["kind"] == "rock":
            big_rock(kit, o["x"], o["z"], o["size"])


def build_rest(kit, L):
    """Goblin Rest: a quiet, safe clearing; a calm warm campfire with logs to sit on, a lantern, a tent, a crate."""
    hw, hd = L["hw"], L["hd"]

    def colour_at(x, z):
        e = (x / (hw + 0.5)) ** 2 + (z / (hd + 0.5)) ** 2
        n = hash_noise(x, z, 2.2)
        c = mix(CAMP_GRASS, CAMP_GRASS_LIGHT, 0.5 + 0.4 * n - 0.25 * e)
        fx, fz = L["campfire"][0], L["campfire"][2]
        d = math.hypot(x - fx, z - fz)
        c = mix(CAMP_PATH, c, clamp((d - 1.8) / 1.8))  # trodden earth round the fire
        if e > 1.0:
            c = mix(c, (0.12, 0.18, 0.12), clamp((math.sqrt(e) - 1.0) * 1.2))
        return c

    def height_at(x, z):
        e = max(abs(x) - hw, -z - hd, z - hd, 0.0)
        return FLOOR_Y + (0.0 if e <= 0.3 else min(e * 0.1, 0.5) * (0.6 + 0.4 * hash_noise(x * 1.7, z * 1.7, 2.2)))
    ground(kit, 34.0, -30.0, 18.0, 1.6, colour_at, height_at)
    fx, fz = L["campfire"][0], L["campfire"][2]
    # the camp's fire is the orc kit's bonfire (stone ring, crossed logs, flames; walkable like the old one)
    kit.orc("bonfire", fx, fz, s=0.72, lights=[])
    kit.empty("light_fire_0", (fx, 1.0, fz))
    kit.empty("campfire", tuple(L["campfire"]))
    for a in (0.35, 2.3, 4.1):
        log_seat(kit, fx + math.cos(a) * 1.95, fz + math.sin(a) * 1.95, a + math.pi / 2, 1.6)
    # the camp's buildings (orc kit, Boss 2026-10-15): two hide huts and the forge, all turned to the fire; each
    # wraps its solid (a rest map: no monsters, so these solids were re-fitted to the kit pieces, see STAGES)
    for o in L["obstacles"]:
        x, z = o["x"], o["z"]
        sx, sy, sz = o["size"]
        if o["kind"] == "hut":
            kit.orc("hut", x + o["dx"], z, yaw=-90.0, s=o["s"])
            # a dark backing inside the doorway, so the solid's face never shows through it
            kit.box("gf_main", (x - sx / 2 - 0.03, sy / 2, z), (0.04, sy, sz * 0.8), (0.05, 0.04, 0.03))
        elif o["kind"] == "forge":
            kit.orc("forge", x + o["dx"], z, yaw=90.0, s=o["s"])
            kit.box("gf_main", (x + sx / 2 + 0.03, 0.6, z), (0.04, 1.2, sz * 0.6), (0.06, 0.05, 0.04))
            barrel(kit, x + 0.3, z + sz / 2 + 0.7, 0.8)
            crate(kit, x - 0.4, 0.0, z - sz / 2 - 0.8, 0.8, 0.3)
    lantern_post(kit, *L["lantern"], light="light_lantern_0")
    kit.orc("war_banner_lo", L["rack"][0], L["rack"][1], yaw=60.0, s=0.9)
    # the camp's north edge: picket fences either side of the two exit paths (outside the bounds)
    for px, yaw in ((0.0, 0.0), (-7.4, 6.0), (7.4, -6.0)):
        kit.orc("picket_fence_lo", px, -hd - 1.1, yaw=yaw)
    for i in range(3):  # a stack of firewood by the fire
        kit.tube("gf_main", (fx + 2.9, 0.14 + i * 0.26, fz + 2.2 - i * 0.08), (fx + 4.0, 0.16 + i * 0.26, fz + 2.3 - i * 0.08),
                 0.13, 0.12, 6, mix(WOOD, (0.27, 0.19, 0.12), 0.4), top_color=(0.46, 0.37, 0.25))
    # flowers, ferns and fireflies: the soft, green mood
    for i in range(48):
        x, z = kit.r(-hw - 1, hw + 1), kit.r(-hd - 1, hd + 1)
        if math.hypot(x - fx, z - fz) < 2.8:
            continue
        kit.prism("gf_main", (x, 0.0, z), 0.06, 0.0, 0.10, 4, mix(kit.pick(CAMP_FLOWERS), CAMP_GRASS, 0.35), jitter=0.1)
    for i in range(16):
        a = i / 16 * math.tau
        kit.blob("gf_glow", (fx + math.cos(a) * kit.r(3.0, 8.0), kit.r(0.6, 1.8), fz + math.sin(a) * kit.r(2.5, 6.0)), 0.04,
                 (0.85, 0.95, 0.45), subdiv=1, wobble=0.0)
    for p in L["exit_portals"]:
        flagstone_path(kit, p[0] * 0.4, fz - 1.8, p[0], p[2], col=(0.42, 0.40, 0.36))
    palette = [(0.14, 0.26, 0.13), (0.18, 0.30, 0.14), (0.12, 0.22, 0.14)]
    rock(kit, -hw - 0.9, 3.2, 0.9)
    rock(kit, hw + 1.0, -1.8, 1.0)
    rock(kit, hw + 0.8, 5.2, 0.7)
    forest_border(kit, hw, hd, broad_share=0.55, dead_share=0.0, palette=palette,
                  keep_out=[(L["rack"][0], L["rack"][1], 2.2)])
    border_undergrowth(kit, hw, hd, n=32, palette=palette)


# ---------------------------------------------------------------- layouts (single source of truth)


def build_boss(kit, L):
    """Brush Ring, the journey's boss room, dressed as the orc war-chief's court (night). ART ONLY: the map file
    data/maps/brush_ring.json is hand-tuned (boss sweep) and keeps its own solids, spawns and floor; this builds the
    art scene round them. North, behind the boss: the horned throne between two bonfires, two horned gates (the way
    out) and palisade sections, watchtowers on both corners; huts, a cage and banners down the sides; the four
    corner rocks of the map (its only cover) are kept where they are."""
    hw, hd = L["hw"], L["hd"]
    col, hgt = night_ground(hw, hd, 7.7)
    ground(kit, 36.0, -30.0, 20.0, 1.6, col, hgt)
    zn = -hd - 1.6   # the north wall line, just outside the bounds
    kit.orc("throne", 0.0, zn - 0.7, s=1.15)
    for side in (-1, 1):
        kit.orc("bonfire", side * 4.6, zn - 0.2, s=0.85)
        kit.orc("gate_lo", side * 9.6, zn, lights=[0 if side > 0 else 1])
        kit.orc("palisade_lo", side * 14.3, zn + 0.05, yaw=side * 3.0)
        kit.orc("watchtower", side * 19.2, zn - 0.6, yaw=-side * 20.0, lights=[0])
        kit.orc("palisade_lo", side * 17.9, -6.8, yaw=-side * 90.0)
        kit.orc("war_banner_lo", side * 17.4, -2.6, yaw=-side * 90.0)
        kit.orc("bone_fence_lo", side * 8.6, hd + 1.6, yaw=side * 6.0)
    kit.orc("hut_lo", -19.6, 1.2, yaw=90.0)
    kit.orc("hut_lo", 19.6, 3.6, yaw=-90.0, s=0.9)
    kit.orc("cage_lo", -18.4, 7.0, yaw=90.0)
    kit.orc("forge_lo", 18.6, -1.4, yaw=-90.0, s=0.85)
    # a carpet of flagstones from the throne down to the middle, and two to the exit gates
    flagstone_path(kit, 0.0, zn + 1.4, 0.0, -2.6, col=(0.36, 0.33, 0.30))
    for p in L["exit_portals"]:
        flagstone_path(kit, p[0] * 0.5, -3.8, p[0], p[2], col=(0.32, 0.31, 0.29))
    for o in L["obstacles"]:
        if o["kind"] == "totem":
            orc_totem(kit, o["x"], o["z"], o["size"], height=1.8)
        elif o["kind"] == "rock":
            big_rock(kit, o["x"], o["z"], o["size"])
    for (bx, bz, n) in [(-6.0, 2.6, 3), (5.2, 4.4, 2), (-2.6, -6.0, 2), (12.4, -2.0, 3), (-13.0, -1.4, 2)]:
        bones(kit, bx, bz, n)
    for (mx, mz, r) in [(-4.2, 3.4, 1.4), (6.6, -3.0, 1.2), (9.0, 7.4, 1.1), (-9.6, 7.8, 1.2)]:
        mud_puddle(kit, mx, mz, r)
    root_arc(kit, -hw - 4.0, 3.0, -hw + 1.2, 6.0, 0.45, 0.30, 0.05)
    root_arc(kit, hw + 4.0, -5.0, hw - 1.0, -2.0, 0.5, 0.30, 0.05)
    glow_mushrooms(kit, -hw - 0.8, -3.0, 3)
    glow_mushrooms(kit, hw + 0.8, 6.0, 3)
    forest_border(kit, hw, hd, density=0.8, north_to=-26.0, side_to=27.0,
                  keep_out=[(0.0, zn - 0.7, 4.2), (-4.6, zn, 2.0), (4.6, zn, 2.0), (-9.6, zn, 3.4), (9.6, zn, 3.4),
                            (-14.3, zn, 2.6), (14.3, zn, 2.6), (-19.2, zn - 0.6, 3.4), (19.2, zn - 0.6, 3.4),
                            (-17.9, -6.8, 2.6), (17.9, -6.8, 2.6), (-17.4, -2.6, 1.6), (17.4, -2.6, 1.6),
                            (-19.6, 1.2, 3.0), (19.6, 3.6, 2.8), (-18.4, 7.0, 2.0), (18.6, -1.4, 2.4)])
    border_undergrowth(kit, hw, hd, n=36)

STAGES = {
    "goblin_arena_a": {
        "name": "Goblin Camp Gate",
        "builder": build_arena_a, "seed": 11, "hw": 14.0, "hd": 10.5, "kind": "fight", "mood": "night", "gain": 1.9,
        "spawn": [0.0, SPOT_Y, 8.6],
        "fire": (-11.4, 6.8),
        "exit_portals": [[-4.8, SPOT_Y, -8.4], [4.8, SPOT_Y, -8.4]],
        # monsters take spots in list order: goblins (listed first in a fight) start nearest, ranged furthest back
        "enemy_spots": [[-4.8, 2.8], [4.6, 1.8], [-1.0, -1.6], [8.6, -1.2], [-8.8, -2.2], [2.4, -6.6],
                        [12.0, -7.2], [-11.6, -6.8]],
        "enemies": ["goblin", "goblin", "goblin", "goblin", "goblin", "goblin", "goblin_archer", "goblin"],
        "obstacles": [("totem", -7.6, -1.8, (0.8, 1.6, 0.8)), ("rock", 7.2, 3.2, (1.6, 1.5, 1.5)),
                      ("crates", 10.8, -5.2, (1.1, 1.5, 1.1)),
                      ("barricade", -10.8, -4.6, (2.8, 1.5, 0.6), 1.35),
                      ("rock", 1.8, -3.8, (1.3, 1.5, 1.3)),
                      ("logs", 9.6, 6.6, (2.4, 1.5, 1.0), 0.35)],
        "design": "Fight arena (Boss 2026-10-14: 28 x 21 m, ~1.7x the first version, 2-2.5 screens at camera 8 - room "
                  "to retreat, circle and kite; still ONE arena, portals north when it is cleared). Night goblin camp: "
                  "the goblins' spiked palisade closes the north side and its two skull-post gates are where the exit "
                  "portals stand (flagstone paths lead to them, so the way out reads before it opens). Landmarks: a "
                  "goblin watchtower with a watch-fire over the north-east corner and the gates themselves; both "
                  "outside the walkable box, so nothing tall can hide a fight. Six cover pieces spread over the bigger "
                  "floor - totem west, moss rocks (south-east and centre-north), crate stack north-east, plank "
                  "barricade north-west, log pile south-east - leave a clear ring to run and an open middle to fight "
                  "in; mud patches, bones and thorn roots keep the extra floor from reading empty. The player starts "
                  "south-centre; spots go near-to-far so goblins arrive first and the archer (second-last spot, far "
                  "north-east) shoots from behind the crates.",
    },
    "goblin_arena_b": {
        "name": "Thornroot Hollow",
        "builder": build_arena_b, "seed": 23, "hw": 13.5, "hd": 10.5, "kind": "fight", "mood": "night", "gain": 1.9,
        "spawn": [0.0, SPOT_Y, 8.6],
        "fire": (9.4, 7.0),
        "exit_portals": [[-5.2, SPOT_Y, -8.2], [5.2, SPOT_Y, -8.2]],
        "enemy_spots": [[4.8, 2.8], [-4.6, 1.6], [0.8, -2.0], [-8.4, -4.8], [8.6, -4.8], [-2.4, -7.0],
                        [-11.4, 1.2], [11.4, -1.8]],
        "enemies": ["goblin", "goblin", "goblin", "goblin", "goblin_knight", "goblin", "goblin_archer", "goblin_mage"],
        "obstacles": [("totem", 0.0, -8.6, (0.9, 1.6, 0.9)), ("rock", -6.8, 3.4, (1.6, 1.5, 1.6)),
                      ("rootknot", 7.4, -2.0, (1.3, 1.5, 1.3)),
                      ("rootwell", -2.8, -4.8, (1.8, 1.5, 1.8)),
                      ("rock", 10.2, 4.6, (1.4, 1.5, 1.4)),
                      ("rootknot", -10.4, -1.8, (1.2, 1.5, 1.2))],
        "design": "Fight arena, dusk (Boss 2026-10-14: 27 x 21 m, ~1.7x the first version). A round hollow ringed by "
                  "giant thorny red roots; one huge root arches over the north edge and frames a goblin shrine (totem "
                  "with skull stakes) between the two exit portals, a second arch spans the west rim - two landmarks "
                  "that also say 'the way out is north'. Inside, six cover pieces ring an open middle: moss rocks "
                  "south-west and east, two broken stumps gripped by red roots (east and west), and the thornroot well "
                  "- a woven basket of roots round a cold-glowing pool, the only cool light in the field and the one "
                  "piece of cover worth fighting around. The player starts south-centre; melee spots are near, the "
                  "ranged ones last on the west and east flanks, so a mixed fight pulls the player sideways across the "
                  "wide floor instead of straight north.",
    },
    "goblin_arena_c": {
        "name": "Goblin Quarry",
        "builder": build_arena_c, "seed": 59, "hw": 14.0, "hd": 10.5, "kind": "fight", "mood": "night", "gain": 1.75,
        "spawn": [0.0, SPOT_Y, 8.6],
        "fire": (-11.6, 6.4),
        "exit_portals": [[-5.0, SPOT_Y, -8.6], [5.0, SPOT_Y, -8.6]],
        "enemy_spots": [[-4.8, 2.6], [4.6, 2.0], [0.6, -1.4], [-8.8, -1.0], [8.8, -2.8], [2.8, -6.4],
                        [12.0, -6.8], [-11.8, -6.4]],
        "enemies": ["goblin", "goblin", "goblin", "goblin", "goblin", "goblin_knight", "goblin_archer", "goblin"],
        "obstacles": [("block", -7.4, -4.4, (1.7, 1.5, 1.7), 0.3), ("block", 6.8, -5.2, (1.5, 1.5, 1.5), -0.2),
                      ("block", 2.2, 1.6, (1.6, 1.5, 1.4), 0.5),
                      ("orecart", -2.1, -6.8, (2.0, 1.5, 1.1), 0.25),
                      ("spoil", 10.6, 2.6, (2.2, 1.5, 2.0)),
                      ("block", -11.0, 1.4, (1.5, 1.5, 1.5), -0.4)],
        "design": "Third fight arena (Boss 2026-10-14: a goblin quarry, same 28 x 21 m as the other two). A worked-out "
                  "stone pit the goblins squat in: grey cut floor streaked with ochre water stains, stepped rock "
                  "benches outside the walkable box and a high cut face across the north with two ramps hacked through "
                  "it - the exit portals stand on the ramps, flagged by skull posts and red rags. Landmark: the "
                  "quarry winch, a timber A-frame with a cracked boulder hanging in a rope net and a brazier at its "
                  "foot, dead centre on the north face; a rusty rail line runs from the north-east ramp across the "
                  "pit to a parked ore cart, so the eye always knows which way the pit works. Cover is cut stone: "
                  "four blocks spread wide, a spoil heap east and a tipped ore cart north-west; the middle stays open "
                  "for the knight (sixth spot) to march into. Glow mushrooms in the wall shade and a small fire "
                  "south-west give the night its warm and cold lights.",
    },
    "goblin_rest_camp": {
        "name": "Goblin Rest Camp",
        "builder": build_rest, "seed": 37, "hw": 9.8, "hd": 7.5, "kind": "rest", "mood": "camp", "gain": 1.3,
        "spawn": [0.0, SPOT_Y, 5.9],
        "campfire": [0.0, SPOT_Y, -0.6],
        "lantern": (-4.6, -3.4),
        "rack": (-7.4, 3.6),
        "exit_portals": [[-3.9, SPOT_Y, -5.6], [3.9, SPOT_Y, -5.6]],
        "enemy_spots": [],
        "enemies": [],
        # (orc kit 2026-10-15: the canvas tents became the kit's hide huts and the supply stack its forge; their
        # solids were re-fitted to the pieces - no monsters here, so no balance depends on them. dx = the art's
        # offset from the solid's centre, s = the kit scale; huts and forge face the fire)
        "obstacles": [("hut", 7.0, -3.0, (1.2, 1.2, 1.7), 0.0, {"dx": -0.03, "s": 0.8}),
                      ("forge", -6.7, -0.8, (1.0, 1.5, 1.8), 0.0, {"dx": 0.3, "s": 0.8}),
                      ("hut", 6.4, 3.8, (1.1, 1.2, 1.6), 0.0, {"dx": -0.03, "s": 0.75})],
        "design": "Safe rest stop between fights (no monsters; Boss 2026-10-14: grown to 19.6 x 15 m, ~1.3x). A green "
                  "clearing round a calm campfire with three logs to sit on, a lantern post, two canvas tents, a "
                  "supply crate stack, a hide-drying rack and a firewood stack; fireflies, flowers and warm light. The "
                  "rest point is the campfire (`campfire` + a rest point there). The two exit portals stand north as "
                  "in the fight arenas, so every stage reads the same way: come in south, leave north.",
    },
    "brush_ring": {
        # ART ONLY (orc kit, Boss 2026-10-15): data/maps/brush_ring.json is hand-written and tuned by the boss
        # sweep; its solids / spawns are mirrored here only to place the art (keep them in step by hand)
        "name": "Brush Ring", "art_only": True,
        "builder": build_boss, "seed": 71, "hw": 16.0, "hd": 11.0, "kind": "fight", "mood": "night", "gain": 1.9,
        "spawn": [0.0, SPOT_Y, 6.0],
        "exit_portals": [[-4.0, SPOT_Y, -6.6], [4.0, SPOT_Y, -6.6]],   # (the loader's default spots for this map)
        "enemy_spots": [[0.0, -1.0], [-9.0, 1.0], [9.0, 1.0], [-6.0, -7.0], [6.0, -7.0]],
        "enemies": ["goblin_chief", "goblin", "goblin", "goblin_archer", "goblin_mage"],
        "obstacles": [("totem", -11.0, -6.0, (1.6, 1.2, 1.6)), ("totem", 11.0, -6.0, (1.6, 1.2, 1.6)),
                      ("rock", -12.0, 5.0, (1.6, 1.2, 1.6)), ("rock", 12.0, 5.0, (1.6, 1.2, 1.6))],
        "design": "",
    },
}


def layout_of(map_id):
    S = STAGES[map_id]
    L = dict(S)
    L["obstacles"] = [dict({"kind": o[0], "x": o[1], "z": o[2], "size": o[3], "yaw": o[4] if len(o) > 4 else 0.0},
                           **(o[5] if len(o) > 5 else {})) for o in S["obstacles"]]
    return L


def map_json(map_id, L):
    hw, hd = L["hw"], L["hd"]
    solids = [{"center": [0, -0.2, 0], "size": [hw * 2, 0.4, hd * 2], "material": "ink"}]
    for o in L["obstacles"]:
        sx, sy, sz = o["size"]
        solids.append({"center": [o["x"], round(sy / 2, 3), o["z"]], "size": [sx, sy, sz], "material": "ink"})  # (hidden inside the art; ink = dark if a corner shows)
    data = {
        "version": 1,
        "id": map_id,
        "name": L["name"],
        "_design": L["design"] + " Built by tools/blender/build_goblin_stages.py (art and this file come from one "
                                 "layout; edit the script, not this file).",
        "modes": ["pve"],
        "kind": L["kind"],
        "camera_style": "top_down",
        "atmosphere": "ink",
        "art_scene": RES_ART + map_id + ".glb",
        "art_mood": L["mood"],
        "bounds": {"half_width": hw, "half_depth": hd},
        "spawn": L["spawn"],
        "exit_portals": L["exit_portals"],
        "solids": solids,
        "enemy_spawns": [{"type": t, "level": 1, "position": [s[0], SPOT_Y, s[1]]}
                         for t, s in zip(L["enemies"], L["enemy_spots"])],
        "rest_points": [],
    }
    if L["kind"] == "rest":
        data["campfire"] = L["campfire"]
        data["rest_points"] = [{"id": "campfire", "position": [L["campfire"][0], SPOT_Y, L["campfire"][2] + 2.2],
                                "radius": 2.0}]
    return data


# ---------------------------------------------------------------- materials + export

def make_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if name == "orc_kit":   # the kit's shared atlas (the export points it at the external png, see build())
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(ORC_ATLAS, check_existing=True)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Metallic"].default_value = 0.0
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = bpy.data.images.load(ORC_NORMAL, check_existing=True)
        ntex.image.colorspace_settings.name = 'Non-Color'
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        m.use_backface_culling = False   # (glTF doubleSided: the kit's banners and hides are single sheets)
        return m
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    if name == "gf_fire":
        bsdf.inputs["Emission Color"].default_value = (1.0, 0.45, 0.10, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.2
    elif name == "gf_glow":
        bsdf.inputs["Emission Color"].default_value = (0.35, 0.80, 0.95, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.6
    return m


def build(map_id):
    global GAIN
    bpy.ops.wm.read_factory_settings(use_empty=True)
    L = layout_of(map_id)
    GAIN = L["gain"]
    kit = Kit(L["seed"])
    L["builder"](kit, L)
    kit.empty("spawn", tuple(L["spawn"]))
    for i, s in enumerate(L["enemy_spots"]):
        kit.empty("enemy_%d" % i, (s[0], SPOT_Y, s[1]))
    for i, p in enumerate(L["exit_portals"]):
        kit.empty("exit_portal_%d" % i, tuple(p))
    objs = []
    tris = {}
    for mat_name, b in kit.bms.items():
        me = bpy.data.meshes.new(map_id + "_" + mat_name)
        b.to_mesh(me)
        b.free()
        me.color_attributes.active_color_index = me.color_attributes.find("Col")
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
        if mat_name == "orc_kit":
            build_orc_kit.set_loop_normals(me)   # (the kit's source shading normals, not Blender's recomputed ones)
        me.materials.append(make_material(mat_name))
        ob = bpy.data.objects.new(map_id + "_" + mat_name, me)
        bpy.context.scene.collection.objects.link(ob)
        objs.append(ob)
        tris[mat_name] = sum(len(p.vertices) - 2 for p in me.polygons)
    for name, pos in kit.empties:
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = 'PLAIN_AXES'
        e.location = P(*pos)
        bpy.context.scene.collection.objects.link(e)
        objs.append(e)
    os.makedirs(ART_DIR, exist_ok=True)
    path = os.path.join(ART_DIR, map_id + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_animations=False, export_lights=False,
              export_cameras=False, export_apply=False, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    if "orc_kit" in kit.bms or "orc_kit" in tris:
        build_orc_kit.glb_external_image(path, {"orc_kit_atlas": ORC_ATLAS_URI, "orc_kit_normal": ORC_NORMAL_URI})
    data = map_json(map_id, L)
    if "--art-only" in sys.argv:
        pass  # Geometry/texture maintenance must not rewrite live gameplay map data.
    elif L.get("art_only"):
        # the map file is hand-written: only check that the art was laid round its real solids and spawn
        with open(os.path.join(MAP_DIR, map_id + ".json")) as f:
            real = json.load(f)
        want = sorted((s["center"][0], s["center"][2], tuple(s["size"])) for s in data["solids"][1:])
        have = sorted((s["center"][0], s["center"][2], tuple(s["size"])) for s in real["solids"][1:])
        assert want == have, "art layout of %s is out of step with its map solids: %s vs %s" % (map_id, want, have)
        assert [round(v, 3) for v in real["spawn"]] == [round(v, 3) for v in data["spawn"]], "spawn out of step"
    else:
        with open(os.path.join(MAP_DIR, map_id + ".json"), "w") as f:
            f.write(json.dumps(data, indent="\t") + "\n")
    print("STAGE %s tris %d %s draw_calls %d empties %d glb %d KB" % (
        map_id, sum(tris.values()), tris, len(tris), len(kit.empties), os.path.getsize(path) // 1024))


ids = [arg for arg in sys.argv[sys.argv.index("--") + 1:] if arg != "--art-only"] if "--" in sys.argv else []
ids = ids or list(STAGES)
for map_id in ids:
    build(map_id)

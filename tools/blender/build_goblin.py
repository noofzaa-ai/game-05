# Builds the game goblin from the raw AI mesh: reduce, UV + painted texture, light monster rig, twin daggers.
# Run:  blender -b --factory-startup -P tools/blender/build_goblin.py
# In:   art_source/monsters/goblin/source/gobbin.glb  (301k tris, no UV/material/skeleton)
# Out:  art/monsters/goblin/goblin.glb, art_source/monsters/goblin/goblin.blend,
#       art_source/monsters/goblin/textures/goblin_albedo.png
# Blender axes: front = -Y (exports as glTF/Godot +Z), up = +Z, feet at the origin, metres.
# Bone convention: every bone's local Z points "forward" (character facing) except bones that themselves
# point forward/sideways (jaw, ears, feet, toes, attach_weapon), whose local Z points up.
# So a positive local-X rotation always swings the bone tip toward its Z axis (forward, or up).
import bpy, bmesh, os, sys, math
import numpy as np
from mathutils import Vector, Matrix, Euler

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "art_source/monsters/goblin/source/gobbin.glb")
OUT_GLB = os.path.join(ROOT, "art/monsters/goblin/goblin.glb")
OUT_BLEND = os.path.join(ROOT, "art_source/monsters/goblin/goblin.blend")
TEX = os.path.join(ROOT, "art_source/monsters/goblin/textures/goblin_albedo.png")
TEX_SIZE = 512
# GOBLIN_STAGE=prehunch (used by build_goblin_variants.py): stop before the hunch and cache the pre-hunch
# body/rig + the hi-poly bake maps for the variants; the approved outputs are not touched in that mode.
STAGE = os.environ.get("GOBLIN_STAGE", "")
CACHE_DIR = os.path.join(ROOT, "art_source/monsters/goblin/cache")
if STAGE == "prehunch": TEX = os.path.join(CACHE_DIR, "goblin_albedo_prehunch.png")
BODY_TRIS = 8200
HEIGHT = 1.0          # player chibi is ~1.61; goblin rest height before the baked hunch
STRIP = 0.9375        # body UVs live in [0,STRIP]^2; the top strip holds dagger swatches

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

def activate(obj, *others):
    bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
    for o in bpy.data.objects: o.select_set(False)
    for o in others: o.select_set(True)
    obj.select_set(True); bpy.context.view_layer.objects.active = obj

def smooth(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t)

# ---------------------------------------------------------------- 1. import, normalise, strip hidden parts
bpy.ops.import_scene.gltf(filepath=SRC)
hi = [o for o in bpy.data.objects if o.type == 'MESH'][0]; hi.name = "goblin_hi"
activate(hi); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.array([v.co[:] for v in hi.data.vertices])
mn, mx = co.min(0), co.max(0)
s = HEIGHT / (mx[2] - mn[2]); ctr = np.array([(mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, mn[2]])
hi.data.vertices.foreach_set("co", ((co - ctr) * s).ravel())
for a in [a.name for a in hi.data.color_attributes]: hi.data.color_attributes.remove(hi.data.color_attributes[a])
hi.data.update()
bm = bmesh.new(); bm.from_mesh(hi.data)
seen, comps = set(), []
for v in bm.verts:            # 7 small shells sit fully inside the head/body: drop them
    if v.index in seen: continue
    st, comp = [v], [v]; seen.add(v.index)
    while st:
        x = st.pop()
        for e in x.link_edges:
            o = e.other_vert(x)
            if o.index not in seen: seen.add(o.index); st.append(o); comp.append(o)
    comps.append(comp)
comps.sort(key=len)
bmesh.ops.delete(bm, geom=[v for c in comps[:-1] for v in c], context='VERTS')
bm.to_mesh(hi.data); bm.free()

# ---------------------------------------------------------------- joints (rest, pre-hunch)
J = {
    "root": ((0, 0.05, 0), (0, 0.05, 0.1), None),
    "hips": ((0, 0.05, 0.22), (0, 0.05, 0.30), "root"),
    "spine": ((0, 0.05, 0.30), (0, 0.05, 0.38), "hips"),
    "chest": ((0, 0.05, 0.38), (0, 0.04, 0.47), "spine"),
    "neck": ((0, 0.04, 0.47), (0, 0.03, 0.53), "chest"),
    "head": ((0, 0.03, 0.53), (0, 0.03, 0.95), "neck"),
    "jaw": ((0, 0.0, 0.605), (0, -0.20, 0.545), "head"),
}
for sd, sx in (("L", 1), ("R", -1)):
    J.update({
        f"ear.{sd}": ((0.27 * sx, 0.0, 0.83), (0.42 * sx, 0.0, 0.885), "head"),
        f"ear_tip.{sd}": ((0.42 * sx, 0.0, 0.885), (0.575 * sx, 0.0, 0.905), f"ear.{sd}"),
        f"upper_arm.{sd}": ((0.15 * sx, 0.075, 0.45), (0.235 * sx, 0.065, 0.355), "chest"),
        f"forearm.{sd}": ((0.235 * sx, 0.065, 0.355), (0.27 * sx, 0.05, 0.29), f"upper_arm.{sd}"),
        f"hand.{sd}": ((0.27 * sx, 0.05, 0.29), (0.275 * sx, 0.045, 0.18), f"forearm.{sd}"),
        f"attach_weapon.{sd}": ((0.27 * sx, 0.045, 0.23), (0.27 * sx, -0.05, 0.23), f"hand.{sd}"),
        f"thigh.{sd}": ((0.095 * sx, 0.05, 0.22), (0.105 * sx, 0.055, 0.12), "hips"),
        f"shin.{sd}": ((0.105 * sx, 0.055, 0.12), (0.115 * sx, 0.08, 0.05), f"thigh.{sd}"),
        f"foot.{sd}": ((0.115 * sx, 0.08, 0.05), (0.115 * sx, 0.0, 0.015), f"shin.{sd}"),
        f"toe.{sd}": ((0.115 * sx, 0.0, 0.015), (0.115 * sx, -0.045, 0.015), f"foot.{sd}"),
    })
Z_UP = ("jaw", "ear", "ear_tip", "foot", "toe", "attach_weapon")

# ---------------------------------------------------------------- 2. decimate (joint zones kept denser)
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "goblin"; scene.collection.objects.link(lo)
vg = lo.vertex_groups.new(name="keep")
zones = [(J[f"{b}.{sd}"][0], r) for sd in "LR" for b, r in
         (("upper_arm", 0.07), ("forearm", 0.06), ("hand", 0.05), ("thigh", 0.07), ("shin", 0.055), ("foot", 0.05),
          ("ear", 0.06), ("ear_tip", 0.045))] + [((0, 0.03, 0.5), 0.12), ((0, 0.05, 0.3), 0.09)]
zc = np.array([z[0] for z in zones]); zr = np.array([z[1] for z in zones])
lco = np.array([v.co[:] for v in lo.data.vertices])
d = np.linalg.norm(lco[:, None, :] - zc[None], axis=2) / zr[None]
w = np.clip(1.5 - d, 0, 1).max(1)
for val in (1.0, 0.5):
    idx = np.nonzero((w >= val) & (w < val + 0.5 if val < 1 else w >= val))[0].tolist()
    if idx: vg.add(idx, val, 'REPLACE')
m = lo.modifiers.new("dec", 'DECIMATE'); m.ratio = BODY_TRIS / len(lo.data.polygons)
m.use_collapse_triangulate = True; m.vertex_group = "keep"; m.vertex_group_factor = 4.0; m.invert_vertex_group = True
activate(lo); bpy.ops.object.modifier_apply(modifier="dec")
lo.vertex_groups.remove(lo.vertex_groups["keep"])
bm = bmesh.new(); bm.from_mesh(lo.data)          # decimation leaves a few wire edges (they showed as lines
wire = [e for e in bm.edges if not e.link_faces]   # and dangling fins from the ears into the head): remove them
bmesh.ops.delete(bm, geom=wire, context='EDGES')
seen_f = {}
for f in bm.faces: seen_f.setdefault(frozenset(v.index for v in f.verts), []).append(f)
dups = [f for fs in seen_f.values() if len(fs) > 1 for f in fs]   # zero-volume needle pockets (ear tip -> inside head)
wire += dups; bmesh.ops.delete(bm, geom=dups, context='FACES_ONLY')
bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
for _ in range(5):
    fins = [f for f in bm.faces if sum(1 for e in f.edges if len(e.link_faces) == 1) >= 2]
    if not fins: break
    wire += fins; bmesh.ops.delete(bm, geom=fins, context='FACES_ONLY')
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
print("GOBLIN removed wire edges", len(wire)); bm.to_mesh(lo.data); bm.free()
for p in lo.data.polygons: p.use_smooth = True
lo.data.set_sharp_from_angle(angle=math.radians(38))   # faceted look, shared verts on soft areas

# ---------------------------------------------------------------- 3. UVs
activate(lo); bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, area_weight=0.0, scale_to_bounds=True)
bpy.ops.object.mode_set(mode='OBJECT')
uv = lo.data.uv_layers.active.data
arr = np.zeros(len(uv) * 2); uv.foreach_get("uv", arr); uv.foreach_set("uv", arr * STRIP)

# ---------------------------------------------------------------- 4. armature + weights
arm_data = bpy.data.armatures.new("goblin_rig"); rig = bpy.data.objects.new("goblin_rig", arm_data)
scene.collection.objects.link(rig); activate(rig); bpy.ops.object.mode_set(mode='EDIT')
for name, (h, t, par) in J.items():
    eb = arm_data.edit_bones.new(name); eb.head = h; eb.tail = t
    if par: eb.parent = arm_data.edit_bones[par]; eb.use_connect = (Vector(arm_data.edit_bones[par].tail) - Vector(h)).length < 1e-4
    base = name.split(".")[0]
    eb.align_roll(Vector((0, 0, 1)) if base in Z_UP else Vector((0, -1, 0)))
    eb.use_deform = base not in ("root", "attach_weapon")
bpy.ops.object.mode_set(mode='OBJECT')
activate(lo, rig); bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

DEFORM = [b.name for b in arm_data.bones if b.use_deform]
gi = {n: (lo.vertex_groups.get(n) or lo.vertex_groups.new(name=n)).index for n in DEFORM}
nv = len(lo.data.vertices); W = np.zeros((nv, len(DEFORM)))
col = {n: i for i, n in enumerate(DEFORM)}
for v in lo.data.vertices:
    for g in v.groups:
        nm = lo.vertex_groups[g.group].name
        if nm in col: W[v.index, col[nm]] = g.weight
P = np.array([v.co[:] for v in lo.data.vertices])
for i in range(nv):
    x, y, z = P[i]; ax = abs(x); sd = "L" if x > 0 else "R"; od = "R" if sd == "L" else "L"
    if (z > 0.65 and ax > 0.30) or (z > 0.70 and ax > 0.285 and abs(y) < 0.075):   # ears (+ rings): head -> ear -> tip
        t = (ax - 0.285) / 0.29; W[i] = 0
        wh = 1 - smooth(0.0, 0.15, t); wt = smooth(0.42, 0.62, t)
        W[i, col["head"]] = wh; W[i, col[f"ear_tip.{sd}"]] = wt; W[i, col[f"ear.{sd}"]] = max(0.0, 1 - wh - wt)
        continue
    if z > 0.535 or (z > 0.48 and y < -0.11):   # skull + face: head and jaw only
        W[i] = 0
        wj = smooth(0.605, 0.572, z) * smooth(-0.03, -0.09, y) * smooth(0.27, 0.19, ax) if z < 0.61 else 0.0
        wn = smooth(0.56, 0.50, z) * smooth(-0.05, 0.02, y) * (1 - wj)
        W[i, col["jaw"]] = wj; W[i, col["neck"]] = wn; W[i, col["head"]] = 1 - wj - wn
        continue
    for b in DEFORM:                       # no cross-side bleed (legs touch, fists sit by the hips)
        if b.endswith("." + od) and ax > 0.03: W[i, col[b]] = 0
    hand = W[i, col[f"hand.{sd}"]] + W[i, col[f"forearm.{sd}"]] if ax > 0.03 else 0
    if hand > 0.5:
        for b in ("hips", "spine", f"thigh.{sd}"): W[i, col[b]] = 0
    if ax > 0.215 and z < 0.40:            # forearm/fist: arm bones only
        for b in DEFORM:
            if not any(k in b for k in ("arm", "hand")): W[i, col[b]] = 0
    for b in ("head", "jaw") + tuple(f"ear{x}.{s}" for x in ("", "_tip") for s in "LR"):
        W[i, col[b]] = 0                   # below the head: no head/ear bleed
# keep 4 strongest, normalise
order = np.argsort(-W, axis=1)
for i in range(nv): W[i, order[i, 4:]] = 0
W /= np.maximum(W.sum(1, keepdims=True), 1e-8)
for n in DEFORM: lo.vertex_groups[n].remove(list(range(nv)))
for n, c in col.items():
    g = lo.vertex_groups[n]
    for i in np.nonzero(W[:, c] > 1e-3)[0]: g.add([int(i)], float(W[i, c]), 'REPLACE')
for g in list(lo.vertex_groups):
    if g.name not in col: lo.vertex_groups.remove(g)
dominant = [DEFORM[k] for k in W.argmax(1)]

# ---------------------------------------------------------------- 5. region map (per face) -> bake
R = dict(skin=0, warm=1, inner_ear=2, iron=3, leather=4, strap=5, cloth=6, pants=7, boot=8, mouth=9, brass=10, gullet=11)
me = lo.data
reg = []
for p in me.polygons:
    c = p.center; n = p.normal; ax = abs(c.x)
    votes = {}
    for vi in p.vertices: votes[dominant[vi]] = votes.get(dominant[vi], 0) + 1
    b = max(votes, key=votes.get).split(".")[0]
    if b in ("head", "jaw", "ear", "ear_tip") or (b == "neck" and c.z > 0.5):
        if (ax > 0.30 and c.z > 0.65) or (ax > 0.285 and c.z > 0.7 and abs(c.y) < 0.075):
            r = "inner_ear" if (n.y < -0.35 and ax < 0.52 and c.y < -0.005) else "skin"
        elif ax < 0.215 and 0.535 < c.z < 0.675 and (c.y < -0.03 or (c.y < 0.10 and c.z > 0.565)):   # deep mouth too
            teeth = (0.615 < c.z < 0.668 or 0.540 < c.z < 0.582) and c.y < -0.15 and n.y < -0.45
            r = "mouth" if teeth else "gullet"
        elif n.y < -0.3 and 0.48 < c.z < 0.88 and ax < 0.26: r = "warm"
        else: r = "skin"
    elif b == "hand": r = "skin"
    elif b == "forearm": r = "leather"
    elif b == "upper_arm": r = "iron" if c.z > 0.385 else "skin"
    elif b in ("hips", "spine", "chest", "neck"):
        if c.z > 0.465: r = "strap"
        elif c.z >= 0.31: r = "iron"
        elif c.z >= 0.215: r = "brass" if (ax < 0.065 and c.y < -0.05) else "leather"
        else: r = "cloth" if ax < 0.14 else "pants"
    elif b == "thigh": r = "pants"
    elif b == "shin": r = "pants" if c.z > 0.095 else "boot"
    else: r = "boot"
    reg.append(R[r])
attr = me.color_attributes.new("region", 'FLOAT_COLOR', 'CORNER')
cols = np.zeros((len(me.loops), 4)); cols[:, 3] = 1
for p in me.polygons:
    for li in p.loop_indices: cols[li, 0] = (reg[p.index] + 0.5) / 16.0
attr.data.foreach_set("color", cols.ravel())

scene.render.engine = 'CYCLES'; scene.cycles.device = 'CPU'; scene.cycles.samples = 24
scene.render.bake.margin = 6
bake_mat = bpy.data.materials.new("bake"); bake_mat.use_nodes = True; lo.data.materials.append(bake_mat)
lo.data.materials.clear(); lo.data.materials.append(bake_mat)
nt = bake_mat.node_tree; nt.nodes.clear()
out = nt.nodes.new("ShaderNodeOutputMaterial"); emi = nt.nodes.new("ShaderNodeEmission"); img_node = nt.nodes.new("ShaderNodeTexImage")
nt.links.new(emi.outputs[0], out.inputs[0]); nt.nodes.active = img_node

def bake(kind, src_socket=None, selected=False):
    im = bpy.data.images.new("bk_" + kind, TEX_SIZE, TEX_SIZE, float_buffer=True); im.colorspace_settings.name = 'Non-Color'
    img_node.image = im
    if src_socket is not None:
        for l in list(emi.inputs[0].links): nt.links.remove(l)
        nt.links.new(src_socket, emi.inputs[0])
    if selected: activate(lo, hi)
    else: activate(lo)
    bake_type = {"region": 'EMIT', "pos": 'EMIT', "ao": 'AO', "nrm": 'NORMAL'}[kind]
    bpy.ops.object.bake(type=bake_type, use_selected_to_active=selected, cage_extrusion=0.012, max_ray_distance=0.04,
                        normal_space='OBJECT', margin=6)
    return np.array(im.pixels[:]).reshape(TEX_SIZE, TEX_SIZE, 4)

an = nt.nodes.new("ShaderNodeAttribute"); an.attribute_name = "region"; an.attribute_type = 'GEOMETRY'
geo = nt.nodes.new("ShaderNodeNewGeometry"); vm = nt.nodes.new("ShaderNodeVectorMath"); vm.operation = 'MULTIPLY_ADD'
vm.inputs[1].default_value = (0.5, 0.5, 0.5); vm.inputs[2].default_value = (0.5, 0.5, 0.5)
nt.links.new(geo.outputs["Position"], vm.inputs[0])
REG = bake("region", an.outputs["Color"])
POS = bake("pos", vm.outputs[0])
hi.data.materials.clear(); hi.data.materials.append(bake_mat)
AO = bake("ao", selected=True)
NRM = bake("nrm", selected=True)
hi.data.materials.clear()

# ---------------------------------------------------------------- 6. paint
def srgb(c): return np.array(c, dtype=float)
PAL = {R["skin"]: (0.44, 0.56, 0.25), R["warm"]: (0.60, 0.64, 0.32), R["inner_ear"]: (0.72, 0.50, 0.40),
       R["iron"]: (0.55, 0.52, 0.48), R["leather"]: (0.50, 0.33, 0.19), R["strap"]: (0.36, 0.24, 0.15),
       R["cloth"]: (0.66, 0.30, 0.22), R["pants"]: (0.42, 0.37, 0.30), R["boot"]: (0.38, 0.26, 0.17),
       R["mouth"]: (0.88, 0.80, 0.55), R["brass"]: (0.78, 0.62, 0.30), R["gullet"]: (0.36, 0.11, 0.10)}
rid = np.clip((REG[..., 0] * 16).astype(int), 0, 15)
pos = POS[..., :3] * 2 - 1
nrm = NRM[..., :3] * 2 - 1
nrm /= np.maximum(np.linalg.norm(nrm, axis=2, keepdims=True), 1e-6)
ao = np.clip(AO[..., 0], 0, 1)
X, Y, Z = pos[..., 0], pos[..., 1], pos[..., 2]
base = np.zeros((TEX_SIZE, TEX_SIZE, 3))
for k, c in PAL.items(): base[rid == k] = c
def nz(a, b, c, f):   # cheap brush-streak noise from object position
    return (np.sin(X * a * f + Z * 1.7 * f) * np.sin(Y * b * f - Z * c * f) + 0.5 * np.sin(Z * c * 2.1 * f + X * b * f)) / 1.5
streak = nz(31, 23, 47, 1.0); blot = nz(13, 11, 9, 1.0)
iron = rid == R["iron"]
rust = np.clip((blot - 0.15) * 3, 0, 1)[..., None] * 0.75
base = np.where(iron[..., None], base * (1 - rust) + srgb((0.60, 0.36, 0.20)) * rust, base)
skin = np.isin(rid, [R["skin"], R["warm"]])
base = np.where(skin[..., None], base * (1 + 0.07 * blot[..., None]), base)
# mouth: deep cavity dark red, the rest (teeth) yellowed
mouth = rid == R["mouth"]
cav = (ao < 0.62)[..., None]
base = np.where((mouth[..., None]) & cav, srgb((0.32, 0.10, 0.09)), base)
gul = rid == R["gullet"]
base[gul & (ao > 0.80) & (Y < -0.215)] = PAL[R["warm"]]   # outer lip rim stays skin, the inside stays dark
# eyes: dark sockets + small bright eyes (read from above)
front = (nrm[..., 1] < -0.2) & (Y < -0.10)
for ex in (0.135, -0.135):
    sx = np.sign(ex); dx = X - ex; dz = Z - 0.79 - 0.22 * dx * sx   # slanted: inner corner low = scowl
    dd = np.sqrt((dx / 0.068) ** 2 + (dz / 0.040) ** 2)
    base[front & (dd < 1.15)] = base[front & (dd < 1.15)] * 0.35 + srgb((0.13, 0.11, 0.08)) * 0.65
    base[front & (dd < 1.0)] = (0.11, 0.09, 0.07)
    de = np.sqrt((X - ex * 0.9) ** 2 + (Z - 0.784) ** 2)
    base[front & (de < 0.019)] = (1.0, 0.84, 0.22)
    base[front & (de < 0.007)] = (1.0, 0.98, 0.75)
L = np.array([0.3, -0.5, 0.8]); L /= np.linalg.norm(L)
light = 0.80 + 0.22 * np.clip((nrm * L).sum(2), 0, 1)
shade = light * (0.45 + 0.55 * ao ** 0.9) * (1 + 0.05 * streak)
edge = np.clip((ao - 0.93) * 8, 0, 1) * iron
col_out = np.clip(base * shade[..., None] + edge[..., None] * 0.10, 0, 1)
# dagger swatch strip (top 1/16): blade, dark iron, wrap light, wrap dark
v0 = int(TEX_SIZE * STRIP); u = np.arange(TEX_SIZE) / TEX_SIZE
yy, xx = np.mgrid[v0:TEX_SIZE, 0:TEX_SIZE]
sw = (xx * 8 // TEX_SIZE).astype(int)
SW = {0: (0.70, 0.70, 0.66), 1: (0.40, 0.33, 0.28), 2: (0.62, 0.50, 0.34), 3: (0.40, 0.28, 0.18)}
strip = np.zeros(yy.shape + (3,))
for k, c in SW.items(): strip[sw == k] = c
r = np.sin(xx * 0.9) * np.sin(yy * 1.7) + np.sin(xx * 0.31 + yy * 0.53)
rustm = (np.clip(r - 0.6, 0, 1) * 0.9)[..., None]
strip = np.where((sw <= 1)[..., None], strip * (1 - rustm) + srgb((0.55, 0.32, 0.18)) * rustm, strip)
col_out[v0:] = strip * (0.92 + 0.08 * np.sin(xx * 0.7))[..., None]
os.makedirs(os.path.dirname(TEX), exist_ok=True)
tex = bpy.data.images.new("goblin_albedo", TEX_SIZE, TEX_SIZE, alpha=False)
px = np.ones((TEX_SIZE, TEX_SIZE, 4), dtype=np.float32); px[..., :3] = col_out   # byte image: pixels are sRGB values
tex.pixels.foreach_set(px.ravel()); tex.filepath_raw = TEX; tex.file_format = 'PNG'; tex.save()
tex.filepath_raw = TEX; tex.reload()

mat = bpy.data.materials.new("goblin"); mat.use_nodes = True
bs = mat.node_tree.nodes["Principled BSDF"]; bs.inputs["Roughness"].default_value = 0.9
ti = mat.node_tree.nodes.new("ShaderNodeTexImage"); ti.image = tex
mat.node_tree.links.new(ti.outputs["Color"], bs.inputs["Base Color"])
lo.data.materials.clear(); lo.data.materials.append(mat)
me.color_attributes.remove(me.color_attributes["region"])
bpy.data.objects.remove(hi, do_unlink=True)

# ---------------------------------------------------------------- 7. twin daggers
def dagger(sd, sx, variant):
    F = Vector(J[f"attach_weapon.{sd}"][0]); bm = bmesh.new(); uvq = []   # (face, swatch)
    th = math.radians(60) * sx   # blade flat tilted outward so it reads from the top-down camera
    def RV(x, y, z): return bm.verts.new(F + Vector((x * math.cos(th) + z * math.sin(th), y, -x * math.sin(th) + z * math.cos(th))))
    def ring(yv, r, nside=5, rot=0.0):
        return [bm.verts.new(F + Vector((r * math.cos(rot + 2 * math.pi * k / nside), yv, r * math.sin(rot + 2 * math.pi * k / nside)))) for k in range(nside)]
    def bridge(a, b, sw):
        for k in range(len(a)):
            f = bm.faces.new((a[k], a[(k + 1) % len(a)], b[(k + 1) % len(b)], b[k])); uvq.append((f, sw))
    # wrapped grip with pommel knob
    ys = [0.11, 0.09, 0.07, 0.05, 0.03, 0.01, -0.01, -0.03, -0.05, -0.07, -0.09]
    rings = [ring(y, 0.0135 if i % 2 else 0.0165) for i, y in enumerate(ys)]
    for i in range(len(rings) - 1): bridge(rings[i], rings[i + 1], 2 if i % 2 else 3)
    pom = ring(0.125, 0.021, 5, 0.3); bridge(pom, rings[0], 1)
    cap = bm.verts.new(F + Vector((0, 0.145, 0)))
    for k in range(5): uvq.append((bm.faces.new((pom[(k + 1) % 5], pom[k], cap)), 1))
    endc = bm.faces.new(list(reversed(rings[-1]))); uvq.append((endc, 1))
    # crude crossguard (lumpy box)
    g0, g1 = -0.088, -0.104
    gz = (0.046, -0.038) if variant else (0.040, -0.045)
    box = [RV(dx, y, z) for y in (g0, g1) for z in gz for dx in (-0.012, 0.012)]
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        uvq.append((bm.faces.new([box[i] for i in q]), 1))
    # jagged blade: outline at x=0, inset ridge plates at x=+-t
    L0, Lb = 0.104, 0.15
    top = [(0, 0.019), (0.03, 0.022), (0.04, 0.012), (0.055, 0.021), (0.075, 0.018), (0.085, 0.008), (0.105, 0.014), (0.125, 0.008)]
    if variant: top = [(s, z * (1.08 if i % 2 else 0.95)) for i, (s, z) in enumerate(top)]
    bot = [(0.135, -0.004), (0.11, -0.012), (0.075, -0.017), (0.04, -0.019), (0, -0.017)]
    outline = top + [(Lb, 0.002)] + bot
    t = 0.0055
    O = [RV(0, -(L0 + s), z * 1.3) for s, z in outline]
    sides = []
    for sgn in (1, -1):
        I = [RV(sgn * t * (1 - s / Lb * 0.8), -(L0 + s), z * 0.6) for s, z in outline]
        sides.append(I)
        n = len(O)
        for k in range(n):
            a, b = k, (k + 1) % n
            q = (O[a], O[b], I[b], I[a]) if sgn > 0 else (O[b], O[a], I[a], I[b])
            uvq.append((bm.faces.new(q), 0))
        f = bm.faces.new(I if sgn < 0 else list(reversed(I))); uvq.append((f, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uvl = bm.loops.layers.uv.new("UVMap")
    for f, swi in uvq:
        for lp in f.loops:
            p = lp.vert.co - F
            uu = (swi + 0.1 + 0.8 * min(1, max(0, (-p.y + 0.19) / 0.44))) / 8
            vv = STRIP + (1 - STRIP) * (0.15 + 0.7 * min(1, max(0, (p.z + 0.025) / 0.05)))
            lp[uvl].uv = (uu, vv)
    res = bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(f"dagger.{sd}"); bm.to_mesh(mesh); bm.free()
    for p in mesh.polygons: p.use_smooth = False
    mesh.materials.append(mat)
    ob = bpy.data.objects.new(f"dagger.{sd}", mesh); scene.collection.objects.link(ob)
    mw = ob.matrix_world.copy()
    ob.parent = rig; ob.parent_type = 'BONE'; ob.parent_bone = f"attach_weapon.{sd}"
    bpy.context.view_layer.update(); ob.matrix_world = mw
    return ob
daggers = [dagger("L", 1, False), dagger("R", -1, True)]
if STAGE == "prehunch":
    os.makedirs(CACHE_DIR, exist_ok=True)
    np.savez_compressed(os.path.join(CACHE_DIR, "goblin_bake.npz"), region=REG.astype(np.float32),
                        pos=POS.astype(np.float32), nrm=NRM.astype(np.float32), ao=AO.astype(np.float32))
    tex.pack(); bpy.ops.wm.save_as_mainfile(filepath=os.path.join(CACHE_DIR, "goblin_prehunch.blend"))
    print("GOBLIN prehunch cache saved"); sys.exit(0)

# ---------------------------------------------------------------- 8. bake a hunched rest pose
HUNCH = {"spine": (10, 0, 0), "chest": (12, 0, 0), "neck": (-6, 0, 0), "head": (-16, 0, 0),
         "upper_arm.L": (12, 0, 0), "upper_arm.R": (12, 0, 0), "forearm.L": (18, 0, 0), "forearm.R": (18, 0, 0),
         "ear.L": (8, 0, 0), "ear.R": (8, 0, 0)}
def pose(rot):
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'; pb.location = (0, 0, 0)
        pb.rotation_euler = Euler([math.radians(a) for a in rot.get(pb.name, (0, 0, 0))])
    bpy.context.view_layer.update()
pose(HUNCH)
activate(lo); bpy.ops.object.modifier_apply(modifier=lo.modifiers[0].name)
dag_world = [o.matrix_world.copy() for o in daggers]
activate(rig); bpy.ops.object.mode_set(mode='POSE'); bpy.ops.pose.select_all(action='SELECT')
bpy.ops.pose.armature_apply(selected=False); bpy.ops.object.mode_set(mode='OBJECT')
bpy.context.view_layer.update()
for o, mw in zip(daggers, dag_world): o.matrix_world = mw
mod = lo.modifiers.new("Armature", 'ARMATURE'); mod.object = rig
# feet stay at z=0 (legs not in the hunch); report height
zs = [(lo.matrix_world @ v.co).z for v in lo.data.vertices]
print("GOBLIN height after hunch %.3f" % max(zs))

# ---------------------------------------------------------------- 9. deformation test action
TEST = [
    ("rest", {}),
    ("crouch", {"hips": (-10, 0, 0), "spine": (18, 0, 0), "chest": (15, 0, 0), "neck": (-12, 0, 0), "head": (-18, 0, 0),
                "thigh.L": (70, 0, -8), "thigh.R": (70, 0, 8), "shin.L": (-95, 0, 0), "shin.R": (-95, 0, 0),
                "foot.L": (35, 0, 0), "foot.R": (35, 0, 0)}),
    ("arms_up", {"upper_arm.L": (95, 0, 0), "upper_arm.R": (20, 0, 85), "forearm.L": (40, 0, 0), "forearm.R": (20, 0, 0)}),
    ("head_turn", {"neck": (0, 20, 0), "head": (-10, 45, 12), "jaw": (-22, 0, 0)}),
    ("ears_bent", {"ear.L": (-30, 0, 25), "ear_tip.L": (-45, 0, 0), "ear.R": (35, 0, -20), "ear_tip.R": (40, 0, 0)}),
    ("wrist_twist", {"forearm.L": (40, 35, 0), "hand.L": (20, 60, 0), "forearm.R": (60, -35, 0), "hand.R": (-30, -60, 0)}),
]
act = bpy.data.actions.new("deform_test"); rig.animation_data_create(); rig.animation_data.action = act
for i, (nm, rot) in enumerate(TEST):
    pose(rot)
    for pb in rig.pose.bones:
        pb.keyframe_insert("rotation_euler", frame=1 + i * 10); pb.keyframe_insert("location", frame=1 + i * 10)
for fc in getattr(act, "fcurves", []):
    for kp in fc.keyframe_points: kp.interpolation = 'CONSTANT'
scene.frame_start, scene.frame_end = 1, 1 + (len(TEST) - 1) * 10
scene["deform_test_poses"] = ",".join(n for n, _ in TEST)
pose({}); scene.frame_set(1)

# ---------------------------------------------------------------- 10. save + export
nb = sum(len(p.vertices) - 2 for p in lo.data.polygons)
print("GOBLIN tris body", nb, "daggers", [len(o.data.polygons) for o in daggers], "bones", len(arm_data.bones))
print("GOBLIN bones", ",".join(b.name for b in arm_data.bones))
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True); os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
tex.pack()
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
for o in bpy.data.objects: o.select_set(o in (lo, rig, *daggers))
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=True, export_animations=True,
                          export_animation_mode='ACTIONS', export_skins=True, export_def_bones=False,
                          export_image_format='JPEG', export_jpeg_quality=88, export_apply=False)
print("GOBLIN done", os.path.getsize(OUT_GLB), os.path.getsize(TEX))

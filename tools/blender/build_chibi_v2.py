"""Build chibi_v2 - a new player base character on the EXISTING chibi skeleton.

    blender -b --factory-startup --python tools/blender/build_chibi_v2.py -- \
        <src chibi_base_animated.glb> <out chibi_v2.glb>

Reuses the GameRig armature from the source GLB EXACTLY (same 57 bone names, hierarchy,
rest heads/tails/rolls) and skins brand-new, smoother, more anime-styled meshes to it:
round head, big glossy eyes (iris as its own material so the Look system can recolour it),
chunky side-swept bob with pointed locks + a thin headband, a smooth narrow-shouldered body
with small readable hands and soft boot-shaped feet.

Mesh / material / node names match the contract client/character_model.gd + body_fit.gd rely on:
  meshes:  Body continuous, Hands articulated, Face, Nose, Brow.L/.R, Eye inset.L/.R,
           Eyelid.L/.R, Mouth, Base foot.L/.R, plus the bob hair pieces tagged
           extras studio_hair_style=original.
  materials: 'Neutral clay' (skin, prefix-matched for tinting), 'Eye inset clay' (eye white
           + mouth), 'Hair clay' (hair, salmon default), 'Iris clay' (recolourable iris),
           'Headband clay' (dark band).  'Short hair clay.002' kept for the alt boy hairs IF reused.
The clips live in art/animations/*.glb (loaded by name), so no animations are embedded here;
only the mesh + the identical rest skeleton are exported.

Rig space is Z-up: +Z up, +X the character's left, FRONT = -Y (face, eyes, nose, toes point -Y).
"""
import bpy, bmesh, sys, math, json
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]

# ----------------------------------------------------------------------------- palette
SKIN = (0.945, 0.804, 0.690, 1.0)      # warm doll skin (code recolours via "Neutral clay")
EYE_WHITE = (0.97, 0.96, 0.96, 1.0)
IRIS = (0.78, 0.17, 0.33, 1.0)         # dark pink / ruby, recolourable (its own material)
LASH = (0.12, 0.09, 0.11, 1.0)         # dark upper lash line (Eyelid + Mouth share "Eye inset clay"? no: lash own)
MOUTH = (0.74, 0.33, 0.38, 1.0)
HAIR = (0.95, 0.60, 0.52, 1.0)         # salmon pink default
HEADBAND = (0.17, 0.14, 0.17, 1.0)
BLUSH = (0.97, 0.66, 0.60, 1.0)


def mat(name, rgba, rough=0.62, spec=0.3):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = rgba
    b.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = spec
    return m


# ----------------------------------------------------------------------------- mesh helpers
def obj_from_bm(bm, name, material, extras=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if material:
        me.materials.append(material)
    if extras:
        for k, v in extras.items():
            ob[k] = v
    return ob


def ring(bm, center, rx, ry, segs, z, front_bias=0.0, verts=None):
    """A ring of `segs` verts in the XY plane at height z (ellipse rx*ry), front(-Y) pushed by front_bias."""
    vs = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        x = center[0] + rx * math.cos(a)
        y = center[1] + ry * math.sin(a)
        if y < center[1]:
            y -= front_bias * (abs(math.sin(a)))
        vs.append(bm.verts.new((x, y, z)))
    if verts is not None:
        verts.append(vs)
    return vs


def bridge(bm, a, b):
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))


def cap(bm, loop, top=True):
    f = bm.faces.new(loop if top else list(reversed(loop)))
    return f


def loft(bm, rings):
    for i in range(len(rings) - 1):
        bridge(bm, rings[i], rings[i + 1])


def smooth_shade(ob):
    for p in ob.data.polygons:
        p.use_smooth = True


def mirror_x(ob, name_r):
    """Duplicate ob mirrored across X (character left->right) into a new object name_r."""
    me = ob.data.copy()
    r = bpy.data.objects.new(name_r, me)
    bpy.context.collection.objects.link(r)
    for v in r.data.vertices:
        v.co.x = -v.co.x
    for p in r.data.polygons:
        p.flip()
    r.data.update()
    for k in ob.keys():
        if k not in ("_RNA_UI",):
            r[k] = ob[k]
    return r


# ----------------------------------------------------------------------------- BODY
def build_body(skin):
    """Torso + neck + both legs + both arms as ONE smooth lofted mesh ('Body continuous').
    Cross-sections kept at or just inside the old silhouette so outfits never poke through.
    Rig space: Z up, X side, -Y front. Rest is a T-pose (arms out along +/-X at Z~1.064)."""
    bm = bmesh.new()
    SEG = 12

    # --- torso: hips(0.72) -> waist -> chest -> shoulders(1.05) -> neck base(1.11)
    # (half-widths slightly under the profile: hips X.11/Y.09, waist X.09/Y.06, chest X.13/Y.08)
    torso = [
        # z,     rx,    ry,   front_bias (belly/chest push to -Y)
        (0.700, 0.095, 0.078, 0.010),   # hip base
        (0.760, 0.100, 0.082, 0.015),   # full hips
        (0.820, 0.082, 0.058, 0.010),   # slim waist
        (0.880, 0.088, 0.062, 0.014),   # lower chest
        (0.955, 0.108, 0.072, 0.018),   # chest
        (1.015, 0.112, 0.066, 0.012),   # upper chest
        (1.070, 0.090, 0.058, 0.006),   # shoulder yoke (narrow shoulders)
        (1.110, 0.050, 0.045, 0.0),     # neck base
        (1.160, 0.040, 0.040, 0.0),     # neck (into head)
    ]
    trings = []
    for z, rx, ry, fb in torso:
        trings.append(ring(bm, (0, 0, 0), rx, ry, SEG, z, front_bias=fb))
    loft(bm, trings)
    cap(bm, trings[-1], top=True)   # neck top (head covers it)

    # --- legs: from hip sockets (x=+-0.078) down to ankle; feet are a separate mesh.
    for side in (1, -1):
        hipx = 0.078 * side
        leg = [
            (0.715, 0.062, 0.062),  # hip socket
            (0.600, 0.058, 0.058),  # thigh
            (0.470, 0.050, 0.050),  # above knee
            (0.425, 0.046, 0.046),  # knee
            (0.300, 0.040, 0.044),  # calf
            (0.175, 0.034, 0.038),  # ankle
            (0.150, 0.033, 0.040),  # ankle base (foot mesh continues)
        ]
        rings = []
        for z, rx, ry in leg:
            rings.append(ring(bm, (hipx, 0, 0), rx, ry, SEG, z))
        loft(bm, rings)
        cap(bm, rings[-1], top=False)  # ankle bottom (foot mesh overlaps)
        # weld hip ring into torso bottom: just cap the socket top so it reads solid
        cap(bm, rings[0], top=True)

    # --- arms: T-pose, out along X from shoulder(x=+-0.11) to wrist(x=+-0.47). Small taper.
    for side in (1, -1):
        base = 0.108 * side
        # arm rings are circles in the Y/Z plane, marching along X
        armpts = [
            (0.110, 0.052),  # shoulder
            (0.165, 0.046),  # upper arm
            (0.250, 0.040),  # elbow
            (0.300, 0.036),  # forearm
            (0.400, 0.032),  # low forearm
            (0.470, 0.030),  # wrist (hands mesh continues)
        ]
        rings = []
        for x, r in armpts:
            vs = []
            cx = x * side
            for i in range(SEG):
                a = 2 * math.pi * i / SEG
                y = r * math.cos(a)
                z = 1.064 + r * math.sin(a)
                vs.append(bm.verts.new((cx, y, z)))
            rings.append(vs)
        loft(bm, rings)
        cap(bm, rings[0], top=(side > 0))   # shoulder cap (reads into torso)
        cap(bm, rings[-1], top=(side < 0))  # wrist cap (hands overlap)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, "Body continuous", skin,
                     extras={"v2": "chibi_v2 base body", "neck_fit_revision": "short_neck_v6"})
    smooth_shade(ob)
    return ob


# ----------------------------------------------------------------------------- FEET (soft boot-ish)
def build_foot(skin, side):
    """A soft rounded foot/ankle, slightly bigger than a blob but boot-shaped. -Y is forward."""
    bm = bmesh.new()
    SEG = 10
    cx = 0.083 * side
    # ankle (top) down to a rounded sole, extruded forward (-Y) into a toe box
    # rings: (z, cy, rx, ry) centre y offset moves forward as we go down
    sections = [
        (0.188, -0.010, 0.038, 0.044),  # ankle top
        (0.140, -0.015, 0.044, 0.055),  # instep
        (0.090, -0.040, 0.050, 0.080),  # mid foot forward
        (0.045, -0.075, 0.052, 0.105),  # toe box
        (0.015, -0.090, 0.046, 0.100),  # sole front
    ]
    rings = []
    for z, cy, rx, ry in sections:
        vs = []
        for i in range(SEG):
            a = 2 * math.pi * i / SEG
            x = cx + rx * math.cos(a)
            y = cy + ry * math.sin(a)
            # flatten the sole: clamp bottom
            zz = z
            if math.sin(a) > 0:  # back half, keep
                pass
            vs.append(bm.verts.new((x, y, max(0.012, zz))))
        rings.append(vs)
    loft(bm, rings)
    cap(bm, rings[0], top=True)
    cap(bm, rings[-1], top=False)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    name = "Base foot.L" if side > 0 else "Base foot.R"
    ob = obj_from_bm(bm, name, skin)
    smooth_shade(ob)
    return ob


# ----------------------------------------------------------------------------- HANDS
def build_hands(skin):
    """Both hands as one mesh 'Hands articulated'. A clean, simple mitt: a smooth tapered capsule
    from the wrist to a rounded end (near-ROUND cross-sections so the ink outline is one convex
    silhouette, never a tangle), with a soft thumb bump welded onto the thumb side. No thin flat
    finger slivers (those broke the outline in round 1). Skinned by the finger bones via auto
    weights reaching across the mitt."""
    bm = bmesh.new()
    SEG = 10
    for side in (1, -1):
        # capsule cross-sections: round, gently widening at the palm then tapering to a dome.
        sections = [
            # x,     r,     cz,     yc
            (0.470, 0.030, 1.064, 0.000),  # wrist
            (0.512, 0.036, 1.063, -0.002),  # palm
            (0.560, 0.038, 1.062, -0.004),  # knuckles (widest, slight droop forward)
            (0.610, 0.034, 1.060, -0.006),  # fingers
            (0.648, 0.026, 1.058, -0.008),  # taper
            (0.672, 0.014, 1.057, -0.010),  # rounded end
        ]
        rings = []
        for x, r, cz, yc in sections:
            vs = []
            cx = x * side
            for i in range(SEG):
                a = 2 * math.pi * i / SEG
                # slightly flatten top-to-bottom (0.85) so it reads as a hand not a sausage, but stay convex
                y = yc + r * math.cos(a)
                z = cz + r * 0.85 * math.sin(a)
                vs.append(bm.verts.new((cx, y, z)))
            rings.append(vs)
        loft(bm, rings)
        cap(bm, rings[0], top=(side > 0))
        cap(bm, rings[-1], top=(side < 0))
        # soft thumb: a small rounded bump on the thumb side (forward, -Y), merged by remove_doubles
        tcx = 0.520 * side
        trings = []
        for x, r, yc, zc in [(0.508, 0.014, -0.022, 1.056),
                             (0.520, 0.013, -0.034, 1.050),
                             (0.528, 0.008, -0.040, 1.046)]:
            vs = []
            cx = x * side
            for i in range(8):
                a = 2 * math.pi * i / 8
                y = yc + r * math.cos(a)
                z = zc + r * 0.9 * math.sin(a)
                vs.append(bm.verts.new((cx, y, z)))
            trings.append(vs)
        loft(bm, trings)
        cap(bm, trings[0], top=(side > 0))
        cap(bm, trings[-1], top=(side < 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    ob = obj_from_bm(bm, "Hands articulated", skin)
    smooth_shade(ob)
    return ob


# ----------------------------------------------------------------------------- HEAD
HEAD_C = Vector((0.0, 0.0, 1.33))   # head centre (rig space)
HEAD_R = Vector((0.165, 0.150, 0.185))  # round skull radii (x side, y depth, z up)


def build_face(skin):
    """A soft ROUND skull with full cheeks and a slightly pointed small chin. One smooth mesh 'Face'
    (the body's own head; a replacement-head item can hide it). -Y is the front."""
    bm = bmesh.new()
    SEG = 16
    RINGS = 12
    cx, cy, cz = HEAD_C
    rx, ry, rz = HEAD_R
    rings = []
    for ri in range(RINGS + 1):
        t = ri / RINGS            # 0 top -> 1 bottom
        phi = math.pi * t          # 0..pi
        z = cz + rz * math.cos(phi)
        rr = math.sin(phi)
        vs = []
        for i in range(SEG):
            a = 2 * math.pi * i / SEG
            # chin taper: lower front narrows & points
            lower = max(0.0, (t - 0.62) / 0.38)
            xr = rx * rr * (1.0 - 0.30 * lower)
            yr = ry * rr * (1.0 - 0.18 * lower)
            x = cx + xr * math.cos(a)
            y = cy + yr * math.sin(a)
            # full cheeks: push mid-front sides out a touch
            cheek = math.sin(phi) * max(0.0, math.cos(a))  # not used strongly
            # pointed chin: pull the very front-bottom vertex forward & in
            if lower > 0.0 and math.sin(a) < -0.3:
                y -= 0.018 * lower
            vs.append(bm.verts.new((x, y, z)))
        rings.append(vs)
    # weld poles
    top = bm.verts.new((cx, cy, cz + rz))
    bot = bm.verts.new((cx, cy - 0.010, cz - rz))  # chin tip nudged forward
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((top, rings[0][j], rings[0][i]))
    for i in range(1, RINGS):
        bridge(bm, rings[i - 1], rings[i])
    # last ring to bottom pole
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((bot, rings[RINGS - 1][i], rings[RINGS - 1][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, "Face", skin,
                     extras={"v2": "chibi_v2 round head", "jaw_shape": "soft_pointed_chin_v2"})
    smooth_shade(ob)
    return ob


def _on_head(a_az, a_el, out=0.0):
    """A point on the head surface at azimuth a_az (around, 0=-Y front) and elevation a_el, pushed out."""
    cx, cy, cz = HEAD_C
    rx, ry, rz = HEAD_R
    y = -math.cos(a_az) * math.cos(a_el)
    x = math.sin(a_az) * math.cos(a_el)
    z = math.sin(a_el)
    return Vector((cx + (rx + out) * x, cy + (ry + out) * y, cz + (rz + out) * z))


def build_nose(skin):
    """A tiny hint of a nose on the front of the face."""
    bm = bmesh.new()
    base = Vector((0.0, HEAD_C.y - HEAD_R.y - 0.002, HEAD_C.z - 0.015))
    tip = base + Vector((0.0, -0.016, -0.004))
    w = 0.012
    v0 = bm.verts.new((base.x - w, base.y, base.z + 0.012))
    v1 = bm.verts.new((base.x + w, base.y, base.z + 0.012))
    v2 = bm.verts.new((base.x, base.y, base.z - 0.016))
    vt = bm.verts.new((tip.x, tip.y, tip.z))
    bm.faces.new((v0, v1, vt))
    bm.faces.new((v1, v2, vt))
    bm.faces.new((v2, v0, vt))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, "Nose", skin)
    smooth_shade(ob)
    return ob


# Eye placement: low-middle of the face, wide apart. azimuth +/- for left/right, slight downward elev.
EYE_AZ = 0.42        # radians from front toward the side (wide apart but still clearly frontal)
EYE_EL = -0.28       # low-middle of the face
EYE_RX = 0.056       # eye half-width (big)
EYE_RZ = 0.050       # eye half-height


def _eye_frame(side):
    """Returns (centre, right, up, normal) for the eye plane tangent to the head front, `side`=+1 left."""
    c = _on_head(EYE_AZ * side, EYE_EL, out=0.004)
    n = (c - Vector((HEAD_C.x, HEAD_C.y, HEAD_C.z))).normalized()
    up = Vector((0, 0, 1))
    right = up.cross(n).normalized() * side
    up2 = n.cross(right).normalized()
    return c, right, up2, n


def build_eye(side):
    """A big glossy anime eye: iris disc (own 'Iris clay' material, recolourable) on a white sclera,
    a big white highlight + a small secondary highlight, slightly domed off the face."""
    name = "Eye inset.L" if side > 0 else "Eye inset.R"
    bm = bmesh.new()
    c, right, up, n = _eye_frame(side)
    # sclera: a filled ellipse (fan) slightly domed
    SEG = 16
    centre = bm.verts.new(c + n * 0.004)
    rim = []
    for i in range(SEG):
        a = 2 * math.pi * i / SEG
        p = c + right * (EYE_RX * math.cos(a)) + up * (EYE_RZ * math.sin(a))
        rim.append(bm.verts.new(p))
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((centre, rim[i], rim[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, name, mat("Eye inset clay", EYE_WHITE, rough=0.25, spec=0.6))

    # iris: a smaller domed disc, OWN material 'Iris clay'
    bm2 = bmesh.new()
    ic = c + n * 0.010 - up * 0.004
    irx, irz = 0.040, 0.044
    cen = bm2.verts.new(ic + n * 0.006)
    irim = []
    for i in range(SEG):
        a = 2 * math.pi * i / SEG
        p = ic + right * (irx * math.cos(a)) + up * (irz * math.sin(a)) + n * 0.004
        irim.append(bm2.verts.new(p))
    for i in range(SEG):
        j = (i + 1) % SEG
        bm2.faces.new((cen, irim[i], irim[j]))
    bmesh.ops.recalc_face_normals(bm2, faces=bm2.faces)
    iris = obj_from_bm(bm2, name + "_iris", mat("Iris clay", IRIS, rough=0.18, spec=0.8))

    # highlights (small white discs) merged into the iris object's material-2
    hl_mat = mat("Eye highlight clay", (1, 1, 1, 1), rough=0.05, spec=1.0)
    iris.data.materials.append(hl_mat)
    bm3 = bmesh.new()
    for (hx, hz, hr) in [(0.016 * side, 0.020, 0.016), (-0.012 * side, -0.014, 0.007)]:
        hc = ic + right * hx + up * hz + n * 0.012
        cc = bm3.verts.new(hc + n * 0.004)
        hrim = []
        for i in range(10):
            a = 2 * math.pi * i / 10
            p = hc + right * (hr * math.cos(a)) + up * (hr * math.sin(a))
            hrim.append(bm3.verts.new(p))
        for i in range(10):
            j = (i + 1) % 10
            bm3.faces.new((cc, hrim[i], hrim[j]))
    bmesh.ops.recalc_face_normals(bm3, faces=bm3.faces)
    tmp = obj_from_bm(bm3, name + "_hl", hl_mat)
    # join iris + highlights into the iris object, then join iris into the eye object (multi-material)
    join_into(iris, [tmp])
    join_into(ob, [iris])
    smooth_shade(ob)
    return ob


def build_eyelid(side):
    """A dark upper lash line arc over the eye, thicker at the OUTER corner. Mesh 'Eyelid.L/.R'."""
    name = "Eyelid.L" if side > 0 else "Eyelid.R"
    bm = bmesh.new()
    c, right, up, n = _eye_frame(side)
    SEG = 10
    inner, outer = [], []
    for i in range(SEG + 1):
        t = i / SEG                      # 0 inner -> 1 outer
        a = math.pi * (0.95 - 0.9 * t)   # arc across the top of the eye
        thick = 0.006 + 0.012 * t        # thicker at outer corner
        ex = EYE_RX * 1.02 * math.cos(a) * (1 if side > 0 else 1)
        ez = EYE_RZ * 1.02 * math.sin(a)
        base = c + right * ex + up * ez + n * 0.012
        innerp = base
        outerp = base + up * thick + n * 0.001
        inner.append(bm.verts.new(innerp))
        outer.append(bm.verts.new(outerp))
    for i in range(SEG):
        bm.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, name, mat("Lash clay", LASH, rough=0.4, spec=0.2))
    smooth_shade(ob)
    return ob


def build_brow(side):
    """A short soft brow above the eye (coloured like the hair by code: material 'Neutral clay')."""
    name = "Brow.L" if side > 0 else "Brow.R"
    bm = bmesh.new()
    c, right, up, n = _eye_frame(side)
    base = c + up * (EYE_RZ * 1.5) + n * 0.010
    verts = []
    row2 = []
    for i in range(4):
        t = i / 3.0
        p = base + right * ((t - 0.5) * 0.070) + up * (0.004 * math.sin(math.pi * t))
        verts.append(bm.verts.new(p + n * 0.002))
        row2.append(bm.verts.new(p - up * 0.010 + n * 0.002))
    for i in range(3):
        bm.faces.new((verts[i], verts[i + 1], row2[i + 1], row2[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, name, mat("Neutral clay", SKIN))  # recoloured to hair by code
    smooth_shade(ob)
    return ob


def build_mouth(skin):
    """A small simple mouth low on the face. Shares 'Eye inset clay'? No - own soft rose via Mouth clay,
    but code hides it with the face item; material name 'Eye inset clay' kept per contract? Mouth used
    'Eye inset clay' in v1. Keep that slot so nothing in code is surprised, tinted rose."""
    bm = bmesh.new()
    cz = HEAD_C.z - 0.095
    cy = HEAD_C.y - HEAD_R.y - 0.004
    w, h = 0.030, 0.010
    rim = []
    SEG = 10
    for i in range(SEG):
        a = 2 * math.pi * i / SEG
        rim.append(bm.verts.new((w * math.cos(a), cy - 0.002 * abs(math.sin(a)), cz + h * math.sin(a) * 0.6)))
    cen = bm.verts.new((0, cy, cz))
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((cen, rim[i], rim[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = obj_from_bm(bm, "Mouth", mat("Eye inset clay", MOUTH, rough=0.4))
    smooth_shade(ob)
    return ob


def join_into(target, others):
    """Join `others` into `target` (object mode), preserving materials."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in others:
        o.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()


# ----------------------------------------------------------------------------- HAIR (chunky locks)
def _lock_prism(bm, path, widths, depths):
    """A chunky lock as a closed 4-sided prism following `path` (list of centre points along the
    lock), with per-node half-width (across) `widths` and half-depth (toward/away the head) `depths`.
    It tapers to a small blunt rectangle at the tip (never a single-vertex spike) so the ink outline
    draws one clean lock shape. `up` across the lock is derived per segment so curved locks stay solid.
    Returns the list of created faces (so the caller can smooth them)."""
    n = len(path)
    rings = []
    for i in range(n):
        c = path[i]
        fwd = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)])
        if fwd.length < 1e-6:
            fwd = Vector((0, 0, -1))
        fwd.normalize()
        # 'across' is horizontal, perpendicular to the lock's forward and to world up
        across = Vector((0, 0, 1)).cross(fwd)
        if across.length < 1e-5:
            across = Vector((1, 0, 0))
        across.normalize()
        depth_dir = fwd.cross(across).normalized()
        w = widths[i]
        d = depths[i]
        quad = [
            bm.verts.new(c + across * w + depth_dir * d),
            bm.verts.new(c - across * w + depth_dir * d),
            bm.verts.new(c - across * w - depth_dir * d),
            bm.verts.new(c + across * w - depth_dir * d),
        ]
        rings.append(quad)
    faces = []
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(4):
            faces.append(bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k])))
    faces.append(bm.faces.new(list(reversed(rings[0]))))   # root cap
    faces.append(bm.faces.new(rings[-1]))                   # tip cap
    return faces


def _curved_lock(bm, root, aim, length, bow, w_root, w_tip, d_root, d_tip, segs=4):
    """Build one lock from `root` heading in direction `aim` (will be normalised), curving by `bow`
    (a world-space vector added with a sin profile so the lock bends), tapering width/depth root->tip."""
    aim = aim.normalized()
    path, widths, depths = [], [], []
    for s in range(segs + 1):
        t = s / segs
        c = root + aim * (length * t) + bow * math.sin(math.pi * 0.5 * t)
        path.append(c)
        taper = (1 - t)
        widths.append(max(0.010, w_root * taper + w_tip * (1 - taper)) if False else (w_root * (1 - t) + w_tip * t))
        depths.append(d_root * (1 - t) + d_tip * t)
    return _lock_prism(bm, path, widths, depths)


def build_hair():
    """The chibi_v2 OWN hair: a thin skullcap (so no scalp shows) + 15-20 separate chunky LOCKS with
    blunt pointed tips - crown locks, side locks framing the cheeks to jaw level, back locks, and a
    fringe of 6 locks whose tips stop ABOVE the brows - plus a thin dark headband. The silhouette is
    wider than the face with visible gaps between locks, so the ink outline draws each lock. All
    pieces are tagged studio_hair_style=original. The locks use the 'Neutral clay' material (prefix
    the Look system recolours by the chosen hair colour, like the model team's own bob); the headband
    is its own dark 'Headband clay'. 'Hair clay' is kept defined so the material-name contract holds."""
    mat("Hair clay", HAIR, rough=0.55, spec=0.35)   # kept for the name contract (locks use Neutral clay)
    hair_mat = mat("Neutral clay", SKIN)             # recoloured to the hair colour by code (hair key)
    objs = []
    cx, cy, cz = HEAD_C
    rx, ry, rz = HEAD_R

    # ---- skullcap: a thin dome over the top/back/sides so no scalp shows between locks.
    bm = bmesh.new()
    SEG = 20
    RINGS = 7
    srx, sry, srz = rx * 1.14, ry * 1.16, rz * 1.08
    sc = Vector((cx, cy + 0.010, cz + 0.012))
    rings = []
    for ri in range(RINGS + 1):
        t = ri / RINGS
        vs = []
        for i in range(SEG):
            a = 2 * math.pi * i / SEG
            fy = math.sin(a)                                   # -1 front .. +1 back
            # the cap stops at a clean hairline across the front (fy<0), hangs lower at sides/back
            depth = 0.40 + 0.26 * max(0.0, fy) + 0.20 * abs(math.cos(a))
            if fy < -0.15:
                depth = 0.23                                   # front hairline, tucked under the fringe
            phi = math.pi * (0.02 + depth * t)
            phi = min(phi, math.pi * 0.95)
            z = sc.z + srz * math.cos(phi)
            rr = math.sin(phi)
            vs.append(bm.verts.new((sc.x + srx * rr * math.cos(a), sc.y + sry * rr * math.sin(a), z)))
        rings.append(vs)
    top = bm.verts.new((sc.x, sc.y, sc.z + srz))
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((top, rings[0][j], rings[0][i]))
    for i in range(RINGS):
        bridge(bm, rings[i], rings[i + 1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    cap_ob = obj_from_bm(bm, "Hair crown", hair_mat, extras={"studio_hair_style": "original"})
    sm = cap_ob.modifiers.new("sol", "SOLIDIFY"); sm.thickness = 0.016; sm.offset = 1.0
    smooth_shade(cap_ob)
    objs.append(cap_ob)

    # ---- all the chunky locks in one object 'Hair locks'.
    bl = bmesh.new()

    def surf(az, el, out):
        return _on_head(az, el, out=out)

    # SIDE LOCKS framing the cheeks down toward the jaw. Per side: a few locks of DIFFERENT widths
    # and lengths, each with its own curve + a little inward twist, tapering to a POINT at the jaw
    # (w1 ~ 0.004) with real thickness (depth) so they are not flat planks. Slightly overlapping.
    for side in (1, -1):
        for li, (az, el0, length, w0, w1, bowx, bowz, d_root) in enumerate([
            # az,  el_top, len,  w_root, w_tip,  bowx,   bowz,   depth_root
            (0.90, 0.28, 0.33, 0.046, 0.004, -0.016, -0.030, 0.030),   # front lock, longest, curls in
            (1.18, 0.33, 0.29, 0.034, 0.005, -0.010, -0.022, 0.024),   # mid-front, shorter, thinner
            (1.46, 0.35, 0.36, 0.050, 0.004, -0.006, -0.034, 0.034),   # main cheek lock, long + chunky
            (1.74, 0.37, 0.26, 0.030, 0.005, 0.006, -0.018, 0.022),   # rear wisp, short
        ]):
            root = surf(az * side, el0, out=0.012)
            # aim mostly down, a touch forward+out; vary the forward tilt per lock for overlap
            aim = Vector(((0.03 + 0.03 * (li % 2)) * side, -0.02 - 0.01 * (li % 2), -1.0))
            # bow curves the lock in toward the jaw, plus a small sideways twist alternating per lock
            twist = (0.006 if li % 2 == 0 else -0.004) * side
            bow = Vector((bowx * side + twist, -0.03, bowz))
            _curved_lock(bl, root, aim, length, bow, w0, w1, d_root, 0.006, segs=5)


    # BACK LOCKS covering the nape (4 across the back, medium length).
    for bi, frac in enumerate([-0.6, -0.2, 0.2, 0.6]):
        az = math.pi + frac                                    # around the back
        root = surf(az, 0.34, out=0.012)
        aim = Vector((0.0, 0.03, -1.0))
        length = 0.30 - 0.04 * abs(frac)
        _curved_lock(bl, root, aim, length, Vector((0.0, 0.02, -0.01)), 0.044, 0.018, 0.016, 0.010, segs=4)

    # CROWN LOCKS lying over the top toward the back (3, add chunk to the silhouette top).
    for ci, (az, el) in enumerate([(2.5, 0.9), (math.pi, 0.95), (3.78, 0.9)]):
        root = surf(az, el, out=0.014)
        aim = Vector((math.sin(az) * 0.3, -math.cos(az) * 0.3, -0.7)).normalized()
        _curved_lock(bl, root, aim, 0.20, Vector((0, 0, -0.01)), 0.046, 0.020, 0.018, 0.012, segs=3)

    # FRINGE: 8 bangs of DIFFERENT widths & lengths, overlapping, blade-shaped (tapered to a soft
    # point, NOT a needle), most swept toward the character's left (a parting). They are LONGER than
    # round-2 and reach down closer to the brow line (tips el ~0.08-0.16) so they cover the forehead
    # and the skullcap rim instead of sitting high as stubby teeth. az spacing / widths / tip heights
    # / proudness all vary and each lock bends with its own bow, so it never reads as an even row.
    fringe_defs = [
        # az,    el_top, el_tip, w_root, w_tip, sweepx,  bowx,   out0,  segs
        (-0.66, 0.44, 0.15, 0.032, 0.004, 0.034, 0.016, 0.022, 6),   # far-left wide bang, long sweep
        (-0.46, 0.46, 0.09, 0.026, 0.004, 0.028, 0.012, 0.019, 6),   # left, longest, points low
        (-0.26, 0.47, 0.12, 0.022, 0.004, 0.022, 0.009, 0.017, 6),   # left-centre
        (-0.08, 0.47, 0.08, 0.028, 0.004, 0.014, 0.004, 0.020, 6),   # the main long bang over the parting
        (0.01, 0.46, 0.13, 0.018, 0.004, 0.006, 0.000, 0.019, 5),    # short centre wisp, closes the parting gap
        (0.10, 0.47, 0.11, 0.024, 0.004, 0.004, -0.004, 0.018, 6),   # centre-right, fills the middle
        (0.30, 0.46, 0.10, 0.021, 0.004, -0.006, -0.009, 0.017, 6),  # right
        (0.48, 0.45, 0.14, 0.025, 0.004, -0.016, -0.012, 0.019, 6),  # right wide
        (0.68, 0.43, 0.17, 0.030, 0.004, -0.026, -0.015, 0.022, 6),  # far-right wide bang, short sweep out
    ]
    for (az, el_top, el_tip, w0, w1, sweepx, bowx, out0, segs) in fringe_defs:
        path, widths, depths = [], [], []
        for s in range(segs + 1):
            t = s / segs
            el = el_top * (1 - t) + el_tip * t
            out = out0 + 0.005 * t                       # hug the head, tip a touch proud
            p = _on_head(az, el, out=out)
            # curve the lock: side-sweep across the brow + a gentle sideways bow (sin profile)
            p.x += sweepx * t + bowx * math.sin(math.pi * t)
            path.append(p)
            # blade taper: linear-ish so it is a soft pointed blade, not a thin needle spike
            wt = w0 * (1 - t) + w1 * t
            widths.append(max(0.003, wt))
            depths.append(max(0.007, wt * 0.9))          # keep thickness so it is not a flat plank
        _lock_prism(bl, path, widths, depths)



    bmesh.ops.recalc_face_normals(bl, faces=bl.faces)
    locks = obj_from_bm(bl, "Hair locks", hair_mat, extras={"studio_hair_style": "original"})
    smooth_shade(locks)
    objs.append(locks)

    # ---- HEADBAND: a thin dark band around the head at the hairline, ABOVE the fringe tips, hugging
    # the skull (not floating in front). Wraps a little past the temples.
    bmb = bmesh.new()
    SEGB = 24
    inner, outer = [], []
    for i in range(SEGB + 1):
        az = (i / SEGB - 0.5) * 2.6                            # ear to ear, a bit around the sides
        bc = _on_head(az, 0.30, out=0.016)
        inner.append(bmb.verts.new(bc))
        outer.append(bmb.verts.new(bc + Vector((0, 0, 0.014))))
    for i in range(SEGB):
        bmb.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))
    bmesh.ops.recalc_face_normals(bmb, faces=bmb.faces)
    band = obj_from_bm(bmb, "Headband", mat("Headband clay", HEADBAND, rough=0.5),
                       extras={"studio_hair_style": "original"})
    bandsol = band.modifiers.new("sol", "SOLIDIFY"); bandsol.thickness = 0.008; bandsol.offset = 0.0
    smooth_shade(band)
    objs.append(band)
    return objs


# ----------------------------------------------------------------------------- SKIN + EXPORT
def skin_to_armature(objs, arm):
    """Parent each mesh to `arm` with automatic (heat) weights, then clean tiny weights and
    cap to 4 bones/vert so the glTF export and Godot stay happy. Keeps all 57 vertex groups."""
    # apply any mesh modifiers (e.g. hair solidify) first
    for ob in objs:
        if not ob.modifiers:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        for m in list(ob.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError:
                ob.modifiers.remove(m)
    for ob in objs:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    # limit + clean
    for ob in objs:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        try:
            bpy.ops.object.vertex_group_limit_total(limit=4)
            bpy.ops.object.vertex_group_clean(limit=0.002, keep_single=True)
            bpy.ops.object.vertex_group_normalize_all()
        except RuntimeError:
            pass


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    # Drop every imported mesh + stray helper; keep ONLY the armature (identical rest skeleton).
    # (The source glb carries a stray Cube + Icosphere at the origin; remove them explicitly too so
    # they can never ride along into our export and render as a grey block around the body.)
    for o in list(bpy.data.objects):
        if o.type != "ARMATURE":
            bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    # Also clear imported actions so none get re-exported (clips come from art/animations).
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    if arm.animation_data:
        arm.animation_data_clear()

    skin = mat("Neutral clay", SKIN)
    meshes = []
    meshes.append(build_body(skin))
    footL = build_foot(skin, 1); footR = build_foot(skin, -1)
    meshes += [footL, footR]
    meshes.append(build_hands(skin))
    meshes.append(build_face(skin))
    meshes.append(build_nose(skin))
    browL = build_brow(1); browR = build_brow(-1)
    meshes += [browL, browR]
    eyeL = build_eye(1); eyeR = build_eye(-1)
    meshes += [eyeL, eyeR]
    lidL = build_eyelid(1); lidR = build_eyelid(-1)
    meshes += [lidL, lidR]
    meshes.append(build_mouth(skin))
    meshes += build_hair()

    skin_to_armature(meshes, arm)

    # Export: armature + all meshes, Y-up (matches the source), no animations.
    # Blender 4.5's read_factory_settings(use_empty) can still leave a default Cube/Icosphere at the
    # origin; they would render as a grey block around the body. Remove anything that is not the
    # armature or one of our built meshes, then purge orphan datablocks.
    keep = set([arm]) | set(meshes)
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    # Purge orphan datablocks (the source glb's stray Cube/Icosphere/Sphere mesh data linger with 0
    # users and otherwise ride into the export). Purge repeatedly until nothing is left to remove.
    for _ in range(5):
        if bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True) == 0:
            break
    for d in list(bpy.data.materials):
        if d.name == "Material":
            try:
                bpy.data.materials.remove(d)
            except Exception:
                pass
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = arm
    import os
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
                              export_skins=True, export_animations=False, export_yup=True,
                              export_extras=True)
    # report
    total = sum(len(m.data.polygons) for m in meshes)
    tris = 0
    for m in meshes:
        m.data.calc_loop_triangles()
        tris += len(m.data.loop_triangles)
    print("CHIBI_V2_BUILT meshes=%d tris=%d file=%s" % (len(meshes), tris, OUT))


main()

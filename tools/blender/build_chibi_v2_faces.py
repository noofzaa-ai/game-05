"""Build the 11 chibi_v2 face items (new assets, model-team files untouched).

    blender -b --factory-startup --python tools/blender/build_chibi_v2_faces.py -- <out_dir>

Each face is a small rigid GLB (no skeleton) authored in the attach_head bone's local frame, the
SAME convention the model team's face items use, so client/character_model.gd mounts them on the
attach_head BoneAttachment with no code change. It fits the chibi_v2 OWN head (round skull, centre
at rig z=1.33; the attach_head bone head is at rig z=1.5393, so face-local z = world z - 1.5393).

Front = -Y, up = +Z, X = character's left. One mesh per face, materials shared across all:
  'Face ink'   - the black line art (lashes, pupils, brows, mouth strokes, nose tick)
  'Face white' - the sclera / teeth / highlights
  'Face iris'  - the recolourable iris (ruby/pink default, its own material)
  'Face tongue'/'Face sweat' - accents

ROUND 3 fix (PO review of round2): the eye/brow/lash frame used a cross-product `up` that FLIPPED
on the character's right side, so every lash wing + brow landed as a diagonal slash down that cheek
and the right brow went missing/misplaced. Rewritten so BOTH sides use a fixed, non-flipping local
frame (up = world +Z, right = world +X, the only mirroring is negating the x of each offset by
`side`). That guarantees true left/right symmetry except where we deliberately break it (wink,
one raised brow, sly tilt). Mouth curve signs corrected against each name (smile/soft_smile now
curve UP). Lower lash reduced to a thin short hint at the OUTER lower corner only. Highlights are
one big upper-outer + one small lower-inner, identical on both eyes. Nose is a tiny dot/tick.
"""
import bpy, bmesh, sys, math, os
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = argv[0]

# ------------------------------------------------------------------- head frame (chibi_v2, attach_head-local)
ATTACH_Z = 1.5393
HEAD_C = Vector((0.0, 0.0, 1.33 - ATTACH_Z))   # head centre in face-local frame  (~ (0,0,-0.209))
HEAD_R = Vector((0.165, 0.150, 0.185))

INK = (0.03, 0.025, 0.035, 1.0)      # crisp near-black line art
WHITE = (0.98, 0.97, 0.96, 1.0)
IRIS = (0.80, 0.17, 0.30, 1.0)       # ruby/pink default (own material, recolourable)
IRIS_DARK = (0.52, 0.10, 0.20, 1.0)  # darker top third / rim
TONGUE = (0.86, 0.40, 0.45, 1.0)
FANG = (0.98, 0.97, 0.96, 1.0)
SWEAT = (0.60, 0.78, 0.95, 1.0)

I_WHITE, I_IRIS, I_INK, I_TONGUE, I_SWEAT = 0, 1, 2, 3, 4


def mat(name, rgba, rough=0.5, spec=0.3):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = rgba
    b.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = spec
    return m


def head_point(az, el, out=0.0):
    """Point on the head surface: az around (0 = front -Y, +toward character's left +X), el up."""
    x = math.sin(az) * math.cos(el)
    y = -math.cos(az) * math.cos(el)
    z = math.sin(el)
    return Vector((HEAD_C.x + (HEAD_R.x + out) * x,
                   HEAD_C.y + (HEAD_R.y + out) * y,
                   HEAD_C.z + (HEAD_R.z + out) * z))


# eye placement (anime: large, low, wide apart)
EYE_AZ = 0.40
EYE_EL = -0.26


def eye_frame(side):
    """Centre of the eye + a FIXED, NON-FLIPPING local frame.

    `right` is always world +X (toward the character's left), `up` is always world +Z, `n` is the
    outward head normal. We do NOT flip the frame per side; mirroring is done by the caller negating
    the x of every offset via `side`. This is the round-3 fix for the diagonal-slash / missing-brow
    bug (the old frame used up.cross(n) which inverted `up` on the right eye)."""
    c = head_point(EYE_AZ * side, EYE_EL, out=0.002)
    n = Vector((c.x - HEAD_C.x, c.y - HEAD_C.y, c.z - HEAD_C.z)).normalized()
    right = Vector((1.0, 0.0, 0.0))
    up = Vector((0.0, 0.0, 1.0))
    return c, right, up, n


# ------------------------------------------------------------------- low-level fillers
def ribbon(bm, mat_i, pts_lo, pts_hi):
    """A quad strip between two matched vertex rows (already bmesh verts)."""
    for i in range(len(pts_lo) - 1):
        f = bm.faces.new((pts_lo[i], pts_lo[i + 1], pts_hi[i + 1], pts_hi[i]))
        f.material_index = mat_i


# ------------------------------------------------------------------- eye builder (parametric by expression)
def build_eye(bm, side, shape):
    """Draws sclera (white), iris (own mat, dark top rim + pupil), two highlights, a thick winged
    upper lash and a thin SHORT lower-lash hint at the outer corner only.

    Local frame is fixed (right=+X, up=+Z). Mirroring is `side`: we negate the x of every offset by
    multiplying its right-component by `side`, so both eyes are exact mirror images. `tilt` is an
    outer-corner rotation applied in-plane; its sign uses `side` so both outer corners move the same
    way (up for soft, down for devious)."""
    c, right, up, n = eye_frame(side)
    rx = shape.get("rx", 0.058)
    rz = shape.get("rz", 0.050) * shape.get("open", 1.0)
    tilt = shape.get("tilt", 0.0)          # + = outer corner down (devious), - = outer up

    def place(ex, ez, lift):
        """Map an (ex, ez) offset in the eye plane to a world vert, mirrored by side and tilted.
        ex is measured so +ex is ALWAYS toward the outer corner; we convert to world +X via side."""
        # tilt rotates around the eye centre; outer corner is +ex
        ca, sa = math.cos(tilt), math.sin(tilt)
        tx = ex * ca - ez * sa * 0 - ez * 0   # keep horizontal; tilt applied to vertical below
        # apply tilt as a shear of vertical by horizontal position (outer end lifts/drops)
        rx_world = right * (ex * side)
        ez2 = ez - math.tan(tilt) * ex        # outer end (+ex) drops when tilt>0
        return c + rx_world + up * ez2 + n * lift

    if shape.get("wink", False):
        # a wink / closed eye: a single thick upward-curving lash line, no sclera
        k = 12
        lo, hi = [], []
        curve = shape.get("curve", 1.0)       # +1 happy (smile up)
        for i in range(k + 1):
            t = i / k                          # 0 inner .. 1 outer
            ex = rx * 1.02 * (t - 0.5) * 2.0   # -rx inner .. +rx outer
            ez = rz * 0.55 * curve * math.sin(math.pi * t)
            thick = 0.006 + 0.012 * t          # thicker at outer
            lo.append(bm.verts.new(place(ex, ez, 0.012)))
            hi.append(bm.verts.new(place(ex, ez + thick, 0.013)))
        ribbon(bm, I_INK, lo, hi)
        return

    # sclera (white almond): filled ellipse, squashed by openness
    scl = []
    k = 20
    for i in range(k + 1):
        a = math.tau * i / k
        scl.append(bm.verts.new(place(rx * math.cos(a), rz * math.sin(a), 0.006)))
    cen = bm.verts.new(place(0, 0, 0.006))
    for i in range(k):
        f = bm.faces.new((cen, scl[i], scl[i + 1]))
        f.material_index = I_WHITE

    # iris: tall oval, pushed slightly down, OWN material
    irx = rx * 0.62
    irz = rz * 0.86
    ioz = -rz * 0.04                           # iris vertical offset
    icen = bm.verts.new(place(0, ioz, 0.015))
    iril = []
    for i in range(k + 1):
        a = math.tau * i / k
        iril.append(bm.verts.new(place(irx * math.cos(a), ioz + irz * math.sin(a), 0.015)))
    for i in range(k):
        f = bm.faces.new((icen, iril[i], iril[i + 1]))
        f.material_index = I_IRIS

    # dark top of the iris: a thin clean rim-line hugging the top edge only
    topl, toph = [], []
    kk = 12
    for i in range(kk + 1):
        a = math.pi * (0.30 + 0.40 * i / kk)   # short arc over the very top
        toph.append(bm.verts.new(place(irx * 1.00 * math.cos(a), ioz + irz * 1.00 * math.sin(a), 0.017)))
        topl.append(bm.verts.new(place(irx * 0.86 * math.cos(a), ioz + irz * 0.86 * math.sin(a), 0.017)))
    ribbon(bm, I_INK, topl, toph)

    # pupil: a small dark disc, centred (slightly low)
    pr = irx * 0.34
    poz = ioz - irz * 0.06
    pcen = bm.verts.new(place(0, poz, 0.019))
    pril = []
    for i in range(13):
        a = math.tau * i / 12
        pril.append(bm.verts.new(place(pr * math.cos(a), poz + pr * math.sin(a), 0.019)))
    for i in range(12):
        f = bm.faces.new((pcen, pril[i], pril[i + 1]))
        f.material_index = I_INK

    # highlights: ONE big upper-outer + ONE small lower-inner, identical on both eyes.
    # ex is in outer-corner space (+ex = outer), so upper-outer = (+ex,+ez); mirrors cleanly via side.
    for (hx, hz, hr) in [(0.014, 0.022, 0.015), (-0.012, -0.016, 0.007)]:
        hcen = bm.verts.new(place(hx, ioz + hz, 0.024))
        hril = []
        for i in range(11):
            a = math.tau * i / 10
            hril.append(bm.verts.new(place(hx + hr * math.cos(a), ioz + hz + hr * math.sin(a), 0.024)))
        for i in range(10):
            f = bm.faces.new((hcen, hril[i], hril[i + 1]))
            f.material_index = I_WHITE

    # thick upper lash line with a winged outer flick (outer = +ex end)
    k = 14
    lo, hi = [], []
    for i in range(k + 1):
        t = i / k                              # 0 inner .. 1 outer
        a = math.pi * (0.04 + 0.92 * t)        # across the top, inner->outer
        ex = rx * 1.04 * math.cos(a)
        ez = rz * 1.02 * math.sin(a)
        thick = 0.006 + 0.014 * t              # thicker toward the outer corner
        flick = 0.012 * max(0.0, t - 0.72) / 0.28   # a small up+out wing at the very outer end
        lo.append(bm.verts.new(place(ex, ez, 0.014)))
        hi.append(bm.verts.new(place(ex + flick, ez + thick, 0.015)))
    ribbon(bm, I_INK, lo, hi)

    # thin SHORT lower-lash hint at the OUTER lower corner only
    if shape.get("lower", True):
        k = 6
        lo, hi = [], []
        for i in range(k + 1):
            t = i / k                          # 0.45 .. 1.0 of the way to the outer corner
            a = math.pi * (1.72 + 0.26 * t)    # a short arc at the lower-outer only
            ex = rx * 0.98 * math.cos(a)
            ez = rz * 0.98 * math.sin(a)
            lo.append(bm.verts.new(place(ex, ez, 0.013)))
            hi.append(bm.verts.new(place(ex, ez + 0.0035, 0.014)))
        ribbon(bm, I_INK, lo, hi)


# ------------------------------------------------------------------- brow
def build_brow(bm, side, shape):
    """A thick arched brow above the eye. Fixed frame (right=+X, up=+Z); mirrored by `side`.
    brow_tilt: + = inner end down (angry), - = inner end up (sad). brow_raise scales the height."""
    c, right, up, n = eye_frame(side)
    raise_h = shape.get("brow_raise", 1.0)
    base_z = c.z + 0.050 * raise_h + 0.040
    base_x = c.x + 0.004 * side                # a touch outward
    ang = shape.get("brow_tilt", 0.0)
    arch = shape.get("brow_arch", 0.006)
    lo, hi = [], []
    k = 6
    for i in range(k + 1):
        t = i / k                              # 0 inner .. 1 outer
        ex = (t - 0.5) * 0.078                 # outer-corner space (+ = outer)
        # inner end (t=0) raised/lowered by ang: inner is -ex, so lift inner by ang when ang<0 (sad)
        y = arch * math.sin(math.pi * t) - ang * (0.5 - t) * 0.14
        thick = 0.013 * (1.0 - 0.55 * t)       # taper to the outer end
        wx = base_x + right.x * (ex * side)
        lo.append(bm.verts.new(Vector((wx, c.y, base_z + y - thick)) + n * 0.011))
        hi.append(bm.verts.new(Vector((wx, c.y, base_z + y + thick)) + n * 0.012))
    ribbon(bm, I_INK, lo, hi)


# ------------------------------------------------------------------- mouth (per expression)
def mouth_center():
    return head_point(0.0, -0.62, out=0.004)


def build_mouth(bm, kind):
    c = mouth_center()
    right = Vector((1, 0, 0))
    up = Vector((0, 0, 1))
    n = Vector((0, -1, 0.2)).normalized()

    def stroke(curve, w=0.0, width=0.052, thick=0.006, open_fill=False, lift=0.012, slant=0.0):
        """A horizontal mouth stroke. curve>0 => ends LOWER than centre = SMILE (upward happy
        curve, corners up). curve<0 => frown. `slant` tilts one corner up (sly). `w` shifts the
        whole stroke vertically."""
        lo, hi = [], []
        k = 14
        for i in range(k + 1):
            t = i / k
            x = (t - 0.5) * width
            # parabola: centre (t=0.5) sits at (w-curve), corners (t=0,1) at w.
            # curve>0 => corners up relative to centre => SMILE; curve<0 => frown.
            y = w - curve * (1.0 - (2 * t - 1) ** 2) + slant * (t - 0.5)
            lo.append(bm.verts.new(c + right * x + up * (y - thick) + n * lift))
            hi.append(bm.verts.new(c + right * x + up * (y + thick) + n * lift))
        ribbon(bm, I_INK, lo, hi)
        if open_fill:  # dark open-mouth fill below the top stroke
            fl = []
            for i in range(k + 1):
                t = i / k
                x = (t - 0.5) * width * 0.92
                y = w - curve * (1.0 - (2 * t - 1) ** 2) + slant * (t - 0.5)
                fl.append(bm.verts.new(c + right * x + up * (y - thick) + n * (lift - 0.002)))
            fb = bm.verts.new(c + up * (w - 0.028) + n * (lift - 0.002))
            for i in range(k):
                f = bm.faces.new((fb, fl[i], fl[i + 1]))
                f.material_index = I_INK

    if kind == "smile":
        # open happy smile: strong upward curve
        stroke(curve=0.020, w=0.004, width=0.060, open_fill=True)
    elif kind == "soft_smile":
        # small gentle upward curve
        stroke(curve=0.009, w=0.0, width=0.042)
    elif kind == "playful":
        # playful open grin + tongue tip
        stroke(curve=0.018, w=0.004, width=0.056, open_fill=True)
        tl = []
        k = 8
        for i in range(k + 1):
            a = math.pi * i / k
            tl.append(bm.verts.new(c + right * (0.016 * math.cos(a)) + up * (-0.024 - 0.012 * math.sin(a)) + n * 0.013))
        tc = bm.verts.new(c + up * (-0.016) + n * 0.013)
        for i in range(k):
            f = bm.faces.new((tc, tl[i], tl[i + 1]))
            f.material_index = I_TONGUE
    elif kind == "prankster":
        # sly grin tilted up to one side
        stroke(curve=0.012, w=-0.002, width=0.056, slant=0.016)
    elif kind == "devious":
        # a smirk: gentle up curve, slanted up on one side, closed
        stroke(curve=0.008, w=0.0, width=0.050, slant=0.012)
    elif kind == "vampire":
        # Fang: a smile with one small fang
        stroke(curve=0.016, w=0.002, width=0.058)
        fx = 0.014
        f0 = bm.verts.new(c + right * fx + up * (-0.002) + n * 0.014)
        f1 = bm.verts.new(c + right * (fx + 0.010) + up * (-0.002) + n * 0.014)
        f2 = bm.verts.new(c + right * (fx + 0.005) + up * (-0.020) + n * 0.014)
        f = bm.faces.new((f0, f1, f2))
        f.material_index = I_WHITE
    elif kind == "bored":
        # flat line
        stroke(curve=0.0, w=0.0, width=0.044)
    elif kind == "annoyed":
        # small frown (downward)
        stroke(curve=-0.010, w=0.002, width=0.040)
    elif kind == "err":
        # wavy mouth
        lo, hi = [], []
        k = 16
        for i in range(k + 1):
            t = i / k
            x = (t - 0.5) * 0.050
            y = 0.006 * math.sin(math.pi * 3.0 * t)
            lo.append(bm.verts.new(c + right * x + up * (y - 0.005) + n * 0.012))
            hi.append(bm.verts.new(c + right * x + up * (y + 0.005) + n * 0.012))
        ribbon(bm, I_INK, lo, hi)
    elif kind == "sad":
        # worried: a thin down-curved frown stroke + a small shallow rounded opening (not a solid V)
        stroke(curve=-0.012, w=0.004, width=0.040)
        # a small shallow dark opening just under the frown, rounded (reads as a slightly open worried mouth)
        rimo = []
        k = 14
        for i in range(k + 1):
            a = math.pi + math.pi * i / k        # lower half-oval only
            rimo.append(bm.verts.new(c + right * (0.015 * math.cos(a)) + up * (-0.012 + 0.010 * math.sin(a)) + n * 0.011))
        cc = bm.verts.new(c + up * (-0.012) + n * 0.010)
        for i in range(k):
            f = bm.faces.new((cc, rimo[i], rimo[i + 1]))
            f.material_index = I_INK
    elif kind == "shout":
        # big open oval mouth
        rimo = []
        k = 20
        for i in range(k + 1):
            a = math.tau * i / k
            rimo.append(bm.verts.new(c + right * (0.030 * math.cos(a)) + up * (-0.004 + 0.038 * math.sin(a)) + n * 0.012))
        cc = bm.verts.new(c + up * (-0.004) + n * 0.010)
        for i in range(k):
            f = bm.faces.new((cc, rimo[i], rimo[i + 1]))
            f.material_index = I_INK
        tl = []
        for i in range(k // 2 + 1):
            a = math.pi + math.pi * i / (k // 2)
            tl.append(bm.verts.new(c + right * (0.020 * math.cos(a)) + up * (-0.014 + 0.016 * math.sin(a)) + n * 0.016))
        tc = bm.verts.new(c + up * (-0.014) + n * 0.016)
        for i in range(len(tl) - 1):
            f = bm.faces.new((tc, tl[i], tl[i + 1]))
            f.material_index = I_TONGUE


def build_nose(bm):
    """A tiny nose tick: a small dot (short vertical dash), NOT a wide triangle/beak."""
    c = head_point(0.0, -0.44, out=0.006)
    right = Vector((1, 0, 0)); up = Vector((0, 0, 1)); n = Vector((0, -1, 0.3)).normalized()
    w, h = 0.0035, 0.007
    v0 = bm.verts.new(c + right * -w + up * (h) + n * 0.004)
    v1 = bm.verts.new(c + right * w + up * (h) + n * 0.004)
    v2 = bm.verts.new(c + up * (-h) + n * 0.004)
    f = bm.faces.new((v0, v1, v2)); f.material_index = I_INK


def build_sweat(bm):
    c = head_point(0.52, 0.10, out=0.012)
    right = Vector((1, 0, 0)); up = Vector((0, 0, 1))
    cen = bm.verts.new(c + Vector((0, -0.004, 0)))
    rim = []
    for i in range(11):
        a = math.tau * i / 10
        rr = 0.012 * (1.0 + 0.5 * max(0.0, math.sin(a)))  # teardrop (pointed up)
        rim.append(bm.verts.new(c + right * (0.010 * math.cos(a)) + up * (rr * math.sin(a))))
    for i in range(10):
        f = bm.faces.new((cen, rim[i], rim[i + 1]))
        f.material_index = I_SWEAT


# ------------------------------------------------------------------- the 11 expressions
EXPR = {
    "smile":      {"eyes": {"open": 0.95, "lower": True}, "brow_raise": 1.1, "brow_arch": 0.008},
    "soft_smile": {"eyes": {"open": 0.60, "lower": True}, "brow_raise": 1.0, "brow_arch": 0.006},
    "playful":    {"eyes": {"open": 1.0}, "wink_side": -1, "brow_raise": 1.15, "brow_arch": 0.010},
    "prankster":  {"eyes": {"open": 0.75, "tilt": -0.10}, "brow_one_up": 1, "brow_raise": 1.0},
    "devious":    {"eyes": {"open": 0.55, "tilt": 0.16}, "brow_tilt": 0.6, "brow_raise": 0.72},
    "vampire":    {"eyes": {"open": 0.90}, "brow_raise": 1.05, "brow_arch": 0.009},
    "bored":      {"eyes": {"open": 0.42, "lower": True}, "brow_raise": 0.9, "brow_arch": 0.002},
    "annoyed":    {"eyes": {"open": 0.72, "tilt": 0.12}, "brow_tilt": 0.7, "brow_raise": 0.70},
    "err":        {"eyes": {"open": 0.70}, "brow_tilt": -0.3, "brow_raise": 1.0, "sweat": True},
    "sad":        {"eyes": {"open": 0.85}, "brow_tilt": -0.7, "brow_raise": 1.2, "brow_arch": 0.004},
    "shout":      {"eyes": {"open": 1.15}, "brow_raise": 1.25, "brow_arch": 0.012},
}


def build_face(face_id):
    bm = bmesh.new()
    mats = [mat("Face white", WHITE, rough=0.3, spec=0.5),
            mat("Face iris", IRIS, rough=0.25, spec=0.6),
            mat("Face ink", INK, rough=0.5, spec=0.1),
            mat("Face tongue", TONGUE, rough=0.4),
            mat("Face sweat", SWEAT, rough=0.1, spec=0.9)]
    cfg = EXPR[face_id]
    # eyes
    for side in (1, -1):
        shape = dict(cfg["eyes"])
        shape.setdefault("rx", 0.058)
        shape.setdefault("rz", 0.052)
        if cfg.get("wink_side") == side:
            shape["wink"] = True
            shape["curve"] = 1.0
        build_eye(bm, side, shape)
    # brows
    for side in (1, -1):
        bshape = {"brow_raise": cfg.get("brow_raise", 1.0),
                  "brow_tilt": cfg.get("brow_tilt", 0.0),
                  "brow_arch": cfg.get("brow_arch", 0.006)}
        if cfg.get("brow_one_up") == side:
            bshape["brow_raise"] = bshape["brow_raise"] + 0.5
        build_brow(bm, side, bshape)
    build_nose(bm)
    build_mouth(bm, face_id)
    if cfg.get("sweat"):
        build_sweat(bm)

    me = bpy.data.meshes.new("Face v2 " + face_id)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new("Face v2 " + face_id, me)
    bpy.context.collection.objects.link(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def export_face(face_id):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    ob = build_face(face_id)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    out = os.path.join(OUT_DIR, "face_v2_%s.glb" % face_id)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True,
                              export_animations=False, export_yup=True, export_extras=True)
    ob.data.calc_loop_triangles()
    tris = len(ob.data.loop_triangles)
    size = os.path.getsize(out)
    print("FACE_V2_BUILT id=%s tris=%d bytes=%d file=%s" % (face_id, tris, size, out))


bpy.ops.wm.read_factory_settings(use_empty=True)
for fid in EXPR:
    export_face(fid)
print("ALL_FACES_DONE")

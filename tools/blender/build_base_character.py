"""Builds the shared base character: a Godot-humanoid skeleton (57 bones), one seamless low-poly body
split by equipment slot, and the customization parts (heads/faces, hair styles), all skinned to the
same skeleton. Run it with Blender:

    blender -b --python tools/blender/build_base_character.py -- <project folder> [--no-preview]

Writes:
  art_source/characters/base_character.blend    source file (build_animations.py opens it)
  art_source/characters/textures/*.png          the painted textures (also packed into the .glb files)
  art/characters/base/base_character.glb         what the game loads: body + default head + default hair
  art/characters/base/parts/<part>.glb           each head/hair part alone, skinned to the same skeleton
  art/characters/base/preview/*.png              preview renders (+ overview.png via contact_sheet.py)

Look (Boss decision 2026-10-04, after Flyff Universe's bare base model): a big-headed ~5-head figure,
1.8 m tall in Blender units (the game scales it to its body height anyway), stylized low-poly with the
skin colour and soft "painted" shading baked into textures, a face drawn as a texture (no geometry
blobs), and light grey-blue underwear shorts as the starter outfit painted on the body.
It stands at the origin, faces -Y in Blender (= +Z in glTF/Godot), T-pose, palms down. Left bones are at +X.

How the body is made: a stick figure with a radius per joint goes through Blender's Skin modifier (ONE
closed quad mesh with proper joints), one subdivision pass rounds it. It is weighted with Blender's heat
weights and only then cut into the slot meshes, so the cut edges match on both sides: no seams in any
pose. The hands are modelled by hand (palm + 2-bone fingers + thumb) with exact weights.

How the textures are made (no hand painting, all procedural, rerunnable): Cycles bakes each mesh's
surface position, normal and ambient occlusion into its UV layout; numpy then "paints" every texel from
those (skin tones from a top-front light and the occlusion, warm shadows, blush, the shorts by height,
the face features by their position on the front of the head). Hair and the iris are painted directly
in their own UV space (strands run along V).
Tinting (data/cosmetics/*.json): the hair uses one material "hair_tint" and the irises "eye_tint" with
neutral light textures; the game multiplies them by the chosen colour (albedo colour). The iris
highlights are in the emission texture so they stay white in every eye colour.
EXTENDING: a new bone is one line in BONES; a body shape change is a radius in body_graph(); a new head
is one entry in HEADS (face features are numbers there); a new hair style is one function in HAIRS.
(The earlier 7.5-head grey mannequin is in git history; the first cartoon version is legacy_cartoon_base.py.)
"""
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

PROJECT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
SOURCE_DIR = os.path.join(PROJECT, "art_source", "characters")
TEXTURE_DIR = os.path.join(SOURCE_DIR, "textures")
OUT_DIR = os.path.join(PROJECT, "art", "characters", "base")
PARTS_DIR = os.path.join(OUT_DIR, "parts")
PREVIEW_DIR = os.path.join(OUT_DIR, "preview")
for folder in (SOURCE_DIR, TEXTURE_DIR, OUT_DIR, PARTS_DIR, PREVIEW_DIR):
    os.makedirs(folder, exist_ok=True)

# ---------------------------------------------------------------------------------------------
# Skeleton: name, parent, head, tail, kind. Names follow Godot's humanoid profile (the side is part
# of the name: LeftUpperArm) so animations from other humanoid sources retarget onto it.
# kind: "core" body bone, "finger", "extra" (secondary motion), "attach" (equipment mount, no skin)
# DO NOT change names or rest directions: the animations are stored relative to them. Joint positions
# follow the ~5-head proportions (Boss decision 2026-10-04).
# ---------------------------------------------------------------------------------------------
BONES = []
ARM_Z = 1.27  # height of the arms in the T-pose (the shoulder line)
WRIST_X = 0.50  # where the hand starts (x of the left wrist)
# The hand was first modelled for a 1.8 m adult (wrist at x 0.72, arms at z 1.40); H() maps those
# coordinates onto this body's wrist with a smaller hand (HS).
HS = 0.83
OLD_WRIST, OLD_ARM_Z = 0.72, 1.40


def H(x, y, z):
    return (WRIST_X + (x - OLD_WRIST) * HS, y * HS, ARM_Z + (z - OLD_ARM_Z) * HS)


def bone(name, parent, head, tail, kind="core"):
    BONES.append((name, parent, Vector(head), Vector(tail), kind))


bone("Root", None, (0, 0, 0), (0, 0, 0.1), "attach")
bone("Hips", "Root", (0, 0, 0.84), (0, 0, 0.92))
bone("Spine", "Hips", (0, 0, 0.92), (0, 0, 1.01))
bone("Chest", "Spine", (0, 0, 1.01), (0, 0, 1.12))
bone("UpperChest", "Chest", (0, 0, 1.12), (0, 0, 1.28))
bone("Neck", "UpperChest", (0, 0, 1.28), (0, 0, 1.365))
bone("Head", "Neck", (0, 0, 1.365), (0, 0, 1.735))
bone("Jaw", "Head", (0, -0.05, 1.435), (0, -0.12, 1.405))
bone("LeftEye", "Head", (0.060, -0.12, 1.518), (0.060, -0.15, 1.518))
bone("RightEye", "Head", (-0.060, -0.12, 1.518), (-0.060, -0.15, 1.518))

FINGERS = (("Index", -0.032, 0.09), ("Middle", -0.008, 0.095), ("Ring", 0.016, 0.09), ("Little", 0.038, 0.075))  # old hand units
FINGER_START = 0.80  # where the fingers leave the palm (old hand x)

for side, sign in (("Left", 1.0), ("Right", -1.0)):
    def m(p):
        return (p[0] * sign, p[1], p[2])

    bone(f"{side}Shoulder", "UpperChest", m((0.025, 0, ARM_Z)), m((0.135, 0, ARM_Z)))
    bone(f"{side}UpperArm", f"{side}Shoulder", m((0.135, 0, ARM_Z)), m((0.32, 0, ARM_Z)))
    bone(f"{side}LowerArm", f"{side}UpperArm", m((0.32, 0, ARM_Z)), m((WRIST_X, 0, ARM_Z)))
    bone(f"{side}Hand", f"{side}LowerArm", m((WRIST_X, 0, ARM_Z)), m(H(FINGER_START, 0, OLD_ARM_Z)))
    bone(f"{side}ForearmTwist", f"{side}LowerArm", m((0.39, 0, ARM_Z)), m((0.48, 0, ARM_Z)), "extra")
    # Thumb (2 bones) and four fingers (2 bones each): enough to close a fist and hold a weapon.
    bone(f"{side}ThumbProximal", f"{side}Hand", m(H(0.73, -0.035, OLD_ARM_Z - 0.01)), m(H(0.775, -0.065, OLD_ARM_Z - 0.02)), "finger")
    bone(f"{side}ThumbDistal", f"{side}ThumbProximal", m(H(0.775, -0.065, OLD_ARM_Z - 0.02)), m(H(0.815, -0.09, OLD_ARM_Z - 0.03)), "finger")
    for finger, offset, length in FINGERS:
        s = FINGER_START
        bone(f"{side}{finger}Proximal", f"{side}Hand", m(H(s, offset, OLD_ARM_Z)), m(H(s + length * 0.55, offset, OLD_ARM_Z)), "finger")
        bone(f"{side}{finger}Intermediate", f"{side}{finger}Proximal", m(H(s + length * 0.55, offset, OLD_ARM_Z)), m(H(s + length, offset, OLD_ARM_Z)), "finger")
    bone(f"{side}UpperLeg", "Hips", m((0.077, 0, 0.80)), m((0.077, 0, 0.45)))
    bone(f"{side}LowerLeg", f"{side}UpperLeg", m((0.077, 0, 0.45)), m((0.077, 0, 0.07)))
    bone(f"{side}Foot", f"{side}LowerLeg", m((0.077, 0, 0.07)), m((0.077, -0.095, 0.03)))
    bone(f"{side}Toes", f"{side}Foot", m((0.077, -0.095, 0.03)), m((0.077, -0.155, 0.018)))
    short = "L" if side == "Left" else "R"
    bone(f"attach_weapon.{short}", f"{side}Hand", m(H(0.80, -0.04, OLD_ARM_Z - 0.05)), m(H(0.80, -0.04, OLD_ARM_Z - 0.11)), "attach")

# Secondary motion: hair and a cape can swing after the body.
bone("HairBack1", "Head", (0, 0.15, 1.665), (0, 0.18, 1.545), "extra")
bone("HairBack2", "HairBack1", (0, 0.18, 1.545), (0, 0.19, 1.425), "extra")
bone("Cape1", "UpperChest", (0, 0.085, 1.27), (0, 0.10, 1.10), "extra")
bone("Cape2", "Cape1", (0, 0.10, 1.10), (0, 0.115, 0.93), "extra")
bone("Cape3", "Cape2", (0, 0.115, 0.93), (0, 0.125, 0.76), "extra")
bone("attach_back", "UpperChest", (0, 0.09, 1.18), (0, 0.15, 1.18), "attach")
bone("attach_head", "Head", (0, 0, 1.735), (0, 0, 1.835), "attach")

DEFORM = [b for b in BONES if b[4] in ("core", "finger", "extra")]
# The bones the body surface is weighted to (heat weights). Fingers, face, hair and cape bones get
# their own meshes; the twist bone is not animated yet.
BODY_BONES = [b[0] for b in BONES if b[4] == "core" and b[0] not in ("Jaw", "LeftEye", "RightEye")]

# Which slot mesh a body face goes to, by the bone that moves it most.
SLOT_OF_BONE = {
    "Hips": "body_torso", "Spine": "body_torso", "Chest": "body_torso", "UpperChest": "body_torso",
    "Neck": "body_torso", "Head": "body_torso", "LeftShoulder": "body_torso", "RightShoulder": "body_torso",
    "LeftUpperArm": "body_arms", "LeftLowerArm": "body_arms", "LeftHand": "body_arms",
    "RightUpperArm": "body_arms", "RightLowerArm": "body_arms", "RightHand": "body_arms",
    "LeftUpperLeg": "body_legs", "LeftLowerLeg": "body_legs", "RightUpperLeg": "body_legs", "RightLowerLeg": "body_legs",
    "LeftFoot": "body_feet", "LeftToes": "body_feet", "RightFoot": "body_feet", "RightToes": "body_feet",
}

# The starter underwear: boxer shorts between these heights, painted on the body (and pushed out a little).
SHORTS_TOP = 0.905
SHORTS_HEM = 0.655

# ---------------------------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------------------------


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, roughness=0.9):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def textured_material(name, image, tint=None, emission=None, roughness=0.85):
    """A material showing `image`; with `tint` the image is multiplied by that colour (glTF exports it as
    the base colour factor, which is what the game changes to tint hair and eyes). `emission`: an image
    added as light (the iris highlights)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.location = (-600, 300)
    if tint is not None:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.name = "tint"
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        mix.inputs[7].default_value = (*tint, 1.0)
        nt.links.new(tex.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        mat.diffuse_color = (*tint, 1.0)
    else:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emission is not None:
        glow = nt.nodes.new("ShaderNodeTexImage")
        glow.image = emission
        glow.location = (-600, -100)
        nt.links.new(glow.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = 0.3
    return mat


def set_tint(mat, color):
    mat.node_tree.nodes["tint"].inputs[7].default_value = (*color, 1.0)
    mat.diffuse_color = (*color, 1.0)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def tri_count(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    count = len(bm.calc_loop_triangles())
    bm.free()
    return count


def build_armature():
    arm_data = bpy.data.armatures.new("Armature")
    arm_obj = link(bpy.data.objects.new("Armature", arm_data))
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    edit = arm_data.edit_bones
    for name, parent, head, tail, kind in BONES:
        eb = edit.new(name)
        eb.head = head
        eb.tail = tail
        eb.use_deform = kind != "attach"
    for name, parent, head, tail, kind in BONES:
        if parent:
            edit[name].parent = edit[parent]
            # connect a child to its parent when it starts exactly where the parent ends
            if (edit[name].head - edit[parent].tail).length < 1e-5:
                edit[name].use_connect = True
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_data.display_type = "OCTAHEDRAL"
    return arm_obj


class MeshBuilder:
    """Collects vertices/faces, per-vertex bone weights and optional per-corner UVs, then makes one object."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.weights = []  # per vertex: {bone: weight}
        self.face_mats = []
        self.face_uvs = []  # per face: list of (u, v) per corner, or None

    def vert(self, co, weights):
        self.verts.append(Vector(co))
        self.weights.append(dict(weights))
        return len(self.verts) - 1

    def face(self, indices, mat=0, uvs=None):
        self.faces.append(tuple(indices))
        self.face_mats.append(mat)
        self.face_uvs.append(uvs)

    def tube(self, rings, weights, mat=0, cap_start=True, cap_end=True, tip_start=None, tip_end=None, uv=None):
        """rings: list of vertex position lists (same count each); weights: one dict per ring.
        tip_*: (position, weights) closes that end with a point instead of a flat cap.
        uv: optional f(ring, segment, face_center_segment) -> (u, v); ring -1 / len(rings) are the tips,
        segment runs 0..count (count = back at the start, so a texture can wrap)."""
        loops = [[self.vert(p, w) for p in ring] for ring, w in zip(rings, weights)]
        count, n = len(rings[0]), len(rings)

        def corner(r, s, c):
            return uv(r, s, c) if uv else None

        for k, (a, b) in enumerate(zip(loops, loops[1:])):
            for i in range(count):
                j = (i + 1) % count
                c = i + 0.5
                uvs = [corner(k, i, c), corner(k, i + 1, c), corner(k + 1, i + 1, c), corner(k + 1, i, c)] if uv else None
                self.face((a[i], a[j], b[j], b[i]), mat, uvs)
        for index, loop, tip, cap, reverse in ((0, loops[0], tip_start, cap_start, True), (n - 1, loops[-1], tip_end, cap_end, False)):
            tip_ring = -1 if reverse else n
            if tip is not None:
                center = self.vert(*tip)
                for i in range(count):
                    j = (i + 1) % count
                    c = i + 0.5
                    if reverse:
                        uvs = [corner(index, i + 1, c), corner(index, i, c), corner(tip_ring, c, c)] if uv else None
                        self.face((loop[j], loop[i], center), mat, uvs)
                    else:
                        uvs = [corner(index, i, c), corner(index, i + 1, c), corner(tip_ring, c, c)] if uv else None
                        self.face((loop[i], loop[j], center), mat, uvs)
            elif cap:
                order = list(range(count))[::-1] if reverse else list(range(count))
                uvs = [corner(index, i, count / 2.0) for i in order] if uv else None
                self.face([loop[i] for i in order], mat, uvs)
        return loops

    def ellipsoid(self, center, axes, radii, weights, mat=0, segments=8, rings=5, uv=None, deform=None):
        """axes: (right, up, out) unit vectors; radii along them. uv: (u0, v0, u1, v1) box for its texture.
        deform: optional f(point) -> point applied to every vertex."""
        right, up, out = axes
        deform = deform or (lambda p: p)
        loops = []
        for r in range(1, rings):
            theta = math.pi * r / rings
            loop = []
            for s in range(segments):
                phi = 2 * math.pi * s / segments
                p = center + up * (math.cos(theta) * radii[1]) + right * (math.sin(theta) * math.cos(phi) * radii[0]) + out * (math.sin(theta) * math.sin(phi) * radii[2])
                loop.append(deform(p))
            loops.append(loop)
        box = None
        if uv is not None:
            u0, v0, u1, v1 = uv

            def box(r, s, c):
                return (u0 + (u1 - u0) * s / segments, v1 - (v1 - v0) * (r + 1) / rings)
        return self.tube(loops, [weights] * len(loops), mat, tip_start=(deform(center + up * radii[1]), weights),
                         tip_end=(deform(center - up * radii[1]), weights), uv=box)

    def build(self, name, materials, smooth=True, recalc=True):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        for mat in materials:
            mesh.materials.append(mat)
        for poly, mat_index in zip(mesh.polygons, self.face_mats):
            poly.material_index = mat_index
            poly.use_smooth = smooth
        if any(uvs is not None for uvs in self.face_uvs):
            layer = mesh.uv_layers.new(name="UVMap")
            for poly, uvs in zip(mesh.polygons, self.face_uvs):
                for corner, loop_index in enumerate(poly.loop_indices):
                    layer.data[loop_index].uv = uvs[corner] if uvs is not None else (0.0, 0.0)
        mesh.validate()
        obj = link(bpy.data.objects.new(name, mesh))
        if recalc:
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(mesh)
            bm.free()
        for index, weights in enumerate(self.weights):
            total = sum(weights.values())
            for bone_name, value in weights.items():
                group = obj.vertex_groups.get(bone_name) or obj.vertex_groups.new(name=bone_name)
                group.add([index], value / total, "REPLACE")
        return obj


def bind(obj, armature):
    modifier = obj.modifiers.get("Armature") or obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature


# ---------------------------------------------------------------------------------------------
# The body
# ---------------------------------------------------------------------------------------------

# The subdivision pass pulls the skin cage in (about 12% across, 25% front-to-back); these factors
# turn the wanted final half-widths into cage radii.
SHRINK_X = 1.0 / 0.88
SHRINK_Y = 1.0 / 0.76


def body_graph():
    """The stick figure for the Skin modifier: (positions with wanted final half-width x, half-depth y),
    edges. Proportions: ~5 heads (Flyff-like): short slim torso, big head, legs about half the height."""
    nodes, edges = [], []

    def node(position, half_x, half_y):
        nodes.append((Vector(position), (half_x * SHRINK_X, half_y * SHRINK_Y)))
        return len(nodes) - 1

    def chain(*ids):
        edges.extend(zip(ids, ids[1:]))

    pelvis = node((0, 0.004, 0.84), 0.112, 0.084)
    belly = node((0, 0.000, 0.93), 0.100, 0.076)
    waist = node((0, 0.002, 1.01), 0.092, 0.070)
    chest = node((0, -0.004, 1.115), 0.108, 0.078)
    upper = node((0, 0.004, 1.215), 0.122, 0.076)
    trapezius = node((0, 0.008, 1.29), 0.076, 0.060)
    neck_base = node((0, 0.008, 1.33), 0.040, 0.040)
    neck_top = node((0, 0.006, 1.40), 0.036, 0.038)
    chain(pelvis, belly, waist, chest, upper, trapezius, neck_base, neck_top)
    for s in (1.0, -1.0):
        shoulder = node((s * 0.135, 0.004, ARM_Z - 0.005), 0.040, 0.040)
        deltoid = node((s * 0.18, 0.002, ARM_Z), 0.038, 0.038)
        upper_arm = node((s * 0.25, 0, ARM_Z), 0.033, 0.034)
        elbow = node((s * 0.32, 0, ARM_Z), 0.027, 0.029)
        forearm = node((s * 0.37, 0, ARM_Z), 0.029, 0.028)
        wrist = node((s * H(0.725, 0, 0)[0], 0, ARM_Z), 0.017, 0.022)
        chain(upper, shoulder, deltoid, upper_arm, elbow, forearm, wrist)
        hip = node((s * 0.075, 0.002, 0.79), 0.062, 0.068)
        thigh = node((s * 0.077, 0.000, 0.65), 0.054, 0.057)
        knee = node((s * 0.077, -0.004, 0.45), 0.040, 0.043)
        calf = node((s * 0.077, 0.006, 0.34), 0.042, 0.046)
        shin = node((s * 0.077, 0.002, 0.20), 0.032, 0.035)
        ankle = node((s * 0.077, 0.004, 0.075), 0.026, 0.028)
        ball = node((s * 0.078, -0.085, 0.026), 0.036, 0.024)
        toe = node((s * 0.079, -0.142, 0.021), 0.029, 0.017)
        heel = node((s * 0.077, 0.030, 0.035), 0.027, 0.027)
        chain(pelvis, hip, thigh, knee, calf, shin, ankle, ball, toe)
        chain(ankle, heel)
    return nodes, edges, pelvis


def build_body_mesh(skin_mat):
    nodes, edges, root = body_graph()
    mesh = bpy.data.meshes.new("body")
    mesh.from_pydata([tuple(p) for p, _ in nodes], edges, [])
    obj = link(bpy.data.objects.new("body", mesh))
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.branch_smoothing = 0.6
    skin.use_x_symmetry = True
    for index, (_, radius) in enumerate(nodes):
        mesh.skin_vertices[0].data[index].radius = radius
    mesh.skin_vertices[0].data[root].use_root = True
    activate(obj)
    bpy.ops.object.modifier_apply(modifier=skin.name)
    subsurf = obj.modifiers.new("Smooth", "SUBSURF")
    subsurf.levels = 1
    bpy.ops.object.modifier_apply(modifier=subsurf.name)
    # flatten the soles a little so the feet stand on the floor
    for v in obj.data.vertices:
        if v.co.z < 0.012 and abs(v.co.x) > 0.03:
            v.co.z = 0.004 + (v.co.z - 0.004) * 0.3
    # the shorts stand off the skin a little, flaring toward the hem (a visible step at the leg openings)
    obj.data.update()
    for v in obj.data.vertices:
        z = v.co.z
        if SHORTS_HEM - 0.004 <= z <= SHORTS_TOP + 0.01 and abs(v.co.x) < 0.2:
            flare = 0.004 + 0.006 * max(0.0, 1.0 - (z - SHORTS_HEM) / 0.08)
            v.co += v.normal * flare
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(skin_mat)
    return obj


def heat_weights(obj, armature):
    """Blender's automatic (bone heat) weights, using only the body bones."""
    saved = {}
    for b in armature.data.bones:
        saved[b.name] = b.use_deform
        b.use_deform = b.name in BODY_BONES
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in armature.data.bones:
        b.use_deform = saved[b.name]
    missing = [v.index for v in obj.data.vertices if not v.groups]
    if missing:
        print("WARNING heat weights missed", len(missing), "vertices")


def limit_weights(obj, count=4):
    """At most `count` bones per vertex (what the game uses), normalized."""
    names = {g.index: g.name for g in obj.vertex_groups}
    for v in obj.data.vertices:
        entries = sorted(((g.weight, g.group) for g in v.groups if g.weight > 0.0), reverse=True)
        keep = [e for e in entries[:count] if e[0] > 0.01] or entries[:1]
        total = sum(w for w, _ in keep) or 1.0
        for w, gi in entries:
            obj.vertex_groups[names[gi]].remove([v.index])
        for w, gi in keep:
            obj.vertex_groups[names[gi]].add([v.index], w / total, "REPLACE")


def split_by_slot(body):
    """Cuts the weighted body into one mesh per equipment slot area. Before cutting, the smooth normals
    of the whole body are frozen as custom normals so the cut edges shade the same on both sides."""
    mesh = body.data
    mesh.normals_split_custom_set_from_vertices([v.normal.copy() for v in mesh.vertices])
    parts = {}
    for slot in ("body_arms", "body_legs", "body_feet"):
        activate(body)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for poly in body.data.polygons:
            poly.select = face_slot_lookup(body, poly) == slot
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        new = [o for o in bpy.context.selected_objects if o is not body][0]
        new.name = slot
        new.data.name = slot
        parts[slot] = new
    body.name = "body_torso"
    body.data.name = "body_torso"
    parts["body_torso"] = body
    return parts


def face_slot_lookup(obj, poly):
    names = {g.index: g.name for g in obj.vertex_groups}
    totals = {}
    for vi in poly.vertices:
        for g in obj.data.vertices[vi].groups:
            slot = SLOT_OF_BONE.get(names[g.group], "body_torso")
            totals[slot] = totals.get(slot, 0.0) + g.weight
    return max(totals, key=totals.get) if totals else "body_torso"


# ---------------------------------------------------------------------------------------------
# Hands: palm + four 2-bone fingers + a thumb, low-poly, with exact weights so a fist closes cleanly.
# Written in the old adult-hand coordinates and mapped onto this body with H().
# ---------------------------------------------------------------------------------------------


def rounded_rect_ring(x, cy, cz, half_w, half_t, top_bulge=0.0):
    """8 points around the X axis: a rounded rectangle in Y-Z (palm cross-section). Back of the hand is +Z."""
    pts = []
    for angle in range(8):
        a = 2 * math.pi * angle / 8 + math.pi / 8
        y = math.cos(a)
        z = math.sin(a)
        y = math.copysign(abs(y) ** 0.6, y) * half_w
        z = math.copysign(abs(z) ** 0.8, z) * half_t + (top_bulge if z > 0 else 0.0)
        pts.append(Vector((x, cy + y, cz + z)))
    return pts


def circle_ring(center, direction, radius_y, radius_z, count=6):
    direction = direction.normalized()
    side = Vector((0, 1, 0))
    side = (side - direction * side.dot(direction)).normalized()
    up = direction.cross(side).normalized()
    if up.z < 0:
        up = -up
    pts = []
    for i in range(count):
        a = 2 * math.pi * i / count + math.pi / count
        pts.append(center + side * (math.cos(a) * radius_y) + up * (math.sin(a) * radius_z))
    return pts


def build_hand(builder, sign, side):
    """One hand into `builder`, palm down, fingers along +X (left) / -X (right)."""
    def m(p):
        q = H(p[0], p[1], p[2])
        return Vector((q[0] * sign, q[1], q[2]))

    hand, lower = side + "Hand", side + "LowerArm"
    z0 = OLD_ARM_Z
    palm = [
        (0.700, 0.000, 0.018, 0.014, {lower: 0.5, hand: 0.5}),
        (0.722, 0.002, 0.032, 0.018, {lower: 0.25, hand: 0.75}),
        (0.752, 0.003, 0.045, 0.020, {hand: 1.0}),
        (0.782, 0.003, 0.050, 0.019, {hand: 1.0}),
        (0.807, 0.003, 0.048, 0.015, {hand: 1.0}),
    ]
    rings = [[m(p) for p in rounded_rect_ring(x, cy, z0 + 0.001, w, t, 0.003)] for x, cy, w, t, _ in palm]
    builder.tube(rings if sign > 0 else [r[::-1] for r in rings], [p[4] for p in palm], cap_start=True, cap_end=True)
    for finger, offset, length in FINGERS:
        prox, inter = side + finger + "Proximal", side + finger + "Intermediate"
        r = 0.0122 if finger != "Little" else 0.0108
        s = FINGER_START
        stations = [
            (s - 0.016, 1.00, {hand: 1.0}),
            (s - 0.004, 1.06, {hand: 0.8, prox: 0.2}),
            (s + 0.007, 1.04, {hand: 0.2, prox: 0.8}),
            (s + length * 0.30, 0.97, {prox: 1.0}),
            (s + length * 0.55 - 0.005, 0.95, {prox: 0.8, inter: 0.2}),
            (s + length * 0.55 + 0.005, 0.93, {prox: 0.2, inter: 0.8}),
            (s + length * 0.82, 0.88, {inter: 1.0}),
            (s + length * 0.97, 0.62, {inter: 1.0}),
        ]
        rings = []
        for x, scale, _ in stations:
            ring = circle_ring(Vector((x, offset, z0)), Vector((1, 0, 0)), r * scale * 1.05, r * scale * 0.9)
            ring = [m(p) for p in ring]
            rings.append(ring if sign > 0 else ring[::-1])
        tip = (m((s + length + 0.002, offset, z0 - 0.001)), {inter: 1.0})
        builder.tube(rings, [st[2] for st in stations], cap_start=True, tip_end=tip)
    # thumb: rests half-closed under the front edge of the palm (the game never bends the thumb bones), so a
    # fist shows it lying along the curled index finger instead of sticking out; weighted to the thumb bones
    t1, t2 = side + "ThumbProximal", side + "ThumbDistal"
    path = [
        ((0.712, -0.018, z0 - 0.006), 0.0150, {hand: 1.0}),
        ((0.732, -0.036, z0 - 0.013), 0.0155, {hand: 0.6, t1: 0.4}),
        ((0.747, -0.046, z0 - 0.020), 0.0142, {t1: 1.0}),
        ((0.760, -0.052, z0 - 0.026), 0.0132, {t1: 0.5, t2: 0.5}),
        ((0.772, -0.055, z0 - 0.031), 0.0118, {t2: 1.0}),
        ((0.781, -0.056, z0 - 0.034), 0.0086, {t2: 1.0}),
    ]
    rings = []
    for i, (p, r, _) in enumerate(path):
        a = Vector(path[max(0, i - 1)][0])
        b = Vector(path[min(len(path) - 1, i + 1)][0])
        ring = circle_ring(Vector(p), b - a, r, r * 0.85)
        ring = [m(q) for q in ring]
        rings.append(ring if sign > 0 else ring[::-1])
    builder.tube(rings, [p[2] for p in path], cap_start=True, tip_end=(m((0.786, -0.057, z0 - 0.036)), {t2: 1.0}))


def build_hands(skin_mat, body):
    builder = MeshBuilder()
    for sign, side in ((1.0, "Left"), (-1.0, "Right")):
        build_hand(builder, sign, side)
    obj = builder.build("body_hands", [skin_mat])
    # wrist vertices take the weights of the nearest arm surface so the wrist bends with the arm
    names = {g.index: g.name for g in body.vertex_groups}
    wrist = [(v, body.matrix_world @ v.co) for v in body.data.vertices if abs(v.co.x) > H(0.66, 0, 0)[0]]
    for v in obj.data.vertices:
        if abs(v.co.x) > H(0.716, 0, 0)[0]:
            continue
        nearest = min(wrist, key=lambda item: (item[1] - v.co).length)[0]
        for g in list(v.groups):
            obj.vertex_groups[g.group].remove([v.index])
        for g in nearest.groups:
            name = names[g.group]
            group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
            group.add([v.index], g.weight, "REPLACE")
    return obj


# ---------------------------------------------------------------------------------------------
# Heads (face variants) and hair styles: customization parts, rigid on the Head bone
# ---------------------------------------------------------------------------------------------

# Face features are drawn into the texture, in metres on the front view of the head (x across, z up;
# eyes are mirrored). eye: centre x/z, half width/height, tilt (degrees, outer corner up), lash
# thickness; iris: half size and offset toward the nose; brow: centre, half width, arch, thickness, tilt.
FACE_ROUND = {
    "eye": {"x": 0.058, "z": 1.518, "w": 0.027, "h": 0.031, "low": 0.80, "tilt": 2.0, "lash": 0.0058},
    "iris": {"w": 0.0195, "h": 0.0260, "dx": -0.002, "dz": -0.002},
    "brow": {"x": 0.060, "z": 1.568, "w": 0.024, "arch": 0.005, "thick": 0.0030, "tilt": -3.0},
    "nose": {"z": 1.474}, "mouth": {"z": 1.436, "w": 0.012, "curve": 0.0025, "thick": 0.0026},
    "blush": {"x": 0.084, "z": 1.480, "r": 0.020, "amount": 0.22},
}
FACE_SHARP = {
    "eye": {"x": 0.059, "z": 1.517, "w": 0.030, "h": 0.023, "low": 0.70, "tilt": 11.0, "lash": 0.0070},
    "iris": {"w": 0.0185, "h": 0.0215, "dx": -0.002, "dz": -0.001},
    "brow": {"x": 0.062, "z": 1.559, "w": 0.028, "arch": 0.003, "thick": 0.0042, "tilt": 14.0},
    "nose": {"z": 1.472}, "mouth": {"z": 1.434, "w": 0.014, "curve": 0.0008, "thick": 0.0024},
    "blush": {"x": 0.084, "z": 1.478, "r": 0.018, "amount": 0.10},
}
HEADS = {
    # rx/ry/rz: half width/depth/height; jaw: how much the lower head narrows; jaw_power: high = square jaw
    "head_round": {"rx": 0.142, "ry": 0.155, "rz": 0.188, "jaw": 0.30, "jaw_power": 1.6, "chin": 0.10, "chin_flat": 0.05, "face_flat": 0.10,
                   "face": FACE_ROUND, "ear": "round"},
    "head_sharp": {"rx": 0.139, "ry": 0.155, "rz": 0.188, "jaw": 0.40, "jaw_power": 1.25, "chin": 0.14, "chin_flat": 0.0, "face_flat": 0.13,
                   "face": FACE_SHARP, "ear": "round"},
    # optional: the round face with pointed (elf) ears, as in the Flyff reference; not the default
    "head_elf": {"rx": 0.142, "ry": 0.155, "rz": 0.188, "jaw": 0.30, "jaw_power": 1.6, "chin": 0.10, "chin_flat": 0.05, "face_flat": 0.10,
                 "face": FACE_ROUND, "ear": "pointed"},
}
HEAD_CENTER = Vector((0, 0.004, 1.563))
HEAD_TEXTURE = 512


def head_point(params, theta, phi, inflate=0.0):
    """A point on the head surface. theta: 0 = top .. pi = bottom; phi: 0 = front (-Y), +pi/2 = left (+X)."""
    st, ct = math.sin(theta), math.cos(theta)
    dx, dy, dz = st * math.sin(phi), -st * math.cos(phi), ct
    x, y, z = dx * params["rx"], dy * params["ry"], dz * params["rz"]
    low = max(0.0, -ct)
    x *= 1.0 - params["jaw"] * low ** params["jaw_power"]
    if dy > 0:
        y *= 1.0 - 0.42 * low ** 1.2  # the back of the skull curves into the neck
        y *= 1.0 + 0.06 * max(0.0, ct) ** 0.5  # a rounder back of the head
    else:
        y *= 1.0 - params["face_flat"] * max(0.0, 1.0 - abs(ct) * 1.6)  # a flatter face
        y *= 1.0 - params["chin"] * low ** 2
    if ct > 0:
        z *= 1.0 - 0.10 * ct ** 6  # a slightly flatter crown, not an egg tip
    else:
        z *= 1.0 - params["chin_flat"] * low ** 3
    p = Vector((x, y, z)) * (1.0 + inflate)
    return HEAD_CENTER + p


def _piecewise(value, points):
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if value <= x1:
            return y0 + (y1 - y0) * (value - x0) / (x1 - x0)
    return points[-1][1]


def head_uv(theta, phi):
    """The head's texture layout: latitude/longitude, stretched so the face (front, eye to chin) gets
    most of the texels. The seam is at the back of the head (under the hair). v 0.13..1 (the strip
    below holds the ears)."""
    t = phi / math.pi  # -1..1, 0 = front
    u = 0.5 + 0.5 * math.copysign(abs(t) ** 0.62, t)
    v = _piecewise(theta, [(0.0, 1.0), (1.25, 0.80), (2.50, 0.24), (math.pi, 0.13)])
    return (u, v)


def build_head_mesh(name, params, skin_mat):
    """The head surface plus ears, with texture coordinates (the face is painted later)."""
    b = MeshBuilder()
    w = {"Head": 1.0}
    segments, rows = 22, 13
    rings = [[head_point(params, math.pi * r / rows, 2 * math.pi * s / segments) for s in range(segments)] for r in range(1, rows)]

    def uv(r, s, c):
        theta = math.pi * (r + 1) / rows
        phi = 2 * math.pi * s / segments
        if 2 * math.pi * c / segments > math.pi:
            phi -= 2 * math.pi  # faces past the back seam use the other edge of the texture
        return head_uv(min(math.pi, max(0.0, theta)), phi)

    b.tube(rings, [w] * len(rings), 0, tip_start=(head_point(params, 0.0, 0.0), w), tip_end=(head_point(params, math.pi, 0.0), w), uv=uv)
    for index, sign in enumerate((1.0, -1.0)):
        p, right, up, out = head_frame(params, 1.84, sign * 1.50)
        center = p - out * 0.006 + Vector((0, 0.010, 0))
        back = Vector((0, 1, 0))
        side_axis = out.cross(Vector((0, 0, 1))).normalized()
        deform = None
        if params["ear"] == "pointed":
            def deform(q, c=center, o=out):
                lift = max(0.0, (q - c).dot(Vector((0, 0, 1)))) / 0.030
                return q + (Vector((0, 0, 1)) * 0.65 + back * 0.55 + o * 0.70) * 0.070 * lift ** 2.2
        b.ellipsoid(center, (side_axis, Vector((0, 0, 1)), out), (0.022, 0.032, 0.012), w, 0, segments=8, rings=5,
                    uv=(0.03 + index * 0.5, 0.005, 0.47 + index * 0.5, 0.12), deform=deform)
    return b.build(name, [skin_mat])


def head_frame(params, theta, phi):
    """Surface point and (right, up, out) axes there, for placing features."""
    e = 0.01
    p = head_point(params, theta, phi)
    du = head_point(params, theta, phi + e) - head_point(params, theta, phi - e)
    dv = head_point(params, theta - e, phi) - head_point(params, theta + e, phi)
    out = du.cross(dv).normalized()
    if out.dot(p - HEAD_CENTER) < 0:
        out = -out
    up = (dv - out * dv.dot(out)).normalized()
    right = up.cross(out).normalized()
    return p, right, up, out


def eye_local(face, x, z):
    """Coordinates in an eye's own frame (x toward the outer corner, z up), for |x| of a face point."""
    eye = face["eye"]
    a = math.radians(eye["tilt"])
    dx, dz = x - eye["x"], z - eye["z"]
    return dx * math.cos(a) + dz * math.sin(a), -dx * math.sin(a) + dz * math.cos(a)


def eye_opening(face, ux, uz):
    """< 1 inside the visible eye (below the upper lash line), in the eye's frame."""
    eye = face["eye"]
    h = eye["h"] if uz > 0 else eye["h"] * eye["low"]
    return math.sqrt((ux / eye["w"]) ** 2 + (uz / h) ** 2)


def build_iris(head_obj, face, iris_mat):
    """The irises: flat fans laid on the face (1 mm out), shaped to the part of the iris inside the eye
    opening, with their own tintable material and texture (u, v 0..1 over the iris ellipse)."""
    b = MeshBuilder()
    w = {"Head": 1.0}
    depsgraph = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(head_obj, depsgraph)
    eye, iris = face["eye"], face["iris"]
    lash_cut = 1.0 - eye["lash"] * 0.35 / eye["h"]

    def on_face(x, z):
        hit, normal, _, _ = tree.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
        return hit + normal * 0.0015

    for sign in (1.0, -1.0):
        cx, cz = eye["x"] + iris["dx"], eye["z"] + iris["dz"]
        count = 20
        center = b.vert(on_face(sign * cx, cz), w)
        ring, inner = [], []
        for i in range(count):
            a = 2 * math.pi * i / count
            dx, dz = math.cos(a) * iris["w"], math.sin(a) * iris["h"]
            lo, hi = 0.0, 1.0  # shrink toward the centre until the point is inside the eye opening
            ux, uz = eye_local(face, cx + dx, cz + dz)

            def outside(ux, uz):  # under the upper lash line, or past the lower edge of the eye
                return eye_opening(face, ux, uz) > (lash_cut if uz > 0 else 1.0)

            if outside(ux, uz):
                for _ in range(24):
                    mid = (lo + hi) / 2
                    ux, uz = eye_local(face, cx + dx * mid, cz + dz * mid)
                    if outside(ux, uz):
                        hi = mid
                    else:
                        lo = mid
                dx, dz = dx * lo, dz * lo
            # an inner ring halfway keeps the fan close to the curved face (the skin must not poke through)
            for f, ring_ in ((0.5, inner), (1.0, ring)):
                ring_.append((b.vert(on_face(sign * (cx + dx * f), cz + dz * f), w), (0.5 + dx * f / (2 * iris["w"]), 0.5 + dz * f / (2 * iris["h"]))))
        for i in range(count):
            j = (i + 1) % count
            quads = [(ring[i], ring[j], inner[j], inner[i])]
            fans = [(inner[i], inner[j])]
            for q in quads:  # counter-clockwise seen from the front: facing out of the face
                order = q if sign > 0 else q[::-1]
                b.face([c[0] for c in order], 0, [c[1] for c in order])
            for a_, b_ in fans:
                order = (a_, b_) if sign > 0 else (b_, a_)
                b.face((order[0][0], order[1][0], center), 0, [order[0][1], order[1][1], (0.5, 0.5)])
    obj = b.build(head_obj.name + "_iris", [iris_mat], recalc=False)
    return obj


# ---------------------------------------------------------------------------------------------
# Baking and painting
# ---------------------------------------------------------------------------------------------


def bake_maps(objects, size, label):
    """Bakes surface position, normal and ambient occlusion of `objects` into their UV layout (Cycles),
    returns them as numpy arrays (size, size, 3) in Blender's pixel order (bottom row first)."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.bake.margin = 8
    scene.render.bake.margin_type = "EXTEND"
    scene.render.bake.use_clear = True
    image = bpy.data.images.new(label + "_bake", size, size, alpha=False, float_buffer=True)
    image.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new("bake_" + label)
    mat.use_nodes = True
    nt = mat.node_tree
    for node in list(nt.nodes):
        nt.nodes.remove(node)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 32
    ao.inputs["Distance"].default_value = 0.12
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    nt.nodes.active = tex
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    saved = {obj: list(obj.data.materials) for obj in objects}
    for obj in objects:
        for i in range(len(obj.data.materials)):
            obj.data.materials[i] = mat
    hidden = {obj: obj.hide_render for obj in scene.objects}
    for obj in scene.objects:
        obj.hide_render = obj not in objects
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    results = {}
    for kind, socket in (("position", geo.outputs["Position"]), ("normal", geo.outputs["Normal"]), ("ao", ao.outputs["AO"])):
        link_ = nt.links.new(socket, emit.inputs["Color"])
        bpy.ops.object.bake(type="EMIT")
        pixels = np.empty(size * size * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        results[kind] = pixels.reshape(size, size, 4)[..., :3].copy()
        nt.links.remove(link_)
    results["ao"] = results["ao"][..., 0]
    results["covered"] = np.linalg.norm(results["normal"], axis=-1) > 0.5  # the islands (and the bake margin)
    for obj, mats in saved.items():
        for i, m in enumerate(mats):
            obj.data.materials[i] = m
    for obj, value in hidden.items():
        obj.hide_render = value
    bpy.data.images.remove(image)
    bpy.data.materials.remove(mat)
    return results


def fill_holes(rgb, covered):
    """Fills the texels between the UV islands with the colours of the nearby islands (push-pull), so the
    smaller mip levels the game uses at a distance do not bleed a foreign colour into the edges."""
    size = rgb.shape[0]
    levels = [(rgb * covered[..., None], covered.astype(np.float32))]
    while levels[-1][1].shape[0] > 1:
        c, w = levels[-1]
        h = c.shape[0] // 2
        levels.append((c.reshape(h, 2, h, 2, 3).sum(axis=(1, 3)), w.reshape(h, 2, h, 2).sum(axis=(1, 3))))
    c, w = levels[-1]
    color = c / np.maximum(w, 1e-6)[..., None]
    for c, w in reversed(levels[:-1]):
        up = np.repeat(np.repeat(color, 2, axis=0), 2, axis=1)
        own = c / np.maximum(w, 1e-6)[..., None]
        a = np.clip(w, 0.0, 1.0)[..., None]
        color = own * a + up * (1.0 - a)
    assert color.shape[0] == size
    return color


def save_texture(name, rgb):
    """Writes an (h, w, 3) sRGB array (bottom row first) to art_source/characters/textures/<name>.png and
    returns it as a Blender image (packed, so the .glb carries it)."""
    h, w = rgb.shape[:2]
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(rgb, 0.0, 1.0)
    image = bpy.data.images.new(name, w, h, alpha=False)
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = os.path.join(TEXTURE_DIR, name + ".png")
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a + (np.asarray(b) - a) * t


def srgb(*c):
    return np.array(c, dtype=np.float32)


def brush_noise(pos, scale=1.0, seed=1):
    """Soft painterly value variation from the surface position (a few random waves), about -1..1."""
    rng = np.random.default_rng(seed)
    total = np.zeros(pos.shape[:-1], dtype=np.float32)
    for _ in range(7):
        direction = rng.normal(size=3)
        direction /= np.linalg.norm(direction)
        freq = rng.uniform(18.0, 60.0) * scale
        total += np.sin(pos @ (direction * freq) + rng.uniform(0, 6.28))
    return total / 7.0 * 1.6


LIGHT = np.array((0.30, -0.45, 0.84), dtype=np.float32) / np.linalg.norm((0.30, -0.45, 0.84))
SKIN_LIGHT = srgb(0.99, 0.88, 0.80)
SKIN = srgb(0.95, 0.77, 0.67)
SKIN_SHADE = srgb(0.85, 0.59, 0.53)
SKIN_DEEP = srgb(0.66, 0.40, 0.39)
BLUSH = srgb(0.98, 0.62, 0.62)
SHORTS_LIGHT = srgb(0.90, 0.93, 0.98)
SHORTS = srgb(0.78, 0.84, 0.93)
SHORTS_SHADE = srgb(0.57, 0.63, 0.76)
SHORTS_DEEP = srgb(0.38, 0.42, 0.56)


def paint_lit(pos, nrm, ao, light, base, shade, deep, seed):
    """The shared "painted" shading: a soft two-tone split from a top-front light, warm occlusion in the
    creases, a lighter top, and a little brush noise."""
    lam = np.clip(nrm @ LIGHT, -1.0, 1.0)
    col = mix(shade, base, smoothstep(-0.30, 0.45, lam))
    col = mix(col, light, smoothstep(0.70, 1.0, lam) * 0.55)
    occlusion = smoothstep(0.30, 0.95, ao)
    col = mix(deep, col, 0.30 + 0.70 * occlusion)
    col = col * (1.0 + 0.025 * brush_noise(pos, seed=seed))[..., None]
    return col


def gauss(pos, center, radius):
    d = pos - np.array(center, dtype=np.float32)
    return np.exp(-np.sum(d * d, axis=-1) / (radius * radius))


def paint_body(maps):
    pos, nrm, ao = maps["position"], maps["normal"], maps["ao"]
    col = paint_lit(pos, nrm, ao, SKIN_LIGHT, SKIN, SKIN_SHADE, SKIN_DEEP, seed=3)
    # warm blush on the joints (knees, elbows, knuckles, toes)
    flush = np.zeros(pos.shape[:-1], dtype=np.float32)
    for s in (1.0, -1.0):
        flush += gauss(pos, (s * 0.077, -0.035, 0.45), 0.035)
        flush += gauss(pos, (s * 0.32, 0.03, ARM_Z), 0.030)
        flush += gauss(pos, (s * H(0.80, 0, 0)[0], 0.0, ARM_Z + 0.01), 0.025) * 0.7
        flush += gauss(pos, (s * 0.079, -0.15, 0.02), 0.025) * 0.4
    col = mix(col, BLUSH, np.clip(flush, 0, 1) * 0.30)
    # the shorts
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    inside = smoothstep(SHORTS_HEM - 0.002, SHORTS_HEM + 0.002, z) * (1.0 - smoothstep(SHORTS_TOP - 0.002, SHORTS_TOP + 0.002, z))
    inside *= (np.abs(x) < 0.22).astype(np.float32)
    cloth = paint_lit(pos, nrm, ao, SHORTS_LIGHT, SHORTS, SHORTS_SHADE, SHORTS_DEEP, seed=5)
    # soft vertical folds on the legs of the shorts
    folds = np.sin(np.arctan2(y, np.abs(x) - 0.077) * 5.0 + z * 30.0)
    cloth = cloth * (1.0 - 0.05 * smoothstep(0.2, 1.0, folds) * smoothstep(0.80, SHORTS_HEM, z))[..., None]
    # waistband (lighter, with a dark line under it), hem line and the front seam
    band = smoothstep(SHORTS_TOP - 0.030, SHORTS_TOP - 0.027, z)
    cloth = mix(cloth, cloth * 0.8 + SHORTS_LIGHT * 0.25, band * 0.8)
    line = np.exp(-((z - (SHORTS_TOP - 0.030)) / 0.0025) ** 2)
    line += np.exp(-((z - (SHORTS_HEM + 0.006)) / 0.0022) ** 2) * 0.8
    seam = np.exp(-(x / 0.0025) ** 2) * (y < 0) * smoothstep(0.78, 0.80, z) * (1.0 - smoothstep(SHORTS_TOP - 0.034, SHORTS_TOP - 0.030, z))
    line = np.clip(line + seam * 0.7, 0, 1)
    cloth = mix(cloth, SHORTS_DEEP * 0.9, line * 0.55)
    col = mix(col, cloth, inside)
    return col


def paint_face(maps, params):
    """Skin like the body, then the face features drawn on the front of the head."""
    pos, nrm, ao = maps["position"], maps["normal"], maps["ao"]
    col = paint_lit(pos, nrm, ao, SKIN_LIGHT, SKIN, SKIN_SHADE, SKIN_DEEP, seed=7)
    face = params["face"]
    x, y, z = np.abs(pos[..., 0]), pos[..., 1], pos[..., 2]
    front = (y < HEAD_CENTER.y - 0.04).astype(np.float32)
    px = 0.0009  # about one texel in metres on the face: the width of the anti-aliased edges

    def cover(distance):
        return np.clip(0.5 - distance / px, 0.0, 1.0) * front

    def draw(color, distance, alpha=1.0):
        nonlocal col
        col = mix(col, srgb(*color), cover(distance) * alpha)

    # blush on the cheeks and a hint of the nose
    blush = face["blush"]
    col = mix(col, BLUSH, np.exp(-(((x - blush["x"]) / blush["r"]) ** 2 + ((z - blush["z"]) / (blush["r"] * 0.6)) ** 2)) * blush["amount"] * front)
    nz = face["nose"]["z"]
    col = mix(col, SKIN_SHADE * 0.92, np.exp(-((x / 0.0055) ** 2 + ((z - nz) / 0.0028) ** 2)) * 0.75 * front)
    col = mix(col, SKIN_LIGHT, np.exp(-((x / 0.006) ** 2 + ((z - nz - 0.010) / 0.008) ** 2)) * 0.25 * front)
    # mouth: a short curved line, a little lighter lower lip shadow
    mouth = face["mouth"]
    ux = x / mouth["w"]
    curve = z - (mouth["z"] + mouth["curve"] * ux ** 2)
    thick = mouth["thick"] * (1.0 - 0.55 * ux ** 2)
    draw((0.55, 0.25, 0.24), np.maximum(np.abs(curve) - thick / 2, (np.abs(x) - mouth["w"]) * 0.6), 0.9)
    col = mix(col, SKIN_SHADE, np.exp(-((x / (mouth["w"] * 0.7)) ** 2 + ((z - mouth["z"] + 0.0075) / 0.0025) ** 2)) * 0.35 * front)
    # eyes
    eye, iris = face["eye"], face["iris"]
    a = math.radians(eye["tilt"])
    dx, dz = x - eye["x"], z - eye["z"]
    ex, ez = dx * math.cos(a) + dz * math.sin(a), -dx * math.sin(a) + dz * math.cos(a)
    h = np.where(ez > 0, eye["h"], eye["h"] * eye["low"])
    q = np.sqrt((ex / eye["w"]) ** 2 + (ez / h) ** 2)
    edge = (q - 1.0) * np.minimum(eye["w"], h)
    # the white, shaded under the lid
    white = srgb(0.99, 0.98, 0.97) * (1.0 - 0.22 * smoothstep(-0.2, 0.9, ez / eye["h"]))[..., None]
    col = mix(col, white, cover(edge))
    # the iris as a dark base (the tinted iris mesh lies on top of it in the game)
    idx, idz = x - (eye["x"] + iris["dx"]), z - (eye["z"] + iris["dz"])
    qi = np.sqrt((idx / iris["w"]) ** 2 + (idz / iris["h"]) ** 2)
    draw((0.25, 0.17, 0.14), np.maximum((qi - 1.0) * iris["w"], edge))
    # upper lash line: thick, heavier toward the outer corner, with a small flick
    outer = np.clip(ex / eye["w"], -1.0, 1.0)
    lash = eye["lash"] * (0.65 + 0.55 * smoothstep(-0.6, 1.0, outer))
    upper = ez > -eye["h"] * (0.10 + 0.35 * smoothstep(0.3, 1.0, outer))
    lash_d = np.abs(edge - lash * 0.25) - lash * 0.55
    draw((0.14, 0.09, 0.09), np.where(upper, lash_d, 1.0))
    flick = np.sqrt(((ex - eye["w"] * 1.08) / (eye["w"] * 0.22)) ** 2 + ((ez - eye["h"] * 0.05 - (ex - eye["w"]) * 0.5) / (lash * 0.6)) ** 2)
    draw((0.14, 0.09, 0.09), (flick - 1.0) * lash * 0.6)
    # lower lash: a thin soft line on the outer half
    lower = (ez < 0) & (outer > -0.1)
    draw((0.45, 0.28, 0.26), np.where(lower, np.abs(edge - 0.0006) - 0.0006, 1.0), 0.55)
    # a faint lid crease above
    crease = np.abs((q - 1.0) * eye["h"] - 0.0055) - 0.0006
    draw((0.80, 0.55, 0.50), np.where((ez > eye["h"] * 0.25) & (np.abs(outer) < 0.75), crease, 1.0), 0.45)
    # brows
    brow = face["brow"]
    b = math.radians(brow["tilt"])
    bx0, bz0 = x - brow["x"], z - brow["z"]
    bx, bz = bx0 * math.cos(b) + bz0 * math.sin(b), -bx0 * math.sin(b) + bz0 * math.cos(b)
    t = np.clip(bx / brow["w"], -1.2, 1.2)
    arc = bz - brow["arch"] * (1.0 - t ** 2)
    taper = brow["thick"] * (1.0 - 0.45 * smoothstep(-0.2, 1.0, t))
    brow_d = np.maximum(np.abs(arc) - taper / 2, (np.abs(bx) - brow["w"]) * 0.8)
    draw((0.30, 0.20, 0.17), brow_d, 0.95)
    return col


def paint_iris(size=128):
    """The iris (neutral light grey, tinted by the eye colour) and its highlights (emission)."""
    v, u = np.mgrid[0:size, 0:size].astype(np.float32)
    u = (u + 0.5) / size * 2 - 1  # -1..1 across
    v = (v + 0.5) / size * 2 - 1  # -1..1 bottom to top
    r = np.sqrt(u * u + v * v)
    value = 0.52 + 0.48 * smoothstep(0.55, -0.85, v)  # dark under the lid, light at the bottom
    value *= 1.0 - 0.45 * smoothstep(0.72, 1.0, r)  # the darker rim
    rays = 0.5 + 0.5 * np.sin(np.arctan2(v, u) * 13.0)
    value *= 1.0 - 0.08 * rays * smoothstep(0.35, 0.8, r)
    pupil = np.sqrt((u / 0.36) ** 2 + ((v - 0.02) / 0.46) ** 2)
    value = value * smoothstep(0.92, 1.05, pupil) + 0.10 * (1.0 - smoothstep(0.92, 1.05, pupil))
    iris = np.repeat(value[..., None], 3, axis=2)
    glow = np.zeros_like(iris)
    big = np.sqrt(((u + 0.30) / 0.30) ** 2 + ((v - 0.38) / 0.24) ** 2)
    small = np.sqrt(((u - 0.38) / 0.12) ** 2 + ((v + 0.40) / 0.12) ** 2)
    shine = np.clip((1.0 - big) * 8.0, 0, 1) + np.clip((1.0 - small) * 8.0, 0, 1) * 0.85
    glow[...] = np.clip(shine, 0, 1)[..., None]
    return save_texture("iris", iris), save_texture("iris_glow", glow)


def paint_hair(size=256):
    """Neutral hair strands for every style: u across (tiles), v from the root (0) to the tip (1)."""
    v, u = np.mgrid[0:size, 0:size].astype(np.float32)
    u = (u + 0.5) / size
    v = (v + 0.5) / size
    rng = np.random.default_rng(11)
    streak = np.zeros_like(u)
    for _ in range(9):
        n = rng.integers(3, 23)
        streak += np.sin(2 * math.pi * n * u + rng.uniform(0, 6.28) + v * rng.uniform(-2.0, 2.0)) / rng.uniform(1.0, 2.5)
    streak /= np.abs(streak).max()
    value = 0.80 + 0.10 * streak
    value *= 0.70 + 0.30 * smoothstep(0.0, 0.22, v)  # darker at the roots
    value += 0.20 * np.exp(-((v - 0.40) / 0.07) ** 2) * (0.55 + 0.45 * smoothstep(-0.3, 0.8, streak))  # the shine band
    value *= 1.0 - 0.14 * smoothstep(0.80, 1.0, v)
    value *= 1.0 - 0.22 * smoothstep(0.55, 1.0, np.cos(4 * math.pi * u))  # dark edges between the locks
    hair = np.stack([value, value * 0.985, value * 0.97], axis=-1)
    return save_texture("hair", np.clip(hair, 0, 1))


# ---------------------------------------------------------------------------------------------
# Hair: a cap over the skull plus locks (tapered, slightly flat strands that follow the head and
# flare out to pointed tips). No colour of its own: "hair_tint" is tinted by data/cosmetics/hair_colors.json.
# ---------------------------------------------------------------------------------------------
HAIR_TINT_MATERIAL = "hair_tint"
EYE_TINT_MATERIAL = "eye_tint"
COSMETICS_DIR = os.path.join(PROJECT, "data", "cosmetics")
HAIR_HEAD = dict(HEADS["head_round"])
HAIR_HEAD["rx"] *= 1.03  # cover the wider of the heads


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def cosmetic_color(file_name, color_id=None):
    """(linear r, g, b) of a colour from data/cosmetics/<file_name> (the file's default one when no id)."""
    with open(os.path.join(COSMETICS_DIR, file_name), encoding="utf-8") as handle:
        data = json.load(handle)
    color_id = color_id or data["default"]
    hex_value = next(c["color"] for c in data["colors"] if c["id"] == color_id).lstrip("#")
    return tuple(srgb_to_linear(int(hex_value[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def hair_color(color_id=None):
    return cosmetic_color("hair_colors.json", color_id)


def eye_color(color_id=None):
    return cosmetic_color("eye_colors.json", color_id)


def hair_cap(b, front, side, back, thick, rows=7, segments=20):
    """The cap: the skull surface pushed out by `thick`, down to a hairline (theta per direction)."""
    w = {"Head": 1.0}

    def hairline(phi):
        c = math.cos(phi)
        return side + (front - side) * max(0.0, c) ** 1.5 + (back - side) * max(0.0, -c) ** 0.6

    rings = []
    for r in range(1, rows + 1):
        t = r / rows
        rings.append([head_point(HAIR_HEAD, hairline(2 * math.pi * s / segments) * t, 2 * math.pi * s / segments, thick * (1.0 - 0.35 * t ** 2)) for s in range(segments)])
    rings.append([head_point(HAIR_HEAD, hairline(2 * math.pi * s / segments) - 0.08, 2 * math.pi * s / segments, -0.01) for s in range(segments)])

    def uv(r, s, c):
        return (s / segments * 5.0, 0.05 + 0.75 * (r + 1) / (rows + 1))

    b.tube(rings, [w] * len(rings), 0, tip_start=(head_point(HAIR_HEAD, 0.0, 0.0, thick), w), cap_end=False, uv=uv)


def lock_along(b, points, normals, width, thick, weights):
    """A lock through `points` (root to tip) with a flattened diamond section facing `normals`;
    it narrows to a point. weights: one dict per point."""
    rings = []
    count = len(points)
    for i, (p, n) in enumerate(zip(points, normals)):
        a = points[max(0, i - 1)]
        c = points[min(count - 1, i + 1)]
        tangent = (c - a).normalized()
        n = (n - tangent * n.dot(tangent)).normalized()
        side = tangent.cross(n).normalized()
        t = i / (count - 1)
        wd = width * (1.0 - 0.80 * t ** 1.3) * (0.85 + 0.15 * math.sin(math.pi * min(1.0, t * 1.6)))
        th = thick * (1.0 - 0.6 * t)
        rings.append([p - side * wd, p + n * th, p + side * wd, p - n * th * 0.4])
    tip = points[-1] + (points[-1] - points[-2]) * 0.6

    def uv(r, s, c):
        return (s / 4.0, min(1.0, 0.12 + 0.88 * max(0, r) / count))

    b.tube(rings[:-1] + [rings[-1]], weights, 0, cap_start=True, tip_end=(tip, weights[-1]), uv=uv)


def surface_lock(b, theta0, phi0, theta1, phi1, width, lift0=0.03, lift1=0.10, thick=0.012, bend=1.0, steps=5, weights=None):
    """A lock lying on the head from (theta0, phi0) to (theta1, phi1), lifting off the skull from lift0 to lift1
    (fractions of the head size); bend > 1 keeps it close to the head longer before it flares."""
    points, normals = [], []
    for i in range(steps):
        t = i / (steps - 1)
        theta = theta0 + (theta1 - theta0) * t
        phi = phi0 + (phi1 - phi0) * t
        lift = lift0 + (lift1 - lift0) * t ** bend
        p = head_point(HAIR_HEAD, theta, phi, lift)
        points.append(p)
        normals.append((p - HEAD_CENTER).normalized())
    lock_along(b, points, normals, width, thick, weights or [{"Head": 1.0}] * steps)


def hair_crop(b):
    """Short spiky hair (the default): a fringe of pointed locks over the forehead, tufts on the crown,
    side locks in front of the ears and spikes at the nape."""
    hair_cap(b, front=1.20, side=1.62, back=2.55, thick=0.075)
    for phi, end, sweep in ((-0.62, 1.42, -0.06), (-0.33, 1.48, -0.04), (-0.04, 1.45, 0.0), (0.26, 1.49, 0.05), (0.55, 1.42, 0.08)):
        surface_lock(b, 0.55, phi * 0.8, end, phi + sweep, 0.048, lift0=0.07, lift1=0.075, bend=1.5)
    for s in (1.0, -1.0):
        surface_lock(b, 0.95, s * 0.95, 1.82, s * 1.08, 0.040, lift0=0.07, lift1=0.06)
        surface_lock(b, 1.00, s * 1.30, 1.74, s * 1.42, 0.040, lift0=0.07, lift1=0.10)
        surface_lock(b, 1.05, s * 1.75, 2.12, s * 1.85, 0.050, lift0=0.07, lift1=0.13)
        surface_lock(b, 1.05, s * 2.20, 2.38, s * 2.25, 0.052, lift0=0.07, lift1=0.13)
        surface_lock(b, 1.05, s * 2.70, 2.48, s * 2.72, 0.052, lift0=0.07, lift1=0.12)
    surface_lock(b, 1.05, math.pi, 2.50, math.pi, 0.054, lift0=0.07, lift1=0.12)
    # crown: layered locks flowing back from the whorl, flicking up a little at the ends
    for phi0, phi1, theta1, lift in ((0.25, 0.55, 1.00, 0.13), (-0.30, -0.60, 1.05, 0.13), (1.10, 1.45, 1.10, 0.12), (-1.10, -1.45, 1.10, 0.12),
                                     (2.00, 2.30, 1.25, 0.14), (-2.00, -2.30, 1.25, 0.14), (math.pi, math.pi, 1.30, 0.15)):
        surface_lock(b, 0.10, phi0, theta1, phi1, 0.058, lift0=0.075, lift1=lift, thick=0.016, bend=2.2)


def hair_ponytail(b):
    """Longer hair tied back: side-swept bangs, long locks framing the face and a ponytail on the hair bones."""
    hair_cap(b, front=1.15, side=1.75, back=2.65, thick=0.055)
    for phi, end, sweep in ((-0.50, 1.52, 0.35), (-0.18, 1.58, 0.32), (0.12, 1.55, 0.28), (0.42, 1.42, 0.22)):
        surface_lock(b, 0.50, phi - 0.1, end, phi + sweep, 0.050, lift0=0.05, lift1=0.06, bend=1.5)
    for s in (1.0, -1.0):
        surface_lock(b, 0.95, s * 0.90, 2.30, s * 1.00, 0.040, lift0=0.05, lift1=0.05, steps=6)
        surface_lock(b, 1.00, s * 1.25, 2.10, s * 1.35, 0.040, lift0=0.05, lift1=0.07, steps=6)
    # the tie and the tail (three locks splaying a little, on HairBack1/HairBack2)
    tie = Vector((0, 0.168, 1.637))
    b.ellipsoid(tie, (Vector((1, 0, 0)), Vector((0, 0.3, 0.95)).normalized(), Vector((0, 0.95, -0.3)).normalized()), (0.026, 0.014, 0.024),
                {"Head": 1.0}, 0, segments=8, rings=4, uv=(0.0, 0.05, 1.0, 0.15))
    for dx, length in ((-0.016, 1.0), (0.0, 1.08), (0.016, 0.95)):
        points = [tie + Vector(o) for o in ((dx * 0.5, 0.010, 0.0), (dx, 0.045, -0.06), (dx * 1.4, 0.055, -0.14 * length),
                                             (dx * 1.8, 0.045, -0.22 * length), (dx * 2.2, 0.035, -0.29 * length))]
        weights = [{"Head": 0.6, "HairBack1": 0.4}, {"HairBack1": 1.0}, {"HairBack1": 0.5, "HairBack2": 0.5}, {"HairBack2": 1.0}, {"HairBack2": 1.0}]
        lock_along(b, points, [Vector((0, 1, 0))] * len(points), 0.042, 0.018, weights)


def hair_topknot(b):
    """Hair pulled up into a samurai-style knot: a smooth cap, two thin strands framing the face, a bun
    on the crown with a short spiky tail."""
    hair_cap(b, front=1.05, side=1.58, back=2.62, thick=0.050)
    for s in (1.0, -1.0):
        surface_lock(b, 1.0, s * 0.62, 1.95, s * 0.70, 0.024, lift0=0.04, lift1=0.05, steps=5)
        surface_lock(b, 1.1, s * 1.45, 1.72, s * 1.55, 0.034, lift0=0.04, lift1=0.06)
    bun = Vector((0, 0.04, 1.780))
    b.ellipsoid(bun, (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0))), (0.042, 0.036, 0.042), {"Head": 1.0}, 0,
                segments=10, rings=6, uv=(0.0, 0.1, 2.0, 0.7))
    b.ellipsoid(Vector((0, 0.036, 1.747)), (Vector((1, 0, 0)), Vector((0, 0, 1)), Vector((0, -1, 0))), (0.032, 0.010, 0.032),
                {"Head": 1.0}, 0, segments=8, rings=3, uv=(0.0, 0.02, 1.0, 0.1))
    for dx, up in ((-0.012, 0.010), (0.012, 0.004), (0.0, 0.020)):
        points = [bun + Vector(o) for o in ((dx, 0.030, 0.012 + up), (dx * 1.5, 0.065, 0.018 + up), (dx * 2.2, 0.095, 0.006 + up), (dx * 2.8, 0.115, -0.015 + up))]
        lock_along(b, points, [Vector((0, 0, 1))] * len(points), 0.022, 0.010, [{"Head": 1.0}] * len(points))


HAIRS = {"hair_crop": hair_crop, "hair_ponytail": hair_ponytail, "hair_topknot": hair_topknot}


def build_hair(name, style, hair_mat):
    b = MeshBuilder()
    style(b)
    return b.build(name, [hair_mat])


# ---------------------------------------------------------------------------------------------
# Previews
# ---------------------------------------------------------------------------------------------

BACKGROUND = (0.16, 0.18, 0.22)


def setup_render(width=720, height=900):
    scene = bpy.context.scene
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    use_eevee()
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    # the camera sees the dark preview background; the light around the character is a brighter grey
    path = nt.nodes.new("ShaderNodeLightPath")
    fill = nt.nodes.new("ShaderNodeBackground")
    fill.inputs["Color"].default_value = (0.55, 0.57, 0.62, 1.0)
    fill.inputs["Strength"].default_value = 1.0
    bg.inputs["Color"].default_value = (*[srgb_to_linear(c) for c in BACKGROUND], 1.0)
    mixer = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(path.outputs["Is Camera Ray"], mixer.inputs[0])
    nt.links.new(fill.outputs[0], mixer.inputs[1])
    nt.links.new(bg.outputs[0], mixer.inputs[2])
    nt.links.new(mixer.outputs[0], nt.nodes["World Output"].inputs["Surface"])
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 2.6
    sun = link(bpy.data.objects.new("Sun", sun_data))
    sun.rotation_euler = (math.radians(40), math.radians(-18), math.radians(-25))
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_obj = link(bpy.data.objects.new("Cam", cam_data))
    scene.camera = cam_obj
    return cam_obj


def use_eevee():
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.eevee.taa_render_samples = 16


def use_workbench():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.background_type = "VIEWPORT"
    shading.background_color = BACKGROUND
    scene.display.render_aa = "8"


def shoot(cam, name, direction, ortho_scale=2.2, center=(0, 0, 0.9), xray=False):
    """direction: vector from the character toward the camera."""
    direction = Vector(direction).normalized()
    center = Vector(center)
    cam.data.ortho_scale = ortho_scale
    cam.location = center + direction * 8.0
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene = bpy.context.scene
    if xray:
        use_workbench()
        scene.display.shading.show_xray = True
        scene.display.shading.xray_alpha = 0.35
    scene.render.filepath = os.path.join(PREVIEW_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    if xray:
        scene.display.shading.show_xray = False
        use_eevee()


def rotate_bone_world(armature, bone_name, axis, degrees):
    """Rotates a pose bone around its own head about a world axis (so poses read in world terms)."""
    pb = armature.pose.bones[bone_name]
    matrix = pb.matrix.copy()
    head = matrix.translation.copy()
    rotation = Matrix.Rotation(math.radians(degrees), 4, axis)
    pb.matrix = Matrix.Translation(head) @ rotation @ Matrix.Translation(-head) @ matrix
    bpy.context.view_layer.update()


def clear_pose(armature):
    for pb in armature.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()


def curl_fingers(armature, degrees, thumb=0.0):
    """Closes the hands the way the game does (client/character_model.gd): each finger bone turns
    about the body's front axis in its rest frame, toward the palm (which faces down in the T-pose)."""
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        for finger, _, _ in FINGERS:
            for part, factor in (("Proximal", 0.8), ("Intermediate", 1.0)):
                pb = armature.pose.bones[side + finger + part]
                axis = pb.bone.matrix_local.to_3x3().inverted() @ Vector((0, 1, 0))
                pb.rotation_quaternion = pb.rotation_quaternion @ Matrix.Rotation(math.radians(sign * degrees * factor), 3, axis).to_quaternion()
        if thumb:
            for part in ("ThumbProximal", "ThumbDistal"):
                pb = armature.pose.bones[side + part]
                axis = pb.bone.matrix_local.to_3x3().inverted() @ Vector((0, 1, 0))
                pb.rotation_quaternion = pb.rotation_quaternion @ Matrix.Rotation(math.radians(sign * thumb), 3, axis).to_quaternion()
    bpy.context.view_layer.update()


def make_skeleton_view():
    """Visible bones for the preview: a sphere per joint and a stick per bone, coloured by kind."""
    colors = {"core": (0.3, 0.7, 1.0), "finger": (1.0, 0.5, 0.8), "extra": (0.8, 0.6, 1.0), "attach": (1.0, 0.8, 0.2)}
    objects = []
    for name, parent, head, tail, kind in BONES:
        mat = material("sk_" + kind, colors[kind])
        direction = tail - head
        if direction.length < 1e-5:
            continue
        bm = bmesh.new()
        radius = 0.006 if kind != "core" else 0.012
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius, radius2=radius * 0.4, depth=direction.length)
        quat = Vector((0, 0, 1)).rotation_difference(direction)
        for v in bm.verts:
            v.co = quat @ v.co + (head + tail) * 0.5
        bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=radius * 1.6)
        mesh = bpy.data.meshes.new("stick_" + name)
        bm.to_mesh(mesh)
        bm.free()
        obj = link(bpy.data.objects.new("stick_" + name, mesh))
        obj.data.materials.append(mat)
        objects.append(obj)
    return objects


def preview_sword(armature):
    """A plain sword in the right hand for the grip check: grip along the fist's hole (front-back)."""
    bm = bmesh.new()
    for center, size in (((0, 0, 0), (0.03, 0.20, 0.03)), ((0, -0.11, 0), (0.16, 0.025, 0.035)), ((0, -0.52, 0), (0.05, 0.78, 0.012))):
        geom = bmesh.ops.create_cube(bm, size=1.0)
        for v in geom["verts"]:
            v.co = Vector((center[0] + v.co.x * size[0], center[1] + v.co.y * size[1], center[2] + v.co.z * size[2]))
    mesh = bpy.data.meshes.new("preview_sword")
    bm.to_mesh(mesh)
    bm.free()
    obj = link(bpy.data.objects.new("preview_sword", mesh))
    obj.data.materials.append(material("steel", (0.75, 0.78, 0.82), 0.3))
    grip = H(0.815, -0.01, OLD_ARM_Z - 0.032)
    obj.location = Vector((-grip[0], grip[1], grip[2]))
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = "RightHand"
    bpy.context.view_layer.update()
    pb = armature.pose.bones["RightHand"]
    obj.matrix_parent_inverse = (armature.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.length, 0))).inverted()
    return obj


def pose_arms_down(arm):
    """A relaxed standing pose (arms by the sides), like the Flyff inventory doll."""
    rotate_bone_world(arm, "LeftUpperArm", (0, 1, 0), 72)
    rotate_bone_world(arm, "RightUpperArm", (0, 1, 0), -72)
    rotate_bone_world(arm, "LeftLowerArm", (0, 1, 0), 8)
    rotate_bone_world(arm, "RightLowerArm", (0, 1, 0), -8)
    curl_fingers(arm, 30)


def pose_idle(arm):
    rotate_bone_world(arm, "Hips", (0, 0, 1), 18)
    rotate_bone_world(arm, "Chest", (0, 0, 1), -14)
    rotate_bone_world(arm, "Spine", (1, 0, 0), 5)
    rotate_bone_world(arm, "LeftUpperLeg", (1, 0, 0), -18)
    rotate_bone_world(arm, "LeftLowerLeg", (1, 0, 0), 26)
    rotate_bone_world(arm, "RightUpperLeg", (1, 0, 0), 10)
    rotate_bone_world(arm, "RightLowerLeg", (1, 0, 0), 18)
    rotate_bone_world(arm, "LeftUpperArm", (0, 1, 0), 68)
    rotate_bone_world(arm, "RightUpperArm", (0, 1, 0), -68)
    rotate_bone_world(arm, "LeftUpperArm", (1, 0, 0), -22)
    rotate_bone_world(arm, "RightUpperArm", (1, 0, 0), -22)
    rotate_bone_world(arm, "LeftLowerArm", (1, 0, 0), -95)
    rotate_bone_world(arm, "RightLowerArm", (1, 0, 0), -95)
    curl_fingers(arm, 78)


def pose_run(arm):
    rotate_bone_world(arm, "Spine", (1, 0, 0), 14)
    rotate_bone_world(arm, "LeftUpperLeg", (1, 0, 0), -58)
    rotate_bone_world(arm, "LeftLowerLeg", (1, 0, 0), 40)
    rotate_bone_world(arm, "RightUpperLeg", (1, 0, 0), 34)
    rotate_bone_world(arm, "RightLowerLeg", (1, 0, 0), 90)
    rotate_bone_world(arm, "LeftUpperArm", (0, 1, 0), 78)
    rotate_bone_world(arm, "RightUpperArm", (0, 1, 0), -78)
    rotate_bone_world(arm, "LeftUpperArm", (1, 0, 0), 45)
    rotate_bone_world(arm, "RightUpperArm", (1, 0, 0), -55)
    rotate_bone_world(arm, "LeftLowerArm", (1, 0, 0), -60)
    rotate_bone_world(arm, "RightLowerArm", (1, 0, 0), -100)
    curl_fingers(arm, 50)


def pose_punch(arm):
    rotate_bone_world(arm, "Hips", (0, 0, 1), 30)
    rotate_bone_world(arm, "Chest", (0, 0, 1), -50)
    rotate_bone_world(arm, "LeftUpperLeg", (1, 0, 0), -40)
    rotate_bone_world(arm, "LeftLowerLeg", (1, 0, 0), 45)
    rotate_bone_world(arm, "RightUpperLeg", (1, 0, 0), 28)
    rotate_bone_world(arm, "RightLowerLeg", (1, 0, 0), 35)
    rotate_bone_world(arm, "LeftUpperArm", (0, 1, 0), 75)
    rotate_bone_world(arm, "RightUpperArm", (0, 1, 0), -75)
    rotate_bone_world(arm, "LeftUpperArm", (1, 0, 0), -90)
    rotate_bone_world(arm, "LeftLowerArm", (1, 0, 0), -5)
    rotate_bone_world(arm, "RightUpperArm", (1, 0, 0), -20)
    rotate_bone_world(arm, "RightLowerArm", (1, 0, 0), -120)
    curl_fingers(arm, 80)


def pose_big_swing(arm):
    # the wind-up of a big overhead swing: both arms high above the head, torso arched back
    rotate_bone_world(arm, "Spine", (1, 0, 0), -12)
    rotate_bone_world(arm, "Chest", (0, 0, 1), -20)
    rotate_bone_world(arm, "LeftUpperLeg", (1, 0, 0), -30)
    rotate_bone_world(arm, "LeftLowerLeg", (1, 0, 0), 30)
    rotate_bone_world(arm, "RightUpperLeg", (1, 0, 0), 18)
    rotate_bone_world(arm, "RightLowerLeg", (1, 0, 0), 20)
    rotate_bone_world(arm, "LeftUpperArm", (0, 1, 0), 80)
    rotate_bone_world(arm, "RightUpperArm", (0, 1, 0), -80)
    rotate_bone_world(arm, "LeftUpperArm", (1, 0, 0), -165)
    rotate_bone_world(arm, "RightUpperArm", (1, 0, 0), -165)
    rotate_bone_world(arm, "LeftLowerArm", (1, 0, 0), -30)
    rotate_bone_world(arm, "RightLowerArm", (1, 0, 0), -30)
    curl_fingers(arm, 72)


def show_only(objects, everything):
    for obj in everything:
        obj.hide_render = obj not in objects


HEAD_VIEW = {"ortho_scale": 0.52, "center": (0, 0, 1.565)}


def render_previews(armature, body_parts, heads, hairs):
    cam = setup_render()
    everything = list(body_parts.values()) + list(heads.values()) + list(hairs.values())
    default = list(body_parts.values()) + [heads["head_round"], hairs["hair_crop"]]
    show_only(default, everything)
    # 1. the body in the T-pose
    shoot(cam, "01_body_front", (0, -1, 0))
    shoot(cam, "02_body_side", (1, 0, 0))
    shoot(cam, "03_body_three_quarter", (-0.7, -1, 0.15))
    shoot(cam, "04_top_down", (0, -1, 1.1), ortho_scale=2.0)  # like the game's high camera
    # 2. the skeleton over the translucent body
    sticks = make_skeleton_view()
    shoot(cam, "05_skeleton_front", (0, -1, 0), xray=True)
    for obj in sticks:
        bpy.data.objects.remove(obj, do_unlink=True)
    # 3. hands: open, fist, gripping a sword
    clear_pose(armature)
    hand = H(0.77, -0.01, OLD_ARM_Z)
    shoot(cam, "06_hand_open", (0.3, -0.6, 1), ortho_scale=0.30 * HS, center=hand)
    curl_fingers(armature, 78)
    fist = H(0.78, -0.02, OLD_ARM_Z - 0.02)
    shoot(cam, "07_hand_fist", (0.6, -1, 0.15), ortho_scale=0.30 * HS, center=fist)
    clear_pose(armature)
    curl_fingers(armature, 66)
    sword = preview_sword(armature)
    grip = H(0.80, -0.06, OLD_ARM_Z - 0.03)
    shoot(cam, "08_hand_grip", (-0.5, -1, 0.35), ortho_scale=0.42 * HS, center=(-grip[0], grip[1], grip[2]))
    # 4. poses (seam check at the hips, shoulders and neck)
    for index, (name, pose, view) in enumerate((
            ("idle", pose_idle, (-0.6, -1, 0.1)), ("run", pose_run, (1, -0.15, 0.1)),
            ("punch", pose_punch, (-1, -0.3, 0.1)), ("big_swing", pose_big_swing, (-0.7, -1, 0.2)))):
        clear_pose(armature)
        pose(armature)
        sword.hide_render = name != "big_swing"
        shoot(cam, f"{10 + index}_pose_{name}", view)
        shoot(cam, f"{14 + index}_pose_{name}_top", (0, -1, 1.1), ortho_scale=2.0)
    bpy.data.objects.remove(sword, do_unlink=True)
    # 5. the Flyff-style bare body: arms down, close views
    clear_pose(armature)
    pose_arms_down(armature)
    shoot(cam, "30_flyff_front", (0, -1, 0.08), ortho_scale=1.95, center=(0, 0, 0.9))
    shoot(cam, "31_flyff_three_quarter", (-0.75, -1, 0.12), ortho_scale=1.95, center=(0, 0, 0.9))
    shoot(cam, "32_flyff_face", (0, -1, 0.04), ortho_scale=0.42, center=(0, 0, 1.55))
    shoot(cam, "33_flyff_face_three_quarter", (-0.8, -1, 0.1), ortho_scale=0.46, center=(0, 0, 1.555))
    shoot(cam, "34_flyff_back", (0.3, 1, 0.1), ortho_scale=1.95, center=(0, 0, 0.9))
    shoot(cam, "35_flyff_game_angle", (0, -1, 1.35), ortho_scale=1.9, center=(0, 0, 0.9))
    show_only(list(body_parts.values()) + [heads["head_elf"], hairs["hair_topknot"]], everything)
    shoot(cam, "36_flyff_elf_ears", (-0.8, -1, 0.1), ortho_scale=0.50, center=(0, 0, 1.565))
    for index, name in enumerate(hairs):
        show_only(list(body_parts.values()) + [heads["head_round"], hairs[name]], everything)
        shoot(cam, f"37_flyff_hair_{name}_front", (-0.45, -1, 0.15), **HEAD_VIEW)
        shoot(cam, f"37_flyff_hair_{name}_back", (0.6, 1, 0.3), **HEAD_VIEW)
    clear_pose(armature)
    # 6. the head and hair parts: every head with every hair, front and from the game's high angle
    combos = [(h, r) for h in heads for r in hairs]
    for index, (head_name, hair_name) in enumerate(combos):
        show_only([heads[head_name], hairs[hair_name]], everything)
        shoot(cam, f"20_parts_{index}_front", (-0.35, -1, 0.1), **HEAD_VIEW)
        shoot(cam, f"21_parts_{index}_high", (0, -1, 1.0), **HEAD_VIEW)
    show_only(default, everything)


def render_hair_colors(heads, hairs, hair_tint, hair_default, everything):
    """Every hair style in a few palette colours (tinting the neutral hair the way the game will), from the
    front and from the game's high camera angle: preview/22_hair_<style>_<colour>_<view>.png."""
    cam = bpy.context.scene.camera
    with open(os.path.join(COSMETICS_DIR, "hair_colors.json"), encoding="utf-8") as handle:
        color_ids = [c["id"] for c in json.load(handle)["colors"]]
    shown = [c for c in ("black", "brown", "blonde", "silver", "ink_blue") if c in color_ids]
    for name, obj in hairs.items():
        obj.data.materials[0] = hair_tint
        show_only([heads["head_round"], obj], everything)
        for color_id in shown:
            set_tint(hair_tint, hair_color(color_id))
            shoot(cam, f"22_hair_{name}_{color_id}_front", (-0.35, -1, 0.1), **HEAD_VIEW)
            shoot(cam, f"22_hair_{name}_{color_id}_high", (0, -1, 1.0), **HEAD_VIEW)
        obj.data.materials[0] = hair_default
    set_tint(hair_tint, (1.0, 1.0, 1.0))


def render_eye_colors(heads, hairs, eye_tint, everything):
    """The faces in every eye colour (tinting the neutral iris the way the game will), front close-ups:
    preview/23_eyes_<head>_<colour>.png, plus one shot from the game's high angle."""
    cam = bpy.context.scene.camera
    with open(os.path.join(COSMETICS_DIR, "eye_colors.json"), encoding="utf-8") as handle:
        color_ids = [c["id"] for c in json.load(handle)["colors"]]
    for name in ("head_round", "head_sharp"):
        obj = heads[name]
        saved = obj.data.materials[1]
        obj.data.materials[1] = eye_tint
        show_only([obj, hairs["hair_crop"]], everything)
        for color_id in color_ids:
            set_tint(eye_tint, eye_color(color_id))
            shoot(cam, f"23_eyes_{name}_{color_id}", (0, -1, 0.04), ortho_scale=0.20, center=(0, -0.05, 1.51))
        if name == "head_round":
            shoot(cam, "23_eyes_head_round_high", (0, -1, 1.0), **HEAD_VIEW)
        obj.data.materials[1] = saved
    set_tint(eye_tint, (1.0, 1.0, 1.0))


# ---------------------------------------------------------------------------------------------


def export_glb(path, armature, objects):
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_skins=True,
                              export_animations=False, export_apply=False, export_yup=True, export_image_format="AUTO")


def uv_unwrap(objects):
    """One shared UV layout for the body and hands (Smart UV Project, packed together)."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(72), island_margin=0.016, scale_to_bounds=True)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin=0.016)  # tighter than smart project's own packing
    bpy.ops.object.mode_set(mode="OBJECT")


def main():
    reset_scene()
    placeholder = material("tmp_skin", (0.98, 0.83, 0.75))
    armature = build_armature()

    # body + hands: build, weight, unwrap, bake and paint, then cut into the slot meshes
    body = build_body_mesh(placeholder)
    heat_weights(body, armature)
    limit_weights(body)
    hands = build_hands(placeholder, body)
    bind(hands, armature)
    uv_unwrap([body, hands])
    maps = bake_maps([body, hands], 512, "body")
    body_image = save_texture("body_skin", fill_holes(paint_body(maps), maps["covered"]))
    skin = textured_material("skin", body_image)
    for obj in (body, hands):
        obj.data.materials[0] = skin
    bpy.data.materials.remove(placeholder)
    body_parts = split_by_slot(body)
    body_parts["body_hands"] = hands

    # heads: surface + ears, baked and painted per face, then the tintable irises joined in
    iris_image, glow_image = paint_iris()
    eye_tint = textured_material(EYE_TINT_MATERIAL, iris_image, tint=(1.0, 1.0, 1.0), emission=glow_image, roughness=0.3)
    eye_default = textured_material("eye_default", iris_image, tint=eye_color(), emission=glow_image, roughness=0.3)
    heads = {}
    for name, params in HEADS.items():
        head = build_head_mesh(name, params, material("tmp_" + name, (1, 1, 1)))
        maps = bake_maps([head], HEAD_TEXTURE, name)
        image = save_texture(name + "_face", fill_holes(paint_face(maps, params), maps["covered"]))
        head.data.materials[0] = textured_material(name + "_skin", image)
        iris = build_iris(head, params["face"], eye_tint)
        activate(head)
        iris.select_set(True)
        bpy.ops.object.join()
        bind(head, armature)
        heads[name] = head

    hair_image = paint_hair()
    hair_tint = textured_material(HAIR_TINT_MATERIAL, hair_image, tint=(1.0, 1.0, 1.0), roughness=0.6)
    hair_default = textured_material("hair_default", hair_image, tint=hair_color(), roughness=0.6)
    hairs = {}
    for name, style in HAIRS.items():
        hairs[name] = build_hair(name, style, hair_tint)
        bind(hairs[name], armature)

    for mat in list(bpy.data.materials):
        if mat.name.startswith("tmp_") and mat.users == 0:
            bpy.data.materials.remove(mat)

    counts = {name: tri_count(obj) for name, obj in list(body_parts.items()) + list(heads.items()) + list(hairs.items())}
    body_total = sum(v for k, v in counts.items() if k.startswith("body_"))
    print("TRIANGLES", counts, "BODY TOTAL", body_total)
    print("BONES", len(BONES), "deform", len(DEFORM))

    if "--no-preview" not in sys.argv:
        for obj in hairs.values():
            obj.data.materials[0] = hair_default  # previews show the default colours
        for obj in heads.values():
            obj.data.materials[1] = eye_default
        render_previews(armature, body_parts, heads, hairs)
        everything = list(body_parts.values()) + list(heads.values()) + list(hairs.values())
        render_hair_colors(heads, hairs, hair_tint, hair_default, everything)
        render_eye_colors(heads, hairs, eye_tint, everything)
        for obj in everything:
            obj.hide_render = False
        for obj in hairs.values():
            obj.data.materials[0] = hair_tint
        for obj in heads.values():
            obj.data.materials[1] = eye_tint

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SOURCE_DIR, "base_character.blend"))
    # what the game loads: the body wearing the default head and hair
    # the parts stay colour-neutral ("hair_tint" / "eye_tint"); the default look wears the default colours
    for name, obj in list(heads.items()) + list(hairs.items()):
        export_glb(os.path.join(PARTS_DIR, name + ".glb"), armature, [obj])
    hairs["hair_crop"].data.materials[0] = hair_default
    heads["head_round"].data.materials[1] = eye_default
    export_glb(os.path.join(OUT_DIR, "base_character.glb"), armature, list(body_parts.values()) + [heads["head_round"], hairs["hair_crop"]])
    hairs["hair_crop"].data.materials[0] = hair_tint
    heads["head_round"].data.materials[1] = eye_tint
    print("DONE", OUT_DIR)


main()

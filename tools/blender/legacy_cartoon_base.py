"""Builds the shared base character: a Godot-humanoid-compatible skeleton (about 55 deform bones) and a
low-poly base body split by equipment slot, weighted to that skeleton. Run it with Blender:

    blender -b --python tools/blender/build_base_character.py -- <output folder>

Writes into the output folder: base_character.blend, base_character.glb (what the game imports) and
preview PNGs (body, skeleton, poses). The character is 1.8 m tall, stands at the origin, faces -Y in
Blender (= +Z in glTF/Godot) in a T-pose. Left bones are at +X.
EXTENDING: a new bone is one line in BONES; a new body part is one call in build_body(); equipment
meshes are built against the same skeleton so they weight the same way.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.abspath("character_out")
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------------------------------------
# Skeleton: name, parent, head, tail, kind. Names follow Godot's humanoid profile (the side is part
# of the name: LeftUpperArm) so animations from other humanoid sources retarget onto it.
# kind: "core" body bone, "finger", "extra" (secondary motion), "attach" (equipment mount, no skin)
# Proportions are cartoon: a big head (about 1/4 of the height) and short limbs.
# ---------------------------------------------------------------------------------------------
BONES = []


def bone(name, parent, head, tail, kind="core"):
    BONES.append((name, parent, Vector(head), Vector(tail), kind))


bone("Root", None, (0, 0, 0), (0, 0, 0.1), "attach")
bone("Hips", "Root", (0, 0, 0.82), (0, 0, 0.90))
bone("Spine", "Hips", (0, 0, 0.90), (0, 0, 1.02))
bone("Chest", "Spine", (0, 0, 1.02), (0, 0, 1.14))
bone("UpperChest", "Chest", (0, 0, 1.14), (0, 0, 1.26))
bone("Neck", "UpperChest", (0, 0, 1.26), (0, 0, 1.36))
bone("Head", "Neck", (0, 0, 1.36), (0, 0, 1.78))
bone("Jaw", "Head", (0, -0.03, 1.46), (0, -0.13, 1.43))
bone("LeftEye", "Head", (0.06, -0.14, 1.60), (0.06, -0.17, 1.60))
bone("RightEye", "Head", (-0.06, -0.14, 1.60), (-0.06, -0.17, 1.60))

for side, sign in (("Left", 1.0), ("Right", -1.0)):
    def x(value):
        return value * sign

    bone(f"{side}Shoulder", "UpperChest", (x(0.03), 0, 1.22), (x(0.14), 0, 1.22))
    bone(f"{side}UpperArm", f"{side}Shoulder", (x(0.14), 0, 1.22), (x(0.38), 0, 1.22))
    bone(f"{side}LowerArm", f"{side}UpperArm", (x(0.38), 0, 1.22), (x(0.60), 0, 1.22))
    bone(f"{side}Hand", f"{side}LowerArm", (x(0.60), 0, 1.22), (x(0.69), 0, 1.22))
    bone(f"{side}ForearmTwist", f"{side}LowerArm", (x(0.47), 0, 1.22), (x(0.57), 0, 1.22), "extra")
    # Thumb (2 bones) and four fingers (2 bones each): enough to close a fist and hold a weapon.
    bone(f"{side}ThumbProximal", f"{side}Hand", (x(0.63), -0.035, 1.215), (x(0.675), -0.065, 1.205), "finger")
    bone(f"{side}ThumbDistal", f"{side}ThumbProximal", (x(0.675), -0.065, 1.205), (x(0.715), -0.09, 1.195), "finger")
    for finger, offset, length in (("Index", -0.03, 0.085), ("Middle", -0.005, 0.09), ("Ring", 0.02, 0.085), ("Little", 0.04, 0.07)):
        start = 0.69
        bone(f"{side}{finger}Proximal", f"{side}Hand", (x(start), offset, 1.22), (x(start + length * 0.55), offset, 1.22), "finger")
        bone(f"{side}{finger}Intermediate", f"{side}{finger}Proximal", (x(start + length * 0.55), offset, 1.22), (x(start + length), offset, 1.22), "finger")
    bone(f"{side}UpperLeg", "Hips", (x(0.085), 0, 0.82), (x(0.085), 0, 0.43))
    bone(f"{side}LowerLeg", f"{side}UpperLeg", (x(0.085), 0, 0.43), (x(0.085), 0, 0.09))
    bone(f"{side}Foot", f"{side}LowerLeg", (x(0.085), 0, 0.09), (x(0.085), -0.12, 0.04))
    bone(f"{side}Toes", f"{side}Foot", (x(0.085), -0.12, 0.04), (x(0.085), -0.20, 0.02))
    short = "L" if side == "Left" else "R"
    bone(f"attach_weapon.{short}", f"{side}Hand", (x(0.70), -0.04, 1.18), (x(0.70), -0.04, 1.12), "attach")

# Secondary motion: hair and a cape can swing after the body.
bone("HairBack1", "Head", (0, 0.10, 1.74), (0, 0.14, 1.56), "extra")
bone("HairBack2", "HairBack1", (0, 0.14, 1.56), (0, 0.15, 1.42), "extra")
bone("Cape1", "UpperChest", (0, 0.10, 1.26), (0, 0.14, 1.05), "extra")
bone("Cape2", "Cape1", (0, 0.14, 1.05), (0, 0.16, 0.85), "extra")
bone("Cape3", "Cape2", (0, 0.16, 0.85), (0, 0.17, 0.65), "extra")
bone("attach_back", "UpperChest", (0, 0.11, 1.20), (0, 0.17, 1.20), "attach")
bone("attach_head", "Head", (0, 0, 1.80), (0, 0, 1.90), "attach")

DEFORM = [b for b in BONES if b[4] in ("core", "finger", "extra")]

# ---------------------------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------------------------


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1.0)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    return mat


def build_armature():
    arm_data = bpy.data.armatures.new("Armature")
    arm_obj = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
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


def ring_points(center, rx, ry, count=8, axis="z"):
    """A ring of points around `center`. axis "z": a horizontal ring (rx along X, ry along Y), for
    things that stand up. axis "x": a ring in the Y-Z plane (rx along Y, ry along Z), for arms."""
    points = []
    for i in range(count):
        angle = 2.0 * math.pi * i / count + math.pi / count
        if axis == "x":
            points.append(Vector((center[0], center[1] + rx * math.cos(angle), center[2] + ry * math.sin(angle))))
        else:
            points.append(Vector((center[0] + rx * math.cos(angle), center[1] + ry * math.sin(angle), center[2])))
    return points


def tube_mesh(name, rings, mat, count=8, cap_start=True, cap_end=True, axis="z"):
    """rings: list of (center (x, y, z), rx, ry). A low-poly tube with flat shading."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    loops = []
    for center, rx, ry in rings:
        loops.append([bm.verts.new(p) for p in ring_points(center, rx, ry, count, axis)])
    for a, b in zip(loops, loops[1:]):
        for i in range(count):
            j = (i + 1) % count
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap_start:
        bm.faces.new(loops[0][::-1])
    if cap_end:
        bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False
    return obj


def box_mesh(name, center, size, mat):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((center[0] + v.co.x * size[0], center[1] + v.co.y * size[1], center[2] + v.co.z * size[2]))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False
    return obj


def merge(name, objects):
    """Joins several objects into one (each equipment slot area is one mesh made of parts)."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


def side_flip(rings):
    return [((-c[0], c[1], c[2]), rx, ry) for c, rx, ry in rings]


# ---------------------------------------------------------------------------------------------
# The base body, one object per equipment slot area.
# ---------------------------------------------------------------------------------------------


def build_body(skin, hair_color, dark):
    parts = {}
    sides = 10  # sides of every tube: round enough for a cartoon look, still cheap
    # head (large and friendly)
    head = tube_mesh("head_main", [
        ((0, -0.005, 1.36), 0.065, 0.070),
        ((0, -0.010, 1.42), 0.110, 0.118),
        ((0, -0.012, 1.50), 0.142, 0.150),
        ((0, -0.005, 1.60), 0.150, 0.155),
        ((0, 0.000, 1.70), 0.135, 0.140),
        ((0, 0.005, 1.77), 0.090, 0.095),
        ((0, 0.008, 1.80), 0.030, 0.035),
    ], skin, count=sides)
    nose = box_mesh("nose", (0, -0.158, 1.56), (0.03, 0.035, 0.045), skin)
    ear_l = box_mesh("ear_l", (0.152, 0.0, 1.58), (0.025, 0.04, 0.07), skin)
    ear_r = box_mesh("ear_r", (-0.152, 0.0, 1.58), (0.025, 0.04, 0.07), skin)
    parts["body_head"] = merge("body_head", [head, nose, ear_l, ear_r])
    eye_l = box_mesh("eye_l", (0.062, -0.150, 1.61), (0.04, 0.016, 0.05), dark)
    eye_r = box_mesh("eye_r", (-0.062, -0.150, 1.61), (0.04, 0.016, 0.05), dark)
    parts["face_eyes"] = merge("face_eyes", [eye_l, eye_r])
    hair = tube_mesh("hair_cap", [
        ((0, 0.012, 1.58), 0.158, 0.164),
        ((0, 0.014, 1.66), 0.158, 0.162),
        ((0, 0.014, 1.74), 0.130, 0.136),
        ((0, 0.014, 1.80), 0.085, 0.090),
        ((0, 0.014, 1.835), 0.030, 0.035),
    ], hair_color, count=sides, cap_start=False)
    fringe = box_mesh("hair_fringe", (0, -0.135, 1.70), (0.27, 0.05, 0.07), hair_color)
    back = box_mesh("hair_back", (0, 0.135, 1.56), (0.22, 0.07, 0.26), hair_color)
    parts["hair_short"] = merge("hair_short", [hair, fringe, back])

    # torso and neck
    torso = tube_mesh("torso_main", [
        ((0, 0.000, 0.72), 0.120, 0.090),
        ((0, 0.000, 0.80), 0.140, 0.098),
        ((0, 0.000, 0.88), 0.152, 0.104),
        ((0, 0.000, 0.98), 0.132, 0.092),
        ((0, 0.000, 1.10), 0.142, 0.097),
        ((0, 0.000, 1.20), 0.170, 0.105),
        ((0, 0.000, 1.27), 0.172, 0.100),
        ((0, 0.000, 1.31), 0.090, 0.070),
    ], skin, count=sides)
    neck = tube_mesh("neck", [((0, 0, 1.26), 0.052, 0.054), ((0, 0, 1.38), 0.047, 0.050)], skin, count=sides)
    parts["body_torso"] = merge("body_torso", [torso, neck])

    # arms: extra rings around the elbow so it bends smoothly
    arm_rings_left = [
        ((0.10, 0, 1.22), 0.068, 0.074),
        ((0.20, 0, 1.22), 0.062, 0.066),
        ((0.33, 0, 1.22), 0.053, 0.056),
        ((0.38, 0, 1.22), 0.051, 0.054),
        ((0.43, 0, 1.22), 0.050, 0.053),
        ((0.52, 0, 1.22), 0.046, 0.049),
        ((0.60, 0, 1.22), 0.041, 0.045),
        ((0.66, 0, 1.22), 0.039, 0.043),
    ]
    arm_l = tube_mesh("arm_l", arm_rings_left, skin, count=sides, cap_start=False, axis="x")
    arm_r = tube_mesh("arm_r", side_flip(arm_rings_left), skin, count=sides, cap_start=False, axis="x")
    parts["body_arms"] = merge("body_arms", [arm_l, arm_r])

    # hands: palm, fingers, thumb (mitten style)
    hand_objects = []
    for sign, tag in ((1.0, "l"), (-1.0, "r")):
        palm = box_mesh("palm_" + tag, (sign * 0.705, 0, 1.22), (0.085, 0.100, 0.044), skin)
        fingers = box_mesh("fingers_" + tag, (sign * 0.795, -0.004, 1.22), (0.100, 0.100, 0.036), skin)
        thumb = box_mesh("thumb_" + tag, (sign * 0.685, -0.068, 1.208), (0.095, 0.038, 0.038), skin)
        hand_objects += [palm, fingers, thumb]
    parts["body_hands"] = merge("body_hands", hand_objects)

    # legs
    leg_rings_left = [
        ((0.085, 0, 0.90), 0.100, 0.104),
        ((0.085, 0, 0.82), 0.104, 0.108),
        ((0.085, 0, 0.70), 0.098, 0.102),
        ((0.085, 0, 0.50), 0.076, 0.080),
        ((0.085, 0, 0.45), 0.072, 0.076),
        ((0.085, 0, 0.40), 0.070, 0.074),
        ((0.085, 0, 0.28), 0.062, 0.066),
        ((0.085, 0, 0.15), 0.054, 0.058),
        ((0.085, 0, 0.06), 0.056, 0.062),
    ]
    leg_l = tube_mesh("leg_l", leg_rings_left, skin, count=sides, cap_start=False)
    leg_r = tube_mesh("leg_r", side_flip(leg_rings_left), skin, count=sides, cap_start=False)
    parts["body_legs"] = merge("body_legs", [leg_l, leg_r])

    # feet: a chunky block each, heel to toe
    foot_objects = []
    for sign, tag in ((1.0, "l"), (-1.0, "r")):
        foot_objects.append(box_mesh("foot_" + tag, (sign * 0.085, -0.075, 0.050), (0.115, 0.28, 0.100), skin))
    parts["body_feet"] = merge("body_feet", foot_objects)
    return parts


def distance_to_segment(point, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (point - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (point - (a + ab * t)).length


# Meshes that should only follow some bones (hair follows the head, eyes the head...).
LIMITS = {
    "face_eyes": ["Head"],
    "hair_short": ["Head", "HairBack1", "HairBack2"],
    "body_head": ["Head", "Neck", "Jaw"],
}


def weight_to_skeleton(obj, armature):
    """Skin weights: each vertex follows the nearest bones, blended by distance (a smooth bend at the joints)."""
    allowed = LIMITS.get(obj.name)
    candidates = [b for b in DEFORM if allowed is None or b[0] in allowed]
    if allowed is None:
        candidates = [b for b in candidates if b[4] != "extra" or b[0].endswith("Twist")]
    for name, *_ in candidates:
        obj.vertex_groups.new(name=name)
    for vertex in obj.data.vertices:
        world = obj.matrix_world @ vertex.co
        scored = []
        for name, parent, head, tail, kind in candidates:
            distance = distance_to_segment(world, head, tail)
            # fingers and twists should only win when the vertex is really close to them
            bias = 1.0 if kind == "core" else 1.8
            scored.append((distance * bias, name))
        scored.sort()
        nearest = scored[:3]
        weights = [1.0 / (d + 0.012) ** 3 for d, _ in nearest]
        total = sum(weights)
        for (d, name), w in zip(nearest, weights):
            if w / total > 0.04:
                obj.vertex_groups[name].add([vertex.index], w / total, "REPLACE")
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature


# ---------------------------------------------------------------------------------------------
# Previews
# ---------------------------------------------------------------------------------------------


def setup_render(width=720, height=900):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_specular_highlight = False
    shading.background_type = "VIEWPORT"
    shading.background_color = (0.16, 0.18, 0.22)
    scene.display.render_aa = "8"
    scene.view_settings.view_transform = "Standard"
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    return cam_obj


def shoot(cam, name, direction, ortho_scale=2.2, center_z=0.9, xray=False):
    """direction: vector from the character toward the camera."""
    direction = Vector(direction).normalized()
    cam.data.ortho_scale = ortho_scale
    cam.location = Vector((0, 0, center_z)) + direction * 8.0
    look = (Vector((0, 0, center_z)) - cam.location).to_track_quat("-Z", "Y")
    cam.rotation_euler = look.to_euler()
    scene = bpy.context.scene
    scene.display.shading.show_xray = xray
    scene.display.shading.xray_alpha = 0.35
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)


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


def make_skeleton_view(armature):
    """Visible bones for the preview: a sphere per joint and a stick per bone, colored by kind."""
    colors = {"core": (0.3, 0.7, 1.0), "finger": (1.0, 0.5, 0.8), "extra": (0.8, 0.6, 1.0), "attach": (1.0, 0.8, 0.2)}
    objects = []
    for name, parent, head, tail, kind in BONES:
        mat = material("sk_" + kind, colors[kind])
        direction = tail - head
        if direction.length < 1e-5:
            continue
        mesh = bpy.data.meshes.new("stick_" + name)
        bm = bmesh.new()
        radius = 0.008 if kind != "core" else 0.014
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius, radius2=radius * 0.4, depth=direction.length)
        quat = Vector((0, 0, 1)).rotation_difference(direction)
        for v in bm.verts:
            v.co = quat @ v.co + (head + tail) * 0.5
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("stick_" + name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.data.materials.append(mat)
        objects.append(obj)
        joint_bm = bmesh.new()
        bmesh.ops.create_uvsphere(joint_bm, u_segments=8, v_segments=6, radius=radius * 1.7 if kind == "core" else radius * 1.5)
        for v in joint_bm.verts:
            v.co += head
        joint_mesh = bpy.data.meshes.new("joint_" + name)
        joint_bm.to_mesh(joint_mesh)
        joint_bm.free()
        joint = bpy.data.objects.new("joint_" + name, joint_mesh)
        bpy.context.scene.collection.objects.link(joint)
        joint.data.materials.append(mat)
        objects.append(joint)
    return objects


def main():
    reset_scene()
    skin = material("skin", (0.88, 0.66, 0.52))
    hair_color = material("hair", (0.18, 0.11, 0.07))
    dark = material("dark", (0.04, 0.04, 0.06))
    armature = build_armature()
    parts = build_body(skin, hair_color, dark)
    for obj in parts.values():
        bpy.context.view_layer.objects.active = obj
        weight_to_skeleton(obj, armature)
    tris = 0
    for obj in parts.values():
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        tris += len(bm.calc_loop_triangles())
        bm.free()
    print("PARTS", {name: len(obj.data.polygons) for name, obj in parts.items()})
    print("BONES", len(BONES), "deform", len(DEFORM), "TRIANGLES", tris)

    cam = setup_render()
    # 1. the body in the T-pose
    shoot(cam, "01_body_front", (0, -1, 0))
    shoot(cam, "02_body_side", (1, 0, 0))
    shoot(cam, "03_body_three_quarter", (-0.7, -1, 0.15))
    # 2. the skeleton over the translucent body
    sticks = make_skeleton_view(armature)
    shoot(cam, "04_skeleton_front", (0, -1, 0), xray=True)
    shoot(cam, "05_skeleton_hands_closeup", (0, -1, 0), ortho_scale=0.55, center_z=1.22, xray=True)
    for obj in sticks:
        bpy.data.objects.remove(obj, do_unlink=True)

    # 3. poses. World axes: arms hang along -Z. About Y, a left arm goes down with + degrees. About X a
    # hanging limb swings forward (toward -Y) with - degrees; a bent knee swings the shin back with +.
    def arms_down(degrees):
        rotate_bone_world(armature, "LeftUpperArm", (0, 1, 0), degrees)
        rotate_bone_world(armature, "RightUpperArm", (0, 1, 0), -degrees)

    clear_pose(armature)
    arms_down(55)
    shoot(cam, "06_pose_relaxed", (-0.5, -1, 0.1))

    clear_pose(armature)
    # fighting stance: knees bent, front leg forward, guard up
    rotate_bone_world(armature, "Hips", (0, 0, 1), 22)
    rotate_bone_world(armature, "Chest", (0, 0, 1), -18)
    rotate_bone_world(armature, "Spine", (1, 0, 0), -8)
    rotate_bone_world(armature, "LeftUpperLeg", (1, 0, 0), -38)
    rotate_bone_world(armature, "LeftLowerLeg", (1, 0, 0), 62)
    rotate_bone_world(armature, "RightUpperLeg", (1, 0, 0), 22)
    rotate_bone_world(armature, "RightLowerLeg", (1, 0, 0), 42)
    arms_down(75)
    rotate_bone_world(armature, "LeftUpperArm", (1, 0, 0), -35)
    rotate_bone_world(armature, "RightUpperArm", (1, 0, 0), -35)
    rotate_bone_world(armature, "LeftLowerArm", (1, 0, 0), -105)
    rotate_bone_world(armature, "RightLowerArm", (1, 0, 0), -105)
    for finger in ("Index", "Middle", "Ring", "Little"):
        for part in ("Proximal", "Intermediate"):
            rotate_bone_world(armature, "Left" + finger + part, (1, 0, 0), -70)
            rotate_bone_world(armature, "Right" + finger + part, (1, 0, 0), -70)
    shoot(cam, "07_pose_fight_stance", (-0.6, -1, 0.1))
    shoot(cam, "08_pose_fight_stance_side", (1, -0.3, 0.1))

    clear_pose(armature)
    # a running stride
    rotate_bone_world(armature, "Spine", (1, 0, 0), -12)
    rotate_bone_world(armature, "LeftUpperLeg", (1, 0, 0), -50)
    rotate_bone_world(armature, "LeftLowerLeg", (1, 0, 0), 25)
    rotate_bone_world(armature, "RightUpperLeg", (1, 0, 0), 32)
    rotate_bone_world(armature, "RightLowerLeg", (1, 0, 0), 80)
    arms_down(78)
    rotate_bone_world(armature, "LeftUpperArm", (1, 0, 0), 40)
    rotate_bone_world(armature, "RightUpperArm", (1, 0, 0), -45)
    rotate_bone_world(armature, "LeftLowerArm", (1, 0, 0), 15)
    rotate_bone_world(armature, "RightLowerArm", (1, 0, 0), -95)
    shoot(cam, "09_pose_run_side", (1, 0, 0.1))

    clear_pose(armature)
    # a punch
    rotate_bone_world(armature, "Hips", (0, 0, 1), 30)
    rotate_bone_world(armature, "Chest", (0, 0, 1), -50)
    rotate_bone_world(armature, "LeftUpperLeg", (1, 0, 0), -40)
    rotate_bone_world(armature, "LeftLowerLeg", (1, 0, 0), 45)
    rotate_bone_world(armature, "RightUpperLeg", (1, 0, 0), 28)
    rotate_bone_world(armature, "RightLowerLeg", (1, 0, 0), 35)
    arms_down(75)
    rotate_bone_world(armature, "LeftUpperArm", (1, 0, 0), -90)
    rotate_bone_world(armature, "LeftLowerArm", (1, 0, 0), -5)
    rotate_bone_world(armature, "RightUpperArm", (1, 0, 0), -20)
    rotate_bone_world(armature, "RightLowerArm", (1, 0, 0), -120)
    shoot(cam, "10_pose_punch", (-1, -0.2, 0.1))
    clear_pose(armature)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "base_character.blend"))
    # export only the character (not the preview camera)
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    for obj in parts.values():
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "base_character.glb"), export_format="GLB", use_selection=True, export_skins=True, export_animations=False, export_apply=False, export_yup=True)
    print("DONE", OUT)


main()

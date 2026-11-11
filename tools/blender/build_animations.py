"""Authors the character animations as keyframed actions on the shared skeleton and exports them.
Run it with Blender on the base character file:

    blender -b art_source/characters/base_character.blend --python tools/blender/build_animations.py -- <project folder>

Writes into <project>/art/animations/: common.glb + common.json (clips every weapon can fall back on),
blade.glb + blade.json (the sword's own attack), and <project>/art/weapons/blade.glb (the sword model).
Each clip is a Blender action named like the move kind it plays for ("idle", "run", "light_1"...).
The .json next to a .glb says, per clip: "length" in seconds, "loop", and for attacks "windup_end" and
"strike_end" (seconds into the clip) so the game can stretch the three phases to the move's frame data.

Poses are written as rotations about the WORLD axes at a bone's head (arms hang along -Z):
  Blender axes: X = the character's left, -Y = forward, Z = up.
  hanging limb forward = X-, backward = X+ ; knee/elbow bend = shin/forearm X+ for the knee, X- for the elbow ;
  spine lean forward = X+ ; chest/hips turn to the character's left = Z+ ; left arm down = Y+, right arm down = Y-.
EXTENDING: a new clip is a new function that calls key() at its frames and a line in main().
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.getcwd()
FPS = 30
ARMATURE = None
# Bones that carry the animation. Parents first, so each rotation builds on the pose above it.
ORDER = ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
         "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
         "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]
FINGERS = ["Index", "Middle", "Ring", "Little"]
AXES = {"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}


def clear_pose():
    for pb in ARMATURE.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()


def rot(bone_name, axis, degrees):
    """Rotate a bone about a world axis through its head, on top of the pose so far."""
    pb = ARMATURE.pose.bones[bone_name]
    matrix = pb.matrix.copy()
    head = matrix.translation.copy()
    rotation = Matrix.Rotation(math.radians(degrees), 4, AXES[axis])
    pb.matrix = Matrix.Translation(head) @ rotation @ Matrix.Translation(-head) @ matrix
    bpy.context.view_layer.update()


def move_hips(x=0.0, y=0.0, z=0.0):
    """Shift the hips (and with them the whole body) in world space."""
    pb = ARMATURE.pose.bones["Hips"]
    pb.matrix = Matrix.Translation(Vector((x, y, z))) @ pb.matrix
    bpy.context.view_layer.update()


def curl_fingers(degrees):
    """Curl every finger toward the palm (palms face down in the T-pose rest, so about the world front-back axis,
    like the curl in client/character_model.gd). Positive closes the hand."""
    for side, sign in (("Left", -1.0), ("Right", 1.0)):
        for finger in FINGERS:
            for part, factor in (("Proximal", 0.8), ("Intermediate", 1.0)):
                pb = ARMATURE.pose.bones[side + finger + part]
                local_axis = pb.bone.matrix_local.to_3x3().inverted() @ Vector((0, -1, 0))
                pb.rotation_quaternion = pb.rotation_quaternion @ Matrix.Rotation(math.radians(sign * degrees * factor), 3, local_axis).to_quaternion()
    bpy.context.view_layer.update()


def key(frame):
    """Records the current pose of every animated bone at `frame`."""
    for name in ORDER + [side + finger + part for side in ("Left", "Right") for finger in FINGERS for part in ("Proximal", "Intermediate")]:
        pb = ARMATURE.pose.bones[name]
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=name)
        if name == "Hips":
            pb.keyframe_insert(data_path="location", frame=frame, group=name)


def new_clip(name):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    if ARMATURE.animation_data is None:
        ARMATURE.animation_data_create()
    ARMATURE.animation_data.action = action
    clear_pose()
    return action


# --------------------------------------------------------------------------------------- shared pieces

def stance(left_forward=True, bounce=0.0, lean=4.0):
    """A relaxed fighting stance: arms down and bent in front of the chest, knees soft, one foot forward."""
    clear_pose()
    move_hips(0, 0, -0.03 + bounce)
    rot("Spine", "x", lean)
    sign = 1.0 if left_forward else -1.0
    rot("LeftUpperLeg", "x", -14 * sign if left_forward else 8)
    rot("LeftLowerLeg", "x", 22 if left_forward else 16)
    rot("RightUpperLeg", "x", 8 if left_forward else -14)
    rot("RightLowerLeg", "x", 16 if left_forward else 22)
    rot("LeftUpperArm", "y", 62)
    rot("RightUpperArm", "y", -62)
    rot("LeftUpperArm", "x", -14)
    rot("RightUpperArm", "x", -14)
    rot("LeftLowerArm", "x", -70)
    rot("RightLowerArm", "x", -70)
    curl_fingers(34)


# --------------------------------------------------------------------------------------- clips

def clip_idle():
    new_clip("idle")
    for frame, breath in ((0, 0.0), (30, 1.0), (60, 0.0)):
        stance(True, bounce=0.012 * breath, lean=4 + 1.5 * breath)
        rot("Chest", "x", 1.5 * breath)
        rot("Head", "x", -2.0 * breath)
        key(frame)
    return {"length": 60 / FPS, "loop": True}


def run_pose(phase):
    """phase 0: left foot forward (contact); 1: passing; 2: right foot forward; 3: passing."""
    clear_pose()
    swing = (1, 0, -1, 0)[phase]  # +1: left leg forward
    passing = phase in (1, 3)
    move_hips(0, -0.02, -0.04 - (0.025 if passing else 0.0))
    rot("Spine", "x", 14)
    rot("Chest", "z", 8 * swing)
    rot("Head", "x", -8)
    left_leg, right_leg = (-52, 30) if swing >= 0 else (30, -52)
    if passing:
        left_leg, right_leg = (-12, 6) if phase == 1 else (6, -12)
    rot("LeftUpperLeg", "x", left_leg)
    rot("RightUpperLeg", "x", right_leg)
    if passing:
        rot("LeftLowerLeg" if phase == 1 else "RightLowerLeg", "x", 82)
        rot("RightLowerLeg" if phase == 1 else "LeftLowerLeg", "x", 14)
    else:
        rot("LeftLowerLeg", "x", 22 if swing > 0 else 70)
        rot("RightLowerLeg", "x", 70 if swing > 0 else 22)
    rot("LeftUpperArm", "y", 74)
    rot("RightUpperArm", "y", -74)
    arm_left, arm_right = (30, -46) if swing >= 0 else (-46, 30)
    if passing:
        arm_left = arm_right = -8
    rot("LeftUpperArm", "x", arm_left)
    rot("RightUpperArm", "x", arm_right)
    rot("LeftLowerArm", "x", -85)
    rot("RightLowerArm", "x", -85)
    curl_fingers(48)


def clip_run():
    new_clip("run")
    for index, frame in enumerate((0, 5, 10, 15, 20)):
        run_pose(index % 4)
        key(frame)
    return {"length": 20 / FPS, "loop": True}


def clip_walk():
    new_clip("walk")
    for index, frame in enumerate((0, 8, 16, 24, 32)):
        run_pose(index % 4)
        # a walk is the run with smaller swings: scale by easing the pose back toward the stance
        key(frame)
    return {"length": 32 / FPS, "loop": True}


def punch_pose(stage):
    """A right cross: 'guard' -> 'wind' (cocked back) -> 'strike' (arm fully forward)."""
    stance(True)
    if stage == "wind":
        move_hips(0, 0.05, 0)
        rot("Hips", "z", -14)
        rot("Chest", "z", -38)
        rot("RightUpperArm", "x", 38)
        rot("RightLowerArm", "x", -95)
        rot("LeftUpperArm", "x", -18)
        rot("LeftLowerArm", "x", -35)
        rot("LeftUpperLeg", "x", 6)
        rot("RightUpperLeg", "x", 10)
        curl_fingers(40)
    elif stage == "strike":
        move_hips(0, -0.16, -0.02)
        rot("Hips", "z", 18)
        rot("Chest", "z", 44)
        rot("Spine", "x", 8)
        rot("RightUpperArm", "x", -92)
        rot("RightLowerArm", "x", 78)
        rot("LeftUpperLeg", "x", -22)
        rot("LeftLowerLeg", "x", 22)
        rot("RightUpperLeg", "x", 22)
        rot("RightLowerLeg", "x", 28)
        curl_fingers(80)


def clip_light_1():
    """The fists' jab-cross: the fallback for any weapon without its own light_1."""
    new_clip("light_1")
    punch_pose("guard")
    key(0)
    punch_pose("wind")
    key(5)
    punch_pose("strike")
    key(8)
    punch_pose("strike")
    rot("RightUpperArm", "x", -4)
    key(10)
    punch_pose("guard")
    key(22)
    return {"length": 22 / FPS, "loop": False, "windup_end": 5 / FPS, "strike_end": 8 / FPS}


# --------------------------------------------------------------------------------------- the sword's move set
# The sword clips are built at 60 frames per second, one frame per simulation tick, so a clip's frames ARE the
# move's ticks (startup / active / recovery from data/combat/weapons.json, scaled by the sword's speed 1.1).
# Most of them start from motion-captured-style CC0 clips (Quaternius "Universal Animation Library", packed as
# glTF on a UE-style 66-bone mannequin by Mesh2Motion, art assets CC0: github.com/Mesh2Motion/mesh2motion-app).
# The source is retargeted onto our skeleton (bone directions aligned at rest, rotations carried over in world
# space), RE-TIMED so its wind-up / cut / follow-through land on the move's ticks, and then exaggerated with
# extra layers (deeper crouch, torso twist, impact dip, spins, jumps) so it reads from the high camera.
# The rest are posed here from source poses plus those layers.

BLADE_FPS = 60
SOURCE_GLB = os.path.join(PROJECT, "art_source", "animations", "ual_mesh2motion_human_base.glb")
# Blade move timing in ticks: (startup, active, recovery) = the template's numbers x 1.1, rounded like the loader.
BLADE_SPEED = 1.1
BLADE_TEMPLATES = {"light_1": (4, 3, 10), "light_2": (4, 3, 10), "light_3": (5, 3, 16), "heavy": (12, 4, 22),
                   "air": (3, 4, 8), "air_heavy": (8, 10, 14), "run_light": (6, 6, 18), "run_heavy": (10, 7, 28),
                   "special": (8, 4, 20), "ultimate": (14, 6, 28)}


def _round_half_away(value):
    return int(math.floor(value + 0.5)) if value >= 0 else -int(math.floor(-value + 0.5))


def blade_ticks(move):
    startup, active, recovery = BLADE_TEMPLATES[move]
    return max(1, _round_half_away(startup * BLADE_SPEED)), active, max(0, _round_half_away(recovery * BLADE_SPEED))


class Source:
    """The CC0 clips, imported next to our armature and retargeted onto it one frame at a time."""
    MAP = {"Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03", "Neck": "neck_01", "Head": "head"}
    for _side, _s in (("Left", "l"), ("Right", "r")):
        MAP.update({_side + "Shoulder": "clavicle_" + _s, _side + "UpperArm": "upperarm_" + _s, _side + "LowerArm": "lowerarm_" + _s,
                    _side + "Hand": "hand_" + _s, _side + "UpperLeg": "thigh_" + _s, _side + "LowerLeg": "calf_" + _s,
                    _side + "Foot": "foot_" + _s, _side + "Toes": "ball_" + _s,
                    _side + "ThumbProximal": "thumb_01_" + _s, _side + "ThumbDistal": "thumb_02_" + _s})
        for _f, _sf in (("Index", "index"), ("Middle", "middle"), ("Ring", "ring"), ("Little", "pinky")):
            MAP[_side + _f + "Proximal"] = "%s_01_%s" % (_sf, _s)
            MAP[_side + _f + "Intermediate"] = "%s_02_%s" % (_sf, _s)
    # each source bone's direction at rest: from its head toward this child's head
    CHILD = {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head", "head": "head_leaf"}
    for _s in "lr":
        CHILD.update({"clavicle_" + _s: "upperarm_" + _s, "upperarm_" + _s: "lowerarm_" + _s, "lowerarm_" + _s: "hand_" + _s,
                      "hand_" + _s: "middle_01_" + _s, "thigh_" + _s: "calf_" + _s, "calf_" + _s: "foot_" + _s, "foot_" + _s: "ball_" + _s,
                      "ball_" + _s: "ball_leaf_" + _s, "thumb_01_" + _s: "thumb_02_" + _s, "thumb_02_" + _s: "thumb_03_" + _s})
        for _sf in ("index", "middle", "ring", "pinky"):
            CHILD["%s_01_%s" % (_sf, _s)] = "%s_02_%s" % (_sf, _s)
            CHILD["%s_02_%s" % (_sf, _s)] = "%s_03_%s" % (_sf, _s)

    def __init__(self, path):
        before = set(bpy.data.objects)
        actions_before = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=path)
        self.objects = [obj for obj in bpy.data.objects if obj not in before]
        self.arm = [obj for obj in self.objects if obj.type == "ARMATURE"][0]
        self.actions = {action.name: action for action in bpy.data.actions if action not in actions_before}
        for obj in self.objects:
            obj.hide_viewport = obj.type != "ARMATURE"
        self.bones = [b.name for b in ARMATURE.data.bones if b.name in self.MAP]  # parents first
        world = self.arm.matrix_world
        self.offset = {}
        for name in self.bones:
            src_bone, bone = self.arm.data.bones[self.MAP[name]], ARMATURE.data.bones[name]
            src_rest = world.to_quaternion() @ src_bone.matrix_local.to_quaternion()
            src_dir = world @ self.arm.data.bones[self.CHILD[src_bone.name]].head_local - world @ src_bone.head_local
            align = (bone.tail_local - bone.head_local).rotation_difference(src_dir)
            self.offset[name] = src_rest.inverted() @ align @ bone.matrix_local.to_quaternion()
        self.pelvis_rest = world @ self.arm.data.bones["pelvis"].head_local
        self.hip_scale = ARMATURE.data.bones["Hips"].head_local.z / self.pelvis_rest.z
        self.cache = {}

    def last_frame(self, clip):
        # the source clips end on a copy of their first key (they were made to loop): stop one key (2.5 frames) early
        return self.actions[clip].frame_range[1] - 2.5

    def loop_length(self, clip):
        return self.actions[clip].frame_range[1] - self.actions[clip].frame_range[0]

    def pose(self, clip, frame, looping=False):
        """Our skeleton posed like the source clip at `frame` (60 per second), as a pose dict. A `looping` clip
        is sampled all the way to its end (which repeats its start)."""
        frame = max(0.0, min(frame, self.loop_length(clip) if looping else self.last_frame(clip)))
        cache_key = (clip, round(frame, 3))
        if cache_key in self.cache:
            return self.cache[cache_key]
        self.arm.animation_data.action = self.actions[clip]
        start = self.actions[clip].frame_range[0]
        whole = math.floor(start + frame)
        bpy.context.scene.frame_set(int(whole), subframe=(start + frame) - whole)
        clear_pose()
        world = self.arm.matrix_world
        for name in self.bones:
            src_pb = self.arm.pose.bones[self.MAP[name]]
            rotation = (world @ src_pb.matrix).to_quaternion() @ self.offset[name]
            pb = ARMATURE.pose.bones[name]
            head = pb.matrix.translation.copy()
            if name == "Hips":  # the hips follow the source pelvis, without the clip's root motion (the game moves the body)
                pelvis = world @ src_pb.matrix.translation
                root = world @ self.arm.pose.bones["root"].matrix.translation
                delta = Vector((pelvis.x - root.x, pelvis.y - root.y, pelvis.z)) - self.pelvis_rest
                head = ARMATURE.data.bones["Hips"].head_local + delta * self.hip_scale
            pb.matrix = Matrix.LocRotScale(head, rotation, None)
            bpy.context.view_layer.update()
        result = capture()
        self.cache[cache_key] = result
        return result

    def remove(self):
        for action in self.actions.values():
            bpy.data.actions.remove(action)
        for obj in self.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


SRC = None
BLADE_BONES = []  # the bones the sword clips key (everything the source drives)


def capture():
    """The current pose as {bone: (local rotation, location)}."""
    return {name: (ARMATURE.pose.bones[name].rotation_quaternion.copy(), ARMATURE.pose.bones[name].location.copy()) for name in BLADE_BONES}


def apply(pose):
    for name, (rotation, location) in pose.items():
        pb = ARMATURE.pose.bones[name]
        pb.rotation_quaternion = rotation
        pb.location = location
    bpy.context.view_layer.update()


def blend(a, b, weight):
    """Per-joint blend of two poses (0 = a, 1 = b)."""
    if weight <= 0.0:
        return a
    if weight >= 1.0:
        return b
    out = {}
    for name in a:
        qa, la = a[name]
        qb, lb = b[name]
        if qa.dot(qb) < 0.0:
            qb = -qb
        out[name] = (qa.slerp(qb, weight), la.lerp(lb, weight))
    return out


def with_parts(pose, other, parts, weight=1.0):
    """`pose` with the bones whose names contain any of `parts` taken from `other` (blended by `weight`)."""
    mixed = blend(pose, other, weight)
    return {name: (mixed[name] if any(part in name for part in parts) else pose[name]) for name in pose}


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


def ease_out(x):
    x = max(0.0, min(1.0, x))
    return 1.0 - (1.0 - x) ** 3


def ease_in(x):
    x = max(0.0, min(1.0, x))
    return x * x


EASES = {"lin": lambda x: max(0.0, min(1.0, x)), "in": ease_in, "out": ease_out, "io": smooth}


def warp(tick, anchors):
    """Source frame for a clip tick: anchors are (tick, source frame[, ease of the segment that ends there])."""
    if tick <= anchors[0][0]:
        return anchors[0][1]
    for previous, anchor in zip(anchors, anchors[1:]):
        if tick <= anchor[0]:
            ease = EASES[anchor[2] if len(anchor) > 2 else "lin"]
            amount = ease((tick - previous[0]) / float(anchor[0] - previous[0]))
            return previous[1] + (anchor[1] - previous[1]) * amount
    return anchors[-1][1]


def bump(tick, start, peak, end):
    """0 before `start`, rises to 1 at `peak`, falls back to 0 at `end` (smoothly)."""
    if tick <= start or tick >= end:
        return 0.0
    if tick <= peak:
        return smooth((tick - start) / float(max(1e-6, peak - start)))
    return 1.0 - smooth((tick - peak) / float(max(1e-6, end - peak)))


def impact(tick, hit, depth=0.05, lean=6.0, rise=2, fall=7):
    """The weight landing in a blow: hips dip and the chest drives forward right after `hit`, then settle."""
    amount = bump(tick, hit, hit + rise, hit + rise + fall)
    if amount > 0.0:
        move_hips(0, 0, -depth * amount)
        rot("Spine", "x", lean * amount)


def twist(degrees):
    """Turns the upper body about the vertical (positive = toward the character's left)."""
    rot("Spine", "z", degrees * 0.35)
    rot("Chest", "z", degrees * 0.35)
    rot("UpperChest", "z", degrees * 0.3)


def tucked_legs():
    """Legs pulled up under the body, as in a jump (rotations on top of straight-hanging legs; see tuck())."""
    rot("LeftUpperLeg", "x", -62)
    rot("LeftLowerLeg", "x", 98)
    rot("RightUpperLeg", "x", -28)
    rot("RightLowerLeg", "x", 84)
    rot("LeftFoot", "x", 20)
    rot("RightFoot", "x", 20)


LEG_BONES = ("LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes")


def tuck(weight=1.0):
    """Pulls the legs up under the body whatever the hips are doing (thighs reset to hang straight down first)."""
    if weight <= 0.0:
        return
    before = capture()
    for leg in LEG_BONES:
        ARMATURE.pose.bones[leg].rotation_quaternion = (1, 0, 0, 0)
    bpy.context.view_layer.update()
    for thigh in ("LeftUpperLeg", "RightUpperLeg"):
        pb = ARMATURE.pose.bones[thigh]
        pb.matrix = Matrix.LocRotScale(pb.matrix.translation.copy(), pb.bone.matrix_local.to_quaternion(), None)
        bpy.context.view_layer.update()
    tucked_legs()
    apply(blend(before, capture(), weight))


def ground_hips(weight=1.0):
    """Moves the hips back toward their standing height (a crouch in the source makes no sense in the air)."""
    hips = ARMATURE.pose.bones["Hips"]
    move_hips(0, 0, (ARMATURE.data.bones["Hips"].head_local.z - hips.matrix.translation.z) * weight)


GRIP_FIX_DEGREES = 50.0  # = the old -40 hold slant minus the square -90 hold, so the blades point as the source meant


def grip_fix():
    """The source clips' wrists are posed for a prop held at a slant; our sword sits square in the fist
    (client/character_model.gd WEAPON_HOLD_ROTATION). Bend the sword hand so the blade points where the source meant."""
    pb = ARMATURE.pose.bones["RightHand"]
    axis = (ARMATURE.pose.bones["attach_weapon.R"].matrix.to_3x3() @ Vector((1, 0, 0))).normalized()
    head = pb.matrix.translation.copy()
    pb.matrix = Matrix.Translation(head) @ Matrix.Rotation(math.radians(GRIP_FIX_DEGREES), 4, axis) @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()


# Ticks after the end of the move's startup at which the blade actually crosses in front of the body. The clips
# reach the top of their wind-up (blade behind) at the startup tick and meet the target a tick or few later, but the
# game lands the hit (and freezes for hit-stop) on the first active frame. So the clip's strike phase is marked from
# the contact tick: the game then plays the swing inside the last frames of the startup and the blade is pointing at
# the target when the hit lands. Measured on the built clips (blade direction per tick, from the game's model).
CONTACT_AFTER_STARTUP = {"light_1": 2, "light_2": 2, "light_3": 2, "heavy": 3, "air": 2, "air_heavy": 2,
                         "run_light": 2, "run_heavy": 0, "special": 3, "ultimate": 1}


def bake(name, total, pose_at, loop=False, timing=None):
    """Keys `pose_at(tick)` (it leaves the armature posed) at every tick 0..total and returns the clip metadata."""
    new_clip(name)
    for tick in range(total + 1):
        pose_at(tick)
        grip_fix()
        for bone in BLADE_BONES:
            pb = ARMATURE.pose.bones[bone]
            pb.keyframe_insert(data_path="rotation_quaternion", frame=tick, group=bone)
            if bone == "Hips":
                pb.keyframe_insert(data_path="location", frame=tick, group=bone)
    meta = {"length": total / BLADE_FPS, "loop": loop}
    if timing is not None:
        startup, active, _recovery = timing
        contact = min(startup + CONTACT_AFTER_STARTUP.get(name, 0), total - active)
        meta["windup_end"] = contact / BLADE_FPS
        meta["strike_end"] = (contact + active) / BLADE_FPS
    print("CLIP", name, total, timing)
    return meta


def ready_pose():
    """The sword-ready stance every sword clip starts from and settles back into: knees bent, blade forward."""
    apply(SRC.pose("Sword_Regular_A", 0))
    move_hips(0, 0.02, -0.04)
    rot("LeftUpperLeg", "x", -8)
    rot("LeftLowerLeg", "x", 10)
    rot("RightUpperLeg", "x", 6)
    rot("RightLowerLeg", "x", 10)
    rot("Spine", "x", 5)
    rot("RightUpperArm", "x", -14)  # sword arm a little forward, so the blade points ahead of the body
    return capture()


def blade_idle():
    ready = ready_pose()
    total = 120

    def pose_at(tick):
        breath = 0.5 - 0.5 * math.cos(2.0 * math.pi * tick / total)
        sway = math.sin(2.0 * math.pi * tick / total)
        apply(ready)
        move_hips(0, 0, -0.015 * breath)
        rot("Spine", "x", 2.0 * breath)
        rot("Chest", "x", -1.5 * breath)
        twist(3.0 * sway)
        rot("RightUpperArm", "x", -3.0 * breath)
        rot("Head", "x", -2.0 * breath)
    return bake("idle", total, pose_at, loop=True)


SWORD_ARM = ("RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "RightThumb", "RightIndex", "RightMiddle", "RightRing", "RightLittle")


def blade_locomotion(name, clip, total, lean):
    """Walk / run with the sword: the source gait (re-timed to the common clip's cycle, which the game's movement
    speed was tuned to), the sword arm held in the ready stance so the blade rides forward instead of swinging
    into the ground."""
    ready = ready_pose()
    length = SRC.loop_length(clip)

    def pose_at(tick):
        pose = with_parts(SRC.pose(clip, length * tick / float(total), looping=True), ready, SWORD_ARM)
        apply(pose)
        rot("Spine", "x", lean)
        rot("RightUpperArm", "x", -lean * 0.5)  # keep the blade level as the body leans
    return bake(name, total, pose_at, loop=True)


def blade_walk():
    return blade_locomotion("walk", "Walk", 64, 4.0)


def blade_run():
    return blade_locomotion("run", "Sprint", 40, 6.0)


def retimed(name, clip, anchors, timing, settle_from, enter=0, layers=None):
    """A source clip re-timed by `anchors`, easing in from the ready stance over the first `enter` ticks and back
    into it from tick `settle_from` to the end; `layers(tick)` adds exaggeration on top."""
    ready = ready_pose()
    startup, active, recovery = timing
    total = startup + active + recovery

    def pose_at(tick):
        pose = SRC.pose(clip, warp(tick, anchors))
        if enter > 0:
            pose = blend(ready, pose, smooth(tick / float(enter)))
        pose = blend(pose, ready, smooth((tick - settle_from) / float(max(1, total - settle_from))))
        apply(pose)
        if layers is not None:
            layers(tick)
    return bake(name, total, pose_at, timing=timing)


def blade_light_1():
    """A rising diagonal cut from low behind on the right, across the front, held out to the left (light_2 starts there)."""
    s, a, r = timing = blade_ticks("light_1")

    def layers(tick):
        twist(-14 * bump(tick, 0, s, s + 2) + 22 * bump(tick, s, s + a + 1, s + a + r))  # coil right, unwind left
        impact(tick, s + 1, depth=0.04, lean=6)
    return retimed("light_1", "Sword_Regular_A", [(0, 0), (s, 12, "in"), (s + a, 16, "out"), (s + a + 6, 17), (s + a + r, 18.5)],
                   timing, settle_from=s + a + 5, layers=layers)


def blade_light_2():
    """A flat backhand sweep from the left side across to the right."""
    s, a, r = timing = blade_ticks("light_2")

    def layers(tick):
        twist(18 * bump(tick, 0, s, s + 2) - 24 * bump(tick, s, s + a + 1, s + a + r))
        impact(tick, s + 1, depth=0.04, lean=5)
    return retimed("light_2", "Sword_Regular_B", [(0, 4), (s, 13, "in"), (s + a, 16.5, "out"), (s + a + 6, 17.5), (s + a + r, 18.5)],
                   timing, settle_from=s + a + 5, layers=layers)


def blade_light_3():
    """The finisher: sword raised high, a heavy diagonal chop down into a deep lunge, held, then recovered."""
    s, a, r = timing = blade_ticks("light_3")

    def layers(tick):
        twist(-20 * bump(tick, 0, s, s + 3) + 16 * bump(tick, s, s + a + 2, s + a + r))
        rot("Spine", "x", -8 * bump(tick, 0, s - 1, s + 1))  # rear back before the chop
        impact(tick, s + 1, depth=0.08, lean=10, rise=3, fall=10)
    return retimed("light_3", "Sword_Attack", [(0, 10), (s, 28, "io"), (s + a, 38, "out"), (s + a + 8, 44, "out"), (s + a + r, 56)],
                   timing, settle_from=s + a + 9, layers=layers)


def blade_heavy():
    """The launcher: sink low with the sword dragged low behind, hold the coil, then explode upward in a rising
    cut that ends with the body stretched up and the blade high in front."""
    s, a, r = timing = blade_ticks("heavy")
    total = s + a + r
    ready = ready_pose()
    apply(SRC.pose("Sword_Regular_A", 11))  # the rising cut's wind-up: blade trailing low behind
    move_hips(0, 0.05, -0.08)
    twist(-20)
    coiled = capture()
    rise = [(s, 62), (s + a, 80, "out"), (s + a + 8, 88, "out"), (total, 98)]
    settle_from = s + a + 11

    def pose_at(tick):
        if tick <= s:
            pose = blend(ready, coiled, ease_out(tick / float(s - 3)))
        else:
            pose = blend(coiled, SRC.pose("Sword_Regular_C", warp(tick, rise)), ease_out((tick - s) / float(a)))
            pose = blend(pose, ready, smooth((tick - settle_from) / float(total - settle_from)))
        apply(pose)
        sink = bump(tick, s - 4, s - 1, s + 1)  # the last squeeze before the release
        move_hips(0, 0, -0.03 * sink)
        twist(-8 * sink)
        up = bump(tick, s, s + a + 2, s + a + r)
        move_hips(0, -0.06 * up, 0.12 * up)  # rise onto the toes with the cut
        rot("Spine", "x", -16 * up)
        twist(26 * up)
        rot("RightUpperArm", "x", -30 * up)
    return bake("heavy", total, pose_at, timing=timing)


def blade_air():
    """A quick backhand sweep in the air, legs tucked under."""
    s, a, r = timing = blade_ticks("air")

    def layers(tick):
        ground_hips(0.9)
        tuck()
        twist(16 * bump(tick, 0, s, s + 1) - 22 * bump(tick, s, s + a, s + a + r))
        rot("Spine", "x", 8 * bump(tick, s, s + a, s + a + r))
    return retimed("air", "Sword_Regular_B", [(0, 9), (s, 13, "in"), (s + a, 17, "out"), (s + a + r, 18.5, "out")],
                   timing, settle_from=s + a + r + 1, layers=layers)


def blade_run_light():
    """A running draw-cut: drop low, then one fast horizontal cut through the target, the blade held out past it."""
    s, a, r = timing = blade_ticks("run_light")

    def layers(tick):
        rot("Spine", "x", 10 * bump(tick, 0, s, s + a + 6))  # thrown forward into the rush
        twist(-18 * bump(tick, 0, s, s + 2) + 20 * bump(tick, s, s + a, s + a + r))
        impact(tick, s + 1, depth=0.04, lean=6)
    return retimed("run_light", "Sword_Dash_RM", [(0, 4), (s, 18, "in"), (s + a, 21.5, "out"), (s + a + 9, 23, "out"), (s + a + r, 60)],
                   timing, settle_from=s + a + 9, layers=layers)


def blade_run_heavy():
    """A leaping rising cut out of the run: crouch, spring up through the target, land and settle."""
    s, a, r = timing = blade_ticks("run_heavy")
    air_from, air_to = s - 1, s + a + 12

    def layers(tick):
        coil = bump(tick, 0, s - 1, s + 1)
        move_hips(0, 0, -0.06 * coil)
        rot("Spine", "x", 12 * coil)
        twist(-30 * coil)
        height = math.sin(math.pi * max(0.0, min(1.0, (tick - air_from) / float(air_to - air_from))))
        jump = bump(tick, air_from, air_from + 3, air_to) if tick < air_to - 3 else bump(tick, air_from, air_to - 3, air_to)
        ground_hips(jump)
        move_hips(0, 0, 0.45 * height)
        tuck(jump * 0.85)
        rot("Spine", "x", -12 * bump(tick, s, s + a, s + a + 12))
        twist(26 * bump(tick, s, s + a + 2, s + a + 16))
        rot("RightUpperArm", "x", -28 * bump(tick, s, s + a + 2, s + a + 16))
        impact(tick, air_to, depth=0.09, lean=12, rise=2, fall=8)
    return retimed("run_heavy", "Sword_Regular_C", [(0, 44), (s, 60, "io"), (s + a, 82, "out"), (s + a + 14, 90, "out"), (s + a + r, 99)],
                   timing, settle_from=s + a + 16, enter=5, layers=layers)


def chop_landing(depth=0.10):
    """The end of a big downward chop, crouched deeper, the blade straight out in front (not low on the far side,
    where the body would hide it from the high camera)."""
    apply(SRC.pose("Sword_Attack", 34.5))
    move_hips(0, 0, -depth)
    rot("Spine", "x", 10)
    return capture()


def blade_air_heavy():
    """The plunge: sword raised overhead in the air, a hard chop down as the body dives, a heavy landing crouch."""
    s, a, r = timing = blade_ticks("air_heavy")
    total = s + a + r
    ready = ready_pose()
    apply(SRC.pose("Sword_Attack", 22))
    rot("Spine", "x", -12)
    up = capture()
    apply(SRC.pose("Sword_Attack", 36))
    rot("Spine", "x", 24)
    dive = capture()
    land = chop_landing(0.12)
    land_at = s + a + 1

    def pose_at(tick):
        air = 1.0
        if tick <= s:
            pose = blend(SRC.pose("Sword_Attack", 12), up, smooth(tick / float(s)))
        elif tick <= s + 3:
            pose = blend(up, dive, ease_out((tick - s) / 3.0))
        elif tick <= land_at:
            pose = blend(dive, land, ease_in((tick - s - 3) / float(land_at - s - 3)))
            air = 1.0 - ease_in((tick - s - 3) / float(land_at - s - 3))
        else:
            pose = blend(land, ready, smooth((tick - land_at - 6) / float(total - land_at - 6)))
            air = 0.0
        apply(pose)
        ground_hips(0.9 * air)
        tuck(air)
        if s < tick <= land_at:  # legs swing back as the body pitches into the dive
            rot("LeftUpperLeg", "x", 30 * air)
            rot("RightUpperLeg", "x", 40 * air)
        impact(tick, land_at, depth=0.10, lean=12, rise=2, fall=9)
    return bake("air_heavy", total, pose_at, timing=timing)


def blade_special():
    """Ember Slash: a full spinning slash. Coil, then the whole body turns once with the sword held out flat."""
    s, a, r = timing = blade_ticks("special")
    total = s + a + r
    ready = ready_pose()
    apply(SRC.pose("Sword_Regular_B", 16))  # arm and blade straight out in front
    flat = with_parts(capture(), ready, ("Leg", "Foot", "Toes", "Hips"))
    apply(SRC.pose("Sword_Regular_B", 6))
    coiled = with_parts(capture(), ready, ("Leg", "Foot", "Toes", "Hips"))
    spin_from, spin_to = s - 3, s + a + 3

    def pose_at(tick):
        if tick <= spin_from:
            pose = blend(ready, coiled, smooth(tick / float(spin_from)))
        elif tick <= spin_from + 3:
            pose = blend(coiled, flat, ease_out((tick - spin_from) / 3.0))
        elif tick <= spin_to + 8:
            pose = flat
        else:
            pose = blend(flat, ready, smooth((tick - spin_to - 8) / float(total - spin_to - 8)))
        apply(pose)
        coil = bump(tick, 0, spin_from, spin_from + 2)
        move_hips(0, 0, -0.07 * coil)
        twist(45 * coil)
        amount = ease_out((tick - spin_from) / float(spin_to - spin_from)) if tick > spin_from else 0.0
        overshoot = 25 * bump(tick, spin_to - 1, spin_to + 3, spin_to + 12)
        rot("Hips", "z", -(360 * amount) - overshoot)
        hop = bump(tick, spin_from, (spin_from + spin_to) / 2.0, spin_to)
        move_hips(0, 0, 0.18 * hop)
        tuck(0.5 * hop)
        rot("Spine", "x", 10 * bump(tick, spin_from, s, spin_to + 6))  # lean into the cut
        impact(tick, spin_to, depth=0.07, lean=8)
    return bake("special", total, pose_at, timing=timing)


def blade_ultimate():
    """Crimson Heaven Edge: leap up spinning with the sword raised, then chop it down into the ground around you."""
    s, a, r = timing = blade_ticks("ultimate")
    total = s + a + r
    ready = ready_pose()
    crouch = blend(ready, chop_landing(0.0), 0.5)
    apply(SRC.pose("Sword_Attack", 22))
    rot("Spine", "x", -16)
    rot("RightUpperArm", "x", -15)
    raised = capture()
    slam = chop_landing(0.16)
    jump_from, top, hit = 4, s - 3, s

    def pose_at(tick):
        if tick <= jump_from:
            pose = blend(ready, crouch, smooth(tick / float(jump_from)))
        elif tick <= top:
            pose = blend(crouch, raised, ease_out((tick - jump_from) / float(top - jump_from)))
        elif tick <= hit:
            pose = blend(raised, slam, ease_in((tick - top) / float(hit - top)))
        elif tick <= s + a + 12:
            pose = slam
        else:
            pose = blend(slam, ready, smooth((tick - s - a - 12) / float(total - s - a - 12)))
        apply(pose)
        progress = max(0.0, min(1.0, (tick - jump_from) / float(hit - jump_from)))
        height = math.sin(math.pi * progress)
        airborne = 1.0 if jump_from < tick < hit else 0.0
        ground_hips(airborne * min(1.0, 3.0 * height))
        move_hips(0, 0, 0.7 * height)
        tuck(airborne * min(1.0, 2.0 * height))
        spin = smooth((tick - jump_from) / float(top - jump_from)) if tick > jump_from else 0.0
        rot("Hips", "z", 360 * spin)
        move_hips(0, 0, -0.10 * bump(tick, 0, jump_from, jump_from + 2))  # crouch before the leap
        impact(tick, hit, depth=0.12, lean=12, rise=2, fall=14)
    return bake("ultimate", total, pose_at, timing=timing)


def build_blade_set():
    global SRC, BLADE_BONES
    SRC = Source(SOURCE_GLB)
    BLADE_BONES = list(SRC.bones)
    clips = {}
    for build in (blade_idle, blade_walk, blade_run, blade_light_1, blade_light_2, blade_light_3, blade_heavy, blade_air, blade_air_heavy,
                  blade_run_light, blade_run_heavy, blade_special, blade_ultimate):
        meta = build()
        clips[ARMATURE.animation_data.action.name] = meta
    SRC.remove()
    return clips


# --------------------------------------------------------------------------------------- sword model

def build_sword():
    """A plain sword, about 0.95 m long. Its grip is at the origin and the blade points along +Y."""
    mat_blade = bpy.data.materials.new("blade")
    mat_blade.diffuse_color = (0.75, 0.8, 0.9, 1.0)
    mat_blade.use_nodes = True
    mat_blade.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.8, 0.9, 1.0)
    mat_blade.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.6
    mat_hilt = bpy.data.materials.new("hilt")
    mat_hilt.diffuse_color = (0.35, 0.22, 0.12, 1.0)
    mat_hilt.use_nodes = True
    mat_hilt.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.22, 0.12, 1.0)
    pieces = []

    def box(name, center, size, mat):
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
        pieces.append(obj)

    box("grip", (0, 0.0, 0), (0.032, 0.20, 0.032), mat_hilt)
    box("guard", (0, 0.105, 0), (0.20, 0.03, 0.045), mat_hilt)
    box("blade", (0, 0.58, 0), (0.060, 0.90, 0.012), mat_blade)
    box("tip", (0, 1.05, 0), (0.030, 0.10, 0.010), mat_blade)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    sword = bpy.context.view_layer.objects.active
    sword.name = "blade"
    for poly in sword.data.polygons:
        poly.use_smooth = False
    return sword


# --------------------------------------------------------------------------------------- export

def export_clips(path, clips):
    """Exports every action as one animation inside a skeleton-only .glb, and writes the .json beside it."""
    bpy.ops.object.select_all(action="DESELECT")
    ARMATURE.select_set(True)
    bpy.context.view_layer.objects.active = ARMATURE
    ARMATURE.animation_data.action = None
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_animations=True,
        export_animation_mode="ACTIONS", export_force_sampling=True, export_skins=True, export_yup=True,
    )
    with open(os.path.splitext(path)[0] + ".json", "w", encoding="utf-8") as handle:
        json.dump(clips, handle, indent=2)
    print("EXPORTED", path, list(clips.keys()))


def delete_all_actions():
    if ARMATURE.animation_data is not None:
        ARMATURE.animation_data.action = None
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def main():
    global ARMATURE
    ARMATURE = bpy.data.objects["Armature"]
    bpy.context.scene.render.fps = FPS  # frames become seconds at this rate when exported
    bpy.context.scene.render.fps_base = 1.0
    # the meshes stay out of the animation files
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    for obj in meshes:
        obj.hide_set(True)
        obj.hide_viewport = True
    out_dir = os.path.join(PROJECT, "art", "animations")
    os.makedirs(out_dir, exist_ok=True)

    delete_all_actions()
    common = {"idle": clip_idle(), "walk": clip_walk(), "run": clip_run(), "light_1": clip_light_1()}
    export_clips(os.path.join(out_dir, "common.glb"), common)

    delete_all_actions()
    bpy.context.scene.render.fps = BLADE_FPS  # the sword clips are keyed one frame per simulation tick
    blade = build_blade_set()
    export_clips(os.path.join(out_dir, "blade.glb"), blade)
    bpy.context.scene.render.fps = FPS

    # the sword model
    for obj in bpy.data.objects:
        obj.select_set(False)
    sword = build_sword()
    weapon_dir = os.path.join(PROJECT, "art", "weapons")
    os.makedirs(weapon_dir, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    sword.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(weapon_dir, "blade.glb"), export_format="GLB", use_selection=True, export_yup=True)
    print("DONE")


main()

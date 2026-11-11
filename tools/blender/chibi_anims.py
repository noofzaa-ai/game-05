"""Exports the chibi-studio clips the game uses into art/animations/chibi*.glb (+ .json).

    blender -b --factory-startup --python tools/blender/chibi_anims.py -- <chibi_base_animated.glb> <art/animations>

One set per weapon (chibi_<weapon>) plus "chibi" for empty hands. Game clip name <- model team clip:
idle <- Stand<W> + a life layer (looping), guard <- Block<W> (plays once and holds), dodge <- Dash<W> (stretched over
the dodge), run <- Run2<W>. Every idle is IDLE_LIFE (build_idle): a calm stance
built on the Stand pose (STANCES: calm, gender-neutral, 3/4 turn, per-weapon arm/hand re-pose, e.g. spear on the
shoulder, hammer on the shoulder too, free arms hanging) plus breathing, a small weight lean with one
transfer to the other leg, a glance and hair/cape/free-arm follow-through; feet stay put by IK.
Skill clips come from the model team's skill packs (art_source/skills/<weapon>/<skill>/motion.glb, same
rig); their wind-up / strike marks are the pack's gameplay_events, matching the move in weapons.json.
"""
import os
import bpy, sys, json, math
from mathutils import Matrix, Quaternion, Vector

src, out = sys.argv[-2], sys.argv[-1]
WEAPON_CLIPS = {"idle": "Stand", "guard": "Block", "dodge": "Dash", "run": "Run2"}
LOOPING = {"idle", "run"}
SETS = {"chibi": {"run": "Run2", "idle": "IDLE_LIFE"},
        "chibi_fists": {}}  # empty-hands attacks only (idle, run etc. come from "chibi": the game looks there next)
for weapon in ("blade", "dagger", "spear", "hammer"):
    SETS["chibi_" + weapon] = {clip: base + weapon.capitalize() for clip, base in WEAPON_CLIPS.items()}
    SETS["chibi_" + weapon]["idle"] = "IDLE_LIFE"  # Stand<W> with the life layer on top (build_idle)
ROOT = os.path.abspath(os.path.join(out, "..", ".."))
## set -> {game clip: (motion.glb under the project, clip name in it, metadata)}
SKILL_CLIPS = {
    "chibi_blade": {"ultimate": ("art_source/skills/blade/inferno_ultimate/motion.glb", "BladeInfernoUltimate",
                                 {"length": 3.2, "loop": False, "windup_end": 1.04, "strike_end": 1.94})},
}

FINGERS = ("Index", "Middle", "Ring", "Little", "Thumb")
IDLE_SECONDS = 8.0  # three breaths, one glance and one weight transfer to the other leg and back per loop
## Armature axes (the rig faces -y, its right is -x): turning about SIDE (+x) leans the top forward,
## about FRONT (+y) tilts the top to the character's left, about UP (+z) turns the face to its left.
SIDE, FRONT, UP = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
TURN = -14.0  # three-quarter stance: hips and feet turned to the right, the head turned back to the front

## The idle stance per set, built on the first frame of a Stand clip. Positions/directions are armature
## space for an unturned body (TURN is applied on top). Arms: "hang" (relaxed, sways), "carry" (the
## weapon carried low in a hanging hand: wrist straight, the weapon turned in the fist (attach bone
## rotation) onto "dir" if given, "head" = where a hammer head's long side points, "swing" = (degrees,
## swings per loop) of its weighted pendulum, lagging the body), "keep" (the Stand arm), or a weapon hand: "grip" = where the weapon's grip
## point goes, "dir" = the weapon's axis (toward the tip / hammer head), "elbow" = which way the elbow
## points, "head" = where the hammer head's long side points, "pin" = "world" keeps the hand still while
## the body breathes (a weapon standing on the floor), else it rides with the chest; "orient" turns the
## weapon in the fist (attach bone rotation) onto `dir` exactly. "low" (carry) = the weapon's low end
## (along its axis from the grip point): the weapon slides through the fist (attach bone position,
## played by character_model.gd) until that end is FLOOR_GAP off the floor, e.g. spear/hammer mid-shaft.
STANCES = {
    "chibi": {"base": "StandDagger", "Right": {"hang": True}, "Left": {"hang": True}},
    "chibi_fists": {"base": "StandDagger", "Right": {"hang": True}, "Left": {"hang": True}},  # = "chibi"
    "chibi_blade": {"base": "StandBlade", "Left": {"hang": True},
                    "Right": {"carry": True, "dir": (-0.2, 0.3, -0.93), "swing": (3.0, 3)}},
    "chibi_dagger": {"base": "StandDagger", "Right": {"carry": True, "swing": (3.0, 3)},
                     "Left": {"carry": True, "swing": (3.0, 3)}},
    "chibi_spear": {"base": "StandSpear", "Left": {"hang": True},
                    "Right": {"carry": True, "hand": (-0.30, -0.08, 0.84), "dir": (-0.08, 0.3, 0.95), "low": -0.342,
                              "swing": (2.5, 2)}},
    "chibi_hammer": {"base": "StandHammer", "Left": {"hang": True}, "heavy": True,
                     "Right": {"carry": True, "dir": (-0.25, 0.15, -0.95), "head": (0.0, 1.0, 0.0), "low": 0.78,
                               "swing": (2.0, 2)}},
}
## feet: (offset from the Stand foot, toe turn in degrees): a little wider than the shoulders, toes out,
## the unweighted right foot a touch forward
FEET = {"Left": (Vector((0.035, 0.0, 0.0)), 10.0), "Right": (Vector((-0.035, -0.04, 0.0)), -14.0)}


def q(axis, deg):
    return Quaternion(axis, math.radians(deg))


BODY_TURN = True  # body() applies the stance's TURN (off while posing attack keys, which face straight)


def body(v):
    return q(UP, TURN if BODY_TURN else 0.0) @ Vector(v)


def turn_about(arm, pb, rot, pivot=None):
    """Turns a pose bone (and so its children) by an armature-space rotation about a point (its head)."""
    pivot = pb.head.copy() if pivot is None else pivot
    pb.matrix = Matrix.Translation(pivot) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-pivot) @ pb.matrix
    bpy.context.view_layer.update()


def aim_arm(arm, side, toward, hint, bend, ref):
    """Clean arm: the elbow bends `bend` degrees about its own hinge (the axis the model team's Stand
    elbow uses: no twist, never sideways or backward), the wrist is straight; then the upper arm points
    the shoulder->wrist line along `toward` and rolls about it so the elbow points to `hint`."""
    P = arm.pose.bones
    up, lo, hand = P[side + "UpperArm"], P[side + "LowerArm"], P[side + "Hand"]
    lo.rotation_quaternion = Quaternion(ref[side + "hinge"], math.radians(bend))
    hand.rotation_quaternion = Quaternion()
    P[side + "ForearmTwist"].rotation_quaternion = Quaternion()
    bpy.context.view_layer.update()
    s = up.head.copy()
    turn_about(arm, up, (hand.head - s).rotation_difference(toward), s)
    axis = toward.normalized()
    flat = lambda v: v - axis * v.dot(axis)
    e, h = flat(lo.head - s), flat(hint)
    if e.length > 1e-6 and h.length > 1e-6:
        turn_about(arm, up, e.rotation_difference(h), s)


def reach_arm(arm, side, wrist, hint, ref):
    """aim_arm with the elbow bend that puts the wrist at `wrist` (as near as the arm reaches)."""
    P = arm.pose.bones
    want = (wrist - P[side + "UpperArm"].head).length
    best = (1e9, 0.0)
    for bend in range(0, 141, 2):
        P[side + "LowerArm"].rotation_quaternion = Quaternion(ref[side + "hinge"], math.radians(bend))
        bpy.context.view_layer.update()
        best = min(best, (abs((P[side + "Hand"].head - P[side + "UpperArm"].head).length - want), bend))
    aim_arm(arm, side, wrist - P[side + "UpperArm"].head, hint, best[1], ref)
    return best[1]


WRIST_MAX = 15.0
FLOOR_GAP = 0.04  # metres between the floor and a carried weapon's low end  # degrees a hand may bend off the forearm line


def pose_weapon_arm(arm, side, spec, ref):
    """The weapon arm without a broken wrist: a clean arm reaches the grip point, the hand stays on the
    forearm line except a roll about it (turning the fist so the handle runs as near `dir` as it can)
    and at most WRIST_MAX of bend. The weapon keeps the model team's angle in the fist, so where it
    points depends on the forearm: the elbow direction is searched around spec elbow for the one that
    brings the weapon nearest `dir` while the points `clear` (along the weapon) stay out of the head."""
    P = arm.pose.bones
    hand, att = P[side + "Hand"], P["attach_weapon." + side[0]]
    rel = hand.matrix.inverted() @ att.matrix  # the model team's grip: weapon in the fist
    grip_axis = rel.to_3x3() @ Vector((0, 1, 0))
    want = body(spec["dir"]).normalized()
    grip = body(spec["grip"])
    head = P["Head"].head + Vector((0, 0, 0.15))  # middle of the (big) head

    def solve(hint):
        for _ in range(3):
            elbow = reach_arm(arm, side, grip - (att.head - hand.head), hint, ref)
            h0 = hand.matrix.to_quaternion()
            roll = min(range(-180, 180, 3), key=lambda a: (h0 @ q(Vector((0, 1, 0)), a) @ grip_axis).angle(want))
            # the fist's roll is shared by forearm and wrist (the ForearmTwist bone has no skin weights)
            P[side + "LowerArm"].rotation_quaternion = P[side + "LowerArm"].rotation_quaternion @ q(Vector((0, 1, 0)), roll / 2)
            hand.rotation_quaternion = q(Vector((0, 1, 0)), roll / 2)
            bpy.context.view_layer.update()
            att.matrix = hand.matrix @ rel
            bpy.context.view_layer.update()
            need = (att.matrix.to_3x3() @ Vector((0, 1, 0))).rotation_difference(want)
            bend = min(math.degrees(need.angle), WRIST_MAX)
            turn_about(arm, hand, Quaternion(need.axis, math.radians(bend)))
            att.matrix = hand.matrix @ rel
            bpy.context.view_layer.update()
        d = att.matrix.to_3x3() @ Vector((0, 1, 0))
        clip = sum(max(0.0, 0.34 - (att.head + d * y - head).length) for y in spec.get("clear", ()))
        return math.degrees(d.angle(want)) + 400.0 * clip, elbow, roll, bend

    base_hint = body(spec["elbow"])
    reach_dir = (grip - P[side + "UpperArm"].head).normalized()
    hints = [Quaternion(reach_dir, math.radians(a)) @ base_hint for a in range(-90, 91, 15)]
    best = min(hints, key=lambda h: solve(h)[0])
    score, elbow, roll, bend = solve(best)
    d = att.matrix.to_3x3() @ Vector((0, 1, 0))
    if spec.get("orient"):  # turn the weapon in the fist (the attach bone) onto `dir` exactly
        turn_about(arm, att, d.rotation_difference(want), att.head.copy())
        d = want
    if "head" in spec:  # spin the weapon about its own axis so the hammer head lies along spec head
        up = body(spec["head"])
        have = att.matrix.to_3x3() @ Vector((1, 0, 0))
        up, have = (up - d * up.dot(d)).normalized(), (have - d * have.dot(d)).normalized()
        turn_about(arm, att, have.rotation_difference(up), att.head.copy())
    print("ARM", side, "elbow %d" % elbow, "fist roll %d" % roll, "wrist bend %.0f" % bend,
          "off dir %.0f" % math.degrees(d.angle(want)), "score %.0f" % score,
          "far end at", tuple(round(c, 2) for c in att.head + d * max(spec.get("clear", (0.0,)))))


## relaxed hand: (proximal, intermediate) curl in degrees per finger, about the model team's curl axis
RELAXED = {"Index": (12, 18), "Middle": (16, 22), "Ring": (20, 26), "Little": (24, 30)}


def build_stance(arm, set_name, ref):
    """The static idle pose: the Stand frame made calm and grounded (3/4 turn, spine straight, shoulders
    relaxed, chin level, soft knees over the toes), gender-neutral (no hip pop, no hand on the hip,
    no chest arch or head tilt), each arm posed by its spec with clean joints. Returns the pinned hands."""
    st = STANCES[set_name]
    P = arm.pose.bones
    crouch = st.get("crouch", 0.0)
    P["Hips"].location = arm.data.bones["Hips"].matrix_local.to_3x3().inverted() @ Vector((0, 0, -0.012 - 0.05 * crouch))
    bpy.context.view_layer.update()
    for name, axis, deg in (("Hips", UP, TURN), ("Spine", SIDE, 3.0 + 8.0 * crouch), ("Chest", SIDE, 2.0 * crouch),
                            ("LeftShoulder", FRONT, 2.0), ("LeftShoulder", UP, 2.0),
                            ("RightShoulder", FRONT, -2.0 - 4.0 * st.get("heavy", 0)), ("RightShoulder", UP, -2.0), ("Neck", UP, -0.4 * TURN),
                            ("Head", UP, -0.4 * TURN), ("Head", SIDE, -3.0 - 10.0 * crouch)):
        turn_about(arm, P[name], q(axis, deg))
    pinned = {}
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        spec = st[side]
        if "hang" in spec:  # hanging a little forward, hand just in front of the thigh, elbow soft, wrist straight
            aim_arm(arm, side, body((sign * 0.13, -0.25, -1.0)), body((sign * 0.3, 1.0, 0.0)), 25.0, ref)
            for finger, (a, b) in RELAXED.items():
                for bone, deg in ((side + finger + "Proximal", a), (side + finger + "Intermediate", b)):
                    P[bone].rotation_quaternion = Quaternion(ref[bone], math.radians(deg))
            for bone in (side + "ThumbProximal", side + "ThumbDistal"):
                P[bone].rotation_quaternion = Quaternion().slerp(ref[bone + "_q"], 0.4)
        elif "carry" in spec:  # hanging like a free arm, a little further out so the weapon clears the leg
            att = P["attach_weapon." + side[0]]
            rel = P[side + "Hand"].matrix.inverted() @ att.matrix  # the model team's grip
            if "hand" in spec:  # the wrist placed higher (elbow bent), e.g. holding a tall spear
                reach_arm(arm, side, body(spec["hand"]), body((sign * 0.3, 1.0, -0.3)), ref)
                P[side + "Hand"].rotation_quaternion = Quaternion()
                bpy.context.view_layer.update()
            else:
                aim_arm(arm, side, body((sign * 0.24, -0.2, -1.0)), body((sign * 0.3, 1.0, 0.0)), 15.0, ref)
            att.matrix = P[side + "Hand"].matrix @ rel
            bpy.context.view_layer.update()
            if "dir" in spec:
                d = att.matrix.to_3x3() @ Vector((0, 1, 0))
                turn_about(arm, att, d.rotation_difference(body(spec["dir"]).normalized()), att.head.copy())
                d = body(spec["dir"]).normalized()
                if "head" in spec:
                    up = body(spec["head"])
                    have = att.matrix.to_3x3() @ Vector((1, 0, 0))
                    up, have = (up - d * up.dot(d)).normalized(), (have - d * have.dot(d)).normalized()
                    turn_about(arm, att, have.rotation_difference(up), att.head.copy())
                if "low" in spec:  # slide the weapon through the fist until its low end is just off the floor
                    slide = (FLOOR_GAP - att.head.z) / d.z - spec["low"]
                    att.matrix = Matrix.Translation(d * slide) @ att.matrix
                    bpy.context.view_layer.update()
                    print("CARRY", set_name, side, "hand at %.2f m along the weapon (from its grip point)" % -slide)
                print("CARRY", set_name, side, "socket", tuple(round(c, 3) for c in att.head))
        elif "keep" in spec:  # the Stand arm, a little forward and the elbow a little more bent
            turn_about(arm, P[side + "UpperArm"], q(SIDE, -12.0 * crouch))
            P[side + "LowerArm"].rotation_quaternion = P[side + "LowerArm"].rotation_quaternion @ Quaternion(
                ref[side + "hinge"], math.radians(18.0 * crouch))
        else:
            pose_weapon_arm(arm, side, spec, ref)
            if spec.get("pin") == "world":
                pinned[side] = None
    bpy.context.view_layer.update()
    return pinned


def idle_life(t, st):
    """({bone: [(armature axis, degrees)]}, hips offset in metres) at t seconds, on top of the stance.
    Weight leans a little onto the left leg, carried by the whole torso (small hip tilt, the chest
    straightens it again) and once per loop moves across to the right leg and back; the chest and
    shoulders breathe; the head glances off, holds and comes back, kept level; hair, cape and free
    arms trail behind."""
    tau = 2.0 * math.pi
    b = math.sin(tau * t * 3.0 / IDLE_SECONDS)  # breath: + = inhale
    lag = lambda d: math.sin(tau * t * 3.0 / IDLE_SECONDS - d)
    ww = lambda d: math.sin(tau * t / IDLE_SECONDS - d)
    swap = 0.5 - 0.5 * math.cos(tau * (t - 4.2) / 2.8) if 4.2 <= t <= 7.0 else 0.0
    w = 0.85 + 0.15 * ww(0.0) - 1.65 * swap  # + = on the left leg, - = on the right
    look = math.tanh(2.5 * math.sin(tau * t / IDLE_SECONDS + 2.6)) / math.tanh(2.5)  # turn, hold, back
    on_l, on_r = max(w, 0.0), max(-w, 0.0)
    knee = {s: q(UP, TURN + FEET[s][1]) @ SIDE for s in FEET}
    r = {
        "Hips": [(FRONT, -2.0 * w), (UP, 1.5 * w)],
        "Spine": [(FRONT, 0.6 * w), (UP, -0.6 * w + 1.0 * look), (SIDE, -0.6 * b)],
        "Chest": [(FRONT, 0.4 * w), (SIDE, -2.5 * b), (UP, -0.6 * w + 1.0 * look)],
        "UpperChest": [(SIDE, -2.0 * b)],
        "LeftShoulder": [(FRONT, -3.0 * lag(0.3))],
        "RightShoulder": [(FRONT, 3.0 * lag(0.3))],
        "Neck": [(SIDE, 1.5 * b), (UP, 4.0 * look)],
        "Head": [(SIDE, 1.5 * lag(0.5)), (UP, 8.0 * look)],
        # the unloaded knee softens, bending over its toes (knee axis follows the foot); IK keeps the feet down
        "LeftUpperLeg": [(knee["Left"], -4.0 - 5.0 * on_r)], "LeftLowerLeg": [(knee["Left"], 8.0 + 10.0 * on_r)],
        "RightUpperLeg": [(knee["Right"], -4.0 - 5.0 * on_l)], "RightLowerLeg": [(knee["Right"], 8.0 + 10.0 * on_l)],
        "HairBack1": [(SIDE, 2.5 * lag(1.2)), (FRONT, 3.0 * ww(1.0) - 2.0 * swap)],
        "HairBack2": [(SIDE, 3.5 * lag(1.7)), (FRONT, 4.0 * ww(1.5) - 3.0 * swap)],
        "Cape1": [(SIDE, 1.5 * lag(1.0)), (FRONT, 2.0 * ww(0.8))],
        "Cape2": [(SIDE, 2.5 * lag(1.5)), (FRONT, 3.0 * ww(1.3))],
        "Cape3": [(SIDE, 3.5 * lag(2.0)), (FRONT, 4.0 * ww(1.8))],
    }
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        spec = st[side]
        if "hang" in spec:
            r[side + "UpperArm"] = [(FRONT, sign * 2.0 * ww(0.6)), (SIDE, 3.0 * lag(0.4) - 2.0 * ww(0.9))]
            r[side + "LowerArm"] = [(SIDE, -3.0 * lag(0.8))]
            r[side + "Hand"] = [(SIDE, -4.0 * lag(1.2))]
        elif "carry" in spec:  # weighted pendulum: shoulder leads, elbow and wrist trail it
            amp, n = spec["swing"]
            sw = lambda d: amp * math.sin(tau * t * n / IDLE_SECONDS - d) + 0.4 * amp * ww(0.9 + d)
            r[side + "UpperArm"] = [(SIDE, sw(0.0)), (FRONT, sign * 0.3 * sw(0.4))]
            r[side + "LowerArm"] = [(SIDE, 0.6 * sw(0.6))]
            r[side + "Hand"] = [(SIDE, 0.8 * sw(1.2))]
        elif "keep" in spec or ("grip" in spec and spec.get("pin") != "world"):
            r[side + "UpperArm"] = [(SIDE, 2.0 * lag(0.4))]
            r[side + "LowerArm"] = [(SIDE, -1.5 * lag(0.8))]
    hips = Vector((0.02 * w, 0.0, -0.004 * b - 0.006 * swap))  # toward the standing foot
    return r, hips


def stand_ref(arm):
    """The model team's StandDagger as a reference: elbow hinge axes, finger curl axes, thumb pose."""
    ref = {}
    arm.animation_data.action = bpy.data.actions["StandDagger"]
    bpy.context.scene.frame_set(int(bpy.data.actions["StandDagger"].frame_range[0]))
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        qq = pb.rotation_quaternion.copy()
        ref[pb.name + "_q"] = qq
        ref[pb.name] = qq.axis.normalized() if qq.angle > 0.01 else None
    for s in ("Left", "Right"):
        ref[s + "hinge"] = ref[s + "LowerArm"]
        for finger in RELAXED:
            for part in ("Proximal", "Intermediate"):
                if ref[s + finger + part] is None:
                    ref[s + finger + part] = ref[s + "Index" + part]
    return ref


def build_idle(arm, set_name):
    """IDLE_LIFE: build_stance, the idle_life layer on top, feet (and planted / on-hip hands) held in
    place by IK, baked to plain keys."""
    st = STANCES[set_name]
    base_act = bpy.data.actions[st["base"]]
    arm.animation_data_create()
    arm.animation_data.action = base_act
    scene = bpy.context.scene
    scene.frame_set(int(base_act.frame_range[0]))
    feet = {s: (arm.pose.bones[s + "Foot"].head.copy(), arm.pose.bones[s + "Foot"].matrix.to_quaternion())
            for s in ("Left", "Right")}
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    ref = stand_ref(arm)
    arm.animation_data.action = base_act
    scene.frame_set(int(base_act.frame_range[0]))
    arm.animation_data.action = None
    pinned = build_stance(arm, set_name, ref)
    P = arm.pose.bones
    base = {pb.name: pb.rotation_quaternion.copy() for pb in P}
    base_loc = {pb.name: pb.location.copy() for pb in P}
    frame = {pb.name: pb.matrix.to_quaternion() for pb in P}  # armature-space rotation
    pins, checks = [], []

    def pin(name, mat, parent_bone=None):
        target = bpy.data.objects.new("pin_" + name, None)
        scene.collection.objects.link(target)
        if parent_bone:
            target.parent, target.parent_type, target.parent_bone = arm, 'BONE', parent_bone
        bpy.context.view_layer.update()
        target.matrix_world = arm.matrix_world @ mat
        pins.append(target)
        return target

    for s, (pos, rot) in feet.items():
        offset, toe = FEET[s]
        target = pin(s + "Foot", Matrix.Translation(body(pos + offset)) @ (q(UP, TURN + toe) @ rot).to_matrix().to_4x4())
        ik = P[s + "LowerLeg"].constraints.new('IK')
        ik.target, ik.chain_count = target, 2
        P[s + "Foot"].constraints.new('COPY_ROTATION').target = target
        checks.append((s + "Foot", body(pos + offset), False))
    for s, parent in pinned.items():
        hand = P[s + "Hand"]
        target = pin(s + "Hand", Matrix.Translation(hand.tail) @ hand.matrix.to_quaternion().to_matrix().to_4x4(), parent)
        ik = hand.constraints.new('IK')  # hand -> lower arm -> upper arm (the hand's parent is LowerArm)
        ik.target, ik.chain_count, ik.use_rotation = target, 3, True
        checks.append((s + "Hand", hand.tail.copy(), parent is not None))
    hips_rest = arm.data.bones["Hips"].matrix_local.to_3x3().inverted()
    act = bpy.data.actions.new("IDLE_LIFE")
    arm.animation_data.action = act
    fps = scene.render.fps
    frames = int(round(IDLE_SECONDS * fps))
    for f in range(0, frames + 1, 2):
        rots, hips = idle_life(f / fps, st)
        for pb in P:
            qq = base[pb.name]
            m = frame[pb.name]  # an armature-space turn, said in the bone's own axes
            for axis, deg in rots.get(pb.name, ()):
                qq = qq @ (m.inverted() @ q(axis, deg) @ m)
            pb.rotation_quaternion = qq
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.location = base_loc[pb.name] + (hips_rest @ hips if pb.name == "Hips" else Vector())
            pb.keyframe_insert("location", frame=f)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.nla.bake(frame_start=0, frame_end=frames, step=1, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=True, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    for target in pins:
        bpy.data.objects.remove(target, do_unlink=True)
    act = arm.animation_data.action
    for fc in act.fcurves:  # close the loop exactly (IK solves can differ in the last digits)
        fc.keyframe_points[-1].co[1] = fc.keyframe_points[0].co[1]
    for check_frame in (frames // 4, frames * 5 // 8):
        scene.frame_set(check_frame)
        for name, where, moves in checks:
            if not moves:
                pb = P[name]
                print("IDLE", set_name, name, "f%d drift %.4f m" % (check_frame, ((pb.head if "Foot" in name else pb.tail) - where).length))
    return act


## ---- Attack clips (docs/design/attack_moves.md) ----
## Authored ATTACK_SCALE times slower than the game plays them (1 tick = 2 frames at 24 fps), so every key
## lands on a frame; client/animation_set.gd time-warps 0..windup_end over startup, windup_end..strike_end
## over active and the rest over recovery, so only the marks matter, not the length.
ATTACK_SCALE = 5.0
## A key: "t" tick; body: "twist" (hips yaw, + = face turns to its left), "chest" (extra yaw above the
## hips), "lean" (forward), "drop" (metres down), "shift" (metres to its left), "fwd" (hips metres forward,
## the weight going onto the front foot); feet: "lf"/"rf" (dx, dy) of the ball of the foot from the idle
## stance (-y = forward), held until a later key moves it again (a move is a lifted step, see
## build_attack; the hips sink by themselves if a leg could not reach with a bent knee); weapon hand: "rh" grip point, "rdir" blade direction, "relbow"
## elbow hint; free hand: "lh" wrist point (else it hangs); "lfturn"/"rfturn" toe turn (degrees, a foot
## pivoting on its ball, also held). Positions are armature space (faces -y, its right is -x). Key "idle" = the idle stance;
## "end": True marks a clip's follow-through pose, and {"from": <clip>} starts a combo hit in that pose
## (combo hand-off). Hair and cape trail the body's turn between keys. Clips end in the idle stance.
ATTACKS = {
    "chibi_blade": {
        "light_1": {"ticks": (4, 3, 11), "keys": [
            {"t": 0, "idle": True},
            {"t": 2, "twist": -20, "chest": -10, "lean": 6, "drop": 0.06,
             "rh": (-0.32, 0.02, 0.86), "rdir": (-0.9, 0.4, 0.0), "relbow": (-0.8, 0.6, -0.6), "lh": (0.15, -0.30, 0.90)},
            {"t": 4, "twist": -35, "chest": -22, "lean": 10, "drop": 0.10, "rfturn": 8,
             "rh": (-0.40, 0.02, 0.88), "rdir": (-0.92, 0.38, 0.05), "relbow": (-0.8, 0.6, -0.6), "lh": (0.18, -0.32, 0.92)},
            {"t": 5, "twist": 0, "chest": -20, "lean": 14, "drop": 0.12, "lf": (0.05, -0.22), "fwd": 0.04,
             "rh": (-0.20, -0.36, 0.90), "rdir": (-0.55, -0.83, 0.0), "relbow": (-1.0, 0.0, -0.6), "lh": (0.25, -0.10, 0.90)},
            {"t": 6, "twist": 25, "chest": -5, "lean": 15, "drop": 0.12, "fwd": 0.06,
             "rh": (0.05, -0.42, 0.90), "rdir": (0.3, -0.95, 0.0), "relbow": (-0.6, 0.0, -1.0), "lh": (0.30, 0.10, 0.88)},
            {"t": 7, "twist": 38, "chest": 12, "lean": 14, "drop": 0.12, "rfturn": -18, "fwd": 0.06,
             "rh": (0.26, -0.26, 0.90), "rdir": (0.97, -0.2, -0.05), "relbow": (-0.2, 0.3, -1.0), "lh": (0.28, 0.22, 0.90)},
            {"t": 9, "twist": 46, "chest": 20, "lean": 12, "drop": 0.13, "fwd": 0.06,
             "rh": (0.30, -0.05, 0.86), "rdir": (0.7, 0.65, -0.25), "relbow": (0.0, 0.6, -1.0), "lh": (0.25, 0.25, 0.88)},
            {"t": 12, "end": True, "twist": 40, "chest": 16, "lean": 10, "drop": 0.11, "fwd": 0.05,
             "rh": (0.28, -0.10, 0.86), "rdir": (0.75, 0.55, -0.3), "relbow": (0.0, 0.6, -1.0), "lh": (0.24, 0.20, 0.88)},
            {"t": 18, "idle": True},
        ]},
        "light_2": {"ticks": (4, 3, 11), "keys": [
            {"t": 0, "from": "light_1"},
            {"t": 4, "twist": 46, "chest": 22, "lean": 10, "drop": 0.12, "fwd": 0.05,
             "rh": (0.30, -0.08, 0.76), "rdir": (0.7, 0.5, -0.5), "relbow": (0.0, 0.6, -1.0), "lh": (0.20, -0.30, 0.95)},
            {"t": 5, "twist": 20, "chest": 28, "lean": 12, "drop": 0.12, "fwd": 0.05,
             "rh": (0.12, -0.40, 0.86), "rdir": (0.4, -0.85, 0.35), "relbow": (-0.4, 0.2, -1.0), "lh": (0.20, -0.20, 0.90)},
            {"t": 6, "twist": -10, "chest": 10, "lean": 10, "drop": 0.10, "fwd": 0.04,
             "rh": (-0.14, -0.40, 1.02), "rdir": (-0.45, -0.75, 0.5), "relbow": (-1.0, 0.0, -0.6), "lh": (0.30, 0.0, 0.88)},
            {"t": 7, "twist": -35, "chest": -15, "lean": 6, "drop": 0.07, "rf": (-0.02, 0.06), "rfturn": 10, "fwd": 0.02,
             "rh": (-0.32, -0.18, 1.14), "rdir": (-0.85, -0.2, 0.5), "relbow": (-1.0, 0.3, -0.2), "lh": (0.32, 0.12, 0.90)},
            {"t": 9, "twist": -44, "chest": -22, "lean": 4, "drop": 0.06, "fwd": 0.02,
             "rh": (-0.32, 0.0, 1.22), "rdir": (-0.55, 0.4, 0.73), "relbow": (-1.0, 0.2, 0.2), "lh": (0.30, 0.15, 0.90)},
            {"t": 12, "end": True, "twist": -38, "chest": -18, "lean": 5, "drop": 0.07, "fwd": 0.02,
             "rh": (-0.30, 0.02, 1.18), "rdir": (-0.6, 0.35, 0.72), "relbow": (-1.0, 0.2, 0.2), "lh": (0.28, 0.12, 0.90)},
            {"t": 18, "idle": True},
        ]},
        "light_3": {"ticks": (6, 3, 18), "keys": [
            {"t": 0, "from": "light_2"},
            {"t": 3, "twist": -40, "chest": -20, "lean": 0, "drop": 0.08, "lf": (0.02, -0.12), "fwd": 0.0,
             "rh": (-0.36, 0.0, 1.16), "rdir": (-0.8, 0.35, 0.5), "relbow": (-1.0, 0.2, 0.2), "lh": (0.20, -0.30, 1.0)},
            {"t": 6, "twist": -45, "chest": -25, "lean": -2, "drop": 0.10, "fwd": 0.02,
             "rh": (-0.36, 0.04, 1.22), "rdir": (-0.75, 0.4, 0.55), "relbow": (-1.0, 0.2, 0.2), "lh": (0.22, -0.32, 1.02)},
            {"t": 7, "twist": -12, "chest": -20, "lean": 14, "drop": 0.13, "lf": (0.12, -0.30), "fwd": 0.06,
             "rh": (-0.12, -0.38, 1.10), "rdir": (-0.3, -0.8, 0.5), "relbow": (-1.0, 0.0, -0.3), "lh": (0.25, -0.10, 0.95)},
            {"t": 8, "twist": 15, "chest": 0, "lean": 24, "drop": 0.17, "fwd": 0.08,
             "rh": (0.06, -0.44, 0.86), "rdir": (0.4, -0.88, -0.2), "relbow": (-0.6, 0.0, -1.0), "lh": (0.30, 0.10, 0.95)},
            {"t": 9, "twist": 32, "chest": 14, "lean": 30, "drop": 0.20, "rfturn": -15, "fwd": 0.10,
             "rh": (0.24, -0.32, 0.60), "rdir": (0.7, -0.3, -0.65), "relbow": (-0.2, 0.3, -1.0), "lh": (0.32, 0.20, 0.95)},
            {"t": 11, "twist": 40, "chest": 20, "lean": 34, "drop": 0.22, "fwd": 0.10,
             "rh": (0.28, -0.18, 0.52), "rdir": (0.65, 0.25, -0.72), "relbow": (0.0, 0.6, -1.0), "lh": (0.32, 0.25, 0.98)},
            {"t": 13, "end": True, "twist": 36, "chest": 16, "lean": 30, "drop": 0.20, "fwd": 0.10,
             "rh": (0.27, -0.20, 0.55), "rdir": (0.66, 0.2, -0.72), "relbow": (0.0, 0.6, -1.0), "lh": (0.30, 0.22, 0.96)},
            {"t": 19, "twist": 35, "chest": 15, "lean": 28, "drop": 0.19, "fwd": 0.09,
             "rh": (0.27, -0.19, 0.56), "rdir": (0.66, 0.2, -0.72), "relbow": (0.0, 0.6, -1.0), "lh": (0.30, 0.22, 0.96)},
            {"t": 24, "twist": 18, "chest": 8, "lean": 16, "drop": 0.15, "fwd": 0.05,
             "rh": (0.02, -0.12, 0.62), "rdir": (0.25, 0.25, -0.85), "relbow": (-0.4, 0.6, -1.0), "lh": (0.25, 0.10, 0.92)},
            {"t": 27, "idle": True},
        ]},
        "heavy": {"ticks": (13, 4, 24), "keys": [
            {"t": 0, "idle": True},
            {"t": 6, "twist": -30, "chest": -15, "lean": 10, "drop": 0.10, "fwd": -0.03,
             "rh": (-0.36, 0.06, 0.80), "rdir": (-0.85, 0.5, -0.1), "relbow": (-1.0, 0.5, -0.5), "lh": (0.15, -0.30, 0.95)},
            {"t": 13, "twist": -50, "chest": -25, "lean": 16, "drop": 0.16, "rfturn": 12, "fwd": -0.04,
             "rh": (-0.40, 0.10, 0.78), "rdir": (-0.8, 0.58, -0.15), "relbow": (-1.0, 0.5, -0.5), "lh": (0.10, -0.38, 1.0)},
            {"t": 14, "twist": -15, "chest": -25, "lean": 18, "drop": 0.16, "fwd": 0.02,
             "rh": (-0.22, -0.34, 0.92), "rdir": (-0.6, -0.8, 0.0), "relbow": (-1.0, 0.0, -0.6), "lh": (0.25, -0.15, 0.95)},
            # Boss option B (2026-10-10): the front step is ~24 cm (was 30), so the finish stands taller
            {"t": 15, "twist": 15, "chest": -5, "lean": 14, "drop": 0.11, "lf": (0.02, -0.24), "fwd": 0.08, "shift": 0.02,
             "rh": (0.04, -0.46, 1.0), "rdir": (0.2, -0.98, 0.05), "relbow": (-0.6, 0.0, -1.0), "lh": (0.30, 0.10, 0.95)},
            {"t": 17, "twist": 35, "chest": 15, "lean": 2, "drop": 0.03, "rfturn": -20, "fwd": 0.11, "shift": 0.04,
             "rh": (0.26, -0.32, 0.98), "rdir": (0.75, -0.3, 0.58), "relbow": (-0.3, 0.2, -1.0), "lh": (0.32, 0.20, 1.0)},
            # the back foot follows through (~12 cm) so the stance closes and the finish stands tall
            {"t": 20, "twist": 42, "chest": 20, "lean": -6, "drop": -0.02, "fwd": 0.14, "shift": 0.04, "rf": (-0.02, -0.12), "rfturn": -12,
             "rh": (0.28, -0.22, 1.0), "rdir": (0.6, 0.1, 0.8), "relbow": (-0.2, 0.3, -1.0), "lh": (0.32, 0.30, 0.95)},
            {"t": 23, "end": True, "twist": 38, "chest": 16, "lean": -4, "drop": 0.0, "fwd": 0.14, "shift": 0.04,
             "rh": (0.27, -0.24, 0.98), "rdir": (0.62, 0.05, 0.78), "relbow": (-0.2, 0.3, -1.0), "lh": (0.30, 0.30, 0.94)},
            {"t": 30, "twist": 37, "chest": 15, "lean": -3, "drop": 0.02, "fwd": 0.13, "shift": 0.03,
             "rh": (0.27, -0.24, 0.96), "rdir": (0.62, 0.05, 0.78), "relbow": (-0.2, 0.3, -1.0), "lh": (0.30, 0.30, 0.93)},
            {"t": 36, "twist": 10, "chest": 4, "lean": 6, "drop": 0.07, "lf": (0.0, 0.0), "fwd": 0.06,
             "rh": (-0.12, -0.22, 0.82), "rdir": (-0.3, 0.2, -0.93), "relbow": (-0.8, 0.5, -1.0)},
            {"t": 41, "idle": True},
        ]},
    },
    ## Hammer: a two-handed maul (left fist near the butt, "l2" -0.17). Big loads, the head lags the hands, the
    ## swing carries the body past the target (overshoot, back heel pivots), contacts are short, recoveries heave.
    "chibi_hammer": {
        "light_1": {"ticks": (6, 3, 15), "keys": [  # flat sweep R->L at hip height
            {"t": 0, "idle": True},
            {"t": 3, "twist": -30, "chest": -12, "lean": 4, "drop": 0.07, "fwd": -0.02, "l2": -0.17,
             "rh": (-0.14, 0.00, 0.80), "rdir": (-0.70, 0.45, -0.55), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 6, "twist": -48, "chest": -20, "lean": 6, "drop": 0.11, "fwd": -0.03, "lf": (0.06, -0.16), "l2": -0.17,
             "rh": (-0.14, 0.04, 0.84), "rdir": (-0.80, 0.55, 0.0), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 7, "twist": -15, "chest": -18, "lean": 10, "drop": 0.13, "fwd": 0.04, "l2": -0.17,
             "rh": (-0.10, -0.20, 0.84), "rdir": (-0.75, -0.65, 0.05), "relbow": (-1.0, 0.0, -0.6)},
            {"t": 8, "twist": 15, "chest": -2, "lean": 12, "drop": 0.14, "fwd": 0.06, "l2": -0.17,
             "rh": (0.02, -0.28, 0.84), "rdir": (0.05, -1.0, 0.02), "relbow": (-0.8, 0.0, -1.0)},
            {"t": 9, "twist": 40, "chest": 14, "lean": 12, "drop": 0.14, "fwd": 0.06, "rfturn": -15, "l2": -0.17,
             "rh": (0.12, -0.20, 0.84), "rdir": (0.80, -0.60, -0.02), "relbow": (-0.3, -0.2, -1.0)},
            {"t": 11, "twist": 55, "chest": 22, "lean": 12, "drop": 0.15, "fwd": 0.06, "rfturn": -25, "l2": -0.17,
             "rh": (0.14, -0.06, 0.82), "rdir": (0.90, 0.35, -0.20), "relbow": (0.0, -0.4, -1.0)},
            {"t": 14, "end": True, "twist": 50, "chest": 20, "lean": 10, "drop": 0.14, "fwd": 0.05, "l2": -0.17,
             "rh": (0.13, -0.08, 0.80), "rdir": (0.88, 0.25, -0.35), "relbow": (0.0, -0.4, -1.0)},
            {"t": 19, "twist": 20, "chest": 5, "lean": 6, "drop": 0.09, "fwd": 0.03,
             "rh": (-0.04, -0.14, 0.76), "rdir": (0.2, -0.35, -0.92), "relbow": (-0.8, 0.2, -1.0)},
            {"t": 24, "idle": True},
        ]},
        "light_2": {"ticks": (6, 3, 15), "keys": [  # backswing L->R, rising; the right foot steps up
            {"t": 0, "from": "light_1"},
            {"t": 3, "twist": 60, "chest": 24, "lean": 8, "drop": 0.14, "fwd": 0.04, "l2": -0.17,
             "rh": (0.14, 0.0, 0.84), "rdir": (0.75, 0.62, 0.0), "relbow": (0.0, -0.4, -1.0)},
            {"t": 6, "twist": 62, "chest": 25, "lean": 6, "drop": 0.13, "fwd": 0.03, "l2": -0.17,
             "rh": (0.14, 0.03, 0.86), "rdir": (0.65, 0.72, 0.15), "relbow": (0.0, -0.4, -1.0)},
            {"t": 7, "twist": 35, "chest": 15, "lean": 10, "drop": 0.12, "fwd": 0.05, "l2": -0.17,
             "rh": (0.08, -0.22, 0.90), "rdir": (0.70, -0.70, 0.12), "relbow": (-0.3, -0.2, -1.0)},
            {"t": 8, "twist": 5, "chest": 0, "lean": 10, "drop": 0.11, "fwd": 0.06, "l2": -0.17,
             "rh": (-0.03, -0.28, 0.94), "rdir": (-0.10, -0.98, 0.18), "relbow": (-0.8, 0.0, -1.0)},
            {"t": 9, "twist": -28, "chest": -14, "lean": 6, "drop": 0.09, "fwd": 0.06, "rf": (-0.05, -0.10), "rfturn": 0, "l2": -0.17,
             "rh": (-0.13, -0.18, 1.00), "rdir": (-0.80, -0.50, 0.30), "relbow": (-1.0, 0.0, -0.6)},
            {"t": 11, "twist": -42, "chest": -20, "lean": 2, "drop": 0.08, "fwd": 0.06, "l2": -0.17,
             "rh": (-0.17, -0.04, 1.04), "rdir": (-0.70, 0.35, 0.60), "relbow": (-1.0, 0.4, -0.3)},
            {"t": 14, "end": True, "twist": -40, "chest": -18, "lean": 3, "drop": 0.09, "fwd": 0.06, "l2": -0.17,
             "rh": (-0.16, -0.05, 1.02), "rdir": (-0.70, 0.30, 0.62), "relbow": (-1.0, 0.4, -0.3)},
            {"t": 19, "twist": -20, "chest": -6, "lean": 4, "drop": 0.08, "fwd": 0.03, "rf": (0.0, 0.0),
             "rh": (-0.15, -0.10, 0.82), "rdir": (-0.35, 0.05, -0.93), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 24, "idle": True},
        ]},
        "light_3": {"ticks": (8, 3, 24), "keys": [  # overhead slam into the floor in front, stuck, heaved out
            {"t": 0, "from": "light_2"},
            {"t": 4, "twist": -35, "chest": -15, "lean": -8, "drop": 0.05, "fwd": 0.0, "l2": -0.17,
             "rh": (-0.15, 0.04, 1.14), "rdir": (-0.35, 0.55, 0.76), "relbow": (-1.0, 0.3, 0.3)},
            {"t": 8, "twist": -30, "chest": -14, "lean": -12, "drop": 0.04, "fwd": -0.02, "l2": -0.17,
             "rh": (-0.13, 0.06, 1.18), "rdir": (-0.30, 0.78, 0.55), "relbow": (-1.0, 0.3, 0.3)},
            {"t": 9, "twist": -12, "chest": -6, "lean": 8, "drop": 0.10, "fwd": 0.04, "lf": (0.06, -0.24), "l2": -0.17,
             "rh": (-0.08, -0.16, 1.12), "rdir": (-0.12, -0.45, 0.88), "relbow": (-1.0, 0.2, 0.0)},
            {"t": 10, "twist": -3, "chest": 0, "lean": 22, "drop": 0.18, "fwd": 0.08, "l2": -0.17,
             "rh": (-0.04, -0.28, 0.82), "rdir": (0.0, -0.88, -0.48), "relbow": (-1.0, 0.2, -0.6)},
            {"t": 11, "twist": 0, "chest": 0, "lean": 28, "drop": 0.22, "fwd": 0.10, "l2": -0.17,
             "rh": (-0.03, -0.26, 0.56), "rdir": (0.0, -0.93, -0.36), "rhead": (0.0, 0.0, -1.0), "relbow": (-1.0, 0.3, -0.6)},
            {"t": 16, "twist": 0, "chest": 0, "lean": 30, "drop": 0.23, "fwd": 0.10, "l2": -0.17,
             "rh": (-0.03, -0.26, 0.55), "rdir": (0.0, -0.93, -0.36), "rhead": (0.0, 0.0, -1.0), "relbow": (-1.0, 0.3, -0.6)},
            {"t": 24, "twist": -15, "chest": -5, "lean": 14, "drop": 0.13, "fwd": 0.06, "rf": (0.0, 0.0), "l2": -0.17,
             "rh": (-0.12, -0.12, 0.78), "rdir": (-0.35, -0.55, -0.76), "relbow": (-1.0, 0.3, -0.6)},
            {"t": 30, "twist": -12, "chest": -4, "lean": 6, "drop": 0.07, "fwd": 0.02, "lf": (0.0, 0.0),
             "rh": (-0.15, -0.08, 0.76), "rdir": (-0.25, 0.05, -0.97), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 35, "idle": True},
        ]},
        "heavy": {"ticks": (18, 4, 33), "keys": [  # long coil, head far behind; golf swing low-right -> high-left
            {"t": 0, "idle": True},
            {"t": 6, "twist": -28, "chest": -12, "lean": 4, "drop": 0.08, "fwd": -0.02, "l2": -0.17,
             "rh": (-0.14, 0.02, 0.82), "rdir": (-0.55, 0.50, -0.67), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 12, "twist": -50, "chest": -22, "lean": 8, "drop": 0.13, "fwd": -0.03, "lf": (0.06, -0.10), "l2": -0.17,
             "rh": (-0.13, 0.06, 0.88), "rdir": (-0.45, 0.85, -0.28), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 18, "twist": -62, "chest": -26, "lean": 10, "drop": 0.16, "fwd": -0.04, "rfturn": 10, "l2": -0.17,
             "rh": (-0.12, 0.08, 0.92), "rdir": (-0.30, 0.93, -0.22), "relbow": (-1.0, 0.4, -0.4)},
            {"t": 19, "twist": -38, "chest": -20, "lean": 10, "drop": 0.17, "fwd": 0.0, "l2": -0.17,
             "rh": (-0.17, -0.10, 0.72), "rdir": (-0.62, -0.25, -0.74), "relbow": (-1.0, 0.2, -0.6)},
            {"t": 20, "twist": -8, "chest": -8, "lean": 8, "drop": 0.13, "fwd": 0.05, "l2": -0.17,
             "rh": (-0.06, -0.27, 0.70), "rdir": (-0.20, -0.95, -0.24), "relbow": (-1.0, 0.0, -0.8)},
            {"t": 21, "twist": 22, "chest": 6, "lean": 2, "drop": 0.05, "fwd": 0.07, "l2": -0.17,
             "rh": (0.06, -0.24, 0.95), "rdir": (0.30, -0.75, 0.59), "relbow": (-0.6, -0.2, -1.0)},
            {"t": 22, "twist": 42, "chest": 16, "lean": -4, "drop": 0.0, "fwd": 0.05, "rfturn": -22, "l2": -0.17,
             "rh": (0.13, -0.10, 1.10), "rdir": (0.50, -0.20, 0.84), "relbow": (-0.3, -0.4, -1.0)},
            {"t": 25, "twist": 55, "chest": 22, "lean": -8, "drop": 0.01, "fwd": 0.05, "rfturn": -25, "l2": -0.17,
             "rh": (0.18, 0.0, 1.10), "rdir": (0.55, 0.35, 0.76), "relbow": (0.0, -0.6, -1.0)},
            {"t": 30, "twist": 52, "chest": 20, "lean": -5, "drop": 0.03, "fwd": 0.05, "l2": -0.17,
             "rh": (0.17, -0.01, 1.08), "rdir": (0.55, 0.30, 0.78), "relbow": (0.0, -0.6, -1.0)},
            {"t": 38, "twist": 30, "chest": 8, "lean": 6, "drop": 0.10, "fwd": 0.05, "l2": -0.17,
             "rh": (0.06, -0.14, 0.86), "rdir": (0.40, -0.55, -0.73), "relbow": (-0.6, -0.2, -1.0)},
            {"t": 44, "twist": 5, "chest": 0, "lean": 4, "drop": 0.08, "fwd": 0.03, "rfturn": 0,
             "rh": (-0.10, -0.12, 0.78), "rdir": (-0.15, -0.15, -0.97), "relbow": (-1.0, 0.3, -0.6)},
            {"t": 49, "twist": 0, "drop": 0.06, "lf": (0.0, 0.0),
             "rh": (-0.14, -0.08, 0.76), "rdir": (-0.25, 0.05, -0.97), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 55, "idle": True},
        ]},
    },
    ## Spear: both hands on the shaft (right rear, left forward "l2" m toward the tip). Thrusts drive the rear
    ## hand forward and the shaft slides through the front fist (l2 0.42 -> 0.10); the body stays side-on
    ## (left shoulder forward), steps in on the front foot. One wide move: the heavy sweep.
    "chibi_spear": {
        "light_1": {"ticks": (5, 3, 12), "keys": [  # chest-high straight thrust, front-foot step
            {"t": 0, "idle": True},
            {"t": 3, "twist": -40, "chest": -12, "lean": 4, "drop": 0.07, "l2": 0.40,
             "rh": (-0.12, 0.06, 0.86), "rdir": (0.04, -1.0, 0.06), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 5, "twist": -50, "chest": -15, "lean": 4, "drop": 0.10, "fwd": -0.02, "l2": 0.42,
             "rh": (-0.11, 0.12, 0.88), "rdir": (0.03, -1.0, 0.04), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 6, "twist": -32, "chest": -12, "lean": 10, "drop": 0.11, "fwd": 0.05, "l2": 0.26,
             "rh": (-0.06, -0.12, 0.89), "rdir": (0.02, -1.0, 0.0), "relbow": (-0.8, 0.5, -0.5)},
            {"t": 8, "twist": -22, "chest": -14, "lean": 14, "drop": 0.11, "fwd": 0.09, "lf": (0.03, -0.18), "l2": 0.12,
             "rh": (-0.04, -0.30, 0.90), "rdir": (0.0, -1.0, -0.02), "relbow": (-1.0, 0.2, -0.5)},
            {"t": 10, "twist": -20, "chest": -14, "lean": 15, "drop": 0.11, "fwd": 0.10, "l2": 0.11,
             "rh": (-0.04, -0.33, 0.90), "rdir": (0.0, -1.0, -0.02), "relbow": (-1.0, 0.2, -0.5)},
            {"t": 12, "end": True, "twist": -26, "chest": -12, "lean": 12, "drop": 0.10, "fwd": 0.08, "l2": 0.17,
             "rh": (-0.06, -0.24, 0.90), "rdir": (0.01, -1.0, 0.0), "relbow": (-0.9, 0.4, -0.5)},
            {"t": 16, "twist": -38, "chest": -10, "lean": 6, "drop": 0.07, "fwd": 0.03, "lf": (0.0, 0.0),
             "rh": (-0.14, 0.0, 0.88), "rdir": (-0.02, -0.75, 0.66), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 20, "idle": True},
        ]},
        "light_2": {"ticks": (5, 3, 12), "keys": [  # head-high thrust, hips twist in, back foot pivots
            {"t": 0, "from": "light_1"},
            {"t": 3, "twist": -45, "chest": -15, "lean": 6, "drop": 0.09, "fwd": 0.04, "l2": 0.40,
             "rh": (-0.10, 0.08, 0.95), "rdir": (0.03, -0.99, 0.14), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 5, "twist": -52, "chest": -18, "lean": 6, "drop": 0.09, "fwd": 0.03, "l2": 0.42,
             "rh": (-0.10, 0.12, 0.97), "rdir": (0.03, -0.98, 0.18), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 6, "twist": -34, "chest": -12, "lean": 10, "drop": 0.09, "fwd": 0.07, "l2": 0.26,
             "rh": (-0.05, -0.12, 1.02), "rdir": (0.01, -0.99, 0.13), "relbow": (-0.9, 0.4, -0.3)},
            {"t": 8, "twist": -18, "chest": -16, "lean": 13, "drop": 0.09, "fwd": 0.10, "rfturn": 15, "l2": 0.12,
             "rh": (-0.03, -0.30, 1.04), "rdir": (0.0, -0.99, 0.10), "relbow": (-1.0, 0.2, -0.2)},
            {"t": 10, "twist": -17, "chest": -16, "lean": 14, "drop": 0.09, "fwd": 0.10, "l2": 0.11,
             "rh": (-0.03, -0.33, 1.04), "rdir": (0.0, -0.99, 0.10), "relbow": (-1.0, 0.2, -0.2)},
            {"t": 12, "end": True, "twist": -24, "chest": -12, "lean": 12, "drop": 0.09, "fwd": 0.08, "l2": 0.17,
             "rh": (-0.05, -0.24, 1.00), "rdir": (0.01, -0.99, 0.08), "relbow": (-0.9, 0.4, -0.4)},
            {"t": 16, "twist": -38, "chest": -10, "lean": 6, "drop": 0.07, "fwd": 0.03, "lf": (0.0, 0.0), "rfturn": 0,
             "rh": (-0.14, 0.0, 0.88), "rdir": (-0.02, -0.75, 0.66), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 20, "idle": True},
        ]},
        "light_3": {"ticks": (6, 3, 18), "keys": [  # deep load, long lunge thrust, held extension
            {"t": 0, "from": "light_2"},
            {"t": 3, "twist": -55, "chest": -18, "lean": 2, "drop": 0.12, "fwd": 0.02, "l2": 0.44,
             "rh": (-0.12, 0.14, 0.85), "rdir": (0.03, -1.0, 0.03), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 6, "twist": -60, "chest": -20, "lean": 2, "drop": 0.14, "fwd": 0.0, "l2": 0.45,
             "rh": (-0.12, 0.18, 0.84), "rdir": (0.03, -1.0, 0.02), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 7, "twist": -36, "chest": -14, "lean": 12, "drop": 0.15, "fwd": 0.08, "l2": 0.26,
             "rh": (-0.06, -0.12, 0.85), "rdir": (0.01, -1.0, 0.0), "relbow": (-0.8, 0.5, -0.5)},
            {"t": 9, "twist": -22, "chest": -14, "lean": 20, "drop": 0.18, "fwd": 0.14, "lf": (0.04, -0.25), "l2": 0.10,
             "rh": (-0.03, -0.38, 0.83), "rdir": (0.0, -1.0, -0.03), "relbow": (-1.0, 0.2, -0.4)},
            {"t": 15, "twist": -21, "chest": -14, "lean": 20, "drop": 0.18, "fwd": 0.14, "l2": 0.11,
             "rh": (-0.03, -0.37, 0.84), "rdir": (0.0, -1.0, -0.03), "relbow": (-1.0, 0.2, -0.4)},
            {"t": 21, "twist": -38, "chest": -10, "lean": 8, "drop": 0.10, "fwd": 0.05, "lf": (0.0, 0.0), "rfturn": 0, "l2": 0.32,
             "rh": (-0.13, 0.02, 0.88), "rdir": (-0.02, -0.85, 0.52), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 24, "twist": -25, "chest": -5, "lean": 3, "drop": 0.05,
             "rh": (-0.20, -0.04, 0.86), "rdir": (-0.05, -0.3, 0.95), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 27, "idle": True},
        ]},
        "heavy": {"ticks": (14, 4, 25), "keys": [  # shaft back over the right shoulder; wide sweep R->L, tip hooks up
            {"t": 0, "idle": True},
            {"t": 6, "twist": -45, "chest": -18, "lean": 4, "drop": 0.08, "l2": 0.18,
             "rh": (-0.05, -0.10, 0.96), "rdir": (-0.70, 0.55, 0.45), "relbow": (-0.8, 0.6, -0.2)},
            {"t": 14, "twist": -62, "chest": -22, "lean": 6, "drop": 0.13, "lf": (0.08, -0.12), "rfturn": 10, "l2": 0.18,
             "rh": (-0.04, -0.12, 0.95), "rdir": (-0.82, 0.52, 0.22), "relbow": (-0.8, 0.6, -0.2)},
            {"t": 15, "twist": -32, "chest": -14, "lean": 8, "drop": 0.13, "fwd": 0.03, "l2": 0.22,
             "rh": (-0.03, -0.22, 0.92), "rdir": (-0.95, -0.30, 0.04), "relbow": (-0.9, 0.3, -0.4)},
            {"t": 16, "twist": 2, "chest": -4, "lean": 8, "drop": 0.12, "fwd": 0.05, "l2": 0.24,
             "rh": (0.0, -0.26, 0.90), "rdir": (-0.35, -0.94, 0.0), "relbow": (-1.0, 0.0, -0.4)},
            {"t": 17, "twist": 32, "chest": 10, "lean": 6, "drop": 0.10, "fwd": 0.06, "l2": 0.22,
             "rh": (0.06, -0.22, 0.92), "rdir": (0.45, -0.88, 0.15), "relbow": (-0.8, -0.2, -0.4)},
            {"t": 18, "twist": 48, "chest": 18, "lean": 0, "drop": 0.06, "fwd": 0.06, "rfturn": -22, "l2": 0.20,
             "rh": (0.10, -0.14, 1.00), "rdir": (0.78, -0.32, 0.54), "relbow": (-0.6, -0.2, -0.6)},
            {"t": 21, "twist": 56, "chest": 22, "lean": -4, "drop": 0.03, "fwd": 0.06, "l2": 0.20,
             "rh": (0.10, -0.08, 1.06), "rdir": (0.60, 0.02, 0.80), "relbow": (-0.6, -0.2, -0.6)},
            {"t": 26, "twist": 53, "chest": 20, "lean": -3, "drop": 0.04, "fwd": 0.05, "l2": 0.20,
             "rh": (0.10, -0.09, 1.05), "rdir": (0.62, -0.05, 0.78), "relbow": (-0.6, -0.2, -0.6)},
            {"t": 35, "twist": 10, "chest": 2, "lean": 3, "drop": 0.06, "fwd": 0.02, "rfturn": 0, "lf": (0.0, 0.0),
             "rh": (-0.14, -0.06, 0.90), "rdir": (-0.10, 0.10, 0.99), "relbow": (-0.6, 0.8, -0.5)},
            {"t": 43, "idle": True},
        ]},
    },
    ## Daggers: reverse grip, one in each hand ("rdir"/"ldir" = where each blade points). Low crouch, fast
    ## mirrored rakes that open the arms wide, a scissor, a spin-load into a slash and a rising stab.
    "chibi_dagger": {
        "light_1": {"ticks": (3, 3, 8), "keys": [  # right hand crossed at the chest, backhand rake L->R
            {"t": 0, "idle": True},
            {"t": 2, "twist": 22, "chest": 12, "lean": 10, "drop": 0.09,
             "rh": (0.10, -0.18, 0.92), "rdir": (0.35, -0.30, -0.89), "relbow": (-0.6, -0.6, 0.2),
             "lh": (0.20, -0.04, 0.84), "ldir": (0.25, -0.35, -0.90)},
            {"t": 3, "twist": 28, "chest": 16, "lean": 12, "drop": 0.11,
             "rh": (0.12, -0.16, 0.92), "rdir": (0.35, -0.30, -0.89), "relbow": (-0.6, -0.6, 0.2),
             "lh": (0.20, -0.02, 0.84), "ldir": (0.25, -0.35, -0.90)},
            {"t": 4, "twist": 4, "chest": 0, "lean": 12, "drop": 0.11,
             "rh": (-0.04, -0.32, 0.92), "rdir": (-0.10, -0.65, -0.75), "relbow": (-0.9, 0.0, 0.0),
             "lh": (0.19, -0.06, 0.85), "ldir": (0.25, -0.35, -0.90)},
            {"t": 5, "twist": -24, "chest": -10, "lean": 12, "drop": 0.11,
             "rh": (-0.24, -0.26, 0.90), "rdir": (-0.50, -0.45, -0.74), "relbow": (-0.8, 0.4, -0.2),
             "lh": (0.18, -0.10, 0.86), "ldir": (0.20, -0.40, -0.90)},
            {"t": 6, "twist": -34, "chest": -16, "lean": 12, "drop": 0.12,
             "rh": (-0.34, -0.10, 0.88), "rdir": (-0.75, -0.05, -0.66), "relbow": (-0.6, 0.8, -0.2),
             "lh": (0.18, -0.12, 0.86), "ldir": (0.20, -0.40, -0.90)},
            {"t": 8, "end": True, "twist": -36, "chest": -18, "lean": 12, "drop": 0.12,
             "rh": (-0.34, -0.07, 0.87), "rdir": (-0.75, -0.05, -0.66), "relbow": (-0.6, 0.8, -0.2),
             "lh": (0.18, -0.12, 0.86), "ldir": (0.20, -0.40, -0.90)},
            {"t": 14, "idle": True},
        ]},
        "light_2": {"ticks": (3, 3, 8), "keys": [  # mirror: left hand crossed, rake R->L
            {"t": 0, "from": "light_1"},
            {"t": 2, "twist": -30, "chest": -18, "lean": 12, "drop": 0.12,
             "lh": (-0.10, -0.18, 0.92), "ldir": (-0.35, -0.30, -0.89), "lelbow": (0.6, -0.6, 0.2),
             "rh": (-0.22, -0.02, 0.84), "rdir": (-0.25, -0.35, -0.90), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 3, "twist": -32, "chest": -18, "lean": 12, "drop": 0.12,
             "lh": (-0.12, -0.16, 0.92), "ldir": (-0.35, -0.30, -0.89), "lelbow": (0.6, -0.6, 0.2),
             "rh": (-0.20, -0.02, 0.84), "rdir": (-0.25, -0.35, -0.90), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 4, "twist": -6, "chest": 0, "lean": 12, "drop": 0.11,
             "lh": (0.04, -0.32, 0.92), "ldir": (0.10, -0.65, -0.75), "lelbow": (0.9, 0.0, 0.0),
             "rh": (-0.19, -0.06, 0.85), "rdir": (-0.25, -0.35, -0.90), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 5, "twist": 22, "chest": 10, "lean": 12, "drop": 0.11,
             "lh": (0.24, -0.26, 0.90), "ldir": (0.50, -0.45, -0.74), "lelbow": (0.8, 0.4, -0.2),
             "rh": (-0.18, -0.10, 0.86), "rdir": (-0.20, -0.40, -0.90), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 6, "twist": 32, "chest": 16, "lean": 12, "drop": 0.12,
             "lh": (0.34, -0.10, 0.88), "ldir": (0.75, -0.05, -0.66), "lelbow": (0.6, 0.8, -0.2),
             "rh": (-0.18, -0.12, 0.86), "rdir": (-0.20, -0.40, -0.90), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 8, "end": True, "twist": 34, "chest": 18, "lean": 12, "drop": 0.12,
             "lh": (0.34, -0.07, 0.87), "ldir": (0.75, -0.05, -0.66), "lelbow": (0.6, 0.8, -0.2),
             "rh": (-0.18, -0.12, 0.86), "rdir": (-0.20, -0.40, -0.90), "relbow": (-1.0, 0.4, -0.6)},
            {"t": 14, "idle": True},
        ]},
        "light_3": {"ticks": (4, 3, 12), "keys": [  # arms crossed in an X, crouch, both blades scissor out
            {"t": 0, "from": "light_2"},
            {"t": 2, "twist": 0, "chest": 0, "lean": 14, "drop": 0.16,
             "rh": (0.08, -0.20, 0.92), "rdir": (0.40, -0.30, -0.87), "relbow": (-0.6, -0.6, 0.2),
             "lh": (-0.08, -0.22, 0.96), "ldir": (-0.40, -0.30, -0.87), "lelbow": (0.6, -0.6, 0.2)},
            {"t": 4, "twist": 0, "chest": 0, "lean": 16, "drop": 0.18,
             "rh": (0.10, -0.18, 0.90), "rdir": (0.40, -0.30, -0.87), "relbow": (-0.6, -0.6, 0.2),
             "lh": (-0.10, -0.20, 0.94), "ldir": (-0.40, -0.30, -0.87), "lelbow": (0.6, -0.6, 0.2)},
            {"t": 5, "twist": 0, "chest": 0, "lean": 16, "drop": 0.19, "fwd": 0.06, "lf": (0.03, -0.12),
             "rh": (-0.10, -0.34, 0.88), "rdir": (-0.20, -0.70, -0.68), "relbow": (-0.9, 0.0, 0.0),
             "lh": (0.10, -0.34, 0.90), "ldir": (0.20, -0.70, -0.68), "lelbow": (0.9, 0.0, 0.0)},
            {"t": 6, "twist": 0, "chest": 0, "lean": 17, "drop": 0.20, "fwd": 0.07,
             "rh": (-0.28, -0.22, 0.88), "rdir": (-0.60, -0.40, -0.70), "relbow": (-0.8, 0.4, -0.2),
             "lh": (0.28, -0.22, 0.88), "ldir": (0.60, -0.40, -0.70), "lelbow": (0.8, 0.4, -0.2)},
            {"t": 7, "twist": 0, "chest": 0, "lean": 18, "drop": 0.21, "fwd": 0.07,
             "rh": (-0.36, -0.05, 0.86), "rdir": (-0.80, 0.10, -0.60), "relbow": (-0.6, 0.8, -0.2),
             "lh": (0.36, -0.05, 0.86), "ldir": (0.80, 0.10, -0.60), "lelbow": (0.6, 0.8, -0.2)},
            {"t": 12, "twist": 0, "chest": 0, "lean": 18, "drop": 0.21, "fwd": 0.07,
             "rh": (-0.35, -0.06, 0.86), "rdir": (-0.80, 0.10, -0.60), "relbow": (-0.6, 0.8, -0.2),
             "lh": (0.35, -0.06, 0.86), "ldir": (0.80, 0.10, -0.60), "lelbow": (0.6, 0.8, -0.2)},
            {"t": 16, "twist": 0, "chest": 0, "lean": 10, "drop": 0.12, "fwd": 0.03, "lf": (0.0, 0.0),
             "rh": (-0.24, -0.06, 0.84), "rdir": (-0.25, -0.35, -0.90), "relbow": (-1.0, 0.4, -0.6),
             "lh": (0.24, -0.06, 0.84), "ldir": (0.25, -0.35, -0.90), "lelbow": (1.0, 0.4, -0.6)},
            {"t": 19, "idle": True},
        ]},
        "heavy": {"ticks": (9, 4, 17), "keys": [  # spin-load (back turned ~90), whip slash, rising left stab
            {"t": 0, "idle": True},
            {"t": 4, "twist": -55, "chest": -22, "lean": 8, "drop": 0.12, "rfturn": -25, "lfturn": -25,
             "rh": (-0.16, 0.14, 0.86), "rdir": (-0.30, 0.60, -0.74), "relbow": (-0.6, 0.8, 0.2),
             "lh": (-0.02, -0.22, 0.92), "ldir": (0.20, -0.40, -0.90), "lelbow": (1.0, 0.4, -0.6)},
            {"t": 9, "twist": -75, "chest": -28, "lean": 10, "drop": 0.14, "rfturn": -35, "lfturn": -35,
             "rh": (-0.10, 0.20, 0.86), "rdir": (-0.20, 0.70, -0.68), "relbow": (-0.6, 0.8, 0.2),
             "lh": (-0.06, -0.18, 0.90), "ldir": (0.20, -0.40, -0.90), "lelbow": (1.0, 0.4, -0.6)},
            {"t": 10, "twist": -35, "chest": -15, "lean": 10, "drop": 0.13,
             "rh": (-0.32, -0.08, 0.88), "rdir": (-0.55, -0.50, -0.67), "relbow": (-0.8, 0.4, 0.0),
             "lh": (0.04, -0.18, 0.88), "ldir": (0.20, -0.40, -0.90), "lelbow": (1.0, 0.4, -0.6)},
            {"t": 11, "twist": 5, "chest": 0, "lean": 10, "drop": 0.12, "rfturn": 0, "lfturn": 0,
             "rh": (-0.06, -0.36, 0.88), "rdir": (0.30, -0.75, -0.60), "relbow": (-0.9, 0.0, 0.0),
             "lh": (0.18, -0.12, 0.86), "ldir": (0.20, -0.40, -0.90), "lelbow": (1.0, 0.4, -0.6)},
            {"t": 12, "twist": 22, "chest": 8, "lean": 6, "drop": 0.08,
             "rh": (-0.20, -0.18, 0.90), "rdir": (-0.40, -0.40, -0.82), "relbow": (-1.0, 0.4, -0.6),
             "lh": (0.06, -0.34, 1.00), "ldir": (0.0, -0.50, 0.86), "lelbow": (1.0, 0.2, -0.6)},
            {"t": 13, "twist": 28, "chest": 10, "lean": 2, "drop": 0.05,
             "rh": (-0.22, -0.16, 0.90), "rdir": (-0.40, -0.40, -0.82), "relbow": (-1.0, 0.4, -0.6),
             "lh": (0.04, -0.34, 1.10), "ldir": (-0.05, -0.40, 0.92), "lelbow": (1.0, 0.2, -0.6)},
            {"t": 18, "twist": 26, "chest": 9, "lean": 8, "drop": 0.10,
             "rh": (-0.22, -0.14, 0.88), "rdir": (-0.40, -0.40, -0.82), "relbow": (-1.0, 0.4, -0.6),
             "lh": (0.04, -0.32, 1.06), "ldir": (-0.05, -0.45, 0.89), "lelbow": (1.0, 0.2, -0.6)},
            {"t": 24, "twist": 10, "chest": 3, "lean": 8, "drop": 0.10,
             "rh": (-0.18, -0.08, 0.84), "rdir": (-0.20, -0.40, -0.90), "relbow": (-1.0, 0.4, -0.6),
             "lh": (0.16, -0.12, 0.86), "ldir": (0.20, -0.40, -0.90), "lelbow": (1.0, 0.4, -0.6)},
            {"t": 30, "idle": True},
        ]},
    },
    ## Fists: a boxer. Guard at the chin, jab (left) / cross (right) with the shoulders and hips behind them,
    ## a dipping left hook, and a crouch-to-rising right uppercut finisher. rh/lh are wrist points.
    "chibi_fists": {
        "light_1": {"ticks": (4, 3, 10), "keys": [  # left jab, feet still
            {"t": 0, "idle": True},
            {"t": 2, "twist": -6, "chest": 0, "lean": 4, "drop": 0.06, "rh": (-0.10, -0.15, 1.02), "lh": (0.10, -0.18, 1.03)},
            {"t": 4, "twist": 6, "chest": 4, "lean": 6, "drop": 0.08, "rh": (-0.10, -0.15, 1.02), "lh": (0.12, -0.14, 1.01)},
            {"t": 5, "twist": -14, "chest": -6, "lean": 7, "drop": 0.08, "fwd": 0.02,
             "rh": (-0.10, -0.15, 1.02), "lh": (0.08, -0.30, 1.05), "lelbow": (1.0, 0.0, -0.6)},
            {"t": 7, "twist": -24, "chest": -10, "lean": 9, "drop": 0.08, "fwd": 0.03,
             "rh": (-0.09, -0.16, 1.03), "lh": (0.05, -0.38, 1.05), "lelbow": (1.0, 0.0, -0.4)},
            {"t": 9, "end": True, "twist": -16, "chest": -6, "lean": 8, "drop": 0.08, "fwd": 0.02,
             "rh": (-0.10, -0.15, 1.03), "lh": (0.09, -0.24, 1.04)},
            {"t": 13, "twist": -8, "chest": 0, "lean": 5, "drop": 0.07, "rh": (-0.10, -0.15, 1.02), "lh": (0.10, -0.18, 1.03)},
            {"t": 17, "idle": True},
        ]},
        "light_2": {"ticks": (4, 3, 10), "keys": [  # right cross, hips turn, back foot pivots
            {"t": 0, "from": "light_1"},
            {"t": 2, "twist": -14, "chest": -4, "lean": 7, "drop": 0.08, "rh": (-0.10, -0.14, 1.02), "lh": (0.10, -0.18, 1.03)},
            {"t": 4, "twist": -22, "chest": -8, "lean": 7, "drop": 0.09, "rh": (-0.13, -0.10, 1.01), "lh": (0.10, -0.20, 1.03)},
            {"t": 5, "twist": 2, "chest": 4, "lean": 9, "drop": 0.09, "fwd": 0.03,
             "rh": (-0.07, -0.30, 1.05), "relbow": (-1.0, 0.0, -0.6), "lh": (0.10, -0.16, 1.04)},
            {"t": 7, "twist": 28, "chest": 12, "lean": 11, "drop": 0.09, "fwd": 0.05, "rfturn": 22,
             "rh": (-0.04, -0.39, 1.05), "relbow": (-1.0, 0.0, -0.4), "lh": (0.10, -0.13, 1.04)},
            {"t": 9, "end": True, "twist": 20, "chest": 8, "lean": 9, "drop": 0.09, "fwd": 0.04,
             "rh": (-0.07, -0.25, 1.04), "lh": (0.10, -0.15, 1.04)},
            {"t": 13, "twist": 0, "chest": 0, "lean": 5, "drop": 0.07, "fwd": 0.01, "rfturn": 0,
             "rh": (-0.10, -0.15, 1.02), "lh": (0.10, -0.18, 1.03)},
            {"t": 17, "idle": True},
        ]},
        "light_3": {"ticks": (5, 3, 16), "keys": [  # dip, left hook with the elbow level, torso wraps right
            {"t": 0, "from": "light_2"},
            {"t": 3, "twist": 24, "chest": 10, "lean": 8, "drop": 0.14,
             "rh": (-0.08, -0.16, 1.03), "lh": (0.21, -0.10, 0.98), "lelbow": (1.0, 0.3, 0.2)},
            {"t": 5, "twist": 30, "chest": 12, "lean": 8, "drop": 0.15, "fwd": 0.03, "lf": (0.05, -0.12),
             "rh": (-0.08, -0.16, 1.03), "lh": (0.24, -0.08, 0.98), "lelbow": (1.0, 0.4, 0.4)},
            {"t": 6, "twist": 6, "chest": 0, "lean": 9, "drop": 0.14, "fwd": 0.05,
             "rh": (-0.08, -0.16, 1.03), "lh": (0.12, -0.32, 1.02), "lelbow": (1.0, 0.2, 0.7)},
            {"t": 7, "twist": -22, "chest": -12, "lean": 9, "drop": 0.13, "fwd": 0.06,
             "rh": (-0.08, -0.15, 1.03), "lh": (-0.06, -0.35, 1.02), "lelbow": (0.6, -0.3, 0.8)},
            {"t": 8, "twist": -38, "chest": -18, "lean": 8, "drop": 0.12, "fwd": 0.06, "rfturn": 0, "lfturn": -20,
             "rh": (-0.08, -0.14, 1.03), "lh": (-0.17, -0.25, 1.00), "lelbow": (0.2, -0.6, 0.8)},
            {"t": 12, "twist": -45, "chest": -20, "lean": 8, "drop": 0.12, "fwd": 0.06,
             "rh": (-0.08, -0.14, 1.03), "lh": (-0.19, -0.21, 0.99), "lelbow": (0.2, -0.6, 0.8)},
            {"t": 18, "twist": -14, "chest": 0, "lean": 5, "drop": 0.08, "fwd": 0.03, "lf": (0.0, 0.0), "lfturn": 0,
             "rh": (-0.10, -0.15, 1.02), "lh": (0.10, -0.18, 1.03)},
            {"t": 24, "idle": True},
        ]},
        "heavy": {"ticks": (12, 4, 22), "keys": [  # deep crouch, right fist by the hip, rising uppercut
            {"t": 0, "idle": True},
            {"t": 5, "twist": -22, "chest": -10, "lean": 12, "drop": 0.12,
             "rh": (-0.18, -0.04, 0.82), "relbow": (-0.6, 0.8, -0.4), "lh": (0.10, -0.20, 1.02)},
            {"t": 12, "twist": -34, "chest": -14, "lean": 16, "drop": 0.19, "fwd": 0.04, "lf": (0.03, -0.10),
             "rh": (-0.20, -0.02, 0.76), "relbow": (-0.6, 0.8, -0.4), "lh": (0.11, -0.20, 1.00)},
            {"t": 13, "twist": -12, "chest": -6, "lean": 10, "drop": 0.12, "fwd": 0.07,
             "rh": (-0.11, -0.24, 0.88), "relbow": (-0.8, 0.2, -0.8), "lh": (0.12, -0.18, 1.00)},
            {"t": 14, "twist": 12, "chest": 4, "lean": 2, "drop": 0.03, "fwd": 0.08,
             "rh": (-0.06, -0.30, 1.12), "relbow": (-0.6, 0.0, -1.0), "lh": (0.15, -0.10, 0.96)},
            {"t": 16, "twist": 20, "chest": 12, "lean": -5, "drop": -0.03, "fwd": 0.05, "shift": 0.02, "rfturn": 20,
             "rh": (-0.07, -0.30, 1.30), "relbow": (-0.6, 0.2, -1.0), "lh": (0.18, 0.0, 0.90)},
            {"t": 20, "twist": 22, "chest": 14, "lean": -7, "drop": -0.04, "fwd": 0.05, "shift": 0.02,
             "rh": (-0.07, -0.29, 1.33), "relbow": (-0.6, 0.2, -1.0), "lh": (0.18, 0.0, 0.90)},
            {"t": 26, "twist": 20, "chest": 11, "lean": -4, "drop": 0.0, "fwd": 0.05, "shift": 0.02,
             "rh": (-0.08, -0.28, 1.28), "relbow": (-0.6, 0.2, -1.0), "lh": (0.17, -0.02, 0.92)},
            {"t": 32, "twist": 5, "chest": 0, "lean": 4, "drop": 0.06, "fwd": 0.03, "rfturn": 0, "lf": (0.0, 0.0),
             "rh": (-0.10, -0.15, 1.02), "lh": (0.10, -0.18, 1.03)},
            {"t": 38, "idle": True},
        ]},
    },
}


LEG_REACH = 0.95  # a leg never straightens past this share of its length (IK keeps a soft knee, no pop)
STEP_TICKS = 4.0  # a step (lift, arc, land) takes at most this long, ending on the key that places the foot
STEP_LIFT = 0.06  # metres of foot clearance at the top of a step's arc
HEEL_OFF = 15.0  # degrees the foot rolls onto its ball as a step starts (heel first off, toe last)
PIVOT_HEEL = 8.0  # degrees the heel comes up while the foot pivots on its ball in a big twist


def pose_attack_key(arm, set_name, k, base, base_loc, ankles, leg_len, ref, prev_yaw=0.0):
    """Sets the pose of one attack key (from the idle stance). `ankles` are the foot targets of this key
    (armature space): the hips sink as far as needed for both legs to reach them with a bent knee.
    `prev_yaw` is the body turn of the key before: hair and cape lag behind the change."""
    P = arm.pose.bones
    for pb in P:
        pb.rotation_quaternion = base[pb.name].copy()
        pb.location = base_loc[pb.name].copy()
    bpy.context.view_layer.update()
    if k.get("idle"):
        return
    twist, chest, lean = k.get("twist", 0.0) - TURN, k.get("chest", 0.0), k.get("lean", 0.0)
    hips_rest = arm.data.bones["Hips"].matrix_local.to_3x3().inverted()
    P["Hips"].location = base_loc["Hips"] + hips_rest @ Vector(
        (k.get("shift", 0.0), -k.get("fwd", 0.0), -k.get("drop", 0.0)))
    bpy.context.view_layer.update()
    turn_about(arm, P["Hips"], q(UP, twist))
    sink = 0.0  # extra drop so neither leg has to straighten (both feet stay on their targets)
    for s, ankle in ankles.items():
        d = ankle - P[s + "UpperLeg"].head
        reach = (LEG_REACH * leg_len[s]) ** 2 - d.xy.length_squared
        sink = max(sink, -d.z - math.sqrt(max(reach, 0.0)))
    if sink > 0.002:
        P["Hips"].location = P["Hips"].location + hips_rest @ Vector((0.0, 0.0, -sink))
        bpy.context.view_layer.update()
        print("KEY t%s: hips sink %.1f cm more so the legs keep a bent knee" % (k["t"], 100 * sink))
    counter = -0.7 * (k.get("twist", 0.0) + chest)
    for name, axis, deg in (("Spine", UP, 0.5 * chest), ("Spine", SIDE, 0.5 * lean),
                            ("Chest", UP, 0.5 * chest), ("Chest", SIDE, 0.5 * lean),
                            ("Neck", UP, 0.4 * counter), ("Head", UP, 0.6 * counter), ("Head", SIDE, -0.7 * lean)):
        turn_about(arm, P[name], q(axis, deg))
    turn = k.get("twist", 0.0) + chest - prev_yaw  # hair and cape trail the turn and lift with it
    for name, lag in (("HairBack1", 0.25), ("HairBack2", 0.4), ("Cape1", 0.2), ("Cape2", 0.3), ("Cape3", 0.4)):
        if name in P:
            turn_about(arm, P[name], q(UP, -lag * turn) @ q(SIDE, -0.15 * abs(turn) * lag))
    style = ATTACK_STYLE[set_name]
    tip = style.get("tip", 1.0)  # -1: the blade runs along the socket's -y (daggers), rdir/ldir say where the blade points
    if style["hands"] == "fists":
        for side, c, hint in (("Right", "r", (-1.0, 0.3, -0.6)), ("Left", "l", (1.0, 0.3, -0.6))):
            reach_arm(arm, side, Vector(k[c + "h"]), Vector(k.get(c + "elbow", hint)), ref)
            report_reach(arm, side, Vector(k[c + "h"]), k["t"])
            if c + "roll" in k:  # turn the fist about the forearm (palm down / vertical fist), shared by forearm and wrist
                roll = k[c + "roll"] * (1.0 if side == "Right" else -1.0)
                P[side + "LowerArm"].rotation_quaternion = P[side + "LowerArm"].rotation_quaternion @ q(Vector((0, 1, 0)), roll / 2)
                P[side + "Hand"].rotation_quaternion = q(Vector((0, 1, 0)), roll / 2)
            grip_fingers(arm, side, ref)
        bpy.context.view_layer.update()
        return
    for bone in ("attach_weapon.R", "attach_weapon.L"):  # attacks hold the weapon at the model team's grip point
        P[bone].location = Vector()  # (the idle carry may slide it through the fist; it slides back over the wind-up)
    bpy.context.view_layer.update()
    spec = {"grip": k["rh"], "dir": tuple(tip * c for c in k["rdir"]), "elbow": k["relbow"], "orient": True}
    if "rhead" in k:
        spec["head"] = k["rhead"]
    pose_weapon_arm(arm, "Right", spec, ref)
    report_reach(arm, "attach_weapon.R", Vector(k["rh"]), k["t"])
    if style["hands"] == "dual":
        pose_weapon_arm(arm, "Left", {"grip": k["lh"], "dir": tuple(tip * c for c in k["ldir"]),
                                      "elbow": k.get("lelbow", (1.0, 0.4, -0.6)), "orient": True}, ref)
        report_reach(arm, "attach_weapon.L", Vector(k["lh"]), k["t"])
    elif "l2" in k:  # both hands on the haft
        grip_shaft(arm, k, style["shaft"], ref)
    elif "lh" in k:
        reach_arm(arm, "Left", Vector(k["lh"]), Vector((1.0, 0.4, -1.0)), ref)
    else:
        aim_arm(arm, "Left", Vector((0.2, -0.2, -1.0)), Vector((0.3, 1.0, 0.0)), 30.0, ref)
    bpy.context.view_layer.update()


## How each set's hands work in attacks: "one" (weapon right, free left hand), "two" (weapon right, the left
## hand on the haft "l2" metres from the right fist toward the head/tip; it slides along the shaft range to a
## point the short arm reaches), "dual" (a weapon in each hand: rh/rdir/relbow and lh/ldir/lelbow),
## "fists" (no weapon: rh/lh are wrist points, closed fists).
ATTACK_STYLE = {
    "chibi_blade": {"hands": "one"},
    "chibi_hammer": {"hands": "two", "shaft": (-0.20, 0.40), "head_len": 0.62},  # haft: butt to under the head
    "chibi_spear": {"hands": "two", "shaft": (-0.30, 1.20)},
    "chibi_dagger": {"hands": "dual", "tip": -1.0},
    "chibi_fists": {"hands": "fists"},
}
GRIP_PALM = 0.072  # metres from the wrist to the middle of the closed fist (the model team's grip point)
ARM_REACH = 0.37  # shoulder to the middle of the fist with a nearly straight elbow


def grip_fingers(arm, side, ref):
    """Closes the hand round a haft (the model team's StandDagger grip, fingers and thumb)."""
    for pb in arm.pose.bones:
        if pb.name.startswith(side) and any(pb.name.startswith(side + f) for f in FINGERS):
            pb.rotation_quaternion = ref[pb.name + "_q"].copy()


def report_reach(arm, bone, want, t):
    bone = bone + "Hand" if bone in ("Left", "Right") else bone
    miss = (arm.pose.bones[bone].head - want).length
    if miss > 0.02:
        print("REACH t%s %s misses by %.1f cm" % (t, bone, 100 * miss))


def grip_shaft(arm, k, shaft, ref):
    """Puts the left fist on the right hand's weapon, k["l2"] metres from the right fist along the weapon
    (+ = toward the head/tip). If the short arm cannot reach that point, the fist slides along the
    shaft (within `shaft`, metres from the weapon's grip point) to the nearest point it reaches."""
    P = arm.pose.bones
    att = P["attach_weapon.R"]
    d = (att.matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
    shoulder = P["LeftUpperArm"].head.copy()
    base = att.head.copy()
    lo, hi = shaft
    cands = [lo + 0.01 * i for i in range(int(round((hi - lo) / 0.01)) + 1)]
    cost = lambda s: abs(s - k["l2"]) + 10.0 * max(0.0, (base + d * s - shoulder).length - ARM_REACH)
    s = min(cands, key=cost)
    point = base + d * s
    toward = point - shoulder
    palm = (toward - d * toward.dot(d)).normalized()  # the fist reaches onto the shaft from the shoulder side
    for _ in range(3):
        reach_arm(arm, "Left", point - palm * GRIP_PALM, Vector(k.get("lelbow", (1.0, 0.0, -1.0))), ref)
        hand = P["LeftHand"]
        have = (hand.tail - hand.head).normalized()
        need = (point - hand.head).normalized()
        turn = have.rotation_difference(need)
        turn_about(arm, hand, Quaternion(turn.axis, min(turn.angle, math.radians(45.0))))
        palm = (hand.tail - hand.head).normalized()
    grip_fingers(arm, "Left", ref)
    miss = (P["LeftHand"].head + palm * GRIP_PALM - point).length
    print("LGRIP t%s l2 wanted %.2f got %.2f (shaft %.2f) miss %.1f cm" % (k["t"], k["l2"], s, s, 100 * miss))


def resolve_keys(set_name, keys):
    """The clip's keys with combo hand-offs filled in and each foot's (dx, dy, turn) on every key: a
    foot holds where it is unless a key moves it ("lf"/"rf", "lfturn"/"rfturn"); "idle" puts both back."""
    out, cur = [], {"Left": (0.0, 0.0, 0.0), "Right": (0.0, 0.0, 0.0)}
    for k in keys:
        if "from" in k:  # combo hand-off: start in the previous hit's follow-through, feet included
            prev = resolve_keys(set_name, ATTACKS[set_name][k["from"]]["keys"])
            k = dict([e for e in prev if e.get("end")][-1], t=k["t"])
            k.pop("end", None)  # (else the next clip's "from" would find this copied key, not this clip's own end)
            cur = dict(k["_feet"])
        for s, c in (("Left", "l"), ("Right", "r")):
            if k.get("idle"):
                cur[s] = (0.0, 0.0, 0.0)
            dx, dy = k.get(c + "f", cur[s][:2])
            cur[s] = (dx, dy, k.get(c + "fturn", cur[s][2]))
        out.append(dict(k, _feet=dict(cur)))
    head_len = ATTACK_STYLE[set_name].get("head_len")
    if head_len:  # a hammer's striking face leads: its head's long side follows the way the head travels
        pts = [(i, Vector(k["rh"]) + Vector(k["rdir"]).normalized() * head_len) for i, k in enumerate(out) if "rdir" in k]
        prev = None
        for j, (i, p) in enumerate(pts):
            if "rhead" in out[i]:
                prev = Vector(out[i]["rhead"])
                continue
            m = pts[min(j + 1, len(pts) - 1)][1] - pts[max(j - 1, 0)][1]
            if m.length < 0.05:
                m = prev if prev is not None else Vector((0.0, 0.0, -1.0))
            if prev is not None and m.dot(prev) < 0.0:
                m = -m  # the head is symmetric: never spin it half a turn about the haft
            out[i] = dict(out[i], rhead=tuple(m.normalized()))
            prev = m
    return out


def footwork_check(arm, clip, frames, pins, floor, idle_dist):
    """Measures the baked feet on every frame and prints one line per clip (armature space, the attack
    faces -y, the character's left is +x). floor = {side: (idle ankle z, idle ball z)}. A foot whose
    ball is within 1 cm of the floor counts as planted; its ball must not travel (a pivot on the ball is
    allowed). Returns the numbers."""
    scene = bpy.context.scene
    P = arm.pose.bones
    inv = arm.matrix_world.inverted()
    st = {"dist": 9.0, "gap": 9.0, "cross": 0, "slide": 0.0, "low": 9.0, "knee": 9.0, "cave": -9.0, "miss": 0.0}
    run = {"Left": None, "Right": None}
    for f in range(frames + 1):
        scene.frame_set(f)
        pt = {}
        for s in ("Left", "Right"):
            ankle, ball, knee = P[s + "Foot"].head.copy(), P[s + "Toes"].head.copy(), P[s + "LowerLeg"].head.copy()
            pt[s] = (ankle, knee)
            st["low"] = min(st["low"], ankle.z - floor[s][0], ball.z - floor[s][1])
            if ball.z - floor[s][1] < 0.01:
                run[s] = ball.copy() if run[s] is None else run[s]
                st["slide"] = max(st["slide"], (ball - run[s]).xy.length)
            else:
                run[s] = None
            if pins:
                st["miss"] = max(st["miss"], (ankle - inv @ pins[s].matrix_world.translation).length)
            toe = (ball - ankle).xy.normalized()  # knee over the toes: its distance from the hip-ankle-toe plane
            hip_joint = P[s + "UpperLeg"].head
            n = (ankle - hip_joint).cross(Vector((toe.x, toe.y, 0.0))).normalized()
            other = P[("Right" if s == "Left" else "Left") + "Foot"].head
            n = n if n.dot(other - ankle) > 0.0 else -n  # + = the knee falls in toward the other leg
            st["cave"] = max(st["cave"], (knee - hip_joint).dot(n))
        st["dist"] = min(st["dist"], (pt["Left"][0] - pt["Right"][0]).xy.length)
        gap = pt["Left"][0].x - pt["Right"][0].x
        st["gap"] = min(st["gap"], gap)
        st["cross"] += gap < 0.0
        st["knee"] = min(st["knee"], (pt["Left"][1] - pt["Right"][1]).length)
        if os.environ.get("FOOTWORK_DEBUG"):
            print("  f%d" % f, {s: ("ankle z %+.1f" % (100 * (pt[s][0].z - floor[s][0])), "ball z %+.1f" % (
                100 * (P[s + "Toes"].head.z - floor[s][1])), "miss %.1f" % (100 * (pt[s][0] - inv @ pins[s].matrix_world.translation).length))
                for s in pt}, "knees %.1f" % (100 * (pt["Left"][1] - pt["Right"][1]).length))
    print("FOOTWORK %-8s min feet %.1f cm (idle %.1f) | min side gap %.1f cm | crossed %d frames | planted slide %.1f cm"
          " | lowest foot %+.1f cm | min knees %.1f cm | knee in of toe line %.1f cm | IK miss %.1f cm"
          % (clip, 100 * st["dist"], 100 * idle_dist, 100 * st["gap"], st["cross"], 100 * st["slide"],
             100 * st["low"], 100 * st["knee"], 100 * st["cave"], 100 * st["miss"]))
    return st


def build_attack(arm, set_name, clip, spec, ref):
    """One attack clip: each key posed from the idle stance (body twist/lean/drop, the blade placed by
    pose_weapon_arm, feet stepping), keyed, feet held by IK, baked. Returns its metadata."""
    global BODY_TURN
    scene = bpy.context.scene
    st = STANCES[set_name]
    base_act = bpy.data.actions[st["base"]]
    arm.animation_data.action = base_act
    scene.frame_set(int(base_act.frame_range[0]))
    feet0 = {s: (arm.pose.bones[s + "Foot"].head.copy(), arm.pose.bones[s + "Foot"].matrix.to_quaternion())
             for s in ("Left", "Right")}
    toe_dz = {s: arm.pose.bones[s + "Toes"].head.z - arm.pose.bones[s + "Foot"].head.z for s in ("Left", "Right")}
    ball_local = {s: feet0[s][1].inverted() @ (arm.pose.bones[s + "Toes"].head - feet0[s][0]) for s in feet0}
    arm.animation_data.action = None
    build_stance(arm, set_name, ref)
    P = arm.pose.bones
    base = {pb.name: pb.rotation_quaternion.copy() for pb in P}
    base_loc = {pb.name: pb.location.copy() for pb in P}
    B = arm.data.bones
    leg_len = {s: (B[s + "LowerLeg"].head_local - B[s + "UpperLeg"].head_local).length
               + (B[s + "Foot"].head_local - B[s + "LowerLeg"].head_local).length for s in feet0}
    feet = {}
    for s, (pos, rot) in feet0.items():
        offset, toe = FEET[s]
        feet[s] = (body(pos + offset), q(UP, TURN + toe) @ rot)
    ball_idle = {s: feet[s][0] + feet[s][1] @ ball_local[s] for s in feet}

    def foot_pose(s, state, pitch=0.0, lift=0.0):
        """Ankle target and foot rotation for a foot whose ball sits at idle + (dx, dy), turned `turn`
        degrees about its ball, rolled `pitch` degrees onto its ball (heel up; < 0 toe up), `lift` up."""
        dx, dy, turn = state
        rot = q(UP, turn) @ feet[s][1]
        off = rot @ ball_local[s]
        if pitch:
            axis = UP.cross(Vector((off.x, off.y, 0.0))).normalized()
            r = Quaternion(axis, math.radians(abs(pitch)))
            if (r @ off).z > off.z:  # the sign that lifts the heel
                r = r.inverted()
            if pitch < 0.0:
                r = r.inverted()
            rot, off = r @ rot, r @ off
        return ball_idle[s] + Vector((dx, dy, lift)) - off, rot

    keys = resolve_keys(set_name, spec["keys"])
    fpt = 24.0 * ATTACK_SCALE / 60.0  # frames per tick
    act = bpy.data.actions.new(clip)
    arm.animation_data.action = act
    pins, poles = {}, {}
    for s in ("Left", "Right"):
        for store, name in ((pins, "pin_"), (poles, "pole_")):
            target = bpy.data.objects.new(name + s, None)
            scene.collection.objects.link(target)
            target.rotation_mode = 'QUATERNION'
            store[s] = target
    last = {}
    BODY_TURN = False
    try:
        prev_yaw = 0.0
        for k in keys:
            f = k["t"] * fpt
            ankles = {s: foot_pose(s, k["_feet"][s])[0] for s in feet}
            pose_attack_key(arm, set_name, k, base, base_loc, ankles, leg_len, ref, prev_yaw)
            prev_yaw = 0.0 if k.get("idle") else k.get("twist", 0.0) + k.get("chest", 0.0)
            for pb in P:
                qq = pb.rotation_quaternion.copy()
                if pb.name in last and last[pb.name].dot(qq) < 0.0:
                    qq.negate()  # keep the shortest way between keys
                last[pb.name] = qq
                pb.rotation_quaternion = qq
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
    finally:
        BODY_TURN = True
    # Feet: each foot holds still until a key moves it. A move of its ball is a step over the last
    # STEP_TICKS before that key (heel rolls off, the foot arcs STEP_LIFT up, lands heel first, then
    # stays); a turn alone is a pivot on the ball with the heel a little up. Two feet stepping onto the
    # same key step one after the other (never a hop). The knee is aimed over the toes by a pole target.
    plans = {s: [] for s in feet}  # (start tick, end tick, from state, to state)
    for s in feet:
        changed_at = keys[0]["t"]
        for a, b in zip(keys, keys[1:]):
            if a["_feet"][s] != b["_feet"][s]:
                plans[s].append([max(changed_at, b["t"] - STEP_TICKS), b["t"], a["_feet"][s], b["_feet"][s]])
                changed_at = b["t"]
    moved = lambda p: abs(p[2][0] - p[3][0]) + abs(p[2][1] - p[3][1]) > 0.005
    for pl in plans["Left"]:
        for pr in plans["Right"]:
            if pl[1] == pr[1] and moved(pl) and moved(pr):  # both land on one key: the longer step goes first
                first, second = (pl, pr) if abs(pl[2][1] - pl[3][1]) >= abs(pr[2][1] - pr[3][1]) else (pr, pl)
                mid = 0.5 * (first[0] + first[1])
                first[1], second[0] = mid, mid
    pin_keys = {s: [(keys[0]["t"], foot_pose(s, keys[0]["_feet"][s]))] for s in feet}
    for s in feet:
        for t0, t1, a, b in plans[s]:
            w = t1 - t0
            mix = lambda u: tuple(x + (y - x) * u for x, y in zip(a, b))
            if moved((t0, t1, a, b)):
                print("STEP", clip, s, "ticks %.1f-%.1f" % (t0, t1), "from", a, "to", b)
                pin_keys[s] += [(t0, foot_pose(s, a)), (t0 + 0.15 * w, foot_pose(s, a, 0.4 * HEEL_OFF, 0.004)),
                                (t0 + 0.3 * w, foot_pose(s, a, HEEL_OFF, 0.006)),
                                (t0 + 0.6 * w, foot_pose(s, mix(0.6), 5.0, STEP_LIFT)),
                                (t0 + 0.85 * w, foot_pose(s, b, -6.0, 0.025)), (t1, foot_pose(s, b))]
            else:
                heel = min(PIVOT_HEEL, 0.4 * abs(b[2] - a[2]))
                print("PIVOT", clip, s, "ticks %.1f-%.1f" % (t0, t1), "turn %.0f -> %.0f" % (a[2], b[2]))
                pin_keys[s] += [(t0, foot_pose(s, a)), (0.5 * (t0 + t1), foot_pose(s, mix(0.5), heel)),
                                (t1, foot_pose(s, b))]
        prev = None
        for t, (ankle, rot) in pin_keys[s]:
            if prev is not None and prev.dot(rot) < 0.0:
                rot = -rot
            prev = rot
            toe = (rot @ ball_local[s]).xy.normalized()
            pins[s].location = arm.matrix_world @ ankle
            pins[s].rotation_quaternion = rot
            poles[s].location = arm.matrix_world @ (ankle + Vector((0.5 * toe.x, 0.5 * toe.y, 0.3)))
            for o in (pins[s], poles[s]):
                o.keyframe_insert("location", frame=t * fpt)
                o.keyframe_insert("rotation_quaternion", frame=t * fpt)
    for s in ("Left", "Right"):
        ik = P[s + "LowerLeg"].constraints.new('IK')
        ik.target, ik.chain_count = pins[s], 2
        ik.pole_target = poles[s]
        P[s + "Foot"].constraints.new('COPY_ROTATION').target = pins[s]
        scene.frame_set(0)
        hip_joint = P[s + "UpperLeg"].head

        def off_plane(angle):  # the knee's distance from the hip-ankle-pole plane (and on the pole's side)
            ik.pole_angle = math.radians(angle)
            bpy.context.view_layer.update()
            pole = arm.matrix_world.inverted() @ poles[s].matrix_world.translation
            ankle = P[s + "Foot"].head
            n = (ankle - hip_joint).cross(pole - hip_joint).normalized()
            mid = 0.5 * (hip_joint + ankle)
            knee = P[s + "LowerLeg"].head
            return abs((knee - hip_joint).dot(n)) + (1.0 if (knee - mid).dot(pole - mid) < 0.0 else 0.0)
        ik.pole_angle = math.radians(min(range(-180, 180, 3), key=off_plane))
        print("POLE", s, "angle %.0f" % math.degrees(ik.pole_angle))
    total = sum(spec["ticks"])
    frames = int(round(total * fpt))
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.nla.bake(frame_start=0, frame_end=frames, step=1, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=True, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    floor = {s: (feet[s][0].z, feet[s][0].z + toe_dz[s]) for s in feet}
    footwork_check(arm, clip, frames, pins, floor, (feet["Left"][0] - feet["Right"][0]).xy.length)
    for target in pins.values():
        bpy.data.objects.remove(target, do_unlink=True)
    arm.animation_data.action = None
    sec = ATTACK_SCALE / 60.0
    startup, active, _ = spec["ticks"]
    return {"length": total * sec, "loop": False, "windup_end": startup * sec, "strike_end": (startup + active) * sec}


ONLY = [s for s in os.environ.get("CHIBI_SETS", "").split(",") if s]  # e.g. CHIBI_SETS=chibi_blade rebuilds one set
for set_name, clips in SETS.items():
    if ONLY and set_name not in ONLY:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    fps = bpy.context.scene.render.fps
    for o in list(bpy.data.objects):
        if o.type != 'ARMATURE': bpy.data.objects.remove(o, do_unlink=True)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    if "idle" in clips:
        build_idle(arm, set_name)
    skill_meta = {}
    for clip, spec in ATTACKS.get(set_name, {}).items():
        skill_meta[clip] = build_attack(arm, set_name, clip, spec, stand_ref(arm))
        clips = dict(clips, **{clip: clip})
    for clip, (path, source_clip, clip_meta) in SKILL_CLIPS.get(set_name, {}).items():
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, path))
        for o in set(bpy.data.objects) - before:
            bpy.data.objects.remove(o, do_unlink=True)  # keep only its action, on our armature
        clips = dict(clips, **{clip: source_clip})
        skill_meta[clip] = clip_meta
    keep = {v: k for k, v in clips.items()}
    meta = {}
    arm.animation_data_create()
    arm.animation_data.action = None
    for act in list(bpy.data.actions):
        if act.name.split("_")[0] not in keep and act.name not in keep:
            bpy.data.actions.remove(act); continue
        src_name = act.name if act.name in keep else act.name.split("_")[0]
        # no root motion: the game moves the body itself
        for fc in list(act.fcurves):
            if fc.data_path.startswith('pose.bones["Root"]') and fc.data_path.endswith("location"):
                act.fcurves.remove(fc)
        act.name = keep[src_name]
        f0, f1 = act.frame_range
        meta[act.name] = skill_meta.get(act.name, {"length": (f1 - f0) / fps, "loop": act.name in LOOPING})
        t = arm.animation_data.nla_tracks.new(); t.strips.new(act.name, int(f0), act)
    missing = set(clips) - set(meta)
    if missing:
        raise SystemExit("missing clips in %s: %s" % (set_name, missing))
    bpy.ops.export_scene.gltf(filepath=out + "/" + set_name + ".glb", export_format='GLB', export_animations=True, export_animation_mode='ACTIONS')
    json.dump(meta, open(out + "/" + set_name + ".json", "w", newline="\n"), indent=2)
    print("SET", set_name, meta, "fps", fps)

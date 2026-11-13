extends Node3D
## Shows the humanoid character model (art/characters/base/base_character.glb) and poses its skeleton.
## The model has no animations yet, so poses are computed from the fight state in code (a stand-in:
## real animations from Blender replace set_pose()/apply_pose() later, the rest of the game keeps
## working). The pose table below is written with short names (thigh.R, upper_arm.L...) and rotation
## offsets in degrees about the MODEL's axes with the arms hanging down:
##   X rotates about the side axis: limbs X+ swings backward, X- forward; knee X+ bends; spine X+ leans forward
##   Z rolls sideways; Y twists. Elbows are written with X+ = bend, as before (flipped inside).
## BONE_MAP turns the short names into the real bones of the shared humanoid skeleton; the rig rests
## in a T-pose, so the arms are first lowered (ARM_DOWN) and the offsets are applied on top of that.
## Attack poses are built from three phases (wind-up, strike, recover) with easing so the motion
## snaps into the blow, and the whole body lunges forward with the strike.
## EXTENDING: a new pose is a new case in _pose_bones(); another character reuses this script as long
## as it uses the same skeleton (Godot humanoid bone names, see tools/blender/build_base_character.py).

const AnimationSet := preload("res://client/animation_set.gd")
const BladeTrail := preload("res://client/vfx/blade_trail.gd")
const BodyFit := preload("res://client/body_fit.gd")
const CharacterLight := preload("res://client/character_light.gd")
const InkStyle := preload("res://client/ink_style.gd")
const SimBody := preload("res://logic/sim_body.gd")

## Original Chibi restored for the approved silhouette and matching wardrobe/ultimate rig.
const MODEL_PATH := "res://art/characters/studio05/split/body_sword_shield.glb"
## The hair style the body shows (its hair meshes are tagged studio_hair_style); the others are hidden.
const BODY_HAIR_STYLE := "original"
const TURN_SPEED := 14.0
const BODY_SPEED := 16.0  ## how fast the body tilt and lunge follow the pose
const POSE_BLEND_RATE := 24.0  ## how quickly joints ease toward the pose (higher = snappier)
const LIE_LIFT := 0.15  ## lying on the back, the body is this far above the feet line
const ARM_DOWN := 80.0  ## degrees the arms are lowered from the T-pose rest

## The pose table's short names -> the skeleton's bones.
const BONE_MAP := {
	"hips": "Hips", "spine": "Spine", "chest": "Chest", "neck": "Neck", "head": "Head",
	"upper_arm.L": "LeftUpperArm", "forearm.L": "LeftLowerArm", "hand.L": "LeftHand",
	"upper_arm.R": "RightUpperArm", "forearm.R": "RightLowerArm", "hand.R": "RightHand",
	"thigh.L": "LeftUpperLeg", "shin.L": "LeftLowerLeg", "foot.L": "LeftFoot",
	"thigh.R": "RightUpperLeg", "shin.R": "RightLowerLeg", "foot.R": "RightFoot",
}
const FINGER_BONES: Array[String] = ["Index", "Middle", "Ring", "Little"]
const RELAXED_CURL := 22.0  ## degrees a relaxed hand's fingers curl
const FIST_CURL := 100.0  ## intermediate joints; the proximal ones curl 0.8 of this (80/100 closes the fist)
const CLIP_FOLLOW_RATE := 40.0  ## how tightly a joint follows an authored animation (higher = closer)
const TRANSITION_SECONDS := 0.15  ## after switching between an animation and a code pose, joints ease for this long
const WEAPON_FOLDER := "res://art/weapons/"
const WEAPON_BONE := "attach_weapon.R"
const WEAPON_BONE_LEFT := "attach_weapon.L"
## The model team's weapons (blade along +Y) turned to how our stand-ins lay (blade along -Z).
const STUDIO_TO_OURS := Quaternion(Vector3.RIGHT, -PI / 2.0)
## The base model's attach bone turn inside the hand, which WEAPON_HOLD_ROTATION is measured against.
const BASE_ATTACH_IN_HAND := Basis(Quaternion(-0.5, 0.5, -0.5, 0.5))
const WEAPON_HOLD_ROTATION := Vector3(-90.0, 0.0, 0.0)
## Grips set by a model's own artist (degrees, in that model's attach bone frame): the chibi's blade hangs down while running.
const WEAPON_HOLD_BY_MODEL := {"chibi": Vector3(90.0, 0.0, 0.0), "newv1": Vector3(90.0, 0.0, 0.0)}  ## how the weapon sits in the hand (degrees, in the attach bone's frame): grip across the closed fist, blade out past the thumb
## How the sword hand bends in the code poses (pose-table degrees, in the frame of a hanging arm; Y twists
## about the forearm). Without it the blade jutted straight back from the fist. At rest it points out and
## down, away from the head and clear of the legs; on guard it lies across the chest, tip a little up to the
## left (a block that reads as a bar in front of the body from above); blown back, it trails forward.
const SWORD_REST_HAND := Vector3(0.0, 0.0, 60.0)
const SWORD_GUARD_HAND := Vector3(0.0, 180.0, 20.0)
const SWORD_FLUNG_HAND := Vector3(0.0, 180.0, 60.0)
## Authored animations play for these pose kinds when a set has a clip of that name.
## Walking plays the run clip (Boss 2026-10-09: no separate walk; it moves like the run, slowed by speed).
const LOCOMOTION_CLIPS := {"idle": "idle", "run": "run", "walk": "run"}
## ... and these, in the air too, timed by `amount`: guard = seconds on guard, slide (dodge) = 0..1 through it.
const STATE_CLIPS := {"guard": "guard", "slide": "dodge"}
## The equipment slots that put clothing on the body (see ItemAssets.looks()).
const BODY_SLOTS: Array[String] = ["shirt", "armband", "pants", "shoes"]  ## no hat slot (Boss 2026-11-13)
## The body's own surfaces that the player's choices recolor (by material name in the model file).
const SKIN_MATERIAL := "Neutral clay"
## The body's own face features: hidden while a face item (art/items/faces) is worn over them.
const FACE_FEATURES: Array[String] = ["Brow_L", "Brow_R", "Eye inset_L", "Eye inset_R", "Eyelid_L", "Eyelid_R", "Mouth"]
const BROWS: Array[String] = ["Brow_L", "Brow_R"]  ## colored like the hair
const HEAD_PARTS: Array[String] = ["Face", "Nose"]  ## the body's own head: hidden under a replacement head
## The skin that clothes cover: pulled in under what is worn so it cannot poke through (BodyFit).
const FIT_PARTS: Array[String] = ["Body continuous", "Hands articulated", "Face"]
const FACE_BONE := "attach_head"
const HAIR_MIN_SHADE := 0.35  ## a dyed hair item's darkest parts keep at least this much of the color

var _turn: Node3D  ## rotated to face left or right
var _lie: Node3D  ## tipped over when knocked down, pushed forward by lunges
var _model_root: Node3D  ## holds the imported model, scaled to the game's body size
var _skeleton: Skeleton3D
var _meshes: Array[MeshInstance3D] = []  ## the body parts (one mesh per equipment slot area)
var _rest: Dictionary = {}  ## bone name -> rest rotation (Quaternion, relative to its parent)
var _global_rest: Dictionary = {}  ## bone name -> rest rotation in model space
var _rest_position: Dictionary = {}  ## bone name -> rest position (Vector3)
var _bone_index: Dictionary = {}  ## bone name -> index
var _shown: Dictionary = {}  ## pose-table name -> the offset currently shown (eased toward the target)
var _curl_shown := RELAXED_CURL
## Draw a dark ink outline around the model (set before load_model()); used by the "ink" stages.
var ink_outline := false
var _follow := 1.0  ## how far joints move toward their target this frame (1 = straight there)
var _was_clip := false
var _skill_clip: Dictionary = {}  ## a clip from outside the character's sets (a skill pack), shown while it is set
var _transition := 0.0
var _weapon_id := ""
var _grip_ours := Quaternion.IDENTITY  ## weapon turn in the attach bone for our animations / code poses
var _grip_own := Quaternion.IDENTITY  ## ... and for the model's own clips (its artist's grip)
## Equipment previews request the native weapon idle (resolved by the reference adapter).
var equipment_rest := false
var _new_v1_base := false
var _anim_model := ""  ## first word of the model's file name ("chibi"): its own animation sets win when they exist
var _weapon_node: Node3D
var _weapon_left: Node3D  ## the second dagger, in the left hand
var _weapon_key := ""  ## what is in the hands now (path | family)
var _hair_meshes: Array[MeshInstance3D] = []  ## the body's own hair (hidden under a hat that hides hair)
var _base_feet: Array[MeshInstance3D] = []  ## the bare feet (hidden by shoes)
var _worn: Dictionary = {}  ## slot -> {"path": String, "meshes": Array[MeshInstance3D]}
var _body_meshes: Array[MeshInstance3D] = []  ## the body itself (skin, hair, own face), not what it wears
var _unfitted: Dictionary = {}  ## FIT_PARTS mesh instance -> its mesh as the file has it
var _face_node: Node3D  ## the worn face item, if any
var _face_path := ""
var _hair_node: Node3D  ## the worn hair item, if any (it replaces the body's own hair)
var _hair_style_path := ""
var _hair_item_meshes: Array[MeshInstance3D] = []
var _hair_tint = null  ## Color for hair items, or null: they keep their own colors
var _hat_hides_hair := false
var _face_meshes: Array[MeshInstance3D] = []  ## the worn face item's pieces
var _skin_color = null  ## the chosen skin Color (null = as the model file has it)
var _face_replaces_head := false  ## the face item is a whole head (the body's own head and face hide)
var _face_hides_hair := false
## One per weapon in hand that has the model team's points: {"start", "end", "tip": Node3D, "trail": BladeTrail}.
var _blades: Array[Dictionary] = []
var _was_striking := false
## The color of the weapon's swing trail (set by the fighter view from the weapon data).
var trail_color := Color(1.0, 0.95, 0.85):
	set(value):
		trail_color = value
		for blade in _blades:
			blade["trail"].color = value

## What the model should be doing; set through set_pose() every simulation tick.
var _pose := {"kind": "idle", "amount": 0.0, "speed": 0.0, "grounded": true, "facing": 1, "lying": false, "phase": "", "clip": "", "weapon": ""}
var _clock := 0.0


## Loads and prepares the model. Returns false (and does nothing) if the file is missing.
func load_model(path: String = MODEL_PATH) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	_turn = Node3D.new()
	_turn.rotation_degrees.y = 90.0
	add_child(_turn)
	_lie = Node3D.new()
	_turn.add_child(_lie)
	_new_v1_base = path.contains("/new-v1/")
	_anim_model = path.get_file().get_basename().get_slice("_", 0)
	_model_root = packed.instantiate()
	_lie.add_child(_model_root)

	_skeleton = _find_skeleton(_model_root)
	_find_meshes(_model_root, _meshes)
	if _skeleton == null or _meshes.is_empty():
		push_warning("character model has no skeleton or mesh")
		return false
	# The body ships with every hair style the Studio offers; keep one, hide the rest for good.
	for mesh_instance in _meshes.duplicate():
		var style := str(mesh_instance.get_meta("extras", {}).get("studio_hair_style", ""))
		if not style.is_empty():
			if style == BODY_HAIR_STYLE:
				_hair_meshes.append(mesh_instance)
			else:
				mesh_instance.visible = false
				_meshes.erase(mesh_instance)
		elif str(mesh_instance.name).begins_with("Base foot"):
			_base_feet.append(mesh_instance)
	_body_meshes = _meshes.duplicate()
	for mesh_instance in _body_meshes:
		if str(mesh_instance.name) in FIT_PARTS:
			_unfitted[mesh_instance] = mesh_instance.mesh
	# Models painted with vertex colors (e.g. the chibi) show them; the importer leaves them off.
	for mesh_instance in _meshes:
		for surface in mesh_instance.mesh.get_surface_count():
			var surface_material := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if surface_material != null and mesh_instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR:
				surface_material.vertex_color_use_as_albedo = true
	for index in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(index)
		_bone_index[bone_name] = index
		_rest[bone_name] = _skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		_global_rest[bone_name] = _skeleton.get_bone_global_rest(index).basis.get_rotation_quaternion()
		_rest_position[bone_name] = _skeleton.get_bone_rest(index).origin

	# Scale the model to the game's body height and put its feet on the origin.
	var bounds := _union_bounds()
	var factor := SimBody.HEIGHT / bounds.size.y
	_model_root.scale = Vector3.ONE * factor
	_model_root.position.y = -bounds.position.y * factor
	_prepare_meshes()
	tint(Color(0.0, 0.0, 0.0, 0.0))
	return true


func has_bone(bone_name: String) -> bool:
	return _bone_index.has(bone_name)


func bone_count() -> int:
	return _bone_index.size()


## How many times its authored size the model is shown (it is scaled to the game's body height).
func model_scale() -> float:
	return _model_root.scale.y if _model_root != null else 1.0


## The authored clip being shown now: {"set", "clip", "time"} or {} (code poses).
func current_clip() -> Dictionary:
	return _active_clip()


## Plays one clip from a file outside the character's own animation sets at an exact time: the
## imported skill packs (deleted with the old skill system; class skills use show_class_skill_frame), whose
## clip runs at the same rate as the move's frames, so the caller passes the time itself. It wins
## over every other clip and pose until clear_skill_clip(); the weapon sits in the artist's grip,
## because these clips were authored on this rig.
func show_skill_clip(library: RefCounted, clip: String, time: float) -> void:
	if library == null or clip == "":
		return
	_skill_clip = {"set": library, "clip": clip, "time": time}


func clear_skill_clip() -> void:
	_skill_clip = {}


## Bounds for UI framing only; includes worn clothes/headgear, excludes weapon reach.
func preview_bounds() -> AABB:
	return _model_root.transform * _union_bounds()


func model_height() -> float:
	if _meshes.is_empty():
		return 0.0
	return _union_bounds().size.y * _model_root.scale.y


## `kind`: idle, walk, run, punch_r, punch_l, heavy, kick, guard, slide, hurt, launched, down.
## `phase`: windup, strike, recover (attacks only); `amount` (0..1) is how far through that phase
## the move is. `speed` is the walking speed as a fraction of the normal walk. `facing` is a
## direction (Vector2 or Vector2i: x, z) or just 1 / -1 for right / left.
## `clip` (attacks) is the kind of move ("light_1", "heavy", "run_light"...) and `weapon` the weapon's
## animation set to look it up in; when neither that set nor the common set has an authored clip
## for it, the move is posed by the code below as before.
func set_pose(kind: String, amount: float, speed: float, grounded: bool, facing: Variant, lying: bool, phase: String = "", clip: String = "", weapon: String = "") -> void:
	_pose = {"kind": kind, "amount": amount, "speed": speed, "grounded": grounded, "facing": facing, "lying": lying, "phase": phase, "clip": clip, "weapon": weapon}


## Shows the stand-in weapon of a combat style in the right hand (art/weapons/<id>.glb); an unknown id
## shows nothing. Items with their own model are shown through dress() instead.
func set_weapon(weapon_id: String) -> void:
	_weapon_id = weapon_id
	_show_weapon(WEAPON_FOLDER + weapon_id + ".glb" if not weapon_id.is_empty() else "", "")


## `path` is a weapon .glb ("" = empty hands). `family` is the model team's weapon family for their
## assets (art/items/weapons): those come ready to sit in the hand socket, a "dagger" pair in both
## hands; "" means one of our older stand-ins (art/weapons), which are turned into the grip here.
func _show_weapon(path: String, family: String) -> void:
	var key := path + "|" + family
	if key == _weapon_key or _skeleton == null:
		return
	_weapon_key = key
	for node in [_weapon_node, _weapon_left]:
		if node != null:
			node.get_parent().queue_free()  # the BoneAttachment3D holding it
	_weapon_node = null
	_weapon_left = null
	for blade in _blades:
		blade["trail"].queue_free()
	_blades.clear()
	if path.is_empty() or not ResourceLoader.exists(path) or not _bone_index.has(WEAPON_BONE):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	# WEAPON_HOLD_ROTATION was tuned on the base model's attach bone; models whose attach bone is turned
	# differently in the hand (the chibi) get the same grip relative to the hand.
	var attach_rest := _skeleton.get_bone_rest(_bone_index[WEAPON_BONE]).basis.orthonormalized()
	_grip_ours = Quaternion(attach_rest.inverse() * BASE_ATTACH_IN_HAND * Basis.from_euler(WEAPON_HOLD_ROTATION * PI / 180.0))
	if family.is_empty():
		# A model whose artist set its own grip (WEAPON_HOLD_BY_MODEL, in its attach bone's frame) uses it in its own clips.
		_grip_own = Quaternion.from_euler(WEAPON_HOLD_BY_MODEL[_anim_model] * PI / 180.0) if WEAPON_HOLD_BY_MODEL.has(_anim_model) else _grip_ours
	else:
		# The model team's weapons sit in the socket as they are in their own clips; in our poses they
		# are first turned to lie like our stand-ins.
		_grip_own = Quaternion.IDENTITY
		_grip_ours = _grip_ours * STUDIO_TO_OURS
	_weapon_node = _attach(packed, WEAPON_BONE)
	_weapon_node.quaternion = _grip_ours
	if family == "dagger" and _bone_index.has(WEAPON_BONE_LEFT):
		_weapon_left = _attach(packed, WEAPON_BONE_LEFT)
	for node in [_weapon_node, _weapon_left]:
		_add_blade_trail(node)
	_prepare_meshes()


## The model team's weapons carry trail_start / trail_end / effect_point markers: the swing trail runs
## between the first two and the strike's glint shows at the third. Weapons without them get none.
func _add_blade_trail(weapon: Node3D) -> void:
	if weapon == null:
		return
	var start := weapon.find_child("trail_start", true, false) as Node3D
	var end := weapon.find_child("trail_end", true, false) as Node3D
	if start == null or end == null:
		return
	var trail := BladeTrail.new()
	trail.color = trail_color
	add_child(trail)
	_blades.append({"start": start, "end": end, "tip": weapon.find_child("effect_point", true, false), "trail": trail})


## True while a swing trail is being drawn (for tests).
func is_trailing() -> bool:
	for blade in _blades:
		if blade["trail"].is_drawing():
			return true
	return false


func has_blade_trail() -> bool:
	return not _blades.is_empty()


## Each frame: while the blow is live (the strike phase of an attack) the trail follows the blade.
func _update_blade_trails() -> void:
	var striking: bool = _pose["phase"] == "strike" and _pose["clip"] != ""
	for blade in _blades:
		if striking:
			blade["trail"].sample(blade["start"].global_position, blade["end"].global_position)
			if not _was_striking and blade["tip"] != null:
				blade["trail"].glint(blade["tip"].global_position)
	_was_striking = striking


func _attach(packed: PackedScene, bone_name: String) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	var node: Node3D = packed.instantiate()
	attachment.add_child(node)
	return node


## Puts on what ItemAssets.looks() describes: the weapon and the clothing of every body slot, and
## the player's own looks under "appearance" (see set_appearance()). Without "weapon" the hands are left alone.
## Clothing is skinned to the same skeleton (the model team's contract), so its meshes move onto ours.
func dress(looks: Dictionary) -> void:
	if _skeleton == null:
		return
	if looks.has("weapon"):
		var weapon: Dictionary = looks["weapon"]
		if not str(weapon.get("path", "")).is_empty():
			_show_weapon(weapon["path"], str(weapon.get("family", "")))
		else:
			set_weapon(str(weapon.get("style", "")))
	if looks.has("appearance"):
		set_appearance(looks["appearance"])
	for slot_id in BODY_SLOTS:
		_wear(slot_id, str(looks.get(slot_id, "")))
	_hat_hides_hair = looks.get("hide_hair", false) and _worn.has("hat")
	_update_hair_visibility()
	for mesh_instance in _base_feet:
		mesh_instance.visible = not _worn.has("shoes")
	_fit_body()
	_prepare_meshes()
	_apply_equipment_refine(looks.get("refine", {}))
	tint(Color(0.0, 0.0, 0.0, 0.0))  # (the new pieces start untinted)


func _apply_equipment_refine(levels: Dictionary) -> void:
	var effect := preload("res://client/refine_equipment.gd")
	for slot in _worn:
		for mesh in _worn[slot].meshes:
			effect.apply(mesh, int(levels.get(slot, 0)), _skeleton)
	for weapon in [_weapon_node, _weapon_left]:
		if not is_instance_valid(weapon): continue
		var meshes: Array[MeshInstance3D] = []
		_find_meshes(weapon, meshes)
		for mesh in meshes:
			if mesh.name in ["RefineAura", "InkOutline"]: continue
			effect.apply(mesh, int(levels.get("weapon", 0)), _skeleton)


## The player's own looks (ItemAssets.appearance()): {"skin": Color, "hair": Color, "hair_natural": bool,
## "face" and "hair_style": path of a face / hair item ("" = the body's own), "face_replaces_head" and
## "face_hides_hair": bool (a whole replacement head)}. A missing key leaves that part as it is. "hair" colors the body's own hair and brows; a hair item takes it too unless
## "hair_natural" (then it keeps its own designed colors).
func set_appearance(appearance: Dictionary) -> void:
	if _skeleton == null:
		return
	if appearance.has("face"):
		_show_face(str(appearance["face"]), appearance.get("face_replaces_head", false), appearance.get("face_hides_hair", false))
	if appearance.has("hair"):
		_hair_tint = null if appearance.get("hair_natural", false) else appearance["hair"]
	if appearance.has("hair_style"):
		_show_hair_style(str(appearance["hair_style"]))
	_color_hair_item()
	for mesh_instance in _body_meshes:
		var key := "hair" if mesh_instance in _hair_meshes or str(mesh_instance.name) in BROWS else "skin"
		if not appearance.has(key):
			continue
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material != null and material.resource_name.begins_with(SKIN_MATERIAL):
				_own_materials(mesh_instance)
				(mesh_instance.get_active_material(surface) as BaseMaterial3D).albedo_color = appearance[key]
	if appearance.has("skin"):
		_skin_color = appearance["skin"]
		_color_worn_skin()


## A replacement head is skin too: it takes the skin color. (Clothes are left alone: some use the same
## "Neutral clay" material as cloth, e.g. the basic shorts and the Ember arm wraps.)
func _color_worn_skin() -> void:
	if _skin_color == null:
		return
	for mesh_instance in _face_meshes:
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material != null and material.resource_name.begins_with(SKIN_MATERIAL):
				_own_materials(mesh_instance)
				(mesh_instance.get_active_material(surface) as BaseMaterial3D).albedo_color = _skin_color


## Pulls the skin under the worn clothes in (BodyFit), and back out when they come off.
func _fit_body() -> void:
	if _new_v1_base:
		return  # fitted continuous liners share the body skin; do not shrink it again
	var garments: Array = []
	for slot_id in _worn:
		for mesh_instance in _worn[slot_id]["meshes"]:
			garments.append(mesh_instance.mesh)
	for mesh_instance in _unfitted:
		var shape: Mesh = BodyFit.fitted(_unfitted[mesh_instance], garments)
		if mesh_instance.mesh == shape:
			continue
		mesh_instance.mesh = shape
		var outline := outline_of(mesh_instance)
		if outline != null:
			outline.mesh = InkStyle.outline_mesh(shape)


## The face item worn now ("" = the body's own face).
func face_path() -> String:
	return _face_path


## The hair item worn now ("" = the body's own hair).
func hair_style_path() -> String:
	return _hair_style_path


func _show_face(path: String, replaces_head: bool = false, hides_hair: bool = false) -> void:
	if path == _face_path:
		return
	for mesh_instance in _face_meshes:
		_meshes.erase(mesh_instance)
	_face_meshes.clear()
	_face_node = _swap_head_item(_face_node, path)
	_face_path = path if _face_node != null else ""
	_face_replaces_head = replaces_head and _face_node != null
	_face_hides_hair = hides_hair and _face_node != null
	if _face_node != null:
		_find_meshes(_face_node, _face_meshes)
		if _face_replaces_head:
			_meshes.append_array(_face_meshes)  # a whole head is outlined like the body (a face is not)
	for mesh_instance in _body_meshes:
		if str(mesh_instance.name) in FACE_FEATURES:
			mesh_instance.visible = _face_node == null
		elif str(mesh_instance.name) in HEAD_PARTS:
			mesh_instance.visible = not _face_replaces_head
	_update_hair_visibility()
	_prepare_meshes()
	tint(Color(0.0, 0.0, 0.0, 0.0))


func _show_hair_style(path: String) -> void:
	if path == _hair_style_path:
		return
	for mesh_instance in _hair_item_meshes:
		_meshes.erase(mesh_instance)
	_hair_item_meshes.clear()
	_hair_node = _swap_head_item(_hair_node, path)
	_hair_style_path = path if _hair_node != null else ""
	if _hair_node != null:
		_find_meshes(_hair_node, _hair_item_meshes)
		_meshes.append_array(_hair_item_meshes)  # (outlined and hit-flashed like the body)
	_update_hair_visibility()
	_prepare_meshes()
	tint(Color(0.0, 0.0, 0.0, 0.0))


## Takes `old` (an item on the head) off and puts the item at `path` on; returns it (null for "").
## Face and hair items are made in the attach_head bone's frame, so they sit there as they are.
func _swap_head_item(old: Node3D, path: String) -> Node3D:
	if old != null:
		old.get_parent().queue_free()  # the BoneAttachment3D holding it
	if path.is_empty() or not ResourceLoader.exists(path) or not _bone_index.has(FACE_BONE):
		return null
	var packed := load(path) as PackedScene
	return null if packed == null else _attach(packed, FACE_BONE)


## The hair shows unless a hat or a replacement head hides it; a hair item replaces the body's own hair.
func _update_hair_visibility() -> void:
	var hidden := _hat_hides_hair or _face_hides_hair
	for mesh_instance in _hair_meshes:
		mesh_instance.visible = not hidden and _hair_node == null
	if _hair_node != null:
		_hair_node.visible = not hidden


## A hair item in the chosen color: each of its materials keeps how light it was against the
## lightest one, so the style's darker under-layers and lighter streaks stay. Natural = as designed.
func _color_hair_item() -> void:
	var lightest := 0.0
	for mesh_instance in _hair_item_meshes:
		_own_materials(mesh_instance)
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material != null:
				if not material.has_meta("style_color"):
					material.set_meta("style_color", material.albedo_color)
				lightest = maxf(lightest, material.get_meta("style_color").get_luminance())
	for mesh_instance in _hair_item_meshes:
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			var designed: Color = material.get_meta("style_color")
			if _hair_tint == null:
				material.albedo_color = designed
			else:
				var shade := clampf(designed.get_luminance() / maxf(lightest, 0.001), HAIR_MIN_SHADE, 1.0)
				material.albedo_color = Color(_hair_tint.r * shade, _hair_tint.g * shade, _hair_tint.b * shade)


## Gives `mesh_instance` its own copies of its materials (they are shared with every other model
## loaded from the same file), once.
func _own_materials(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.has_meta("own_colors"):
		return
	mesh_instance.set_meta("own_colors", true)
	for surface in mesh_instance.get_surface_override_material_count():
		var shared := mesh_instance.get_active_material(surface)
		if shared != null:
			var copy := shared.duplicate()
			if shared.has_meta("style_color"):
				copy.set_meta("style_color", shared.get_meta("style_color"))
			mesh_instance.set_surface_override_material(surface, copy)


## The clothing worn now: slot -> path.
func worn_paths() -> Dictionary:
	var result := {}
	for slot_id in _worn:
		result[slot_id] = _worn[slot_id]["path"]
	return result


func is_hair_shown() -> bool:
	if _hair_node != null:
		return _hair_node.visible
	return not _hair_meshes.is_empty() and _hair_meshes[0].visible


func _wear(slot_id: String, path: String) -> void:
	if _worn.get(slot_id, {}).get("path", "") == path:
		return
	for mesh_instance in _worn.get(slot_id, {}).get("meshes", []):
		_meshes.erase(mesh_instance)
		mesh_instance.queue_free()
	_worn.erase(slot_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var piece := packed.instantiate()
	var found: Array[MeshInstance3D] = []
	_find_meshes(piece, found)
	for mesh_instance in found:
		var local := mesh_instance.transform
		mesh_instance.owner = null
		mesh_instance.get_parent().remove_child(mesh_instance)
		_skeleton.add_child(mesh_instance)
		mesh_instance.transform = local
		mesh_instance.skeleton = mesh_instance.get_path_to(_skeleton)
		_meshes.append(mesh_instance)
	piece.free()
	_worn[slot_id] = {"path": path, "meshes": found}


## Hides the weapon in the hands without unequipping it (a spear pack throws it and catches it again).
func set_weapon_visible(shown: bool) -> void:
	for node in [_weapon_node, _weapon_left]:
		if node != null:
			node.visible = shown


func has_weapon_model() -> bool:
	return _weapon_node != null


func has_left_weapon() -> bool:
	return _weapon_left != null


## The authored clip for the current pose, if there is one: {"set": AnimationSet, "clip": name, "time": seconds}
## or {}. A weapon's own set wins over the common set.
func _active_clip() -> Dictionary:
	if _pose["lying"]:
		return {}
	if not _skill_clip.is_empty():
		return _skill_clip
	if equipment_rest and _new_v1_base:
		var resting := "Stand" + str(_pose["weapon"]).capitalize()
		var source := AnimationSet.load_file(MODEL_PATH)
		if source != null and source.has_clip(resting):
			return {"set": source, "clip": resting, "time": fposmod(_clock, maxf(source.length(resting), 0.001))}
	var kind: String = _pose["kind"]
	var wanted := ""
	var time := 0.0
	var is_attack: bool = _pose["clip"] != "" and _pose["phase"] != ""
	if is_attack:
		wanted = _pose["clip"]
	elif LOCOMOTION_CLIPS.has(kind) and _pose["grounded"]:
		wanted = LOCOMOTION_CLIPS[kind]
	elif STATE_CLIPS.has(kind):
		wanted = STATE_CLIPS[kind]
	else:
		return {}
	# The model's own sets first (art/animations/<model>_<weapon>.glb, <model>.glb), then the weapon's, then common.
	var model_sets: Array = [] if _anim_model == "" else [_anim_model + "_" + str(_pose["weapon"]), _anim_model]
	for set_name in model_sets + [_pose["weapon"], "common"]:
		if set_name == "" or (set_name == _anim_model + "_" and _pose["weapon"] == ""):
			continue
		var library := AnimationSet.load_set(set_name)
		if library == null or not library.has_clip(wanted):
			continue
		if is_attack:
			time = library.attack_time(wanted, _pose["phase"], _pose["amount"])
		elif kind == "guard":
			time = _pose["amount"]  # seconds on guard: the raise plays once, then the clip holds its last frame
		elif kind == "slide":
			time = clampf(_pose["amount"], 0.0, 1.0) * library.length(wanted)  # stretched over the dodge
		else:
			var rate := 1.0 if kind == "idle" else clampf(float(_pose["speed"]), 0.6, 1.4)
			time = _clock * rate
		return {"set": library, "clip": wanted, "time": time}
	return {}


## New meshes (body, clothing, weapon) join the character lighting; with the ink outline, each part
## that gets it gets a child drawing its outline (InkStyle.outline_mesh, moved by the same bones).
func _prepare_meshes() -> void:
	if ink_outline:
		for mesh_instance in _meshes:
			if mesh_instance.has_meta("outline"):
				continue
			var outline := MeshInstance3D.new()
			outline.name = "InkOutline"
			outline.mesh = InkStyle.outline_mesh(mesh_instance.mesh)
			outline.skin = mesh_instance.skin
			mesh_instance.add_child(outline)
			outline.skeleton = outline.get_path_to(_skeleton) if mesh_instance.skin != null else NodePath()
			outline.material_override = InkStyle.outline_material(0.005)
			outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_instance.set_meta("outline", outline)
	CharacterLight.prepare(_model_root)


## The outline drawn around `mesh_instance` (null without the ink style).
func outline_of(mesh_instance: MeshInstance3D) -> MeshInstance3D:
	return mesh_instance.get_meta("outline") if mesh_instance.has_meta("outline") else null


## Tints the whole model (hit flash); a transparent color removes the tint.
## One overlay material per model, recolored in place: a new material every frame (while a debuff
## lasts) was wasteful and made the headless renderer log errors when the old ones were freed.
var _tint_material: StandardMaterial3D


func tint(color: Color) -> void:
	if color.a <= 0.0:
		for mesh in _meshes:
			mesh.material_overlay = mesh.get_meta("refine_surface") if mesh.has_meta("refine_surface") else null
		return
	if _tint_material == null:
		_tint_material = StandardMaterial3D.new()
		_tint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tint_material.albedo_color = color
	for mesh in _meshes:
		if mesh.material_overlay != _tint_material:
			mesh.material_overlay = _tint_material


## The tint goes before the model is freed: a mesh freed while it still has the overlay made the
## headless renderer log "Parameter material is null" (a debuff on the player when leaving a stage).
func _exit_tree() -> void:
	tint(Color(0.0, 0.0, 0.0, 0.0))


func apply_pose(delta: float) -> void:
	if _skeleton == null:
		return
	_clock += delta
	_update_blade_trails.call_deferred()  # (after this frame's bones are posed)
	# The model's front is +z. A direction (x, z) needs a turn of atan2(x, z) about the up axis:
	# right = 90 degrees, left = -90, toward the camera = 0, away from it = 180.
	var facing: Variant = _pose["facing"]
	var direction := Vector2(float(facing), 0.0) if typeof(facing) == TYPE_INT or typeof(facing) == TYPE_FLOAT else Vector2(facing)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	_turn.rotation.y = lerp_angle(_turn.rotation.y, atan2(direction.x, direction.y), minf(1.0, TURN_SPEED * delta))

	var active := _active_clip()
	var is_clip := not active.is_empty()
	if _weapon_node != null:  # ease between the artist's grip (model's own clips) and ours
		var own: bool = is_clip and (not _skill_clip.is_empty() or (active["set"].set_name.begins_with(_anim_model) and _anim_model != ""))
		_weapon_node.quaternion = _weapon_node.quaternion.slerp(_grip_own if own else _grip_ours, minf(1.0, delta * 20.0))
	if is_clip != _was_clip:
		_transition = TRANSITION_SECONDS
	_was_clip = is_clip
	_transition = maxf(0.0, _transition - delta)
	var body := Vector3(-90.0, LIE_LIFT, 0.0) if _pose["lying"] else Vector3.ZERO
	var follow := minf(1.0, BODY_SPEED * delta)
	_lie.rotation_degrees.x = lerpf(_lie.rotation_degrees.x, body.x, follow)
	_lie.position.y = lerpf(_lie.position.y, body.y, follow)
	_lie.position.z = lerpf(_lie.position.z, body.z, follow)

	# Joints follow an authored animation closely, or ease toward a code pose; right after switching
	# between the two they ease for a moment so nothing pops.
	if is_clip:
		_follow = 1.0 - exp(-CLIP_FOLLOW_RATE * delta)
		_apply_clip(active)
		return


## Pose-table degrees (x, y, z) -> a rotation about the model's own axes. Elbows were written with
## X+ = bend forward, which is a rotation about -X for a hanging forearm; arms roll outward with Z+ on
## the right and Z- on the left in the table, which is the opposite sign about the model's Z axis.
func _model_rotation(short_name: String, degrees: Vector3) -> Quaternion:
	var x := degrees.x
	var z := degrees.z
	if short_name.begins_with("forearm"):
		x = -x
	if short_name.begins_with("upper_arm") or short_name.begins_with("forearm"):
		z = -z
	return Quaternion.from_euler(Vector3(x, degrees.y, z) * (PI / 180.0))


## The rest pose is a T-pose: lower the arm to hang by the side (a rotation about the front axis).
func _arm_lowering(is_left: bool) -> Quaternion:
	return Quaternion(Vector3.BACK, deg_to_rad(-ARM_DOWN if is_left else ARM_DOWN))


## Applies a rotation expressed in model space to a bone: converted into the bone's own rest frame
## (the skeleton rests in a T-pose, so its bones' axes are not the model's axes).
func _set_bone(bone_name: String, model_rotation: Quaternion) -> void:
	var global: Quaternion = _global_rest[bone_name]
	var local := global.inverse() * model_rotation * global
	_move_bone_to(bone_name, _rest[bone_name] * local)


## Moves a bone toward a target rotation (all the way when _follow is 1).
func _move_bone_to(bone_name: String, target: Quaternion) -> void:
	var index: int = _bone_index[bone_name]
	var current := _skeleton.get_bone_pose_rotation(index)
	_skeleton.set_bone_pose_rotation(index, target if _follow >= 1.0 else current.slerp(target, _follow))


## Poses every bone from an authored clip sample; bones the clip does not move go back to their rest pose.
func _apply_clip(active: Dictionary) -> void:
	var library: RefCounted = active["set"]
	var sample: Dictionary = library.sample(active["clip"], active["time"])
	for bone_name in _bone_index:
		var values: Dictionary = sample.get(bone_name, {})
		_move_bone_to(bone_name, values.get("rotation", _rest[bone_name]))
	# Positions: the hips, and the weapon sockets (a clip can slide the weapon in the fist, e.g. the
	# idles grip spear and hammer mid-shaft); a clip without a track keeps the rest offset.
	for bone_name in ["Hips", WEAPON_BONE, WEAPON_BONE_LEFT]:
		if _bone_index.has(bone_name):
			var index: int = _bone_index[bone_name]
			var target: Vector3 = sample.get(bone_name, {}).get("position", _rest_position[bone_name])
			_skeleton.set_bone_pose_position(index, _skeleton.get_bone_pose_position(index).lerp(target, _follow))


func _union_bounds() -> AABB:
	var bounds: AABB = _meshes[0].get_aabb()
	for mesh in _meshes:
		if mesh.visible:
			bounds = bounds.merge(mesh.get_aabb())
	return bounds


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _find_meshes(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		_find_meshes(child, found)

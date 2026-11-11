extends RefCounted
## Tests the character model wrapper: the imported .glb loads, fits the game's body, and its
## skeleton can be posed. (Run `godot --headless --path . --import` once after adding or changing a model.)

const CharacterModel := preload("res://client/character_model.gd")

const RIG_BONES: Array[String] = [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "Jaw",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
	"LeftIndexProximal", "LeftThumbProximal", "RightIndexProximal", "RightThumbProximal",
	"attach_weapon.L", "attach_weapon.R", "attach_back", "attach_head",
]


func run(ctx) -> void:
	var missing := CharacterModel.new()
	ctx.root.add_child(missing)
	ctx.check("a missing model file is refused without crashing", not missing.load_model("res://art/characters/nope.glb"))
	missing.queue_free()

	var model := CharacterModel.new()
	ctx.root.add_child(model)
	var loaded: bool = model.load_model()
	ctx.check("the character model loads", loaded)
	if not loaded:
		model.queue_free()
		return

	ctx.check("the rig has the 57 bones of the shared humanoid skeleton (%d)" % model.bone_count(), model.bone_count() == 57)
	var all_bones := true
	for bone_name in RIG_BONES:
		all_bones = all_bones and model.has_bone(bone_name)
	ctx.check("every expected humanoid bone exists", all_bones)
	ctx.check("the model is scaled to the game's body height (%.3f)" % model.model_height(), absf(model.model_height() - 1.8) < 0.01)

	var skeleton: Skeleton3D = model._skeleton
	var arm: int = skeleton.find_bone("RightUpperArm")
	# The skeleton rests in a T-pose, so every pose starts with the arms lowered by about 80 degrees.
	var rest: Quaternion = skeleton.get_bone_rest(arm).basis.get_rotation_quaternion()
	model.set_pose("idle", 0.0, 0.0, true, 1, false)
	for i in 30:
		model.apply_pose(1.0 / 30.0)
	var idle: Quaternion = skeleton.get_bone_pose_rotation(arm)
	ctx.check("idle lowers the arm from the T-pose (%.0f degrees)" % rad_to_deg(idle.angle_to(rest)), absf(rad_to_deg(idle.angle_to(rest)) - 80.0) < 25.0)
	model.set_pose("punch_r", 1.0, 0.0, true, 1, false, "strike")
	for i in 30:
		model.apply_pose(1.0 / 30.0)
	var punch: Quaternion = skeleton.get_bone_pose_rotation(arm)
	ctx.check("a punch moves the right arm well away from its idle pose", punch.angle_to(idle) > deg_to_rad(60.0))
	var left_arm: int = skeleton.find_bone("LeftUpperArm")
	var left_idle: Quaternion = skeleton.get_bone_pose_rotation(left_arm)
	ctx.check("a right punch keeps the left hand up as a guard, moving less than the striking arm", left_idle.angle_to(skeleton.get_bone_rest(left_arm).basis.get_rotation_quaternion()) > deg_to_rad(30.0))
	var index_finger: int = skeleton.find_bone("RightIndexProximal")
	var fist_curl: float = skeleton.get_bone_pose_rotation(index_finger).angle_to(skeleton.get_bone_rest(index_finger).basis.get_rotation_quaternion())
	model.set_pose("idle", 0.0, 0.0, true, 1, false)
	for i in 30:
		model.apply_pose(1.0 / 30.0)
	var relaxed_curl: float = skeleton.get_bone_pose_rotation(index_finger).angle_to(skeleton.get_bone_rest(index_finger).basis.get_rotation_quaternion())
	ctx.check("the fingers close into a fist for a punch (%.0f vs %.0f degrees)" % [rad_to_deg(fist_curl), rad_to_deg(relaxed_curl)], fist_curl > relaxed_curl + deg_to_rad(25.0))

	model.set_pose("idle", 0.0, 0.0, true, -1, false)
	for i in 60:
		model.apply_pose(1.0 / 30.0)
	ctx.check("the model turns to face left (%.2f rad)" % model._turn.rotation.y, absf(angle_difference(model._turn.rotation.y, -PI / 2.0)) < 0.05)
	model.set_pose("down", 0.0, 0.0, true, 1, true)
	for i in 60:
		model.apply_pose(1.0 / 30.0)
	ctx.check("a knocked-down fighter lies on the ground", absf(model._lie.rotation_degrees.x + 90.0) < 1.0)
	model.set_pose("idle", 0.0, 0.0, true, 1, false)
	for i in 60:
		model.apply_pose(1.0 / 30.0)
	ctx.check("and stands up again", absf(model._lie.rotation_degrees.x) < 1.0)

	model.tint(Color(1, 0, 0, 0.3))
	ctx.check("tinting puts an overlay on every part of the model", not model._meshes.is_empty() and model._meshes.all(func(mesh): return mesh.material_overlay != null))
	model.tint(Color(0, 0, 0, 0))
	ctx.check("a transparent tint removes it", model._meshes.all(func(mesh): return mesh.material_overlay == null))
	model.queue_free()

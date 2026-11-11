extends SceneTree
## The goblin family in the real renderer: player, goblin, archer, mage, knight and chief side by side on the
## ink stage and the golden stage, from the game's camera 8 (wide + close crop), each playing the goblin
## clips (art/animations/goblin.glb sampled like client/fighter_view.gd) with the monster ink outline.
## Prints each model's bounds height (what fighter_view fits to monster_model_height). Needs a window:
##   godot --path . --script res://tools/shots/goblin_family_shot.gd -- <out_dir>

const Atmosphere := preload("res://client/atmosphere.gd")
const CharacterModel := preload("res://client/character_model.gd")
const CharacterLight := preload("res://client/character_light.gd")
const InkStyle := preload("res://client/ink_style.gd")
const AnimationSet := preload("res://client/animation_set.gd")

const MONSTERS := [
	["goblin", "res://art/monsters/goblin/goblin.glb", -1.25, 1.0],
	["goblin_archer", "res://art/monsters/goblin_archer/goblin_archer.glb", -0.35, 1.06],
	["goblin_mage", "res://art/monsters/goblin_mage/goblin_mage.glb", 0.55, 1.0],
	["goblin_knight", "res://art/monsters/goblin_knight/goblin_knight.glb", 1.6, 1.28],
	["goblin_chief", "res://art/monsters/goblin_chief/goblin_chief.glb", 3.05, 1.72],
]
const POSES := [["idle", 0.9], ["run", 0.15], ["attack_1", 0.4], ["taunt", 0.5]]

var _out := ""
var _anim: RefCounted


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://goblin_family"
	DirAccess.make_dir_recursive_absolute(_out)
	_anim = AnimationSet.load_file("res://art/animations/goblin.glb")
	await process_frame
	for style in ["ink", "golden"]:
		for pose in POSES:
			await _shot(style, pose[0], pose[1])
	quit()


func _monster(parent: Node, path: String, x: float, scale: float, ink: bool) -> Dictionary:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	parent.add_child(model)
	model.position.x = x
	model.scale = Vector3.ONE * scale  # in the game: fighter_view fits the bounds to the data's model_height
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var bounds := AABB()
	var first := true
	for mesh in meshes:
		var to_model: Transform3D = mesh.transform
		var p := mesh.get_parent()
		while p != model:
			to_model = p.transform * to_model
			p = p.get_parent()
		var box: AABB = to_model * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	CharacterLight.prepare(model)
	if ink:
		for mesh in meshes:
			var outline := MeshInstance3D.new()
			outline.mesh = InkStyle.outline_mesh(mesh.mesh)
			outline.skin = mesh.skin
			mesh.add_child(outline)
			if mesh.skin != null:
				outline.skeleton = outline.get_path_to(mesh.get_node(mesh.skeleton))
			outline.material_override = InkStyle.outline_material(0.02)
			outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for player in model.find_children("*", "AnimationPlayer", true, false):
		player.active = false
	return {"model": model, "height": bounds.size.y, "skeleton": model.find_children("*", "Skeleton3D", true, false)[0]}


func _pose(skeleton: Skeleton3D, clip: String, time: float) -> void:
	skeleton.reset_bone_poses()
	var pose: Dictionary = _anim.sample(clip, time)
	for bone in pose:
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		if pose[bone].has("rotation"):
			skeleton.set_bone_pose_rotation(index, pose[bone]["rotation"])
		if pose[bone].has("position"):
			skeleton.set_bone_pose_position(index, pose[bone]["position"])


func _shot(style: String, clip: String, frac: float) -> void:
	for crop in [false, true]:
		var vp := SubViewport.new()
		vp.size = Vector2i(1600, 900)
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var atmo := Atmosphere.new()
		atmo.style = style
		vp.add_child(atmo)
		var player := CharacterModel.new()
		player.ink_outline = true
		vp.add_child(player)
		player.load_model()
		player.position = Vector3(-2.3, 0, 0)
		var heights := []
		var skeletons := []
		for entry in MONSTERS:
			var m := _monster(vp, entry[1], entry[2], entry[3], true)
			heights.append("%s glb %.3f -> x%.2f = %.3f" % [entry[0], m["height"], entry[3], m["height"] * entry[3]])
			skeletons.append(m["skeleton"])
		var length: float = _anim.length(clip)
		for s in skeletons:
			_pose(s, clip, frac * length)
		var cam := Camera3D.new()
		cam.fov = 55.0 if not crop else 22.0
		vp.add_child(cam)
		var cx := 0.4
		cam.position = Vector3(cx, 7.0, 7.0)
		cam.look_at(Vector3(cx, 0.5, 0.0))
		for i in 24:
			await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(_out.path_join("%s_%s_%s.png" % [style, clip, "close" if crop else "wide"]))
		if style == "ink" and clip == "idle" and not crop:
			print("BOUNDS ", heights)
		vp.queue_free()
		await process_frame
